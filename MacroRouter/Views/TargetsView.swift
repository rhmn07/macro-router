import SwiftUI
import MacroCore

struct TargetsView: View {
    @Environment(AppState.self) private var app
    @State private var targets = MacroTargets.example
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Calories", unit: "kcal", value: $targets.calories)
                    field("Protein", unit: "g", value: $targets.protein)
                    field("Carbs", unit: "g", value: $targets.carbs)
                    field("Fat", unit: "g", value: $targets.fat)
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text("Set calories to 0 to only optimize protein, carbs and fat.")
                }

                if targets.calories > 0 && !targets.isConsistent() {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your macros add up to \(targets.impliedCalories) kcal (4·P + 4·C + 9·F), not \(targets.calories) kcal.")
                                Button("Use \(targets.impliedCalories) kcal") {
                                    targets.calories = targets.impliedCalories
                                }
                                .buttonStyle(.bordered)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Button {
                        focused = false
                        app.updateTargets(targets)
                        app.selectedTab = .pantry
                    } label: {
                        Text("Next: choose ingredients").frame(maxWidth: .infinity).bold()
                    }
                    .disabled(!targets.isValid)
                }

                AccountSection()
            }
            .navigationTitle("Targets")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
            .onAppear { targets = app.data.targets }
            .onChange(of: app.data.targets) { _, new in targets = new }
            .onChange(of: targets) { _, new in
                if new.isValid { app.updateTargets(new) }
            }
        }
    }

    private func field(_ title: String, unit: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .frame(maxWidth: 120)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

private struct AccountSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Section("Account") {
            if let user = app.auth.user {
                LabeledContent("Signed in", value: user.email ?? "Account")
                Button("Sign out", role: .destructive) { app.signOut() }
            } else if app.cloudEnabled {
                Text("Not signed in. Your data is only on this iPhone.")
                    .foregroundStyle(.secondary)
                Button("Sign in or create an account") { app.isGuest = false }
            } else {
                Text("Local mode. Add a Firebase config to enable accounts and sync (see README).")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
