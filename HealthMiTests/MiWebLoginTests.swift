import XCTest
@testable import HealthMi

/// 校验网页登录后从 Cookie 提取 userId/passToken 的逻辑。
final class MiWebLoginTests: XCTestCase {
    private func cookie(name: String, value: String, domain: String = "account.xiaomi.com") -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: value,
        ])!
    }

    func testValidPair() {
        let credentials = MiWebLogin.credentials(from: [
            cookie(name: "userId", value: "123456"),
            cookie(name: "passToken", value: "abc"),
        ])
        XCTAssertEqual(credentials?.userId, "123456")
        XCTAssertEqual(credentials?.passToken, "abc")
    }

    func testIgnoresUnrelatedCookies() {
        let credentials = MiWebLogin.credentials(from: [
            cookie(name: "serviceToken", value: "s"),
            cookie(name: "deviceId", value: "d"),
            cookie(name: "userId", value: "42"),
            cookie(name: "passToken", value: "tok"),
        ])
        XCTAssertEqual(credentials?.userId, "42")
        XCTAssertEqual(credentials?.passToken, "tok")
    }

    func testMissingPassToken() {
        let credentials = MiWebLogin.credentials(from: [cookie(name: "userId", value: "42")])
        XCTAssertNil(credentials)
    }

    func testMissingUserId() {
        let credentials = MiWebLogin.credentials(from: [cookie(name: "passToken", value: "tok")])
        XCTAssertNil(credentials)
    }

    func testEmptyValue() {
        let credentials = MiWebLogin.credentials(from: [
            cookie(name: "userId", value: "42"),
            cookie(name: "passToken", value: ""),
        ])
        XCTAssertNil(credentials)
    }

    func testWrongDomainIgnored() {
        let credentials = MiWebLogin.credentials(from: [
            cookie(name: "userId", value: "42", domain: "example.com"),
            cookie(name: "passToken", value: "tok", domain: "example.com"),
        ])
        XCTAssertNil(credentials)
    }

    func testLeadingDotDomain() {
        let credentials = MiWebLogin.credentials(from: [
            cookie(name: "userId", value: "42", domain: ".account.xiaomi.com"),
            cookie(name: "passToken", value: "tok", domain: ".account.xiaomi.com"),
        ])
        XCTAssertEqual(credentials?.userId, "42")
        XCTAssertEqual(credentials?.passToken, "tok")
    }
}
