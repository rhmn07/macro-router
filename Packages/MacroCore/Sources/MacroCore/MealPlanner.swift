import Foundation

/// Splits a day into meals (breakfast, lunch, optional snack, dinner), each built from foods that suit it.
///
/// 1. Each food gets the meals it suits (`Ingredient.suitableMeals`: eggs at any main meal, oats at
///    breakfast, yogurt and fruit at breakfast or snack, meat and rice at lunch/dinner, ...). The user
///    can override this in the food editor. Foods the diet settings rule out are dropped.
/// 2. Variety: lunch/dinner proteins and dense carbs (rice, pasta: 40 g+ carbs per 100 g) rotate. With
///    two, they alternate between lunch and dinner and swap every day. With three or more, each day
///    uses the next pair, so a week cycles through all of them. Watery carbs (soup), vegetables and fats
///    stay flexible.
/// 3. A main meal with no protein food that suits it (e.g. breakfast when only chicken and rice are
///    selected) borrows the proteins and carbs of the other meals. A meal that has a protein but no
///    carb doesn't borrow: its share of carbs moves to the other meals. Same for fat. A snack with no
///    snack foods is skipped and its share goes to the other meals.
/// 4. Every food in the day's rotation gets a "home" meal where it must appear in a real amount
///    (30 g, 5 g of oil, or one piece), so nothing the user picked is silently dropped.
/// 5. Each meal is solved with `MacroSolver.optimize` against its share of the day, then solved again
///    without crumb-sized amounts. Foods eaten in pieces (bread, eggs) are fixed to whole pieces.
///    Meals already eaten are kept as they are and the rest of the day is planned around them.
public enum MealPlanner {
    /// Meals with the default settings.
    public static var slots: [MealSlot] { PlannerSettings().slots }

    /// Largest amount of one food in one meal when the user set no limit, so no meal asks for
    /// 1 kg of soup or a whole loaf of bread.
    static func maxServing(_ ingredient: Ingredient, slot: MealSlot = .lunch) -> Double {
        if let piece = ingredient.pieceSize { return Double(piece.maxPerMeal) * piece.grams }
        if slot == .snack { return 250 }
        return ingredient.isVegetable ? 400 : 500
    }

    /// Smallest amount that counts as "using" a food in a meal.
    static func minServing(_ ingredient: Ingredient) -> Double {
        if let piece = ingredient.pieceSize { return min(piece.grams, ingredient.maxGrams ?? .infinity) }
        let serving = ingredient.macrosPer100g.fat >= 50 ? 5.0 : 30.0
        return min(serving, ingredient.maxGrams ?? .infinity)
    }

    /// Lunch/dinner main of a category (step 2): a protein, or a carb with 40 g+ per 100 g.
    static func isRotatingMain(_ ing: Ingredient, _ category: IngredientCategory, allowed: Set<MealSlot>) -> Bool {
        let dense = category == .protein || ing.macrosPer100g.carbs >= 40
        return ing.meals == nil && !ing.isVegetable && ing.category == category && dense
            && allowed.isSuperset(of: [.lunch, .dinner])
    }

    /// Which meals each ingredient may appear in on a given day after steps 1–3.
    static func allowedMeals(for ingredients: [Ingredient], slots: [MealSlot] = MealPlanner.slots, day: Int = 0) -> [Set<MealSlot>] {
        var allowed = ingredients.map { $0.suitableMeals.intersection(slots) }

        // Step 2: rotate lunch/dinner mains.
        for category in [IngredientCategory.protein, .carb] {
            let mains = ingredients.indices.filter { isRotatingMain(ingredients[$0], category, allowed: allowed[$0]) }
            guard mains.count >= 2 else { continue }
            let n = mains.count
            if n == 2 {
                for (k, i) in mains.enumerated() {
                    let keep: MealSlot = (k + day) % 2 == 0 ? .lunch : .dinner
                    allowed[i].subtract([.lunch, .dinner])
                    allowed[i].insert(keep)
                }
            } else {
                let lunchIndex = (2 * day) % n
                let dinnerIndex = (2 * day + 1) % n
                for (k, i) in mains.enumerated() {
                    allowed[i].subtract([.lunch, .dinner])
                    if k == lunchIndex { allowed[i].insert(.lunch) }
                    if k == dinnerIndex { allowed[i].insert(.dinner) }
                }
            }
        }

        // Step 3: a main meal without any protein food borrows the other meals' proteins and carbs.
        let proteins = ingredients.indices.filter { isSource(ingredients[$0], of: .protein) }
        let carbs = ingredients.indices.filter { isSource(ingredients[$0], of: .carbs) }
        for slot in slots where slot != .snack {
            if !proteins.isEmpty && !proteins.contains(where: { allowed[$0].contains(slot) }) {
                // Prefer the foods in today's rotation, so borrowing doesn't undo it.
                let inRotation = proteins.filter { !allowed[$0].isEmpty }
                for i in (inRotation.isEmpty ? proteins : inRotation) { allowed[i].insert(slot) }
                let carbsInRotation = carbs.filter { !allowed[$0].isEmpty }
                for i in (carbsInRotation.isEmpty ? carbs : carbsInRotation) { allowed[i].insert(slot) }
            }
            // A meal with no food at all gets everything.
            if !allowed.contains(where: { $0.contains(slot) }) {
                for i in allowed.indices { allowed[i].insert(slot) }
            }
        }
        return allowed
    }

