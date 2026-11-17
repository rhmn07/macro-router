import Foundation
import Observation
import MacroCore

/// Everything a user owns, persisted locally and (when signed in) mirrored to Firestore.
struct UserData: Codable, Equatable {
    var targets: MacroTargets = .example
    var pantry: [Ingredient] = SeedIngredients.all
    var selectedIDs: Set<String> = SeedIngredients.defaultSelection
    var plans: [MealPlan] = []
    /// Answers from onboarding. Optional so data saved before onboarding existed still decodes.
    var profile: BodyProfile?
    /// Set once the user finishes or skips onboarding.
    var onboardingDone: Bool?
}

enum AppTab: Hashable {
    case targets, pantry, plan, history
}

@Observable
@MainActor
final class AppState {
    let auth: AuthService
    let cloudEnabled: Bool
    private let cloud: CloudStore?
    private let local = LocalStore()

    private(set) var data = UserData()
    var currentPlan: MealPlan?
    var selectedTab: AppTab = .targets
    var errorMessage: String?
    var isLoading = false
    /// Chose "Continue without an account" (or Firebase isn't configured).
    var isGuest: Bool

    private var userKey = "guest"
    private var profileSyncTask: Task<Void, Never>?

    init(cloudEnabled: Bool) {
        self.cloudEnabled = cloudEnabled
        self.cloud = cloudEnabled ? CloudStore() : nil
        self.auth = AuthService(isEnabled: cloudEnabled)
        self.isGuest = !cloudEnabled
        if let stored = local.load(key: userKey) { data = stored }
        auth.onUserChange = { [weak self] user in
            Task { await self?.userDidChange(user) }
        }
    }

    var isSignedIn: Bool { auth.user != nil }
    var needsLogin: Bool { cloudEnabled && !isSignedIn && !isGuest }
    /// Show the onboarding questions until they're answered or skipped. Waits for cloud data on sign-in.
    var needsOnboarding: Bool { !needsLogin && !isLoading && data.onboardingDone != true }

    var selectedIngredients: [Ingredient] {
        data.pantry.filter { data.selectedIDs.contains($0.id) }
    }

    // MARK: - Session

    private func userDidChange(_ user: AppUser?) async {
        profileSyncTask?.cancel()
        currentPlan = nil
        guard let user else {
            userKey = "guest"
            data = local.load(key: userKey) ?? UserData()
            return
        }
        isGuest = false
        userKey = user.uid
        data = local.load(key: userKey) ?? UserData()
        guard let cloud else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let remote = try await cloud.fetchUserData(uid: user.uid) {
                data = remote
                local.save(data, key: userKey)
            } else {
                // First sign-in: upload whatever the user set up locally.
                try await cloud.uploadAll(uid: user.uid, data: data)
            }
        } catch {
            errorMessage = "Couldn't sync with the cloud: \(error.localizedDescription)"
        }
    }

    func signOut() {
        do { try auth.signOut() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Targets & selection

    func updateTargets(_ targets: MacroTargets) {
        guard targets != data.targets else { return }
        data.targets = targets
        persist(profileChanged: true)
    }

    /// Saves the onboarding answers and the targets calculated from them.
    func completeOnboarding(profile: BodyProfile, targets: MacroTargets) {
        data.profile = profile
        data.targets = targets
        data.onboardingDone = true
        selectedTab = .targets
        persist(profileChanged: true)
    }

    func skipOnboarding() {
        data.onboardingDone = true
        persist(profileChanged: true)
    }

    func isSelected(_ ingredient: Ingredient) -> Bool {
        data.selectedIDs.contains(ingredient.id)
    }

    func setSelected(_ ingredient: Ingredient, _ selected: Bool) {
        if selected { data.selectedIDs.insert(ingredient.id) } else { data.selectedIDs.remove(ingredient.id) }
        persist(profileChanged: true)
    }

    // MARK: - Pantry

    func contains(_ ingredient: Ingredient) -> Bool {
        data.pantry.contains { $0.id == ingredient.id }
    }

    /// Adds (or replaces) an ingredient and selects it.
    func upsert(_ ingredient: Ingredient, select: Bool = true) {
        if let index = data.pantry.firstIndex(where: { $0.id == ingredient.id }) {
            data.pantry[index] = ingredient
        } else {
            data.pantry.append(ingredient)
        }
        if select { data.selectedIDs.insert(ingredient.id) }
        persist(profileChanged: select)
        cloudWrite { try await $0.saveIngredient(uid: $1, ingredient: ingredient) }
    }

    func remove(_ ingredient: Ingredient) {
        data.pantry.removeAll { $0.id == ingredient.id }
        data.selectedIDs.remove(ingredient.id)
        persist(profileChanged: true)
        cloudWrite { try await $0.deleteIngredient(uid: $1, id: ingredient.id) }
    }

    func restoreStaples() {
        for seed in SeedIngredients.all where !contains(seed) {
            upsert(seed, select: false)
        }
    }

    // MARK: - Plans

    func generatePlan() {
        do {
            currentPlan = try MacroSolver.solve(ingredients: selectedIngredients, targets: data.targets)
            selectedTab = .plan
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isSaved(_ plan: MealPlan) -> Bool {
        data.plans.contains { $0.id == plan.id }
    }

    func save(_ plan: MealPlan) {
        guard !isSaved(plan) else { return }
        data.plans.insert(plan, at: 0)
        persist()
        cloudWrite { try await $0.savePlan(uid: $1, plan: plan) }
    }

    func delete(_ plan: MealPlan) {
        data.plans.removeAll { $0.id == plan.id }
        persist()
        cloudWrite { cloud, _ in try await cloud.deletePlan(id: plan.id) }
    }

    // MARK: - Persistence

    private func persist(profileChanged: Bool = false) {
        local.save(data, key: userKey)
        guard profileChanged, let cloud, let uid = auth.user?.uid else { return }
        // Debounce: typing in the targets form would otherwise write on every keystroke.
        profileSyncTask?.cancel()
        let snapshot = data
        profileSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            do {
                try await cloud.saveProfile(uid: uid, data: snapshot)
            } catch {
                self?.errorMessage = "Couldn't save your profile: \(error.localizedDescription)"
            }
        }
    }

    private func cloudWrite(_ operation: @escaping (CloudStore, String) async throws -> Void) {
        guard let cloud, let uid = auth.user?.uid else { return }
        Task { [weak self] in
            do {
                try await operation(cloud, uid)
            } catch {
                self?.errorMessage = "Couldn't sync: \(error.localizedDescription)"
            }
        }
    }
}
