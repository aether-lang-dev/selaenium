package org.seleniumhq.aether;

import java.lang.foreign.MemorySegment;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A WebDriver session over the shared pure-Aether engine. Re-glued to the one
 * {@code libselenium_core.so} via Panama FFM ({@link Native}); carries NO
 * protocol logic — every command is one {@code Native.execute} call plus JSON
 * marshalling. The W3C command map, routing, By normalization, error decode and
 * HTTP round-trip all live in the shared engine.
 */
public final class WebDriver {

    static final String W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf";

    private MemorySegment handle;

    // The BiDi endpoint negotiated at newSession; the channel opens lazily.
    private String wsUrl = "";
    private BiDi bidi;

    @SuppressWarnings("unchecked")
    private WebDriver(String commandExecutor, Map<String, Object> capabilities) {
        this.handle = Native.open(commandExecutor);
        if (Native.isNull(handle)) {
            throw new WebDriverError("failed to open session handle", -1);
        }
        // Request a BiDi channel so bidi() is available on demand; the channel
        // itself is opened lazily (a classic script never opens the WebSocket).
        Map<String, Object> caps = new HashMap<>(capabilities);
        caps.put("webSocketUrl", Boolean.TRUE);
        Object result = execute("newSession", Map.of("capabilities", Map.of("alwaysMatch", caps)));
        // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
        if (result instanceof Map<?, ?> m && m.get("capabilities") instanceof Map<?, ?> c) {
            Object ws = ((Map<String, Object>) c).get("webSocketUrl");
            if (ws instanceof String s) {
                this.wsUrl = s;
            }
        }
    }

    /** Pin an explicit native library path (wins over env/bundled discovery). */
    public static void configureNativeLib(String path) {
        Native.configure(path);
    }

    public static WebDriver chrome(String commandExecutor, Map<String, Object> options) {
        Map<String, Object> caps = new HashMap<>();
        caps.put("browserName", "chrome");
        if (options != null) {
            caps.putAll(options);
        }
        return new WebDriver(commandExecutor, caps);
    }

    public static WebDriver headlessChrome(String commandExecutor) {
        return chrome(commandExecutor, Map.of("goog:chromeOptions",
                Map.of("args", List.of("--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"))));
    }

    // ---- the FFI seam ----

    @SuppressWarnings("unchecked")
    Object execute(String command, Map<String, Object> params) {
        int rc = Native.execute(handle, command, Json.encode(params == null ? Map.of() : params));
        if (rc != 0) {
            int code = Native.lastErrorCode(handle);
            String message = Native.lastError(handle);
            if (rc == -1 && code == 0) {
                throw new WebDriverError(message.isEmpty() ? "transport failure" : message, -1);
            }
            throw classify(code, message);
        }
        String raw = Native.lastValue(handle);
        if (raw.isEmpty()) {
            return null;
        }
        return Json.decode(raw);
    }

    // ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

    /** Drain the last_value after an atom call, raising a typed error on rc != 0. */
    Object atomResult(int rc) {
        if (rc != 0) {
            int code = Native.lastErrorCode(handle);
            String message = Native.lastError(handle);
            if (rc == -1 && code == 0) {
                throw new WebDriverError(message.isEmpty() ? "transport failure" : message, -1);
            }
            throw classify(code, message);
        }
        String raw = Native.lastValue(handle);
        return raw.isEmpty() ? null : Json.decode(raw);
    }

    /** last_value drain shared with WebElement's atom calls. */
    MemorySegment handle() {
        return handle;
    }

    /**
     * Relative locators: elements matching {@code baseCss} filtered by spatial
     * relation to anchors, nearest first. Each filter is a map
     * {@code {"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"}}
     * ({@code near} also accepts {@code "dist"}). Returns a list of WebElement.
     */
    @SuppressWarnings("unchecked")
    public List<WebElement> findRelative(String baseCss, List<Map<String, Object>> filters) {
        int rc = Native.findRelative(handle, baseCss, Json.encode(filters == null ? List.of() : filters));
        Object result = atomResult(rc);
        if (!(result instanceof List<?> refs)) {
            return List.of();
        }
        return refs.stream()
                .map(e -> new WebElement(this, (String) ((Map<String, Object>) e).get(W3C_ELEMENT_KEY)))
                .toList();
    }

