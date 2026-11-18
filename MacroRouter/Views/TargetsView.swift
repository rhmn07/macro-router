import SwiftUI
import MacroCore

struct TargetsView: View {
    @Environment(AppState.self) private var app
    @State private var targets = MacroTargets.example
    @FocusState private var focused: Bool
    @State private var showingRecalculate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TargetsHero(targets: targets)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    Button { showingRecalculate = true } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: "wand.and.stars", color: Theme.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Recalculate from my stats").foregroundStyle(Color(.label))
                                Text(statsSummary).font(.caption).foregroundStyle(Color(.secondaryLabel))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        PreferencesView()
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: "slider.horizontal.3", color: MacroKind.calories.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Plan preferences").foregroundStyle(Color(.label))
                                Text(preferencesSummary).font(.caption).foregroundStyle(Color(.secondaryLabel))
                            }
                        }
                    }
                }

                Section {
                    field(.calories, value: $targets.calories)
                    field(.protein, value: $targets.protein)
                    field(.carbs, value: $targets.carbs)
                    field(.fat, value: $targets.fat)
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text("Set calories to 0 to only optimize protein, carbs and fat.")
                }

                if targets.calories > 0 && !targets.isConsistent() {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "exclamationmark.triangle.fill", color: .orange)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your macros add up to \(targets.impliedCalories) kcal (4·P + 4·C + 9·F), not \(targets.calories) kcal.")
                                    .font(.subheadline)
                                Button("Use \(targets.impliedCalories) kcal") {
                                    withAnimation { targets.calories = targets.impliedCalories }
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button {
                        focused = false
                        app.updateTargets(targets)
                        app.selectedTab = .pantry
                    } label: {
                        Label("Next: choose ingredients", systemImage: "arrow.right")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(!targets.isValid)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                AccountSection()
            }
            .themedList()
            .navigationTitle("Targets")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
            .sheet(isPresented: $showingRecalculate) {
                OnboardingView(existing: app.data.profile, isRedo: true)
            }
            .onAppear { targets = app.data.targets }
            .onChange(of: app.data.targets) { _, new in targets = new }
            .onChange(of: targets) { _, new in
                if new.isValid { app.updateTargets(new) }
            }
        }
    }

    /// e.g. "3 meals + snack · Balanced · Vegetarian"
    private var preferencesSummary: String {
        let s = app.settings
        var parts = ["\(s.slots.filter { $0 != .snack }.count) meals" + (s.includeSnack ? " + snack" : ""), s.mealSizes.displayName]
        parts += s.diet.sorted { $0.rawValue < $1.rawValue }.map(\.displayName)
        if app.reminders.enabled { parts.append("Reminders on") }
        return parts.joined(separator: " · ")
    }

    /// e.g. "Lose weight · 80 kg · Moderately active"
    private var statsSummary: String {
        guard let p = app.data.profile else { return "Answer a few questions to get suggested targets" }
        let weight = p.usesMetric
            ? "\(Int(p.weightKg.rounded())) kg"
            : "\(Int(BodyUnits.pounds(fromKg: p.weightKg).rounded())) lb"
        return "\(p.goal.displayName) · \(weight) · \(p.activity.displayName)"
    }

    private func field(_ kind: MacroKind, value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: kind.symbol, color: kind.color)
            Text(kind.displayName)
            Spacer()
            TextField(kind.displayName, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(kind.color)
                .focused($focused)
                .frame(maxWidth: 110)
            Text(kind.unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

/// Gradient card with the calorie goal and how it splits across protein, carbs and fat.
private struct TargetsHero: View {
    let targets: MacroTargets

    private var parts: [(kind: MacroKind, kcal: Double)] {
        [(.protein, Double(4 * targets.protein)),
         (.carbs, Double(4 * targets.carbs)),
         (.fat, Double(9 * targets.fat))]
    }

    private var total: Double { max(parts.map(\.kcal).reduce(0, +), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your daily goal", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(targets.calories > 0 ? targets.calories : targets.impliedCalories)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.title3.weight(.semibold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)

            // Calorie split bar
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(parts, id: \.kind) { part in
                        Capsule()
                            .fill(.white.opacity(part.kind == .protein ? 1 : part.kind == .carbs ? 0.7 : 0.45))
                            .frame(width: max((geo.size.width - 6) * part.kcal / total, 4))
                    }
                }
            }
            .frame(height: 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: targets)

            HStack(spacing: 8) {
                ForEach(parts, id: \.kind) { part in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(targets[part.kind]) g")
                            .font(.headline.monospacedDigit())
                        Text("\(part.kind.displayName) · \(Int((part.kcal / total * 100).rounded()))%")
                            .font(.caption)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text("🥗")
                .font(.system(size: 54))
                .rotationEffect(.degrees(12))
                .padding(14)
                .opacity(0.9)
        }
        .shadow(color: Theme.blue.opacity(0.3), radius: 14, y: 8)
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

private struct AccountSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Section("Account") {
            if let user = app.auth.user {
                HStack(spacing: 12) {
                    IconBadge(symbol: "person.fill", color: Theme.cyan)
                    LabeledContent("Signed in", value: user.email ?? "Account")
                }
                Button("Sign out", role: .destructive) { app.signOut() }
            } else if app.cloudEnabled {
                HStack(spacing: 12) {
                    IconBadge(symbol: "iphone", color: .gray)
                    Text("Not signed in. Your data is only on this iPhone.")
                        .foregroundStyle(.secondary)
                }
                Button("Sign in or create an account") { app.isGuest = false }
            } else {
                HStack(spacing: 12) {
                    IconBadge(symbol: "iphone", color: .gray)
                    Text("Local mode. Add a Firebase config to enable accounts and sync (see README).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
