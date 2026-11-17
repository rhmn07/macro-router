import XCTest
@testable import MacroCore

final class BodyProfileTests: XCTestCase {
    private func profile(_ sex: BiologicalSex = .male, age: Int = 30, cm: Double = 180, kg: Double = 80,
                         activity: ActivityLevel = .moderate, goal: WeightGoal = .maintain) -> BodyProfile {
        BodyProfile(sex: sex, age: age, heightCm: cm, weightKg: kg, activity: activity, goal: goal, usesMetric: true)
    }

    func testMifflinStJeor() {
        // 10·80 + 6.25·180 − 5·30 + 5 = 1780
        XCTAssertEqual(profile().bmr, 1780, accuracy: 0.001)
        // 10·60 + 6.25·165 − 5·25 − 161 = 1345.25
        XCTAssertEqual(profile(.female, age: 25, cm: 165, kg: 60).bmr, 1345.25, accuracy: 0.001)
    }

    func testMaintainTargets() {
        // 1780 × 1.55 = 2759 → 2760 kcal; protein 1.8·80 = 144; fat 2760·0.25/9 ≈ 77; carbs (2760 − 576 − 693)/4 ≈ 373
        XCTAssertEqual(profile().recommendedTargets(),
                       MacroTargets(calories: 2760, protein: 144, carbs: 373, fat: 77))
    }

    func testLoseTargets() {
        // 1345.25 × 1.375 × 0.8 ≈ 1480 kcal; protein 2.0·60 = 120; fat ≈ 41; carbs (1480 − 480 − 369)/4 ≈ 158
        let targets = profile(.female, age: 25, cm: 165, kg: 60, activity: .light, goal: .lose).recommendedTargets()
        XCTAssertEqual(targets, MacroTargets(calories: 1480, protein: 120, carbs: 158, fat: 41))
    }

    func testGainIsMoreThanMaintainIsMoreThanLose() {
        let lose = profile(goal: .lose).recommendedTargets().calories
        let maintain = profile(goal: .maintain).recommendedTargets().calories
        let gain = profile(goal: .gain).recommendedTargets().calories
        XCTAssertLessThan(lose, maintain)
        XCTAssertLessThan(maintain, gain)
    }

    func testTargetsAlwaysAddUp() {
        for sex in BiologicalSex.allCases {
            for goal in WeightGoal.allCases {
                for activity in ActivityLevel.allCases {
                    for kg in stride(from: 40.0, through: 250.0, by: 30) {
                        let targets = profile(sex, age: 40, cm: 170, kg: kg, activity: activity, goal: goal)
                            .recommendedTargets()
                        XCTAssertTrue(targets.isValid)
                        XCTAssertGreaterThan(targets.carbs, 0, "\(sex) \(goal) \(activity) \(kg) kg")
                        XCTAssertTrue(targets.isConsistent(), "\(targets) for \(kg) kg")
                    }
                }
            }
        }
    }

    func testCalorieFloor() {
        let tiny = profile(.female, age: 80, cm: 145, kg: 40, activity: .sedentary, goal: .lose)
        XCTAssertEqual(tiny.recommendedTargets().calories, 1200)
    }

    func testUnitConversions() {
        XCTAssertEqual(BodyUnits.pounds(fromKg: 80), 176.37, accuracy: 0.01)
        XCTAssertEqual(BodyUnits.kg(fromPounds: 176.37), 80, accuracy: 0.01)
        XCTAssertTrue(BodyUnits.feetAndInches(fromCm: 180) == (5, 11))
        XCTAssertEqual(BodyUnits.cm(feet: 5, inches: 11), 180.34, accuracy: 0.001)
    }
}
