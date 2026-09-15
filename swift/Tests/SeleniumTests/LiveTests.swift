import XCTest
@testable import Selenium

// LIVE browser facts for the Swift binding.
//
// FfiTests and SurfaceTests are no-browser facts: they prove the shadow finders
// and the firefox factory EXIST and reach the transport, which stays green even
// when the code behind them is broken. These drive real browsers through the
// engine so the shadow-DOM path and firefox() are actually executed.
//
// Both legs self-orchestrate via the engine's driver ABI (resolveDriver +
// DriverProcess.ensure, docs/Driver-Orchestration-ABI.md) — no driver on PATH
// and no Grid — and use data: pages, so no content server is needed.
final class LiveTests: XCTestCase {

    /// An empty resolveDriver means the engine genuinely could not provide the
    /// driver; that is the only reason either leg is allowed not to run.
    private func driverFor(_ browser: String) -> DriverProcess? {
        guard !resolveDriver(browser).isEmpty else { return nil }
        return DriverProcess.ensure(browser, timeoutMs: 20_000)
    }

    func testLiveChromeShadowRoot() throws {
        guard let proc = driverFor("chrome") else {
            throw XCTSkip("engine cannot resolve a chromedriver")
        }
        defer { proc.stop() }

        let d = try WebDriver.headlessChrome(commandExecutor: proc.url)
        defer { d.quit() }

        XCTAssertFalse(d.sessionId.isEmpty, "session started")
        try d.get("data:text/html,<!doctype html><title>SwiftLive</title>"
                  + "<h1 id=\"hdr\">plain</h1><div id=\"host\"></div>")
        XCTAssertEqual(try d.title(), "SwiftLive")

        // Host an open shadow root, then reach an element INSIDE it — the
        // getShadowRoot -> findElementFromShadowRoot round trip, for real.
        _ = try d.executeScript(
            "var h=document.getElementById('host');"
            + "var r=h.attachShadow({mode:'open'});"
            + "r.innerHTML='<p id=\"sinner\">swift-shadow</p>';")

        let shadow = try d.findElement(By.id("host")).getShadowRoot()
        XCTAssertEqual(try shadow.findElement(By.css("#sinner")).text(), "swift-shadow")
        XCTAssertEqual(try shadow.findElements(By.css("p")).count, 1)

        // A non-host element has no shadow root: W3C code 19.
        XCTAssertThrowsError(try d.findElement(By.id("hdr")).getShadowRoot()) { err in
            XCTAssertEqual((err as? WebDriverError)?.code, WebDriverError.noSuchShadowRoot)
        }
    }

    func testLiveFirefox() throws {
        guard let proc = driverFor("firefox") else {
            throw XCTSkip("engine cannot resolve a geckodriver")
        }
        defer { proc.stop() }

        let d = try WebDriver.headlessFirefox(commandExecutor: proc.url)
        defer { d.quit() }

        XCTAssertFalse(d.sessionId.isEmpty, "firefox session started")
        try d.get("data:text/html,<!doctype html><title>Aether Firefox</title>"
                  + "<h1 id=\"hdr\">Hello FF</h1>")
        XCTAssertEqual(try d.title(), "Aether Firefox")
        XCTAssertEqual(try d.findElement(By.id("hdr")).text(), "Hello FF")
    }
}
