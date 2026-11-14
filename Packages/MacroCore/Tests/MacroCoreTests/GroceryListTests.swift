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
        XCTAssertEqual(items[0].grams, 1250)
        XCTAssertEqual(items[0].formattedWeight, "1.25 kg")
        XCTAssertEqual(items[1].formattedWeight, "750 g")
        XCTAssertEqual(plan.unusedIngredients.map(\.id), [SeedIngredients.oliveOil.id])
    }
}
