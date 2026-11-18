import SwiftUI
import MacroCore

/// Create a custom food, or edit any food's macros and daily portion limits.
struct IngredientEditorView: View {
    let original: Ingredient?
    let onSave: (Ingredient) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var calories: Double?
    @State private var minGrams: Double?
    @State private var maxGrams: Double?
    /// Nil = guess from the name.
    @State private var mealChoice: Set<MealSlot>?
    /// Nil = guess from the name.
    @State private var packageUnit: String?
    @State private var packageGrams: Double?

    init(ingredient: Ingredient?, onSave: @escaping (Ingredient) -> Void) {
        self.original = ingredient
        self.onSave = onSave
        if let ingredient {
            _name = State(initialValue: ingredient.name)
            _protein = State(initialValue: ingredient.macrosPer100g.protein)
            _carbs = State(initialValue: ingredient.macrosPer100g.carbs)
            _fat = State(initialValue: ingredient.macrosPer100g.fat)
            _calories = State(initialValue: ingredient.macrosPer100g.calories)
            _minGrams = State(initialValue: ingredient.minGrams)
            _maxGrams = State(initialValue: ingredient.maxGrams)
            _mealChoice = State(initialValue: ingredient.meals.map(Set.init))
            _packageUnit = State(initialValue: ingredient.package?.unit)
            _packageGrams = State(initialValue: ingredient.package?.grams)
        }
    }

