import SwiftUI
import MacroCore

struct CurrentPlanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            Group {
                if let plan = app.currentPlan {
                    PlanContent(plan: plan)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                if app.isSaved(plan) {
                                    Label("Saved", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(Theme.green)
                                } else {
                                    Button { withAnimation { app.save(plan) } } label: {
                                        Label("Save", systemImage: "bookmark.fill")
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                            }
                        }
                } else {
                    EmptyStateView(emoji: "🍽️",
                                   title: "No plan yet",
                                   message: "Set your targets, pick foods in the Pantry, then tap Generate.") {
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
                if app.data.plans.isEmpty {
                    EmptyStateView(emoji: "📚",
                                   title: "No saved plans",
                                   message: "Plans you save from the Plan tab show up here.") { EmptyView() }
                } else {
                    List {
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
                    }
                    .themedList()
                }
            }
            .background(ThemedBackground())
            .navigationTitle("History")
        }
    }
}

private struct HistoryRow: View {
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
struct PlanContent: View {
    let plan: MealPlan
    @State private var days = 5

    var body: some View {
        List {
            Section {
                PlanSummaryCard(plan: plan)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                ForEach(plan.results) { result in
                    MacroResultRow(result: result)
                }
            } header: {
                SectionTitle(emoji: "🎯", title: "Daily totals")
            }

            if !plan.suggestions.isEmpty {
                Section {
                    ForEach(plan.suggestions, id: \.self) { hint in
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "lightbulb.fill", color: MacroKind.carbs.color, size: 26)
                            Text(hint).font(.subheadline)
                        }
                    }
                } header: {
                    SectionTitle(emoji: "💡", title: "Suggestions")
                }
            }

            Section {
                ForEach(plan.recipe) { item in
                    HStack(spacing: 12) {
                        EmojiBadge(ingredient: item.ingredient)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.ingredient.name)
                                .font(.body.weight(.medium))
                            MacroPills(macros: item.macros, showCalories: false)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(GroceryList.formatWeight(grams: item.grams))
                                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(item.ingredient.category.color)
                            Text("\(Int(item.macros.calories.rounded())) kcal")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(MacroKind.calories.color)
                        }
                        .fixedSize()
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                SectionTitle(emoji: "🍳", title: "Daily recipe")
            } footer: {
                if !plan.unusedIngredients.isEmpty {
                    Text("Not needed today: \(plan.unusedIngredients.map(\.name).joined(separator: ", ")).")
                }
            }

            Section {
                Stepper(value: $days, in: 1...14) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "calendar", color: Theme.teal)
                        Text("Prep for **\(days)** days")
                            .contentTransition(.numericText())
                    }
                }
                ForEach(GroceryList.items(for: plan, days: days)) { item in
                    HStack {
                        Image(systemName: "cart.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.teal)
                        Text(item.name)
                        Spacer()
                        Text(item.formattedWeight)
                            .font(.body.monospacedDigit().bold())
                            .contentTransition(.numericText())
                    }
                }
                ShareLink(item: GroceryList.shareText(for: plan, days: days)) {
                    Label("Share grocery list", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GradientButtonStyle())
                .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                .listRowBackground(Color.clear)
            } header: {
                SectionTitle(emoji: "🛒", title: "\(days)-day grocery list")
            }
            .animation(.snappy, value: days)
        }
        .themedList()
    }
}

/// Rings for each macro plus an overall status, at the top of a plan.
private struct PlanSummaryCard: View {
    let plan: MealPlan

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: plan.isWithinMargin ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                Text(plan.isWithinMargin
                     ? "All targets within ±\(Int(plan.marginOfError * 100))%"
                     : "Some targets are off by more than \(Int(plan.marginOfError * 100))%")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background((plan.isWithinMargin ? Theme.green : Color.orange).gradient, in: Capsule())

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
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
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

struct MacroResultRow: View {
    let result: MacroResult

    private var statusColor: Color { result.isWithinMargin ? Theme.green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: result.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(result.kind.color)
                    .frame(width: 18)
                Text(result.kind.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(result.achieved.rounded())) / \(Int(result.target.rounded())) \(result.kind.unit)")
                    .font(.subheadline)
                    .monospacedDigit()
                if let error = result.relativeError {
                    Text(error.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.14), in: Capsule())
                        .frame(width: 64, alignment: .trailing)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(result.kind.color.opacity(0.15))
                    Capsule()
                        .fill(result.kind.color.gradient)
                        .frame(width: geo.size.width * min(result.achieved / max(result.target, 1), 1))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? Theme.green : .orange)
            .accessibilityLabel(ok ? "Within target" : "Off target")
    }
}
