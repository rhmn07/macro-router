import XCTest
@testable import MacroCore

final class MacroSolverTests: XCTestCase {
    private let targets = MacroTargets(calories: 2350, protein: 180, carbs: 250, fat: 70)
    private let staples = [SeedIngredients.chickenBreast, SeedIngredients.whiteRice,
                           SeedIngredients.broccoli, SeedIngredients.oliveOil]

    func testHitsPRDExampleWithinFivePercent() throws {
        let plan = try MacroSolver.solve(ingredients: staples, targets: targets)
        for result in plan.results {
            XCTAssertTrue(result.isWithinMargin, "\(result.kind) off by \(result.relativeError ?? .nan)")
        }
        XCTAssertTrue(plan.isWithinMargin)
        XCTAssertTrue(plan.suggestions.isEmpty)
    }

    func testAllSevenStaplesWithinFivePercent() throws {
        let plan = try MacroSolver.solve(ingredients: SeedIngredients.all, targets: targets)
        XCTAssertTrue(plan.isWithinMargin)
    }

    func testWeightsAreNonNegativeAndRoundedToFiveGrams() throws {
        let plan = try MacroSolver.solve(ingredients: SeedIngredients.all, targets: targets)
        for item in plan.items {
            XCTAssertGreaterThanOrEqual(item.grams, 0)
            XCTAssertEqual(item.grams.truncatingRemainder(dividingBy: 5), 0, accuracy: 1e-9)
        }
    }

    func testRespectsPortionLimits() throws {
        var broccoli = SeedIngredients.broccoli
        broccoli.minGrams = 200
        broccoli.maxGrams = 250
        var oil = SeedIngredients.oliveOil
        oil.maxGrams = 30
        let plan = try MacroSolver.solve(
            ingredients: [SeedIngredients.chickenBreast, SeedIngredients.whiteRice, broccoli, oil, SeedIngredients.avocado],
            targets: targets)
        let byID = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0.grams) })
        XCTAssertGreaterThanOrEqual(byID[broccoli.id]!, 200)
        XCTAssertLessThanOrEqual(byID[broccoli.id]!, 250)
        XCTAssertLessThanOrEqual(byID[oil.id]!, 30)
    }

    func testInfeasibleSelectionReturnsBestEffortWithSuggestions() throws {
        let plan = try MacroSolver.solve(ingredients: [SeedIngredients.chickenBreast], targets: targets)
        XCTAssertFalse(plan.isWithinMargin)
        XCTAssertGreaterThan(plan.recipe.count, 0)
        XCTAssertTrue(plan.suggestions.contains { $0.hasPrefix("Carbs are") })
    }

    func testCustomIngredientIsUsed() throws {
        let whey = Ingredient(name: "Whey Isolate", source: .custom,
                              macrosPer100g: Macros(protein: 90, carbs: 2, fat: 1))
        let plan = try MacroSolver.solve(ingredients: [whey, SeedIngredients.whiteRice, SeedIngredients.oliveOil],
                                         targets: targets)
        XCTAssertTrue(plan.isWithinMargin)
        XCTAssertGreaterThan(plan.items.first { $0.id == whey.id }!.grams, 0)
    }

    func testZeroCaloriesMeansCaloriesNotTracked() throws {
        let t = MacroTargets(calories: 0, protein: 180, carbs: 250, fat: 70)
        let plan = try MacroSolver.solve(ingredients: staples, targets: t)
        XCTAssertFalse(plan.results.contains { $0.kind == .calories })
        XCTAssertTrue(plan.isWithinMargin)
    }

    func testInconsistentTargetsProduceWarning() throws {
        let t = MacroTargets(calories: 1500, protein: 180, carbs: 250, fat: 70) // macros imply 2350
        XCTAssertFalse(t.isConsistent())
        let plan = try MacroSolver.solve(ingredients: staples, targets: t)
        XCTAssertTrue(plan.suggestions.first?.contains("2350 kcal") ?? false)
    }

    func testErrors() {
        XCTAssertThrowsError(try MacroSolver.solve(ingredients: [], targets: targets)) {
            XCTAssertEqual($0 as? SolverError, .noIngredients)
        }
        XCTAssertThrowsError(try MacroSolver.solve(ingredients: staples,
                                                   targets: MacroTargets(calories: 0, protein: 0, carbs: 0, fat: 0)))
        var bad = SeedIngredients.broccoli
        bad.minGrams = 300
        bad.maxGrams = 100
        XCTAssertThrowsError(try MacroSolver.solve(ingredients: [bad], targets: targets)) {
            XCTAssertEqual($0 as? SolverError, .invalidBounds(ingredient: bad.name))
        }
    }
}
