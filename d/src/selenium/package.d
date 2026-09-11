/**
 * selenium — the D binding over the shared pure-Aether WebDriver core.
 *
 * One engine (`libselenium_core`, written in Aether) exposes a flat C ABI of
 * `aether_sel_embed_*` symbols; every language binding is a thin, ergonomic
 * surface over that ABI. This is the D one.
 *
 * Why extern(C) + a real link (not a runtime dlopen): D compiles and links like
 * Nim/Go-cgo/Rust. The four `.aeb.ae` nodes stage the engine `.so` into
 * `d/native/` and pass `-L-L<dir> -L-lselenium_core -L-rpath ...` to dmd, so an
 * in-tree test binary finds the engine at build time and at run time.
 *
 * Every ABI call that returns a `char*` hands back a caller-owned string; it is
 * copied into a GC'd D `string` and freed via `aether_sel_embed_free_string` by
 * `takeString`. Do not hold the raw pointer.
 */
module selenium;

import std.json;
import std.string : toStringz, fromStringz, indexOf, startsWith;
import std.array : split;
import std.conv : to;
import std.datetime.stopwatch : StopWatch, AutoStart;
import core.thread : Thread;
import core.time : msecs, Duration, dur;

// ---- the flat C ABI (aether_sel_embed_*) -----------------------------------

private extern (C) nothrow @nogc {
    void* aether_sel_embed_open(const(char)* base_url);
    void  aether_sel_embed_close(void* h);
    int   aether_sel_embed_execute(void* h, const(char)* name, const(char)* params_json);
    char* aether_sel_embed_last_value(void* h);
    int   aether_sel_embed_last_status(void* h);
    int   aether_sel_embed_last_error_code(void* h);
    char* aether_sel_embed_last_error(void* h);
    char* aether_sel_embed_session_id(void* h);
    char* aether_sel_embed_by_locator(const(char)* strategy, const(char)* value);
    char* aether_sel_embed_route(const(char)* name);
    char* aether_sel_embed_build_request(const(char)* name, const(char)* session_id, const(char)* params_json);
    int   aether_sel_embed_error_code(const(char)* w3c_error);
    char* aether_sel_embed_free_string(char* s);

    // TLS trust config (before the first execute)
    void  aether_sel_embed_set_ca(void* h, const(char)* ca_path);
    void  aether_sel_embed_set_insecure(void* h, int on);

    // atom-backed element commands
    int   aether_sel_embed_execute_atom(void* h, const(char)* atom_name, const(char)* elem_id, const(char)* extra_json);
    int   aether_sel_embed_is_displayed(void* h, const(char)* elem_id);
    int   aether_sel_embed_get_attribute(void* h, const(char)* elem_id, const(char)* name);
    char* aether_sel_embed_atom_str_arg(const(char)* s);

    // relative locators
    int   aether_sel_embed_find_relative(void* h, const(char)* base_sel, const(char)* filters_json);

    // driver-process orchestration
    char* aether_sel_embed_resolve_driver(const(char)* browser, const(char)* hint);
    void* aether_sel_embed_launch_driver(const(char)* driver_path, int timeout_ms);
    char* aether_sel_embed_browser_binary(const(char)* browser, const(char)* hint);
    void* aether_sel_embed_ensure_driver(const(char)* browser, const(char)* hint, int timeout_ms);
    char* aether_sel_embed_driver_url(void* dh);
    int   aether_sel_embed_driver_pid(void* dh);
    void  aether_sel_embed_stop_driver(void* dh);

    // WebDriver-BiDi (central demux, non-blocking poll)
    void* aether_sel_embed_bidi_open(const(char)* ws_url);
    void  aether_sel_embed_bidi_close(void* h);
    int   aether_sel_embed_bidi_send(void* h, int id, const(char)* method, const(char)* params_json);
    int   aether_sel_embed_bidi_pump(void* h, int timeout_ms);
    int   aether_sel_embed_bidi_fd(void* h);
    char* aether_sel_embed_bidi_poll_reply(void* h, int id);
    char* aether_sel_embed_bidi_poll_event(void* h);
    int   aether_sel_embed_bidi_lost_events(void* h);
    void  aether_sel_embed_bidi_cancel(void* h, int id);
    char* aether_sel_embed_bidi_subscribe(void* h, int id, const(char)* events_csv, int timeout_ms);
    char* aether_sel_embed_bidi_unsubscribe(void* h, int id, const(char)* events_csv, int timeout_ms);
    char* aether_sel_embed_bidi_wait_event(void* h, const(char)* method, int timeout_ms);
    char* aether_sel_embed_bidi_get_tree(void* h, int id, int timeout_ms);
    char* aether_sel_embed_bidi_script_evaluate(void* h, int id, const(char)* expression, const(char)* context_id, int timeout_ms);
    char* aether_sel_embed_bidi_navigate(void* h, int id, const(char)* context_id, const(char)* url, int timeout_ms);

    // BiDi network interception
    char* aether_sel_embed_bidi_network_add_intercept(void* h, int id, const(char)* phases_csv, const(char)* url_pattern, int timeout_ms);
    char* aether_sel_embed_bidi_network_remove_intercept(void* h, int id, const(char)* intercept_id, int timeout_ms);
    char* aether_sel_embed_bidi_network_continue_request(void* h, int id, const(char)* request_id, int timeout_ms);
    char* aether_sel_embed_bidi_network_fail_request(void* h, int id, const(char)* request_id, int timeout_ms);
    char* aether_sel_embed_bidi_network_provide_response(void* h, int id, const(char)* request_id, int status, const(char)* content_type, const(char)* body, int timeout_ms);
    char* aether_sel_embed_bidi_network_continue_with_auth(void* h, int id, const(char)* request_id, const(char)* username, const(char)* password, int timeout_ms);
    char* aether_sel_embed_bidi_network_set_cache_behavior(void* h, int id, const(char)* behavior, int timeout_ms);
}

/// Copy an ABI-returned string into a GC'd D string and free the original.
/// Every string this module surfaces goes through here; the pointer is dead
/// after. A null pointer becomes "".
private string takeString(char* p) {
    if (p is null)
        return "";
    string s = fromStringz(p).idup;
    aether_sel_embed_free_string(p);
    return s;
}

