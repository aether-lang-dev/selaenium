// Selenium.swift — the Swift binding over the shared Aether engine.
//
// Swift calls the engine's flat C ABI (aether_sel_embed_*) DIRECTLY through the
// CSeleniumCore module map — no glue .c, no second copy of the marshalling rules
// to drift from selenium_core/embed.ae. This file is the idiomatic Swift surface:
// a `By` factory, automatic caller-owned-string handling, typed errors, and a
// `WebDriver`/`WebElement` pair carrying the W3C operations, plus the classic
// convenience tier (Keys, Select, Actions, explicit waits). The engine .so is
// resolved via SELENIUM_CORE_LIB (linked at build; see Package.swift).
//
// FFI scope: the CSeleniumCore header declares only the GENERIC seam — open /
// close / execute / by_locator / route / error_code / session_id / free_string.
// Every command below is issued by name + JSON params through `execute`, so no
// per-command native symbols are needed. Features that mainstream reaches through
// DEDICATED engine symbols not present in this header — atom-backed isDisplayed /
// getAttribute, relative locators, TLS trust config, in-binding driver
// orchestration (local_chrome / ensure_driver / resolve_driver / launch_driver),
// and the WebDriver-BiDi channel — are intentionally NOT provided here; see the
// "freestyle limitations" note at the end. `getAttribute` is offered via an
// injected-script fallback so the classic call still works.
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

/// A frame target for `WebDriver.switchToFrame(_:)`. The W3C `switchToFrame`
/// command's `id` may be an unsigned index, a frame element reference, or null
/// (top-level context) — this enum makes those three shapes explicit rather than
/// overloading one stringly-typed argument.
public enum Frame {
    /// The frame at this 0-based index among the current context's child frames.
    case index(Int)
    /// The frame whose `<iframe>`/`<frame>` element has this W3C element id.
    case element(String)
    /// The top-level browsing context.
    case defaultContent

    /// Build a frame target from a located `<iframe>`/`<frame>` element.
    public static func of(_ element: WebElement) -> Frame { .element(element.id) }

    /// The W3C `id` value for this frame target: a number, an element-reference
    /// object, or NSNull.
    fileprivate var idJSON: Any {
        switch self {
        case .index(let i): return i
        case .element(let id): return [WebElement.w3cElementKey: id]
        case .defaultContent: return NSNull()
        }
    }
}

/// A typed WebDriver error carrying the W3C error code (-1 = transport failure).
public struct WebDriverError: Error {
    public let message: String
    public let code: Int32

    /// The stable W3C code for "no such element" (a clean miss on findElement).
    public static let noSuchElement: Int32 = 17
    /// The stable W3C code for "no such alert" (probed by `alertPresent`).
    public static let noSuchAlert: Int32 = 15
}

// Take ownership of a C string the engine returned, copy to a Swift String, and
// free it via the engine's allocator (never free()).
private func take(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let p = ptr else { return "" }
    let s = String(cString: p)
    _ = aether_sel_embed_free_string(p)
    return s
}

// ---- tiny JSON helpers (Foundation-backed) ----
// The engine speaks JSON on the seam; these turn Swift dictionaries/arrays into
// the compact JSON `execute` expects and decode results back. Keeping them here
// avoids a second copy of any protocol logic — only (de)serialization lives in
// the binding, exactly as the Rust reference's json.rs does.

private func encodeJSON(_ obj: Any) -> String {
    // The engine tolerates any well-formed JSON object/array as params. Empty or
    // un-encodable input degrades to "{}", never a crash.
    guard JSONSerialization.isValidJSONObject(obj),
          let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
          let s = String(data: data, encoding: .utf8)
    else { return "{}" }
    return s
}

