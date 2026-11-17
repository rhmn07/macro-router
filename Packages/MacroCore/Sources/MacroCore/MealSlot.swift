import Foundation

public enum MealSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, snack, dinner

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .snack: return "Snack"
        case .dinner: return "Dinner"
        }
    }

    public var emoji: String {
        switch self {
        case .breakfast: return "🍳"
        case .lunch: return "🥗"
        case .snack: return "🍎"
        case .dinner: return "🍽️"
        }
    }

    /// Share of the day with the default settings (breakfast, lunch, dinner; no snack).
    public var defaultShare: Double { PlannerSettings().share(of: self) }
}

/// How the day is split between meals.
public enum MealSizes: String, Codable, CaseIterable, Sendable, Identifiable {
    case balanced, bigBreakfast, bigLunch, bigDinner

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .bigBreakfast: return "Bigger breakfast"
        case .bigLunch: return "Bigger lunch"
        case .bigDinner: return "Bigger dinner"
        }
    }

    /// Breakfast, lunch, dinner shares (add up to 1).
    var split: (breakfast: Double, lunch: Double, dinner: Double) {
        switch self {
        case .balanced: return (0.25, 0.35, 0.40)
        case .bigBreakfast: return (0.35, 0.35, 0.30)
        case .bigLunch: return (0.25, 0.45, 0.30)
        case .bigDinner: return (0.20, 0.30, 0.50)
        }
    }

    /// e.g. "25% · 35% · 40%"
    public var summary: String {
        let s = split
        return [s.breakfast, s.lunch, s.dinner].map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: " · ")
    }
}

/// Foods to leave out of plans.
public enum DietRestriction: String, Codable, CaseIterable, Sendable, Identifiable {
    case vegetarian, pescatarian, noPork, noBeef, dairyFree, glutenFree

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .pescatarian: return "Pescatarian"
        case .noPork: return "No pork"
        case .noBeef: return "No beef"
        case .dairyFree: return "Dairy-free"
        case .glutenFree: return "Gluten-free"
        }
    }

    private static let meat = ["chicken", "turkey", "beef", "steak", "pork", "bacon", "ham", "lamb", "sausage",
                               "veal", "bison", "venison", "duck", "jerky", "pepperoni", "salami"]
    private static let fish = ["salmon", "tuna", "cod", "tilapia", "fish", "shrimp", "prawn", "crab", "lobster", "sardine", "anchov"]

    /// True when this food breaks the restriction, judged from its name.
    public func excludes(_ ingredient: Ingredient) -> Bool {
        let name = ingredient.name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { name.contains($0) } }
        switch self {
        case .vegetarian: return has(Self.meat + Self.fish + ["gelatin"])
        case .pescatarian: return has(Self.meat)
        case .noPork: return has(["pork", "bacon", "ham,", "ham ", "sausage", "pepperoni", "salami", "prosciutto"]) || name.hasSuffix("ham")
        case .noBeef: return has(["beef", "steak", "veal", "93/7", "90/10", "85/15"])
        case .dairyFree: return has(["milk", "cheese", "yogurt", "yoghurt", "butter", "cream", "whey", "cottage"]) && !has(["peanut butter", "almond butter", "almond milk", "oat milk", "soy milk", "coconut milk"])
        case .glutenFree: return has(["bread", "pasta", "spaghetti", "macaroni", "penne", "noodle", "bagel", "tortilla", "wrap", "cereal", "toast", "couscous", "barley", "wheat", "muffin", "pita"]) && !has(["corn tortilla", "rice noodle", "gluten-free", "gluten free"])
        }
    }
}

/// The user's plan preferences.
public struct PlannerSettings: Codable, Hashable, Sendable {
    public var includeBreakfast: Bool
    public var includeSnack: Bool
    public var mealSizes: MealSizes
    public var diet: Set<DietRestriction>

