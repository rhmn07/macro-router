import Foundation

public enum IngredientSource: String, Codable, Sendable {
    case seed, usda, custom
}

/// Which macro supplies most of an ingredient's calories. Used for grouping and suggestions.
public enum IngredientCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case protein, carb, fat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .protein: return "Proteins"
        case .carb: return "Carbs"
        case .fat: return "Fats & Oils"
        }
    }
}

public struct Ingredient: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var source: IngredientSource
    public var macrosPer100g: Macros
    /// Optional portion limits for the daily recipe, in grams.
    public var minGrams: Double?
    public var maxGrams: Double?

    public init(id: String = UUID().uuidString,
                name: String,
                source: IngredientSource,
                macrosPer100g: Macros,
                minGrams: Double? = nil,
                maxGrams: Double? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.macrosPer100g = macrosPer100g
        self.minGrams = minGrams
        self.maxGrams = maxGrams
    }

    /// The macro with the most grams, matching how people read a nutrition label.
    /// (Comparing calories instead would put salmon, whole eggs and most meat under fat,
    /// because fat has 9 kcal/g against 4 for protein.)
    public var category: IngredientCategory {
        let m = macrosPer100g
        let p = m.protein, c = m.carbs, f = m.fat
        if p >= c && p >= f { return .protein }
        if c >= f { return .carb }
        return .fat
    }

    public func macros(forGrams grams: Double) -> Macros {
        macrosPer100g.scaled(by: grams / 100)
    }
}

/// The pre-seeded staples from the PRD. Values are per 100 g as purchased (raw/dry),
/// so the grocery list shows real shopping weights. Source: USDA FoodData Central (SR Legacy).
public enum SeedIngredients {
    public static let chickenBreast = Ingredient(
        id: "seed-chicken-breast", name: "Chicken Breast (raw)", source: .seed,
        macrosPer100g: Macros(protein: 22.5, carbs: 0, fat: 2.6, calories: 120))
    public static let groundBeef = Ingredient(
        id: "seed-ground-beef-93", name: "93/7 Ground Beef (raw)", source: .seed,
        macrosPer100g: Macros(protein: 18.7, carbs: 0, fat: 7.0, calories: 152))
    public static let eggWhites = Ingredient(
        id: "seed-egg-whites", name: "Egg Whites", source: .seed,
        macrosPer100g: Macros(protein: 10.9, carbs: 0.7, fat: 0.2, calories: 52))
    public static let whiteRice = Ingredient(
        id: "seed-white-rice", name: "White Rice (dry)", source: .seed,
        macrosPer100g: Macros(protein: 7.1, carbs: 80.0, fat: 0.7, calories: 365))
    public static let broccoli = Ingredient(
        id: "seed-broccoli", name: "Broccoli", source: .seed,
        macrosPer100g: Macros(protein: 2.8, carbs: 6.6, fat: 0.4, calories: 34))
    public static let oliveOil = Ingredient(
        id: "seed-olive-oil", name: "Olive Oil", source: .seed,
        macrosPer100g: Macros(protein: 0, carbs: 0, fat: 100, calories: 884))
    public static let avocado = Ingredient(
        id: "seed-avocado", name: "Avocado", source: .seed,
        macrosPer100g: Macros(protein: 2.0, carbs: 8.5, fat: 14.7, calories: 160))

    public static let all: [Ingredient] = [
        chickenBreast, groundBeef, eggWhites, whiteRice, broccoli, oliveOil, avocado,
    ]

    public static let defaultSelection: Set<String> = [
        chickenBreast.id, whiteRice.id, broccoli.id, oliveOil.id,
    ]
}
