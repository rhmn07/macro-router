import Foundation

public enum BiologicalSex: String, Codable, CaseIterable, Sendable, Identifiable {
    case male, female

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    public var id: String { rawValue }

    /// Multiplier applied to resting energy (BMR) to get daily energy use.
    public var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }

    public var displayName: String {
        switch self {
        case .sedentary: return "Mostly sitting"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Very active"
        case .veryActive: return "Athlete"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary: return "Desk job, little or no exercise"
        case .light: return "Exercise 1–3 days a week"
        case .moderate: return "Exercise 3–5 days a week"
        case .active: return "Hard exercise 6–7 days a week"
        case .veryActive: return "Physical job or training twice a day"
        }
    }
}

public enum WeightGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case lose, maintain, gain

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lose: return "Lose weight"
        case .maintain: return "Maintain weight"
        case .gain: return "Gain weight"
        }
    }

    public var detail: String {
        switch self {
        case .lose: return "About 20% under maintenance calories"
        case .maintain: return "Eat at maintenance calories"
        case .gain: return "About 10% over maintenance for lean gains"
        }
    }

    /// Fraction of maintenance calories to eat.
    public var calorieFactor: Double {
        switch self {
        case .lose: return 0.8
        case .maintain: return 1.0
        case .gain: return 1.1
        }
    }

    /// Grams of protein per kg of body weight. Higher when cutting to protect muscle.
    public var proteinPerKg: Double {
        switch self {
        case .lose: return 2.0
        case .maintain, .gain: return 1.8
        }
    }
}

/// The answers from onboarding, stored in metric.
public struct BodyProfile: Codable, Hashable, Sendable {
    public var sex: BiologicalSex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: ActivityLevel
    public var goal: WeightGoal
    /// Show pounds and feet/inches instead of kg and cm.
    public var usesMetric: Bool

    public init(sex: BiologicalSex, age: Int, heightCm: Double, weightKg: Double,
                activity: ActivityLevel, goal: WeightGoal, usesMetric: Bool) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.usesMetric = usesMetric
    }

    public static let validAges = 13...100
    public static let validHeightsCm = 120.0...230.0
    public static let validWeightsKg = 30.0...300.0

    public var isValid: Bool {
        Self.validAges.contains(age)
            && Self.validHeightsCm.contains(heightCm)
            && Self.validWeightsKg.contains(weightKg)
    }

    /// Resting energy use (Mifflin-St Jeor equation), in kcal/day.
    public var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return base + (sex == .male ? 5 : -161)
    }

    /// Calories to stay at the current weight, in kcal/day.
    public var maintenanceCalories: Double { bmr * activity.multiplier }

    /// Daily targets for this profile's goal:
    /// - calories: maintenance × goal factor, rounded to 10, never below 1500 (men) / 1200 (women)
    /// - protein: g/kg from the goal, capped at 35% of calories for very heavy users
    /// - fat: 25% of calories
    /// - carbs: whatever calories are left
    public func recommendedTargets() -> MacroTargets {
        let floor = sex == .male ? 1500.0 : 1200.0
        let calories = max((maintenanceCalories * goal.calorieFactor / 10).rounded() * 10, floor)
        let protein = min(goal.proteinPerKg * weightKg, 0.35 * calories / 4).rounded()
        let fat = (0.25 * calories / 9).rounded()
        let carbs = max(((calories - 4 * protein - 9 * fat) / 4).rounded(), 0)
        return MacroTargets(calories: Int(calories), protein: Int(protein), carbs: Int(carbs), fat: Int(fat))
    }
}

/// Unit conversions for the onboarding form.
public enum BodyUnits {
    public static let kgPerPound = 0.45359237
    public static let cmPerInch = 2.54

    public static func pounds(fromKg kg: Double) -> Double { kg / kgPerPound }
    public static func kg(fromPounds lb: Double) -> Double { lb * kgPerPound }

    /// Height in whole feet and inches, e.g. 180 cm -> (5, 11).
    public static func feetAndInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / cmPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    public static func cm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * cmPerInch
    }
}
