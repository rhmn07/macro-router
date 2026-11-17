import Foundation

/// Foods eaten in whole pieces (a slice of bread, an egg, a tortilla). The planner gives these in
/// whole pieces and never more than a normal amount per meal.
public struct PieceSize: Hashable, Sendable {
    /// Singular name of one piece: "slice", "egg", "tortilla".
    public var unit: String
    /// Grams in one piece.
    public var grams: Double
    /// Most pieces in one meal.
    public var maxPerMeal: Int

    public init(unit: String, grams: Double, maxPerMeal: Int) {
        self.unit = unit
        self.grams = grams
        self.maxPerMeal = maxPerMeal
    }

    /// "1 slice", "3 slices", "2 eggs"
    public func countText(_ count: Int) -> String {
        "\(count) \(count == 1 ? unit : unit + "s")"
    }

    /// Typical piece sizes, guessed from the food's name. Nil for foods weighed by the gram.
    public static func guess(for ingredient: Ingredient) -> PieceSize? {
        let name = ingredient.name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        if has("crumb", "flour") { return nil }
        if has("bagel") { return PieceSize(unit: "bagel", grams: 100, maxPerMeal: 1) }
        if has("english muffin") { return PieceSize(unit: "muffin", grams: 57, maxPerMeal: 2) }
        if has("tortilla", "wrap") { return PieceSize(unit: "tortilla", grams: 45, maxPerMeal: 3) }
        if has("pita") { return PieceSize(unit: "pita", grams: 60, maxPerMeal: 2) }
        if has("bread", "toast") { return PieceSize(unit: "slice", grams: 32, maxPerMeal: 4) }
        // Whole eggs only: egg whites are weighed or poured.
        if has("egg") && !has("white", "eggplant") { return PieceSize(unit: "egg", grams: 50, maxPerMeal: 4) }
        if has("banana") { return PieceSize(unit: "banana", grams: 120, maxPerMeal: 2) }
        if has("apple") && !has("sauce", "juice") { return PieceSize(unit: "apple", grams: 180, maxPerMeal: 1) }
        if has("orange") && !has("juice") { return PieceSize(unit: "orange", grams: 130, maxPerMeal: 2) }
        return nil
    }
}

extension Ingredient {
    public var pieceSize: PieceSize? { PieceSize.guess(for: self) }
}

extension PlanItem {
    /// Whole pieces in this portion ("3 slices"), for foods eaten in pieces.
    public var pieceText: String? {
        guard let piece = ingredient.pieceSize, piece.grams > 0 else { return nil }
        return piece.countText(max(Int((grams / piece.grams).rounded()), 1))
    }
}