private func decodeJSON(_ s: String) -> Any? {
    guard let data = s.data(using: .utf8), !data.isEmpty else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
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
    let handle: UnsafeMutableRawPointer
    // The BiDi endpoint advertised by newSession (webSocketUrl), "" if none.
    private(set) public var webSocketUrl: String = ""
    // Retains an engine-launched driver process so it outlives the session.
    var driverProcess: DriverProcess?
    // Lazily-opened BiDi channel (never opened by a classic script).
    private var _bidi: BiDi?

    /// Open a session bound to a remote-end URL (e.g. a chromedriver or Grid URL).
    /// No network I/O until `execute("newSession", …)`.
    public init(commandExecutor url: String) {
        self.handle = aether_sel_embed_open(url)
    }

    deinit { aether_sel_embed_close(handle) }

    // ---- factories ----

    /// Start a Chrome session against a running chromedriver (or Grid). `options`
    /// is a JSON-object dictionary of extra capabilities merged under
    /// browserName: chrome. Throws on a protocol/transport error at newSession.
    @discardableResult
    public static func chrome(
        commandExecutor url: String = "http://127.0.0.1:9515",
        options: [String: Any]? = nil
    ) throws -> WebDriver {
        var caps: [String: Any] = options ?? [:]
        caps["browserName"] = "chrome"
        let d = WebDriver(commandExecutor: url)
        try d.startSession(caps)
        return d
    }

    // Request a BiDi channel (webSocketUrl:true) at newSession and capture the
    // advertised endpoint. The socket itself opens lazily via bidi().
    private func startSession(_ caps: [String: Any]) throws {
        var match = caps
        match["webSocketUrl"] = true
        let raw = try execute("newSession", encodeJSON(["capabilities": ["alwaysMatch": match]]))
        if let obj = decodeJSON(raw) as? [String: Any] {
            // Some remote ends nest capabilities; accept either shape.
            let caps = (obj["capabilities"] as? [String: Any]) ?? obj
            self.webSocketUrl = (caps["webSocketUrl"] as? String) ?? ""
        }
    }

    /// Open (once) and return the WebDriver-BiDi channel for this session. Throws
    /// if the session advertised no webSocketUrl or the socket won't connect.
    public func bidi() throws -> BiDi {
        if let b = _bidi { return b }
        guard !webSocketUrl.isEmpty else {
            throw WebDriverError(message: "session has no BiDi webSocketUrl", code: -1)
        }
        let b = try BiDi(wsUrl: webSocketUrl)
        _bidi = b
        return b
    }

    /// Convenience: headless-Chrome launch args baked in.
    @discardableResult
    public static func headlessChrome(
        commandExecutor url: String = "http://127.0.0.1:9515"
    ) throws -> WebDriver {
        let opts: [String: Any] = [
            "goog:chromeOptions": [
                "args": ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
            ]
        ]
        return try chrome(commandExecutor: url, options: opts)
    }

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

    // Issue a command whose params are a Swift dictionary; return the decoded
    // value (Any?, or nil when the command produced no value).
    @discardableResult
    func exec(_ name: String, _ params: [String: Any] = [:]) throws -> Any? {
        let raw = try execute(name, encodeJSON(params))
        return decodeJSON(raw)
    }

    // Issue a command and coerce its value to String ("" when absent/non-string).
    func execString(_ name: String, _ params: [String: Any] = [:]) throws -> String {
        (try exec(name, params)) as? String ?? ""
    }

    // Issue a command and coerce its value to Bool (false when absent/non-bool).
    func execBool(_ name: String, _ params: [String: Any] = [:]) throws -> Bool {
        (try exec(name, params)) as? Bool ?? false
    }

    // ---- atom-backed commands (dedicated engine symbols, no W3C route) ----
    // Drain the atom rc the same way execute() does: last_value on success, a
    // typed WebDriverError otherwise.
    private func drainAtom(_ rc: Int32) throws -> Any? {
        if rc != 0 {
            let msg = take(aether_sel_embed_last_error(handle))
            let code = aether_sel_embed_last_error_code(handle)
            throw WebDriverError(message: msg, code: rc == -1 && code == 0 ? -1 : code)
        }
        return decodeJSON(take(aether_sel_embed_last_value(handle)))
    }

    // Run an atom (isDisplayed / getAttribute / getText / …) against an element.
    // extraJSON is a JSON array of extra args ("[]"/"" for none).
    @discardableResult
    func executeAtom(_ atomName: String, _ elemId: String, _ extraJSON: String = "") throws -> Any? {
        try drainAtom(aether_sel_embed_execute_atom(handle, atomName, elemId, extraJSON))
    }

    func atomIsDisplayed(_ elemId: String) throws -> Bool {
        (try drainAtom(aether_sel_embed_is_displayed(handle, elemId))) as? Bool ?? false
    }

    func atomGetAttribute(_ elemId: String, _ name: String) throws -> String? {
        let v = try drainAtom(aether_sel_embed_get_attribute(handle, elemId, name))
        if v == nil || v is NSNull { return nil }
        if let s = v as? String { return s }
        if let b = v as? Bool { return b ? "true" : "false" }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    // ---- relative locators (findElementsRelative atom) ----
    // baseSel is a CSS anchor; filters is a JSON array of {kind, sel[, dist]} with
    // kind in above/below/left/right/near. Returns matching elements, nearest first.
    public func findRelative(_ baseSel: String, _ filters: [[String: Any]]) throws -> [WebElement] {
        let rc = aether_sel_embed_find_relative(handle, baseSel, encodeJSON(filters))
        let v = try drainAtom(rc) as? [[String: Any]] ?? []
        return v.compactMap { ref in
            (ref[WebElement.w3cElementKey] as? String).map { WebElement(driver: self, id: $0) }
        }
    }

    public func findRelativeCount(_ baseSel: String, _ filters: [[String: Any]]) throws -> Int {
        try findRelative(baseSel, filters).count
    }

    // ---- TLS trust config (call before the first execute / newSession) ----
    /// Pin the peer certificate against a private CA file ("" reverts to the
    /// system store). For a Grid served over HTTPS with its own CA.
    public func setCa(_ caPath: String) { aether_sel_embed_set_ca(handle, caPath) }
    /// Skip TLS verification (self-signed dev/staging Grid). `on` true to skip.
    public func setInsecure(_ on: Bool) { aether_sel_embed_set_insecure(handle, on ? 1 : 0) }

    /// Start a Chrome session over an https:// Grid with TLS trust configured
    /// before newSession. `caPath` pins a private CA; `insecure` skips verification.
    @discardableResult
    public static func chromeTls(
        commandExecutor url: String,
        options: [String: Any]? = nil,
        caPath: String? = nil,
        insecure: Bool = false
    ) throws -> WebDriver {
        var caps: [String: Any] = options ?? [:]
        caps["browserName"] = "chrome"
        let d = WebDriver(commandExecutor: url)
        if let ca = caPath { d.setCa(ca) }
        if insecure { d.setInsecure(true) }
        try d.startSession(caps)
        return d
    }

    // ---- navigation ----

    /// Navigate to `url` (the classic `driver.get(url)`).
    public func get(_ url: String) throws {
        _ = try exec("get", ["url": url])
    }
    public var currentUrl: String { (try? execString("getCurrentUrl")) ?? "" }
    public func currentURL() throws -> String { try execString("getCurrentUrl") }
    public func title() throws -> String { try execString("getTitle") }
    public func pageSource() throws -> String { try execString("getPageSource") }
    public func back() throws { _ = try exec("goBack") }
    public func forward() throws { _ = try exec("goForward") }
    public func refresh() throws { _ = try exec("refresh") }

    // ---- elements ----

    /// Find one element (Selenium-style one-arg find): `findElement(By.id("x"))`.
    /// Returns a `WebElement`, throwing a typed WebDriverError on a protocol /
    /// transport error (e.g. no such element).
    public func findElement(_ by: By) throws -> WebElement {
        let params = take(aether_sel_embed_by_locator(by.strategy, by.value))
        let value = try execute("findElement", params)
        guard let id = WebElement.extractElementId(value) else {
            throw WebDriverError(message: "element reference key missing", code: WebDriverError.noSuchElement)
        }
        return WebElement(driver: self, id: id)
    }

    /// Find every element matching `by` (may be empty).
    public func findElements(_ by: By) throws -> [WebElement] {
        let params = take(aether_sel_embed_by_locator(by.strategy, by.value))
        let value = try execute("findElements", params)
        let arr = (decodeJSON(value) as? [[String: Any]]) ?? []
        return arr.compactMap { ref in
            (ref[WebElement.w3cElementKey] as? String).map { WebElement(driver: self, id: $0) }
        }
    }

    /// True if at least one element matching `by` is present RIGHT NOW — an
    /// immediate presence check with no implicit wait. A clean element-not-found
    /// resolves to `false`; a transport-level failure still throws.
    public func exists(_ by: By) throws -> Bool {
        do {
            _ = try findElement(by)
            return true
        } catch let e as WebDriverError where e.code == WebDriverError.noSuchElement {
            return false
        }
    }

    /// The active (focused) element (`getActiveElement`).
    public func activeElement() throws -> WebElement {
        let value = try execute("getActiveElement", "{}")
        guard let id = WebElement.extractElementId(value) else {
            throw WebDriverError(message: "element reference key missing", code: WebDriverError.noSuchElement)
        }
        return WebElement(driver: self, id: id)
    }

    // ---- script ----

    /// Run a synchronous script; `args` are JSON-encodable values. Returns the
    /// decoded result value (Any?).
    @discardableResult
    public func executeScript(_ script: String, _ args: [Any] = []) throws -> Any? {
        try exec("executeScript", ["script": script, "args": args])
    }

    /// Run an async script: the page signals completion via the injected callback
    /// (`arguments[arguments.length - 1]`). Returns the callback value.
    @discardableResult
    public func executeAsyncScript(_ script: String, _ args: [Any] = []) throws -> Any? {
        try exec("executeAsyncScript", ["script": script, "args": args])
    }

    // ---- windows ----

    public func windowHandles() throws -> [String] {
        (try exec("getWindowHandles")) as? [String] ?? []
    }
    public func currentWindowHandle() throws -> String { try execString("getCurrentWindowHandle") }

    /// Switch the session's top-level browsing context to the window `handle`.
    public func switchToWindow(_ handle: String) throws {
        _ = try exec("switchToWindow", ["handle": handle])
    }
    @discardableResult
    public func setWindowRect(_ rect: [String: Any]) throws -> Any? { try exec("setWindowRect", rect) }
    @discardableResult
    public func getWindowRect() throws -> Any? { try exec("getWindowRect") }
    @discardableResult
    public func maximizeWindow() throws -> Any? { try exec("maximizeWindow") }
    @discardableResult
    public func minimizeWindow() throws -> Any? { try exec("minimizeWindow") }
    @discardableResult
    public func fullscreenWindow() throws -> Any? { try exec("fullscreenWindow") }

    /// Open a new top-level browsing context (`newWindow`). `typeHint` is "tab"
    /// or "window". Returns the new window's handle ("" if the remote end sent
    /// none) — pass it to `switchToWindow`.
    public func newWindow(_ typeHint: String = "tab") throws -> String {
        let v = try exec("newWindow", ["type": typeHint]) as? [String: Any]
        return (v?["handle"] as? String) ?? ""
    }

    /// Close the current window/tab (`close`). Returns the window handles that
    /// remain. Does NOT end the session (use `quit()` for that).
    @discardableResult
    public func closeWindow() throws -> [String] {
        (try exec("close")) as? [String] ?? []
    }

    // ---- frames ----

    /// Switch focus to a frame (`switchToFrame`): by `.index`, by `.element`
    /// (or `Frame.of(webElement)`), or `.defaultContent` for the top-level.
    public func switchToFrame(_ frame: Frame) throws {
        _ = try exec("switchToFrame", ["id": frame.idJSON])
    }

    /// Switch to the parent of the current frame — one level out, unlike
    /// `switchToDefaultContent` which jumps to the top.
    public func switchToParentFrame() throws {
        _ = try exec("switchToFrameParent")
    }

    /// Return focus to the top-level browsing context.
    public func switchToDefaultContent() throws {
        try switchToFrame(.defaultContent)
    }

    // ---- alerts ----

    public func acceptAlert() throws { _ = try exec("acceptAlert") }
    public func dismissAlert() throws { _ = try exec("dismissAlert") }
    public func alertText() throws -> String { try execString("getAlertText") }

    /// Type `text` into the current prompt dialog's input field.
    public func sendAlertText(_ text: String) throws {
        _ = try exec("setAlertValue", ["text": text])
    }

    /// True if a user-prompt / alert dialog is currently present (probed via
    /// `getAlertText`). A clean "no such alert" resolves to `false`; a
    /// transport-level failure still throws.
    public func alertPresent() throws -> Bool {
        do {
            _ = try exec("getAlertText")
            return true
        } catch let e as WebDriverError where e.code == WebDriverError.noSuchAlert {
            return false
        }
    }

    // ---- cookies ----

    public func addCookie(_ cookie: [String: Any]) throws {
        _ = try exec("addCookie", ["cookie": cookie])
    }
    @discardableResult
    public func getCookies() throws -> Any? { try exec("getCookies") }
    @discardableResult
    public func getCookie(_ name: String) throws -> Any? { try exec("getCookie", ["name": name]) }
    public func deleteCookie(_ name: String) throws { _ = try exec("deleteCookie", ["name": name]) }
    public func deleteAllCookies() throws { _ = try exec("deleteAllCookies") }

    // ---- actions ----

    /// Start a fluent `Actions` builder bound to this driver: queue pointer / key
    /// gestures, then `.perform()`.
    public func actions() -> Actions { Actions(driver: self) }

    /// Post a pre-built W3C actions array in one `actions` command.
    public func performActions(_ actions: [Any]) throws {
        _ = try exec("actions", ["actions": actions])
    }
    public func clearActions() throws { _ = try exec("clearActions") }

    // ---- timeouts (all values in milliseconds) ----

    public func setTimeouts(_ timeouts: [String: Any]) throws { _ = try exec("setTimeout", timeouts) }
    public func setPageLoadTimeout(ms: Int) throws { _ = try exec("setTimeout", ["pageLoad": ms]) }
    public func setScriptTimeout(ms: Int) throws { _ = try exec("setTimeout", ["script": ms]) }
    public func implicitlyWait(ms: Int) throws { _ = try exec("setTimeout", ["implicit": ms]) }

    // ---- screenshots ----

    public func screenshotBase64() throws -> String { try execString("screenshot") }

    /// Print the current page to PDF (`printPage`), returning the PDF as a
    /// base64 string. `options` is the W3C print-options object; pass nil for
    /// defaults.
    public func printPDF(_ options: [String: Any]? = nil) throws -> String {
        try execString("printPage", options ?? [:])
    }

    // ---- explicit waits ----

    /// Start an explicit wait with `timeout` seconds. Poll cadence defaults to
    /// 0.5s; override with `Wait.pollEvery(_:)`.
    public func wait(_ timeout: TimeInterval) -> Wait {
        Wait(driver: self, timeout: timeout)
    }

    // ---- lifecycle ----

    public func quit() {
        _ = try? execute("quit", "{}")
    }

    public var sessionId: String { take(aether_sel_embed_session_id(handle)) }
}

// ---- WebElement ----

/// A remote element handle. Methods issue element-scoped commands, passing this
/// element's id as the `:id` path parameter.
public final class WebElement {
    private unowned let driver: WebDriver
    public let id: String

    init(driver: WebDriver, id: String) {
        self.driver = driver
        self.id = id
    }

    static let w3cElementKey = "element-6066-11e4-a52e-4f735466cecf"

    // Pull the element-reference id out of a findElement value JSON string. The
    // value looks like {"element-6066-...":"<id>"}; a small textual extraction
    // keeps this dependency-free (mirrors the Gleam/LFE bindings).
    static func extractElementId(_ json: String) -> String? {
        let needle = "\"\(w3cElementKey)\":\""
        guard let start = json.range(of: needle) else { return nil }
        let rest = json[start.upperBound...]
        guard let end = rest.range(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end.lowerBound])
    }

    // Element-scoped exec: fold this element's id into the params, then issue.
    @discardableResult
    private func exec(_ command: String, _ params: [String: Any] = [:]) throws -> Any? {
        var p = params
        p["id"] = id
        return try driver.exec(command, p)
    }

    private func execString(_ command: String, _ params: [String: Any] = [:]) throws -> String {
        (try exec(command, params)) as? String ?? ""
    }

    private func execBool(_ command: String, _ params: [String: Any] = [:]) throws -> Bool {
        (try exec(command, params)) as? Bool ?? false
    }

    public func click() throws { _ = try exec("clickElement") }
    public func clear() throws { _ = try exec("clearElement") }

    /// Type `text` into this element. Accepts `Keys` constants embedded in the
    /// string; the engine forwards the code points unchanged.
    public func sendKeys(_ text: String) throws {
        let chars = text.map { String($0) }
        _ = try exec("sendKeysToElement", ["text": text, "value": chars])
    }

    public func text() throws -> String { try execString("getElementText") }
    public func tagName() throws -> String { try execString("getElementTagName") }
    public func isEnabled() throws -> Bool { try execBool("isElementEnabled") }
    public func isSelected() throws -> Bool { try execBool("isElementSelected") }
    @discardableResult
    public func rect() throws -> Any? { try exec("getElementRect") }

    /// The literal DOM attribute (W3C getDomAttribute), no property fallback.
    @discardableResult
    public func getDomAttribute(_ name: String) throws -> Any? {
        try exec("getDomAttribute", ["name": name])
    }
    @discardableResult
    public func getProperty(_ name: String) throws -> Any? {
        try exec("getElementProperty", ["name": name])
    }

    /// The classic getAttribute(name): property-or-attribute semantics, via the
    /// engine's dedicated getAttribute atom (the ONE shared atom source, not a
    /// per-binding script). Returns nil when the attribute is absent.
    public func getAttribute(_ name: String) throws -> String? {
        try driver.atomGetAttribute(id, name)
    }

    /// Is this element displayed? Uses the engine's dedicated isDisplayed atom.
    public func isDisplayed() throws -> Bool {
        try driver.atomIsDisplayed(id)
    }

    /// The computed value of the CSS property `prop` on this element
    /// (`getElementValueOfCssProperty`). `valueOfCssProperty` is the
    /// classic-Selenium-named alias.
    public func cssValue(_ prop: String) throws -> String {
        try execString("getElementValueOfCssProperty", ["propertyName": prop])
    }
    public func valueOfCssProperty(_ prop: String) throws -> String { try cssValue(prop) }

    /// A PNG screenshot of just this element (`takeElementScreenshot`), base64.
    public func screenshotBase64() throws -> String {
        try execString("takeElementScreenshot")
    }

    /// Submit the form this element belongs to. W3C removed the dedicated
    /// `submit` endpoint, so — like the reference binding and modern Selenium —
    /// this walks up to the enclosing `<form>` and calls `requestSubmit()`
    /// (falling back to `submit()`) via an injected script. Throws (noSuchElement)
    /// if the element is not inside a form.
    public func submit() throws {
        let script = """
        var e=arguments[0];var f=e.form||e.closest('form');\
        if(!f){throw new Error('Element is not within a form');}\
        if(f.requestSubmit){f.requestSubmit();}else{f.submit();}
        """
        let arg: [String: Any] = [WebElement.w3cElementKey: id]
        _ = try driver.executeScript(script, [arg])
    }

    /// Find one descendant matching `by` (element-scoped `findChildElement`).
    public func findElement(_ by: By) throws -> WebElement {
        let value = try exec("findChildElement", decodeBy(by)) as? [String: Any]
        guard let ref = value?[WebElement.w3cElementKey] as? String else {
            throw WebDriverError(message: "element reference key missing", code: WebDriverError.noSuchElement)
        }
        return WebElement(driver: driver, id: ref)
    }

    /// Find all descendants matching `by` (element-scoped `findChildElements`).
    public func findElements(_ by: By) throws -> [WebElement] {
        let value = try exec("findChildElements", decodeBy(by)) as? [[String: Any]] ?? []
        return value.compactMap { ref in
            (ref[WebElement.w3cElementKey] as? String).map { WebElement(driver: driver, id: $0) }
        }
    }

    // The {"using","value"} object for a By, decoded from the engine's locator
    // JSON so id/name are rewritten to CSS exactly as the driver-level finds are.
    private func decodeBy(_ by: By) -> [String: Any] {
        let raw = take(aether_sel_embed_by_locator(by.strategy, by.value))
        return (decodeJSON(raw) as? [String: Any]) ?? ["using": by.strategy, "value": by.value]
    }
}

