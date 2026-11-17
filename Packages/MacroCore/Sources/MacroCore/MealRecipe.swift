import Foundation

extension Ingredient {
    /// Readable name for meal titles: "Beef, ground, 93% lean meat…" → "Ground beef",
    /// "Soup, black bean, canned" → "Black bean soup", "Chicken Breast (raw)" → "Chicken breast".
    public var shortName: String {
        if nameHas("egg white") { return "Egg whites" }
        var text = name
        if let paren = text.firstIndex(of: "(") { text = String(text[..<paren]) }
        text = text.replacingOccurrences(of: #"\s*\d+/\d+"#, with: "", options: .regularExpression)
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = parts.first else { return name }
        // "Greek yogurt, nonfat" → "Greek yogurt"; "Corn, peanut and olive oil" stays whole.
        var result = first.split(separator: " ").count >= 2 ? first : parts.joined(separator: ", ")
        result = result.lowercased()
        return result.prefix(1).uppercased() + result.dropFirst()
    }
}

/// A name and simple cooking steps for a planned meal, built from its foods.
public enum MealRecipe {
    private static func mains(_ meal: PlannedMeal) -> (protein: PlanItem?, carb: PlanItem?, veg: PlanItem?, fat: PlanItem?) {
        let items = meal.items
        let protein = items.first { $0.ingredient.category == .protein }
        let carb = items.first { $0.ingredient.category == .carb && !$0.ingredient.isVegetable }
        let veg = items.first { $0.ingredient.isVegetable }
        let fat = items.first { $0.ingredient.category == .fat }
        return (protein, carb, veg, fat)
    }

    /// e.g. "Chicken breast & rice bowl", "Egg whites on toast", "Greek yogurt & banana".
    public static func name(for meal: PlannedMeal) -> String {
        let m = mains(meal)
        let p = m.protein.map { $0.ingredient.shortName }
        let c = m.carb.map { $0.ingredient.shortName.lowercased() }
        let v = m.veg.map { $0.ingredient.shortName.lowercased() }
        let isBread = m.carb?.ingredient.nameHas("bread", "toast", "bagel") ?? false
        let isWrap = m.carb?.ingredient.nameHas("tortilla", "wrap", "pita") ?? false

        if meal.slot == .snack {
            let names = meal.items.prefix(2).map { $0.ingredient.shortName }
            return names.isEmpty ? "Snack" : ListFormatter.localizedString(byJoining: names).replacingOccurrences(of: " and ", with: " & ")
        }
        switch (p, c, v) {
        case let (p?, _, _) where isBread: return "\(p) on toast"
        case let (p?, _, _) where isWrap: return "\(p) wrap"
        case let (p?, c?, v?): return "\(p) & \(c) bowl with \(v)"
        case let (p?, c?, nil): return "\(p) & \(c) bowl"
        case let (p?, nil, v?): return "\(p) with \(v)"
        case let (p?, nil, nil): return meal.slot == .breakfast ? "\(p) scramble" : "\(p) plate"
        case let (nil, c?, v?): return "\(c.prefix(1).uppercased() + c.dropFirst()) with \(v)"
        case let (nil, c?, nil): return c.prefix(1).uppercased() + c.dropFirst()
        default:
            return meal.items.first.map { $0.ingredient.shortName } ?? meal.slot.displayName
        }
    }

    /// Short cooking steps, one per food, with oil folded into the first cooking step.
    public static func steps(for meal: PlannedMeal) -> [String] {
        var steps: [String] = []
        let oil = meal.items.first { $0.ingredient.nameHas("^oil", "butter") }
        var oilUsed = false
        func oilPhrase() -> String {
            guard let oil, !oilUsed else { return "" }
            oilUsed = true
            return " in \(GroceryList.formatWeight(grams: oil.grams)) \(oil.ingredient.shortName.lowercased())"
        }
        func amount(_ item: PlanItem) -> String { item.pieceText ?? GroceryList.formatWeight(grams: item.grams) }

        for item in meal.items where item.id != oil?.id {
            let ing = item.ingredient
            let name = ing.shortName.lowercased()
            let cooked = item.approximateCookedGrams.map { " (about \(GroceryList.formatWeight(grams: $0)) cooked)" } ?? ""
            switch ing.weighingState {
            case .dry:
                if ing.nameHas("^oat") {
                    steps.append("Cook \(amount(item)) \(name) with water or milk.")
                } else {
                    steps.append("Boil \(amount(item)) dry \(name)\(cooked).")
                }
            case .raw where ing.category == .protein && !ing.nameHas("egg"):
                steps.append("Cook \(amount(item)) raw \(name)\(oilPhrase()) until done\(cooked).")
            case .cooked where ing.category == .protein:
                steps.append("Warm \(amount(item)) cooked \(name)\(oilPhrase()).")
            default:
                if ing.nameHas("egg") {
                    steps.append("Scramble \(amount(item)) \(name)\(oilPhrase()).")
                } else if ing.isVegetable {
                    steps.append("Steam or roast \(amount(item)) \(name).")
                } else if ing.nameHas("bread", "toast", "bagel") {
                    steps.append("Toast \(amount(item)) of \(name).")
                } else if ing.nameHas("soup") {
                    steps.append("Heat \(amount(item)) \(name).")
                } else {
                    steps.append("Add \(amount(item)) \(name).")
                }
            }
        }
        if let oil, !oilUsed {
            steps.append("Drizzle \(GroceryList.formatWeight(grams: oil.grams)) \(oil.ingredient.shortName.lowercased()) on top.")
        }
        return steps
    }
}
