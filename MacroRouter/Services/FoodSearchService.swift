import Foundation
import MacroCore

enum FoodSearchError: LocalizedError {
    case rateLimited
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "USDA search limit reached. The shared DEMO_KEY allows only a few searches per hour. Add your own free key (see README)."
        case .badResponse(let code):
            return "Food search failed (HTTP \(code))."
        }
    }
}

/// Searches USDA FoodData Central. Free API key: https://fdc.nal.usda.gov/api-key-signup
struct FoodSearchService {
    var apiKey: String = FoodSearchService.configuredKey
    var session: URLSession = .shared

    static var configuredKey: String {
        let key = (Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return key.isEmpty || key.hasPrefix("$(") ? "DEMO_KEY" : key
    }

    /// USDA parses the query as Lucene syntax, so characters like / ( " + ! and
    /// uppercase AND/OR/NOT cause an HTTP 400. Turn any other punctuation into spaces
    /// and lowercase the text (search is case-insensitive), e.g. "93/7 beef" -> "93 7 beef".
    static func sanitize(_ query: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-%"))
        let cleaned = String(query.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    func search(_ query: String, includeBranded: Bool = false) async throws -> [Ingredient] {
        let trimmed = Self.sanitize(query)
        guard !trimmed.isEmpty else { return [] }

        var dataTypes = ["Foundation", "SR Legacy"]
        if includeBranded { dataTypes.append("Branded") }

        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "dataType", value: dataTypes.joined(separator: ",")),
            URLQueryItem(name: "pageSize", value: "30"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]

        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw FoodSearchError.rateLimited }
            guard (200..<300).contains(http.statusCode) else { throw FoodSearchError.badResponse(http.statusCode) }
        }
        let decoded = try JSONDecoder().decode(USDASearchResponse.self, from: data)

        // De-duplicate by name; USDA often returns several near-identical entries.
        var seen = Set<String>()
        return decoded.foods.compactMap { $0.toIngredient() }.filter { seen.insert($0.name.lowercased()).inserted }
    }
}
