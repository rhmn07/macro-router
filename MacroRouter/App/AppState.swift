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
    // Added later; optional so older saved data still decodes. Use the AppState accessors.
    var currentWeek: WeekPlan?
    var savedWeeks: [WeekPlan]?
    var settings: PlannerSettings?
    var weights: [WeightEntry]?
    var reminders: ReminderSettings?
    /// Set once old USDA names have been tidied, so already-clean names aren't cleaned twice.
    var foodNamesCleaned: Bool?
}

extension UserData {
    /// USDA foods added before names were tidied ("Beef, ground, 93% lean meat / 7% fat, raw") get
    /// the readable name ("Ground beef 93/7 (raw)"), in the pantry and the current week. Branded
    /// foods ("… (Brand)") and names the user typed are left alone.
    func withCleanFoodNames() -> UserData {
        guard foodNamesCleaned != true else { return self }
        func cleaned(_ ing: Ingredient) -> Ingredient {
            // Raw USDA names start with a one-word food ("Beef, ground, …"). Clean names don't, except
            // lists like "Corn, peanut and olive oil" (raw ones say ", and").
            let first = ing.name.split(separator: ",").first.map(String.init) ?? ""
            let looksRaw = !first.contains(" ") && (!ing.name.contains(" and ") || ing.name.contains(", and "))
            guard ing.source == .usda, ing.name.contains(","), !ing.name.hasSuffix(")"), looksRaw else { return ing }
            var copy = ing
            copy.name = FoodName.clean(ing.name)
            return copy
        }
        func cleaned(_ items: [PlanItem]) -> [PlanItem] {
            items.map { PlanItem(ingredient: cleaned($0.ingredient), grams: $0.grams) }
        }
        var data = self
        data.foodNamesCleaned = true
        data.pantry = pantry.map(cleaned)
        if var week = currentWeek {
            week.days = week.days.map { day in
                var day = day
                day.items = cleaned(day.items)
                day.meals = day.meals?.map { PlannedMeal(slot: $0.slot, items: cleaned($0.items)) }
                return day
            }
            data.currentWeek = week
        }
        return data
    }
}

/// Meal reminder times, in minutes after midnight.
struct ReminderSettings: Codable, Equatable {
    var enabled = false
    var times: [MealSlot: Int] = [.breakfast: 8 * 60, .lunch: 12 * 60 + 30, .snack: 15 * 60 + 30, .dinner: 18 * 60 + 30]

    func minutes(for slot: MealSlot) -> Int { times[slot] ?? 12 * 60 }
}

enum AppTab: Hashable {
    case targets, pantry, plan, progress, history
}

@Observable
@MainActor
final class AppState {
    let auth: AuthService
    let cloudEnabled: Bool
    private let cloud: CloudStore?
    private let local = LocalStore()

    private(set) var data = UserData()
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
        if let stored = local.load(key: userKey) { data = stored.withCleanFoodNames() }
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

    var settings: PlannerSettings { data.settings ?? PlannerSettings() }
    var weights: [WeightEntry] { (data.weights ?? []).sorted { $0.date < $1.date } }
    var reminders: ReminderSettings { data.reminders ?? ReminderSettings() }
    var savedWeeks: [WeekPlan] { data.savedWeeks ?? [] }

    // MARK: - Session

