import XCTest
@testable import MacroCore

final class MealPlannerTests: XCTestCase {
    let targets = MacroTargets(calories: 2210, protein: 160, carbs: 255, fat: 61)
    let oats = Ingredient(name: "Oats (dry)", source: .custom, macrosPer100g: Macros(protein: 13, carbs: 68, fat: 6.5))
    let eggs = Ingredient(name: "Eggs, whole, raw", source: .custom, macrosPer100g: Macros(protein: 12.6, carbs: 0.7, fat: 9.5))
    let pasta = Ingredient(name: "Pasta (dry)", source: .custom, macrosPer100g: Macros(protein: 13, carbs: 75, fat: 1.5))

    private func meal(_ plan: MealPlan, _ slot: MealSlot) -> Set<String> {
        Set(plan.meals?.first { $0.slot == slot }?.items.map(\.ingredient.id) ?? [])
    }

    func testHasThreeMealsThatAddUpToTargets() throws {
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all, targets: targets)
        XCTAssertEqual(plan.meals?.map(\.slot), [.breakfast, .lunch, .dinner])
        XCTAssertTrue(plan.isWithinMargin, "\(plan.results)")
        let mealTotal = plan.meals!.reduce(0) { $0 + $1.macros.calories }
        XCTAssertEqual(mealTotal, plan.achieved.calories, accuracy: 0.001, "meals add up to the daily totals")
    }

    func testUsesEverySelectedFood() throws {
        let foods = SeedIngredients.all + [oats, eggs, pasta]
        let plan = try MealPlanner.solve(ingredients: foods, targets: targets)
        XCTAssertTrue(plan.unusedIngredients.isEmpty, "unused: \(plan.unusedIngredients.map(\.name))")
        XCTAssertTrue(plan.isWithinMargin, "\(plan.results)")
    }

    func testMealsSuitTheFood() throws {
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all + [oats, eggs, pasta], targets: targets)
        XCTAssertTrue(meal(plan, .breakfast).contains(oats.id))
        XCTAssertFalse(meal(plan, .lunch).contains(oats.id))
        XCTAssertFalse(meal(plan, .dinner).contains(oats.id))
        XCTAssertFalse(meal(plan, .breakfast).contains(SeedIngredients.groundBeef.id), "beef isn't breakfast when eggs are there")
    }

    func testLunchAndDinnerGetDifferentMains() throws {
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all + [pasta], targets: targets)
        let lunch = meal(plan, .lunch), dinner = meal(plan, .dinner)
        let proteins = [SeedIngredients.chickenBreast.id, SeedIngredients.groundBeef.id]
        XCTAssertEqual(proteins.filter { lunch.contains($0) }.count, 1)
        XCTAssertEqual(proteins.filter { dinner.contains($0) }.count, 1)
        XCTAssertNotEqual(proteins.filter { lunch.contains($0) }, proteins.filter { dinner.contains($0) })
        XCTAssertFalse(plan.suggestions.contains { $0.hasPrefix("Lunch and dinner") })
    }

    func testFewFoodsStillMakesThreeMealsAndSaysSo() throws {
        let foods = [SeedIngredients.chickenBreast, SeedIngredients.whiteRice, SeedIngredients.broccoli, SeedIngredients.oliveOil]
        let plan = try MealPlanner.solve(ingredients: foods, targets: targets)
        XCTAssertTrue(plan.meals!.allSatisfy { !$0.items.isEmpty })
        XCTAssertTrue(plan.isWithinMargin, "\(plan.results)")
        XCTAssertTrue(plan.suggestions.contains { $0.hasPrefix("Lunch and dinner") })
    }

    func testNoCrumbPortions() throws {
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all + [oats, eggs, pasta], targets: targets)
        for meal in plan.meals! {
            for item in meal.items {
                XCTAssertGreaterThanOrEqual(item.grams, MealPlanner.minServing(item.ingredient), "\(meal.slot): \(item.ingredient.name)")
            }
        }
    }

    func testUserMealChoiceIsRespected() throws {
        var beef = SeedIngredients.groundBeef
        beef.meals = [.breakfast]
        let plan = try MealPlanner.solve(ingredients: [beef, SeedIngredients.chickenBreast, SeedIngredients.whiteRice], targets: targets)
        XCTAssertTrue(meal(plan, .breakfast).contains(beef.id))
        XCTAssertFalse(meal(plan, .lunch).contains(beef.id))
        XCTAssertFalse(meal(plan, .dinner).contains(beef.id))
    }

    func testDailyLimitsHold() throws {
        var rice = SeedIngredients.whiteRice
        rice.maxGrams = 150
        let plan = try MealPlanner.solve(ingredients: SeedIngredients.all.filter { $0.id != rice.id } + [rice], targets: targets)
        XCTAssertLessThanOrEqual(plan.items.first { $0.ingredient.id == rice.id }!.grams, 150)
    }

    func testOldPlansWithoutMealsStillDecode() throws {
        let old = MealPlan(targets: targets, items: [PlanItem(ingredient: SeedIngredients.chickenBreast, grams: 300)])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "meals")
        let decoded = try JSONDecoder().decode(MealPlan.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.meals)
        XCTAssertEqual(decoded.recipe.count, 1)
    }

    func testBreakfastWithoutCarbsDoesNotBorrowDinnerFoods() throws {
        // The user's pantry: beef, egg whites, rice, black bean soup, broccoli. No breakfast carb.
        let soup = Ingredient(name: "Soup, black bean, canned, condensed", source: .custom,
                              macrosPer100g: Macros(protein: 4.8, carbs: 15.4, fat: 1.3, calories: 91))
        let beef = Ingredient(name: "Beef, ground, 93% lean, crumbles, cooked", source: .custom,
                              macrosPer100g: Macros(protein: 28.9, carbs: 0, fat: 9.5, calories: 209))
        let plan = try MealPlanner.solve(ingredients: [beef, SeedIngredients.eggWhites, SeedIngredients.whiteRice, soup, SeedIngredients.broccoli],
                                         targets: targets)
        XCTAssertEqual(meal(plan, .breakfast), [SeedIngredients.eggWhites.id], "egg whites only, no soup or rice")
        XCTAssertTrue(plan.unusedIngredients.isEmpty)
        // This pantry has no real fat source, so only protein, carbs and calories can get close.
        let errors = plan.results.filter { $0.kind != .fat }.compactMap(\.relativeError).map(abs)
        XCTAssertLessThan(errors.max()!, 0.15, "\(plan.results)")
    }

    func testBreadComesInSlicesNotLoaves() throws {
        let bread = Ingredient(name: "Bread, whole-wheat", source: .custom, macrosPer100g: Macros(protein: 13, carbs: 43, fat: 3.4, calories: 252))
        for foods in [SeedIngredients.all + [bread],
                      [SeedIngredients.chickenBreast, SeedIngredients.eggWhites, bread, SeedIngredients.broccoli, SeedIngredients.oliveOil]] {
            let plan = try MealPlanner.solve(ingredients: foods, targets: targets)
            for meal in plan.meals! {
                guard let item = meal.items.first(where: { $0.ingredient.id == bread.id }) else { continue }
                let slices = item.grams / 32
                XCTAssertEqual(slices, slices.rounded(), accuracy: 0.001, "whole slices in \(meal.slot)")
                XCTAssertLessThanOrEqual(slices, 4, "at most 4 slices in \(meal.slot)")
                XCTAssertNotNil(item.pieceText)
            }
            XCTAssertTrue(plan.unusedIngredients.isEmpty)
        }
    }

    func testPieceGuesses() {
        func piece(_ name: String) -> String? {
            Ingredient(name: name, source: .custom, macrosPer100g: Macros(protein: 10, carbs: 10, fat: 1)).pieceSize?.unit
        }
        XCTAssertEqual(piece("Bread, whole-wheat"), "slice")
        XCTAssertEqual(piece("Bagel, plain"), "bagel")
        XCTAssertEqual(piece("Eggs, whole, raw"), "egg")
        XCTAssertNil(piece("Egg Whites"))
        XCTAssertNil(piece("Bread crumbs"))
        XCTAssertNil(piece("White Rice (dry)"))
        XCTAssertEqual(PlanItem(ingredient: Ingredient(name: "Bread", source: .custom, macrosPer100g: .zero), grams: 96).pieceText, "3 slices")
    }

    func testMealGuesses() {
        XCTAssertEqual(oats.guessedMeals, [.breakfast])
        XCTAssertEqual(eggs.guessedMeals, [.breakfast, .lunch, .dinner])
        XCTAssertEqual(SeedIngredients.broccoli.guessedMeals, [.lunch, .dinner])
        XCTAssertEqual(SeedIngredients.oliveOil.guessedMeals, [.breakfast, .lunch, .dinner])
        let boiled = Ingredient(name: "Potatoes, boiled", source: .custom, macrosPer100g: Macros(protein: 2, carbs: 20, fat: 0.1))
        XCTAssertEqual(boiled.guessedMeals, [.lunch, .dinner], "'boiled' isn't oil")
    }
}