    /// Whether a food is a real source of a macro (vegetables don't count as carb sources).
    static func isSource(_ ingredient: Ingredient, of kind: MacroKind) -> Bool {
        let m = ingredient.macrosPer100g
        switch kind {
        case .protein: return ingredient.category == .protein
        case .carbs: return ingredient.category == .carb && !ingredient.isVegetable
        case .fat: return ingredient.category == .fat || m.fat >= 10
        case .calories: return true
        }
    }

    /// Each meal's target. A meal with no source of a macro gets none of it, and the other meals
    /// split its share in proportion to their usual shares. Calories follow the macros.
    static func mealTargets(ingredients: [Ingredient], allowed: [Set<MealSlot>], daily: Macros,
                            slots: [MealSlot], settings: PlannerSettings) -> [MealSlot: Macros] {
        func baseShare(_ slot: MealSlot) -> Double { max(settings.share(of: slot), 0.0001) }
        var share: [MacroKind: [MealSlot: Double]] = [:]
        for kind in [MacroKind.protein, .carbs, .fat] {
            var raw: [MealSlot: Double] = [:]
            for slot in slots {
                let has = ingredients.indices.contains { allowed[$0].contains(slot) && isSource(ingredients[$0], of: kind) }
                raw[slot] = has ? baseShare(slot) : 0
            }
            let total = raw.values.reduce(0, +)
            let fallbackTotal = slots.map(baseShare).reduce(0, +)
            share[kind] = total > 0
                ? raw.mapValues { $0 / total }
                : Dictionary(uniqueKeysWithValues: slots.map { ($0, baseShare($0) / fallbackTotal) })
        }
        let dailyEnergy = 4 * daily.protein + 4 * daily.carbs + 9 * daily.fat
        var result: [MealSlot: Macros] = [:]
        for slot in slots {
            let p = daily.protein * share[.protein]![slot]!
            let c = daily.carbs * share[.carbs]![slot]!
            let f = daily.fat * share[.fat]![slot]!
            let energyShare = dailyEnergy > 0 ? (4 * p + 4 * c + 9 * f) / dailyEnergy : 1 / Double(slots.count)
            result[slot] = Macros(protein: p, carbs: c, fat: f, calories: daily.calories * energyShare)
        }
        return result
    }