// ---- errors ----------------------------------------------------------------

/// A coarse classification of a WebDriver failure, mirroring the other
/// bindings' error kinds (the stable integer `code` remains authoritative).
enum ErrorKind {
    transport,
    noSuchElement,
    staleElementReference,
    elementClickIntercepted,
    elementNotInteractable,
    invalidSelector,
    timeout,
    javascript,
    unknownCommand,
    noSuchShadowRoot,
    detachedShadowRoot,
    other,
}

/// The one exception type this binding throws. `code` is the engine's stable
/// W3C error code (0 = success, -1 = transport); `kind` is the coarse bucket.
class WebDriverException : Exception {
    int code;
    ErrorKind kind;
    this(int code, string message, string file = __FILE__, size_t line = __LINE__) {
        super(message, file, line);
        this.code = code;
        this.kind = classifyKind(code);
    }
}

private ErrorKind classifyKind(int code) {
    switch (code) {
        case -1: return ErrorKind.transport;
        case 3:  return ErrorKind.elementClickIntercepted;
        case 4:  return ErrorKind.elementNotInteractable;
        case 11: return ErrorKind.invalidSelector;
        case 13: return ErrorKind.javascript;
        case 17: return ErrorKind.noSuchElement;
        case 19: return ErrorKind.noSuchShadowRoot;
        case 2:  return ErrorKind.detachedShadowRoot;
        case 21: case 24: return ErrorKind.timeout;
        case 23: return ErrorKind.staleElementReference;
        case 28: return ErrorKind.unknownCommand;
        default: return ErrorKind.other;
    }
}

// ---- By --------------------------------------------------------------------

/// A locator: a Selenium-style mechanism/value pair, built through the
/// `By.id`/`By.cssSelector`/... factories and passed to `findElement`/
/// `findElements`. Mirrors Java's `By`. The engine rewrites id/name/"class
/// name" to CSS.
struct By {
    string strategy;
    string value;

    static By id(string value)              { return By("id", value); }
    static By name(string value)            { return By("name", value); }
    static By className(string value)       { return By("class name", value); }
    static By cssSelector(string value)     { return By("css selector", value); }
    static By tagName(string value)         { return By("tag name", value); }
    static By linkText(string value)        { return By("link text", value); }
    static By partialLinkText(string value) { return By("partial link text", value); }
    static By xpath(string value)           { return By("xpath", value); }
}

/// The W3C element-reference key present in every returned element JSON.
enum w3cElementKey = "element-6066-11e4-a52e-4f735466cecf";

/// The W3C shadow-root reference key, distinct from the element key.
enum w3cShadowKey = "shadow-6066-11e4-a52e-4f735466cecf";

// ---- pure engine helpers ---------------------------------------------------

/// The "METHOD PATH" route for a command name, or "" if unknown.
string route(string command) {
    return takeString(aether_sel_embed_route(command.toStringz));
}

/// Map a W3C error string to its stable integer code (0 = success).
int errorCode(string w3cError) {
    return aether_sel_embed_error_code(w3cError.toStringz);
}

/// The W3C {"using","value"} locator JSON for a (by, value) pair.
string locator(string by, string value) {
    return takeString(aether_sel_embed_by_locator(by.toStringz, value.toStringz));
}

private JSONValue decodeBy(By by) {
    return parseJSON(locator(by.strategy, by.value));
}

// ---- WebDriver / WebElement ------------------------------------------------

/// A live WebDriver session. Close it with `quit()` (also called by the
/// destructor). Create one with `chrome(...)` / `headlessChrome(...)`.
final class WebDriver {
    private void* handle;
    package string wsUrl;
    private BiDi _bidi;

    private this(void* handle) {
        this.handle = handle;
    }

    ~this() {
        quit();
    }

    /// Close the session and release the engine handle. Idempotent.
    void quit() {
        if (handle !is null) {
            aether_sel_embed_close(handle);
            handle = null;
        }
    }

    /// Run a raw W3C command by name with JSON params; returns the decoded
    /// `value` (JSONValue null when empty). Throws on any non-zero rc.
    JSONValue execute(string command, JSONValue params) {
        string paramsJson = params.toString();
        int rc = aether_sel_embed_execute(handle, command.toStringz, paramsJson.toStringz);
        return drain(rc);
    }

    private JSONValue drain(int rc) {
        if (rc != 0) {
            int code = aether_sel_embed_last_error_code(handle);
            string message = takeString(aether_sel_embed_last_error(handle));
            if (rc == -1 && code == 0)
                throw new WebDriverException(-1, message.length == 0 ? "transport failure" : message);
            throw new WebDriverException(code, message);
        }
        string raw = takeString(aether_sel_embed_last_value(handle));
        if (raw.length == 0)
            return JSONValue(null);
        return parseJSON(raw);
    }

    /// The current W3C session id.
    string sessionId() {
        return takeString(aether_sel_embed_session_id(handle));
    }

    // --- navigation ---
    void get(string url)      { execute("get", JSONValue(["url": JSONValue(url)])); }
    string title()            { return execute("getTitle", emptyObj).str; }
    string currentUrl()       { return execute("getCurrentUrl", emptyObj).str; }
    string pageSource()       { return execute("getPageSource", emptyObj).str; }
    void back()               { execute("goBack", emptyObj); }
    void forward()            { execute("goForward", emptyObj); }
    void refresh()            { execute("refresh", emptyObj); }

    // --- find ---
    WebElement findElement(By by) {
        auto v = execute("findElement", decodeBy(by));
        return new WebElement(this, v[w3cElementKey].str);
    }

    WebElement[] findElements(By by) {
        auto v = execute("findElements", decodeBy(by));
        WebElement[] outv;
        foreach (item; v.array)
            outv ~= new WebElement(this, item[w3cElementKey].str);
        return outv;
    }

    /// Does at least one element match? A NoSuchElement is swallowed to `false`.
    bool exists(By by) {
        try {
            return findElements(by).length > 0;
        } catch (WebDriverException e) {
            if (e.kind == ErrorKind.noSuchElement)
                return false;
            throw e;
        }
    }