// ---- Keys ----

/// Special keys — the W3C WebDriver Unicode private-use code points for non-text
/// keys (W3C §17.4.2). Mirrors mainstream Selenium's `Keys`: send them through
/// `WebElement.sendKeys` or an `Actions` key gesture; the values are the same
/// code points the protocol defines, so the engine forwards them unchanged.
public enum Keys {
    public static let null = "\u{E000}"
    public static let cancel = "\u{E001}"
    public static let help = "\u{E002}"
    public static let backspace = "\u{E003}"
    public static let tab = "\u{E004}"
    public static let clear = "\u{E005}"
    public static let `return` = "\u{E006}"
    public static let enter = "\u{E007}"
    public static let shift = "\u{E008}"
    public static let control = "\u{E009}"
    public static let alt = "\u{E00A}"
    public static let pause = "\u{E00B}"
    public static let escape = "\u{E00C}"
    public static let space = "\u{E00D}"
    public static let pageUp = "\u{E00E}"
    public static let pageDown = "\u{E00F}"
    public static let end = "\u{E010}"
    public static let home = "\u{E011}"
    public static let left = "\u{E012}"
    public static let arrowLeft = "\u{E012}"
    public static let up = "\u{E013}"
    public static let arrowUp = "\u{E013}"
    public static let right = "\u{E014}"
    public static let arrowRight = "\u{E014}"
    public static let down = "\u{E015}"
    public static let arrowDown = "\u{E015}"
    public static let insert = "\u{E016}"
    public static let delete = "\u{E017}"
    public static let semicolon = "\u{E018}"
    public static let equals = "\u{E019}"
    public static let numpad0 = "\u{E01A}"
    public static let numpad1 = "\u{E01B}"
    public static let numpad2 = "\u{E01C}"
    public static let numpad3 = "\u{E01D}"
    public static let numpad4 = "\u{E01E}"
    public static let numpad5 = "\u{E01F}"
    public static let numpad6 = "\u{E020}"
    public static let numpad7 = "\u{E021}"
    public static let numpad8 = "\u{E022}"
    public static let numpad9 = "\u{E023}"
    public static let multiply = "\u{E024}"
    public static let add = "\u{E025}"
    public static let separator = "\u{E026}"
    public static let subtract = "\u{E027}"
    public static let decimal = "\u{E028}"
    public static let divide = "\u{E029}"
    public static let f1 = "\u{E031}"
    public static let f2 = "\u{E032}"
    public static let f3 = "\u{E033}"
    public static let f4 = "\u{E034}"
    public static let f5 = "\u{E035}"
    public static let f6 = "\u{E036}"
    public static let f7 = "\u{E037}"
    public static let f8 = "\u{E038}"
    public static let f9 = "\u{E039}"
    public static let f10 = "\u{E03A}"
    public static let f11 = "\u{E03B}"
    public static let f12 = "\u{E03C}"
    public static let meta = "\u{E03D}"
    public static let command = "\u{E03D}"

