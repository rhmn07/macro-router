import Foundation

/// A macro the selected foods can't reach, found by a trial plan before the user plans their week.
public struct MacroGap: Hashable, Identifiable, Sendable {
    public var kind: MacroKind
    /// e.g. -0.56 = 56% short, 0.2 = 20% over
    public var relativeError: Double
    /// True when no selected food is a real source of this macro.
    public var noSource: Bool
    /// A food to add that would help, if one is in the pantry or the default staples.
    public var suggestion: Ingredient?

    public var id: MacroKind { kind }
    public var isShort: Bool { relativeError < 0 }

    /// e.g. "Fat will be about 56% short"
    public var headline: String {
        let percent = Int((abs(relativeError) * 100).rounded())
        return "\(kind.displayName) will be about \(percent)% \(isShort ? "short" : "over")"
    }

    /// e.g. "None of your picked foods is a fat source."
    public var detail: String {
        switch (kind, isShort, noSource) {
        case (.protein, true, true): return "None of your picked foods is a protein source."
        case (.carbs, true, true): return "None of your picked foods is a carb source."
        case (.fat, true, true): return "None of your picked foods is a fat source."
        case (.protein, true, false): return "Your protein foods can't cover it without going over on something else."
        case (.carbs, true, false): return "Your carb foods can't cover it without going over on something else."
        case (.fat, true, false): return "Your fat sources are too small a part of your picks."
        case (_, false, _): return "Your picks are heavy in \(kind.displayName.lowercased()). Pick leaner options or set a max in the Pantry."
        default: return ""
        }
    }
}

public enum PantryCheck {
    /// How far off a macro can be before it's worth a warning.
    public static let threshold = 0.10

    /// Staples to suggest for a missing macro, in order of preference.
    static func candidates(for kind: MacroKind) -> [Ingredient] {
        switch kind {
        case .protein: return [SeedIngredients.chickenBreast, SeedIngredients.eggWhites, SeedIngredients.groundBeef]
        case .carbs: return [SeedIngredients.whiteRice]
        case .fat: return [SeedIngredients.oliveOil, SeedIngredients.avocado]
        case .calories: return []
        }
    }

    /// Plans one day with the selected foods and reports macros more than 10% off.
    /// - Parameter pantry: everything in the user's pantry, to suggest foods they already have.
    public static func gaps(selected: [Ingredient], pantry: [Ingredient], targets: MacroTargets,
                            settings: PlannerSettings = PlannerSettings()) -> [MacroGap] {
        let usable = selected.filter(settings.allows)
        guard !usable.isEmpty, targets.isValid,
              let plan = try? MealPlanner.solve(ingredients: usable, targets: targets, settings: settings) else { return [] }

        return plan.results.compactMap { result -> MacroGap? in
            guard result.kind != .calories, let error = result.relativeError, abs(error) > threshold else { return nil }
            let noSource = !usable.contains { MealPlanner.isSource($0, of: result.kind) }
            var suggestion: Ingredient?
            if error < 0 {
                let selectedIDs = Set(usable.map(\.id))
                // Prefer a food already in the pantry that isn't picked, then a default staple.
                suggestion = pantry.first { !selectedIDs.contains($0.id) && settings.allows($0) && MealPlanner.isSource($0, of: result.kind) }
                    ?? candidates(for: result.kind).first { !selectedIDs.contains($0.id) && settings.allows($0) }
            }
            return MacroGap(kind: result.kind, relativeError: error, noSource: noSource, suggestion: suggestion)
        }
    }
}
