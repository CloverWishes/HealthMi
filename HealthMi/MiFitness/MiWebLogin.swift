import Foundation

/// 小米网页登录的常量与 Cookie 提取逻辑。
///
/// 登录页与 `MiSessionClient.login` 使用相同的 SID，用户在小米官方页面完成
/// 登录（含验证码/短信二次验证）后，`account.xiaomi.com` 域会下发 `userId`、
/// `passToken` 等 Cookie；这里只负责从 WebView 的 Cookie 里挑出这两个值，
/// 之后继续走既有的 token → 会话交换链路。
enum MiWebLogin {
    /// 小米官方登录页（`_json=true` 与 `MiSessionClient.login` 保持一致）。
    static let loginURL = URL(string: "https://account.xiaomi.com/pass/serviceLogin?sid=miothealth")!

    /// 登录成功后需要捕获的两个 Cookie 名。
    static let userIdCookie = "userId"
    static let passTokenCookie = "passToken"

    /// 从 WebView 的 Cookie 中提取 `userId` + `passToken`。
    /// - Parameter cookies: `WKHTTPCookieStore.getAllCookies()` 返回的全部 Cookie。
    /// - Returns: 两个值都存在且非空时返回，否则返回 `nil`（尚未登录成功）。
    static func credentials(from cookies: [HTTPCookie]) -> (userId: String, passToken: String)? {
        let values = Dictionary(
            cookies
                .filter { $0.domain.contains("account.xiaomi.com") }
                .map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        guard let userId = values[userIdCookie], !userId.isEmpty,
              let passToken = values[passTokenCookie], !passToken.isEmpty
        else {
            return nil
        }
        return (userId, passToken)
    }
}
