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
            }
        }
        .overlay {
            if app.isLoading {
                ProgressView("Syncing…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                .tabItem { Label("Targets", systemImage: "target") }
                .tag(AppTab.targets)
            PantryView()
                .tabItem { Label("Pantry", systemImage: "basket") }
                .tag(AppTab.pantry)
            CurrentPlanView()
                .tabItem { Label("Plan", systemImage: "fork.knife") }
                .tag(AppTab.plan)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(AppTab.history)
        }
    }
}
