using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace OpenQA.Selenium;

/// <summary>
/// A WebDriver session over the shared pure-Aether engine (the concrete
/// <see cref="IWebDriver"/> / <see cref="IJavaScriptExecutor"/>). Re-glued to the
/// one <c>libselenium_core.so</c> via P/Invoke (<see cref="NativeMethods"/>);
/// carries NO protocol logic — every command is one native Execute call plus
/// JSON marshalling. The W3C command map, routing, By normalization, error
/// decode and HTTP round-trip all live in the shared engine.
///
/// Named to match Selenium 4.x (<c>OpenQA.Selenium.Remote.RemoteWebDriver</c>
/// shape); <see cref="ChromeDriver"/> subclasses it for the local-launch entry
/// point, and the static <see cref="Chrome"/>/<see cref="LocalChrome"/> factories
/// remain for callers that already use them.
///
/// Command results are returned as <see cref="JsonElement"/> (System.Text.Json).
/// </summary>
public class RemoteWebDriver : IWebDriver
{
    internal const string W3CElementKey = "element-6066-11e4-a52e-4f735466cecf";

    private IntPtr _handle;
    private readonly string _wsUrl;
    private BiDi? _bidi;
    // A driver process this session owns (set by LocalChrome/ChromeDriver);
    // stopped on Quit/Dispose. Null for sessions against a caller-supplied URL.
    private DriverProcess? _ownedDriver;

    /// <summary>
    /// Connect to a running remote end at <paramref name="commandExecutor"/> (a
    /// WebDriver base URL: Grid, a standalone driver, etc.) and start a session
    /// negotiating the given capabilities. Mirrors Selenium 4.x
    /// <c>new RemoteWebDriver(uri, options)</c>.
    /// </summary>
    public RemoteWebDriver(string commandExecutor, IDictionary<string, object?> capabilities)
        : this(commandExecutor, capabilities, null, false)
    {
    }

    protected RemoteWebDriver(string commandExecutor, IDictionary<string, object?> capabilities,
                              string? caPath, bool insecure)
    {
        _handle = NativeMethods.Open(commandExecutor);
        if (_handle == IntPtr.Zero)
        {
            throw new WebDriverException("failed to open session handle", -1);
        }
        // TLS trust config must land on the handle BEFORE newSession (the first
        // request). caPath pins a private-CA bundle; insecure skips verification
        // entirely (self-signed dev/staging Grid — trust the host out-of-band).
        if (!string.IsNullOrEmpty(caPath))
        {
            NativeMethods.SetCa(_handle, caPath);
        }
        if (insecure)
        {
            NativeMethods.SetInsecure(_handle, 1);
        }
        // Request a BiDi channel so `.Bidi` is available on demand; the channel
        // itself is opened lazily (a classic script never opens the WebSocket).
        var caps = new Dictionary<string, object?>(capabilities) { ["webSocketUrl"] = true };
        JsonElement? result = Execute("newSession", new Dictionary<string, object?>
        {
            ["capabilities"] = new Dictionary<string, object?> { ["alwaysMatch"] = caps },
        });
        // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
        _wsUrl = string.Empty;
        if (result is { } value && value.ValueKind == JsonValueKind.Object &&
            value.TryGetProperty("capabilities", out JsonElement negotiated) &&
            negotiated.ValueKind == JsonValueKind.Object &&
            negotiated.TryGetProperty("webSocketUrl", out JsonElement ws) &&
            ws.ValueKind == JsonValueKind.String)
        {
            _wsUrl = ws.GetString() ?? string.Empty;
        }
    }

    /// <summary>Pin an explicit native library path (wins over env/bundled).</summary>
    public static void ConfigureNativeLib(string path) => NativeLoader.Configure(path);

    public static RemoteWebDriver Chrome(string commandExecutor, IDictionary<string, object?>? options = null,
                                         string? caPath = null, bool insecure = false)
    {
        var caps = new Dictionary<string, object?> { ["browserName"] = "chrome" };
        if (options != null)
        {
            foreach (var kv in options)
            {
                caps[kv.Key] = kv.Value;
            }
        }
        return new RemoteWebDriver(commandExecutor, caps, caPath, insecure);
    }

