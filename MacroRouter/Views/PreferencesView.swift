import SwiftUI
import MacroCore

/// Plan preferences: which meals, how big each is, diet restrictions and meal reminders.
struct PreferencesView: View {
    @Environment(AppState.self) private var app
    @State private var settings = PlannerSettings()
    @State private var reminders = ReminderSettings()
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
                toggleRow("Breakfast", emoji: MealSlot.breakfast.emoji, isOn: $settings.includeBreakfast)
                HStack(spacing: 12) {
                    Text(MealSlot.lunch.emoji).font(.title3)
                    Text("Lunch & dinner")
                    Spacer()
                    Text("Always").foregroundStyle(.secondary)
                }
                toggleRow("Afternoon snack", emoji: MealSlot.snack.emoji, isOn: $settings.includeSnack)
            } header: {
                Text("Meals")
            } footer: {
                Text("A snack is only planned when you've picked snack foods, like yogurt, fruit or nuts.")
            }

            Section {
                // Plain buttons instead of an inline Picker: the inline picker stopped every other
                // control on this screen from responding to taps.
                ForEach(MealSizes.allCases) { size in
                    Button {
                        settings.mealSizes = size
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(size.displayName).foregroundStyle(Color(.label))
                                Text(size.summary).font(.caption).foregroundStyle(Color(.secondaryLabel))
                            }
                            Spacer()
                            if settings.mealSizes == size {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(settings.mealSizes == size ? .isSelected : [])
                }
            } header: {
                Text("Meal sizes")
            } footer: {
                Text("Share of the day for breakfast · lunch · dinner. A snack takes 12% and the rest scale down.")
            }

            Section {
                ForEach(DietRestriction.allCases) { diet in
                    ToggleRow(isOn: Binding(
                        get: { settings.diet.contains(diet) },
                        set: { on in if on { settings.diet.insert(diet) } else { settings.diet.remove(diet) } })) {
                        Text(diet.displayName)
                    }
                }
            } header: {
                Text("Diet")
            } footer: {
                Text(excludedText)
            }

            Section {
                ToggleRow(isOn: $reminders.enabled) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "bell.fill", color: .orange)
                        Text("Meal reminders")
                    }
                }
                if reminders.enabled {
                    ForEach(settings.slots) { slot in
                        DatePicker("\(slot.emoji) \(slot.displayName)", selection: timeBinding(slot), displayedComponents: .hourAndMinute)
                    }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text(notificationsDenied
                     ? "Notifications are off for Macro Router. Turn them on in the Settings app."
                     : "Get a notification at each meal with what to eat.")
            }

            if app.data.currentWeek != nil {
                Section {
                    Button {
                        app.updateSettings(settings)
                        app.generatePlan()
                    } label: {
                        Label("Re-plan my week with these settings", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(GradientButtonStyle())
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .themedList()
        .navigationTitle("Plan preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            settings = app.settings
            reminders = app.reminders
        }
        .onChange(of: settings) { _, new in app.updateSettings(new) }
        .onChange(of: reminders) { old, new in
            if new.enabled && !old.enabled {
                Task {
                    let granted = await ReminderService.requestPermission()
                    notificationsDenied = !granted
                    if !granted { reminders.enabled = false }
                    app.updateReminders(reminders)
                }
            } else {
                app.updateReminders(new)
            }
        }
    }

    private func toggleRow(_ title: String, emoji: String, isOn: Binding<Bool>) -> some View {
        ToggleRow(isOn: isOn) {
            HStack(spacing: 12) {
                Text(emoji).font(.title3)
                Text(title)
            }
        }
    }

    private func timeBinding(_ slot: MealSlot) -> Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: reminders.minutes(for: slot), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminders.times[slot] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    /// Which picked foods the diet leaves out.
    private var excludedText: String {
        let left = app.selectedIngredients.filter { !settings.allows($0) }
        guard !settings.diet.isEmpty else { return "Foods are matched by name. Plans leave out anything that doesn't fit." }
        guard !left.isEmpty else { return "None of your picked foods are left out." }
        return "Left out of plans: " + left.map(\.shortName).joined(separator: ", ") + "."
    }
}

/// A switch row where tapping anywhere on the row flips it. Plain Toggles further down this Form
/// stopped receiving taps once the list had been scrolled, while Buttons kept working, so the row
/// is a Button and the switch only shows the state.
private struct ToggleRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder var label: Label

    var body: some View {
        Button {
            withAnimation(.snappy) { isOn.toggle() }
        } label: {
            HStack {
                label.foregroundStyle(Color(.label))
                Spacer()
                Toggle("", isOn: .constant(isOn))
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
