using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Drawing;
using System.Text.Json;

namespace OpenQA.Selenium;

// The upstream-shaped facade surface. Mainstream Selenium-.NET reaches navigation,
// focus-switching and session management through driver.Navigate() / SwitchTo() /
// Manage(); this binding flattened those onto the driver. These interfaces + their
// implementations (all backed by RemoteWebDriver.Execute) restore the facade shape
// ADDITIVELY — the flat methods still work, and there is one source of truth (each
// facade method issues the same W3C command the flat method does).

/// <summary>The kind of top-level context <see cref="ITargetLocator.NewWindow"/>
/// opens. Mirrors Selenium 4.x's <c>OpenQA.Selenium.WindowType</c>.</summary>
public enum WindowType
{
    /// <summary>A new browser window.</summary>
    Window,

    /// <summary>A new browser tab.</summary>
    Tab,
}

/// <summary>
/// The navigation facade returned by <see cref="IWebDriver.Navigate"/>. Mirrors
/// Selenium 4.x's <c>OpenQA.Selenium.INavigation</c>.
/// </summary>
public interface INavigation
{
    void Back();

    void Forward();

    void Refresh();

    /// <summary>Navigate to <paramref name="url"/>.</summary>
    void GoToUrl(string url);

    /// <summary>Navigate to <paramref name="url"/>.</summary>
    void GoToUrl(Uri url);
}

/// <summary>
/// The focus-switching facade returned by <see cref="IWebDriver.SwitchTo"/>. Mirrors
/// Selenium 4.x's <c>OpenQA.Selenium.ITargetLocator</c>.
/// </summary>
public interface ITargetLocator
{
    IWebDriver Frame(int frameIndex);

    IWebDriver Frame(string frameName);

    IWebDriver Frame(IWebElement frameElement);

    IWebDriver ParentFrame();

    IWebDriver Window(string windowName);

    IWebDriver NewWindow(WindowType typeHint);

    IWebDriver DefaultContent();

    IWebElement ActiveElement();

    IAlert Alert();
}

/// <summary>
/// The session-management facade returned by <see cref="IWebDriver.Manage"/>. Mirrors
/// Selenium 4.x's <c>OpenQA.Selenium.IOptions</c>.
/// </summary>
public interface IOptions
{
    ICookieJar Cookies { get; }

    IWindow Window { get; }

    ITimeouts Timeouts();
}

/// <summary>
/// The cookie store reached via <c>Manage().Cookies</c>. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.ICookieJar</c>.
/// </summary>
public interface ICookieJar
{
    ReadOnlyCollection<Cookie> AllCookies { get; }

    void AddCookie(Cookie cookie);

    Cookie? GetCookieNamed(string name);

    void DeleteCookie(Cookie cookie);

    void DeleteCookieNamed(string name);

    void DeleteAllCookies();
}

/// <summary>
/// The window controls reached via <c>Manage().Window</c>. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.IWindow</c> (geometry as <see cref="System.Drawing.Point"/> /
/// <see cref="System.Drawing.Size"/>).
/// </summary>
public interface IWindow
{
    Point Position { get; set; }

    Size Size { get; set; }

    void Maximize();

    void Minimize();

    void FullScreen();
}

/// <summary>
/// The timeout settings reached via <c>Manage().Timeouts()</c>. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.ITimeouts</c> (values as <see cref="TimeSpan"/>). On the wire the
/// engine takes milliseconds, so each setter sends <c>(long)value.TotalMilliseconds</c>.
/// </summary>
public interface ITimeouts
{
    TimeSpan ImplicitWait { get; set; }

    TimeSpan AsynchronousJavaScript { get; set; }

    TimeSpan PageLoad { get; set; }
}

/// <summary>
/// An open JavaScript alert/confirm/prompt, reached via <c>SwitchTo().Alert()</c>.
/// Mirrors Selenium 4.x's <c>OpenQA.Selenium.IAlert</c>.
/// </summary>
public interface IAlert
{
    string? Text { get; }

    void Dismiss();

    void Accept();

    void SendKeys(string keysToSend);
}

// ---- implementations (all backed by the driver's Execute seam) --------------