    public static RemoteWebDriver HeadlessChrome(string commandExecutor) =>
        Chrome(commandExecutor, new Dictionary<string, object?>
        {
            ["goog:chromeOptions"] = new Dictionary<string, object?>
            {
                ["args"] = new List<object?> { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" },
            },
        });

    // ---- the FFI seam ----
    /// <summary>Issue any W3C command by name with a params dictionary, returning
    /// the decoded <c>value</c> payload (or null). The generic escape hatch for
    /// commands with no dedicated wrapper (alerts, <c>switchToWindow</c>, …) —
    /// e.g. <c>Execute("acceptAlert", null)</c>.</summary>
    public JsonElement? Execute(string command, IDictionary<string, object?>? parameters)
    {
        string paramsJson = JsonSerializer.Serialize(parameters ?? new Dictionary<string, object?>());
        int rc = NativeMethods.Execute(_handle, command, paramsJson);
        if (rc != 0)
        {
            int code = NativeMethods.LastErrorCode(_handle);
            string message = NativeMethods.TakeString(NativeMethods.LastError(_handle));
            if (rc == -1 && code == 0)
            {
                throw new WebDriverException(string.IsNullOrEmpty(message) ? "transport failure" : message, -1);
            }
            throw Classify(code, message);
        }
        string raw = NativeMethods.TakeString(NativeMethods.LastValue(_handle));
        if (raw.Length == 0)
        {
            return null;
        }
        using var doc = JsonDocument.Parse(raw);
        return doc.RootElement.Clone();
    }

    // ---- atom-backed commands (a shared JS atom run in-page via the engine) ----

    // Drain last_value after an atom call, raising a typed error on rc != 0.
    internal JsonElement? AtomResult(int rc)
    {
        if (rc != 0)
        {
            int code = NativeMethods.LastErrorCode(_handle);
            string message = NativeMethods.TakeString(NativeMethods.LastError(_handle));
            if (rc == -1 && code == 0)
            {
                throw new WebDriverException(string.IsNullOrEmpty(message) ? "transport failure" : message, -1);
            }
            throw Classify(code, message);
        }
        string raw = NativeMethods.TakeString(NativeMethods.LastValue(_handle));
        if (raw.Length == 0)
        {
            return null;
        }
        using var doc = JsonDocument.Parse(raw);
        return doc.RootElement.Clone();
    }

    internal bool AtomIsDisplayed(string elementId) =>
        AtomResult(NativeMethods.IsDisplayed(_handle, elementId))?.GetBoolean() ?? false;

    internal string? AtomGetAttribute(string elementId, string name)
    {
        JsonElement? v = AtomResult(NativeMethods.GetAttribute(_handle, elementId, name));
        return v is { ValueKind: JsonValueKind.String } s ? s.GetString() : null;
    }

    /// <summary>Relative locators: elements matching <paramref name="baseCss"/> filtered by
    /// spatial relation to anchors, nearest first. Each filter is a dictionary
    /// { "kind": "above"|"below"|"left"|"right"|"near", "sel": "&lt;css&gt;" } (near also
    /// accepts "dist").</summary>
    public IReadOnlyList<RemoteWebElement> FindRelative(string baseCss, params IDictionary<string, object?>[] filters)
    {
        string filtersJson = JsonSerializer.Serialize(filters);
        JsonElement? result = AtomResult(NativeMethods.FindRelative(_handle, baseCss, filtersJson));
        var els = new List<RemoteWebElement>();
        if (result is { ValueKind: JsonValueKind.Array } arr)
        {
            foreach (JsonElement r in arr.EnumerateArray())
            {
                if (r.TryGetProperty("element-6066-11e4-a52e-4f735466cecf", out JsonElement idEl))
                {
                    els.Add(new RemoteWebElement(this, idEl.GetString()!));
                }
            }
        }
        return els;
    }

    internal static WebDriverException Classify(int code, string message) => code switch
    {
        3 => new ElementClickInterceptedException(message, code),
        4 => new ElementNotInteractableException(message, code),
        11 => new InvalidSelectorException(message, code),
        13 => new JavaScriptException(message, code),
        17 => new NoSuchElementException(message, code),
        21 or 24 => new TimeoutException(message, code),
        23 => new StaleElementReferenceException(message, code),
        28 => new UnknownCommandException(message, code),
        _ => new WebDriverException(message, code),
    };

    private static Dictionary<string, object?> DecodeBy(string by, string value)
    {
        string raw = NativeMethods.TakeString(NativeMethods.ByLocator(by, value));
        using var doc = JsonDocument.Parse(raw);
        return new Dictionary<string, object?>
        {
            ["using"] = doc.RootElement.GetProperty("using").GetString(),
            ["value"] = doc.RootElement.GetProperty("value").GetString(),
        };
    }

    // ---- navigation ----
    public void Get(string url) => Execute("get", new Dictionary<string, object?> { ["url"] = url });
    public string CurrentUrl => Execute("getCurrentUrl", null)!.Value.GetString()!;
    public string Title => Execute("getTitle", null)!.Value.GetString()!;
    public string PageSource => Execute("getPageSource", null)!.Value.GetString()!;
    public void Back() => Execute("goBack", null);
    public void Forward() => Execute("goForward", null);
    public void Refresh() => Execute("refresh", null);

    // ---- elements ----
    public IWebElement FindElement(By by)
    {
        JsonElement result = Execute("findElement", DecodeBy(by.Strategy, by.Value))!.Value;
        return new RemoteWebElement(this, result.GetProperty(W3CElementKey).GetString()!);
    }

    public IReadOnlyList<IWebElement> FindElements(By by)
    {
        JsonElement result = Execute("findElements", DecodeBy(by.Strategy, by.Value))!.Value;
        return result.EnumerateArray()
            .Select(e => (IWebElement)new RemoteWebElement(this, e.GetProperty(W3CElementKey).GetString()!))
            .ToList();
    }

    // ---- script ----
    public JsonElement? ExecuteScript(string script, params object?[] args) =>
        Execute("executeScript", new Dictionary<string, object?>
        {
            ["script"] = script,
            ["args"] = new List<object?>(args),
        });

    /// <summary>The async script executor: the page calls the injected callback
    /// (last argument) to complete. Use for anything that must turn the event loop.</summary>
    public JsonElement? ExecuteAsyncScript(string script, params object?[] args) =>
        Execute("executeAsyncScript", new Dictionary<string, object?>
        {
            ["script"] = script,
            ["args"] = new List<object?>(args),
        });

    // ---- windows ----
    public IReadOnlyList<string> WindowHandles =>
        Execute("getWindowHandles", null)!.Value.EnumerateArray().Select(e => e.GetString()!).ToList();

    public string CurrentWindowHandle => Execute("getCurrentWindowHandle", null)!.Value.GetString()!;

    public void SwitchToWindow(string handle) =>
        Execute("switchToWindow", new Dictionary<string, object?> { ["handle"] = handle });
    public JsonElement? MaximizeWindow() => Execute("maximizeWindow", null);
    public JsonElement? MinimizeWindow() => Execute("minimizeWindow", null);
    public JsonElement? FullscreenWindow() => Execute("fullscreenWindow", null);
    public Rect SetWindowRect(IDictionary<string, object?> rect) =>
        Execute("setWindowRect", rect)?.Deserialize<Rect>() ?? new Rect();
    public Rect GetWindowRect() =>
        Execute("getWindowRect", null)?.Deserialize<Rect>() ?? new Rect();

    // ---- alerts ----
    public void AcceptAlert() => Execute("acceptAlert", null);
    public void DismissAlert() => Execute("dismissAlert", null);
    public string AlertText => Execute("getAlertText", null)!.Value.GetString()!;
    public void SendAlertText(string text) =>
        Execute("setAlertValue", new Dictionary<string, object?> { ["text"] = text });

    // ---- cookies ----
    public void AddCookie(IDictionary<string, object?> cookie) =>
        Execute("addCookie", new Dictionary<string, object?> { ["cookie"] = cookie });

    public IReadOnlyList<Cookie> GetCookies() =>
        Execute("getCookies", null)?.Deserialize<List<Cookie>>() ?? new List<Cookie>();
    public Cookie GetCookie(string name) =>
        Execute("getCookie", new Dictionary<string, object?> { ["name"] = name })?.Deserialize<Cookie>() ?? new Cookie();
    public void DeleteCookie(string name) => Execute("deleteCookie", new Dictionary<string, object?> { ["name"] = name });
    public void DeleteAllCookies() => Execute("deleteAllCookies", null);

    // ---- actions ----
    public void PerformActions(IList<object?> actions) =>
        Execute("actions", new Dictionary<string, object?> { ["actions"] = actions });
    public void ClearActions() => Execute("clearActions", null);

    // ---- timeouts ----
    public void SetTimeouts(IDictionary<string, object?> timeouts) => Execute("setTimeout", timeouts);
    public void SetPageLoadTimeout(int ms) => Execute("setTimeout", new Dictionary<string, object?> { ["pageLoad"] = ms });
    public void SetScriptTimeout(int ms) => Execute("setTimeout", new Dictionary<string, object?> { ["script"] = ms });
    public void ImplicitlyWait(int ms) => Execute("setTimeout", new Dictionary<string, object?> { ["implicit"] = ms });

    // ---- screenshots ----
    public string ScreenshotBase64() => Execute("screenshot", null)!.Value.GetString()!;

    // ---- lifecycle ----
    public string SessionId => NativeMethods.TakeString(NativeMethods.SessionId(_handle));

    // ---- WebDriver-BiDi ----

    /// <summary>
    /// The event-driven BiDi surface for this session (lazily opened over the
    /// negotiated webSocketUrl). Throws if the remote end granted no BiDi URL.
    ///
    ///     driver.Bidi.Subscribe("log.entryAdded");
    ///     driver.Get(url);
    ///     var ev = driver.Bidi.NextEvent("log.entryAdded", timeoutMs: 5000);
    /// </summary>
    public BiDi Bidi
    {
        get
        {
            if (_bidi == null)
            {
                if (string.IsNullOrEmpty(_wsUrl))
                {
                    throw new WebDriverException("BiDi not available: the session negotiated no webSocketUrl", 0);
                }
                IntPtr handle = NativeMethods.BidiOpen(_wsUrl);
                if (handle == IntPtr.Zero)
                {
                    throw new WebDriverException("BiDi channel failed to open", -1);
                }
                _bidi = new BiDi(handle);
            }
            return _bidi;
        }
    }

    /// <summary>True if this session can use BiDi (a webSocketUrl was negotiated).</summary>
    public bool BidiAvailable => !string.IsNullOrEmpty(_wsUrl);

    public void Quit()
    {
        try
        {
            if (_bidi != null)
            {
                _bidi.Close();
                _bidi = null;
            }
            Execute("quit", null);
        }
        finally
        {
            CloseHandle();
            _ownedDriver?.Stop();
            _ownedDriver = null;
        }
    }

    public void Dispose()
    {
        if (_bidi != null)
        {
            _bidi.Close();
            _bidi = null;
        }
        CloseHandle();
        _ownedDriver?.Stop();
        _ownedDriver = null;
    }

    private void CloseHandle()
    {
        if (_handle != IntPtr.Zero)
        {
            NativeMethods.Close(_handle);
            _handle = IntPtr.Zero;
        }
    }

    // ---- driver orchestration (spawn/adopt a driver process in-binding) ------
    // The engine can resolve, download-or-cache, and launch a browser driver
    // itself — so a caller needs neither a driver on PATH nor a running Grid.

    /// <summary>Resolve the local driver binary path for <paramref name="browser"/>
    /// without launching it (detect/download/cache as needed). <paramref name="hint"/>
    /// pins a version/path; "" auto-detects. Returns "" if none resolvable.</summary>
    public static string ResolveDriver(string browser = "chrome", string hint = "") =>
        NativeMethods.TakeString(NativeMethods.ResolveDriver(browser, hint));

    /// <summary>Launch a driver at an explicit binary path. Returns a
    /// <see cref="DriverProcess"/>, or null if it did not come up in time.</summary>
    public static DriverProcess? LaunchDriver(string driverPath, int timeoutMs = 15000)
    {
        IntPtr h = NativeMethods.LaunchDriver(driverPath, timeoutMs);
        return h == IntPtr.Zero ? null : new DriverProcess(h);
    }

    /// <summary>Resolve (detect/download/cache) AND launch a driver for
    /// <paramref name="browser"/> in one step. Returns a running
    /// <see cref="DriverProcess"/>, or null if none could be resolved/launched.</summary>
    public static DriverProcess? EnsureDriver(string browser = "chrome", string hint = "", int timeoutMs = 15000)
    {
        IntPtr h = NativeMethods.EnsureDriver(browser, hint, timeoutMs);
        return h == IntPtr.Zero ? null : new DriverProcess(h);
    }

    /// <summary>A Chrome session that spawns its OWN chromedriver via the engine —
    /// no driver on PATH, no Grid. The driver process is stopped on Quit/Dispose.
    /// Throws <see cref="WebDriverException"/> if no driver can be resolved/launched.</summary>
    public static RemoteWebDriver LocalChrome(IDictionary<string, object?>? options = null, string hint = "",
                                              int timeoutMs = 15000, string? caPath = null, bool insecure = false)
    {
        DriverProcess proc = EnsureDriver("chrome", hint, timeoutMs)
            ?? throw new WebDriverException("could not resolve/launch chromedriver", -1);
        try
        {
            var caps = new Dictionary<string, object?> { ["browserName"] = "chrome" };
            if (options != null)
            {
                foreach (var kv in options)
                {
                    caps[kv.Key] = kv.Value;
                }
            }
            var driver = new RemoteWebDriver(proc.Url, caps, caPath, insecure);
            driver._ownedDriver = proc;
            return driver;
        }
        catch
        {
            proc.Stop();
            throw;
        }
    }

    /// <summary>Adopt a driver process this session owns so it is stopped on
    /// Quit/Dispose (used by <see cref="ChromeDriver"/>, which launches its own
    /// driver before the base constructor runs).</summary>
    private protected void AdoptDriver(DriverProcess proc) => _ownedDriver = proc;

    // ---- pure engine helpers ----
    public static string Route(string command) => NativeMethods.TakeString(NativeMethods.Route(command));
    public static int ErrorCode(string w3cError) => NativeMethods.ErrorCode(w3cError);
    public static string Locator(string by, string value) => NativeMethods.TakeString(NativeMethods.ByLocator(by, value));
}

/// <summary>A driver process launched by the engine. Owns the opaque driver
/// handle (independent of any session); call <see cref="Stop"/> to terminate it.</summary>
public sealed class DriverProcess
{
    private IntPtr _handle;

    internal DriverProcess(IntPtr handle) => _handle = handle;

    /// <summary>The base URL the driver is listening on — pass to
    /// <see cref="WebDriver.Chrome"/> as the command executor.</summary>
    public string Url => _handle == IntPtr.Zero ? string.Empty
        : NativeMethods.TakeString(NativeMethods.DriverUrl(_handle));

    /// <summary>The driver process id (0 if not running).</summary>
    public int Pid => _handle == IntPtr.Zero ? 0 : NativeMethods.DriverPid(_handle);

    public void Stop()
    {
        if (_handle != IntPtr.Zero)
        {
            NativeMethods.StopDriver(_handle);
            _handle = IntPtr.Zero;
        }
    }
}
