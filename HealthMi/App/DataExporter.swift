import Foundation
import SwiftData
import SwiftUI

/// 数据导出：按天汇总最近 N 天数据，生成 CSV。
enum DataExporter {
    /// 导出最近 N 天的每日数据为 CSV 字符串。
    static func exportCSV(days: Int, trends: [DailyTrend], stressRecords: [StressRecord]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = .current

        var lines: [String] = []
        // CSV 表头
        lines.append("日期,步数,平均心率,睡眠分钟,平均HRV(ms),平均压力")
        // 按天合并压力数据
        let stressByDay = Dictionary(grouping: stressRecords, by: {
            Calendar.current.startOfDay(for: $0.timestamp)
        }).mapValues { records in
            Double(records.map(\.stressScore).reduce(0, +)) / Double(records.count)
        }

        for trend in trends.sorted(by: { $0.date < $1.date }) {
            let dateStr = dateFormatter.string(from: trend.date)
            let steps = trend.stepCount.map { Int($0) }.map(String.init) ?? ""
            let hr = trend.avgHeartRate.map { String(format: "%.0f", $0) } ?? ""
            let sleep = trend.sleepMinutes.map { String(format: "%.0f", $0) } ?? ""
            let hrv = trend.avgHRV.map { String(format: "%.0f", $0) } ?? ""
            let stress = stressByDay[Calendar.current.startOfDay(for: trend.date)].map { String(format: "%.0f", $0) } ?? ""
            lines.append("\(dateStr),\(steps),\(hr),\(sleep),\(hrv),\(stress)")
        }
        return lines.joined(separator: "\n")
    }

    /// 将 CSV 写入临时文件，返回文件 URL。
    static func writeCSV(_ csv: String, filename: String = "HealthMi_Export.csv") -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
}
