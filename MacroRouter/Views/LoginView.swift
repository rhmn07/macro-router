import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "chart.pie.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                        Text("Macro Router")
                            .font(.largeTitle.bold())
                        Text("Tell it your macros and your foods. Get exact gram weights and a grocery list.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (6+ characters)", text: $password)
                        .textContentType(isCreatingAccount ? .newPassword : .password)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() } else {
                                Text(isCreatingAccount ? "Create account" : "Sign in").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(isWorking || email.isEmpty || password.count < 6)

                    Button(isCreatingAccount ? "I already have an account" : "Create a new account") {
                        isCreatingAccount.toggle()
                    }
                    if !isCreatingAccount {
                        Button("Forgot password?") { Task { await resetPassword() } }
                            .disabled(email.isEmpty)
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Continue without an account") { app.isGuest = true }
                } footer: {
                    Text("Your data stays on this iPhone. Sign in later from the Targets tab to back it up and sync.")
                }
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if isCreatingAccount {
                try await app.auth.signUp(email: email, password: password)
            } else {
                try await app.auth.signIn(email: email, password: password)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func resetPassword() async {
        do {
            try await app.auth.sendPasswordReset(email: email)
            message = "Password reset email sent to \(email)."
        } catch {
            message = error.localizedDescription
        }
    }
}
