import Foundation

public struct PlanItem: Codable, Hashable, Identifiable, Sendable {
    public var ingredient: Ingredient
    /// Daily grams.
    public var grams: Double

    public var id: String { ingredient.id }

    public init(ingredient: Ingredient, grams: Double) {
        self.ingredient = ingredient
        self.grams = grams
    }

    public var macros: Macros { ingredient.macros(forGrams: grams) }
}

public struct MacroResult: Hashable, Identifiable, Sendable {
    public var kind: MacroKind
    public var target: Double
    public var achieved: Double
    public var margin: Double

    public var id: MacroKind { kind }

    public var difference: Double { achieved - target }

    /// Relative error (0.03 = 3% over). Nil when the target is 0.
    public var relativeError: Double? {
        target > 0 ? difference / target : nil
    }

    public var isWithinMargin: Bool {
        if let error = relativeError { return abs(error) <= margin + 1e-9 }
        return achieved < 1
    }
}

public struct MealPlan: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var targets: MacroTargets
    /// Every selected ingredient, including ones the solver set to 0 g.
    public var items: [PlanItem]
    public var marginOfError: Double

    public init(id: String = UUID().uuidString,
                createdAt: Date = Date(),
                targets: MacroTargets,
                items: [PlanItem],
                marginOfError: Double = 0.05) {
        self.id = id
        self.createdAt = createdAt
        self.targets = targets
        self.items = items
        self.marginOfError = marginOfError
    }

    /// Ingredients that actually appear in the recipe, heaviest first.
    public var recipe: [PlanItem] {
        items.filter { $0.grams > 0 }.sorted { $0.grams > $1.grams }
    }

    /// Selected ingredients the optimizer chose not to use.
    public var unusedIngredients: [Ingredient] {
        items.filter { $0.grams <= 0 }.map(\.ingredient)
    }

    public var achieved: Macros {
        items.reduce(.zero) { $0 + $1.macros }
    }

    public var tracksCalories: Bool { targets.calories > 0 }

    public var results: [MacroResult] {
        let kinds: [MacroKind] = tracksCalories ? MacroKind.allCases : [.protein, .carbs, .fat]
        return kinds.map {
            MacroResult(kind: $0, target: Double(targets[$0]), achieved: achieved[$0], margin: marginOfError)
        }
    }

    public var isWithinMargin: Bool { results.allSatisfy(\.isWithinMargin) }

    /// Daily weights keyed by ingredient name, as stored in Firestore (`daily_weights`).
    public var dailyWeights: [String: Double] {
        Dictionary(recipe.map { ($0.ingredient.name, $0.grams) }, uniquingKeysWith: +)
    }

    /// Plain-language hints for macros that miss the margin.
    public var suggestions: [String] {
        var hints: [String] = []
        if tracksCalories && !targets.isConsistent(tolerance: marginOfError) {
            hints.append("Your macros add up to \(targets.impliedCalories) kcal but your calorie target is \(targets.calories) kcal. No combination of foods can hit both, so consider adjusting one of them.")
        }
        for result in results where !result.isWithinMargin && result.kind != .calories {
            let amount = Int(abs(result.difference).rounded())
            let under = result.difference < 0
            switch (result.kind, under) {
            case (.protein, true):
                hints.append("Protein is \(amount) g short. Add a lean protein (e.g. chicken breast, egg whites, white fish, whey).")
            case (.protein, false):
                hints.append("Protein is \(amount) g over. Set a max on a protein food or swap in a less protein-dense one.")
            case (.carbs, true):
                hints.append("Carbs are \(amount) g short. Add a carb source (e.g. rice, oats, potatoes, fruit).")
            case (.carbs, false):
                hints.append("Carbs are \(amount) g over. Set a max on carb-heavy foods or swap to lower-carb vegetables.")
            case (.fat, true):
                hints.append("Fat is \(amount) g short. Add a fat source (e.g. olive oil, avocado, nuts).")
            case (.fat, false):
                hints.append("Fat is \(amount) g over. Swap a fatty food for a leaner one (e.g. 93/7 → 99% lean, whole eggs → egg whites).")
            default:
                break
            }
        }
        return hints
    }
}