    /// The element that currently has focus.
    WebElement activeElement() {
        auto v = execute("getActiveElement", emptyObj);
        return new WebElement(this, v[w3cElementKey].str);
    }

    /// Relative-locator find (findElementsRelative atom): elements matching
    /// `baseCss` filtered by `filtersJson` (above/below/near/left/right).
    WebElement[] findRelative(string baseCss, JSONValue filters) {
        int rc = aether_sel_embed_find_relative(handle, baseCss.toStringz, filters.toString().toStringz);
        auto v = drain(rc);
        WebElement[] outv;
        if (v.type == JSONType.array)
            foreach (item; v.array)
                outv ~= new WebElement(this, item[w3cElementKey].str);
        return outv;
    }

    /// Count of relative matches (cheaper than materializing elements).
    size_t findRelativeCount(string baseCss, JSONValue filters = JSONValue((JSONValue[string]).init)) {
        return findRelative(baseCss, filters).length;
    }

    // --- scripts ---
    JSONValue executeScript(string script, JSONValue args = JSONValue(cast(JSONValue[]) [])) {
        return execute("executeScript", JSONValue(["script": JSONValue(script), "args": args]));
    }

    JSONValue executeAsyncScript(string script, JSONValue args = JSONValue(cast(JSONValue[]) [])) {
        return execute("executeAsyncScript", JSONValue(["script": JSONValue(script), "args": args]));
    }

    // --- windows ---
    string[] windowHandles() {
        auto v = execute("getWindowHandles", emptyObj);
        string[] outv;
        foreach (h; v.array) outv ~= h.str;
        return outv;
    }

    string currentWindowHandle() { return execute("getCurrentWindowHandle", emptyObj).str; }
    void switchToWindow(string handle) { execute("switchToWindow", JSONValue(["handle": JSONValue(handle)])); }

    string newWindow(string typeHint = "tab") {
        auto v = execute("newWindow", JSONValue(["type": JSONValue(typeHint)]));
        return v["handle"].str;
    }

    string[] closeWindow() {
        auto v = execute("close", emptyObj);
        string[] outv;
        foreach (h; v.array) outv ~= h.str;
        return outv;
    }

    JSONValue setWindowRect(JSONValue rect) { return execute("setWindowRect", rect); }
    JSONValue getWindowRect()               { return execute("getWindowRect", emptyObj); }
    JSONValue maximizeWindow()              { return execute("maximizeWindow", emptyObj); }
    JSONValue minimizeWindow()              { return execute("minimizeWindow", emptyObj); }
    JSONValue fullscreenWindow()            { return execute("fullscreenWindow", emptyObj); }

    // --- frames ---
    void switchToFrame(Frame frame) {
        JSONValue id;
        final switch (frame.kind) {
            case FrameKind.index:   id = JSONValue(frame.index); break;
            case FrameKind.element: id = JSONValue([w3cElementKey: JSONValue(frame.elementId)]); break;
            case FrameKind.deflt:   id = JSONValue(null); break;
        }
        execute("switchToFrame", JSONValue(["id": id]));
    }
    void switchToParentFrame()   { execute("switchToFrameParent", emptyObj); }
    void switchToDefaultContent() { execute("switchToFrame", JSONValue(["id": JSONValue(null)])); }

    // --- alerts ---
    void acceptAlert()  { execute("acceptAlert", emptyObj); }
    void dismissAlert() { execute("dismissAlert", emptyObj); }
    string alertText()  { return execute("getAlertText", emptyObj).str; }
    void sendAlertText(string text) { execute("setAlertValue", JSONValue(["text": JSONValue(text)])); }
    bool alertPresent() {
        try {
            execute("getAlertText", emptyObj);
            return true;
        } catch (WebDriverException) {
            return false;
        }
    }

    // --- cookies ---
    void addCookie(JSONValue cookie) { execute("addCookie", JSONValue(["cookie": cookie])); }
    JSONValue cookies()              { return execute("getCookies", emptyObj); }
    JSONValue cookie(string name)    { return execute("getCookie", JSONValue(["name": JSONValue(name)])); }
    void deleteCookie(string name)   { execute("deleteCookie", JSONValue(["name": JSONValue(name)])); }
    void deleteAllCookies()          { execute("deleteAllCookies", emptyObj); }

    // --- timeouts ---
    void setTimeouts(JSONValue timeouts) { execute("setTimeout", timeouts); }
    JSONValue getTimeouts()              { return execute("getTimeout", emptyObj); }

    // --- screenshots / print ---
    string screenshotBase64() { return execute("screenshot", emptyObj).str; }

    /// Print the current page to PDF; returns base64-encoded PDF bytes.
    string printPdf(JSONValue options = JSONValue((JSONValue[string]).init)) {
        return execute("printPage", options).str;
    }

    // --- actions ---
    void performActions(JSONValue actions) {
        execute("actions", JSONValue(["actions": actions]));
    }
    void releaseActions() { execute("clearActions", emptyObj); }

    /// A fresh Actions builder bound to this driver.
    Actions actions() { return new Actions(this); }

    // --- logs (Selenium `se/log` vendor extension) ---
    /// The available log types, e.g. `["browser", "driver"]`.
    string[] logTypes() {
        auto v = execute("getAvailableLogTypes", emptyObj);
        string[] outv;
        if (v.type == JSONType.array)
            foreach (t; v.array) outv ~= t.str;
        return outv;
    }
    /// The log entries for `type` (each `{level, message, timestamp}`).
    JSONValue log(string type) {
        return execute("getLog", JSONValue(["type": JSONValue(type)]));
    }

    // --- file transfer (Selenium `se/file` + `se/files` vendor extensions) ---
    /// Upload a local file (base64 zip per the `se/file` protocol); returns the
    /// remote path the driver stored it at.
    string uploadFile(string base64Zip) {
        return execute("uploadFile", JSONValue(["file": JSONValue(base64Zip)])).str;
    }
    /// The names of files available for download from the remote end.
    JSONValue downloadableFiles() { return execute("getDownloadableFiles", emptyObj); }
    /// Fetch a downloadable file by `name` (base64 contents in the result).
    JSONValue downloadFile(string name) {
        return execute("downloadFile", JSONValue(["name": JSONValue(name)]));
    }
    /// Clear the remote end's downloadable-files set.
    void deleteDownloadableFiles() { execute("deleteDownloadableFiles", emptyObj); }

