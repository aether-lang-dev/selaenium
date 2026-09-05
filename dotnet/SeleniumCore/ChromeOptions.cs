using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace OpenQA.Selenium.Chrome;

/// <summary>
/// The Chromium-family options base. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Chromium.ChromiumOptions</c>: collect <c>--flags</c> via
/// <see cref="AddArgument"/> / <see cref="AddArguments(string[])"/>, experimental
/// options via <see cref="AddAdditionalChromiumOption"/>, per-profile preferences via
/// <see cref="AddUserProfilePreference"/> and a <see cref="BinaryLocation"/>.
/// <see cref="ToCapabilities"/> nests them all under the vendor capability key
/// (<c>goog:chromeOptions</c> for <see cref="ChromeOptions"/>).
/// </summary>
public abstract class ChromiumOptions : DriverOptions
{
    private readonly List<string> _arguments = new();
    private readonly List<string> _extensions = new();
    private readonly Dictionary<string, object?> _experimentalOptions = new();
    private readonly Dictionary<string, object?> _userProfilePreferences = new();
    private string? _binaryLocation;

    /// <summary>The vendor capability key the options nest under (e.g.
    /// <c>goog:chromeOptions</c>).</summary>
    public abstract string CapabilityName { get; }

    /// <summary>The accumulated command-line arguments.</summary>
    public ReadOnlyCollection<string> Arguments => new ReadOnlyCollection<string>(_arguments);

    /// <summary>The path to the browser binary, or null.</summary>
    public override string? BinaryLocation
    {
        get => _binaryLocation;
        set => _binaryLocation = value;
    }

    /// <summary>The address (host:port) of a running devtools instance to attach to.</summary>
    public string? DebuggerAddress { get; set; }

    /// <summary>Append a command-line argument (e.g. <c>--headless=new</c>).</summary>
    public void AddArgument(string argument)
    {
        if (string.IsNullOrEmpty(argument)) throw new ArgumentException("argument must not be null or empty", nameof(argument));
        _arguments.Add(argument);
    }

    /// <summary>Append several command-line arguments.</summary>
    public void AddArguments(params string[] argumentsToAdd) => AddArguments((IEnumerable<string>)argumentsToAdd);

    /// <summary>Append several command-line arguments.</summary>
    public void AddArguments(IEnumerable<string> argumentsToAdd)
    {
        if (argumentsToAdd == null) throw new ArgumentNullException(nameof(argumentsToAdd));
        foreach (string a in argumentsToAdd) AddArgument(a);
    }

    /// <summary>Set a per-profile preference nested under <c>prefs</c> in the vendor block.</summary>
    public void AddUserProfilePreference(string preferenceName, object preferenceValue)
    {
        _userProfilePreferences[preferenceName] = preferenceValue;
    }

    /// <summary>Set an experimental (vendor-block) option — the protected entry point the
    /// concrete <c>AddAdditionalChromeOption</c> forwards to.</summary>
    protected void AddAdditionalChromiumOption(string optionName, object optionValue)
    {
        _experimentalOptions[optionName] = optionValue;
    }

    /// <summary>Assemble the W3C caps dict with the vendor block under
    /// <see cref="CapabilityName"/> (args, binary, prefs, experimental options).</summary>
    public override IDictionary<string, object?> ToCapabilities()
    {
        var caps = new Dictionary<string, object?>(Capabilities);
        var vendor = new Dictionary<string, object?>(_experimentalOptions)
        {
            ["args"] = new List<string>(_arguments),
        };
        if (_extensions.Count > 0) vendor["extensions"] = new List<string>(_extensions);
        if (!string.IsNullOrEmpty(_binaryLocation)) vendor["binary"] = _binaryLocation;
        if (_userProfilePreferences.Count > 0) vendor["prefs"] = new Dictionary<string, object?>(_userProfilePreferences);
        if (!string.IsNullOrEmpty(DebuggerAddress)) vendor["debuggerAddress"] = DebuggerAddress;
        caps[CapabilityName] = vendor;
        return caps;
    }
}

/// <summary>
/// Chrome/Chromium options. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Chrome.ChromeOptions</c>: nests everything under
/// <c>goog:chromeOptions</c>. A <see cref="ChromeDriver"/> /
/// <see cref="RemoteWebDriver"/> constructor accepts an instance and applies
/// <see cref="ChromiumOptions.ToCapabilities"/>.
/// <code>
/// var options = new ChromeOptions();
/// options.AddArgument("--headless=new");
/// var driver = new ChromeDriver(options);
/// </code>
/// </summary>
public class ChromeOptions : ChromiumOptions
{
    /// <summary>The <c>goog:chromeOptions</c> capability key.</summary>
    public const string ChromeOptionsCapabilityName = "goog:chromeOptions";

    public ChromeOptions()
    {
        BrowserName = "chrome";
    }

    /// <inheritdoc/>
    public override string CapabilityName => ChromeOptionsCapabilityName;

    /// <summary>Set an experimental option in the <c>goog:chromeOptions</c> block
    /// (mainstream <c>AddAdditionalChromeOption</c>).</summary>
    public void AddAdditionalChromeOption(string optionName, object optionValue) =>
        AddAdditionalChromiumOption(optionName, optionValue);
}
