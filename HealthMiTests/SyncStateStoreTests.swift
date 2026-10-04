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
        SyncStartStore.clearAll()
    }

    override func tearDown() {
        SyncStartStore.clearAll()
        super.tearDown()
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

    // MARK: - SyncStartStore

    func testStartDateRoundTripIsPerType() {
        XCTAssertNil(SyncStartStore.startDate(for: .heartRate))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        SyncStartStore.setStartDate(date, for: .heartRate)

        let stored = SyncStartStore.startDate(for: .heartRate)
        XCTAssertNotNil(stored)
        // 应归一到当天 00:00
        XCTAssertEqual(
            stored!.timeIntervalSince(Calendar.current.startOfDay(for: date)), 0, accuracy: 1
        )
        // 其它类别不受影响
        XCTAssertNil(SyncStartStore.startDate(for: .sleep))
    }

    func testClearStartDateRemovesIt() {
        SyncStartStore.setStartDate(Date(), for: .sleep)
        XCTAssertNotNil(SyncStartStore.startDate(for: .sleep))

        SyncStartStore.setStartDate(nil, for: .sleep)
        XCTAssertNil(SyncStartStore.startDate(for: .sleep))
    }

    func testClearAllStartDates() {
        SyncStartStore.setStartDate(Date(), for: .heartRate)
        SyncStartStore.setStartDate(Date(), for: .sleep)

        SyncStartStore.clearAll()

        for type in SyncDataType.allCases {
            XCTAssertNil(SyncStartStore.startDate(for: type))
        }
    }
}
