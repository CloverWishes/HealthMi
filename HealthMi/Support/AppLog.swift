import os

/// 统一日志入口，按 category 分类，便于在 Console.app 中过滤。
enum AppLog {
    static let subsystem = "com.healthmi.HealthMi"

    static let backgroundSync = Logger(subsystem: subsystem, category: "BackgroundSync")
    static let apiClient = Logger(subsystem: subsystem, category: "MiAPIClient")
    static let syncStateStore = Logger(subsystem: subsystem, category: "SyncStateStore")
    static let stressStore = Logger(subsystem: subsystem, category: "StressStore")
    static let syncLogStore = Logger(subsystem: subsystem, category: "SyncLogStore")
}
