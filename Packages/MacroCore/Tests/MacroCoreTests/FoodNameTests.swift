import XCTest
@testable import MacroCore

final class FoodNameTests: XCTestCase {
    func testRealUSDANames() {
        let cases: [(String, String)] = [
            ("Beef, ground, 93% lean meat / 7% fat, crumbles, cooked, pan-browned", "Ground beef 93/7 (cooked)"),
            ("Beef, ground, 70% lean meat / 30% fat, raw", "Ground beef 70/30 (raw)"),
            ("Beef, ground, unspecified fat content, cooked", "Ground beef (cooked)"),
            ("Beef, grass-fed, ground, raw", "Ground beef, grass-fed (raw)"),
            ("Eggs, Grade A, Large, egg white", "Egg whites"),
            ("Egg, white, raw, fresh", "Egg whites (raw)"),
            ("Oil, corn, peanut, and olive", "Corn, peanut and olive oil"),
            ("Oil, olive, extra virgin", "Olive oil, extra virgin"),
            ("Soup, black bean, canned, condensed", "Black bean soup (canned, condensed)"),
            ("Soup, black bean, canned, prepared with equal volume water", "Black bean soup (canned, prepared)"),
            ("Restaurant, Latino, black bean soup", "Black bean soup (restaurant)"),
            ("Chicken, breast, boneless, skinless, raw", "Chicken breast (raw)"),
            ("Fish, salmon, pink, raw", "Pink salmon (raw)"),
            ("Yogurt, Greek, plain, nonfat", "Greek yogurt, nonfat"),
            ("Rice, white, long-grain, regular, raw, enriched", "White rice, long-grain (dry)"),
            ("Oats, puffed", "Puffed oats"),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(FoodName.clean(raw), expected, raw)
        }
    }

    func testLeavesUserNamesAlone() {
        XCTAssertEqual(FoodName.clean("Chicken Breast (raw)"), "Chicken Breast (raw)")
        XCTAssertEqual(FoodName.clean("My protein shake"), "My protein shake")
    }

    func testCleanNamesKeepWhatThePlannerNeeds() {
        func food(_ raw: String) -> Ingredient {
            Ingredient(name: FoodName.clean(raw), source: .usda, macrosPer100g: Macros(protein: 10, carbs: 10, fat: 1))
        }
        XCTAssertEqual(food("Rice, white, long-grain, regular, raw, enriched").weighingState, .dry)
        XCTAssertEqual(food("Rice, white, long-grain, regular, raw, enriched").cookedWeightFactor, 3.0)
        XCTAssertEqual(food("Beef, ground, 93% lean meat / 7% fat, crumbles, cooked, pan-browned").weighingState, .cooked)
        XCTAssertEqual(food("Eggs, Grade A, Large, egg white").packageSize?.unit, "carton")
        XCTAssertEqual(food("Soup, black bean, canned, condensed").packageSize?.grams, 305)
        XCTAssertFalse(PlannerSettings(diet: [.noBeef]).allows(food("Beef, ground, 70% lean meat / 30% fat, raw")))
    }

    func testUSDAImportUsesCleanName() throws {
        let food = USDAFood(fdcId: 1, description: "Beef, ground, 93% lean meat / 7% fat, raw", dataType: "SR Legacy",
                            brandOwner: nil, brandName: nil,
                            foodNutrients: [USDANutrient(nutrientId: 1003, nutrientName: nil, unitName: "G", value: 20)])
        XCTAssertEqual(try XCTUnwrap(food.toIngredient()).name, "Ground beef 93/7 (raw)")
    }
}

final class PantryCheckTests: XCTestCase {
    let targets = MacroTargets(calories: 1930, protein: 154, carbs: 207, fat: 54)

    func testNoFatSourceIsFlaggedWithASuggestion() {
        let picks = [SeedIngredients.chickenBreast, SeedIngredients.eggWhites, SeedIngredients.whiteRice, SeedIngredients.broccoli]
        let gaps = PantryCheck.gaps(selected: picks, pantry: SeedIngredients.all, targets: targets)
        let fat = gaps.first { $0.kind == .fat }
        XCTAssertNotNil(fat, "\(gaps)")
        XCTAssertTrue(fat!.isShort)
        XCTAssertTrue(fat!.noSource)
        XCTAssertEqual(fat!.suggestion?.id, SeedIngredients.oliveOil.id)
        XCTAssertEqual(fat!.detail, "None of your picked foods is a fat source.")
    }

    func testBalancedPicksHaveNoGaps() {
        XCTAssertTrue(PantryCheck.gaps(selected: SeedIngredients.all, pantry: SeedIngredients.all, targets: targets).isEmpty)
    }

    func testSuggestionRespectsDiet() {
        let picks = [SeedIngredients.whiteRice, SeedIngredients.broccoli, SeedIngredients.oliveOil]
        let settings = PlannerSettings(diet: [.vegetarian])
        let protein = PantryCheck.gaps(selected: picks, pantry: SeedIngredients.all, targets: targets, settings: settings)
            .first { $0.kind == .protein }
        XCTAssertEqual(protein?.suggestion?.id, SeedIngredients.eggWhites.id, "chicken isn't vegetarian")
    }
}
