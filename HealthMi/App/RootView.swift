import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    /// 主题色 token：空 = 系统默认；预设 id（如 "teal"）；或自定义 "#RRGGBB"。
    @AppStorage("theme_tint") private var themeTint = ""

    var body: some View {
        Group {
            if model.isConfigured {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .tint(ThemeTint.color(for: themeTint))
        .animation(.easeInOut(duration: 0.2), value: model.isConfigured)
    }
}

/// 底部 Tab 栏容器：同步 / 趋势 / 历史 / 设置。
///
/// iOS 26 起系统 Tab 栏自动使用液态玻璃（Liquid Glass）外观；更低系统版本自动回退为普通样式。
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext

    @State private var selection: MainTab = .sync

    enum MainTab: Hashable {
        case sync, trends, history, settings
    }

    var body: some View {
        tabs
            .task {
                // 快捷指令 / Siri 触发：切到「同步」页并立即同步
                if SyncIntentTrigger.shouldSync {
                    SyncIntentTrigger.shouldSync = false
                    selection = .sync
                    await model.syncAll(modelContext: modelContext)
                }
            }
    }

    /// iOS 26 起可声明 Tab 栏收缩行为：这里设为永不收缩，保持始终完整显示。
    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 26.0, *) {
            tabView.tabBarMinimizeBehavior(.never)
        } else {
            tabView
        }
    }

    private var tabView: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("同步", systemImage: "arrow.triangle.2.circlepath") }
                .tag(MainTab.sync)

            TrendsTabView()
                .tabItem { Label("趋势", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(MainTab.trends)

            NavigationStack {
                SyncHistoryView()
            }
            .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            .tag(MainTab.history)

            SettingsTabView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
    }
}

// MARK: - 主题色

/// 一个预设主题色。
struct ThemePreset: Identifiable {
    /// 存储 token：空字符串表示「默认」（跟随系统 accent）。
    let id: String
    /// 无障碍名称。
    let name: String
    let color: Color
}

/// 全局主题色解析：预设走 Apple 动态系统色（浅/深色自适应），自定义色存为 `#RRGGBB`。
enum ThemeTint {
    /// 「默认」主题色（系统蓝，固定值，不随 tint 变化）。
    static let defaultColor: Color = .blue

    /// 预设色板；第一项为「默认」（系统蓝）。
    static let presets: [ThemePreset] = [
        ThemePreset(id: "", name: "默认", color: defaultColor),
        ThemePreset(id: "teal", name: "青", color: .teal),
        ThemePreset(id: "green", name: "绿", color: .green),
        ThemePreset(id: "orange", name: "橙", color: .orange),
        ThemePreset(id: "pink", name: "粉", color: .pink),
        ThemePreset(id: "purple", name: "紫", color: .purple),
        ThemePreset(id: "indigo", name: "靛", color: .indigo),
        ThemePreset(id: "red", name: "红", color: .red),
    ]

    /// token → 颜色：空 = 默认；预设 id；其余按 `#RRGGBB` 解析，非法则回退默认。
    static func color(for token: String) -> Color {
        if token.isEmpty { return defaultColor }
        if let preset = presets.first(where: { $0.id == token }) { return preset.color }
        return Color(hex: token) ?? defaultColor
    }

    /// 颜色 → `#RRGGBB`（按 sRGB 取分量；失败返回 nil）。
    static func hex(_ color: Color) -> String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

extension Color {
    /// 由十六进制字符串（`#RRGGBB` 或 `RRGGBB`）构造；非法返回 nil。
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt64(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255,
            opacity: 1
        )
    }
}

#Preview {
    RootView()
        .environment(AppModel())
}
