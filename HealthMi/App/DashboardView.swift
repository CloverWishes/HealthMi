import SwiftData
import SwiftUI

// MARK: - 同步页（Tab）

/// 同步页：立即增量同步、重新回填、各类数据状态。
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SyncState.typeRawValue) private var syncStates: [SyncState]
    @State private var showRebackfillConfirm = false

    /// “全部”显示为中文，其余显示“N 天”。
    private var backfillDaysLabel: String {
        model.backfillDays == 3650 ? "全部" : "\(model.backfillDays) 天"
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                // ---------- 增量同步（日常） ----------
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("增量同步", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Text("只同步上次之后的新数据，快、省流量。\n日常每天点一次这里即可。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task { await model.syncAll(modelContext: modelContext) }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isSyncing {
                                    ProgressView()
                                    if let progress = model.syncProgressText {
                                        Text(progress).font(.caption)
                                    }
                                }
                                Text(model.isSyncing ? "同步中…" : "立即增量同步")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSyncing)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("同步")
                } footer: {
                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                    }
                    if let lastError = model.lastError {
                        Text(lastError)
                            .foregroundStyle(.red)
                    }
                }

                // ---------- 重新回填历史 ----------
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("重新回填历史", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                        Text("忽略增量游标，按所选范围全量重拉并重写。\n用于补历史或修正数据，不会产生重复。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker("回填范围", selection: $model.backfillDays) {
                            Text("7 天").tag(7)
                            Text("30 天").tag(30)
                            Text("90 天").tag(90)
                            Text("全部（3650 天）").tag(3650)
                        }
                        .pickerStyle(.menu)

                        Button("重新回填 \(backfillDaysLabel)") {
                            showRebackfillConfirm = true
                        }
                        .disabled(model.isSyncing)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("重新回填")
                }
                .confirmationDialog(
                    "重新回填 \(backfillDaysLabel)？",
                    isPresented: $showRebackfillConfirm,
                    titleVisibility: .visible
                ) {
                    Button("回填 \(backfillDaysLabel)", role: .destructive) {
                        Task { await model.syncAll(modelContext: modelContext, forceBackfill: true) }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("将从最早 \(backfillDaysLabel) 重新拉取并重写。由于按 externalID 去重，已存在的数据不会重复。若某类别设置了起始日期，其回填不会早于该日期。")
                }

                // ---------- 各类数据状态 ----------
                Section {
                    ForEach(SyncDataType.allCases) { type in
                        statusRow(type)
                    }
                } header: {
                    Text("各类数据状态")
                } footer: {
                    Text("「上次同步」就是该类的增量进度；下次增量从它往前 1 天开始拉取。")
                }
            }
            .navigationTitle("同步")
            .refreshable { await model.syncAll(modelContext: modelContext) }
        }
    }

    private func statusRow(_ type: SyncDataType) -> some View {
        let enabled = model.isTypeEnabled(type)
        let state = syncStates.first { $0.typeRawValue == type.rawValue }
        let outcome = model.outcomes[type]
        return LabeledContent(type.displayName) {
            if !enabled {
                Text("已关闭")
                    .foregroundStyle(.tertiary)
            } else if let state, let last = state.lastSyncAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("上次 \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let outcome {
                        Text("新增 \(outcome.added) · 拉取 \(outcome.fetched)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("未同步")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    DashboardView()
        .environment(AppModel())
        .modelContainer(for: [SyncState.self, StressRecord.self])
}

// MARK: - 趋势页（Tab）

/// 趋势页：最近 7 天数据概览、趋势图、每日详情入口。
struct TrendsTabView: View {
    @Environment(AppModel.self) private var model

    @Query(sort: \StressRecord.timestamp, order: .reverse) private var recentStress: [StressRecord]

    /// 最近 7 天平均压力值。
    private var avgStress7d: Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = recentStress.filter { $0.timestamp >= cutoff }
        guard !recent.isEmpty else { return nil }
        return Double(recent.map(\.stressScore).reduce(0, +)) / Double(recent.count)
    }

    /// 最近 7 天是否存在任一可展示的趋势数据（`trends` 恒有 7 条，需按值判断）。
    private var hasTrendData: Bool {
        model.trends.contains {
            $0.stepCount != nil || $0.avgHeartRate != nil || $0.sleepMinutes != nil || $0.avgHRV != nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // ---------- 数据概览 ----------
                Section {
                    summaryRow("步数", value: model.summary?.stepCount.map { "\(Int($0)) 步" })
                    summaryRow("睡眠", value: model.summary?.sleepMinutes.map { String(format: "%.1f 小时", $0 / 60) })
                    summaryRow("平均心率", value: model.summary?.avgHeartRate.map { String(format: "%.0f 次/分", $0) })
                    summaryRow("平均呼吸频率", value: model.summary?.avgRespiratoryRate.map { String(format: "%.0f 次/分", $0) })
                    summaryRow("平均 HRV", value: model.summary?.avgHRV.map { String(format: "%.0f ms", $0) })
                    summaryRow("平均压力", value: avgStress7d.map { String(format: "%.0f", $0) })
                } header: {
                    Text("数据概览（最近 7 天）")
                } footer: {
                    Text("从 Apple 健康读回，需已授权相应数据类型。")
                }

                // ---------- 趋势图 ----------
                Section {
                    if !hasTrendData {
                        Text("暂无趋势数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TrendChartsSection()
                        ForEach(model.trends.reversed(), id: \.date) { trend in
                            NavigationLink {
                                DayDetailView(trend: trend, stressRecords: recentStress)
                            } label: {
                                daySummaryRow(trend)
                            }
                        }
                    }
                } header: {
                    Text("趋势（最近 7 天）")
                }
            }
            .navigationTitle("趋势")
            .task { await model.refreshSummary() }
        }
    }

    private func summaryRow(_ title: String, value: String?) -> some View {
        LabeledContent(title) {
            if let value {
                Text(value)
                    .foregroundStyle(.primary)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func daySummaryRow(_ trend: DailyTrend) -> some View {
        HStack {
            Text(trend.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(trend.stepCount.map { "\(Int($0)) 步" } ?? "—")
                .font(.caption)
        }
    }
}

// MARK: - 设置页（Tab）

/// 设置页：账号与权限、同步类别与起始日期、数据导出、退出登录。
struct SettingsTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \StressRecord.timestamp, order: .reverse) private var recentStress: [StressRecord]
    @AppStorage("mi_region") private var regionRaw = MiRegion.cn.rawValue
    /// 全局主题色 token（与 `RootView` 共用同一键）。
    @AppStorage("theme_tint") private var themeTint = ""
    @State private var showWebLogin = false
    @State private var exportFileURL: URL?
    /// 正在编辑起始日期的类别（nil 表示不显示编辑弹窗）。
    @State private var editingStartType: SyncDataType?
    /// 正在显示起始日期说明气泡的类别（nil 表示不显示）。
    @State private var startDateHelpType: SyncDataType?
    /// 正在显示类别说明气泡的类别（nil 表示不显示）。
    @State private var categoryHelpType: SyncDataType?

    var body: some View {
        NavigationStack {
            List {
                // ---------- 账号 ----------
                Section("账号") {
                    LabeledContent("小米账号", value: model.accountID)
                    LabeledContent("连接状态", value: model.connected ? "已连接" : "未连接")
                    Picker("区域", selection: $regionRaw) {
                        ForEach(MiRegion.allCases) { region in
                            Text(region.displayName).tag(region.rawValue)
                        }
                    }
                    LabeledContent("Apple 健康", value: model.healthKitAuthorized ? "已授权" : "未授权")
                    if !model.healthKitAuthorized {
                        Button("请求健康权限") {
                            Task { try? await model.requestHealthKit() }
                        }
                    }
                    if model.authNeedsRefresh {
                        Label("小米凭据已过期，请更新后重试", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Button("更新小米凭据") {
                        showWebLogin = true
                    }
                }

                // ---------- 同步类别 ----------
                Section {
                    ForEach(SyncDataType.allCases) { type in
                        categoryRow(type)
                        if model.isTypeEnabled(type) {
                            startDateRow(type)
                        }
                    }
                } header: {
                    Text("同步类别")
                } footer: {
                    Text("每个类别独立记录同步进度，关闭的类别不会同步，也不会更新进度。")
                }

                // ---------- 主题色 ----------
                Section {
                    HStack(spacing: 14) {
                        ForEach(ThemeTint.presets) { preset in
                            Button {
                                themeTint = preset.id
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if themeTint == preset.id {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .overlay {
                                        Circle().strokeBorder(
                                            Color.primary.opacity(themeTint == preset.id ? 0.35 : 0),
                                            lineWidth: 2
                                        )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(preset.name)
                        }
                    }
                    .padding(.vertical, 4)

                    ColorPicker("自定义颜色", selection: customTintBinding, supportsOpacity: false)

                    if !themeTint.isEmpty {
                        Button("恢复默认") { themeTint = "" }
                    }
                } header: {
                    Text("主题色")
                } footer: {
                    Text("影响 Tab、按钮、开关与趋势折线图等处的强调色。")
                }

                // ---------- 数据导出 ----------
                Section {
                    Button {
                        let csv = DataExporter.exportCSV(days: 7, trends: model.trends, stressRecords: recentStress)
                        exportFileURL = DataExporter.writeCSV(csv)
                    } label: {
                        Label("导出最近 7 天数据（CSV）", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.trends.isEmpty)
                } header: {
                    Text("数据导出")
                }

                // ---------- 退出登录 ----------
                Section {
                    Button("退出登录并清除小米凭据", role: .destructive) {
                        model.disconnect(modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("设置")
            .task { await model.refreshSummary() }
            .sheet(isPresented: $showWebLogin) {
                MiWebLoginView()
            }
            .sheet(isPresented: Binding(
                get: { exportFileURL != nil },
                set: { if !$0 { exportFileURL = nil } }
            )) {
                if let exportFileURL {
                    ShareSheet(items: [exportFileURL])
                }
            }
            .sheet(item: $editingStartType) { type in
                StartDateEditor(
                    typeName: type.displayName,
                    initial: model.startDate(for: type)
                ) { newDate in
                    model.setStartDate(newDate, for: type)
                }
            }
        }
    }

    /// 取色器绑定：读取当前主题色，写入时转成 `#RRGGBB` token 持久化。
    private var customTintBinding: Binding<Color> {
        Binding(
            get: { ThemeTint.color(for: themeTint) },
            set: { newValue in
                if let hex = ThemeTint.hex(newValue) { themeTint = hex }
            }
        )
    }

    /// 某个同步类别的开关行；「日常活动」额外提供 ⓘ 说明气泡。
    /// 名称用 `.plain` Button 触发切换，以便与 ⓘ 按钮各自独立响应点击。
    private func categoryRow(_ type: SyncDataType) -> some View {
        HStack(spacing: 6) {
            Button {
                model.setTypeEnabled(type, enabled: !model.isTypeEnabled(type))
            } label: {
                Text(type.displayName)
            }
            .buttonStyle(.plain)

            if type == .dailyActivity {
                Button {
                    categoryHelpType = type
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("日常活动同步说明")
                .popover(
                    isPresented: Binding(
                        get: { categoryHelpType == type },
                        set: { if !$0 { categoryHelpType = nil } }
                    )
                ) {
                    InfoPopover(text: "iPhone 已记步数，同步小米的步数会与 iPhone 的叠加，导致数值翻倍。")
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.isTypeEnabled(type) },
                set: { model.setTypeEnabled(type, enabled: $0) }
            ))
            .labelsHidden()
            .tint(ThemeTint.color(for: themeTint))
            .accessibilityLabel(type.displayName)
        }
    }

    /// 某类别的「起始日期」行：显示当前值（不限 / 具体日期），点击整行弹出编辑面板；
    /// 左侧 ⓘ 图标点击后弹出说明气泡。
    private func startDateRow(_ type: SyncDataType) -> some View {
        let stored = model.startDate(for: type)
        return HStack(spacing: 6) {
            Text("起始日期")
                .foregroundStyle(.secondary)
            Button {
                startDateHelpType = type
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("起始日期说明")
            .popover(
                isPresented: Binding(
                    get: { startDateHelpType == type },
                    set: { if !$0 { startDateHelpType = nil } }
                )
            ) {
                InfoPopover(text: "早于此日期的数据不会同步；「重新回填历史」同样受此限制。留空为「不限」，可回填更早历史。")
            }

            Spacer()

            Button {
                editingStartType = type
            } label: {
                HStack(spacing: 4) {
                    Text(stored.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "不限")
                        .foregroundStyle(stored == nil ? .secondary : .primary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 说明气泡

/// 说明气泡内容：固定宽度并按实际行数展开高度，避免多行文本被截断。
private struct InfoPopover: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(width: 260, alignment: .leading)
            .presentationCompactAdaptation(.popover)
    }
}

// MARK: - 起始日期编辑面板

/// 「起始日期」编辑面板：在「不限」与「指定日期」之间二选一，完成后回调（nil 表示不限）。
private struct StartDateEditor: View {
    enum Mode: Hashable {
        case unlimited
        case specific
    }

    let typeName: String
    let onSave: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var date: Date

    init(typeName: String, initial: Date?, onSave: @escaping (Date?) -> Void) {
        self.typeName = typeName
        self.onSave = onSave
        _mode = State(initialValue: initial == nil ? .unlimited : .specific)
        _date = State(initialValue: initial ?? Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("模式", selection: $mode) {
                        Text("不限").tag(Mode.unlimited)
                        Text("指定日期").tag(Mode.specific)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("「不限」表示不限制起始日期，可回填更早历史。")
                }

                if mode == .specific {
                    DatePicker("起始日期", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("\(typeName)·起始日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(mode == .specific ? date : nil)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 分享面板

/// UIActivityViewController 的 SwiftUI 包装。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
