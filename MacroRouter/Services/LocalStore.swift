import Foundation

/// Stores each user's data as a JSON file in the app's Documents folder.
struct LocalStore {
    private func url(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(of: "/", with: "_")
        return URL.documentsDirectory.appending(path: "macro-router-\(safeKey).json")
    }

    func load(key: String) -> UserData? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(UserData.self, from: data)
    }

    func save(_ userData: UserData, key: String) {
        do {
            let data = try JSONEncoder().encode(userData)
            try data.write(to: url(for: key), options: .atomic)
        } catch {
            print("LocalStore save failed: \(error)")
        }
    }
}
