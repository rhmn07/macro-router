import Foundation

public struct SolverOptions: Sendable {
    /// Allowed relative error per macro (PRD: 5%).
    public var marginOfError: Double = 0.05
    /// Weights are rounded to this many grams for a recipe you can actually measure.
    public var roundingStep: Double = 5
    /// Upper limit for an ingredient that has no `maxGrams` set.
    public var defaultMaxGrams: Double = 2000
    /// Small L2 penalty. It spreads grams across similar foods instead of picking one arbitrarily,
    /// and keeps the problem well conditioned when foods are near-duplicates.
    public var ridge: Double = 1e-4
    public var maxIterations: Int = 20_000
    public var tolerance: Double = 1e-9

    public init() {}
}

public enum SolverError: Error, Equatable, LocalizedError {
    case noIngredients
    case invalidTargets
    case invalidBounds(ingredient: String)

    public var errorDescription: String? {
        switch self {
        case .noIngredients: return "Select at least one ingredient."
        case .invalidTargets: return "Enter your daily targets first."
        case .invalidBounds(let name): return "The min/max limits for \(name) are invalid (min must be ≤ max and not negative)."
        }
    }
}

/// Finds the grams of each ingredient that get closest to the daily targets.
///
/// Formulation: box-constrained weighted least squares
///
///     minimize   Σ_k ((A x - t)_k / t_k)²  +  ridge·|x|²
///     subject to min_i ≤ x_i ≤ max_i
///
/// where the rows k are protein, carbs, fat and calories, and each row is divided by its target
/// so that every macro is measured in *relative* error. Unlike a strict LP feasibility problem,
/// this always returns the best compromise. When the selected foods can't hit the targets
/// (e.g. only chicken but a 250 g carb goal), the plan reports which macros miss instead of
/// failing outright.
///
/// It is solved with cyclic coordinate descent. The objective is a convex quadratic, so each
/// coordinate step is an exact 1-D minimization clamped to its bounds, and the method converges
/// to the global optimum. With 4 rows and a handful of foods it finishes in well under a millisecond.
public enum MacroSolver {

    public static func solve(ingredients: [Ingredient],
                             targets: MacroTargets,
                             options: SolverOptions = SolverOptions(),
                             now: Date = Date()) throws -> MealPlan {
        guard !ingredients.isEmpty else { throw SolverError.noIngredients }
        guard targets.isValid else { throw SolverError.invalidTargets }

        let tracksCalories = targets.calories > 0
        var lower: [Double] = []
        var upper: [Double] = []
        for ing in ingredients {
            let lo = ing.minGrams ?? 0
            let hi = ing.maxGrams ?? options.defaultMaxGrams
            guard lo >= 0, hi >= lo, lo.isFinite, hi.isFinite else {
                throw SolverError.invalidBounds(ingredient: ing.name)
            }
            lower.append(lo)
            upper.append(hi)
        }

        let grams = optimize(ingredients: ingredients, lowerGrams: lower, upperGrams: upper,
                             target: targets.macros, tracksCalories: tracksCalories, options: options)
        let items: [PlanItem] = ingredients.enumerated().map { i, ing in
            let rounded = Self.round(grams[i], step: options.roundingStep)
            return PlanItem(ingredient: ing, grams: min(max(rounded, lower[i]), upper[i]))
        }

        return MealPlan(createdAt: now,
                        targets: targets,
                        items: items,
                        marginOfError: options.marginOfError)
    }

    /// Core optimizer: grams of each ingredient (unrounded) that best match `target` within the bounds.
    /// Used for a whole day by `solve` and for each meal by `MealPlanner`.
    static func optimize(ingredients: [Ingredient],
                         lowerGrams: [Double],
                         upperGrams: [Double],
                         target: Macros,
                         tracksCalories: Bool,
                         options: SolverOptions) -> [Double] {
        let n = ingredients.count
        guard n > 0 else { return [] }
        // A macro with a zero target is ignored rather than pushed to zero: a meal planned with no carbs
        // (only egg whites available at breakfast) shouldn't be starved over their 0.7 g of carbs.
        let kinds: [MacroKind] = (tracksCalories ? [.protein, .carbs, .fat, .calories] : [.protein, .carbs, .fat])
            .filter { target[$0] >= 1 }
        guard !kinds.isEmpty else { return lowerGrams }

        // Variables are in units of 100 g so all coefficients are on a similar scale.
        let lower = lowerGrams.map { $0 / 100 }
        let upper = upperGrams.map { $0 / 100 }

        // Scaled design matrix A (rows = macros, cols = foods) and target vector b.
        var a = [[Double]](repeating: [Double](repeating: 0, count: n), count: kinds.count)
        var b = [Double](repeating: 0, count: kinds.count)
        for (k, kind) in kinds.enumerated() {
            let t = target[kind]
            let scale = 1.0 / max(t, 1.0)
            b[k] = t * scale
            for i in 0..<n {
                a[k][i] = ingredients[i].macrosPer100g[kind] * scale
            }
        }

        // Diagonal of the Hessian (AᵀA + ridge·I).
        var hessianDiagonal = [Double](repeating: options.ridge, count: n)
        for i in 0..<n {
            for k in 0..<kinds.count { hessianDiagonal[i] += a[k][i] * a[k][i] }
        }

        // Start at the lower bounds; keep the residual r = A x - b updated incrementally.
        var x = lower
        var residual = [Double](repeating: 0, count: kinds.count)
        for k in 0..<kinds.count {
            var sum = 0.0
            for i in 0..<n { sum += a[k][i] * x[i] }
            residual[k] = sum - b[k]
        }

        for _ in 0..<options.maxIterations {
            var largestStep = 0.0
            for i in 0..<n {
                var gradient = options.ridge * x[i]
                for k in 0..<kinds.count { gradient += a[k][i] * residual[k] }
                let proposed = min(max(x[i] - gradient / hessianDiagonal[i], lower[i]), upper[i])
                let step = proposed - x[i]
                if step != 0 {
                    for k in 0..<kinds.count { residual[k] += a[k][i] * step }
                    x[i] = proposed
                    largestStep = max(largestStep, abs(step))
                }
            }
            if largestStep < options.tolerance { break }
        }
        return x.map { $0 * 100 }
    }

    static func round(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }
}
