import Foundation
import Observation
import FirebaseAuth

struct AppUser: Equatable {
    let uid: String
    let email: String?
}

/// Thin wrapper over Firebase Auth (email + password).
@Observable
@MainActor
final class AuthService {
    let isEnabled: Bool
    private(set) var user: AppUser?
    @ObservationIgnored var onUserChange: ((AppUser?) -> Void)?
    @ObservationIgnored private var handle: AuthStateDidChangeListenerHandle?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        guard isEnabled else { return }
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            let newUser = firebaseUser.map { AppUser(uid: $0.uid, email: $0.email) }
            Task { @MainActor in
                guard let self, self.user != newUser else { return }
                self.user = newUser
                self.onUserChange?(newUser)
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() throws {
        guard isEnabled else { return }
        try Auth.auth().signOut()
    }
}
