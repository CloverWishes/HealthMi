import XCTest
@testable import HealthMi

final class SyncEngineTests: XCTestCase {
    private let engine = SyncEngine()

    func testFirstSyncWindow() async {
        // 首次同步：无游标，按 backfillDays 回填
        let now = Date()
        let result = await engine.syncWindow(highWater: nil, backfillDays: 30, forceBackfill: false)
        // start 应该大约 30 天前
        let daysDiff = Calendar.current.dateComponents([.day], from: result.start, to: now).day ?? 0
        XCTAssertEqual(daysDiff, 30, accuracy: 1)
        XCTAssertEqual(result.end.timeIntervalSince(now), 0, accuracy: 60)
    }

    func testIncrementalSyncWindow() async {
        // 增量同步：有游标，从游标往前 1 天（重叠）
        let highWater = Date(timeIntervalSinceNow: -86400) // 1 天前
        let result = await engine.syncWindow(highWater: highWater, backfillDays: 30, forceBackfill: false)
        // start 应该在 highWater 前 1 天（重叠）
        let expected = Calendar.current.date(byAdding: .day, value: -1, to: highWater)!
        XCTAssertEqual(result.start.timeIntervalSince(expected), 0, accuracy: 60)
    }

    func testForceBackfillWindow() async {
        // 强制回填：忽略游标，按 backfillDays 重拉
        let highWater = Date(timeIntervalSinceNow: -86400 * 7)
        let now = Date()
        let result = await engine.syncWindow(highWater: highWater, backfillDays: 7, forceBackfill: true)
        let daysDiff = Calendar.current.dateComponents([.day], from: result.start, to: now).day ?? 0
        XCTAssertEqual(daysDiff, 7, accuracy: 1)
    }

    func testStartTimeBeforeEndTime() async {
        let result = await engine.syncWindow(highWater: nil, backfillDays: 30, forceBackfill: false)
        XCTAssertLessThan(result.start, result.end)
        XCTAssertLessThan(result.startTime, result.endTime)
    }

    func testFirstSyncClampedByStartDate() async {
        // 首次同步（无游标）设了起始日：不应回填到起始日之前
        let today = Calendar.current.startOfDay(for: Date())
        let result = await engine.syncWindow(
            highWater: nil, backfillDays: 30, forceBackfill: false, startFrom: today
        )
        XCTAssertEqual(result.start.timeIntervalSince(today), 0, accuracy: 60)
    }

    func testIncrementalClampedByStartDate() async {
        // 增量重叠本会回到昨天，但被起始日钳制到不早于今天
        let today = Calendar.current.startOfDay(for: Date())
        let highWater = Date(timeIntervalSinceNow: -3600) // 1 小时前
        let result = await engine.syncWindow(
            highWater: highWater, backfillDays: 30, forceBackfill: false, startFrom: today
        )
        XCTAssertGreaterThanOrEqual(result.start.timeIntervalSince(today), -60)
    }

    func testForceBackfillClampedByStartDate() async {
        // 重新回填同样受起始日约束（不允许突破）
        let today = Calendar.current.startOfDay(for: Date())
        let result = await engine.syncWindow(
            highWater: Date(timeIntervalSinceNow: -86400 * 7), backfillDays: 90,
            forceBackfill: true, startFrom: today
        )
        XCTAssertEqual(result.start.timeIntervalSince(today), 0, accuracy: 60)
    }

    func testNilStartDateAllowsEarlierHistory() async {
        // 起始日为空：不钳制，按回填天数拉更早历史
        let now = Date()
        let result = await engine.syncWindow(
            highWater: nil, backfillDays: 30, forceBackfill: false, startFrom: nil
        )
        let daysDiff = Calendar.current.dateComponents([.day], from: result.start, to: now).day ?? 0
        XCTAssertEqual(daysDiff, 30, accuracy: 1)
    }
}
