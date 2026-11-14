import XCTest
@testable import MacroCore

final class USDAParsingTests: XCTestCase {
    func testParsesSearchResult() throws {
        let json = """
        {"totalHits": 1, "foods": [{
          "fdcId": 175167, "description": "FISH, SALMON, ATLANTIC, FARMED, RAW", "dataType": "SR Legacy",
          "foodNutrients": [
            {"nutrientId": 1003, "nutrientName": "Protein", "unitName": "G", "value": 20.4},
            {"nutrientId": 1004, "nutrientName": "Total lipid (fat)", "unitName": "G", "value": 13.4},
            {"nutrientId": 1005, "nutrientName": "Carbohydrate, by difference", "unitName": "G", "value": 0.0},
            {"nutrientId": 1008, "nutrientName": "Energy", "unitName": "KCAL", "value": 208}
          ]}]}
        """
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: Data(json.utf8))
        let ingredient = try XCTUnwrap(response.foods.first?.toIngredient())
        XCTAssertEqual(ingredient.id, "usda-175167")
        XCTAssertEqual(ingredient.name, "Fish, Salmon, Atlantic, Farmed, Raw")
        XCTAssertEqual(ingredient.macrosPer100g.protein, 20.4)
        XCTAssertEqual(ingredient.macrosPer100g.calories, 208)
        XCTAssertEqual(ingredient.category, .protein)
    }

    func testFallsBackToAtwaterWhenNoEnergy() throws {
        let food = USDAFood(fdcId: 1, description: "Oats", dataType: "Foundation", brandOwner: nil, brandName: nil,
                            foodNutrients: [
                                USDANutrient(nutrientId: 1003, nutrientName: nil, unitName: "G", value: 13),
                                USDANutrient(nutrientId: 1005, nutrientName: nil, unitName: "G", value: 68),
                                USDANutrient(nutrientId: 1004, nutrientName: nil, unitName: "G", value: 6.5),
                            ])
        let ingredient = try XCTUnwrap(food.toIngredient())
        XCTAssertEqual(ingredient.macrosPer100g.calories, 4 * 13 + 4 * 68 + 9 * 6.5, accuracy: 1e-9)
    }

    func testSkipsFoodsWithoutMacros() {
        let food = USDAFood(fdcId: 2, description: "Water", dataType: nil, brandOwner: nil, brandName: nil, foodNutrients: [])
        XCTAssertNil(food.toIngredient())
    }
}
