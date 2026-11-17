import Foundation

public struct GroceryItem: Hashable, Identifiable, Sendable {
    public var ingredient: Ingredient
    /// Total grams needed for the whole shopping period.
    public var grams: Double
    public var id: String { ingredient.id }
    public var name: String { ingredient.name }

    public var formattedWeight: String { GroceryList.formatWeight(grams: grams) }

    /// How the food is sold, if known.
    public var package: PackageSize? { ingredient.packageSize }

    /// Packages to buy: always rounded up, but a 3% overshoot (e.g. 1.03 packs) doesn't cost a whole extra pack.
    public var packageCount: Int? {
        guard let package, package.grams > 0, grams > 0 else { return nil }
        return max(Int((grams / package.grams - 0.03).rounded(.up)), 1)
    }

    /// "3 packs", or the weight when the package size is unknown.
    public var quantityText: String {
        guard let package, let count = packageCount else { return formattedWeight }
        return package.countText(count)
    }
}

public enum GroceryList {
    /// Daily totals × `days`, heaviest first.
    public static func items(for plan: MealPlan, days: Int = 5) -> [GroceryItem] {
        plan.recipe.map { GroceryItem(ingredient: $0.ingredient, grams: $0.grams * Double(max(days, 0))) }
    }

    /// "250 g" below a kilogram, "1.25 kg" at or above one.
    public static func formatWeight(grams: Double) -> String {
        if grams >= 1000 {
            return "\(trimmed(grams / 1000, maxFractionDigits: 2)) kg"
        }
        return "\(trimmed(grams, maxFractionDigits: 0)) g"
    }

    public static func shareText(for plan: MealPlan, days: Int = 5) -> String {
        var lines = ["Macro Router — grocery list for \(days) \(days == 1 ? "day" : "days")", ""]
        lines += items(for: plan, days: days).map { item in
            if let package = item.package, item.packageCount != nil {
                return "• \(item.quantityText) \(item.name) (\(package.sizeText))"
            }
            return "• \(item.quantityText) \(item.name)"
        }
        for meal in plan.meals ?? [] where !meal.items.isEmpty {
            lines += ["", "\(meal.slot.displayName):"]
            lines += meal.items.map { item in
                if let pieces = item.pieceText { return "• \(pieces) \(item.ingredient.name) (\(formatWeight(grams: item.grams)))" }
                return "• \(formatWeight(grams: item.grams)) \(item.ingredient.name)"
            }
        }
        if plan.meals == nil {
            lines += ["", "Daily recipe:"]
            lines += plan.recipe.map { "• \(formatWeight(grams: $0.grams)) \($0.ingredient.name)" }
        }
        let a = plan.achieved
        lines += ["", "Per day: \(Int(a.calories.rounded())) kcal · P \(Int(a.protein.rounded())) g · C \(Int(a.carbs.rounded())) g · F \(Int(a.fat.rounded())) g"]
        return lines.joined(separator: "\n")
    }

    static func trimmed(_ value: Double, maxFractionDigits: Int) -> String {
        let factor = pow(10.0, Double(maxFractionDigits))
        let rounded = (value * factor).rounded() / factor
        var text = String(format: "%.\(maxFractionDigits)f", rounded)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
