// FfiTests.swift — no-browser FFI facts for the Swift binding.
//
// Proves Swift drives the engine's flat C ABI directly (via CSeleniumCore) and
// that the shared engine helpers marshal correctly. Needs only the .so
// (SELENIUM_CORE_LIB / linked). Real XCTest cases.
import XCTest
@testable import SeleniumCore

final class FfiTests: XCTestCase {

    func testRoute() {
        XCTAssertEqual(route("get"), "POST /session/:sessionId/url")
        XCTAssertEqual(route("nope"), "")
    }

    func testErrorCode() {
        XCTAssertEqual(errorCode("no such element"), 17)
        XCTAssertEqual(errorCode(""), 0)
    }

    func testLocatorCss() {
        XCTAssertEqual(
            locator(.css, "div.foo"),
            "{\"using\":\"css selector\",\"value\":\"div.foo\"}"
        )
    }

    func testLocatorIdRewrite() {
        XCTAssertTrue(locator(.id, "main").contains("*[id="))
    }

    func testTransportFailure() {
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        var threw = false
        do {
            _ = try d.execute("newSession", "{}")
        } catch let e as WebDriverError {
            threw = e.code == -1
        } catch {}
        XCTAssertTrue(threw, "transport failure should surface code -1")
    }
}