    /// One day of meals.
    /// - Parameters:
    ///   - day: day number in a week plan; drives the rotation of mains.
    ///   - eaten: meals already eaten today. They're kept as they are and the other meals are planned
    ///     to cover what's left of the day.
    public static func solve(ingredients allIngredients: [Ingredient],
                             targets: MacroTargets,
                             settings: PlannerSettings = PlannerSettings(),
                             day: Int = 0,
                             eaten: [PlannedMeal] = [],
                             options: SolverOptions = SolverOptions(),
                             now: Date = Date()) throws -> MealPlan {
        let ingredients = allIngredients.filter(settings.allows)
        guard !ingredients.isEmpty || !eaten.isEmpty else { throw SolverError.noIngredients }
        guard targets.isValid else { throw SolverError.invalidTargets }
        for ing in ingredients {
            let lo = ing.minGrams ?? 0
            let hi = ing.maxGrams ?? options.defaultMaxGrams
            guard lo >= 0, hi >= lo, lo.isFinite, hi.isFinite else {
                throw SolverError.invalidBounds(ingredient: ing.name)
            }
        }

        // A slightly stronger pull toward smaller amounts than the daily solver uses: per meal it keeps
        // watery foods (soup, vegetables) from taking over when a denser food can do the job.
        var options = options
        options.ridge = max(options.ridge, 0.002)

        let eatenSlots = Set(eaten.map(\.slot))
        var slots = settings.slots.filter { !eatenSlots.contains($0) }
        let eatenMacros = eaten.reduce(Macros.zero) { $0 + $1.macros }
        let remaining = Macros(protein: max(Double(targets.protein) - eatenMacros.protein, 0),
                               carbs: max(Double(targets.carbs) - eatenMacros.carbs, 0),
                               fat: max(Double(targets.fat) - eatenMacros.fat, 0),
                               calories: max(Double(targets.calories) - eatenMacros.calories, 0))

        var allowed = allowedMeals(for: ingredients, slots: slots, day: day)
        // A snack with nothing snack-like is skipped.
        if slots.contains(.snack) && !allowed.contains(where: { $0.contains(.snack) }) {
            slots.removeAll { $0 == .snack }
        }
        allowed = allowed.map { $0.intersection(slots) }
        let perMeal = mealTargets(ingredients: ingredients, allowed: allowed, daily: remaining,
                                  slots: slots, settings: settings)

        // Step 4: pick each food's home meal, spreading foods of the same category across meals.
        var home = [MealSlot?](repeating: nil, count: ingredients.count)
        var load: [MealSlot: [IngredientCategory: Int]] = [:]
        for i in ingredients.indices {
            let choices = slots.filter { allowed[i].contains($0) }
            let category = ingredients[i].category
            let pick = choices.min { a, b in
                let la = load[a]?[category] ?? 0, lb = load[b]?[category] ?? 0
                return la != lb ? la < lb : settings.share(of: a) > settings.share(of: b)
            }
            home[i] = pick
            if let pick { load[pick, default: [:]][category, default: 0] += 1 }
        }

        // Step 5: solve each meal. A second pass drops crumbs (e.g. 2 g of oil) that aren't the food's
        // home meal and solves again, so every portion is a real amount.
        let tracksCalories = targets.calories > 0
        var gramsBySlot: [MealSlot: [Int: Double]] = [:]
        for slot in slots {
            var members = ingredients.indices.filter { allowed[$0].contains(slot) }
            for pass in 0..<2 {
                guard !members.isEmpty else { break }
                var lower: [Double] = []
                var upper: [Double] = []
                for i in members {
                    let ing = ingredients[i]
                    let mealsForFood = Double(max(allowed[i].count, 1))
                    // Daily limits are shared evenly between the meals a food can be in.
                    var lo = (ing.minGrams ?? 0) / mealsForFood
                    let hi = min(ing.maxGrams.map { $0 / mealsForFood } ?? .infinity, maxServing(ing, slot: slot))
                    if home[i] == slot { lo = max(lo, minServing(ing)) }
                    lower.append(min(lo, hi))
                    upper.append(hi)
                }
                let target = perMeal[slot]!
                let foods = members.map { ingredients[$0] }
                var grams = MacroSolver.optimize(ingredients: foods, lowerGrams: lower, upperGrams: upper,
                                                 target: target, tracksCalories: tracksCalories, options: options)
                // Foods eaten in pieces (bread, eggs) are fixed to whole pieces, then the rest is solved
                // again around them so the meal still adds up.
                var pieceGrams: [Int: Double] = [:]
                for (j, ing) in foods.enumerated() {
                    guard let piece = ing.pieceSize, piece.grams > 0 else { continue }
                    let maxPieces = Int((upper[j] / piece.grams).rounded(.down))
                    let minPieces = Int((lower[j] / piece.grams).rounded(.up))
                    let count = min(max(Int((grams[j] / piece.grams).rounded()), minPieces), maxPieces)
                    pieceGrams[j] = Double(max(count, 0)) * piece.grams
                }
                if !pieceGrams.isEmpty {
                    var lo = lower, hi = upper
                    for (j, g) in pieceGrams { lo[j] = g; hi[j] = g }
                    grams = MacroSolver.optimize(ingredients: foods, lowerGrams: lo, upperGrams: hi,
                                                 target: target, tracksCalories: tracksCalories, options: options)
                }
                var result: [Int: Double] = [:]
                var crumbs: Set<Int> = []
                for (j, i) in members.enumerated() {
                    var g = MealSplit.roundPortion(grams[j])
                    g = min(max(g, lower[j].rounded(.up)), upper[j])
                    if let fixed = pieceGrams[j] { g = fixed }
                    if g >= 1 { result[i] = g }
                    if g < minServing(ingredients[i]) && home[i] != slot && lower[j] == 0 && pieceGrams[j] == nil { crumbs.insert(i) }
                }
                gramsBySlot[slot] = result
                if pass == 0 && !crumbs.isEmpty {
                    members.removeAll { crumbs.contains($0) }
                } else {
                    break
                }
            }
        }

        let solved: [MealSlot: PlannedMeal] = Dictionary(uniqueKeysWithValues: slots.map { slot in
            (slot, PlannedMeal(slot: slot, items: (gramsBySlot[slot] ?? [:])
                .map { PlanItem(ingredient: ingredients[$0.key], grams: $0.value) }
                .sorted { $0.grams > $1.grams }))
        })
        let eatenBySlot = Dictionary(eaten.map { ($0.slot, $0) }, uniquingKeysWith: { a, _ in a })
        let meals = settings.slots.compactMap { eatenBySlot[$0] ?? solved[$0] }
            + eaten.filter { !settings.slots.contains($0.slot) }

        // Daily totals per food: every selected food, plus anything only in an eaten meal.
        var totals: [String: (Ingredient, Double)] = [:]
        var order: [String] = []
        for ing in ingredients where totals[ing.id] == nil {
            totals[ing.id] = (ing, 0)
            order.append(ing.id)
        }
        for meal in meals {
            for item in meal.items {
                if totals[item.ingredient.id] == nil { order.append(item.ingredient.id) }
                totals[item.ingredient.id] = (item.ingredient, (totals[item.ingredient.id]?.1 ?? 0) + item.grams)
            }
        }
        let daily = order.map { PlanItem(ingredient: totals[$0]!.0, grams: totals[$0]!.1) }
        return MealPlan(createdAt: now, targets: targets, items: daily,
                        marginOfError: options.marginOfError, meals: meals)
    }
}
