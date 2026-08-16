import AppIntents
import Foundation

/// "同步健康数据" App Intent：打开 App 并触发一次同步。
struct SyncHealthDataIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "同步健康数据"
    nonisolated static let description = IntentDescription("从小米云端拉取最新健康数据，写入 Apple 健康")
    nonisolated static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SyncIntentTrigger.shouldSync = true
        return .result()
    }
}

/// App Intent 触发标记，DashboardView 启动时检查。
enum SyncIntentTrigger {
    nonisolated(unsafe) static var shouldSync = false
}

/// 快捷指令注册：Siri / 快捷指令 App 中可搜索到「同步健康数据」。
struct HealthMiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncHealthDataIntent(),
            phrases: [
                "同步\(.applicationName)健康数据",
                "同步\(.applicationName)",
                "\(.applicationName)健康同步"
            ],
            shortTitle: "同步健康数据",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
