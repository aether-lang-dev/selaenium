package org.openqa.selenium;

import java.lang.foreign.MemorySegment;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A WebDriver session over the shared pure-Aether engine (the concrete
 * {@link WebDriver} / {@link JavascriptExecutor}). Re-glued to the one
 * {@code libselenium_core.so} via Panama FFM ({@link Native}); carries NO
 * protocol logic — every command is one {@code Native.execute} call plus JSON
 * marshalling. The W3C command map, routing, By normalization, error decode and
 * HTTP round-trip all live in the shared engine.
 *
 * <p>Named to match Selenium 4.x ({@code org.openqa.selenium.remote.RemoteWebDriver}
 * shape). {@link ChromeDriver} subclasses it for the local-launch entry point;
 * the {@code chrome}/{@code localChrome} static factories remain for callers
 * that already use them.
 */
public class RemoteWebDriver implements WebDriver {

    static final String W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf";

    private MemorySegment handle;

    // The BiDi endpoint negotiated at newSession; the channel opens lazily.
    private String wsUrl = "";
    private BiDi bidi;
    // A driver process this session owns (set by localChrome); stopped on quit().
    private DriverProcess ownedDriver;

    /**
     * Connect to a running remote end at {@code commandExecutor} (a WebDriver
     * base URL: Grid, a standalone driver, etc.) and start a session negotiating
     * the given capabilities. Mirrors Selenium 4.x
     * {@code new RemoteWebDriver(url, capabilities)}.
     */
    public RemoteWebDriver(String commandExecutor, Map<String, Object> capabilities) {
        this(commandExecutor, capabilities, null, false);
    }

