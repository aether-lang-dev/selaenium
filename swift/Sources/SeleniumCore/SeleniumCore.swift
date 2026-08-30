// SeleniumCore.swift — the Swift binding over the shared Aether engine.
//
// Swift calls the engine's flat C ABI (aether_sel_embed_*) DIRECTLY through the
// CSeleniumCore module map — no glue .c, no second copy of the marshalling rules
// to drift from selenium_core/embed.ae. This file is the idiomatic Swift surface:
// a typed `By`, automatic caller-owned-string handling, typed errors, and a
// `WebDriver` with the W3C operations. The engine .so is resolved via
// SELENIUM_CORE_LIB (linked at build; see Package.swift linker settings).
import CSeleniumCore

/// Locator strategies (the same string values the engine's by_locator expects).
public enum By: String {
    case id = "id"
    case name = "name"
    case css = "css selector"
    case className = "className"
    case tagName = "tag name"
    case linkText = "link text"
    case partialLinkText = "partial link text"
    case xpath = "xpath"
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

public func locator(_ by: By, _ value: String) -> String {
    take(aether_sel_embed_by_locator(by.rawValue, value))
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

    public func quit() {
        _ = try? execute("quit", "{}")
    }

    public var sessionId: String { take(aether_sel_embed_session_id(handle)) }
}
