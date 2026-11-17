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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: -10) {
                            ForEach(["🍗", "🍚", "🥑"], id: \.self) { emoji in
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(width: 56, height: 56)
                                    .background(.white.opacity(0.9), in: Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                        Text("Macro Router")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Tell it your macros and your foods. Get exact gram weights and a grocery list.")
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .shadow(color: Theme.green.opacity(0.3), radius: 14, y: 8)
                }
                .listRowInsets(EdgeInsets())
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
                        if isWorking { ProgressView().tint(.white) } else {
                            Text(isCreatingAccount ? "Create account" : "Sign in")
                        }
                    }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(isWorking || email.isEmpty || password.count < 6)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
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
            .themedList()
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
