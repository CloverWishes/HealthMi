import SwiftUI
import WebKit

/// 网页登录 sheet：内嵌小米官方登录页，登录成功后自动读取 Cookie 并保存凭据。
///
/// 密码、验证码都在小米官方页面内完成，App 不接触密码；登录成功后从 WebView
/// 的 Cookie 中提取 `userId` + `passToken`，调用 `AppModel.saveCredentials`
/// 存入钥匙串并校验连接，随后通过 `onConnected` 通知父视图。
struct MiWebLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// 登录成功并保存凭据后，由父视图执行的后续动作（如首次使用请求 HealthKit 授权）。
    var onConnected: () async -> Void = {}

    @State private var isWorking = false
    @State private var errorMessage: String?
    /// 重试时 +1，通过 `.id()` 重建 WebView（非持久化会话，重建即重新登录）。
    @State private var loginAttempt = 0

    var body: some View {
        NavigationStack {
            ZStack {
                MiWebLoginViewRepresentable(
                    onCredentials: { userId, passToken in
                        Task { @MainActor in await completeLogin(userId: userId, passToken: passToken) }
                    },
                    onLoadError: { message in
                        errorMessage = message
                    }
                )
                .id(loginAttempt)

                if isWorking {
                    ProgressView("正在验证登录凭证…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("小米账号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("重试") {
                            self.errorMessage = nil
                            loginAttempt += 1
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
    }

    private func completeLogin(userId: String, passToken: String) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await model.saveCredentials(userId: userId, passToken: passToken)
            dismiss()
            await onConnected()
        } catch {
            errorMessage = "保存并验证登录凭证失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - UIKit 桥接

private struct MiWebLoginViewRepresentable: UIViewControllerRepresentable {
    let onCredentials: @MainActor (String, String) -> Void
    let onLoadError: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> MiWebLoginViewController {
        MiWebLoginViewController(onCredentials: onCredentials, onLoadError: onLoadError)
    }

    func updateUIViewController(_ uiViewController: MiWebLoginViewController, context: Context) {}
}

/// 持有 WKWebView 的容器控制器。
@MainActor
private final class MiWebLoginViewController: UIViewController {
    private let controller: MiWebLoginController

    init(onCredentials: @escaping @MainActor (String, String) -> Void,
         onLoadError: @escaping @MainActor (String) -> Void) {
        let controller = MiWebLoginController()
        controller.onCredentials = onCredentials
        controller.onLoadError = onLoadError
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = controller.webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        controller.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        controller.stop()
    }
}

// MARK: - WebView 逻辑

/// 管理登录页的加载与 Cookie 捕获。
@MainActor
private final class MiWebLoginController: NSObject, WKNavigationDelegate, WKUIDelegate {
    var onCredentials: (@MainActor (String, String) -> Void)?
    var onLoadError: (@MainActor (String) -> Void)?

    private(set) var didSucceed = false

    let webView: WKWebView
    private var cookieTimer: Timer?

    override init() {
        let configuration = WKWebViewConfiguration()
        // 非持久化会话：登录期间的 Cookie 不写入 WebView 缓存，下次启动无残留登录态。
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// 打开小米登录页并开始轮询 Cookie。在 `viewDidLoad` 调用。
    func start() {
        guard !didSucceed else { return }
        cookieTimer?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCookies() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cookieTimer = timer
        webView.load(URLRequest(url: MiWebLogin.loginURL))
    }

    func stop() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        webView.stopLoading()
    }

    // MARK: - Cookie 捕获

    private func checkCookies() {
        guard !didSucceed else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self, !self.didSucceed,
                      let credentials = MiWebLogin.credentials(from: cookies)
                else { return }
                self.complete(credentials.userId, credentials.passToken)
            }
        }
    }

    private func complete(_ userId: String, _ passToken: String) {
        guard !didSucceed else { return }
        didSucceed = true
        cookieTimer?.invalidate()
        cookieTimer = nil
        onCredentials?(userId, passToken)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 登录会经历多次重定向，每次完成后都检查一次 Cookie。
        checkCookies()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard !didSucceed else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        onLoadError?(error.localizedDescription)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // `target=_blank` 的弹窗在同一个 WebView 内打开，避免登录流程被新窗口打断。
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

#Preview {
    MiWebLoginView()
        .environment(AppModel())
}