    // --- virtual authenticator (WebAuthn) ---
    /// Add a virtual authenticator with the given config; returns its id.
    string addVirtualAuthenticator(JSONValue config) {
        return execute("addVirtualAuthenticator", config).str;
    }
    void removeVirtualAuthenticator(string authenticatorId) {
        execute("removeVirtualAuthenticator", JSONValue(["authenticatorId": JSONValue(authenticatorId)]));
    }
    void addCredential(string authenticatorId, JSONValue credential) {
        auto p = credential;
        p["authenticatorId"] = JSONValue(authenticatorId);
        execute("addCredential", p);
    }
    JSONValue credentials(string authenticatorId) {
        return execute("getCredentials", JSONValue(["authenticatorId": JSONValue(authenticatorId)]));
    }
    void removeCredential(string authenticatorId, string credentialId) {
        execute("removeCredential", JSONValue([
            "authenticatorId": JSONValue(authenticatorId), "credentialId": JSONValue(credentialId)]));
    }
    void removeAllCredentials(string authenticatorId) {
        execute("removeAllCredentials", JSONValue(["authenticatorId": JSONValue(authenticatorId)]));
    }
    void setUserVerified(string authenticatorId, bool verified) {
        execute("setUserVerified", JSONValue([
            "authenticatorId": JSONValue(authenticatorId), "isUserVerified": JSONValue(verified)]));
    }

    // --- FedCM (federated credential management dialog control) ---
    JSONValue fedcmAccounts()    { return execute("getAccounts", emptyObj); }
    string fedcmTitle()          { return execute("getFedCmTitle", emptyObj).str; }
    string fedcmDialogType()     { return execute("getFedCmDialogType", emptyObj).str; }
    void fedcmSelectAccount(int index) {
        execute("selectAccount", JSONValue(["accountIndex": JSONValue(index)]));
    }
    void fedcmClickDialogButton(string dialogButton) {
        execute("clickdialogbutton", JSONValue(["dialogButton": JSONValue(dialogButton)]));
    }
    void fedcmCancelDialog()     { execute("cancelDialog", emptyObj); }
    void fedcmSetDelayEnabled(bool enabled) {
        execute("setDelayEnabled", JSONValue(["enabled": JSONValue(enabled)]));
    }
    void fedcmResetCooldown()    { execute("resetCooldown", emptyObj); }

    // --- BiDi ---
    /// The lazily-opened BiDi channel for this session (needs a session created
    /// with a webSocketUrl capability, which `chrome()` requests).
    BiDi bidi() {
        if (_bidi is null) {
            if (wsUrl.length == 0)
                throw new WebDriverException(-1, "no BiDi webSocketUrl negotiated for this session");
            _bidi = new BiDi(wsUrl);
        }
        return _bidi;
    }
}

/// A W3C element reference plus a back-pointer to its driver.
final class WebElement {
    private WebDriver driver;
    string id; /// the W3C element reference; also the Actions/Select origin key

    package this(WebDriver driver, string id) {
        this.driver = driver;
        this.id = id;
    }

    /// Reconstruct an element handle from a known W3C reference `id` (and an
    /// optional driver). Mirrors Selenium's ability to hold a bare element
    /// reference; also the way to feed an id into an `Actions` chain in tests.
    static WebElement fromId(string id, WebDriver driver = null) {
        return new WebElement(driver, id);
    }

    private JSONValue elExec(string command, JSONValue params) {
        auto p = params;
        p["id"] = JSONValue(id);
        return driver.execute(command, p);
    }

    void click()  { elExec("clickElement", emptyObj); }
    void clear()  { elExec("clearElement", emptyObj); }

    /// Submit the enclosing form. W3C removed the dedicated `submit` endpoint,
    /// so — like modern Selenium and the reference binding — walk to the
    /// enclosing <form> and requestSubmit()/submit() via an injected script.
    void submit() {
        enum script = "var e=arguments[0];var f=e.form||e.closest('form');"
            ~ "if(!f){throw new Error('Element is not within a form');}"
            ~ "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}";
        driver.executeScript(script, JSONValue([JSONValue([w3cElementKey: JSONValue(id)])]));
    }

    void sendKeys(string text) {
        JSONValue[] value;
        foreach (dchar c; text) value ~= JSONValue(to!string(c));
        elExec("sendKeysToElement", JSONValue(["text": JSONValue(text), "value": JSONValue(value)]));
    }

    string text()    { return elExec("getElementText", emptyObj).str; }
    string tagName() { return elExec("getElementTagName", emptyObj).str; }

    /// The computed ARIA role of this element (W3C `getComputedRole`).
    string ariaRole() { return elExec("getAriaRole", emptyObj).str; }
    /// The computed accessible name of this element (W3C `getComputedLabel`).
    string accessibleName() { return elExec("getAccessibleName", emptyObj).str; }
    JSONValue rect() { return elExec("getElementRect", emptyObj); }
    JSONValue getProperty(string name) {
        return elExec("getElementProperty", JSONValue(["name": JSONValue(name)]));
    }

    bool isDisplayed() {
        int rc = aether_sel_embed_is_displayed(driver.handle, id.toStringz);
        return driver.drain(rc).boolean;
    }
    bool isEnabled()  { return elExec("isElementEnabled", emptyObj).boolean; }
    bool isSelected() { return elExec("isElementSelected", emptyObj).boolean; }

    /// The element attribute (atom-backed, matches Selenium's getAttribute).
    JSONValue getAttribute(string name) {
        int rc = aether_sel_embed_get_attribute(driver.handle, id.toStringz, name.toStringz);
        return driver.drain(rc);
    }
    /// The raw DOM attribute (W3C getDomAttribute), no property fallback.
    string getDomAttribute(string name) {
        auto v = elExec("getDomAttribute", JSONValue(["name": JSONValue(name)]));
        return v.type == JSONType.string ? v.str : "";
    }
    string cssValue(string prop) {
        return elExec("getElementValueOfCssProperty", JSONValue(["propertyName": JSONValue(prop)])).str;
    }
    /// Alias matching Selenium's Java name.
    string valueOfCssProperty(string prop) { return cssValue(prop); }