internal sealed class Navigation : INavigation
{
    private readonly RemoteWebDriver _driver;
    internal Navigation(RemoteWebDriver driver) => _driver = driver;

    public void Back() => _driver.Back();
    public void Forward() => _driver.Forward();
    public void Refresh() => _driver.Refresh();
    public void GoToUrl(string url) => _driver.Get(url);
    public void GoToUrl(Uri url) => _driver.Get((url ?? throw new ArgumentNullException(nameof(url))).ToString());
}

internal sealed class TargetLocator : ITargetLocator
{
    private readonly RemoteWebDriver _driver;
    internal TargetLocator(RemoteWebDriver driver) => _driver = driver;

    public IWebDriver Frame(int frameIndex)
    {
        _driver.Execute("switchToFrame", new Dictionary<string, object?> { ["id"] = frameIndex });
        return _driver;
    }

    public IWebDriver Frame(string frameName)
    {
        // Mainstream resolves a name/id to a frame element first, matching upstream.
        IWebElement frame;
        try
        {
            frame = _driver.FindElement(By.Id(frameName));
        }
        catch (NoSuchElementException)
        {
            try
            {
                frame = _driver.FindElement(By.Name(frameName));
            }
            catch (NoSuchElementException exc)
            {
                throw new NoSuchFrameException(frameName, exc);
            }
        }
        return Frame(frame);
    }

    public IWebDriver Frame(IWebElement frameElement)
    {
        string id = ((RemoteWebElement)frameElement).Id;
        _driver.Execute("switchToFrame", new Dictionary<string, object?>
        {
            ["id"] = new Dictionary<string, object?> { [RemoteWebDriver.W3CElementKey] = id },
        });
        return _driver;
    }

    public IWebDriver ParentFrame()
    {
        _driver.Execute("switchToFrameParent", null);
        return _driver;
    }

    public IWebDriver DefaultContent()
    {
        _driver.Execute("switchToFrame", new Dictionary<string, object?> { ["id"] = null });
        return _driver;
    }

    public IWebDriver Window(string windowName)
    {
        _driver.SwitchToWindow(windowName);
        return _driver;
    }

    public IWebDriver NewWindow(WindowType typeHint)
    {
        string type = typeHint == WindowType.Tab ? "tab" : "window";
        JsonElement? result = _driver.Execute("newWindow", new Dictionary<string, object?> { ["type"] = type });
        if (result is { ValueKind: JsonValueKind.Object } value &&
            value.TryGetProperty("handle", out JsonElement handle) &&
            handle.ValueKind == JsonValueKind.String)
        {
            _driver.SwitchToWindow(handle.GetString()!);
        }
        return _driver;
    }

    public IWebElement ActiveElement()
    {
        JsonElement result = _driver.Execute("getActiveElement", null)!.Value;
        return new RemoteWebElement(_driver, result.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!);
    }

    public IAlert Alert()
    {
        var alert = new AlertImpl(_driver);
        // Touch the text so a missing alert surfaces as NoAlertPresentException here,
        // matching mainstream's SwitchTo().Alert() eager check.
        _ = alert.Text;
        return alert;
    }
}

internal sealed class AlertImpl : IAlert
{
    private readonly RemoteWebDriver _driver;
    internal AlertImpl(RemoteWebDriver driver) => _driver = driver;

    public string? Text
    {
        get
        {
            JsonElement? v = _driver.Execute("getAlertText", null);
            return v is { ValueKind: JsonValueKind.String } s ? s.GetString() : null;
        }
    }

    public void Dismiss() => _driver.Execute("dismissAlert", null);
    public void Accept() => _driver.Execute("acceptAlert", null);

    public void SendKeys(string keysToSend)
    {
        var chars = new List<object?>();
        foreach (char c in keysToSend ?? string.Empty)
        {
            chars.Add(c.ToString());
        }
        _driver.Execute("setAlertValue", new Dictionary<string, object?>
        {
            ["text"] = keysToSend,
            ["value"] = chars,
        });
    }
}

internal sealed class OptionsImpl : IOptions
{
    private readonly RemoteWebDriver _driver;
    internal OptionsImpl(RemoteWebDriver driver) => _driver = driver;

