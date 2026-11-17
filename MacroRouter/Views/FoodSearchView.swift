import SwiftUI
import MacroCore

struct FoodSearchView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var includeBranded = false
    @State private var results: [Ingredient] = []
    @State private var isSearching = false
    @State private var error: String?

    private let service = FoodSearchService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Include branded products", isOn: $includeBranded)
                } footer: {
                    Text("Values are per 100 g from USDA FoodData Central. Tip: search for raw or dry versions (e.g. “salmon raw”, “oats dry”) so the grocery list shows purchase weights.")
                }

                if let error {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(symbol: "exclamationmark.triangle.fill", color: .orange)
                            Text(error).font(.subheadline)
                        }
                    }
                }

                Section {
                    ForEach(results) { food in
                        let added = app.contains(food)
                        Button {
                            if !added { app.upsert(food) }
                        } label: {
                            HStack(spacing: 12) {
                                EmojiBadge(ingredient: food, size: 36)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(food.name).foregroundStyle(.primary)
                                    MacroPills(macros: food.macrosPer100g)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(added ? AnyShapeStyle(Theme.green) : AnyShapeStyle(Theme.brandGradient))
                                    .symbolEffect(.bounce, value: added)
                            }
                        }
                        .disabled(added)
                    }
                } header: {
                    if !results.isEmpty { SectionTitle(emoji: "🔎", title: "Tap to add to your pantry") }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && !query.isEmpty && error == nil {
                    ContentUnavailableView.search(text: query)
                } else if query.isEmpty {
                    ContentUnavailableView("Search any food",
                                           systemImage: "magnifyingglass",
                                           description: Text("Salmon, Greek yogurt, oats, sweet potato…"))
                }
            }
            .themedList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .task(id: SearchKey(query: query, branded: includeBranded)) {
                await runSearch()
            }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private struct SearchKey: Equatable {
        let query: String
        let branded: Bool
    }

    private func runSearch() async {
        let text = query
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            error = nil
            return
        }
        // Debounce typing; .task(id:) cancels this when the query changes.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await service.search(text, includeBranded: includeBranded)
            guard !Task.isCancelled else { return }
            results = found
            error = nil
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