    private var atwater: Double {
        Macros.atwaterCalories(protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
    }

    private var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a name." }
        let values = [protein, carbs, fat].compactMap { $0 }
        if values.isEmpty { return "Enter at least one macro." }
        if values.contains(where: { $0 < 0 }) { return "Macros can't be negative." }
        if values.reduce(0, +) > 100.5 { return "Protein + carbs + fat can't exceed 100 g per 100 g." }
        if let min = minGrams, let max = maxGrams, min > max { return "Minimum must be less than maximum." }
        if (minGrams ?? 0) < 0 || (maxGrams ?? 0) < 0 { return "Limits can't be negative." }
        if mealChoice?.isEmpty == true { return "Pick at least one meal." }
        if packageUnit != nil, (packageGrams ?? 0) <= 0 { return "Enter the package weight in grams." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (e.g. Greek Yogurt 0%)", text: $name)
                }
                Section {
                    numberField("Protein", unit: "g", value: $protein, kind: .protein)
                    numberField("Carbs", unit: "g", value: $carbs, kind: .carbs)
                    numberField("Fat", unit: "g", value: $fat, kind: .fat)
                    numberField("Calories", unit: "kcal", value: $calories, kind: .calories,
                                placeholder: Int(atwater.rounded()).formatted())
                } header: {
                    Text("Per 100 g")
                } footer: {
                    Text("Copy these from the nutrition label's “per 100 g” column. Leave calories empty to calculate them from the macros. For shopping, use the as-purchased (raw/dry) values.")
                }
                Section {
                    numberField("Minimum", unit: "g/day", value: $minGrams, symbol: "arrow.down.to.line", color: Theme.cyan, placeholder: "none")
                    numberField("Maximum", unit: "g/day", value: $maxGrams, symbol: "arrow.up.to.line", color: Theme.cyan, placeholder: "none")
                } header: {
                    Text("Daily portion limits (optional)")
                } footer: {
                    Text("Keeps the plan realistic, e.g. at most 300 g broccoli or at least 100 g egg whites.")
                }
                Section {
                    HStack(spacing: 8) {
                        ForEach(MealSlot.allCases) { slot in
                            MealChip(slot: slot, isOn: shownMeals.contains(slot)) { toggle(slot) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } header: {
                    Text("Meals")
                } footer: {
                    if mealChoice == nil {
                        Text("Guessed from the name. Tap to choose which meals this food can go in.")
                    } else {
                        Button("Reset to automatic") { mealChoice = nil }
                            .font(.footnote.weight(.semibold))
                    }
                }

                Section {
                    Picker(selection: unitBinding) {
                        Text("Not set").tag(String?.none)
                        ForEach(PackageSize.commonUnits, id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: "bag.fill", color: Theme.blue, size: 28)
                            Text("Sold as")
                        }
                    }
                    if let unit = shownPackage?.unit {
                        numberField(unit == "dozen" ? "Weight per dozen" : unit == "whole" ? "Weight of one" : "Weight per \(unit)",
                                    unit: "g", value: gramsBinding, symbol: "scalemass.fill", color: Theme.cyan,
                                    placeholder: shownPackage.map { Int($0.grams).formatted() } ?? "0")
                    }
                } header: {
                    Text("How it's sold")
                } footer: {
                    Text(packageUnit == nil && shownPackage != nil
                         ? "Guessed from the name. The grocery list uses this to count packs, e.g. 3 packs or 2 dozen."
                         : "The grocery list uses this to count packs, e.g. 3 packs or 2 dozen. Weight is on the label (1 lb = 454 g, 1 oz = 28 g).")
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .themedList()
            .navigationTitle(original == nil ? "Custom food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(validationMessage != nil)
                }
            }
        }
    }

    /// The food as currently typed, for name-based guesses.
    private var draft: Ingredient {
        Ingredient(name: name, source: .custom, macrosPer100g: Macros(protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0))
    }

    private var shownMeals: Set<MealSlot> { mealChoice ?? draft.guessedMeals }

    private func toggle(_ slot: MealSlot) {
        var meals = shownMeals
        if meals.contains(slot) { meals.remove(slot) } else { meals.insert(slot) }
        mealChoice = meals
    }

    private var shownPackage: PackageSize? {
        if let packageUnit { return PackageSize(unit: packageUnit, grams: packageGrams ?? 0) }
        return PackageSize.guess(for: draft)
    }

    private var unitBinding: Binding<String?> {
        Binding {
            shownPackage?.unit
        } set: { unit in
            let guessGrams = PackageSize.guess(for: draft)?.grams
            packageUnit = unit
            if unit != nil, packageGrams == nil { packageGrams = guessGrams }
            if unit == nil { packageGrams = nil }
        }
    }

    private var gramsBinding: Binding<Double?> {
        Binding {
            packageUnit == nil ? nil : packageGrams
        } set: { grams in
            if packageUnit == nil { packageUnit = shownPackage?.unit }
            packageGrams = grams
        }
    }

    private func save() {
        let macros = Macros(protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, calories: calories)
        var ingredient = original ?? Ingredient(name: name, source: .custom, macrosPer100g: macros)
        ingredient.name = name.trimmingCharacters(in: .whitespaces)
        ingredient.macrosPer100g = macros
        ingredient.minGrams = minGrams
        ingredient.maxGrams = maxGrams
        // Only store choices that differ from the name-based guess, so better guesses apply later.
        ingredient.meals = mealChoice.flatMap { $0 == draft.guessedMeals ? nil : MealSlot.allCases.filter($0.contains) }
        let chosenPackage = packageUnit.map { PackageSize(unit: $0, grams: packageGrams ?? 0) }
        ingredient.package = chosenPackage == PackageSize.guess(for: draft) ? nil : chosenPackage
        onSave(ingredient)
        dismiss()
    }

    private func numberField(_ title: String, unit: String, value: Binding<Double?>, kind: MacroKind,
                             placeholder: String = "0") -> some View {
        numberField(title, unit: unit, value: value, symbol: kind.symbol, color: kind.color, placeholder: placeholder)
    }

    private func numberField(_ title: String, unit: String, value: Binding<Double?>, symbol: String, color: Color,
                             placeholder: String = "0") -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color, size: 28)
            Text(title)
            Spacer()
            TextField(placeholder, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
        }
    }
}

/// Breakfast / Lunch / Dinner toggle.
private struct MealChip: View {
    let slot: MealSlot
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(slot.emoji).font(.title3)
                Text(slot.displayName).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
