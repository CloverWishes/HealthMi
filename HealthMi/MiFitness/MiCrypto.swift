import CryptoKit
import Foundation

/// Swift 移植自 `mi_fitness_mcp/adapters/mi_fitness_cloud.py` 的加密原语。
///
/// 小米健康云用一套“非对称登录 + RC4 流加密 + SHA1 签名”保护请求体：
/// - 登录后用 `ssecurity` 派生 `signed_nonce`，作为 RC4 密钥对请求参数加密；
/// - 同时用 SHA1 生成签名，防止篡改。
/// 这里逐函数对应 Python 实现，并用同一套测试向量验证行为一致。
enum MiCrypto {
    /// 标准 RC4 流加密（Python `_rc4_crypt`），丢弃前 1024 字节密钥流。
    /// - Parameters:
    ///   - key: RC4 密钥（即 signed_nonce 原始字节）
    ///   - payload: 待加密数据
    /// - Returns: 与明文等长的密文字节
    static func rc4Crypt(key: [UInt8], payload: [UInt8]) -> [UInt8] {
        var s = Array(UInt8(0)...UInt8(255))
        var j = 0
        let keyLen = key.count
        guard keyLen > 0 else { return payload }
        for i in 0..<256 {
            j = (j + Int(s[i]) + Int(key[i % keyLen])) % 256
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        func nextByte() -> UInt8 {
            i = (i + 1) % 256
            j = (j + Int(s[i])) % 256
            s.swapAt(i, j)
            return s[(Int(s[i]) + Int(s[j])) % 256]
        }
        for _ in 0..<1024 { _ = nextByte() }
        return payload.map { $0 ^ nextByte() }
    }

    /// 生成 nonce（Python `_gen_nonce`）：8 字节随机数 + 4 字节大端“(当前秒 / 60)”。
    static func genNonce(now: Date = Date()) -> [UInt8] {
        var raw = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 { raw[i] = UInt8.random(in: 0...255) }
        let minutes = UInt32(now.timeIntervalSince1970 / 60)
        withUnsafeBytes(of: minutes.bigEndian) { raw.append(contentsOf: $0) }
        return raw
    }

    /// 由 ssecurity 与 nonce 派生签名密钥（Python `_gen_signed_nonce`）：
    /// `SHA256(ssecurity || nonce)`，返回原始 32 字节。
    static func genSignedNonce(ssecurity: [UInt8], nonce: [UInt8]) -> [UInt8] {
        var data = Data(ssecurity)
        data.append(contentsOf: nonce)
        return Array(SHA256.hash(data: data))
    }

    /// 生成请求签名（Python `_gen_signature`）：
    /// base = `METHOD&path&data=<data>[&rc4_hash__=<rc4>]&<b64(signed_nonce)>`
    /// 返回 `SHA1(base)` 的 Base64。
    static func genSignature(
        method: String,
        path: String,
        values: [String: String],
        signedNonce: [UInt8]
    ) -> String {
        var base = method + "&" + path + "&data=" + values["data"]!
        if let rc4Hash = values["rc4_hash__"] {
            base += "&rc4_hash__=" + rc4Hash
        }
        base += "&" + Data(signedNonce).base64EncodedString()
        let digest = Insecure.SHA1.hash(data: Data(base.utf8))
        return Data(digest).base64EncodedString()
    }
}
