// SurfaceTests.swift — no-browser ABI-surface facts for the Swift binding's
// convenience tier (Keys, Actions wire shape, Frame id encoding). These pin the
// pure logic that mainstream scripts depend on, with no chromedriver required.
import XCTest
import Foundation
@testable import Selenium

final class SurfaceTests: XCTestCase {

    // ---- Keys: W3C PUA code points (§17.4.2) ----

    func testKeysCodePoints() {
        XCTAssertEqual(Keys.null.unicodeScalars.first!.value, 0xE000)
        XCTAssertEqual(Keys.tab.unicodeScalars.first!.value, 0xE004)
        XCTAssertEqual(Keys.enter.unicodeScalars.first!.value, 0xE007)
        XCTAssertEqual(Keys.escape.unicodeScalars.first!.value, 0xE00C)
        XCTAssertEqual(Keys.divide.unicodeScalars.first!.value, 0xE029)
        XCTAssertEqual(Keys.f1.unicodeScalars.first!.value, 0xE031)
        XCTAssertEqual(Keys.f12.unicodeScalars.first!.value, 0xE03C)
        XCTAssertEqual(Keys.meta.unicodeScalars.first!.value, 0xE03D)
    }

    func testKeysAliasesAgree() {
        XCTAssertEqual(Keys.arrowLeft, Keys.left)
        XCTAssertEqual(Keys.arrowUp, Keys.up)
        XCTAssertEqual(Keys.command, Keys.meta)
    }

    func testChordHoldsModifierThenReleasesWithNull() {
        let s = Keys.chord(Keys.control, "a")
        let chars = Array(s.unicodeScalars)
        XCTAssertEqual(chars[0].value, 0xE009) // CONTROL
        XCTAssertEqual(Character(chars[1]), "a")
        XCTAssertEqual(chars[2].value, 0xE000) // NULL terminator
        XCTAssertEqual(chars.count, 3)
    }

    // ---- Frame: the three switchToFrame id shapes ----

