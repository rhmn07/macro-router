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
                    numberField("Minimum", unit: "g/day", value: $minGrams, symbol: "arrow.down.to.line", color: Theme.teal, placeholder: "none")
                    numberField("Maximum", unit: "g/day", value: $maxGrams, symbol: "arrow.up.to.line", color: Theme.teal, placeholder: "none")
                } header: {
                    Text("Daily portion limits (optional)")
                } footer: {
                    Text("Keeps the plan realistic, e.g. at most 300 g broccoli or at least 100 g egg whites.")
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

    private func save() {
        let macros = Macros(protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, calories: calories)
        var ingredient = original ?? Ingredient(name: name, source: .custom, macrosPer100g: macros)
        ingredient.name = name.trimmingCharacters(in: .whitespaces)
        ingredient.macrosPer100g = macros
        ingredient.minGrams = minGrams
        ingredient.maxGrams = maxGrams
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
