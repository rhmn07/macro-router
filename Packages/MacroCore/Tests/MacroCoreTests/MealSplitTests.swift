import XCTest
@testable import MacroCore

final class MealSplitTests: XCTestCase {
    private func food(_ name: String) -> Ingredient {
        Ingredient(name: name, source: .custom, macrosPer100g: Macros(protein: 10, carbs: 10, fat: 1))
    }

    func testWeighingStateFromName() {
        XCTAssertEqual(SeedIngredients.whiteRice.weighingState, .dry)
        XCTAssertEqual(SeedIngredients.chickenBreast.weighingState, .raw)
        XCTAssertEqual(SeedIngredients.groundBeef.weighingState, .raw)
        XCTAssertEqual(SeedIngredients.broccoli.weighingState, .unspecified)
        XCTAssertEqual(food("Beef, ground, 93% lean meat / 7% fat, crumbles, cooked, pan-browned").weighingState, .cooked)
        XCTAssertEqual(food("Rice, white, long-grain, regular, raw, enriched").weighingState, .raw)
        XCTAssertEqual(food("Oats, dry").weighingState, .dry)
    }

    func testCookedWeightFactor() {
        XCTAssertEqual(SeedIngredients.whiteRice.cookedWeightFactor, 3.0)
        XCTAssertEqual(SeedIngredients.chickenBreast.cookedWeightFactor, 0.75)
        XCTAssertNil(SeedIngredients.broccoli.cookedWeightFactor)
        XCTAssertNil(SeedIngredients.oliveOil.cookedWeightFactor)
        XCTAssertNil(food("Chicken breast, grilled").cookedWeightFactor, "already cooked")
    }

    func testCookedEstimate() {
        XCTAssertEqual(PlanItem(ingredient: SeedIngredients.whiteRice, grams: 90).approximateCookedGrams, 270)
        XCTAssertNil(PlanItem(ingredient: SeedIngredients.oliveOil, grams: 10).approximateCookedGrams)
    }

    func testTinyPortionsNeverRoundToZero() {
        XCTAssertEqual(MealSplit.roundPortion(0.4), 1)
        XCTAssertEqual(MealSplit.roundPortion(0), 0)
    }
}