    /// A modifier chord: `modifier` held while `text` is typed, then closed by
    /// the terminating NULL that the protocol uses to release held modifiers —
    /// e.g. `Keys.chord(Keys.control, "a")` for select-all.
    public static func chord(_ modifier: String, _ text: String) -> String {
        modifier + text + null
    }
}

// ---- Select ----

/// A `<select>` dropdown helper — the `Select` convenience tier. Wraps a
/// `<select>` `WebElement` and drives it by finding and clicking its `<option>`
/// children, the same approach mainstream Selenium's `Select` uses. Throws if the
/// wrapped element is not a `<select>`.
public final class Select {
    private let element: WebElement
    public let isMultiple: Bool

    public init(_ element: WebElement) throws {
        let tag = try element.tagName().lowercased()
        if tag != "select" {
            throw WebDriverError(message: "Select only works on <select> elements, not <\(tag)>", code: 0)
        }
        // `multiple` is a boolean attribute: present (any non-"false" value) ==
        // multi-select. Mirrors the reference truthiness check.
        let multi = try element.getAttribute("multiple")
        if let v = multi { self.isMultiple = !v.isEmpty && v != "false" } else { self.isMultiple = false }
        self.element = element
    }

    /// All `<option>` children, in document order.
    public func options() throws -> [WebElement] {
        try element.findElements(By.tagName("option"))
    }