    @SuppressWarnings("unchecked")
    protected RemoteWebDriver(String commandExecutor, Map<String, Object> capabilities,
                              String caPath, boolean insecure) {
        this.handle = Native.open(commandExecutor);
        if (Native.isNull(handle)) {
            throw new WebDriverException("failed to open session handle", -1);
        }
        // TLS trust config must land on the handle BEFORE newSession (the first
        // request). caPath pins a private-CA bundle; insecure skips verification
        // entirely (self-signed dev/staging Grid — trust the host out-of-band).
        if (caPath != null && !caPath.isEmpty()) {
            Native.setCa(handle, caPath);
        }
        if (insecure) {
            Native.setInsecure(handle, 1);
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

    /**
     * Start a session against an engine-launched driver process, adopting
     * ownership so {@link #quit()} tears the process down. Used by local-launch
     * subclasses ({@link ChromeDriver}).
     */
    protected RemoteWebDriver(DriverProcess ownedDriver, Map<String, Object> capabilities,
                              String caPath, boolean insecure) {
        this(ownedDriver.url(), capabilities, caPath, insecure);
        this.ownedDriver = ownedDriver;
    }

    /** Pin an explicit native library path (wins over env/bundled discovery). */
    public static void configureNativeLib(String path) {
        Native.configure(path);
    }

    public static RemoteWebDriver chrome(String commandExecutor, Map<String, Object> options) {
        return chrome(commandExecutor, options, null, false);
    }

    public static RemoteWebDriver chrome(String commandExecutor, Map<String, Object> options,
                                         String caPath, boolean insecure) {
        Map<String, Object> caps = new HashMap<>();
        caps.put("browserName", "chrome");
        if (options != null) {
            caps.putAll(options);
        }
        return new RemoteWebDriver(commandExecutor, caps, caPath, insecure);
    }

    public static RemoteWebDriver headlessChrome(String commandExecutor) {
        return chrome(commandExecutor, Map.of("goog:chromeOptions",
                Map.of("args", List.of("--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"))));
    }

    // ---- driver orchestration (spawn/adopt a driver process in-binding) ------
    // The engine can resolve, download-or-cache, and launch a browser driver
    // itself — so a caller needs neither a driver on PATH nor a running Grid.

    /**
     * Resolve the local driver binary path for {@code browser} without launching
     * it (detect/download/cache as needed). {@code hint} pins a version/path; ""
     * auto-detects. Returns "" if none resolvable (offline, no cache).
     */
    public static String resolveDriver(String browser, String hint) {
        return Native.resolveDriver(browser, hint);
    }

    public static String resolveDriver(String browser) {
        return resolveDriver(browser, "");
    }

    /** Launch a driver at an explicit binary path. Returns null if it did not come up. */
    public static DriverProcess launchDriver(String driverPath, int timeoutMs) {
        MemorySegment dh = Native.launchDriver(driverPath, timeoutMs);
        return Native.isNull(dh) ? null : new DriverProcess(dh);
    }

    public static DriverProcess launchDriver(String driverPath) {
        return launchDriver(driverPath, 15000);
    }

    /** Resolve (detect/download/cache) AND launch a driver in one step. Returns null on failure. */
    public static DriverProcess ensureDriver(String browser, String hint, int timeoutMs) {
        MemorySegment dh = Native.ensureDriver(browser, hint, timeoutMs);
        return Native.isNull(dh) ? null : new DriverProcess(dh);
    }

    public static DriverProcess ensureDriver(String browser) {
        return ensureDriver(browser, "", 15000);
    }

    /**
     * A Chrome session that spawns its OWN chromedriver via the engine — no driver
     * on PATH, no Grid. The driver process is stopped on {@link #quit()}. Throws
     * {@link WebDriverException} if no driver can be resolved/launched.
     */
    public static RemoteWebDriver localChrome(Map<String, Object> options, String hint, int timeoutMs,
                                              String caPath, boolean insecure) {
        DriverProcess proc = ensureDriver("chrome", hint, timeoutMs);
        if (proc == null) {
            throw new WebDriverException("could not resolve/launch chromedriver", -1);
        }
        try {
            Map<String, Object> caps = new HashMap<>();
            caps.put("browserName", "chrome");
            if (options != null) {
                caps.putAll(options);
            }
            RemoteWebDriver driver = new RemoteWebDriver(proc.url(), caps, caPath, insecure);
            driver.ownedDriver = proc;
            return driver;
        } catch (RuntimeException e) {
            proc.stop();
            throw e;
        }
    }

    public static RemoteWebDriver localChrome(Map<String, Object> options) {
        return localChrome(options, "", 15000, null, false);
    }

    // ---- the FFI seam ----

    /**
     * Issue any W3C command by name with a params map, returning the decoded
     * {@code value} payload (or null). The generic escape hatch for commands
     * this binding has no dedicated wrapper for (alerts, {@code switchToWindow},
     * etc.) — e.g. {@code execute("acceptAlert", Map.of())}.
     */
    public Object execute(String command, Map<String, Object> params) {
        int rc = Native.execute(handle, command, Json.encode(params == null ? Map.of() : params));
        if (rc != 0) {
            int code = Native.lastErrorCode(handle);
            String message = Native.lastError(handle);
            if (rc == -1 && code == 0) {
                throw new WebDriverException(message.isEmpty() ? "transport failure" : message, -1);
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
                throw new WebDriverException(message.isEmpty() ? "transport failure" : message, -1);
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
    @Override
    @SuppressWarnings("unchecked")
    public List<WebElement> findRelative(String baseCss, List<Map<String, Object>> filters) {
        int rc = Native.findRelative(handle, baseCss, Json.encode(filters == null ? List.of() : filters));
        Object result = atomResult(rc);
        if (!(result instanceof List<?> refs)) {
            return List.of();
        }
        return refs.stream()
                .map(e -> (WebElement) new RemoteWebElement(this, (String) ((Map<String, Object>) e).get(W3C_ELEMENT_KEY)))
                .toList();
    }

    static WebDriverException classify(int code, String message) {
        return switch (code) {
            case 3 -> new ElementClickInterceptedException(message, code);
            case 4 -> new ElementNotInteractableException(message, code);
            case 11 -> new InvalidSelectorException(message, code);
            case 13 -> new JavascriptException(message, code);
            case 17 -> new NoSuchElementException(message, code);
            case 21, 24 -> new TimeoutException(message, code);
            case 23 -> new StaleElementReferenceException(message, code);
            case 28 -> new UnknownCommandException(message, code);
            default -> new WebDriverException(message, code);
        };
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> decodeBy(String by, String value) {
        return (Map<String, Object>) Json.decode(Native.byLocator(by, value));
    }

    // ---- navigation ----
    @Override
    public void get(String url) {
        execute("get", Map.of("url", url));
    }

    @Override
    public String getCurrentUrl() {
        return (String) execute("getCurrentUrl", null);
    }

    @Override
    public String getTitle() {
        return (String) execute("getTitle", null);
    }

    @Override
    public String getPageSource() {
        return (String) execute("getPageSource", null);
    }

    @Override
    public void back() {
        execute("goBack", null);
    }

    @Override
    public void forward() {
        execute("goForward", null);
    }

    @Override
    public void refresh() {
        execute("refresh", null);
    }

    // ---- elements ----
    @Override
    @SuppressWarnings("unchecked")
    public WebElement findElement(By by) {
        Map<String, Object> result = (Map<String, Object>) execute("findElement", decodeBy(by.strategy(), by.value()));
        return new RemoteWebElement(this, (String) result.get(W3C_ELEMENT_KEY));
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<WebElement> findElements(By by) {
        List<Object> result = (List<Object>) execute("findElements", decodeBy(by.strategy(), by.value()));
        return result.stream()
                .map(e -> (WebElement) new RemoteWebElement(this, (String) ((Map<String, Object>) e).get(W3C_ELEMENT_KEY)))
                .toList();
    }

    // ---- script ----
    @Override
    public Object executeScript(String script, Object... args) {
        return execute("executeScript", Map.of("script", script, "args", List.of(args)));
    }

    @Override
    public Object executeAsyncScript(String script, Object... args) {
        return execute("executeAsyncScript", Map.of("script", script, "args", List.of(args)));
    }

    // ---- windows ----
    @Override
    @SuppressWarnings("unchecked")
    public List<String> windowHandles() {
        return ((List<Object>) execute("getWindowHandles", null)).stream().map(String.class::cast).toList();
    }

    @Override
    public String currentWindowHandle() {
        return (String) execute("getCurrentWindowHandle", null);
    }

    @Override
    public void switchToWindow(String handle) {
        execute("switchToWindow", Map.of("handle", handle));
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> maximizeWindow() {
        return (Map<String, Object>) execute("maximizeWindow", null);
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> minimizeWindow() {
        return (Map<String, Object>) execute("minimizeWindow", null);
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> fullscreenWindow() {
        return (Map<String, Object>) execute("fullscreenWindow", null);
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> setWindowRect(Map<String, Object> rect) {
        return (Map<String, Object>) execute("setWindowRect", rect);
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> getWindowRect() {
        return (Map<String, Object>) execute("getWindowRect", null);
    }

    // ---- cookies ----
    @Override
    public void addCookie(Map<String, Object> cookie) {
        execute("addCookie", Map.of("cookie", cookie));
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> getCookies() {
        return ((List<Object>) execute("getCookies", null)).stream()
                .map(o -> (Map<String, Object>) o).toList();
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> getCookie(String name) {
        return (Map<String, Object>) execute("getCookie", Map.of("name", name));
    }

    @Override
    public void deleteCookie(String name) {
        execute("deleteCookie", Map.of("name", name));
    }

    @Override
    public void deleteAllCookies() {
        execute("deleteAllCookies", null);
    }

    // ---- actions ----
    @Override
    public void performActions(List<Object> actions) {
        execute("actions", Map.of("actions", actions));
    }

    @Override
    public void clearActions() {
        execute("clearActions", null);
    }

    // ---- alerts ----
    @Override
    public void acceptAlert() {
        execute("acceptAlert", null);
    }

    @Override
    public void dismissAlert() {
        execute("dismissAlert", null);
    }

    @Override
    public String alertText() {
        return (String) execute("getAlertText", null);
    }

    @Override
    public void sendAlertText(String text) {
        execute("setAlertValue", Map.of("text", text));
    }

    // ---- timeouts ----
    @Override
    public void setTimeouts(Map<String, Object> timeouts) {
        execute("setTimeout", timeouts);
    }

    @Override
    public void setPageLoadTimeout(long ms) {
        execute("setTimeout", Map.of("pageLoad", ms));
    }

    @Override
    public void setScriptTimeout(long ms) {
        execute("setTimeout", Map.of("script", ms));
    }

    @Override
    public void implicitlyWait(long ms) {
        execute("setTimeout", Map.of("implicit", ms));
    }

    // ---- screenshots ----
    @Override
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
    @Override
    public BiDi bidi() {
        if (bidi == null) {
            if (wsUrl.isEmpty()) {
                throw new WebDriverException("BiDi not available: the session negotiated no webSocketUrl", 0);
            }
            MemorySegment channel = Native.bidiOpen(wsUrl);
            if (Native.isNull(channel)) {
                throw new WebDriverException("BiDi channel failed to open", -1);
            }
            bidi = new BiDi(channel);
        }
        return bidi;
    }

    /** True if this session can use BiDi (a webSocketUrl was negotiated). */
    @Override
    public boolean bidiAvailable() {
        return !wsUrl.isEmpty();
    }

    // ---- lifecycle ----
    @Override
    public String sessionId() {
        return Native.sessionId(handle);
    }

    @Override
    public void quit() {
        try {
            if (bidi != null) {
                bidi.close();
                bidi = null;
            }
            execute("quit", null);
        } finally {
            closeHandle();
            if (ownedDriver != null) {
                ownedDriver.stop();
                ownedDriver = null;
            }
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

    /**
     * A driver process launched by the engine. Owns the opaque driver handle
     * (independent of any session); call {@link #stop()} to terminate it.
     */
    public static final class DriverProcess {
        private MemorySegment handle;

        DriverProcess(MemorySegment handle) {
            this.handle = handle;
        }

        /** The base URL the driver is listening on — pass to {@link #chrome}. */
        public String url() {
            return handle == null ? "" : Native.driverUrl(handle);
        }

        /** The driver process id (0 if not running). */
        public int pid() {
            return handle == null ? 0 : Native.driverPid(handle);
        }

        public void stop() {
            if (handle != null && !Native.isNull(handle)) {
                Native.stopDriver(handle);
                handle = null;
            }
        }
    }
}
