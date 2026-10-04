import Charts
import SwiftUI

/// 单项趋势小图（步数/心率/睡眠/HRV）。
struct TrendChartView: View {
    let title: String
    let unit: String
    let values: [(date: Date, value: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let latest = values.last?.value {
                    Text(String(format: "%.0f %@", latest, unit))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
            Chart(values, id: \.date) { item in
                LineMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value(title, item.value)
                )
                .foregroundStyle(.tint)
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value(title, item.value)
                )
                .foregroundStyle(.tint)
                .symbolSize(12)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.day())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
        }
    }
}

/// 7 天趋势图表区域。只渲染有数据的类别，避免出现空白占位。
struct TrendChartsSection: View {
    @Environment(AppModel.self) private var model

    private var stepValues: [(date: Date, value: Double)] {
        model.trends.compactMap { t in t.stepCount.map { (date: t.date, value: $0) } }
    }

    private var heartRateValues: [(date: Date, value: Double)] {
        model.trends.compactMap { t in t.avgHeartRate.map { (date: t.date, value: $0) } }
    }

    private var sleepValues: [(date: Date, value: Double)] {
        model.trends.compactMap { t in t.sleepMinutes.map { (date: t.date, value: $0) } }
    }

    private var hrvValues: [(date: Date, value: Double)] {
        model.trends.compactMap { t in t.avgHRV.map { (date: t.date, value: $0) } }
    }

    var body: some View {
        VStack(spacing: 16) {
            if !stepValues.isEmpty {
                TrendChartView(title: "步数", unit: "步", values: stepValues)
            }
            if !heartRateValues.isEmpty {
                TrendChartView(title: "心率", unit: "bpm", values: heartRateValues)
            }
            if !sleepValues.isEmpty {
                TrendChartView(title: "睡眠", unit: "分钟", values: sleepValues)
            }
            if !hrvValues.isEmpty {
                TrendChartView(title: "HRV", unit: "ms", values: hrvValues)
            }
        }
    }
}
