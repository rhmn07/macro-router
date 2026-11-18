import SwiftUI
import MacroCore

/// A week of meals: pick a day, see its meals, mark them eaten, swap foods, and shop.
/// `isCurrent` is false for saved weeks in History, which are read-only.
struct WeekPlanView: View {
    let week: WeekPlan
    let isCurrent: Bool

    @Environment(AppState.self) private var app
    @State private var selectedDay = 0
    @State private var shopDays = 7

    private var todayIndex: Int? { week.dayIndex(for: Date()) }
    private var day: MealPlan { week.days[min(selectedDay, week.days.count - 1)] }

    var body: some View {
        List {
            Section {
                DayStrip(week: week, selected: $selectedDay, today: isCurrent ? todayIndex : nil)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                DayProgressCard(week: week, day: selectedDay, isToday: isCurrent && selectedDay == todayIndex)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Macros this day misses by more than 10%, right under the progress card.
            let misses = day.results.filter { $0.kind != .calories && abs($0.relativeError ?? 0) > PantryCheck.threshold }
            if !misses.isEmpty {
                Section {
                    ForEach(misses) { result in
                        let error = result.relativeError ?? 0
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "exclamationmark.triangle.fill", color: .orange, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(result.kind.displayName) \(Int((abs(error) * 100).rounded()))% \(error < 0 ? "short" : "over") today")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Int(result.achieved.rounded())) of \(Int(result.target.rounded())) \(result.kind.unit). See Tips below, or fix it in the Pantry.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if isCurrent {
                        Button { app.selectedTab = .pantry } label: {
                            Label("Fix in Pantry", systemImage: "basket.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }

            ForEach(day.meals ?? []) { meal in
                MealSection(week: week, day: selectedDay, meal: meal, isCurrent: isCurrent)
            }

            if !day.suggestions.isEmpty {
                Section {
                    ForEach(day.suggestions, id: \.self) { hint in
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
                PlanSummaryCard(plan: day)
            } header: {
                SectionTitle(emoji: "🎯", title: "How close the day gets")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            groceries
        }
        .themedList()
        .onAppear {
            if isCurrent, let todayIndex { selectedDay = todayIndex }
            shopDays = min(shopDays, week.days.count - selectedDay)
        }
        .onChange(of: selectedDay) { _, new in
            shopDays = min(max(shopDays, 1), week.days.count - new)
        }
        .animation(.snappy, value: selectedDay)
    }

    private var shopRange: Range<Int> {
        let start = min(selectedDay, week.days.count - 1)
        return start..<min(start + max(shopDays, 1), week.days.count)
    }

    @ViewBuilder private var groceries: some View {
        let items = GroceryList.items(for: Array(week.days[shopRange]))
        Section {
            Stepper(value: $shopDays, in: 1...max(week.days.count - selectedDay, 1)) {
                HStack(spacing: 12) {
                    IconBadge(symbol: "calendar", color: Theme.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Shop for **\(shopRange.count)** \(shopRange.count == 1 ? "day" : "days")")
                            .contentTransition(.numericText())
                        Text(rangeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(items) { item in
                GroceryRow(item: item)
            }
            ShareLink(item: GroceryList.shareText(for: week, days: shopRange)) {
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
        .animation(.snappy, value: shopDays)
    }

    /// e.g. "Mon, Nov 17 – Sun, Nov 23"
    private var rangeText: String {
        let first = week.date(ofDay: shopRange.lowerBound)
        let last = week.date(ofDay: shopRange.upperBound - 1)
        let style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        return shopRange.count == 1 ? first.formatted(style) : "\(first.formatted(style)) – \(last.formatted(style))"
    }
}

/// Horizontal row of day chips.
private struct DayStrip: View {
    let week: WeekPlan
    @Binding var selected: Int
    let today: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(week.days.indices, id: \.self) { index in
                        let date = week.date(ofDay: index)
                        let isSelected = index == selected
                        Button { selected = index } label: {
                            VStack(spacing: 2) {
                                Text(index == today ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption.weight(.semibold))
                                Text(date.formatted(.dateTime.day()))
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                Circle()
                                    .fill(allEaten(index) ? Theme.success : .clear)
                                    .frame(width: 6, height: 6)
                            }
                            .frame(width: 58, height: 72)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(isSelected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
    }

    private func allEaten(_ day: Int) -> Bool {
        let meals = week.days[day].meals ?? []
        return !meals.isEmpty && meals.allSatisfy { week.isEaten(day: day, slot: $0.slot) }
    }
}

/// Today's calories eaten vs. the target, or the planned total for another day.
private struct DayProgressCard: View {
    let week: WeekPlan
    let day: Int
    let isToday: Bool

    private var target: Double { Double(week.targets.calories) }
    private var eaten: Double { week.eatenCalories(day: day) }
    private var planned: Double { week.days[day].achieved.calories }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(eaten / max(target, 1), 1))
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((min(eaten / max(target, 1), 9.99) * 100).rounded()))%")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
            }
            .frame(width: 70, height: 70)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: eaten)

            VStack(alignment: .leading, spacing: 4) {
                Text(isToday ? "Today" : week.date(ofDay: day).formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.9)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(eaten.rounded()).formatted())")
                        .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("/ \(Int(target).formatted()) kcal eaten")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.85)
                }
                Text(eaten > 0
                     ? "\(Int(max(target - eaten, 0).rounded()).formatted()) kcal left today. Tap “I ate it” after each meal."
                     : "Planned: \(Int(planned.rounded()).formatted()) kcal. Tap “I ate it” after each meal.")
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blue.opacity(0.3), radius: 14, y: 8)
    }
}

/// One meal: name and macros, foods (swipe to swap out), how to make it, and "I ate it".
private struct MealSection: View {
    let week: WeekPlan
    let day: Int
    let meal: PlannedMeal
    let isCurrent: Bool

    @Environment(AppState.self) private var app
    @State private var showSteps = false

    private var eaten: Bool { week.isEaten(day: day, slot: meal.slot) }

    var body: some View {
        Section {
            Text(MealRecipe.name(for: meal))
                .font(.headline)
                .strikethrough(eaten, color: .secondary)
                .padding(.vertical, 2)

            ForEach(meal.items) { item in
                PortionRow(item: item)
                    .opacity(eaten ? 0.55 : 1)
                    .swipeActions {
                        if isCurrent && !eaten {
                            Button { app.swapOut(item.ingredient, day: day) } label: {
                                Label("Not today", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .tint(.orange)
                        }
                    }
                    .contextMenu {
                        if isCurrent && !eaten {
                            Button { app.swapOut(item.ingredient, day: day) } label: {
                                Label("Swap out for this day", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
            }

            DisclosureGroup(isExpanded: $showSteps) {
                ForEach(Array(MealRecipe.steps(for: meal).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.cyan, in: Circle())
                        Text(step).font(.subheadline)
                    }
                }
            } label: {
                Label("How to make it", systemImage: "frying.pan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cyan)
            }

            if isCurrent {
                Button {
                    withAnimation(.snappy) { app.toggleEaten(day: day, slot: meal.slot) }
                } label: {
                    Label(eaten ? "Eaten" : "I ate it", systemImage: eaten ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(eaten ? Theme.success : Color.accentColor)
                }
                .sensoryFeedback(.success, trigger: eaten)
            }
        } header: {
            MealHeader(meal: meal, isWholeDay: false)
        }
    }
}