    private func userDidChange(_ user: AppUser?) async {
        profileSyncTask?.cancel()
        guard let user else {
            userKey = "guest"
            data = (local.load(key: userKey) ?? UserData()).withCleanFoodNames()
            return
        }
        isGuest = false
        userKey = user.uid
        data = (local.load(key: userKey) ?? UserData()).withCleanFoodNames()
        guard let cloud else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let remote = try await cloud.fetchUserData(uid: user.uid) {
                data = remote.withCleanFoodNames()
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

    /// Plans the next 7 days, starting today.
    func generatePlan() {
        do {
            data.currentWeek = try WeekPlan.make(ingredients: selectedIngredients, targets: data.targets,
                                                 settings: settings, days: 7)
            persist(profileChanged: true)
            selectedTab = .plan
            Task { await rescheduleReminders() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marks a meal as eaten (or not). Eaten meals stay fixed if the day is re-planned.
    func toggleEaten(day: Int, slot: MealSlot) {
        guard var week = data.currentWeek else { return }
        let key = WeekPlan.key(day: day, slot: slot)
        if week.eaten.contains(key) { week.eaten.remove(key) } else { week.eaten.insert(key) }
        data.currentWeek = week
        persist(profileChanged: true)
    }

    /// Re-plans one day without a food, keeping meals already eaten.
    func swapOut(_ ingredient: Ingredient, day: Int) {
        guard var week = data.currentWeek else { return }
        let without = selectedIngredients.filter { $0.id != ingredient.id }
        do {
            try week.replan(day: day, ingredients: without)
            data.currentWeek = week
            persist(profileChanged: true)
            Task { await rescheduleReminders() }
        } catch {
            errorMessage = "Couldn't re-plan without \(ingredient.shortName.lowercased()): \(error.localizedDescription)"
        }
    }

    func isSaved(_ week: WeekPlan) -> Bool {
        savedWeeks.contains { $0.id == week.id }
    }

    func save(_ week: WeekPlan) {
        guard !isSaved(week) else { return }
        data.savedWeeks = [week] + savedWeeks
        persist()
        cloudWrite { try await $0.saveWeek(uid: $1, week: week) }
    }

    func delete(_ week: WeekPlan) {
        data.savedWeeks = savedWeeks.filter { $0.id != week.id }
        persist()
        cloudWrite { cloud, _ in try await cloud.deletePlan(id: week.id) }
    }

    /// Old single-day plans saved before week plans existed.
    func delete(_ plan: MealPlan) {
        data.plans.removeAll { $0.id == plan.id }
        persist()
        cloudWrite { cloud, _ in try await cloud.deletePlan(id: plan.id) }
    }

    // MARK: - Preferences

    func updateSettings(_ settings: PlannerSettings) {
        guard settings != self.settings else { return }
        data.settings = settings
        persist(profileChanged: true)
    }

    func updateReminders(_ reminders: ReminderSettings) {
        guard reminders != self.reminders else { return }
        data.reminders = reminders
        persist()
        Task { await rescheduleReminders() }
    }

    func rescheduleReminders() async {
        await ReminderService.schedule(week: data.currentWeek, settings: reminders)
    }

    // MARK: - Weight

    func addWeight(_ entry: WeightEntry) {
        data.weights = weights + [entry]
        if var profile = data.profile, entry.date >= (weights.last?.date ?? .distantPast) {
            profile.weightKg = entry.kg
            data.profile = profile
        }
        persist(profileChanged: true)
    }

    func deleteWeight(_ entry: WeightEntry) {
        data.weights = weights.filter { $0.id != entry.id }
        persist(profileChanged: true)
    }

    /// Adds Apple Health weigh-ins that aren't already in the log (same day and weight).
    func importHealthWeights() async {
        do {
            let fromHealth = try await HealthService.weights(days: 90)
            let calendar = Calendar.current
            let new = fromHealth.filter { h in
                !weights.contains { calendar.isDate($0.date, inSameDayAs: h.date) && abs($0.kg - h.kg) < 0.05 }
            }
            guard !new.isEmpty else {
                errorMessage = fromHealth.isEmpty ? "No weight found in Apple Health for the last 90 days." : nil
                return
            }
            data.weights = weights + new
            if var profile = data.profile, let latest = (weights).last {
                profile.weightKg = latest.kg
                data.profile = profile
            }
            persist(profileChanged: true)
        } catch {
            errorMessage = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }

    var checkIn: CalorieCheckIn? {
        CalorieCheckIn.evaluate(entries: weights, goal: data.profile?.goal ?? .maintain)
    }

    func applyCheckIn(_ checkIn: CalorieCheckIn) {
        updateTargets(data.targets.adjusted(byCalories: checkIn.calorieChange))
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