    static WebDriverError classify(int code, String message) {
        return switch (code) {
            case 3 -> new WebDriverError.ElementClickIntercepted(message, code);
            case 4 -> new WebDriverError.ElementNotInteractable(message, code);
            case 11 -> new WebDriverError.InvalidSelector(message, code);
            case 13 -> new WebDriverError.Javascript(message, code);
            case 17 -> new WebDriverError.NoSuchElement(message, code);
            case 21, 24 -> new WebDriverError.Timeout(message, code);
            case 23 -> new WebDriverError.StaleElementReference(message, code);
            case 28 -> new WebDriverError.UnknownCommand(message, code);
            default -> new WebDriverError(message, code);
        };
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> decodeBy(String by, String value) {
        return (Map<String, Object>) Json.decode(Native.byLocator(by, value));
    }

    // ---- navigation ----
    public void get(String url) {
        execute("get", Map.of("url", url));
    }

    public String currentUrl() {
        return (String) execute("getCurrentUrl", null);
    }

    public String title() {
        return (String) execute("getTitle", null);
    }

    public String pageSource() {
        return (String) execute("getPageSource", null);
    }

    public void back() {
        execute("goBack", null);
    }

    public void forward() {
        execute("goForward", null);
    }

    public void refresh() {
        execute("refresh", null);
    }

    // ---- elements ----
    @SuppressWarnings("unchecked")
    public WebElement findElement(String by, String value) {
        Map<String, Object> result = (Map<String, Object>) execute("findElement", decodeBy(by, value));
        return new WebElement(this, (String) result.get(W3C_ELEMENT_KEY));
    }

    @SuppressWarnings("unchecked")
    public List<WebElement> findElements(String by, String value) {
        List<Object> result = (List<Object>) execute("findElements", decodeBy(by, value));
        return result.stream()
                .map(e -> new WebElement(this, (String) ((Map<String, Object>) e).get(W3C_ELEMENT_KEY)))
                .toList();
    }

    // ---- script ----
    public Object executeScript(String script, Object... args) {
        return execute("executeScript", Map.of("script", script, "args", List.of(args)));
    }

    // ---- windows ----
    @SuppressWarnings("unchecked")
    public List<String> windowHandles() {
        return ((List<Object>) execute("getWindowHandles", null)).stream().map(String.class::cast).toList();
    }

    public String currentWindowHandle() {
        return (String) execute("getCurrentWindowHandle", null);
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> setWindowRect(Map<String, Object> rect) {
        return (Map<String, Object>) execute("setWindowRect", rect);
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> getWindowRect() {
        return (Map<String, Object>) execute("getWindowRect", null);
    }

    // ---- cookies ----
    public void addCookie(Map<String, Object> cookie) {
        execute("addCookie", Map.of("cookie", cookie));
    }

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> getCookies() {
        return ((List<Object>) execute("getCookies", null)).stream()
                .map(o -> (Map<String, Object>) o).toList();
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> getCookie(String name) {
        return (Map<String, Object>) execute("getCookie", Map.of("name", name));
    }

    public void deleteCookie(String name) {
        execute("deleteCookie", Map.of("name", name));
    }

    public void deleteAllCookies() {
        execute("deleteAllCookies", null);
    }

    // ---- actions ----
    public void performActions(List<Object> actions) {
        execute("actions", Map.of("actions", actions));
    }

    public void clearActions() {
        execute("clearActions", null);
    }

    // ---- timeouts ----
    public void setTimeouts(Map<String, Object> timeouts) {
        execute("setTimeout", timeouts);
    }

    // ---- screenshots ----
    public String screenshotBase64() {
        return (String) execute("screenshot", null);
    }

    // ---- WebDriver-BiDi ----

    /**
     * The event-driven BiDi surface for this session (lazily opened over the
     * negotiated webSocketUrl). Throws if the remote end granted no BiDi URL.
     *
     * <pre>{@code
     * driver.bidi().subscribe(BidiEvent.LOG_ENTRY_ADDED);
     * driver.get(url);
     * Map<String, Object> ev = driver.bidi().nextEvent(BidiEvent.LOG_ENTRY_ADDED, 5000);
     * }</pre>
     */
    public BiDi bidi() {
        if (bidi == null) {
            if (wsUrl.isEmpty()) {
                throw new WebDriverError("BiDi not available: the session negotiated no webSocketUrl", 0);
            }
            MemorySegment channel = Native.bidiOpen(wsUrl);
            if (Native.isNull(channel)) {
                throw new WebDriverError("BiDi channel failed to open", -1);
            }
            bidi = new BiDi(channel);
        }
        return bidi;
    }

    /** True if this session can use BiDi (a webSocketUrl was negotiated). */
    public boolean bidiAvailable() {
        return !wsUrl.isEmpty();
    }

    // ---- lifecycle ----
    public String sessionId() {
        return Native.sessionId(handle);
    }

    public void quit() {
        try {
            if (bidi != null) {
                bidi.close();
                bidi = null;
            }
            execute("quit", null);
        } finally {
            closeHandle();
        }
    }

    private void closeHandle() {
        if (handle != null && !Native.isNull(handle)) {
            Native.close(handle);
            handle = null;
        }
    }

    // ---- pure engine helpers ----
    public static String route(String command) {
        return Native.route(command);
    }

    public static int errorCode(String w3cError) {
        return Native.errorCode(w3cError);
    }

    public static String locator(String by, String value) {
        return Native.byLocator(by, value);
    }
}
