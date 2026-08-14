import BackgroundTasks
import Foundation

/// BGAppRefreshTask 后台同步（模拟器不会触发，需真机运行验证）。
enum BackgroundSync {
    static let taskIdentifier = "com.example.HealthMi.sync"

    @MainActor
    static func register(syncHandler: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            refreshTask.expirationHandler = {
                refreshTask.setTaskCompleted(success: false)
            }
            Task { @MainActor in
                await syncHandler()
                refreshTask.setTaskCompleted(success: true)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
