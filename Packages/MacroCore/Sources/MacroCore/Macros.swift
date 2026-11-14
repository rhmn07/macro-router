import Foundation

/// The four nutrition values the app works with.
public enum MacroKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case protein, carbs, fat, calories

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .protein: return "Protein"
        case .carbs: return "Carbs"
        case .fat: return "Fat"
        case .calories: return "Calories"
        }
    }

    public var unit: String { self == .calories ? "kcal" : "g" }
}

/// A bundle of macro values: protein/carbs/fat in grams, calories in kcal.
public struct Macros: Codable, Hashable, Sendable {
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var calories: Double

    /// If `calories` is nil it is derived from the Atwater factors (4/4/9).
    public init(protein: Double, carbs: Double, fat: Double, calories: Double? = nil) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.calories = calories ?? Macros.atwaterCalories(protein: protein, carbs: carbs, fat: fat)
    }

    public static let zero = Macros(protein: 0, carbs: 0, fat: 0, calories: 0)

    public static func atwaterCalories(protein: Double, carbs: Double, fat: Double) -> Double {
        4 * protein + 4 * carbs + 9 * fat
    }

    public subscript(kind: MacroKind) -> Double {
        switch kind {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        case .calories: return calories
        }
    }

    public func scaled(by factor: Double) -> Macros {
        Macros(protein: protein * factor, carbs: carbs * factor, fat: fat * factor, calories: calories * factor)
    }

    public static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat,
               calories: lhs.calories + rhs.calories)
    }
}

/// The user's daily goals. Whole numbers, as the PRD specifies.
public struct MacroTargets: Codable, Hashable, Sendable {
    public var calories: Int
    public var protein: Int
    public var carbs: Int
    public var fat: Int

    public init(calories: Int, protein: Int, carbs: Int, fat: Int) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    public static let example = MacroTargets(calories: 2350, protein: 180, carbs: 250, fat: 70)

    public var macros: Macros {
        Macros(protein: Double(protein), carbs: Double(carbs), fat: Double(fat), calories: Double(calories))
    }

    public subscript(kind: MacroKind) -> Int {
        switch kind {
        case .protein: return protein
        case .carbs: return carbs
        case .fat: return fat
        case .calories: return calories
        }
    }

    /// Calories implied by the macro grams (4P + 4C + 9F).
    public var impliedCalories: Int { 4 * protein + 4 * carbs + 9 * fat }

    /// Relative difference between implied and entered calories (0.1 = macros add up to 10% more).
    public var calorieMismatch: Double {
        guard calories > 0 else { return 0 }
        return Double(impliedCalories - calories) / Double(calories)
    }

    /// True when the calorie target and the macro targets agree within `tolerance`.
    public func isConsistent(tolerance: Double = 0.05) -> Bool {
        abs(calorieMismatch) <= tolerance
    }

    public var isValid: Bool {
        calories >= 0 && protein >= 0 && carbs >= 0 && fat >= 0
            && (calories + protein + carbs + fat) > 0
    }
}
