import SwiftUI
import MacroCore

struct CurrentPlanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if let week = app.data.currentWeek {
                    WeekPlanView(week: week, isCurrent: true)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                if app.isSaved(week) {
                                    Label("Saved", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(Theme.success)
                                } else {
                                    Button { withAnimation { app.save(week) } } label: {
                                        Label("Save", systemImage: "bookmark.fill")
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                            }
                        }
                } else {
                    EmptyStateView(emoji: "🍽️",
                                   title: "No plan yet",
                                   message: "Set your targets, pick foods in the Pantry, then tap Generate to plan your week.") {
                        Button {
                            app.selectedTab = .pantry
                        } label: {
                            Label("Go to Pantry", systemImage: "basket.fill")
                        }
                        .buttonStyle(GradientButtonStyle())
                        .frame(maxWidth: 240)
                    }
                }
            }
            .background(ThemedBackground())
            .navigationTitle("Plan")
        }
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if app.savedWeeks.isEmpty && app.data.plans.isEmpty {
                    EmptyStateView(emoji: "📚",
                                   title: "No saved plans",
                                   message: "Weeks you save from the Plan tab show up here.") { EmptyView() }
                } else {
                    List {
                        if !app.savedWeeks.isEmpty {
                            Section {
                                ForEach(app.savedWeeks) { week in
                                    NavigationLink {
                                        WeekPlanView(week: week, isCurrent: false)
                                            .navigationTitle("Week of " + week.startDate.formatted(.dateTime.month().day()))
                                            .navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        WeekHistoryRow(week: week)
                                    }
                                }
                                .onDelete { offsets in
                                    offsets.map { app.savedWeeks[$0] }.forEach(app.delete)
                                }
                            } header: {
                                SectionTitle(emoji: "🗓️", title: "Weeks")
                            }
                        }
                        if !app.data.plans.isEmpty {
                            Section {
                                ForEach(app.data.plans) { plan in
                                    NavigationLink {
                                        PlanContent(plan: plan)
                                            .navigationTitle(plan.createdAt.formatted(date: .abbreviated, time: .omitted))
                                            .navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        HistoryRow(plan: plan)
                                    }
                                }
                                .onDelete { offsets in
                                    offsets.map { app.data.plans[$0] }.forEach(app.delete)
                                }
                            } header: {
                                SectionTitle(emoji: "📄", title: "Older single-day plans")
                            }
                        }
                    }
                    .themedList()
                }
            }
            .background(ThemedBackground())
            .navigationTitle("History")
        }
    }
}

