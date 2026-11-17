import Foundation
import FirebaseFirestore
import MacroCore

/// Firestore persistence, following the PRD schema:
///
///   users/{uid}                    target_calories, target_protein, target_carbs, target_fats, selected_ingredient_ids,
///                                  onboarding_done, body_profile {sex, age, height_cm, weight_kg, activity, goal, uses_metric}
///   users/{uid}/pantry/{id}        name, source, macros_per_100g {protein, carbs, fat, calories}, min_grams, max_grams
///   generated_plans/{plan_id}      plan_id, uid, daily_weights, achieved_macros, created_at, plan_json
final class CloudStore {
    private let db = Firestore.firestore()

    private func userDoc(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private var plans: CollectionReference { db.collection("generated_plans") }

    // MARK: Read

    /// Returns nil when this user has never synced before.
    func fetchUserData(uid: String) async throws -> UserData? {
        let snapshot = try await userDoc(uid).getDocument()
        guard snapshot.exists, let fields = snapshot.data() else { return nil }

        var data = UserData()
        data.targets = MacroTargets(
            calories: Self.int(fields["target_calories"]) ?? data.targets.calories,
            protein: Self.int(fields["target_protein"]) ?? data.targets.protein,
            carbs: Self.int(fields["target_carbs"]) ?? data.targets.carbs,
            fat: Self.int(fields["target_fats"]) ?? data.targets.fat)
        if let ids = fields["selected_ingredient_ids"] as? [String] {
            data.selectedIDs = Set(ids)
        }
        data.onboardingDone = fields["onboarding_done"] as? Bool
        data.profile = (fields["body_profile"] as? [String: Any]).flatMap(Self.profile)

        let pantry = try await userDoc(uid).collection("pantry").getDocuments()
        let ingredients = pantry.documents.compactMap { Self.ingredient(id: $0.documentID, fields: $0.data()) }
        if !ingredients.isEmpty {
            data.pantry = ingredients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        let planDocs = try await plans.whereField("uid", isEqualTo: uid).getDocuments()
        let decoder = JSONDecoder()
        data.plans = planDocs.documents
            .compactMap { doc -> MealPlan? in
                guard let json = doc.data()["plan_json"] as? String else { return nil }
                return try? decoder.decode(MealPlan.self, from: Data(json.utf8))
            }
            .sorted { $0.createdAt > $1.createdAt }
        return data
    }

    // MARK: Write

    func uploadAll(uid: String, data: UserData) async throws {
        try await saveProfile(uid: uid, data: data)
        for ingredient in data.pantry { try await saveIngredient(uid: uid, ingredient: ingredient) }
        for plan in data.plans { try await savePlan(uid: uid, plan: plan) }
    }

    func saveProfile(uid: String, data: UserData) async throws {
        let targets = data.targets
        var fields: [String: Any] = [
            "uid": uid,
            "target_calories": targets.calories,
            "target_protein": targets.protein,
            "target_carbs": targets.carbs,
            "target_fats": targets.fat,
            "selected_ingredient_ids": Array(data.selectedIDs).sorted(),
            "updated_at": FieldValue.serverTimestamp(),
        ]
        if let done = data.onboardingDone { fields["onboarding_done"] = done }
        if let profile = data.profile {
            fields["body_profile"] = [
                "sex": profile.sex.rawValue,
                "age": profile.age,
                "height_cm": profile.heightCm,
                "weight_kg": profile.weightKg,
                "activity": profile.activity.rawValue,
                "goal": profile.goal.rawValue,
                "uses_metric": profile.usesMetric,
            ] as [String: Any]
        }
        try await userDoc(uid).setData(fields, merge: true)
    }

    func saveIngredient(uid: String, ingredient: Ingredient) async throws {
        var fields: [String: Any] = [
            "id": ingredient.id,
            "name": ingredient.name,
            "source": ingredient.source.rawValue,
            "macros_per_100g": [
                "protein": ingredient.macrosPer100g.protein,
                "carbs": ingredient.macrosPer100g.carbs,
                "fat": ingredient.macrosPer100g.fat,
                "calories": ingredient.macrosPer100g.calories,
            ],
        ]
        fields["min_grams"] = ingredient.minGrams.map { $0 as Any } ?? NSNull()
        fields["max_grams"] = ingredient.maxGrams.map { $0 as Any } ?? NSNull()
        try await userDoc(uid).collection("pantry").document(ingredient.id).setData(fields)
    }

    func deleteIngredient(uid: String, id: String) async throws {
        try await userDoc(uid).collection("pantry").document(id).delete()
    }

    func savePlan(uid: String, plan: MealPlan) async throws {
        let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        let achieved = plan.achieved
        try await plans.document(plan.id).setData([
            "plan_id": plan.id,
            "uid": uid,
            "daily_weights": plan.dailyWeights,
            "achieved_macros": [
                "protein": achieved.protein,
                "carbs": achieved.carbs,
                "fat": achieved.fat,
                "calories": achieved.calories,
            ],
            "created_at": Timestamp(date: plan.createdAt),
            "plan_json": json,
        ])
    }

    func deletePlan(id: String) async throws {
        try await plans.document(id).delete()
    }

    // MARK: Mapping helpers

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func profile(_ fields: [String: Any]) -> BodyProfile? {
        guard let sex = (fields["sex"] as? String).flatMap(BiologicalSex.init(rawValue:)),
              let age = int(fields["age"]),
              let height = double(fields["height_cm"]),
              let weight = double(fields["weight_kg"]),
              let activity = (fields["activity"] as? String).flatMap(ActivityLevel.init(rawValue:)),
              let goal = (fields["goal"] as? String).flatMap(WeightGoal.init(rawValue:)) else { return nil }
        return BodyProfile(sex: sex, age: age, heightCm: height, weightKg: weight, activity: activity, goal: goal,
                           usesMetric: fields["uses_metric"] as? Bool ?? true)
    }

    private static func ingredient(id: String, fields: [String: Any]) -> Ingredient? {
        guard let name = fields["name"] as? String,
              let macros = fields["macros_per_100g"] as? [String: Any] else { return nil }
        let source = (fields["source"] as? String).flatMap(IngredientSource.init(rawValue:)) ?? .custom
        return Ingredient(
            id: id,
            name: name,
            source: source,
            macrosPer100g: Macros(protein: double(macros["protein"]) ?? 0,
                                  carbs: double(macros["carbs"]) ?? 0,
                                  fat: double(macros["fat"]) ?? 0,
                                  calories: double(macros["calories"])),
            minGrams: double(fields["min_grams"]),
            maxGrams: double(fields["max_grams"]))
    }
}
