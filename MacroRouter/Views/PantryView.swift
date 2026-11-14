import SwiftUI
import MacroCore

struct PantryView: View {
    @Environment(AppState.self) private var app
    @State private var showingSearch = false
    @State private var editing: EditorTarget?

    var body: some View {
        NavigationStack {
            List {
                ForEach(IngredientCategory.allCases) { category in
                    let foods = app.data.pantry
                        .filter { $0.category == category }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if !foods.isEmpty {
                        Section(category.displayName) {
                            ForEach(foods) { ingredient in
                                IngredientRow(ingredient: ingredient,
                                              isSelected: app.isSelected(ingredient)) {
                                    app.setSelected(ingredient, !app.isSelected(ingredient))
                                }
                                .swipeActions {
                                    Button(role: .destructive) { app.remove(ingredient) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { editing = .edit(ingredient) } label: {
                                        Label("Edit", systemImage: "slider.horizontal.3")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button { editing = .edit(ingredient) } label: {
                                        Label("Edit amounts & limits", systemImage: "slider.horizontal.3")
                                    }
                                    Button(role: .destructive) { app.remove(ingredient) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { showingSearch = true } label: {
                        Label("Search foods (USDA database)", systemImage: "magnifyingglass")
                    }
                    Button { editing = .new } label: {
                        Label("Add a custom food", systemImage: "square.and.pencil")
                    }
                    if SeedIngredients.all.contains(where: { !app.contains($0) }) {
                        Button { app.restoreStaples() } label: {
                            Label("Restore default staples", systemImage: "arrow.counterclockwise")
                        }
                    }
                } footer: {
                    Text("Tap a food to include it this week. Swipe left to edit portion limits or delete it.")
                }
            }
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingSearch = true } label: { Label("Search foods", systemImage: "magnifyingglass") }
                        Button { editing = .new } label: { Label("Custom food", systemImage: "square.and.pencil") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                GenerateBar()
            }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView()
            }
            .sheet(item: $editing) { target in
                IngredientEditorView(ingredient: target.ingredient) { edited in
                    app.upsert(edited, select: target.ingredient == nil || app.isSelected(edited))
                }
            }
        }
    }
}

enum EditorTarget: Identifiable {
    case new
    case edit(Ingredient)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let ingredient): return ingredient.id
        }
    }

    var ingredient: Ingredient? {
        if case .edit(let ingredient) = self { return ingredient }
        return nil
    }
}

private struct GenerateBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let count = app.data.selectedIDs.intersection(app.data.pantry.map(\.id)).count
        Button {
            app.generatePlan()
        } label: {
            Text(count == 0 ? "Select foods to generate a plan" : "Generate plan · \(count) foods")
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(count == 0)
        .padding()
        .background(.bar)
    }
}

struct IngredientRow: View {
    let ingredient: Ingredient
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.name)
                        .foregroundStyle(.primary)
                    Text(MacroFormat.per100g(ingredient.macrosPer100g))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let limits = MacroFormat.limits(ingredient) {
                        Text(limits)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                Spacer()
                if ingredient.source == .custom {
                    Text("Custom").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum MacroFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    static func per100g(_ m: Macros) -> String {
        "P \(number(m.protein)) · C \(number(m.carbs)) · F \(number(m.fat)) g · \(Int(m.calories.rounded())) kcal / 100 g"
    }

    static func limits(_ ingredient: Ingredient) -> String? {
        switch (ingredient.minGrams, ingredient.maxGrams) {
        case (nil, nil): return nil
        case (let min?, nil): return "At least \(Int(min)) g/day"
        case (nil, let max?): return "At most \(Int(max)) g/day"
        case (let min?, let max?): return "\(Int(min))–\(Int(max)) g/day"
        }
    }
}
