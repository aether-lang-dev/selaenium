using System.Collections.Generic;

namespace OpenQA.Selenium;

/// <summary>
/// A Chrome session that resolves, downloads-or-caches, and launches its OWN
/// chromedriver via the shared engine — no driver on PATH, no Grid. Mirrors
/// Selenium 4.x's <c>OpenQA.Selenium.Chrome.ChromeDriver</c>: the no-arg
/// constructor "just works", and the options constructor threads
/// <c>goog:chromeOptions</c>-style capabilities. The launched driver process is
/// stopped on <see cref="RemoteWebDriver.Quit"/> / <see cref="RemoteWebDriver.Dispose"/>.
/// </summary>
public class ChromeDriver : RemoteWebDriver
{
    /// <summary>Launch chromedriver and start a default Chrome session.</summary>
    public ChromeDriver() : this((IDictionary<string, object?>?)null)
    {
    }

    /// <summary>
    /// Launch chromedriver and start a Chrome session with the given options
    /// (e.g. <c>new Dictionary&lt;string, object?&gt; { ["goog:chromeOptions"] =
    /// new Dictionary&lt;string, object?&gt; { ["args"] = new List&lt;object?&gt;
    /// { "--headless=new" } } }</c>). <c>browserName=chrome</c> is set automatically.
    /// </summary>
    public ChromeDriver(IDictionary<string, object?>? options)
        : this(EnsureChromeDriver(), options)
    {
    }

    /// <summary>
    /// Launch chromedriver and start a Chrome session from a mainstream
    /// <see cref="OpenQA.Selenium.Chrome.ChromeOptions"/> (or any
    /// <see cref="DriverOptions"/>): its <see cref="DriverOptions.ToCapabilities"/>
    /// supplies the capabilities. This is the Selenium 4.x <c>new ChromeDriver(options)</c>
    /// entry point.
    /// </summary>
    public ChromeDriver(DriverOptions options)
        : this(EnsureChromeDriver(), (options ?? throw new System.ArgumentNullException(nameof(options))).ToDictionary())
    {
    }

    private ChromeDriver(DriverProcess proc, IDictionary<string, object?>? options)
        : base(proc.Url, WithChrome(options), null, false)
    {
        AdoptDriver(proc);
    }

    private static DriverProcess EnsureChromeDriver() =>
        EnsureDriver("chrome") ?? throw new WebDriverException("could not resolve/launch chromedriver", -1);

    private static IDictionary<string, object?> WithChrome(IDictionary<string, object?>? options)
    {
        var caps = new Dictionary<string, object?> { ["browserName"] = "chrome" };
        if (options != null)
        {
            foreach (var kv in options)
            {
                caps[kv.Key] = kv.Value;
            }
        }
        return caps;
    }
}
