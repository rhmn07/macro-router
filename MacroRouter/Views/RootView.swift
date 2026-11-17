import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if app.needsLogin {
                LoginView()
            } else {
                MainTabView()
                    .fullScreenCover(isPresented: Binding(get: { app.needsOnboarding }, set: { _ in })) {
                        OnboardingView()
                    }
            }
        }
        .overlay {
            if app.isLoading {
                ProgressView("Syncing…")
                    .tint(Theme.green)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            TargetsView()
                .tabItem { Label("Targets", systemImage: "scope") }
                .tag(AppTab.targets)
            PantryView()
                .tabItem { Label("Pantry", systemImage: "basket.fill") }
                .tag(AppTab.pantry)
            CurrentPlanView()
                .tabItem { Label("Plan", systemImage: "fork.knife") }
                .tag(AppTab.plan)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.fill") }
                .tag(AppTab.history)
        }
        .tint(Theme.green)
    }
}
