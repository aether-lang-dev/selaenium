// Selenium.swift — the Swift binding over the shared Aether engine.
//
// Swift calls the engine's flat C ABI (aether_sel_embed_*) DIRECTLY through the
// CSeleniumCore module map — no glue .c, no second copy of the marshalling rules
// to drift from selenium_core/embed.ae. This file is the idiomatic Swift surface:
// a `By` factory, automatic caller-owned-string handling, typed errors, and a
// `WebDriver` with the W3C operations. The engine .so is resolved via
// SELENIUM_CORE_LIB (linked at build; see Package.swift linker settings).
import Foundation
import CSeleniumCore

/// A Selenium-style locator carrying a (strategy, value) pair. Built with the
/// static By factory — `By.id("x")`, `By.className("x")` — mirroring Selenium's
/// By, and passed to `WebDriver.findElement(_:)`. The strategy strings are the
/// ones the engine's by_locator understands; `className` maps to the W3C
/// "class name" (matching every other Selenium binding).
public struct By {
    public let strategy: String
    public let value: String

    public init(strategy: String, value: String) {
        self.strategy = strategy
        self.value = value
    }

    public static func id(_ value: String) -> By { By(strategy: "id", value: value) }
    public static func name(_ value: String) -> By { By(strategy: "name", value: value) }
    public static func className(_ value: String) -> By { By(strategy: "class name", value: value) }
    public static func cssSelector(_ value: String) -> By { By(strategy: "css selector", value: value) }
    public static func css(_ value: String) -> By { By(strategy: "css selector", value: value) }
    public static func tagName(_ value: String) -> By { By(strategy: "tag name", value: value) }
    public static func linkText(_ value: String) -> By { By(strategy: "link text", value: value) }
    public static func partialLinkText(_ value: String) -> By { By(strategy: "partial link text", value: value) }
    public static func xpath(_ value: String) -> By { By(strategy: "xpath", value: value) }
}

/// A typed WebDriver error carrying the W3C error code (-1 = transport failure).
public struct WebDriverError: Error {
    public let message: String
    public let code: Int32
}

// Take ownership of a C string the engine returned, copy to a Swift String, and
// free it via the engine's allocator (never free()).
private func take(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let p = ptr else { return "" }
    let s = String(cString: p)
    _ = aether_sel_embed_free_string(p)
    return s
}

// ---- pure engine helpers (no session) — shared with every binding ----

public func route(_ command: String) -> String {
    take(aether_sel_embed_route(command))
}

public func errorCode(_ w3cError: String) -> Int32 {
    aether_sel_embed_error_code(w3cError)
}

/// The W3C {"using","value"} locator JSON for a By.
public func locator(_ by: By) -> String {
    take(aether_sel_embed_by_locator(by.strategy, by.value))
}

// ---- session ----

public final class WebDriver {
    private let handle: UnsafeMutableRawPointer

    /// Open a session bound to a remote-end URL (e.g. a chromedriver or Grid URL).
    /// No network I/O until `execute("newSession", …)`.
    public init(commandExecutor url: String) {
        self.handle = aether_sel_embed_open(url)
    }

    deinit { aether_sel_embed_close(handle) }

    /// Run a WebDriver command by name with JSON params. Returns the result value
    /// (raw JSON), throwing a typed WebDriverError on a protocol/transport error.
    @discardableResult
    public func execute(_ name: String, _ paramsJSON: String = "{}") throws -> String {
        let rc = aether_sel_embed_execute(handle, name, paramsJSON)
        if rc != 0 {
            let msg = take(aether_sel_embed_last_error(handle))
            let code = aether_sel_embed_last_error_code(handle)
            throw WebDriverError(message: msg, code: rc == -1 && code == 0 ? -1 : code)
        }
        return take(aether_sel_embed_last_value(handle))
    }

    /// Find one element (Selenium-style one-arg find): `findElement(By.id("x"))`.
    /// Returns the W3C element reference id, throwing a typed WebDriverError on a
    /// protocol/transport error (e.g. no such element).
    @discardableResult
    public func findElement(_ by: By) throws -> String {
        let params = take(aether_sel_embed_by_locator(by.strategy, by.value))
        let value = try execute("findElement", params)
        guard let id = Self.extractElementId(value) else {
            throw WebDriverError(message: "element reference key missing", code: 17)
        }
        return id
    }

    // Pull the element-reference id out of a findElement value JSON string. The
    // value looks like {"element-6066-...":"<id>"}; a small textual extraction
    // keeps this dependency-free (mirrors the Gleam/LFE bindings).
    private static let w3cElementKey = "element-6066-11e4-a52e-4f735466cecf"
    private static func extractElementId(_ json: String) -> String? {
        let needle = "\"\(w3cElementKey)\":\""
        guard let start = json.range(of: needle) else { return nil }
        let rest = json[start.upperBound...]
        guard let end = rest.range(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end.lowerBound])
    }

    public func quit() {
        _ = try? execute("quit", "{}")
    }

    public var sessionId: String { take(aether_sel_embed_session_id(handle)) }
}
