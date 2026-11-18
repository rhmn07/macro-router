import SwiftUI
import MacroCore

/// Asks for goal, body stats and activity, then suggests daily targets the user can tweak.
/// Shown once after login, and again from Targets > "Recalculate from my stats".
struct OnboardingView: View {
    /// When opened from Targets: prefill with the saved answers and show Cancel instead of Skip.
    let existing: BodyProfile?
    let isRedo: Bool

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    @State private var step: Step = .goal
    @State private var goal: WeightGoal?
    @State private var sex: BiologicalSex?
    @State private var usesMetric: Bool
    @State private var age: Int?
    @State private var heightCm: Double?
    @State private var feet: Int?
    @State private var inches: Int?
    /// In kg or lb depending on `usesMetric`.
    @State private var weight: Double?
    @State private var activity: ActivityLevel?
    @State private var targets = MacroTargets.example

    private enum Step: Int, CaseIterable {
        case goal, body, activity, result
    }

    /// Text fields, in keyboard "Next" order.
    enum Field: Hashable {
        case age, heightCm, feet, inches, weight, macro(MacroKind)
    }

    private var fieldOrder: [Field] {
        switch step {
        case .body: return usesMetric ? [.age, .heightCm, .weight] : [.age, .feet, .inches, .weight]
        case .result: return [.macro(.calories), .macro(.protein), .macro(.carbs), .macro(.fat)]
        case .goal, .activity: return []
        }
    }

    private var nextField: Field? {
        guard let focused, let index = fieldOrder.firstIndex(of: focused), index + 1 < fieldOrder.count else { return nil }
        return fieldOrder[index + 1]
    }

    init(existing: BodyProfile? = nil, isRedo: Bool = false) {
        self.existing = existing
        self.isRedo = isRedo
        let metric = existing?.usesMetric ?? (Locale.current.measurementSystem == .metric)
        _usesMetric = State(initialValue: metric)
        if let existing {
            _goal = State(initialValue: existing.goal)
            _sex = State(initialValue: existing.sex)
            _age = State(initialValue: existing.age)
            _heightCm = State(initialValue: existing.heightCm.rounded())
            let imperial = BodyUnits.feetAndInches(fromCm: existing.heightCm)
            _feet = State(initialValue: imperial.feet)
            _inches = State(initialValue: imperial.inches)
            let shownWeight = metric ? existing.weightKg : BodyUnits.pounds(fromKg: existing.weightKg)
            _weight = State(initialValue: (shownWeight * 10).rounded() / 10)
            _activity = State(initialValue: existing.activity)
        }
    }

    // MARK: - Derived

    private var height: Double? {
        if usesMetric { return heightCm }
        guard let feet else { return nil }
        return BodyUnits.cm(feet: feet, inches: inches ?? 0)
    }

    private var weightKg: Double? {
        guard let weight else { return nil }
        return usesMetric ? weight : BodyUnits.kg(fromPounds: weight)
    }

    private var profile: BodyProfile? {
        guard let goal, let sex, let age, let height, let weightKg else { return nil }
        return BodyProfile(sex: sex, age: age, heightCm: height, weightKg: weightKg,
                           activity: activity ?? .moderate, goal: goal, usesMetric: usesMetric)
    }

    private var bodyProblem: String? {
        guard sex != nil, let age, let height, let weightKg else { return nil }
        if !BodyProfile.validAges.contains(age) { return "Enter an age between 13 and 100." }
        if !BodyProfile.validHeightsCm.contains(height) {
            return usesMetric ? "Enter a height between 120 and 230 cm." : "Enter a height between 4 ft 0 in and 7 ft 6 in."
        }
        if !BodyProfile.validWeightsKg.contains(weightKg) {
            return usesMetric ? "Enter a weight between 30 and 300 kg." : "Enter a weight between 66 and 660 lb."
        }
        return nil
    }