    string screenshotBase64() { return elExec("takeElementScreenshot", emptyObj).str; }

    WebElement findElement(By by) {
        auto v = elExec("findChildElement", decodeBy(by));
        return new WebElement(driver, v[w3cElementKey].str);
    }
    WebElement[] findElements(By by) {
        auto v = elExec("findChildElements", decodeBy(by));
        WebElement[] outv;
        foreach (item; v.array)
            outv ~= new WebElement(driver, item[w3cElementKey].str);
        return outv;
    }

    /// This element's shadow root as a search context (mirrors Selenium's
    /// `getShadowRoot`). Throws a `noSuchShadowRoot` (code 19) if the element
    /// hosts no open shadow root.
    ShadowRoot shadowRoot() {
        auto v = elExec("getShadowRoot", emptyObj);
        if (v.type == JSONType.object && w3cShadowKey in v)
            return ShadowRoot(driver, v[w3cShadowKey].str);
        throw new WebDriverException(19, "no such shadow root");
    }
}

/// A shadow root as a search context (mirrors Selenium's `ShadowRoot`). Only
/// `findElement`/`findElements` are supported, scoped inside the shadow tree.
struct ShadowRoot {
    private WebDriver driver;
    string id; /// the W3C shadow-root reference

    private JSONValue srExec(string command, JSONValue params) {
        auto p = params;
        p["id"] = JSONValue(id);
        return driver.execute(command, p);
    }

    /// The first descendant of this shadow root matching `by`.
    WebElement findElement(By by) {
        auto v = srExec("findElementFromShadowRoot", decodeBy(by));
        return new WebElement(driver, v[w3cElementKey].str);
    }

    /// All descendants of this shadow root matching `by`.
    WebElement[] findElements(By by) {
        auto v = srExec("findElementsFromShadowRoot", decodeBy(by));
        WebElement[] outv;
        foreach (item; v.array)
            outv ~= new WebElement(driver, item[w3cElementKey].str);
        return outv;
    }
}

private JSONValue emptyObj() {
    return JSONValue((JSONValue[string]).init);
}

// ---- session factories -----------------------------------------------------

/// Open a W3C session with the given `browserName` and capabilities against a
/// running driver (or Grid) at `commandExecutor`. `caPath` pins a private-CA
/// bundle; `insecure` skips TLS verification — both must land before the first
/// request (newSession), which is why they're applied here. A BiDi channel is
/// requested (`webSocketUrl`) so `.bidi` is available on demand. The per-browser
/// `chrome()`/`firefox()`/`edge()`/`safari()` factories are thin wrappers.
WebDriver openSession(string commandExecutor, string browserName,
                      JSONValue options = JSONValue((JSONValue[string]).init),
                      string caPath = "", bool insecure = false) {
    JSONValue caps = options.type == JSONType.object ? options : emptyObj;
    caps["browserName"] = JSONValue(browserName);
    caps["webSocketUrl"] = JSONValue(true);

    void* handle = aether_sel_embed_open(commandExecutor.toStringz);
    if (handle is null)
        throw new WebDriverException(-1, "failed to open session handle");
    if (caPath.length != 0)
        aether_sel_embed_set_ca(handle, caPath.toStringz);
    if (insecure)
        aether_sel_embed_set_insecure(handle, 1);

    auto d = new WebDriver(handle);
    auto session = d.execute("newSession",
        JSONValue(["capabilities": JSONValue(["alwaysMatch": caps])]));
    if (session.type == JSONType.object && "capabilities" in session) {
        auto negotiated = session["capabilities"];
        if (negotiated.type == JSONType.object && "webSocketUrl" in negotiated)
            d.wsUrl = negotiated["webSocketUrl"].str;
    }
    return d;
}

// --- Chrome ---
/// Start a Chrome session against a running chromedriver (or Grid).
WebDriver chrome(string commandExecutor, JSONValue options = JSONValue((JSONValue[string]).init),
                 string caPath = "", bool insecure = false) {
    return openSession(commandExecutor, "chrome", options, caPath, insecure);
}

/// Convenience: a headless Chrome session with the standard launch args.
WebDriver headlessChrome(string commandExecutor, string caPath = "", bool insecure = false) {
    JSONValue args = JSONValue([
        JSONValue("--headless=new"), JSONValue("--no-sandbox"),
        JSONValue("--disable-gpu"), JSONValue("--disable-dev-shm-usage")]);
    JSONValue opts = JSONValue(["goog:chromeOptions": JSONValue(["args": args])]);
    return chrome(commandExecutor, opts, caPath, insecure);
}

// --- Firefox ---
/// Start a Firefox session against a running geckodriver (or Grid).
WebDriver firefox(string commandExecutor, JSONValue options = JSONValue((JSONValue[string]).init),
                  string caPath = "", bool insecure = false) {
    return openSession(commandExecutor, "firefox", options, caPath, insecure);
}

/// Convenience: a headless Firefox session (`moz:firefoxOptions` `-headless`).
WebDriver headlessFirefox(string commandExecutor, string caPath = "", bool insecure = false) {
    JSONValue opts = JSONValue([
        "moz:firefoxOptions": JSONValue(["args": JSONValue([JSONValue("-headless")])])]);
    return firefox(commandExecutor, opts, caPath, insecure);
}

// --- Edge ---
/// Start a Microsoft Edge session against a running msedgedriver (or Grid).
/// (W3C browserName is "MicrosoftEdge".)
WebDriver edge(string commandExecutor, JSONValue options = JSONValue((JSONValue[string]).init),
               string caPath = "", bool insecure = false) {
    return openSession(commandExecutor, "MicrosoftEdge", options, caPath, insecure);
}

/// Convenience: a headless Edge session (Chromium-based, `ms:edgeOptions` args).
WebDriver headlessEdge(string commandExecutor, string caPath = "", bool insecure = false) {
    JSONValue args = JSONValue([
        JSONValue("--headless=new"), JSONValue("--no-sandbox"),
        JSONValue("--disable-gpu"), JSONValue("--disable-dev-shm-usage")]);
    JSONValue opts = JSONValue(["ms:edgeOptions": JSONValue(["args": args])]);
    return edge(commandExecutor, opts, caPath, insecure);
}