    /// The options currently selected.
    public func allSelectedOptions() throws -> [WebElement] {
        try options().filter { try $0.isSelected() }
    }

    /// The first selected option. Throws (noSuchElement) if none is selected.
    public func firstSelectedOption() throws -> WebElement {
        for o in try options() where try o.isSelected() { return o }
        throw WebDriverError(message: "no option is selected", code: WebDriverError.noSuchElement)
    }

    /// Select the option whose visible text equals `text`.
    public func selectByVisibleText(_ text: String) throws {
        for o in try options() where try o.text() == text {
            try selectOption(o); return
        }
        throw WebDriverError(message: "no option with visible text \(text)", code: WebDriverError.noSuchElement)
    }

    /// Select the option whose `value` attribute equals `value`.
    public func selectByValue(_ value: String) throws {
        for o in try options() where (try o.getAttribute("value")) == value {
            try selectOption(o); return
        }
        throw WebDriverError(message: "no option with value \(value)", code: WebDriverError.noSuchElement)
    }

    /// Select the option at `index` (0-based, document order).
    public func selectByIndex(_ index: Int) throws {
        let opts = try options()
        guard index >= 0 && index < opts.count else {
            throw WebDriverError(message: "no option at index \(index)", code: WebDriverError.noSuchElement)
        }
        try selectOption(opts[index])
    }

    /// Deselect every selected option (multi-select only). Throws on a
    /// single-select, mirroring the mainstream NotImplementedError.
    public func deselectAll() throws {
        if !isMultiple {
            throw WebDriverError(message: "deselectAll only makes sense on a multi-select", code: 0)
        }
        for o in try options() where try o.isSelected() { try o.click() }
    }