    private var canContinue: Bool {
        switch step {
        case .goal: return goal != nil
        case .body: return profile?.isValid == true
        case .activity: return activity != nil
        case .result: return targets.isValid
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch step {
                    case .goal: goalStep
                    case .body: bodyStep
                    case .activity: activityStep
                    case .result: resultStep
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                // Extra room while typing so the focused row can scroll clear of the keyboard.
                .padding(.bottom, focused == nil ? 12 : 160)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focused) { _, field in
                guard let field else { return }
                withAnimation { proxy.scrollTo(field, anchor: .center) }
            }
            }
            // Hidden while typing so the fields get the space above the keyboard; Done brings it back.
            if focused == nil { footer }
        }
        .background(ThemedBackground())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let nextField {
                    Button("Next") { focused = nextField }
                }
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                if step != .goal {
                    Button { go(back: true) } label: {
                        Image(systemName: "chevron.left").font(.headline)
                    }
                    .tint(.primary)
                }
                Spacer()
                Button(isRedo ? "Cancel" : "Skip") {
                    if isRedo { dismiss() } else { app.skipOnboarding() }
                }
                .font(.subheadline.weight(.semibold))
                .tint(.secondary)
            }
            .frame(height: 28)

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                        .frame(height: 6)
                }
            }
            .animation(.snappy, value: step)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var footer: some View {
        Button {
            if step == .result { finish() } else { go(back: false) }
        } label: {
            Label(step == .result ? "Start with these targets" : "Continue",
                  systemImage: step == .result ? "checkmark" : "arrow.right")
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(GradientButtonStyle())
        .disabled(!canContinue)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Steps

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(emoji: "👋", title: "What's your goal?",
                      subtitle: "A few quick questions and we'll set up your daily targets.")
            ForEach(WeightGoal.allCases) { option in
                OptionCard(emoji: option.emoji, title: option.displayName, detail: option.detail,
                           color: option.color, isSelected: goal == option) {
                    goal = option
                }
            }
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(emoji: "📏", title: "About you",
                      subtitle: "Used to estimate how many calories your body burns.")

            HStack(spacing: 12) {
                ForEach(BiologicalSex.allCases) { option in
                    SexCard(sex: option, isSelected: sex == option) { sex = option }
                }
            }

            Picker("Units", selection: $usesMetric.animation()) {
                Text("lb · ft").tag(false)
                Text("kg · cm").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: usesMetric) { _, metric in convertUnits(toMetric: metric) }

            VStack(spacing: 0) {
                InputRow(symbol: "birthday.cake.fill", color: MacroKind.carbs.color, title: "Age") {
                    NumberField(placeholder: "30", value: $age.asDouble, unit: "years", field: .age, focused: $focused)
                }
                .id(Field.age)
                Divider().padding(.leading, 54)
                InputRow(symbol: "ruler.fill", color: Theme.cyan, title: "Height") {
                    if usesMetric {
                        NumberField(placeholder: "175", value: $heightCm, unit: "cm", field: .heightCm, focused: $focused)
                    } else {
                        HStack(spacing: 8) {
                            NumberField(placeholder: "5", value: $feet.asDouble, unit: "ft", field: .feet, focused: $focused, width: 36)
                            NumberField(placeholder: "9", value: $inches.asDouble, unit: "in", field: .inches, focused: $focused, width: 36)
                        }
                    }
                }
                .id(usesMetric ? Field.heightCm : Field.feet)
                Divider().padding(.leading, 54)
                InputRow(symbol: "scalemass.fill", color: MacroKind.fat.color, title: "Weight") {
                    NumberField(placeholder: usesMetric ? "75" : "165", value: $weight,
                                unit: usesMetric ? "kg" : "lb", field: .weight, focused: $focused, decimal: true)
                }
                .id(Field.weight)
            }
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

            if let bodyProblem {
                Label(bodyProblem, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(emoji: "🏃", title: "How active are you?",
                      subtitle: "Count workouts and how much you move during the day.")
            ForEach(ActivityLevel.allCases) { option in
                OptionCard(emoji: option.emoji, title: option.displayName, detail: option.detail,
                           color: Theme.cyan, isSelected: activity == option) {
                    activity = option
                }
            }
        }
    }

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(emoji: "🎉", title: "Your daily targets",
                      subtitle: "Change any number if you'd like. You can edit them anytime in Targets.")

            if let profile {
                ResultHero(profile: profile, targets: targets)
            }

            VStack(spacing: 0) {
                ForEach(Array([MacroKind.calories, .protein, .carbs, .fat].enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().padding(.leading, 54) }
                    InputRow(symbol: kind.symbol, color: kind.color, title: kind.displayName) {
                        NumberField(placeholder: "0", value: binding(for: kind).asDouble, unit: kind.unit,
                                    field: .macro(kind), focused: $focused, color: kind.color)
                    }
                    .id(Field.macro(kind))
                }
            }
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

            if targets.calories > 0 && !targets.isConsistent() {
                Label("Your macros add up to \(targets.impliedCalories) kcal, not \(targets.calories) kcal.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }

            Button("Reset to suggested") {
                if let profile { withAnimation { targets = profile.recommendedTargets() } }
            }
            .font(.subheadline.weight(.semibold))
            .tint(Theme.blue)

            Text("These are estimates from the Mifflin-St Jeor equation, not medical advice. Check with a doctor or dietitian if you have a health condition, are pregnant, or are under 18.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func binding(for kind: MacroKind) -> Binding<Int?> {
        Binding {
            targets[kind]
        } set: { value in
            let v = max(value ?? 0, 0)
            switch kind {
            case .calories: targets.calories = v
            case .protein: targets.protein = v
            case .carbs: targets.carbs = v
            case .fat: targets.fat = v
            }
        }
    }

    private func go(back: Bool) {
        focused = nil
        let next = step.rawValue + (back ? -1 : 1)
        guard let nextStep = Step(rawValue: next) else { return }
        if nextStep == .result, let profile { targets = profile.recommendedTargets() }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = nextStep }
    }

    private func finish() {
        guard let profile else { return }
        app.completeOnboarding(profile: profile, targets: targets)
        if isRedo { dismiss() }
    }

    private func convertUnits(toMetric metric: Bool) {
        if metric {
            if let feet { heightCm = BodyUnits.cm(feet: feet, inches: inches ?? 0).rounded() }
            if let weight { self.weight = (BodyUnits.kg(fromPounds: weight) * 10).rounded() / 10 }
        } else {
            if let heightCm {
                let imperial = BodyUnits.feetAndInches(fromCm: heightCm)
                feet = imperial.feet
                inches = imperial.inches
            }
            if let weight { self.weight = (BodyUnits.pounds(fromKg: weight) * 10).rounded() / 10 }
        }
    }
}

// MARK: - Pieces

private extension WeightGoal {
    var emoji: String {
        switch self {
        case .lose: return "🔥"
        case .maintain: return "⚖️"
        case .gain: return "💪"
        }
    }

    var color: Color {
        switch self {
        case .lose: return MacroKind.protein.color
        case .maintain: return Theme.blue
        case .gain: return MacroKind.fat.color
        }
    }
}

private extension ActivityLevel {
    var emoji: String {
        switch self {
        case .sedentary: return "🛋️"
        case .light: return "🚶"
        case .moderate: return "🚴"
        case .active: return "🏋️"
        case .veryActive: return "🏅"
        }
    }
}

private struct StepTitle: View {
    let emoji: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 44))
            Text(title).font(.system(.largeTitle, design: .rounded).bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(.bottom, 6)
    }
}

