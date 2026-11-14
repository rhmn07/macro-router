import SwiftUI
import FirebaseCore

@main
struct MacroRouterApp: App {
    @State private var appState: AppState

    init() {
        // Firebase is optional: without GoogleService-Info.plist the app runs in local-only mode.
        let hasFirebaseConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        if hasFirebaseConfig {
            FirebaseApp.configure()
        }
        _appState = State(initialValue: AppState(cloudEnabled: hasFirebaseConfig))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
