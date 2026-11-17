import Foundation

/// Turns USDA-style names ("Beef, ground, 93% lean meat / 7% fat, raw") into readable ones
/// ("Ground beef 93/7 (raw)").
///
/// USDA lists the main food first, then descriptors, then preparation, all comma-separated.
/// The cleaner keeps the food and up to two descriptors, drops filler ("Grade A", "enriched"),
/// and moves how it's prepared to the end in parentheses. The preparation words matter:
/// the app uses "raw", "dry" and "cooked" to tell you how to weigh food.
public enum FoodName {
    /// Words that describe preparation. Cooking methods all become "cooked".
    private static let states: [String: String] = [
        "raw": "raw", "dry": "dry", "dried": "dried", "uncooked": "raw",
        "cooked": "cooked", "broiled": "cooked", "roasted": "cooked", "grilled": "cooked", "baked": "cooked",
        "boiled": "cooked", "steamed": "cooked", "pan-browned": "cooked", "pan-fried": "cooked",
        "fried": "cooked", "braised": "cooked", "stewed": "cooked", "simmered": "cooked", "oven-roasted": "cooked",
        "canned": "canned", "condensed": "condensed", "frozen": "frozen", "smoked": "smoked",
    ]

    /// Descriptors that add nothing when shopping or cooking.
    private static let filler: Set<String> = [
        "grade a", "large", "medium", "small", "regular", "enriched", "unenriched", "fresh", "boneless",
        "skinless", "meat only", "unspecified fat content", "pasteurized", "all varieties", "nfs", "ns",
        "crumbles", "salad or cooking", "without salt", "with salt", "unsalted", "commercial",
        "drained solids", "ready-to-serve", "ready-to-eat", "plain", "solids and liquids",
    ]

    /// Words that go after the main food rather than before it ("Chicken breast", not "Breast chicken").
    private static let cuts: Set<String> = [
        "breast", "thigh", "thighs", "drumstick", "wing", "wings", "leg", "loin", "tenderloin", "sirloin",
        "fillet", "fillets", "steak", "chop", "chops", "roast", "brisket",
    ]

    /// Generic first words where the second part is the real food ("Fish, salmon" → "salmon").
    private static let groups: Set<String> = ["fish", "nuts", "seeds", "cereals", "cereals ready-to-eat", "beverages"]

    /// Foods sold dry whose USDA "raw" means "dry".
    private static let dryGoods = ["rice", "pasta", "spaghetti", "macaroni", "noodle", "oat", "quinoa",
                                   "lentil", "barley", "couscous", "bulgur", "beans, ", "chickpea"]

    public static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some USDA entries are ALL CAPS.
        if text == text.uppercased() { text = text.lowercased() }
        // Only tidy USDA-style names; leave what the user typed alone.
        guard text.contains(",") else { return text }
        let lowerAll = text.lowercased()

        var parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return text }

        // "93% lean meat / 7% fat" → "93/7"
        var lean: String?
        parts = parts.filter { part in
            if let match = part.range(of: #"(\d+)% lean meat / (\d+)% fat"#, options: .regularExpression) {
                let numbers = part[match].split(whereSeparator: { !$0.isNumber }).map(String.init)
                if numbers.count >= 2 { lean = "\(numbers[0])/\(numbers[1])" }
                return false
            }
            return true
        }

        // Pull out preparation states and filler.
        var found: [String] = []
        var descriptors: [String] = []
        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower.hasPrefix("prepared") {
                if !found.contains("prepared") { found.append("prepared") }
            } else if let state = states[lower] {
                if !found.contains(state) { found.append(state) }
            } else if !filler.contains(lower) && !lower.hasPrefix("ns as to") && !lower.hasPrefix("includes") {
                descriptors.append(part)
            }
        }

        var head = parts[0]
        let headLower = head.lowercased()

        // "Restaurant, Latino, black bean soup" → "Black bean soup (restaurant)"
        if ["restaurant", "fast foods", "fast food"].contains(headLower), let last = descriptors.last {
            return finish(last, lean: nil, states: ["restaurant"] + found)
        }
        // "Fish, salmon, pink" → head "salmon"
        if groups.contains(headLower), !descriptors.isEmpty {
            head = descriptors.removeFirst()
        }
        // "Eggs, Grade A, Large, egg white" → "Egg whites"
        let headWord = String(head.lowercased().prefix(while: { $0.isLetter }).prefix(3))
        if let full = descriptors.first(where: { $0.lowercased().contains(headWord) && $0.contains(" ") }) {
            descriptors.removeAll { $0 == full }
            head = full
            descriptors.removeAll()
        }

        // "Oil, corn, peanut, and olive" → "Corn, peanut and olive oil"
        var name: String
        if descriptors.contains(where: { $0.lowercased().hasPrefix("and ") }) {
            let list = descriptors.map { $0.lowercased().hasPrefix("and ") ? String($0.dropFirst(4)) : $0 }
            name = list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "") + " " + head.lowercased()
            descriptors.removeAll()
        } else {
            // "ground" always sits right before the food.
            if let ground = descriptors.firstIndex(where: { $0.lowercased() == "ground" }), ground != 0 {
                descriptors.insert(descriptors.remove(at: ground), at: 0)
            }
            name = head
            if let first = descriptors.first {
                let isEggPart = head.lowercased().hasPrefix("egg") && ["white", "whites", "yolk"].contains(first.lowercased())
                if cuts.contains(first.lowercased()) || isEggPart {
                    name = "\(head) \(first.lowercased())"
                } else {
                    name = "\(first) \(head.lowercased())"
                }
                descriptors.removeFirst()
            }
            let extra = descriptors.prefix(2).map { $0.lowercased() }
            if !extra.isEmpty { name += ", " + extra.joined(separator: ", ") }
        }
        if name.lowercased().hasSuffix("egg white") { name += "s" }

        // USDA "raw" rice or pasta is sold dry.
        if let i = found.firstIndex(of: "raw"), dryGoods.contains(where: { lowerAll.contains($0) }) {
            found[i] = "dry"
        }
        return finish(name, lean: lean, states: found)
    }

    private static func finish(_ name: String, lean: String?, states: [String]) -> String {
        var result = name
        if let lean { result += " \(lean)" }
        let shown = states.prefix(2)
        if !shown.isEmpty { result += " (\(shown.joined(separator: ", ")))" }
        return result.prefix(1).uppercased() + result.dropFirst()
    }
}
