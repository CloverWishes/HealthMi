import Foundation
import HealthKit
import Observation
import SwiftData

enum AppError: LocalizedError {
    case noCredentials
    case healthKitUnavailable

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "未找到小米凭据，请先在设置页登录。"
        case .healthKitUnavailable: return "当前设备不支持 HealthKit。"
        }
    }
}

/// 应用全局状态（主线程）。
@MainActor
@Observable
final class AppModel {
    var isConfigured = false
    var connected = false
    var accountID = ""
    var healthKitAuthorized = false
    var isSyncing = false
    var backfillDays = 30
    var statusMessage = ""
    var lastError: String?
    var outcomes: [SyncDataType: SyncOutcome] = [:]
    /// 最近 7 天数据概览（从 HealthKit 读回，用于 App 内回显）。
    var summary: HealthSummary?

    /// 小米凭据是否已过期/无效（需要用户重新登录获取新 token）。
    var authNeedsRefresh = false

    /// 已启用的同步类别（持久化到 UserDefaults，默认全部启用）。
    var enabledTypes: Set<SyncDataType> = Set(SyncDataType.allCases)

    private var engine: SyncEngine?

    // MARK: - 初始化 / 凭据

    func bootstrap() {
        loadEnabledTypes()
        if let cred = CredentialStore.load() {
            isConfigured = true
            accountID = mask(cred.userId)
        }
        refreshHealthKitStatus()
    }

    // MARK: - 同步类别开关

    func isTypeEnabled(_ type: SyncDataType) -> Bool {
        enabledTypes.contains(type)
    }

    func setTypeEnabled(_ type: SyncDataType, enabled: Bool) {
        if enabled {
            enabledTypes.insert(type)
        } else {
            enabledTypes.remove(type)
        }
        UserDefaults.standard.set(
            enabledTypes.map(\.rawValue).sorted(),
            forKey: Self.enabledTypesKey
        )
    }

    private static let enabledTypesKey = "enabled_sync_types"

    private func loadEnabledTypes() {
        guard let raw = UserDefaults.standard.array(forKey: Self.enabledTypesKey) as? [String] else {
            return
        }
        let stored = Set(raw.compactMap(SyncDataType.init(rawValue:)))
        if !stored.isEmpty {
            enabledTypes = stored
        }
    }

    func saveCredentials(userId: String, passToken: String) async throws {
        try CredentialStore.save(userId: userId, passToken: passToken)
        let engine = SyncEngine()
        try await engine.connect(userId: userId, passToken: passToken)
        self.engine = engine
        isConfigured = true
        connected = true
        authNeedsRefresh = false
        accountID = mask(userId)
        refreshHealthKitStatus()
    }

    func disconnect() {
        engine = nil
        CredentialStore.delete()
        isConfigured = false
        connected = false
        accountID = ""
        outcomes = [:]
    }

    // MARK: - HealthKit

    func requestHealthKit() async throws {
        guard HealthKitManager.isAvailable else { throw AppError.healthKitUnavailable }
        try await HealthKitManager.requestAuthorization()
        refreshHealthKitStatus()
    }

    func refreshHealthKitStatus() {
        guard HealthKitManager.isAvailable else {
            healthKitAuthorized = false
            return
        }
        let status = HealthKitManager.healthStore.authorizationStatus(
            for: HKQuantityType(.stepCount)
        )
        healthKitAuthorized = (status == .sharingAuthorized)
    }

    // MARK: - 同步

    /// 读取最近 N 天健康摘要用于 App 内回显。
    func refreshSummary(days: Int = 7) async {
        summary = await HealthKitReader.summary(days: days)
    }

    /// 若存在尚未请求过授权的类型（如后来新增的呼吸频率），先弹出 HealthKit 授权。
    func ensureHealthKitAuthorization() async {
        guard HealthKitManager.isAvailable else { return }
        let notDetermined = HealthKitManager.typesToShare.contains { type in
            HealthKitManager.healthStore.authorizationStatus(for: type) == .notDetermined
        }
        guard notDetermined else { return }
        do {
            try await HealthKitManager.requestAuthorization()
            refreshHealthKitStatus()
        } catch {
            lastError = "HealthKit 授权失败：\(error.localizedDescription)"
        }
    }

    /// - Parameter forceBackfill: 为 true 时忽略增量游标，按 `backfillDays` 重新回填历史。
    func syncAll(modelContext: ModelContext, forceBackfill: Bool = false) async {
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        // 新增类型（如呼吸频率）可能还没授权，先补齐授权，否则写入会被 HealthKit 拒绝
        await ensureHealthKitAuthorization()

        do {
            try await ensureEngine()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "❌ \(error.localizedDescription)"
            return
        }

        var messages: [String] = []
        let types = SyncDataType.allCases.filter { enabledTypes.contains($0) }
        for type in types {
            let highWater = SyncStateStore.state(for: type, in: modelContext)?.lastSyncedEnd
            do {
                let outcome = try await engine?.sync(
                    type: type, highWater: highWater, backfillDays: backfillDays,
                    forceBackfill: forceBackfill
                )
                if let outcome {
                    SyncStateStore.record(
                        type: type, highWater: outcome.highWater,
                        added: outcome.added, in: modelContext
                    )
                    outcomes[type] = outcome
                    messages.append("\(type.displayName) +\(outcome.added)")
                }
            } catch {
                let message = "\(type.displayName)：\(Self.describeSyncError(error))"
                lastError = message
                messages.append("\(type.displayName) ❌")
            }
        }
        statusMessage = messages.joined(separator: "  ")
        refreshHealthKitStatus()
        // 同步完成后刷新 App 内数据概览
        await refreshSummary()
    }

    /// 把同步错误转成可读信息，健康权限被拒时给出设置引导。
    private static func describeSyncError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == HKErrorDomain {
            if nsError.code == HKError.Code.errorAuthorizationDenied.rawValue
                || nsError.code == HKError.Code.errorAuthorizationNotDetermined.rawValue {
                return "健康权限未允许（请在 设置 → 健康 → 数据访问 中允许 HealthMi）"
            }
        }
        return error.localizedDescription
    }

    private func ensureEngine() async throws {
        if engine != nil { return }
        guard let cred = CredentialStore.load() else { throw AppError.noCredentials }
        let newEngine = SyncEngine()
        do {
            try await newEngine.connect(userId: cred.userId, passToken: cred.passToken)
            engine = newEngine
            connected = true
            authNeedsRefresh = false
            accountID = mask(cred.userId)
        } catch {
            if Self.isAuthError(error) {
                authNeedsRefresh = true
                lastError = "小米凭据已过期或无效，请更新凭据后重试。"
            }
            throw error
        }
    }

    /// 是否小米登录认证错误（passToken 过期 / 无效等）。
    private static func isAuthError(_ error: Error) -> Bool {
        if case MiLoginError.loginRejected = error { return true }
        return false
    }

    // MARK: - 工具

    private func mask(_ value: String) -> String {
        guard value.count > 4 else { return "****" }
        return value.prefix(4) + "****"
    }
}
