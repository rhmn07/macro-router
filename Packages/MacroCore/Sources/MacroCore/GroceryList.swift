import Foundation

public struct GroceryItem: Hashable, Identifiable, Sendable {
    public var name: String
    public var grams: Double
    public var id: String { name }

    public var formattedWeight: String { GroceryList.formatWeight(grams: grams) }
}

public enum GroceryList {
    /// Daily recipe × `days`, heaviest first (PRD: 5-day list).
    public static func items(for plan: MealPlan, days: Int = 5) -> [GroceryItem] {
        plan.recipe.map { GroceryItem(name: $0.ingredient.name, grams: $0.grams * Double(max(days, 0))) }
    }

    /// "250 g" below a kilogram, "1.25 kg" at or above one.
    public static func formatWeight(grams: Double) -> String {
        if grams >= 1000 {
            return "\(trimmed(grams / 1000, maxFractionDigits: 2)) kg"
        }
        return "\(trimmed(grams, maxFractionDigits: 0)) g"
    }

    public static func shareText(for plan: MealPlan, days: Int = 5) -> String {
        var lines = ["Macro Router — \(days)-day grocery list", ""]
        lines += items(for: plan, days: days).map { "• \($0.formattedWeight) \($0.name)" }
        lines += ["", "Daily recipe:"]
        lines += plan.recipe.map { "• \(formatWeight(grams: $0.grams)) \($0.ingredient.name)" }
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