    // Click an option to select it, but only if it isn't already selected — a
    // second click on a selected single-select option is a no-op, but on a
    // multi-select it would toggle it off.
    private func selectOption(_ option: WebElement) throws {
        if try !option.isSelected() { try option.click() }
    }
}

// ---- Actions ----

/// A queued sequence of W3C input actions, built fluently and posted in one
/// `actions` command by `perform()`. Obtain one from `WebDriver.actions()`.
public final class Actions {
    private let driver: WebDriver
    private var pointer: [[String: Any]] = []
    private var key: [[String: Any]] = []

    init(driver: WebDriver) { self.driver = driver }

    private func pauseAction(_ ms: Int) -> [String: Any] { ["type": "pause", "duration": ms] }
    private func moveTo(_ id: String) -> [String: Any] {
        ["type": "pointerMove", "duration": 100, "x": 0, "y": 0,
         "origin": [WebElement.w3cElementKey: id]]
    }
    private func buttonDown(_ b: Int) -> [String: Any] { ["type": "pointerDown", "button": b] }
    private func buttonUp(_ b: Int) -> [String: Any] { ["type": "pointerUp", "button": b] }
    private func keyEvent(_ kind: String, _ value: String) -> [String: Any] { ["type": kind, "value": value] }

    // W3C requires every device's action list to be the same length; pad the
    // shorter device with zero-duration pauses so gestures don't desync ticks.
    private func syncLengths() {
        let n = max(pointer.count, key.count)
        while pointer.count < n { pointer.append(pauseAction(0)) }
        while key.count < n { key.append(pauseAction(0)) }
    }

    @discardableResult
    public func moveToElement(_ element: WebElement) -> Actions {
        pointer.append(moveTo(element.id)); syncLengths(); return self
    }

    @discardableResult
    public func click(_ element: WebElement? = nil) -> Actions {
        if let e = element { pointer.append(moveTo(e.id)) }
        pointer.append(buttonDown(0)); pointer.append(buttonUp(0)); syncLengths(); return self
    }

    @discardableResult
    public func contextClick(_ element: WebElement? = nil) -> Actions {
        if let e = element { pointer.append(moveTo(e.id)) }
        pointer.append(buttonDown(2)); pointer.append(buttonUp(2)); syncLengths(); return self
    }

    @discardableResult
    public func doubleClick(_ element: WebElement? = nil) -> Actions {
        if let e = element { pointer.append(moveTo(e.id)) }
        for _ in 0..<2 { pointer.append(buttonDown(0)); pointer.append(buttonUp(0)) }
        syncLengths(); return self
    }

    @discardableResult
    public func clickAndHold(_ element: WebElement? = nil) -> Actions {
        if let e = element { pointer.append(moveTo(e.id)) }
        pointer.append(buttonDown(0)); syncLengths(); return self
    }

    @discardableResult
    public func release(_ element: WebElement? = nil) -> Actions {
        if let e = element { pointer.append(moveTo(e.id)) }
        pointer.append(buttonUp(0)); syncLengths(); return self
    }

    @discardableResult
    public func dragAndDrop(_ source: WebElement, _ target: WebElement) -> Actions {
        pointer.append(moveTo(source.id)); pointer.append(buttonDown(0))
        pointer.append(moveTo(target.id)); pointer.append(buttonUp(0))
        syncLengths(); return self
    }

    @discardableResult
    public func keyDown(_ value: String) -> Actions {
        key.append(keyEvent("keyDown", value)); syncLengths(); return self
    }

    @discardableResult
    public func keyUp(_ value: String) -> Actions {
        key.append(keyEvent("keyUp", value)); syncLengths(); return self
    }

    @discardableResult
    public func sendKeys(_ text: String) -> Actions {
        for ch in text {
            key.append(keyEvent("keyDown", String(ch)))
            key.append(keyEvent("keyUp", String(ch)))
        }
        syncLengths(); return self
    }

    @discardableResult
    public func pause(_ ms: Int) -> Actions {
        pointer.append(pauseAction(ms)); syncLengths(); return self
    }

    // The W3C `actions` array assembled from the two device lists. A device
    // sub-array is emitted only when it holds a real (non-pause) action.
    public func build() -> [Any] {
        var actions: [Any] = []
        if pointer.contains(where: { ($0["type"] as? String) != "pause" }) {
            actions.append([
                "type": "pointer", "id": "mouse",
                "parameters": ["pointerType": "mouse"],
                "actions": pointer,
            ] as [String: Any])
        }
        if key.contains(where: { ($0["type"] as? String) != "pause" }) {
            actions.append([
                "type": "key", "id": "keyboard",
                "actions": key,
            ] as [String: Any])
        }
        return actions
    }

    /// Post the queued gestures as one `actions` command. A no-op when nothing
    /// but pauses was queued.
    public func perform() throws {
        let actions = build()
        if actions.isEmpty { return }
        try driver.performActions(actions)
    }
}

// ---- Wait ----

/// A configured waiter over a driver: call `until` / `untilNot` with a predicate,
/// or use the convenience `waitFor*` methods. Poll cadence defaults to 0.5s.
/// On timeout, throws a WebDriverError with code 21.
public final class Wait {
    private let driver: WebDriver
    private let timeout: TimeInterval
    private var poll: TimeInterval = 0.5

    init(driver: WebDriver, timeout: TimeInterval) {
        self.driver = driver
        self.timeout = timeout
    }

    /// Override the poll cadence (default 0.5s). A non-positive interval is
    /// clamped up to the default.
    @discardableResult
    public func pollEvery(_ interval: TimeInterval) -> Wait {
        poll = interval > 0 ? interval : 0.5
        return self
    }

    // A NoSuchElement thrown by the condition is swallowed and retried (a
    // not-yet-present element should wait, not fail); any other error propagates.
    private func ignorable(_ e: Error) -> Bool {
        (e as? WebDriverError)?.code == WebDriverError.noSuchElement
    }

