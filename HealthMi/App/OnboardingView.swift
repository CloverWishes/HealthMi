import SwiftUI

/// 首次使用：输入小米凭据 → 验证连接 → 请求 HealthKit 授权。
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var userId = ""
    @State private var passToken = ""
    @State private var showToken = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showWebLogin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HealthMi")
                            .font(.largeTitle.bold())
                        Text("把小米运动健康（Mi Fitness）云端的步数、心率、睡眠、血氧、体重等数据，写入 Apple 健康。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !HealthKitManager.isAvailable {
                        Label("当前设备不支持 HealthKit", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }

                    Button {
                        showWebLogin = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "globe.asia.australia")
                            Text("使用小米账号网页登录")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("在小米官方页面完成登录（支持验证码、短信验证），登录成功后自动保存凭据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("手动粘贴 Cookie（高级）") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("小米账号")
                                .font(.headline)
                            TextField("userId（account.xiaomi.com 的 Cookie）", text: $userId)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                            // 用普通 TextField 而非 SecureField：安全输入框在 iOS 上强制系统键盘，
                            // 第三方键盘（含从 Mac 复制粘贴）无法使用。
                            HStack(spacing: 8) {
                                Group {
                                    if showToken {
                                        TextField("passToken（有效期短，过期需重新获取）", text: $passToken)
                                    } else {
                                        SecureField("passToken", text: $passToken)
                                    }
                                }
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                Button {
                                    showToken.toggle()
                                } label: {
                                    Image(systemName: showToken ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))

                            Text("passToken 默认明文显示以兼容第三方键盘粘贴，可点击眼睛隐藏。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Task { await onSubmit() }
                            } label: {
                                Group {
                                    if isWorking {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("保存并连接")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(userId.isEmpty || passToken.isEmpty || isWorking)
                        }
                        .padding(.top, 8)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                    Text("凭据仅保存在本机钥匙串（Keychain），用于从你账号云端读取数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("开始使用")
            .sheet(isPresented: $showWebLogin) {
                MiWebLoginView(onConnected: {
                    try? await model.requestHealthKit()
                })
            }
        }
    }

    private func onSubmit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await model.saveCredentials(userId: userId.trimmingCharacters(in: .whitespaces),
                                            passToken: passToken.trimmingCharacters(in: .whitespaces))
            try await model.requestHealthKit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppModel())
}