// --- Safari ---
/// Start a Safari session against a running safaridriver (macOS only). Safari
/// has no headless mode, so there is no `headlessSafari`.
WebDriver safari(string commandExecutor, JSONValue options = JSONValue((JSONValue[string]).init),
                 string caPath = "", bool insecure = false) {
    return openSession(commandExecutor, "safari", options, caPath, insecure);
}

// ---- frames ----------------------------------------------------------------

enum FrameKind { index, element, deflt }

/// A frame target for `switchToFrame`. Build with `frameIndex`, `frame`, or
/// `defaultFrame`.
struct Frame {
    FrameKind kind;
    int index;
    string elementId;
}

Frame frameIndex(int index)      { Frame f; f.kind = FrameKind.index; f.index = index; return f; }
Frame frame(WebElement element)  { Frame f; f.kind = FrameKind.element; f.elementId = element.id; return f; }
Frame defaultFrame()             { Frame f; f.kind = FrameKind.deflt; return f; }

// ---- driver-process orchestration ------------------------------------------

/// The resolved driver-binary path for a browser (downloading if needed), or ""
/// on failure. `hint` is an optional version/channel hint.
string resolveDriver(string browser, string hint = "") {
    return takeString(aether_sel_embed_resolve_driver(browser.toStringz, hint.toStringz));
}

/// The resolved browser-binary path, or "".
string browserBinary(string browser, string hint = "") {
    return takeString(aether_sel_embed_browser_binary(browser.toStringz, hint.toStringz));
}

/// A running driver process (resolve + launch + health-wait). `url()` is its
/// base URL for `chrome(...)`; `stop()` terminates it.
final class DriverProcess {
    private void* dh;
    private this(void* dh) { this.dh = dh; }
    ~this() { stop(); }

    string url() { return takeString(aether_sel_embed_driver_url(dh)); }
    int pid()    { return aether_sel_embed_driver_pid(dh); }
    void stop() {
        if (dh !is null) {
            aether_sel_embed_stop_driver(dh);
            dh = null;
        }
    }
}

/// Ensure a driver for `browser` is running (resolve+launch+wait); returns a
/// managed `DriverProcess`, or null on failure.
DriverProcess ensureDriver(string browser, string hint = "", int timeoutMs = 20_000) {
    void* dh = aether_sel_embed_ensure_driver(browser.toStringz, hint.toStringz, timeoutMs);
    return dh is null ? null : new DriverProcess(dh);
}

/// Launch a specific driver binary; returns a managed `DriverProcess`, or null.
DriverProcess launchDriver(string driverPath, int timeoutMs = 20_000) {
    void* dh = aether_sel_embed_launch_driver(driverPath.toStringz, timeoutMs);
    return dh is null ? null : new DriverProcess(dh);
}

// ---- explicit waits --------------------------------------------------------

alias DriverPredicate = bool delegate(WebDriver);

/// Poll `predicate` until it returns true or `timeoutMs` elapses (raising a
/// timeout `WebDriverException`). Returns true on success.
bool waitUntil(WebDriver d, int timeoutMs, DriverPredicate predicate, int pollMs = 250) {
    auto sw = StopWatch(AutoStart.yes);
    for (;;) {
        if (predicate(d))
            return true;
        if (sw.peek.total!"msecs" >= timeoutMs)
            throw new WebDriverException(21, "timed out after " ~ to!string(timeoutMs) ~ "ms");
        Thread.sleep(pollMs.msecs);
    }
}

/// Poll until `predicate` goes false (or timeout).
bool waitUntilNot(WebDriver d, int timeoutMs, DriverPredicate predicate, int pollMs = 250) {
    return waitUntil(d, timeoutMs, (WebDriver dd) => !predicate(dd), pollMs);
}

/// Wait until an element matching `by` is present; returns it.
WebElement waitForElement(WebDriver d, By by, int timeoutMs) {
    WebElement found;
    waitUntil(d, timeoutMs, (WebDriver dd) {
        auto els = dd.findElements(by);
        if (els.length > 0) { found = els[0]; return true; }
        return false;
    });
    return found;
}

/// Wait until an element matching `by` is present AND displayed; returns it.
WebElement waitForVisible(WebDriver d, By by, int timeoutMs) {
    WebElement found;
    waitUntil(d, timeoutMs, (WebDriver dd) {
        auto els = dd.findElements(by);
        if (els.length > 0 && els[0].isDisplayed()) { found = els[0]; return true; }
        return false;
    });
    return found;
}

/// Wait until an element matching `by` is present, displayed AND enabled.
WebElement waitForClickable(WebDriver d, By by, int timeoutMs) {
    WebElement found;
    waitUntil(d, timeoutMs, (WebDriver dd) {
        auto els = dd.findElements(by);
        if (els.length > 0 && els[0].isDisplayed() && els[0].isEnabled()) { found = els[0]; return true; }
        return false;
    });
    return found;
}

/// Wait until nothing matches `by`. Returns true once gone.
bool waitUntilGone(WebDriver d, By by, int timeoutMs) {
    return waitUntilNot(d, timeoutMs, (WebDriver dd) => dd.findElements(by).length > 0);
}

bool waitForTitleIs(WebDriver d, string want, int timeoutMs) {
    return waitUntil(d, timeoutMs, (WebDriver dd) => dd.title() == want);
}
bool waitForTitleContains(WebDriver d, string substr, int timeoutMs) {
    return waitUntil(d, timeoutMs, (WebDriver dd) => dd.title().indexOf(substr) >= 0);
}
bool waitForUrlIs(WebDriver d, string want, int timeoutMs) {
    return waitUntil(d, timeoutMs, (WebDriver dd) => dd.currentUrl() == want);
}
bool waitForUrlContains(WebDriver d, string substr, int timeoutMs) {
    return waitUntil(d, timeoutMs, (WebDriver dd) => dd.currentUrl().indexOf(substr) >= 0);
}

// ---- Select ----------------------------------------------------------------

