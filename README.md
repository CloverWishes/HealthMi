# HealthMi

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

把小米运动健康（Mi Fitness）云端的健康数据，写入 Apple 健康（HealthKit）的纯 iOS App。

## 原理

`HealthMi` 用 Swift 重新实现了已验证的开源工具 [mi-fitness-mcp-cn](tools/mi-fitness-mcp-cn) 的取数逻辑：

1. **登录**：用小米账号 `userId` / `passToken`（account.xiaomi.com 的 Cookie）经 `serviceLogin` 换取 `ssecurity` 与会话 Cookie；
2. **签名请求**：每个请求用 `signed_nonce = SHA256(ssecurity||nonce)` 做 RC4 加密 + SHA1 签名，调用 `hlth.io.mi.com` 的 `get_fitness_data_by_time` / `get_sport_records_by_time`；
3. **数据映射**：步数/距离/卡路里、心率（含静息）、睡眠（含分期）、血氧、体重/体脂、运动记录 → HealthKit 类型；
4. **幂等写入**：每个样本带 `HKMetadataKeyExternalUUID`，按类型+时间区间查重后**一次批量保存**（复刻 [healthloom.app](https://github.com/wpowiertowski/healthloom.app) 的 `HealthKitWriter` 模式）。

## 数据映射

| 小米数据 | Apple Health 类型 | 换算 |
|---|---|---|
| 步数 | `stepCount` | count |
| 距离 | `distanceWalkingRunning` | m |
| 活动卡路里 | `activeEnergyBurned` | kcal |
| 心率采样 / 静息 | `heartRate` / `restingHeartRate` | count/min |
| 睡眠 | `sleepAnalysis` | inBed / asleep / AsleepCore / AsleepDeep / AsleepREM |
| 血氧 | `oxygenSaturation` | **百分比 → 分数**（98% → 0.98） |
| 体重 / 体脂 | `bodyMass` / `bodyFatPercentage` | 体脂百分比 → 分数 |
| 运动 | `HKWorkout` | 关键词映射 `HKWorkoutActivityType` |

> stress / 异常心跳暂无 HealthKit 对应类型，未纳入（数据仍可从小米云端读到）。

## 目录结构

```
project.yml          XcodeGen 工程定义（改配置后 xcodegen generate 重新生成）
HealthMi/
  App/               入口、引导、主界面、Keychain 凭据、App 状态
  MiFitness/         小米云 API 的 Swift 移植（Crypto/Session/API/Models/Parser）
  Health/            HealthKit 授权、幂等写入器、数据映射
  Sync/              同步引擎、SwiftData 游标、后台任务
HealthMiTests/       加密向量 / 解析 / 映射 单测
tools/               已验证的 Python 参考实现（mi-fitness-mcp-cn）
```

## 构建与测试

```bash
# 生成工程（首次或改 project.yml 后）
xcodegen generate

# 编译（iOS 模拟器）
xcodebuild -project HealthMi.xcodeproj -scheme HealthMi \
  -destination 'generic/platform=iOS Simulator' build

# 运行单测（对某一台已创建的模拟器）
xcodebuild -project HealthMi.xcodeproj -scheme HealthMi \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 使用

1. 首次打开 App，输入小米 `userId` / `passToken`（登录 account.xiaomi.com 后从浏览器 Cookie 中复制）；
2. 同意 HealthKit 读写权限；
3. 点「立即同步」，选择首次回填天数（7/30/90/全部）；
4. 之后在「健康」App 里即可看到小米设备的数据。

## 注意事项

- **passToken 有效期短**：过期后同步会报「登录被拒绝（code=70016）」，重新登录 account.xiaomi.com 复制新 token 更新即可。
- **HealthKit 仅 iOS 可用**：原生 macOS App 无法写 HealthKit（需 Mac Catalyst + entitlement），因此本方案做成纯 iOS。
- **后台同步**：已接入 `BGAppRefreshTask`，但模拟器不触发，需真机验证。
- **真机部署**：把 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 换成你自己的，并在 Xcode 中配置开发团队（HealthKit entitlement 需要付费开发者账号）。
- **运动记录**：`HKWorkout` 构造器在 iOS 17 起标记废弃（建议 HKWorkoutBuilder），v1 仍用旧构造器，后续可升级。

## 测试说明

`MiCryptoTests` 使用 `tools/mi-fitness-mcp-cn`（已验证的 Python 实现）作为"预言机"生成固定向量，保证 Swift 移植的 RC4/签名算法与 Python 逐字节一致，不依赖网络。可选的真实 API 集成测试需要提供有效凭据，未包含在默认单测中。

## 许可证

本项目以 **Apache License 2.0** 开源，详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

内置参考工具 [mi-fitness-mcp-cn](tools/mi-fitness-mcp-cn) 使用 **MIT License** 发布（Copyright © 2026 Aleksej Kubulashvili），详见 [tools/mi-fitness-mcp-cn/LICENSE](tools/mi-fitness-mcp-cn/LICENSE)。
