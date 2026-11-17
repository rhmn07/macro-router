import Foundation

public struct WeightEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var date: Date
    public var kg: Double
    /// True when imported from Apple Health.
    public var fromHealth: Bool

    public init(id: String = UUID().uuidString, date: Date, kg: Double, fromHealth: Bool = false) {
        self.id = id
        self.date = date
        self.kg = kg
        self.fromHealth = fromHealth
    }
}

/// Every couple of weeks, compares how weight actually changed with what the goal expects and
/// suggests a calorie change. 1 kg of body weight ≈ 7700 kcal.
public struct CalorieCheckIn: Hashable, Sendable {
    public static let kcalPerKg = 7700.0
    public static let minimumDays = 14.0
    public static let minimumEntries = 4

    /// Measured change, kg per week (negative = losing).
    public var kgPerWeek: Double
    /// Goal range, kg per week.
    public var goalRange: ClosedRange<Double>
    /// Suggested change to daily calories (0 = on track). Rounded to 50, at most ±300.
    public var calorieChange: Int

    public var isOnTrack: Bool { calorieChange == 0 }

    /// Expected weekly change for a goal: losing 0.25–1% of body weight, maintaining within ±0.25%,
    /// gaining 0.1–0.5%.
    public static func goalRange(for goal: WeightGoal, weightKg: Double) -> ClosedRange<Double> {
        switch goal {
        case .lose: return (-0.01 * weightKg)...(-0.0025 * weightKg)
        case .maintain: return (-0.0025 * weightKg)...(0.0025 * weightKg)
        case .gain: return (0.001 * weightKg)...(0.005 * weightKg)
        }
    }

    /// Weekly trend from a least-squares line through recent weigh-ins (last 28 days).
    public static func trend(_ entries: [WeightEntry], now: Date = Date()) -> Double? {
        let recent = entries.filter { now.timeIntervalSince($0.date) <= 28 * 86400 && $0.date <= now }
        guard recent.count >= minimumEntries,
              let first = recent.map(\.date).min(), let last = recent.map(\.date).max(),
              last.timeIntervalSince(first) >= minimumDays * 86400 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first) / 86400 }
        let ys = recent.map(\.kg)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).map { ($0 - mx) * ($1 - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        return sxy / sxx * 7
    }

    /// Nil until there are at least 4 weigh-ins over 14+ days.
    public static func evaluate(entries: [WeightEntry], goal: WeightGoal, now: Date = Date()) -> CalorieCheckIn? {
        guard let kgPerWeek = trend(entries, now: now),
              let latest = entries.max(by: { $0.date < $1.date }) else { return nil }
        let range = goalRange(for: goal, weightKg: latest.kg)
        let change: Double
        if kgPerWeek > range.upperBound {
            change = -(kgPerWeek - range.upperBound) * kcalPerKg / 7
        } else if kgPerWeek < range.lowerBound {
            change = (range.lowerBound - kgPerWeek) * kcalPerKg / 7
        } else {
            change = 0
        }
        let rounded = Int((change / 50).rounded()) * 50
        return CalorieCheckIn(kgPerWeek: kgPerWeek, goalRange: range, calorieChange: max(min(rounded, 300), -300))
    }
}

extension MacroTargets {
    /// Changes calories and carbs by `calories`, keeping protein and fat.
    public func adjusted(byCalories calories: Int) -> MacroTargets {
        var t = self
        t.calories = max(calories + self.calories, 1000)
        let applied = t.calories - self.calories
        t.carbs = max(self.carbs + Int((Double(applied) / 4).rounded()), 0)
        return t
    }
}