    private func timedOut() -> WebDriverError {
        WebDriverError(message: "waited \(timeout)s for condition", code: 21)
    }

    /// Poll `condition(driver)` until it returns `true`. The condition is checked
    /// once before the first sleep, so a zero timeout still gives one attempt.
    public func until(_ condition: (WebDriver) throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                if try condition(driver) { return }
            } catch where ignorable(error) {
                // retry
            }
            if Date() >= deadline { throw timedOut() }
            Thread.sleep(forTimeInterval: poll)
        }
    }

    /// Poll `condition(driver)` until it returns `false` (or an ignored
    /// NoSuchElement, which counts as "gone").
    public func untilNot(_ condition: (WebDriver) throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                if try !condition(driver) { return }
            } catch where ignorable(error) {
                return
            }
            if Date() >= deadline { throw timedOut() }
            Thread.sleep(forTimeInterval: poll)
        }
    }

    // find that maps a NoSuchElement miss to nil — the primitive the
    // element-returning waits poll on.
    private func tryFind(_ by: By) throws -> WebElement? {
        do { return try driver.findElement(by) }
        catch let e as WebDriverError where e.code == WebDriverError.noSuchElement { return nil }
    }

    private func pollElement(_ probe: (WebDriver) throws -> WebElement?) throws -> WebElement {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                if let el = try probe(driver) { return el }
            } catch where ignorable(error) {
                // retry
            }
            if Date() >= deadline { throw timedOut() }
            Thread.sleep(forTimeInterval: poll)
        }
    }

    /// Block until an element matching `by` is present; return it.
    public func forElement(_ by: By) throws -> WebElement {
        try pollElement { _ in try self.tryFind(by) }
    }

    /// Block until an element matching `by` is present AND displayed; return it.
    public func forVisible(_ by: By) throws -> WebElement {
        try pollElement { _ in
            guard let el = try self.tryFind(by) else { return nil }
            return try self.isDisplayed(el) ? el : nil
        }
    }

    /// Block until an element matching `by` is present, displayed AND enabled.
    public func forClickable(_ by: By) throws -> WebElement {
        try pollElement { _ in
            guard let el = try self.tryFind(by) else { return nil }
            return (try self.isDisplayed(el) && (try el.isEnabled())) ? el : nil
        }
    }

    /// Block until NO element matches `by` — it's absent/removed.
    public func untilGone(_ by: By) throws {
        try untilNot { _ in try self.tryFind(by) != nil }
    }

    /// Block until the page title equals `title`.
    public func forTitleIs(_ title: String) throws {
        try until { try $0.title() == title }
    }
    /// Block until the page title contains `substr`.
    public func forTitleContains(_ substr: String) throws {
        try until { try $0.title().contains(substr) }
    }
    /// Block until the current URL equals `url`.
    public func forURLIs(_ url: String) throws {
        try until { try $0.currentURL() == url }
    }
    /// Block until the current URL contains `substr`.
    public func forURLContains(_ substr: String) throws {
        try until { try $0.currentURL().contains(substr) }
    }

    // Visibility probe via the engine's dedicated isDisplayed atom (the shared
    // atom source, identical to element.isDisplayed()).
    private func isDisplayed(_ el: WebElement) throws -> Bool {
        try driver.atomIsDisplayed(el.id)
    }
}

// ---- driver-process orchestration ---------------------------------------------
//
// Spawn, reach, and reap the driver process (chromedriver/…) so the binding need
// not shell out itself. Lifecycle: ensureDriver → .url → WebDriver(commandExecutor:)
// → … → close → stop. `DriverProcess.deinit` reaps automatically.

/// A driver process (chromedriver/geckodriver/…) launched by the engine. Owns the
/// opaque driver handle; the process is killed + reaped on `stop()` / deinit.
public final class DriverProcess {
    let handle: UnsafeMutableRawPointer?

    init(handle: UnsafeMutableRawPointer?) { self.handle = handle }

    /// resolve + launch a driver for `browser` ("chrome"/"firefox"/…). Returns nil
    /// when no driver could be started (the binding's cue to SKIP a live test).
    public static func ensure(_ browser: String = "chrome",
                              hint: String = "",
                              timeoutMs: Int32 = 10_000) -> DriverProcess? {
        guard let h = aether_sel_embed_ensure_driver(browser, hint, timeoutMs) else { return nil }
        return DriverProcess(handle: h)
    }

    /// Launch an explicit driver binary on a free port. nil if it never came up.
    public static func launch(_ driverPath: String, timeoutMs: Int32 = 10_000) -> DriverProcess? {
        guard let h = aether_sel_embed_launch_driver(driverPath, timeoutMs) else { return nil }
        return DriverProcess(handle: h)
    }

    /// The "http://127.0.0.1:<port>" to pass to `WebDriver(commandExecutor:)`.
    public var url: String { take(aether_sel_embed_driver_url(handle)) }
    /// The driver's spawn token / pid (diagnostics). -1 if the handle is null.
    public var pid: Int32 { aether_sel_embed_driver_pid(handle) }

    /// Kill + reap the driver process. Idempotent; also runs on deinit.
    public func stop() { aether_sel_embed_stop_driver(handle) }
    deinit { aether_sel_embed_stop_driver(handle) }
}

/// Resolve the driver binary path for `browser` (v1: the conventional driver on
/// PATH). Empty when none is found.
public func resolveDriver(_ browser: String = "chrome", hint: String = "") -> String {
    take(aether_sel_embed_resolve_driver(browser, hint))
}

/// A self-provisioned browser binary path for `browser` (downloads Chrome-for-
/// Testing on first call if no system Chrome), or "" when a system browser exists.
public func browserBinary(_ browser: String = "chrome", hint: String = "") -> String {
    take(aether_sel_embed_browser_binary(browser, hint))
}

