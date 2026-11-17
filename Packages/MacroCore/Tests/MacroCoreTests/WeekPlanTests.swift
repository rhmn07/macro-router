import XCTest
@testable import MacroCore

final class WeekPlanTests: XCTestCase {
    let targets = MacroTargets(calories: 2210, protein: 160, carbs: 255, fat: 61)
    let oats = Ingredient(name: "Oats (dry)", source: .custom, macrosPer100g: Macros(protein: 13, carbs: 68, fat: 6.5))
    let yogurt = Ingredient(name: "Greek yogurt, plain, nonfat", source: .custom, macrosPer100g: Macros(protein: 10, carbs: 3.6, fat: 0.4))
    let banana = Ingredient(name: "Banana, raw", source: .custom, macrosPer100g: Macros(protein: 1.1, carbs: 23, fat: 0.3))
    let salmon = Ingredient(name: "Salmon, raw", source: .custom, macrosPer100g: Macros(protein: 20, carbs: 0, fat: 13))
    let pasta = Ingredient(name: "Pasta (dry)", source: .custom, macrosPer100g: Macros(protein: 13, carbs: 75, fat: 1.5))

    private func proteinsAt(_ plan: MealPlan, _ slot: MealSlot) -> Set<String> {
        Set(plan.meals?.first { $0.slot == slot }?.items
            .filter { $0.ingredient.category == .protein }.map(\.ingredient.id) ?? [])
    }

    func testWeekRotatesLunchAndDinner() throws {
        let foods = SeedIngredients.all + [salmon, pasta]
        let week = try WeekPlan.make(ingredients: foods, targets: targets, settings: PlannerSettings(), days: 7)
        XCTAssertEqual(week.days.count, 7)
        let lunches = week.days.map { proteinsAt($0, .lunch) }
        XCTAssertGreaterThan(Set(lunches).count, 1, "lunch protein changes during the week")
        XCTAssertTrue(week.unusedIngredients.isEmpty, "every food is used at some point: \(week.unusedIngredients.map(\.name))")
        for day in week.days {
            let errors = day.results.compactMap(\.relativeError).map(abs)
            XCTAssertLessThan(errors.max()!, 0.12, "\(day.results)")
        }
    }

    func testGroceryListSumsTheWeek() throws {
        let week = try WeekPlan.make(ingredients: SeedIngredients.all, targets: targets, settings: PlannerSettings(), days: 7)
        let total = GroceryList.items(for: week.days).reduce(0) { $0 + $1.grams }
        let expected = week.days.reduce(0) { $0 + $1.recipe.reduce(0) { $0 + $1.grams } }
        XCTAssertEqual(total, expected, accuracy: 0.001)
    }

    func testEatenMealIsKeptAndRestReplanned() throws {
        var week = try WeekPlan.make(ingredients: SeedIngredients.all, targets: targets, settings: PlannerSettings(), days: 2)
        let breakfast = week.days[0].meals!.first { $0.slot == .breakfast }!
        week.eaten.insert(WeekPlan.key(day: 0, slot: .breakfast))
        // Drop chicken for today: the day is re-planned without it, breakfast stays the same.
        let withoutChicken = SeedIngredients.all.filter { $0.id != SeedIngredients.chickenBreast.id }
        try week.replan(day: 0, ingredients: withoutChicken)
        XCTAssertEqual(week.days[0].meals!.first { $0.slot == .breakfast }, breakfast)
        XCTAssertFalse(week.days[0].meals!.contains { $0.slot != .breakfast && $0.items.contains { $0.ingredient.id == SeedIngredients.chickenBreast.id } })
        XCTAssertTrue(week.days[0].isWithinMargin || week.days[0].results.allSatisfy { abs($0.relativeError ?? 0) < 0.12 }, "\(week.days[0].results)")
        XCTAssertEqual(week.eatenCalories(day: 0), breakfast.macros.calories, accuracy: 0.001)
    }

