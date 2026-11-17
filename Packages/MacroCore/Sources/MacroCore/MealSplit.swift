import Foundation

/// How a food's weight should be measured, read from its name ("White Rice (dry)", "Chicken Breast (raw)").
public enum WeighingState: String, Sendable {
    case raw, dry, cooked, unspecified

    /// Short instruction shown next to a portion.
    public var instruction: String? {
        switch self {
        case .raw: return "weigh raw"
        case .dry: return "weigh dry"
        case .cooked: return "weigh cooked"
        case .unspecified: return nil
        }
    }
}

extension Ingredient {
    public var weighingState: WeighingState {
        let name = self.name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        if has("cooked", "boiled", "baked", "roasted", "grilled", "steamed", "pan-browned", "fried") { return .cooked }
        if has("(dry)", " dry", "dry ", "uncooked") { return .dry }
        if has("raw") { return .raw }
        return .unspecified
    }

    /// Rough cooked weight per gram as weighed, for foods whose weight changes a lot when cooked.
    /// Nil when unknown or not needed. Values are typical yields (water absorbed or lost).
    public var cookedWeightFactor: Double? {
        let name = self.name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        switch weighingState {
        case .dry:
            if has("rice") { return 3.0 }
            if has("pasta", "spaghetti", "macaroni", "noodle", "penne") { return 2.3 }
            if has("quinoa") { return 2.7 }
            if has("lentil") { return 2.5 }
            if has("bean", "chickpea") { return 2.4 }
            return nil
        case .raw:
            if has("chicken", "turkey", "beef", "pork", "steak", "lamb") { return 0.75 }
            if has("salmon", "fish", "cod", "tilapia", "tuna", "shrimp") { return 0.8 }
            return nil
        case .cooked, .unspecified:
            return nil
        }
    }
}

public enum MealSplit {
    /// 1 g steps for small amounts (oils, nuts), 5 g steps otherwise, so portions are easy to measure.
    public static func roundPortion(_ grams: Double) -> Double {
        let step: Double = grams < 50 ? 1 : 5
        return max((grams / step).rounded() * step, grams > 0 ? 1 : 0)
    }
}

extension PlanItem {
    /// Approximate cooked weight, when the food changes weight a lot when cooked.
    public var approximateCookedGrams: Double? {
        ingredient.cookedWeightFactor.map { MealSplit.roundPortion(grams * $0) }
    }
}
