import Foundation

/// How a food is sold at the store, e.g. a 1 lb pack of ground beef or a 15 oz can of beans.
public struct PackageSize: Codable, Hashable, Sendable {
    /// Singular unit name: "pack", "can", "dozen", "whole", ...
    public var unit: String
    /// Grams of food in one unit.
    public var grams: Double

    public init(unit: String, grams: Double) {
        self.unit = unit
        self.grams = grams
    }

    /// Units offered in the food editor.
    public static let commonUnits = ["pack", "can", "carton", "bag", "bottle", "jar", "box", "tub", "dozen", "loaf", "head", "block", "canister", "whole"]

    /// "3 packs", "2 dozen", "1 can", "4 whole"
    public func countText(_ count: Int) -> String {
        "\(count) \(count == 1 ? unit : Self.plural(unit))"
    }

    static func plural(_ unit: String) -> String {
        switch unit {
        case "dozen", "whole": return unit
        case "box": return "boxes"
        case "loaf": return "loaves"
        default: return unit.hasSuffix("s") ? unit : unit + "s"
        }
    }

    /// "16 oz pack", "12 eggs", "about 150 g each"
    public var sizeText: String {
        switch unit {
        case "dozen": return "12 per dozen"
        case "whole": return "about \(Int(grams.rounded())) g each"
        default:
            let ounces = grams / 28.3495
            let oz = ounces >= 10 ? "\(Int(ounces.rounded())) oz" : String(format: "%.1f oz", ounces)
            return "\(oz) \(unit)"
        }
    }

    /// Typical US grocery sizes, guessed from the food's name. Nil when there's no good guess.
    public static func guess(for ingredient: Ingredient) -> PackageSize? {
        let rules: [(words: [String], package: PackageSize)] = [
            // Order matters: more specific words first.
            (["egg white"], PackageSize(unit: "carton", grams: 454)),           // 16 oz liquid egg whites
            (["eggplant"], PackageSize(unit: "whole", grams: 450)),
            (["egg"], PackageSize(unit: "dozen", grams: 600)),                  // 12 large eggs, ~50 g each
            (["soup", "condensed"], PackageSize(unit: "can", grams: 305)),       // 10.75 oz
            (["canned", "bean", "chickpea", "lentil"], PackageSize(unit: "can", grams: 425)), // 15 oz
            (["ground beef", "ground turkey", "beef, ground", "turkey, ground", "93/7", "90/10", "85/15"],
             PackageSize(unit: "pack", grams: 454)),                            // 1 lb
            (["chicken", "turkey breast"], PackageSize(unit: "pack", grams: 680)), // 1.5 lb
            (["bacon"], PackageSize(unit: "pack", grams: 340)),
            (["steak", "beef", "pork", "lamb", "salmon", "fish", "cod", "tilapia", "shrimp", "tuna"],
             PackageSize(unit: "pack", grams: 454)),
            (["rice", "quinoa"], PackageSize(unit: "bag", grams: 907)),          // 2 lb
            (["oat"], PackageSize(unit: "canister", grams: 510)),               // 18 oz
            (["pasta", "spaghetti", "macaroni", "penne", "noodle"], PackageSize(unit: "box", grams: 454)),
            (["bread", "toast"], PackageSize(unit: "loaf", grams: 567)),
            (["tortilla", "wrap"], PackageSize(unit: "pack", grams: 450)),
            (["broccoli", "cauliflower"], PackageSize(unit: "head", grams: 400)),
            (["spinach", "kale", "lettuce", "salad"], PackageSize(unit: "bag", grams: 284)),
            (["sweet potato", "potato", "yam"], PackageSize(unit: "whole", grams: 200)),
            (["avocado"], PackageSize(unit: "whole", grams: 150)),
            (["banana"], PackageSize(unit: "whole", grams: 120)),
            (["apple", "orange"], PackageSize(unit: "whole", grams: 180)),
            (["olive oil", " oil", "oil,"], PackageSize(unit: "bottle", grams: 460)),                 // ~500 ml
            (["milk"], PackageSize(unit: "carton", grams: 1890)),               // half gallon
            (["yogurt", "yoghurt", "cottage"], PackageSize(unit: "tub", grams: 907)),
            (["whey", "protein powder"], PackageSize(unit: "tub", grams: 907)),
            (["peanut butter", "almond butter"], PackageSize(unit: "jar", grams: 454)),
            (["butter"], PackageSize(unit: "pack", grams: 454)),
            (["cheese"], PackageSize(unit: "block", grams: 227)),
            (["almond", "peanut", "cashew", "walnut", "nut"], PackageSize(unit: "bag", grams: 454)),
            (["berr"], PackageSize(unit: "pack", grams: 340)),
        ]
        let name = ingredient.name.lowercased()
        return rules.first { rule in rule.words.contains { name.contains($0) } }?.package
    }
}

extension Ingredient {
    /// The user's package size, or a guess from the name.
    public var packageSize: PackageSize? { package ?? PackageSize.guess(for: self) }
}