private struct OptionCard: View {
    let emoji: String
    let title: String
    let detail: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 26))
                    .frame(width: 50, height: 50)
                    .background(color.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color(.label))
                    Text(detail).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            }
            .scaleEffect(isSelected ? 1.0 : 0.98)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SexCard: View {
    let sex: BiologicalSex
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { sex == .male ? MacroKind.fat.color : MacroKind.protein.color }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: sex == .male ? "figure.stand" : "figure.stand.dress")
                    .font(.system(size: 30))
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(width: 56, height: 56)
                    .background(isSelected ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15)), in: Circle())
                Text(sex.displayName)
                    .font(.headline)
                    .foregroundStyle(Color(.label))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: 2)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct InputRow<Field: View>: View {
    let symbol: String
    let color: Color
    let title: String
    @ViewBuilder var field: Field

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color)
            Text(title)
            Spacer()
            field
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Numeric text field that updates its value on every keystroke (a `format:` TextField only
/// commits when editing ends, which would leave Continue disabled until the keyboard closes).
/// Whole numbers unless `decimal` is set.
private struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    let unit: String
    let field: OnboardingView.Field
    var focused: FocusState<OnboardingView.Field?>.Binding
    var width: CGFloat = 72
    var decimal = false
    var color: Color = .primary

    @State private var text = ""

    private static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...(decimal ? 1 : 0))))
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
                .focused(focused, equals: field)
                .frame(width: width)
                .onAppear { text = format(value) }
                .onChange(of: text) { _, new in
                    let parsed = Self.parse(new)
                    if parsed != value { value = parsed }
                }
                .onChange(of: value) { _, new in
                    // Outside changes (unit switch, "Reset to suggested") rewrite the text.
                    if Self.parse(text) != new { text = format(new) }
                }
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
        }
    }
}

extension Binding where Value == Int? {
    /// Lets an Int field use the Double-based NumberField.
    var asDouble: Binding<Double?> {
        Binding<Double?>(get: { wrappedValue.map(Double.init) },
                         set: { wrappedValue = $0.map { Int($0.rounded()) } })
    }
}

/// Gradient card on the last step: suggested calories and how they were worked out.
private struct ResultHero: View {
    let profile: BodyProfile
    let targets: MacroTargets

    private var maintenance: Int { Int((profile.maintenanceCalories / 10).rounded() * 10) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(profile.goal.displayName)
                .font(.subheadline.weight(.semibold))
                .opacity(0.9)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(targets.calories)")
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("kcal / day").font(.headline).opacity(0.85)
            }
            Text("You burn about \(maintenance.formatted()) kcal a day.")
                .font(.subheadline)
                .opacity(0.9)
            HStack(spacing: 6) {
                ForEach([MacroKind.protein, .carbs, .fat], id: \.self) { kind in
                    Text("\(kind.letter) \(targets[kind])g")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blue.opacity(0.3), radius: 14, y: 8)
        .animation(.snappy, value: targets)
    }
}
