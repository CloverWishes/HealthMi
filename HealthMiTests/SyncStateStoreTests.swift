import SwiftData
import XCTest
@testable import HealthMi

@MainActor
final class SyncStateStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([SyncState.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
    }

    func testRecordUpdatesState() {
        let type: SyncDataType = .heartRate
        let highWater = Date()
        SyncStateStore.record(type: type, highWater: highWater, added: 42, in: context)

        let state = SyncStateStore.state(for: type, in: context)
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.lastSyncedEnd?.timeIntervalSince(highWater) ?? -1, 0, accuracy: 1)
        XCTAssertEqual(state?.lastAddedCount, 42)
    }

    func testClearAllRemovesAllStates() {
        SyncStateStore.record(type: .heartRate, highWater: Date(), added: 10, in: context)
        SyncStateStore.record(type: .sleep, highWater: Date(), added: 5, in: context)
        SyncStateStore.record(type: .spo2, highWater: Date(), added: 3, in: context)

        SyncStateStore.clearAll(in: context)

        for type in SyncDataType.allCases {
            XCTAssertNil(SyncStateStore.state(for: type, in: context))
        }
    }

    func testRecordTwiceUpdatesSameRow() {
        let type: SyncDataType = .heartRate
        SyncStateStore.record(type: type, highWater: Date(timeIntervalSinceNow: -3600), added: 10, in: context)
        SyncStateStore.record(type: type, highWater: Date(), added: 20, in: context)

        let state = SyncStateStore.state(for: type, in: context)
        XCTAssertEqual(state?.lastAddedCount, 20)
    }
}
