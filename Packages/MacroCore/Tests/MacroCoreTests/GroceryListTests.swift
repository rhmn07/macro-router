import XCTest
@testable import MacroCore

final class GroceryListTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(GroceryList.formatWeight(grams: 250), "250 g")
        XCTAssertEqual(GroceryList.formatWeight(grams: 1250), "1.25 kg")
        XCTAssertEqual(GroceryList.formatWeight(grams: 1000), "1 kg")
        XCTAssertEqual(GroceryList.formatWeight(grams: 1500), "1.5 kg")
        XCTAssertEqual(GroceryList.formatWeight(grams: 3456), "3.46 kg")
    }

    func testFiveDayListIsDailyTimesFive() {
        let plan = MealPlan(targets: .example, items: [
            PlanItem(ingredient: SeedIngredients.chickenBreast, grams: 250),
            PlanItem(ingredient: SeedIngredients.whiteRice, grams: 150),
            PlanItem(ingredient: SeedIngredients.oliveOil, grams: 0),
        ])
        let items = GroceryList.items(for: plan)
        XCTAssertEqual(items.count, 2, "0 g items are left off the list")
        XCTAssertEqual(items[0].quantityText, "2 packs", "1.25 kg chicken in 680 g packs")
        XCTAssertEqual(items[1].quantityText, "1 bag", "750 g rice in a 2 lb bag")
        XCTAssertEqual(items[0].grams, 1250)
        XCTAssertEqual(items[0].formattedWeight, "1.25 kg")
        XCTAssertEqual(items[1].formattedWeight, "750 g")
        XCTAssertEqual(plan.unusedIngredients.map(\.id), [SeedIngredients.oliveOil.id])
    }
}

final class PackageSizeTests: XCTestCase {
    private func food(_ name: String) -> Ingredient {
        Ingredient(name: name, source: .custom, macrosPer100g: Macros(protein: 10, carbs: 10, fat: 1))
    }

    func testGuessesCommonFoods() {
        XCTAssertEqual(PackageSize.guess(for: SeedIngredients.groundBeef)?.unit, "pack")
        XCTAssertEqual(PackageSize.guess(for: SeedIngredients.eggWhites)?.unit, "carton")
        XCTAssertEqual(PackageSize.guess(for: food("Eggs, Grade A, Large, egg white"))?.unit, "carton")
        XCTAssertEqual(PackageSize.guess(for: food("Eggs, whole, raw"))?.unit, "dozen")
        XCTAssertEqual(PackageSize.guess(for: food("Beans, black, canned"))?.unit, "can")
        XCTAssertEqual(PackageSize.guess(for: food("Soup, black bean, canned, condensed"))?.grams, 305)
        XCTAssertEqual(PackageSize.guess(for: SeedIngredients.oliveOil)?.unit, "bottle")
        XCTAssertEqual(PackageSize.guess(for: SeedIngredients.avocado)?.unit, "whole")
        XCTAssertNil(PackageSize.guess(for: food("Mystery mix")))
    }

    func testCountsRoundUpWithSmallTolerance() {
        let beef = SeedIngredients.groundBeef // 454 g packs
        XCTAssertEqual(GroceryItem(ingredient: beef, grams: 1250).packageCount, 3)
        XCTAssertEqual(GroceryItem(ingredient: beef, grams: 460).packageCount, 1, "1.3% over still fits one pack")
        XCTAssertEqual(GroceryItem(ingredient: beef, grams: 100).packageCount, 1)
        XCTAssertEqual(GroceryItem(ingredient: food("Eggs, whole"), grams: 1500).quantityText, "3 dozen")
        XCTAssertEqual(GroceryItem(ingredient: SeedIngredients.avocado, grams: 500).quantityText, "4 whole")
        XCTAssertEqual(GroceryItem(ingredient: food("Mystery mix"), grams: 1500).quantityText, "1.5 kg")
    }

    func testUserPackageOverridesGuess() {
        var beef = SeedIngredients.groundBeef
        beef.package = PackageSize(unit: "pack", grams: 907) // 2 lb family pack
        XCTAssertEqual(GroceryItem(ingredient: beef, grams: 1250).quantityText, "2 packs")
    }

    func testCountText() {
        XCTAssertEqual(PackageSize(unit: "box", grams: 454).countText(2), "2 boxes")
        XCTAssertEqual(PackageSize(unit: "can", grams: 425).countText(1), "1 can")
        XCTAssertEqual(PackageSize(unit: "dozen", grams: 600).countText(2), "2 dozen")
    }
}
