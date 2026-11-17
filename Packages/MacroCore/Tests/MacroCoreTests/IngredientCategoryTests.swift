import XCTest
@testable import MacroCore

final class IngredientCategoryTests: XCTestCase {
    private func category(p: Double, c: Double, f: Double) -> IngredientCategory {
        Ingredient(name: "Test", source: .custom, macrosPer100g: Macros(protein: p, carbs: c, fat: f)).category
    }

    func testSeedStaplesKeepTheirCategories() {
        XCTAssertEqual(SeedIngredients.chickenBreast.category, .protein)
        XCTAssertEqual(SeedIngredients.groundBeef.category, .protein)
        XCTAssertEqual(SeedIngredients.eggWhites.category, .protein)
        XCTAssertEqual(SeedIngredients.whiteRice.category, .carb)
        XCTAssertEqual(SeedIngredients.broccoli.category, .carb)
        XCTAssertEqual(SeedIngredients.oliveOil.category, .fat)
        XCTAssertEqual(SeedIngredients.avocado.category, .fat)
    }

    func testFattyProteinsAreProteins() {
        XCTAssertEqual(category(p: 20.4, c: 0, f: 13.4), .protein, "salmon")
        XCTAssertEqual(category(p: 12.6, c: 0.7, f: 9.5), .protein, "whole egg")
        XCTAssertEqual(category(p: 17.2, c: 0, f: 15.0), .protein, "85/15 ground beef")
    }

    func testFatHeavyFoodsAreFats() {
        XCTAssertEqual(category(p: 25, c: 20, f: 50), .fat, "peanut butter")
        XCTAssertEqual(category(p: 21, c: 22, f: 49), .fat, "almonds")
    }
}