    public init(includeBreakfast: Bool = true, includeSnack: Bool = false,
                mealSizes: MealSizes = .balanced, diet: Set<DietRestriction> = []) {
        self.includeBreakfast = includeBreakfast
        self.includeSnack = includeSnack
        self.mealSizes = mealSizes
        self.diet = diet
    }

    /// Meals in the order they're eaten.
    public var slots: [MealSlot] {
        MealSlot.allCases.filter { slot in
            switch slot {
            case .breakfast: return includeBreakfast
            case .snack: return includeSnack
            case .lunch, .dinner: return true
            }
        }
    }

    public static let snackShare = 0.12

    /// Share of the day's targets for a meal. The shares of `slots` add up to 1.
    public func share(of slot: MealSlot) -> Double {
        guard slots.contains(slot) else { return 0 }
        if slot == .snack { return Self.snackShare }
        let split = mealSizes.split
        let raw: Double
        switch slot {
        case .breakfast: raw = split.breakfast
        case .lunch: raw = split.lunch
        case .dinner: raw = split.dinner
        case .snack: raw = 0
        }
        let mainsTotal = (includeBreakfast ? split.breakfast : 0) + split.lunch + split.dinner
        return raw / mainsTotal * (1 - (includeSnack ? Self.snackShare : 0))
    }

    /// True when a food is allowed by the diet restrictions.
    public func allows(_ ingredient: Ingredient) -> Bool {
        !diet.contains { $0.excludes(ingredient) }
    }
}

extension Ingredient {
    /// True for low-calorie vegetables, which go with lunch and dinner but don't count as a "main" food.
    public var isVegetable: Bool {
        nameHas("broccoli", "spinach", "lettuce", "kale", "salad", "carrot", "pepper", "green bean", "asparagus",
                "zucchini", "cauliflower", "tomato", "cucumber", "onion", "mushroom", "cabbage", "brussels", "celery", "eggplant")
    }

    /// Meals this food fits, from the user's choice or guessed from its name.
    public var suitableMeals: Set<MealSlot> {
        if let meals, !meals.isEmpty { return Set(meals) }
        return guessedMeals
    }

    /// The name-based guess, shown as the default in the food editor.
    public var guessedMeals: Set<MealSlot> {
        if isVegetable { return [.lunch, .dinner] }
        // Snack-friendly and fits any main meal.
        if nameHas("nut", "almond", "peanut", "cashew", "walnut", "pistachio", "seed", "cheese") {
            return Set(MealSlot.allCases)
        }
        if nameHas("whey", "protein powder", "protein bar", "jerky") { return [.breakfast, .snack] }
        // Fits any main meal.
        if nameHas("egg", "^oil", "butter", "avocado") { return [.breakfast, .lunch, .dinner] }
        // Breakfast or snack.
        if nameHas("yogurt", "yoghurt", "cottage", "banana", "berr", "fruit", "apple", "orange", "grape", "melon", "rice cake") {
            return [.breakfast, .snack]
        }
        // Breakfast only.
        if nameHas("^oat", "cereal", "granola", "muesli", "milk", "pancake", "waffle", "bagel", "juice") {
            return [.breakfast]
        }
        if nameHas("bread", "toast", "tortilla", "wrap") {
            return [.breakfast, .lunch]
        }
        // Meat, fish, rice, pasta, potatoes, beans, soups.
        return [.lunch, .dinner]
    }

    /// Case-insensitive name match. A leading "^" means the word must start there
    /// ("^oil" matches "olive oil" but not "boiled").
    public func nameHas(_ words: String...) -> Bool {
        let name = self.name.lowercased()
        return words.contains { word in
            guard word.hasPrefix("^") else { return name.contains(word) }
            let w = String(word.dropFirst())
            var search = name.startIndex..<name.endIndex
            while let r = name.range(of: w, range: search) {
                if r.lowerBound == name.startIndex || !name[name.index(before: r.lowerBound)].isLetter { return true }
                search = r.upperBound..<name.endIndex
            }
            return false
        }
    }
}