    public ICookieJar Cookies => new CookieJar(_driver);
    public IWindow Window => new WindowImpl(_driver);
    public ITimeouts Timeouts() => new TimeoutsImpl(_driver);
}

internal sealed class CookieJar : ICookieJar
{
    private readonly RemoteWebDriver _driver;
    internal CookieJar(RemoteWebDriver driver) => _driver = driver;

    public ReadOnlyCollection<Cookie> AllCookies =>
        new ReadOnlyCollection<Cookie>(new List<Cookie>(_driver.GetCookies()));

    public void AddCookie(Cookie cookie)
    {
        var dict = new Dictionary<string, object?>
        {
            ["name"] = cookie.Name,
            ["value"] = cookie.Value,
        };
        if (cookie.Domain != null) dict["domain"] = cookie.Domain;
        if (cookie.Path != null) dict["path"] = cookie.Path;
        if (cookie.Expiry.HasValue) dict["expiry"] = cookie.Expiry.Value;
        if (cookie.Secure) dict["secure"] = true;
        if (cookie.HttpOnly) dict["httpOnly"] = true;
        if (cookie.SameSite != null) dict["sameSite"] = cookie.SameSite;
        _driver.AddCookie(dict);
    }

    public Cookie? GetCookieNamed(string name)
    {
        try
        {
            Cookie c = _driver.GetCookie(name);
            // The flat GetCookie yields an empty record when the remote end reports
            // none; treat a name mismatch as "not present" (mainstream returns null).
            return string.IsNullOrEmpty(c.Name) ? null : c;
        }
        catch (WebDriverException)
        {
            return null;
        }
    }

    public void DeleteCookie(Cookie cookie) => _driver.DeleteCookie(cookie.Name);
    public void DeleteCookieNamed(string name) => _driver.DeleteCookie(name);
    public void DeleteAllCookies() => _driver.DeleteAllCookies();
}

internal sealed class WindowImpl : IWindow
{
    private readonly RemoteWebDriver _driver;
    internal WindowImpl(RemoteWebDriver driver) => _driver = driver;

    public Point Position
    {
        get
        {
            Rect r = _driver.GetWindowRect();
            return new Point((int)r.X, (int)r.Y);
        }
        set => _driver.SetWindowRect(new Dictionary<string, object?> { ["x"] = value.X, ["y"] = value.Y });
    }

    public Size Size
    {
        get
        {
            Rect r = _driver.GetWindowRect();
            return new Size((int)r.Width, (int)r.Height);
        }
        set => _driver.SetWindowRect(new Dictionary<string, object?> { ["width"] = value.Width, ["height"] = value.Height });
    }

    public void Maximize() => _driver.MaximizeWindow();
    public void Minimize() => _driver.MinimizeWindow();
    public void FullScreen() => _driver.FullscreenWindow();
}

internal sealed class TimeoutsImpl : ITimeouts
{
    private readonly RemoteWebDriver _driver;
    internal TimeoutsImpl(RemoteWebDriver driver) => _driver = driver;

    // The engine takes milliseconds on the wire; the facade takes TimeSpan (upstream).
    public TimeSpan ImplicitWait
    {
        get => ReadTimeout("implicit");
        set => _driver.Execute("setTimeout", new Dictionary<string, object?> { ["implicit"] = (long)value.TotalMilliseconds });
    }

    public TimeSpan AsynchronousJavaScript
    {
        get => ReadTimeout("script");
        set => _driver.Execute("setTimeout", new Dictionary<string, object?> { ["script"] = (long)value.TotalMilliseconds });
    }

    public TimeSpan PageLoad
    {
        get => ReadTimeout("pageLoad");
        set => _driver.Execute("setTimeout", new Dictionary<string, object?> { ["pageLoad"] = (long)value.TotalMilliseconds });
    }

    private TimeSpan ReadTimeout(string key)
    {
        JsonElement? result = _driver.Execute("getTimeout", null);
        if (result is { ValueKind: JsonValueKind.Object } obj &&
            obj.TryGetProperty(key, out JsonElement v) &&
            v.ValueKind == JsonValueKind.Number)
        {
            return TimeSpan.FromMilliseconds(v.GetDouble());
        }
        return TimeSpan.Zero;
    }
}