extension WebDriver {
    /// Engine-managed local Chrome: resolve+launch a chromedriver, open a session
    /// against it, and keep the driver process alive for the session's lifetime.
    /// Returns nil when no driver could be started (SKIP-a-live-test cue).
    @discardableResult
    public static func localChrome(options: [String: Any]? = nil,
                                   headless: Bool = false,
                                   timeoutMs: Int32 = 10_000) throws -> WebDriver? {
        guard let proc = DriverProcess.ensure("chrome", timeoutMs: timeoutMs) else { return nil }
        var opts: [String: Any] = options ?? [:]
        if headless {
            var chromeOpts = (opts["goog:chromeOptions"] as? [String: Any]) ?? [:]
            var args = (chromeOpts["args"] as? [String]) ?? []
            args.append(contentsOf: ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"])
            chromeOpts["args"] = args
            opts["goog:chromeOptions"] = chromeOpts
        }
        let d = try chrome(commandExecutor: proc.url, options: opts)
        d.driverProcess = proc // retain so the driver outlives the session
        return d
    }
}

// ---- WebDriver-BiDi (central demux, non-blocking poll) ------------------------
//
// The multiplexed BiDi transport over the session's webSocketUrl. The engine owns
// the ONE demux (single reader → id-keyed reply table + bounded event queue); the
// binding drives the wait (pump / fd) then drains replies+events. Open a channel
// from a session whose newSession requested webSocketUrl:true (WebDriver.chrome
// does), reading `driver.webSocketUrl`.

/// A WebDriver-BiDi channel. Strings returned are the raw reply/event JSON.
public final class BiDi {
    let handle: UnsafeMutableRawPointer
    private var nextId: Int32 = 0

    /// Open a channel to a session's webSocketUrl. Throws on connect failure.
    public init(wsUrl: String) throws {
        guard let h = aether_sel_embed_bidi_open(wsUrl) else {
            throw WebDriverError(message: "BiDi connect failed: \(wsUrl)", code: -1)
        }
        self.handle = h
    }
    deinit { aether_sel_embed_bidi_close(handle) }

    public func close() { aether_sel_embed_bidi_close(handle) }

    /// The readable socket fd, for a native event loop. Readiness is a HINT; on
    /// wake always drain via `pump(0)` until it returns 0.
    public var fd: Int32 { aether_sel_embed_bidi_fd(handle) }

    /// Advance the demux one step (read ≤1 frame, route it). 1 routed / 0 timed
    /// out / -1 closed.
    @discardableResult
    public func pump(timeoutMs: Int32 = 0) -> Int32 { aether_sel_embed_bidi_pump(handle, timeoutMs) }

    /// How many events the bounded queue dropped since the last check (then resets).
    public var lostEvents: Int32 { aether_sel_embed_bidi_lost_events(handle) }

    private func newId() -> Int32 { nextId += 1; return nextId }

    /// Send one command with a caller-managed id. Returns the id (poll its reply).
    @discardableResult
    public func send(_ method: String, _ params: [String: Any] = [:]) -> Int32 {
        let id = newId()
        _ = aether_sel_embed_bidi_send(handle, id, method, encodeJSON(params))
        return id
    }

    /// The reply JSON for a command id if it has arrived (consumes it), else "".
    public func pollReply(_ id: Int32) -> String { take(aether_sel_embed_bidi_poll_reply(handle, id)) }
    /// The next queued event JSON (dequeues), or "".
    public func pollEvent() -> String { take(aether_sel_embed_bidi_poll_event(handle)) }
    /// Drop a pending-reply slot so a late reply is discarded.
    public func cancel(_ id: Int32) { aether_sel_embed_bidi_cancel(handle, id) }

    /// Send `method` and pump until its reply arrives (or timeout). Returns the
    /// reply JSON, "" on timeout/close.
    public func command(_ method: String, _ params: [String: Any] = [:], timeoutMs: Int32 = 30_000) -> String {
        let id = send(method, params)
        var remaining = timeoutMs
        while remaining > 0 {
            let step: Int32 = min(remaining, 250)
            let r = aether_sel_embed_bidi_pump(handle, step)
            let reply = pollReply(id)
            if !reply.isEmpty { return reply }
            if r == -1 { break }
            remaining -= step
        }
        cancel(id)
        return ""
    }

    // ---- convenience verbs (thin wrappers, caller-managed ids) ----
    public func subscribe(_ eventsCsv: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_subscribe(handle, newId(), eventsCsv, timeoutMs))
    }
    public func unsubscribe(_ eventsCsv: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_unsubscribe(handle, newId(), eventsCsv, timeoutMs))
    }
    public func waitEvent(_ method: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_wait_event(handle, method, timeoutMs))
    }
    public func getTree(timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_get_tree(handle, newId(), timeoutMs))
    }
    public func scriptEvaluate(_ expression: String, contextId: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_script_evaluate(handle, newId(), expression, contextId, timeoutMs))
    }
    public func navigate(contextId: String, url: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_navigate(handle, newId(), contextId, url, timeoutMs))
    }

    // ---- network interception ----
    public func addIntercept(phasesCsv: String, urlPattern: String = "", timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_add_intercept(handle, newId(), phasesCsv, urlPattern, timeoutMs))
    }
    public func removeIntercept(_ interceptId: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_remove_intercept(handle, newId(), interceptId, timeoutMs))
    }
    public func continueRequest(_ requestId: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_continue_request(handle, newId(), requestId, timeoutMs))
    }
    public func failRequest(_ requestId: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_fail_request(handle, newId(), requestId, timeoutMs))
    }
    public func provideResponse(_ requestId: String, status: Int32, contentType: String = "", body: String = "", timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_provide_response(handle, newId(), requestId, status, contentType, body, timeoutMs))
    }
    public func continueWithAuth(_ requestId: String, username: String, password: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_continue_with_auth(handle, newId(), requestId, username, password, timeoutMs))
    }
    public func setCacheBehavior(_ behavior: String, timeoutMs: Int32 = 30_000) -> String {
        take(aether_sel_embed_bidi_network_set_cache_behavior(handle, newId(), behavior, timeoutMs))
    }
}

// The Swift binding now covers the full Rust-reference feature bar: the C header
// (selenium_core.h) declares every aether_sel_embed_* symbol the engine exports,
// so nothing is faked or deferred — atom-backed isDisplayed/getAttribute, relative
// locators, TLS trust config, driver orchestration, and the entire WebDriver-BiDi
// surface are all first-class.