/// The by-what a `Select.select`/`firstMatchIndex` matches on.
enum SelectBy { value, text, index }

/// A parsed <option>: its `value` attribute and visible `text`.
struct OptionData {
    string value;
    string text;
}

/// Pure option-matching used by `Select` and unit-testable without a browser.
/// Returns the first index matching `needle` under `by`, or -1.
int firstMatchIndex(const OptionData[] opts, SelectBy by, string needle) {
    final switch (by) {
        case SelectBy.value:
            foreach (i, o; opts) if (o.value == needle) return cast(int) i;
            return -1;
        case SelectBy.text:
            foreach (i, o; opts) if (o.text == needle) return cast(int) i;
            return -1;
        case SelectBy.index:
            int want;
            try { want = to!int(needle); } catch (Exception) { return -1; }
            return (want >= 0 && want < cast(int) opts.length) ? want : -1;
    }
}

/// A wrapper around a <select> element mirroring Selenium's Select support.
struct Select {
    WebElement element;

    private OptionData[] readOptions() {
        OptionData[] outv;
        foreach (opt; element.findElements(By.tagName("option"))) {
            auto v = opt.getAttribute("value");
            string val = v.type == JSONType.string ? v.str : "";
            outv ~= OptionData(val, opt.text());
        }
        return outv;
    }

    private bool isMultiple() {
        auto v = element.getAttribute("multiple");
        return v.type == JSONType.string && v.str.length > 0
            || v.type == JSONType.true_;
    }

    void selectByValue(string value) {
        auto opts = element.findElements(By.cssSelector("option[value=" ~ jsonQuote(value) ~ "]"));
        if (opts.length == 0)
            throw new WebDriverException(0, "no option with value " ~ value);
        opts[0].click();
    }

    void selectByVisibleText(string text) {
        auto opts = element.findElements(
            By.xpath(".//option[normalize-space(.)=" ~ xpathLiteral(text) ~ "]"));
        if (opts.length == 0)
            throw new WebDriverException(0, "no option with text " ~ text);
        opts[0].click();
    }

    void selectByIndex(int index) {
        auto opts = element.findElements(By.tagName("option"));
        if (index < 0 || index >= cast(int) opts.length)
            throw new WebDriverException(0, "index out of range");
        opts[index].click();
    }

    void deselectAll() {
        if (!isMultiple())
            throw new WebDriverException(0, "deselectAll only makes sense on a multi-select");
        foreach (opt; element.findElements(By.tagName("option")))
            if (opt.isSelected())
                opt.click();
    }
}

private string jsonQuote(string s) {
    return JSONValue(s).toString();
}

/// Quote a string as an XPath literal (handling embedded quotes via concat()).
private string xpathLiteral(string s) {
    if (s.indexOf('\'') < 0)
        return "'" ~ s ~ "'";
    if (s.indexOf('"') < 0)
        return "\"" ~ s ~ "\"";
    // both quote kinds present: build a concat()
    string outp = "concat(";
    bool first = true;
    foreach (part; s.split('\'')) {
        if (!first) outp ~= ", \"'\", ";
        outp ~= "'" ~ part ~ "'";
        first = false;
    }
    return outp ~ ")";
}

// ---- Keys ------------------------------------------------------------------

/// The W3C key constants (PUA code points). Mirrors Selenium's Keys.
struct KeysTable {
    string nul          = "";
    string cancel       = "";
    string help         = "";
    string backspace    = "";
    string tab          = "";
    string clear        = "";
    string returnKey    = "";
    string enter        = "";
    string shift        = "";
    string control      = "";
    string alt          = "";
    string pause        = "";
    string escape       = "";
    string space        = "";
    string pageUp       = "";
    string pageDown     = "";
    string end          = "";
    string home         = "";
    string left         = "";
    string up           = "";
    string right        = "";
    string down         = "";
    string insert       = "";
    string delete_      = "";
    string semicolon    = "";
    string equals       = "";
    string numpad0      = "";
    string numpad1      = "";
    string numpad2      = "";
    string numpad3      = "";
    string numpad4      = "";
    string numpad5      = "";
    string numpad6      = "";
    string numpad7      = "";
    string numpad8      = "";
    string numpad9      = "";
    string multiply     = "";
    string add          = "";
    string separator    = "";
    string subtract     = "";
    string decimal      = "";
    string divide       = "";
    string f1           = "";
    string f2           = "";
    string f3           = "";
    string f4           = "";
    string f5           = "";
    string f6           = "";
    string f7           = "";
    string f8           = "";
    string f9           = "";
    string f10          = "";
    string f11          = "";
    string f12          = "";
    string meta         = "";
    // aliases
    string arrowLeft()  const { return left; }
    string arrowUp()    const { return up; }
    string arrowRight() const { return right; }
    string arrowDown()  const { return down; }
    string command()    const { return meta; }
}

/// The single Keys table value.
enum Keys = KeysTable.init;

/// Convenience alias matching Selenium (BACK_SPACE).
enum BackSpace = KeysTable.init.backspace;

/// Build a chord: hold `modifier`, type `keys`, then a trailing NULL to release
/// all held keys — e.g. `chord(Keys.control, "a")`.
string chord(string modifier, string keys) {
    return modifier ~ keys ~ Keys.nul;
}

// ---- Actions ---------------------------------------------------------------

/// A W3C Actions builder (pointer + keyboard). Chain gestures then `perform()`.
/// `build()` returns the raw W3C `actions` array (unit-testable).
final class Actions {
    private WebDriver driver;
    private JSONValue[] pointerSeq;
    private JSONValue[] keySeq;

    /// Build an Actions chain. Pass the driver that will `perform()` it; a null
    /// driver still `build()`s the raw W3C array (useful in tests). Prefer
    /// `driver.actions()` in application code.
    this(WebDriver driver) { this.driver = driver; }

    private static JSONValue moveTo(string elementId) {
        return JSONValue([
            "type": JSONValue("pointerMove"),
            "duration": JSONValue(0),
            "origin": JSONValue([w3cElementKey: JSONValue(elementId)]),
            "x": JSONValue(0), "y": JSONValue(0)]);
    }
    private static JSONValue pointerDown(int button) {
        return JSONValue(["type": JSONValue("pointerDown"), "button": JSONValue(button)]);
    }
    private static JSONValue pointerUp(int button) {
        return JSONValue(["type": JSONValue("pointerUp"), "button": JSONValue(button)]);
    }

