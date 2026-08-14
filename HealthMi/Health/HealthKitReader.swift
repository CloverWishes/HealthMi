import HealthKit
import Foundation

/// 最近一段时间的健康摘要（用于 App 内回显已同步的数据）。
struct HealthSummary: Sendable {
    var stepCount: Double?
    var sleepMinutes: Double?
    var avgHeartRate: Double?
    var avgRespiratoryRate: Double?
    var avgHRV: Double?
}

/// 从 HealthKit 读回摘要，让用户在 App 里直接看到已同步的数据。
enum HealthKitReader {
    /// 最近 7 天（含今天）的摘要。
    static func summary(days: Int = 7) async -> HealthSummary {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        var summary = HealthSummary()
        summary.stepCount = try? await sum(
            .stepCount, unit: .count(), start: start, end: end
        )
        summary.avgHeartRate = try? await average(
            .heartRate, unit: .count().unitDivided(by: .minute()), start: start, end: end
        )
        summary.avgRespiratoryRate = try? await average(
            .respiratoryRate, unit: .count().unitDivided(by: .minute()), start: start, end: end
        )
        summary.avgHRV = try? await average(
            .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end
        )
        summary.sleepMinutes = try? await sleepMinutes(from: start, to: end)
        return summary
    }

    // MARK: - 统计

    private static func sum(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let stats = try await statistics(
            for: HKQuantityType(identifier), predicate: predicate, options: .cumulativeSum
        )
        return stats.sumQuantity()?.doubleValue(for: unit)
    }

    private static func average(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let stats = try await statistics(
            for: HKQuantityType(identifier), predicate: predicate, options: .discreteAverage
        )
        return stats.averageQuantity()?.doubleValue(for: unit)
    }

    /// 睡眠总时长（分钟）= asleepUnspecified / Core / Deep / REM 之和。
    private static func sleepMinutes(from start: Date, to end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = try await query(HKCategoryType(.sleepAnalysis), predicate: predicate)
        let sleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        return samples
            .compactMap { $0 as? HKCategorySample }
            .filter { sleepValues.contains($0.value) }
            .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60 }
    }

    // MARK: - 底层查询

    private static func statistics(
        for type: HKQuantityType, predicate: NSPredicate, options: HKStatisticsOptions
    ) async throws -> HKStatistics {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let statistics {
                    continuation.resume(returning: statistics)
                } else {
                    continuation.resume(throwing: HealthKitReaderError.noStatistics)
                }
            }
            HealthKitManager.healthStore.execute(query)
        }
    }

    private static func query(_ type: HKObjectType, predicate: NSPredicate) async throws -> [HKObject] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type as! HKSampleType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            HealthKitManager.healthStore.execute(query)
        }
    }

    enum HealthKitReaderError: LocalizedError {
        case noStatistics
        var errorDescription: String? { "没有可用的统计数据" }
    }
}