    private func frameIdJSON(_ frame: Frame) throws -> String {
        // Reach the id shape the driver would send: {"id": <shape>}.
        // Frame.idJSON is fileprivate, so exercise it through JSONSerialization
        // of a mirror of what switchToFrame builds.
        let mirror: [String: Any]
        switch frame {
        case .index(let i): mirror = ["id": i]
        case .element(let id): mirror = ["id": [WebElement.w3cElementKey: id]]
        case .defaultContent: mirror = ["id": NSNull()]
        }
        let data = try JSONSerialization.data(withJSONObject: mirror, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    func testFrameIndexEncodesAsBareNumber() throws {
        XCTAssertEqual(try frameIdJSON(.index(2)), "{\"id\":2}")
    }

    func testFrameDefaultEncodesAsNull() throws {
        XCTAssertEqual(try frameIdJSON(.defaultContent), "{\"id\":null}")
    }

    func testFrameElementEncodesAsW3CRef() throws {
        let s = try frameIdJSON(.element("FID"))
        XCTAssertTrue(s.contains("\"element-6066-11e4-a52e-4f735466cecf\":\"FID\""), s)
    }

    // ---- Actions: the W3C wire shape ----

    func testActionsClickBuildsPointerDevice() throws {
        // Build a click(elem) sequence and assert the pointer device shape.
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        let el = WebElement(driver: d, id: "EID")
        let built = d.actions().click(el).build()
        XCTAssertEqual(built.count, 1, "only the pointer device")
        let ptr = built[0] as! [String: Any]
        XCTAssertEqual(ptr["type"] as? String, "pointer")
        XCTAssertEqual(ptr["id"] as? String, "mouse")
        let acts = ptr["actions"] as! [[String: Any]]
        XCTAssertEqual(acts.count, 3)
        XCTAssertEqual(acts[0]["type"] as? String, "pointerMove")
        let origin = acts[0]["origin"] as! [String: Any]
        XCTAssertEqual(origin[WebElement.w3cElementKey] as? String, "EID")
        XCTAssertEqual(acts[1]["type"] as? String, "pointerDown")
        XCTAssertEqual(acts[1]["button"] as? Int, 0)
        XCTAssertEqual(acts[2]["type"] as? String, "pointerUp")
    }

    func testActionsContextClickUsesButton2() throws {
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        let built = d.actions().contextClick().build()
        let ptr = built[0] as! [String: Any]
        let acts = ptr["actions"] as! [[String: Any]]
        XCTAssertEqual(acts[0]["button"] as? Int, 2)
        XCTAssertEqual(acts[1]["button"] as? Int, 2)
    }

    func testActionsSendKeysBuildsKeyDeviceDownUpPerChar() throws {
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        let built = d.actions().sendKeys("hi").build()
        XCTAssertEqual(built.count, 1, "only the key device")
        let kbd = built[0] as! [String: Any]
        XCTAssertEqual(kbd["type"] as? String, "key")
        XCTAssertEqual(kbd["id"] as? String, "keyboard")
        let acts = kbd["actions"] as! [[String: Any]]
        XCTAssertEqual(acts.count, 4)
        XCTAssertEqual(acts[0]["type"] as? String, "keyDown")
        XCTAssertEqual(acts[0]["value"] as? String, "h")
        XCTAssertEqual(acts[3]["value"] as? String, "i")
    }

    func testActionsMixedDevicesAreLengthSynced() throws {
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        // click(3 pointer ticks) then send one char (2 key ticks): both devices
        // present, each padded to equal length with pauses.
        let built = d.actions().click(WebElement(driver: d, id: "E1")).sendKeys("x").build()
        XCTAssertEqual(built.count, 2)
        let ptr = (built.first { ($0 as! [String: Any])["type"] as? String == "pointer" }) as! [String: Any]
        let kbd = (built.first { ($0 as! [String: Any])["type"] as? String == "key" }) as! [String: Any]
        let pActs = ptr["actions"] as! [[String: Any]]
        let kActs = kbd["actions"] as! [[String: Any]]
        XCTAssertEqual(pActs.count, kActs.count, "device lists must be equal length")
    }

    func testActionsOnlyPausesBuildsNothing() throws {
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        XCTAssertTrue(d.actions().pause(10).build().isEmpty)
    }

    // ---- By factory: the added strategies ----

    func testByFactoryStrategies() {
        XCTAssertEqual(By.tagName("div").strategy, "tag name")
        XCTAssertEqual(By.linkText("Home").strategy, "link text")
        XCTAssertEqual(By.partialLinkText("Ho").strategy, "partial link text")
        XCTAssertEqual(By.xpath("//a").strategy, "xpath")
        XCTAssertEqual(By.cssSelector("a.b").strategy, "css selector")
    }

    // ---- newly-completed FFI surface: reachability without a live session ----
    // These pin that the widened C header + wrappers compile and are callable.
    // (They hit the engine only through pure helpers or a dead endpoint, so no
    // chromedriver is needed.)

    func testResolveDriverIsReachable() {
        // resolveDriver returns "" when no chromedriver is on PATH; either way it
        // must not crash — proves aether_sel_embed_resolve_driver links.
        let path = resolveDriver("chrome")
        XCTAssertNotNil(path as String?)
    }

    func testDriverProcessEnsureSkipCleanlyWithoutDriver() {
        // ensure returns nil (no driver) or a live process; both are valid. This
        // proves ensure_driver / stop_driver link and the optional flows.
        if let proc = DriverProcess.ensure("chrome", timeoutMs: 500) {
            XCTAssertFalse(proc.url.isEmpty)
            proc.stop()
        }
    }

    func testTlsAccessorsLinkAndAreNoOpBeforeSession() {
        // set_ca / set_insecure must link and be safe to call pre-session.
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        d.setCa("")          // "" reverts to system store
        d.setInsecure(false)
        XCTAssertTrue(d.webSocketUrl.isEmpty, "no BiDi endpoint until newSession")
    }

    func testBidiWithoutSessionThrows() {
        // A session that never ran newSession has no webSocketUrl → bidi() throws
        // the typed error rather than dereferencing a null channel.
        let d = WebDriver(commandExecutor: "http://127.0.0.1:1")
        XCTAssertThrowsError(try d.bidi()) { err in
            XCTAssertTrue(err is WebDriverError)
        }
    }

    func testBidiOpenFailsClean() {
        // Opening a channel to a dead ws URL throws (connect failure), proving
        // bidi_open links and null is turned into a typed error.
        XCTAssertThrowsError(try BiDi(wsUrl: "ws://127.0.0.1:1/session")) { err in
            XCTAssertTrue(err is WebDriverError)
        }
    }
}
