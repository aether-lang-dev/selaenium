using System;
using System.Collections.Generic;

namespace OpenQA.Selenium;

/// <summary>
/// The base for browser options. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.DriverOptions</c>: accumulate top-level W3C capabilities
/// (<see cref="AddAdditionalOption"/>, <see cref="BrowserName"/>, …) and materialize
/// them with <see cref="ToCapabilities"/> / <see cref="ToDictionary"/>. A
/// <see cref="RemoteWebDriver"/> / <see cref="ChromeDriver"/> constructor accepts an
/// options object and calls <see cref="ToDictionary"/> to obtain the caps dict — the
/// mainstream <c>new ChromeDriver(options)</c> entry point.
///
/// The concrete <see cref="ChromeOptions"/> (via <see cref="ChromiumOptions"/>) adds
/// the argument/preference surface and nests everything under
/// <c>goog:chromeOptions</c>.
/// </summary>
public abstract class DriverOptions
{
    // Top-level W3C capabilities (browserName, platformName, arbitrary vendor caps).
    private protected readonly Dictionary<string, object?> Capabilities = new();

    /// <summary>The requested browser name (e.g. "chrome"); set by subclasses.</summary>
    public string? BrowserName
    {
        get => Capabilities.TryGetValue("browserName", out object? v) ? v as string : null;
        protected set
        {
            if (value != null) Capabilities["browserName"] = value;
        }
    }

    /// <summary>The requested browser version, or null.</summary>
    public string? BrowserVersion
    {
        get => Capabilities.TryGetValue("browserVersion", out object? v) ? v as string : null;
        set { if (value != null) Capabilities["browserVersion"] = value; }
    }

    /// <summary>The requested platform name, or null.</summary>
    public string? PlatformName
    {
        get => Capabilities.TryGetValue("platformName", out object? v) ? v as string : null;
        set { if (value != null) Capabilities["platformName"] = value; }
    }

    /// <summary>Whether to accept insecure TLS certificates for this session.</summary>
    public bool? AcceptInsecureCertificates
    {
        get => Capabilities.TryGetValue("acceptInsecureCerts", out object? v) ? v as bool? : null;
        set { if (value.HasValue) Capabilities["acceptInsecureCerts"] = value.Value; }
    }

    /// <summary>The binary path for the browser. The base implementation is a no-op
    /// store; <see cref="ChromiumOptions"/> overrides it to nest under the vendor block.</summary>
    public virtual string? BinaryLocation { get; set; }

    /// <summary>Set an arbitrary top-level W3C capability (mainstream
    /// <c>AddAdditionalOption</c>).</summary>
    public virtual void AddAdditionalOption(string optionName, object optionValue)
    {
        Capabilities[optionName] = optionValue;
    }

    /// <summary>Assemble the W3C capabilities dictionary for this option set.</summary>
    public abstract IDictionary<string, object?> ToCapabilities();

    /// <summary>The capabilities dictionary a driver constructor consumes (mainstream
    /// exposes this as the internal <c>ToDictionary()</c>); an alias of
    /// <see cref="ToCapabilities"/> for this binding's seam.</summary>
    public IDictionary<string, object?> ToDictionary() => ToCapabilities();
}
