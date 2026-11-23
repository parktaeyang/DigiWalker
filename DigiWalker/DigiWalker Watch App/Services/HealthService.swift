import DigiWalkerCore
import HealthKit

struct HealthService {
    private let store = HKHealthStore()
    private let steps = HKQuantityType(.stepCount)
    private let distance = HKQuantityType(.distanceWalkingRunning)

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthFailure.unavailable }
        try await store.requestAuthorization(toShare: [], read: [steps, distance])
    }

    func reconciled(_ saved: GameState, through now: Date) async throws -> GameState {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthFailure.unavailable }
        return try await GrowthService.reconcile(saved, through: now) { metric, start, end in
            switch metric {
            case .steps: try await sum(steps, unit: .count(), from: start, to: end)
            case .distanceMeters: try await sum(distance, unit: .meter(), from: start, to: end)
            }
        }
    }

    private func sum(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        guard start < end else { return nil }
        let interval = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: interval),
            options: .cumulativeSum
        )
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        }
    }
}

enum HealthFailure: LocalizedError {
    case unavailable
    var errorDescription: String? { "이 기기에서는 건강 데이터를 읽을 수 없어요." }
}
