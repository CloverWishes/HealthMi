import XCTest
@testable import HealthMi

/// 用已验证的 Python 实现（`tools/mi-fitness-mcp-cn` 的 oracle 向量）校验 Swift 移植。
final class MiCryptoTests: XCTestCase {
    private func b64(_ string: String) -> [UInt8] {
        Array(Data(base64Encoded: string)!)
    }

    private func b64String(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
    }

    private func byteRange(_ range: ClosedRange<UInt8>) -> [UInt8] {
        Array(range)
    }

    func testRC4Vector() {
        let key = b64("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=")
        let plain = Array("hello mi fitness".utf8)
        let out = MiCrypto.rc4Crypt(key: key, payload: plain)
        XCTAssertEqual(b64String(out), "3g08gF/TkZJ/x5IKBDEQAQ==")
    }

    func testSignedNonceVector() {
        let ssecurity = b64("MDEyMzQ1Njc4OWFiY2RlZg==")
        let nonce = byteRange(0...11)
        let signed = MiCrypto.genSignedNonce(ssecurity: ssecurity, nonce: nonce)
        XCTAssertEqual(b64String(signed), "16/CeTzC9IqVVbiZ01Hy/Qd8rtVo5ybLo+ph/Vvh52k=")
    }

    /// 完整请求字段（rc4_hash__ → 加密 data/rc4_hash__ → signature → _nonce）。
    func testRequestFieldVectors() {
        let ssecurity = b64("MDEyMzQ1Njc4OWFiY2RlZg==")
        let nonce = byteRange(0...11)
        let signed = MiCrypto.genSignedNonce(ssecurity: ssecurity, nonce: nonce)
        let path = "/app/v1/data/get_fitness_data_by_time"
        let data = "{\"start_time\":1782000000,\"end_time\":1782086399,\"key\":\"sleep\"}"

        var form = ["data": data]
        form["rc4_hash__"] = MiCrypto.genSignature(
            method: "POST", path: path, values: form, signedNonce: signed
        )
        XCTAssertEqual(form["rc4_hash__"], "dQeOexvAuinXDEkbLIQbMBouHGY=")

        var encrypted: [String: String] = [:]
        for (key, value) in form {
            encrypted[key] = b64String(MiCrypto.rc4Crypt(key: signed, payload: Array(value.utf8)))
        }
        encrypted["signature"] = MiCrypto.genSignature(
            method: "POST", path: path, values: encrypted, signedNonce: signed
        )
        encrypted["_nonce"] = b64String(nonce)

        XCTAssertEqual(encrypted["data"],
                       "5bCltiq5kl1uIEgC9s4jiIDNu+OVEGTncoC71qy+qtD4n0IkmB+onNFhbSyRCklfa0XbLc3XOY2aY08IMA==")
        XCTAssertEqual(encrypted["rc4_hash__"], "+sOzjS6zkENvIEs/kLF53fS22rHoYjuiFuWHhQ==")
        XCTAssertEqual(encrypted["signature"], "5CKrj+1MdRE9d8ILAeQPUF7dl0o=")
        XCTAssertEqual(encrypted["_nonce"], "AAECAwQFBgcICQoL")
    }

    /// 响应解密（服务端返回 base64(RC4(plaintext))）。
    func testResponseDecryptionVector() {
        let ssecurity = b64("MDEyMzQ1Njc4OWFiY2RlZg==")
        let nonce = byteRange(0...11)
        let signed = MiCrypto.genSignedNonce(ssecurity: ssecurity, nonce: nonce)
        let wire = b64("5bC1rS+uxDgqZQcVsYdn08zdsaiHRDWjP/2y0buV/IPOpx1j")
        let plain = MiCrypto.rc4Crypt(key: signed, payload: wire)
        XCTAssertEqual(String(data: Data(plain), encoding: .utf8),
                       "{\"code\":0,\"result\":{\"data_list\":[]}}")
    }

    /// 请求体 JSON 必须按 Python 字典插入顺序生成。
    func testDataStringOrder() {
        XCTAssertEqual(
            MiAPIClient.dataString(startTime: 1782000000, endTime: 1782086399, key: "sleep"),
            "{\"start_time\":1782000000,\"end_time\":1782086399,\"key\":\"sleep\"}"
        )
        XCTAssertEqual(
            MiAPIClient.dataString(startTime: 1, endTime: 2, key: "sport", limit: 50, nextKey: "abc"),
            "{\"start_time\":1,\"end_time\":2,\"key\":\"sport\",\"limit\":50,\"next_key\":\"abc\"}"
        )
    }
}
