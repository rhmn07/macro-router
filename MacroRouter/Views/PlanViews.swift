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
                                    Label("Saved", systemImage: "checkmark")
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button { app.save(plan) } label: {
                                        Label("Save", systemImage: "square.and.arrow.down")
                                            .labelStyle(.titleAndIcon)
                                    }
                                }
                            }
                        }
                } else {
                    ContentUnavailableView {
                        Label("No plan yet", systemImage: "fork.knife")
                    } description: {
                        Text("Set your targets, pick foods in the Pantry, then tap Generate.")
                    } actions: {
                        Button("Go to Pantry") { app.selectedTab = .pantry }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
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
                    ContentUnavailableView("No saved plans",
                                           systemImage: "clock",
                                           description: Text("Saved plans show up here."))
                } else {
                    List {
                        ForEach(app.data.plans) { plan in
                            NavigationLink {
                                PlanContent(plan: plan)
                                    .navigationTitle(plan.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(plan.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.headline)
                                        Spacer()
                                        StatusBadge(ok: plan.isWithinMargin)
                                    }
                                    Text(plan.recipe.map(\.ingredient.name).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { app.data.plans[$0] }.forEach(app.delete)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }
}

/// Shared body for the current plan and saved plans.
struct PlanContent: View {
    let plan: MealPlan
    @State private var days = 5

    var body: some View {
        List {
            Section {
                HStack {
                    StatusBadge(ok: plan.isWithinMargin)
                    Text(plan.isWithinMargin
                         ? "All targets within ±\(Int(plan.marginOfError * 100))%"
                         : "Some targets are off by more than \(Int(plan.marginOfError * 100))%")
                        .font(.subheadline)
                }
                ForEach(plan.results) { result in
                    MacroResultRow(result: result)
                }
            } header: {
                Text("Daily totals")
            }

            if !plan.suggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(plan.suggestions, id: \.self) { hint in
                        Label(hint, systemImage: "lightbulb")
                            .font(.subheadline)
                    }
                }
            }

            Section {
                ForEach(plan.recipe) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(GroceryList.formatWeight(grams: item.grams))
                            .font(.body.monospacedDigit().bold())
                            .frame(minWidth: 70, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.ingredient.name)
                            Text("P \(Int(item.macros.protein.rounded())) · C \(Int(item.macros.carbs.rounded())) · F \(Int(item.macros.fat.rounded())) g · \(Int(item.macros.calories.rounded())) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Daily recipe")
            } footer: {
                if !plan.unusedIngredients.isEmpty {
                    Text("Not needed today: \(plan.unusedIngredients.map(\.name).joined(separator: ", ")).")
                }
            }

            Section {
                Stepper("Prep for \(days) days", value: $days, in: 1...14)
                ForEach(GroceryList.items(for: plan, days: days)) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.formattedWeight)
                            .font(.body.monospacedDigit().bold())
                    }
                }
                ShareLink(item: GroceryList.shareText(for: plan, days: days)) {
                    Label("Share grocery list", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("\(days)-day grocery list")
            }
        }
    }
}

struct MacroResultRow: View {
    let result: MacroResult

    private var color: Color { result.isWithinMargin ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.kind.displayName)
                Spacer()
                Text("\(Int(result.achieved.rounded())) / \(Int(result.target.rounded())) \(result.kind.unit)")
                    .monospacedDigit()
                if let error = result.relativeError {
                    Text(error.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(color)
                        .frame(width: 56, alignment: .trailing)
                }
            }
            ProgressView(value: min(result.achieved / max(result.target, 1), 1.0))
                .tint(color)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let ok: Bool

    var body: some View {
        Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(ok ? .green : .orange)
            .accessibilityLabel(ok ? "Within target" : "Off target")
    }
}
