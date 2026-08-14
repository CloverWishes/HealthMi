import HealthKit
import Foundation

/// 幂等写入器，复刻 `healthloom.app` 的 `HealthKitWriter` 模式：
/// - 每个样本带 `HKMetadataKeyExternalUUID`；
/// - 写入前按「类型 + 时间段」一次查询已有的 externalID，内存里 diff 后只保存新增批次；
/// - 更新 = 按 externalID 删除 + 重插（HK 样本不可变）。
actor HealthWriter {
    private let store: HKHealthStore

    init(store: HKHealthStore = HealthKitManager.healthStore) {
        self.store = store
    }

    /// 该类型在 `[start, end]` 内已写入的 externalID 集合。
    func existingExternalIDs(ofType type: HKSampleType, start: Date, end: Date) async throws -> Set<String> {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(
                withStart: start, end: end,
                options: [.strictStartDate, .strictEndDate]
            ),
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID),
        ])
        var ids = Set<String>()
        var anchor: Date? = nil
        while true {
            let samples = try await queryPage(type: type, predicate: predicate, anchor: anchor)
            guard !samples.isEmpty else { break }
            for sample in samples {
                if let uuid = sample.metadata?[HKMetadataKeyExternalUUID] as? String {
                    ids.insert(uuid)
                }
                if let last = samples.last, last.startDate > (anchor ?? .distantPast) {
                    anchor = last.startDate
                }
            }
            if samples.count < Self.pageSize { break }
        }
        return ids
    }

    /// 一次性批量保存（空批次直接跳过）。
    func save(_ batch: [HKObject]) async throws {
        guard !batch.isEmpty else { return }
        try await store.save(batch)
    }

    /// 用 `HKWorkoutBuilder` 构建并保存一条运动记录。
    /// 保留 externalUUID metadata（builder 支持 addMetadata），继续用于去重。
    func saveWorkout(_ draft: TypeMapper.WorkoutDraft) async throws -> HKWorkout {
        let config = HKWorkoutConfiguration()
        config.activityType = draft.activityType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
        do {
            try await builder.beginCollection(at: draft.start)
            try await builder.addMetadata([HKMetadataKeyExternalUUID: draft.externalUUID])
            try await builder.endCollection(at: draft.end)
            guard let workout = try await builder.finishWorkout() else {
                throw HealthWriterError.workoutBuildFailed
            }
            return workout
        } catch {
            builder.discardWorkout()
            throw error
        }
    }

    enum HealthWriterError: LocalizedError {
        case workoutBuildFailed
        var errorDescription: String? { "运动记录构建失败" }
    }

    /// 按 externalID 删除指定类型的对象，返回删除数量。
    @discardableResult
    func delete(ofType type: HKObjectType, externalIDs: Set<String>) async throws -> Int {
        guard !externalIDs.isEmpty else { return 0 }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: Array(externalIDs)
        )
        return try await withCheckedThrowingContinuation { continuation in
            store.deleteObjects(of: type, predicate: predicate) { _, count, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
        }
    }

    // MARK: - 分页查询

    private static let pageSize = 1000

    private func queryPage(
        type: HKSampleType, predicate: NSPredicate, anchor: Date?
    ) async throws -> [HKSample] {
        var combined = predicate
        if let anchor {
            combined = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                HKQuery.predicateForSamples(withStart: anchor, end: nil),
            ])
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: combined,
                limit: Self.pageSize, sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}