    Actions moveToElement(WebElement el) { pointerSeq ~= moveTo(el.id); return this; }

    Actions click(WebElement el) {
        pointerSeq ~= moveTo(el.id);
        pointerSeq ~= pointerDown(0);
        pointerSeq ~= pointerUp(0);
        return this;
    }
    Actions contextClick(WebElement el) {
        pointerSeq ~= moveTo(el.id);
        pointerSeq ~= pointerDown(2);
        pointerSeq ~= pointerUp(2);
        return this;
    }
    Actions doubleClick(WebElement el) {
        pointerSeq ~= moveTo(el.id);
        pointerSeq ~= pointerDown(0);
        pointerSeq ~= pointerUp(0);
        pointerSeq ~= pointerDown(0);
        pointerSeq ~= pointerUp(0);
        return this;
    }
    Actions dragAndDrop(WebElement source, WebElement target) {
        pointerSeq ~= moveTo(source.id);
        pointerSeq ~= pointerDown(0);
        pointerSeq ~= moveTo(target.id);
        pointerSeq ~= pointerUp(0);
        return this;
    }

    Actions keyDown(string key) {
        keySeq ~= JSONValue(["type": JSONValue("keyDown"), "value": JSONValue(key)]);
        return this;
    }
    Actions keyUp(string key) {
        keySeq ~= JSONValue(["type": JSONValue("keyUp"), "value": JSONValue(key)]);
        return this;
    }
    Actions sendKeys(string text) {
        foreach (dchar c; text) {
            string s = to!string(c);
            keySeq ~= JSONValue(["type": JSONValue("keyDown"), "value": JSONValue(s)]);
            keySeq ~= JSONValue(["type": JSONValue("keyUp"), "value": JSONValue(s)]);
        }
        return this;
    }

    /// The raw W3C actions array for the chained gestures.
    JSONValue build() {
        JSONValue[] devices;
        if (pointerSeq.length > 0) {
            devices ~= JSONValue([
                "type": JSONValue("pointer"),
                "id": JSONValue("mouse"),
                "parameters": JSONValue(["pointerType": JSONValue("mouse")]),
                "actions": JSONValue(pointerSeq)]);
        }
        if (keySeq.length > 0) {
            devices ~= JSONValue([
                "type": JSONValue("key"),
                "id": JSONValue("keyboard"),
                "actions": JSONValue(keySeq)]);
        }
        return JSONValue(devices);
    }

    /// Perform the chained gestures, then reset the builder.
    void perform() {
        driver.performActions(build());
        pointerSeq = null;
        keySeq = null;
    }
}

// ---- BiDi ------------------------------------------------------------------

/// The event-driven BiDi channel for a session. Commands and events multiplex
/// over one WebSocket via the engine's demux; command ids come from a
/// per-channel monotonic counter. Strings are caller-owned (taken here).
final class BiDi {
    private void* handle;
    private int nextId = 1;

    package this(string wsUrl) {
        handle = aether_sel_embed_bidi_open(wsUrl.toStringz);
        if (handle is null)
            throw new WebDriverException(-1, "failed to open BiDi channel");
    }
    ~this() { close(); }
    void close() {
        if (handle !is null) {
            aether_sel_embed_bidi_close(handle);
            handle = null;
        }
    }

    private int takeId() { return nextId++; }

    /// Fire a command (auto-assigned id) and return that id.
    int send(string method, JSONValue params = JSONValue((JSONValue[string]).init)) {
        int id = takeId();
        aether_sel_embed_bidi_send(handle, id, method.toStringz, params.toString().toStringz);
        return id;
    }

    /// Pump the reader for up to `timeoutMs`; returns >0 when progress was made.
    int pump(int timeoutMs) { return aether_sel_embed_bidi_pump(handle, timeoutMs); }

    /// The reply for `id` if already demuxed (JSONValue null if not yet), taken.
    JSONValue pollReply(int id) {
        string raw = takeString(aether_sel_embed_bidi_poll_reply(handle, id));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }

    /// The next queued event, or JSONValue null.
    JSONValue pollEvent() {
        string raw = takeString(aether_sel_embed_bidi_poll_event(handle));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }

    int lostEvents() { return aether_sel_embed_bidi_lost_events(handle); }
    void cancel(int id) { aether_sel_embed_bidi_cancel(handle, id); }

    /// Subscribe to `events` (comma-separated); blocks up to timeout for the ack.
    JSONValue subscribe(string eventsCsv, int timeoutMs = 5000) {
        string raw = takeString(aether_sel_embed_bidi_subscribe(handle, takeId(), eventsCsv.toStringz, timeoutMs));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }
    JSONValue unsubscribe(string eventsCsv, int timeoutMs = 5000) {
        string raw = takeString(aether_sel_embed_bidi_unsubscribe(handle, takeId(), eventsCsv.toStringz, timeoutMs));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }

    /// Block for the next event of `method` (up to timeout), taken.
    JSONValue waitEvent(string method, int timeoutMs = 5000) {
        string raw = takeString(aether_sel_embed_bidi_wait_event(handle, method.toStringz, timeoutMs));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }

    /// browsingContext.getTree (blocking, taken).
    JSONValue getTree(int timeoutMs = 5000) {
        string raw = takeString(aether_sel_embed_bidi_get_tree(handle, takeId(), timeoutMs));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }

    JSONValue scriptEvaluate(string expression, string contextId, int timeoutMs = 5000) {
        string raw = takeString(aether_sel_embed_bidi_script_evaluate(
            handle, takeId(), expression.toStringz, contextId.toStringz, timeoutMs));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }

    JSONValue navigate(string contextId, string url, int timeoutMs = 5000) {
        string raw = takeString(aether_sel_embed_bidi_navigate(
            handle, takeId(), contextId.toStringz, url.toStringz, timeoutMs));
        return raw.length == 0 ? JSONValue(null) : parseJSON(raw);
    }
}
