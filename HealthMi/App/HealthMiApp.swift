import SwiftData
import SwiftUI

@main
struct HealthMiApp: App {
    let modelContainer: ModelContainer

    @State private var model = AppModel()

    init() {
        let schema = Schema([SyncState.self])
        let configuration = ModelConfiguration(schema: schema)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法初始化 SwiftData 容器：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(modelContainer)
                .task {
                    model.bootstrap()
                    BackgroundSync.register { [model, modelContainer] in
                        let context = modelContainer.mainContext
                        await model.syncAll(modelContext: context)
                    }
                    BackgroundSync.schedule()
                }
        }
    }
}
