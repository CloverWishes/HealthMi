import Foundation
import SwiftData
import os

/// 可同步的数据类型。stress 无 HealthKit 对应类型，存 App 内 SwiftData 展示。
/// abnormal_heart_beat 暂不纳入。
enum SyncDataType: String, CaseIterable, Identifiable, Sendable {
    case dailyActivity = "daily_activity"
    case heartRate = "heart_rate"
    case sleep = "sleep"
    case spo2 = "spo2"
    case respiratoryRate = "respiratory_rate"
    case hrv = "hrv"
    case bodyMeasurements = "body_measurements"
    case workouts = "workouts"
    case stress = "stress"

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
        case .stress: return "压力"
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
        do {
            try context.save()
        } catch {
            AppLog.syncStateStore.error("保存同步游标失败 (\(type.rawValue))：\(error.localizedDescription)")
        }
    }

    /// 清除所有同步游标（退出登录或切换账号时调用，防止新账号继承旧进度）。
    static func clearAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<SyncState>()
        do {
            let all = try context.fetch(descriptor)
            for state in all {
                context.delete(state)
            }
            try context.save()
        } catch {
            AppLog.syncStateStore.error("清除同步游标失败：\(error.localizedDescription)")
        }
    }
}

/// 每类同步数据的「起始日期」（可选）。按 `SyncDataType` 独立存储，互不影响。
///
/// 语义：设置后作为该类同步的时间下界——**增量与重新回填都不会拉取早于该日期的数据**；
/// 未设置（nil）表示无下界，此时「重新回填」可补更早的历史。
/// 存储于 UserDefaults（不改 SwiftData schema，避免迁移），值为当天 00:00 的时间戳。
enum SyncStartStore {
    private static func key(for type: SyncDataType) -> String {
        "sync_start_day_\(type.rawValue)"
    }

    /// 读取该类别的起始日期；未设置返回 nil。
    static func startDate(for type: SyncDataType) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: key(for: type))
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// 设置起始日期（自动归一到当天 00:00）；传 nil 表示清除（无下界）。
    static func setStartDate(_ date: Date?, for type: SyncDataType) {
        let defaults = UserDefaults.standard
        if let date {
            defaults.set(
                Calendar.current.startOfDay(for: date).timeIntervalSince1970,
                forKey: key(for: type)
            )
        } else {
            defaults.removeObject(forKey: key(for: type))
        }
    }

    /// 清除所有类别的起始日期（退出登录或切换账号时调用，与游标保持一致）。
    static func clearAll() {
        let defaults = UserDefaults.standard
        for type in SyncDataType.allCases {
            defaults.removeObject(forKey: key(for: type))
        }
    }
}
