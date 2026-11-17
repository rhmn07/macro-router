import Foundation

/// Decodable subset of the USDA FoodData Central `/v1/foods/search` response.
/// Docs: https://fdc.nal.usda.gov/api-guide
public struct USDASearchResponse: Decodable, Sendable {
    public var totalHits: Int?
    public var foods: [USDAFood]
}

public struct USDAFood: Decodable, Sendable {
    public var fdcId: Int
    public var description: String
    public var dataType: String?
    public var brandOwner: String?
    public var brandName: String?
    public var foodNutrients: [USDANutrient]
}

public struct USDANutrient: Decodable, Sendable {
    public var nutrientId: Int?
    public var nutrientName: String?
    public var unitName: String?
    public var value: Double?
}

public enum USDANutrientID {
    public static let protein = 1003
    public static let fat = 1004
    public static let carbs = 1005          // Carbohydrate, by difference
    public static let energy = 1008         // Energy (kcal)
    public static let energyAtwaterGeneral = 2047
    public static let energyAtwaterSpecific = 2048
}

extension USDAFood {
    /// Search results report nutrients per 100 g for Foundation, SR Legacy and Branded foods.
    /// Returns nil when the food has no macro data at all.
    public func toIngredient() -> Ingredient? {
        func value(_ id: Int) -> Double? {
            foodNutrients.first { $0.nutrientId == id }?.value
        }
        func kcal(_ id: Int) -> Double? {
            guard let n = foodNutrients.first(where: { $0.nutrientId == id }),
                  let v = n.value else { return nil }
            if let unit = n.unitName?.uppercased(), unit == "KJ" { return v / 4.184 }
            return v
        }

        let protein = value(USDANutrientID.protein)
        let carbs = value(USDANutrientID.carbs)
        let fat = value(USDANutrientID.fat)
        guard protein != nil || carbs != nil || fat != nil else { return nil }

        let p = max(protein ?? 0, 0), c = max(carbs ?? 0, 0), f = max(fat ?? 0, 0)
        let calories = kcal(USDANutrientID.energy)
            ?? kcal(USDANutrientID.energyAtwaterSpecific)
            ?? kcal(USDANutrientID.energyAtwaterGeneral)

        return Ingredient(id: "usda-\(fdcId)",
                          name: displayName,
                          source: .usda,
                          macrosPer100g: Macros(protein: p, carbs: c, fat: f, calories: calories))
    }

    /// Readable name: generic foods are tidied by `FoodName.clean`; branded ones (often ALL CAPS)
    /// are title-cased and get their brand in parentheses.
    public var displayName: String {
        let isBranded = (brandName ?? brandOwner).map { !$0.isEmpty } ?? false
        if !isBranded { return FoodName.clean(description) }
        let base = description == description.uppercased() ? description.capitalized : description
        if let brand = brandName ?? brandOwner, !brand.isEmpty {
            let tidyBrand = brand == brand.uppercased() ? brand.capitalized : brand
            return "\(base) (\(tidyBrand))"
        }
        return base
    }
}
