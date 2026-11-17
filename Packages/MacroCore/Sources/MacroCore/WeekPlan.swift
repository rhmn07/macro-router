import Foundation

/// A week (or any number of days) of meals, plus which meals have been eaten.
public struct WeekPlan: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    /// Start of the first day (midnight, local time).
    public var startDate: Date
    public var targets: MacroTargets
    public var settings: PlannerSettings
    /// One plan per day, in order.
    public var days: [MealPlan]
    /// Eaten meals, as "day:slot" keys (see `key(day:slot:)`).
    public var eaten: Set<String>

    public init(id: String = UUID().uuidString, createdAt: Date = Date(), startDate: Date,
                targets: MacroTargets, settings: PlannerSettings, days: [MealPlan], eaten: Set<String> = []) {
        self.id = id
        self.createdAt = createdAt
        self.startDate = startDate
        self.targets = targets
        self.settings = settings
        self.days = days
        self.eaten = eaten
    }

    public static func key(day: Int, slot: MealSlot) -> String { "\(day):\(slot.rawValue)" }

    public func isEaten(day: Int, slot: MealSlot) -> Bool { eaten.contains(Self.key(day: day, slot: slot)) }

    public func eatenMeals(day: Int) -> [PlannedMeal] {
        guard days.indices.contains(day) else { return [] }
        return (days[day].meals ?? []).filter { isEaten(day: day, slot: $0.slot) }
    }

    /// Calories from eaten meals on a day.
    public func eatenCalories(day: Int) -> Double {
        eatenMeals(day: day).reduce(0) { $0 + $1.macros.calories }
    }

    public func date(ofDay day: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
    }

    /// Index of the day containing `date`, or nil when it's outside the plan.
    public func dayIndex(for date: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)
        guard let n = calendar.dateComponents([.day], from: start, to: target).day, days.indices.contains(n) else { return nil }
        return n
    }

    /// Foods selected for the week that no day uses.
    public var unusedIngredients: [Ingredient] {
        var used = Set<String>()
        var all: [String: Ingredient] = [:]
        var order: [String] = []
        for day in days {
            for item in day.items {
                if all[item.ingredient.id] == nil { order.append(item.ingredient.id) }
                all[item.ingredient.id] = item.ingredient
                if item.grams > 0 { used.insert(item.ingredient.id) }
            }
        }
        return order.filter { !used.contains($0) }.compactMap { all[$0] }
    }

    /// Plans `count` days starting at `start`. Mains rotate from day to day.
    public static func make(ingredients: [Ingredient], targets: MacroTargets, settings: PlannerSettings,
                            days count: Int = 7, start: Date = Date(), calendar: Calendar = .current,
                            options: SolverOptions = SolverOptions()) throws -> WeekPlan {
        let startDate = calendar.startOfDay(for: start)
        let days = try (0..<max(count, 1)).map { day in
            try MealPlanner.solve(ingredients: ingredients, targets: targets, settings: settings,
                                  day: day, options: options,
                                  now: calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate)
        }
        return WeekPlan(startDate: startDate, targets: targets, settings: settings, days: days)
    }

    /// Re-plans one day around its eaten meals, e.g. after removing a food the user doesn't want.
    public mutating func replan(day: Int, ingredients: [Ingredient], options: SolverOptions = SolverOptions()) throws {
        guard days.indices.contains(day) else { return }
        let plan = try MealPlanner.solve(ingredients: ingredients, targets: targets, settings: settings,
                                         day: day, eaten: eatenMeals(day: day), options: options,
                                         now: days[day].createdAt)
        days[day] = plan
    }
}

extension GroceryList {
    /// Total of several days, heaviest first.
    public static func items(for days: [MealPlan]) -> [GroceryItem] {
        var grams: [String: (Ingredient, Double)] = [:]
        var order: [String] = []
        for day in days {
            for item in day.recipe {
                if grams[item.ingredient.id] == nil { order.append(item.ingredient.id) }
                grams[item.ingredient.id] = (item.ingredient, (grams[item.ingredient.id]?.1 ?? 0) + item.grams)
            }
        }
        return order.map { GroceryItem(ingredient: grams[$0]!.0, grams: grams[$0]!.1) }
            .sorted { $0.grams > $1.grams }
    }

    public static func shareText(for week: WeekPlan, days range: Range<Int>) -> String {
        let days = Array(week.days[range.clamped(to: week.days.indices)])
        var lines = ["Macro Router — grocery list for \(days.count) \(days.count == 1 ? "day" : "days")", ""]
        lines += items(for: days).map { item in
            if let package = item.package, item.packageCount != nil {
                return "• \(item.quantityText) \(item.name) (\(package.sizeText))"
            }
            return "• \(item.quantityText) \(item.name)"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        for (offset, day) in days.enumerated() {
            let index = range.lowerBound + offset
            lines += ["", formatter.string(from: week.date(ofDay: index)) + ":"]
            for meal in day.meals ?? [] where !meal.items.isEmpty {
                let foods = meal.items.map { item in item.pieceText ?? formatWeight(grams: item.grams) }
                lines.append("\(meal.slot.displayName) — \(MealRecipe.name(for: meal)): "
                             + zip(foods, meal.items).map { "\($0) \($1.ingredient.shortName)" }.joined(separator: ", "))
            }
        }
        return lines.joined(separator: "\n")
    }
}
