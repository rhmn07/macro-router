import Foundation
import HealthKit
import MacroCore

enum HealthError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Apple Health isn't available on this device." }
}

/// Reads body weight from Apple Health. Read-only: the app never writes to Health.
enum HealthService {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Weigh-ins from the last `days` days, oldest first. Asks for permission the first time.
    static func weights(days: Int) async throws -> [WeightEntry] {
        guard isAvailable else { throw HealthError.unavailable }
        let type = HKQuantityType(.bodyMass)
        try await store.requestAuthorization(toShare: [], read: [type])

        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        return samples.map {
            WeightEntry(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)), fromHealth: true)
        }
    }
}