    func testSnackUsesSnackFoods() throws {
        let settings = PlannerSettings(includeSnack: true)
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all + [oats, yogurt, banana], targets: targets, settings: settings)
        let snack = plan.meals!.first { $0.slot == .snack }
        XCTAssertNotNil(snack)
        XCTAssertTrue(snack!.items.allSatisfy { $0.ingredient.suitableMeals.contains(.snack) }, "\(snack!.items.map(\.ingredient.name))")
        XCTAssertEqual(plan.meals!.map(\.slot), [.breakfast, .lunch, .snack, .dinner])
    }

    func testSnackSkippedWithoutSnackFoods() throws {
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all, targets: targets, settings: PlannerSettings(includeSnack: true))
        XCTAssertFalse(plan.meals!.contains { $0.slot == .snack })
    }

    func testNoBreakfast() throws {
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all, targets: targets, settings: PlannerSettings(includeBreakfast: false))
        XCTAssertEqual(plan.meals!.map(\.slot), [.lunch, .dinner])
    }

    func testSharesAddUp() {
        for sizes in MealSizes.allCases {
            for breakfast in [true, false] {
                for snack in [true, false] {
                    let s = PlannerSettings(includeBreakfast: breakfast, includeSnack: snack, mealSizes: sizes)
                    XCTAssertEqual(s.slots.map(s.share).reduce(0, +), 1, accuracy: 1e-9)
                }
            }
        }
        let big = PlannerSettings(mealSizes: .bigDinner)
        XCTAssertGreaterThan(big.share(of: .dinner), big.share(of: .lunch))
    }

    func testDietFilters() throws {
        let veg = PlannerSettings(diet: [.vegetarian])
        XCTAssertFalse(veg.allows(SeedIngredients.chickenBreast))
        XCTAssertFalse(veg.allows(salmon))
        XCTAssertTrue(veg.allows(SeedIngredients.eggWhites))
        XCTAssertTrue(PlannerSettings(diet: [.pescatarian]).allows(salmon))
        XCTAssertFalse(PlannerSettings(diet: [.noBeef]).allows(SeedIngredients.groundBeef))
        XCTAssertFalse(PlannerSettings(diet: [.dairyFree]).allows(yogurt))
        XCTAssertFalse(PlannerSettings(diet: [.glutenFree]).allows(pasta))
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all, targets: targets, settings: veg)
        XCTAssertFalse(plan.recipe.contains { $0.ingredient.id == SeedIngredients.chickenBreast.id })
    }

    func testMealNamesAndSteps() throws {
        let meal = PlannedMeal(slot: .lunch, items: [
            PlanItem(ingredient: SeedIngredients.chickenBreast, grams: 170),
            PlanItem(ingredient: SeedIngredients.whiteRice, grams: 90),
            PlanItem(ingredient: SeedIngredients.broccoli, grams: 100),
            PlanItem(ingredient: SeedIngredients.oliveOil, grams: 10),
        ])
        XCTAssertEqual(MealRecipe.name(for: meal), "Chicken breast & white rice bowl with broccoli")
        let steps = MealRecipe.steps(for: meal)
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps[0].contains("170 g raw chicken breast in 10 g olive oil"), steps[0])
        XCTAssertTrue(steps[1].contains("about 270 g cooked"), steps[1])
        let beef = Ingredient(name: FoodName.clean("Beef, ground, 93% lean meat / 7% fat, crumbles, cooked"), source: .usda, macrosPer100g: .zero)
        XCTAssertEqual(beef.shortName, "Ground beef")
        let soup = Ingredient(name: FoodName.clean("Soup, black bean, canned, condensed"), source: .usda, macrosPer100g: .zero)
        XCTAssertEqual(Ingredient(name: "Corn, peanut and olive oil", source: .usda, macrosPer100g: .zero).shortName, "Corn, peanut and olive oil")
        XCTAssertEqual(Ingredient(name: "Greek yogurt, nonfat", source: .usda, macrosPer100g: .zero).shortName, "Greek yogurt")
        XCTAssertEqual(soup.shortName, "Black bean soup")
    }

    func testCheckIn() {
        let now = Date()
        func entries(_ kgs: [Double]) -> [WeightEntry] {
            kgs.enumerated().map { WeightEntry(date: now.addingTimeInterval(-Double(kgs.count - 1 - $0.offset) * 5 * 86400), kg: $0.element) }
        }
        XCTAssertNil(CalorieCheckIn.evaluate(entries: entries([80, 79.8]), goal: .lose, now: now), "too few weigh-ins")
        // Losing ~0.5 kg/week on a lose goal: on track.
        let onTrack = CalorieCheckIn.evaluate(entries: entries([80, 79.65, 79.3, 78.95]), goal: .lose, now: now)!
        XCTAssertEqual(onTrack.kgPerWeek, -0.49, accuracy: 0.01)
        XCTAssertTrue(onTrack.isOnTrack)
        // Not losing on a lose goal: eat less.
        let stalled = CalorieCheckIn.evaluate(entries: entries([80, 80.1, 80, 80.1]), goal: .lose, now: now)!
        XCTAssertLessThan(stalled.calorieChange, 0)
        XCTAssertGreaterThanOrEqual(stalled.calorieChange, -300)
        // Losing on a gain goal: eat more.
        XCTAssertGreaterThan(CalorieCheckIn.evaluate(entries: entries([80, 79.7, 79.4, 79.1]), goal: .gain, now: now)!.calorieChange, 0)
        XCTAssertEqual(MacroTargets(calories: 2200, protein: 160, carbs: 250, fat: 60).adjusted(byCalories: -200),
                       MacroTargets(calories: 2000, protein: 160, carbs: 200, fat: 60))
    }
}
