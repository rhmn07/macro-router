import SwiftUI
import MacroCore

struct PantryView: View {
    @Environment(AppState.self) private var app
    @State private var showingSearch = false
    @State private var editing: EditorTarget?

    var body: some View {
        NavigationStack {
            List {
                let gaps = PantryCheck.gaps(selected: app.selectedIngredients, pantry: app.data.pantry,
                                            targets: app.data.targets, settings: app.settings)
                if !gaps.isEmpty {
                    Section {
                        ForEach(gaps) { gap in
                            GapRow(gap: gap) { food in
                                withAnimation {
                                    if app.contains(food) { app.setSelected(food, true) } else { app.upsert(food) }
                                }
                            }
                        }
                    } header: {
                        SectionTitle(emoji: "⚠️", title: "Before you plan")
                    } footer: {
                        Text("Checked with a trial plan of your picked foods and targets.")
                    }
                }

                ForEach(IngredientCategory.allCases) { category in
                    let foods = app.data.pantry
                        .filter { $0.category == category }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if !foods.isEmpty {
                        Section {
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
                        } header: {
                            CategoryHeader(category: category,
                                           selected: foods.filter { app.isSelected($0) }.count,
                                           total: foods.count)
                        }
                    }
                }

                Section {
                    Button { showingSearch = true } label: {
                        ActionRow(title: "Search foods", subtitle: "USDA database", symbol: "magnifyingglass", color: Theme.cyan)
                    }
                    Button { editing = .new } label: {
                        ActionRow(title: "Add a custom food", subtitle: "From a nutrition label", symbol: "square.and.pencil", color: MacroKind.calories.color)
                    }
                    if SeedIngredients.all.contains(where: { !app.contains($0) }) {
                        Button { app.restoreStaples() } label: {
                            ActionRow(title: "Restore default staples", subtitle: nil, symbol: "arrow.counterclockwise", color: .gray)
                        }
                    }
                } footer: {
                    Text("Macros are per 100 g. Tap a food to include it this week. Swipe left to edit portion limits or delete it.")
                }
            }
            .themedList()
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingSearch = true } label: { Label("Search foods", systemImage: "magnifyingglass") }
                        Button { editing = .new } label: { Label("Custom food", systemImage: "square.and.pencil") }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
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
            Label(count == 0 ? "Select foods to plan your week" : "Plan my week · \(count) foods",
                  systemImage: "wand.and.stars")
                .contentTransition(.numericText())
        }
        .buttonStyle(GradientButtonStyle())
        .disabled(count == 0)
        .animation(.snappy, value: count)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

private struct CategoryHeader: View {
    let category: IngredientCategory
    let selected: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(category.emoji)
            Text(category.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            Text("\(selected)/\(total) picked")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(category.color.opacity(0.14), in: Capsule())
                .textCase(nil)
        }
    }
}

private struct ActionRow: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(Color(.label))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Color(.secondaryLabel))
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

struct IngredientRow: View {
    let ingredient: Ingredient
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                EmojiBadge(ingredient: ingredient)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(ingredient.name)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        if ingredient.source == .custom {
                            Text("Custom")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    MacroPills(macros: ingredient.macrosPer100g)
                    if let limits = MacroFormat.limits(ingredient) {
                        Label(limits, systemImage: "ruler")
                            .font(.caption)
                            .foregroundStyle(Theme.cyan)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
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

/// One macro the picked foods can't reach, with a one-tap fix.
private struct GapRow: View {
    let gap: MacroGap
    let add: (Ingredient) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: gap.kind.symbol, color: gap.kind.color)
            VStack(alignment: .leading, spacing: 6) {
                Text(gap.headline)
                    .font(.subheadline.weight(.semibold))
                Text(gap.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let food = gap.suggestion {
                    Button { add(food) } label: {
                        Label("Add \(food.shortName.lowercased())", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(gap.kind.color)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