private struct WeekHistoryRow: View {
    let week: WeekPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Week of " + week.startDate.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)
            Text("\(week.days.count) days · \(week.targets.calories.formatted()) kcal a day")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(GroceryList.items(for: week.days).prefix(6).map(\.ingredient.emoji).joined())
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct HistoryRow: View {
    let plan: MealPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.createdAt.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.headline)
                    Text(plan.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(ok: plan.isWithinMargin)
            }
            MacroPills(macros: plan.achieved)
            HStack(spacing: 2) {
                Text(plan.recipe.map(\.ingredient.emoji).joined())
                Text(plan.recipe.map(\.ingredient.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

/// Shared body for the current plan and saved plans.
/// Order: breakfast, lunch, dinner; then how close the day gets; then the shopping list.
struct PlanContent: View {
    let plan: MealPlan
    @State private var days = 5

    /// Plans saved before meals existed show their daily totals as one card.
    private var meals: [PlannedMeal] {
        plan.meals ?? [PlannedMeal(slot: .lunch, items: plan.recipe)]
    }

    var body: some View {
        List {
            ForEach(meals) { meal in
                Section {
                    ForEach(meal.items) { item in
                        PortionRow(item: item)
                    }
                    if meal.items.isEmpty {
                        Text("Nothing planned for this meal.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    MealHeader(meal: meal, isWholeDay: plan.meals == nil)
                }
            }

            if !plan.unusedIngredients.isEmpty {
                Section {
                } footer: {
                    Text("Not used: \(plan.unusedIngredients.map(\.name).joined(separator: ", ")). Check its portion limits in the Pantry.")
                }
            }

            Section {
                PlanSummaryCard(plan: plan)
            } header: {
                SectionTitle(emoji: "🎯", title: "How close the day gets")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if !plan.suggestions.isEmpty {
                Section {
                    ForEach(plan.suggestions, id: \.self) { hint in
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "lightbulb.fill", color: MacroKind.carbs.color, size: 26)
                            Text(hint).font(.subheadline)
                        }
                    }
                } header: {
                    SectionTitle(emoji: "💡", title: "Tips")
                }
            }

            Section {
                Stepper(value: $days, in: 1...14) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "calendar", color: Theme.cyan)
                        Text("Shop for **\(days)** \(days == 1 ? "day" : "days")")
                            .contentTransition(.numericText())
                    }
                }
                ForEach(GroceryList.items(for: plan, days: days)) { item in
                    GroceryRow(item: item)
                }
                ShareLink(item: GroceryList.shareText(for: plan, days: days)) {
                    Label("Share plan & grocery list", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GradientButtonStyle())
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                .listRowBackground(Color.clear)
            } header: {
                SectionTitle(emoji: "🛒", title: "Grocery list")
            } footer: {
                Text("Package sizes are typical US sizes. If yours differ, change them under Pantry > swipe a food > Edit.")
            }
            .animation(.snappy, value: days)
        }
        .themedList()
    }
}

/// "🍳 Breakfast" with the meal's calories and macros.
struct MealHeader: View {
    let meal: PlannedMeal
    let isWholeDay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(isWholeDay ? "📋" : meal.slot.emoji)
                Text(isWholeDay ? "Whole day" : meal.slot.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(meal.macros.calories.rounded()).formatted()) kcal")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MacroKind.calories.color)
            }
            MacroPills(macros: meal.macros, showCalories: false)
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

/// One food in a meal: how much to weigh, and how to weigh it.
struct PortionRow: View {
    let item: PlanItem

    var body: some View {
        HStack(spacing: 12) {
            EmojiBadge(ingredient: item.ingredient)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.ingredient.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let howTo = howToWeigh {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "scalemass")
                        Text(howTo)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                // Bread, eggs, tortillas: "3 slices", with the weight underneath.
                Text(item.pieceText ?? GroceryList.formatWeight(grams: item.grams))
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(item.ingredient.category.color)
                if item.pieceText != nil {
                    Text(GroceryList.formatWeight(grams: item.grams))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    /// e.g. "Weigh dry · about 270 g cooked"
    private var howToWeigh: String? {
        guard let instruction = item.ingredient.weighingState.instruction else { return nil }
        var text = instruction.prefix(1).uppercased() + instruction.dropFirst()
        if let cooked = item.approximateCookedGrams {
            text += " · about \(GroceryList.formatWeight(grams: cooked)) cooked"
        }
        return text
    }
}

/// "3 packs  Ground beef" with the package size underneath.
struct GroceryRow: View {
    let item: GroceryItem

    var body: some View {
        HStack(spacing: 12) {
            EmojiBadge(ingredient: item.ingredient, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(item.quantityText)
                .font(.body.monospacedDigit().bold())
                .foregroundStyle(Theme.cyan)
                .contentTransition(.numericText())
                .fixedSize()
        }
    }

    /// e.g. "16 oz pack · you'll use 1.52 kg"
    private var detail: String {
        guard let package = item.package else { return "Package size unknown, set it in the Pantry" }
        return "\(package.sizeText) · you'll use \(item.formattedWeight)"
    }
}

/// Rings for each macro, how far off each one is, and an overall status.
struct PlanSummaryCard: View {
    let plan: MealPlan

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: plan.isWithinMargin ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                Text(plan.isWithinMargin
                     ? "Hits all your targets (within ±\(Int(plan.marginOfError * 100))%)"
                     : "Close, but some targets are off by more than \(Int(plan.marginOfError * 100))%")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background((plan.isWithinMargin ? Theme.success : Color.orange).gradient, in: Capsule())

            HStack(spacing: 10) {
                ForEach(plan.results) { result in
                    VStack(spacing: 6) {
                        MacroRing(kind: result.kind, achieved: result.achieved, target: result.target)
                            .frame(width: 66, height: 66)
                        Text(result.kind.displayName)
                            .font(.caption.weight(.semibold))
                        Text("of \(Int(result.target.rounded()))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let error = result.relativeError {
                            Text(error.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always())))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(result.isWithinMargin ? Theme.success : .orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((result.isWithinMargin ? Theme.success : Color.orange).opacity(0.14), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("Daily total vs. your targets")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }
}

struct SectionTitle: View {
    let emoji: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }
}

/// Big emoji, title, message and an optional action, for empty screens.
struct EmptyStateView<Actions: View>: View {
    let emoji: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    @State private var bounce = false

    var body: some View {
        VStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 72))
                .padding(26)
                .background(Theme.brandGradient.opacity(0.18), in: Circle())
                .scaleEffect(bounce ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.55), value: bounce)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            actions
                .padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { bounce = true }
    }
}

struct StatusBadge: View {
    let ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Theme.success : .orange)
            .accessibilityLabel(ok ? "Within target" : "Off target")
    }
}
