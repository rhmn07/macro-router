import SwiftUI
import Charts
import MacroCore

/// Weight log, trend chart, Apple Health import and the calorie check-in.
struct ProgressTabView: View {
    @Environment(AppState.self) private var app
    @State private var showingAdd = false
    @State private var importing = false

    private var usesMetric: Bool { app.data.profile?.usesMetric ?? (Locale.current.measurementSystem == .metric) }

    private func display(_ kg: Double) -> Double { usesMetric ? kg : BodyUnits.pounds(fromKg: kg) }
    private var unit: String { usesMetric ? "kg" : "lb" }
    private func format(_ kg: Double) -> String {
        "\(display(kg).formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeightHero(entries: app.weights, format: format)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if app.weights.count >= 2 {
                    Section {
                        Chart(app.weights) { entry in
                            LineMark(x: .value("Date", entry.date), y: .value("Weight", display(entry.kg)))
                                .foregroundStyle(Theme.blue.gradient)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", entry.date), y: .value("Weight", display(entry.kg)))
                                .foregroundStyle(Theme.cyan)
                                .symbolSize(30)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxisLabel(unit)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                    } header: {
                        SectionTitle(emoji: "📈", title: "Trend")
                    }
                }

                Section {
                    CheckInCard()
                } header: {
                    SectionTitle(emoji: "🧭", title: "Calorie check-in")
                }

                Section {
                    Button { showingAdd = true } label: {
                        Label("Add weigh-in", systemImage: "plus")
                    }
                    .buttonStyle(GradientButtonStyle())
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)

                    if HealthService.isAvailable {
                        Button {
                            importing = true
                            Task {
                                await app.importHealthWeights()
                                importing = false
                            }
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(symbol: "heart.fill", color: MacroKind.protein.color)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Import from Apple Health").foregroundStyle(Color(.label))
                                    Text("Weigh-ins from the last 90 days").font(.caption).foregroundStyle(Color(.secondaryLabel))
                                }
                                Spacer()
                                if importing { ProgressView() }
                            }
                        }
                        .disabled(importing)
                    }
                }

                if !app.weights.isEmpty {
                    Section {
                        ForEach(app.weights.reversed()) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    if entry.fromHealth {
                                        Text("Apple Health").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(format(entry.kg))
                                    .font(.body.monospacedDigit().weight(.semibold))
                            }
                        }
                        .onDelete { offsets in
                            let reversed = Array(app.weights.reversed())
                            offsets.map { reversed[$0] }.forEach(app.deleteWeight)
                        }
                    } header: {
                        SectionTitle(emoji: "⚖️", title: "Weigh-ins")
                    }
                }
            }
            .themedList()
            .navigationTitle("Progress")
            .sheet(isPresented: $showingAdd) {
                AddWeightView(usesMetric: usesMetric, last: app.weights.last?.kg ?? app.data.profile?.weightKg)
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct WeightHero: View {
    let entries: [WeightEntry]
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Current weight", systemImage: "scalemass.fill")
                .font(.subheadline.weight(.semibold))
                .opacity(0.9)
            if let latest = entries.last {
                Text(format(latest.kg))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                if let first = entries.first, first.id != latest.id {
                    let change = latest.kg - first.kg
                    Text("\(change <= 0 ? "▼" : "▲") \(format(abs(change))) since \(first.date.formatted(.dateTime.month().day()))")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)
                }
            } else {
                Text("No weigh-ins yet")
                    .font(.title2.bold())
                Text("Weigh yourself a few times a week, same time of day, to see your trend.")
                    .font(.subheadline)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blue.opacity(0.3), radius: 14, y: 8)
    }
}

/// Every two weeks: are you moving toward your goal at a healthy pace? Offers a calorie change if not.
private struct CheckInCard: View {
    @Environment(AppState.self) private var app
    @State private var applied = false

    var body: some View {
        if let checkIn = app.checkIn {
            let goal = app.data.profile?.goal ?? .maintain
            VStack(alignment: .leading, spacing: 10) {
                Text("You're \(trendText(checkIn.kgPerWeek)) a week.")
                    .font(.subheadline.weight(.semibold))
                Text("For “\(goal.displayName.lowercased())” a healthy pace is \(rangeText(checkIn.goalRange)) a week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if checkIn.isOnTrack {
                    Label("On track. Keep your current targets.", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.success)
                } else if applied {
                    Label("Targets updated. Re-plan your week to use them.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.success)
                } else {
                    let change = checkIn.calorieChange
                    Text("Suggestion: eat \(abs(change)) kcal \(change < 0 ? "less" : "more") a day (\(app.data.targets.calories.formatted()) → \((app.data.targets.calories + change).formatted()) kcal). Carbs change; protein and fat stay the same.")
                        .font(.subheadline)
                    Button {
                        app.applyCheckIn(checkIn)
                        applied = true
                    } label: {
                        Text("Apply new targets").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
                }
            }
            .padding(.vertical, 4)
        } else {
            Label("Weigh in at least 4 times over 2 weeks and you'll get a check-in that tells you whether to eat more or less.",
                  systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var usesMetric: Bool { app.data.profile?.usesMetric ?? (Locale.current.measurementSystem == .metric) }

    private func amount(_ kg: Double) -> String {
        let value = usesMetric ? kg : BodyUnits.pounds(fromKg: kg)
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(usesMetric ? "kg" : "lb")"
    }

    private func trendText(_ kgPerWeek: Double) -> String {
        if abs(kgPerWeek) < 0.05 { return "holding steady (about \(amount(0)))" }
        return "\(kgPerWeek < 0 ? "losing" : "gaining") \(amount(abs(kgPerWeek)))"
    }

    private func rangeText(_ range: ClosedRange<Double>) -> String {
        if range.lowerBound < 0 && range.upperBound > 0 { return "within ±\(amount(range.upperBound))" }
        let lo = min(abs(range.lowerBound), abs(range.upperBound)), hi = max(abs(range.lowerBound), abs(range.upperBound))
        return "\(range.upperBound < 0 ? "losing" : "gaining") \(amount(lo))–\(amount(hi))"
    }
}

private struct AddWeightView: View {
    let usesMetric: Bool
    let last: Double?

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var text = ""
    @FocusState private var focused: Bool

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var kg: Double? { value.map { usesMetric ? $0 : BodyUnits.kg(fromPounds: $0) } }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField(last.map { (usesMetric ? $0 : BodyUnits.pounds(fromKg: $0)).formatted(.number.precision(.fractionLength(1))) } ?? "0",
                              text: $text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .focused($focused)
                    Text(usesMetric ? "kg" : "lb").foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            .navigationTitle("Add weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kg { app.addWeight(WeightEntry(date: date, kg: kg)) }
                        dismiss()
                    }
                    .disabled(!BodyProfile.validWeightsKg.contains(kg ?? 0))
                }
            }
            .onAppear { focused = true }
        }
    }
}
