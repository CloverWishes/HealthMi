import Foundation
import SwiftData

/// 可同步的数据类型。stress / abnormal_heart_beat 暂无 HealthKit 对应类型，暂不纳入。
enum SyncDataType: String, CaseIterable, Identifiable, Sendable {
    case dailyActivity = "daily_activity"
    case heartRate = "heart_rate"
    case sleep = "sleep"
    case spo2 = "spo2"
    case respiratoryRate = "respiratory_rate"
    case hrv = "hrv"
    case bodyMeasurements = "body_measurements"
    case workouts = "workouts"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dailyActivity: return "日常活动"
        case .heartRate: return "心率"
        case .sleep: return "睡眠"
        case .spo2: return "血氧"
        case .respiratoryRate: return "呼吸频率"
        case .hrv: return "心率变异性"
        case .bodyMeasurements: return "体重/体脂"
        case .workouts: return "运动记录"
        }
    }
}

/// 每类数据的同步游标（high-water mark）。
@Model
final class SyncState {
    @Attribute(.unique) var typeRawValue: String
    /// 已同步到的最晚时间，用于增量拉取。
    var lastSyncedEnd: Date?
    var lastSyncAt: Date?
    var lastAddedCount: Int

    init(typeRawValue: String, lastSyncedEnd: Date? = nil, lastSyncAt: Date? = nil, lastAddedCount: Int = 0) {
        self.typeRawValue = typeRawValue
        self.lastSyncedEnd = lastSyncedEnd
        self.lastSyncAt = lastSyncAt
        self.lastAddedCount = lastAddedCount
    }
}

/// SwiftData 存取同步游标（必须在 MainActor 上使用，SwiftData 上下文非 Sendable）。
@MainActor
enum SyncStateStore {
    static func state(for type: SyncDataType, in context: ModelContext) -> SyncState? {
        let raw = type.rawValue
        let descriptor = FetchDescriptor<SyncState>(
            predicate: #Predicate { $0.typeRawValue == raw }
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func ensureState(for type: SyncDataType, in context: ModelContext) -> SyncState {
        if let existing = state(for: type, in: context) { return existing }
        let created = SyncState(typeRawValue: type.rawValue)
        context.insert(created)
        return created
    }

    static func record(
        type: SyncDataType, highWater: Date?, added: Int, in context: ModelContext
    ) {
        let state = ensureState(for: type, in: context)
        state.lastSyncedEnd = highWater
        state.lastSyncAt = Date()
        state.lastAddedCount = added
        try? context.save()
    }
}
