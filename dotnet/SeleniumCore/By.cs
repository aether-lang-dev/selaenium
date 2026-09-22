using System;

namespace OpenQA.Selenium;

/// <summary>
/// A locator: a (strategy, value) pair produced by one of the static factory
/// methods and passed to <see cref="IWebDriver.FindElement(By)"/> /
/// <see cref="IWebDriver.FindElements(By)"/>. Mirrors Selenium 4.x's
/// <c>By.Id("x")</c> grammar. The strategy strings are exactly what the shared
/// engine's <c>by_locator</c> accepts; ClassName uses the W3C-canonical
/// <c>"class name"</c> form.
/// </summary>
public class By
{
    // Protected so the relative-locator support (RelativeBy) can extend By and
    // flow through the ordinary FindElement(By) path, as in mainstream Selenium.
    protected By(string strategy, string value)
    {
        Strategy = strategy;
        Value = value;
    }

    /// <summary>The engine strategy string (e.g. <c>"css selector"</c>).</summary>
    public string Strategy { get; }

    /// <summary>The raw selector value.</summary>
    public string Value { get; }

    public static By Id(string value) => new("id", value);

    public static By Name(string value) => new("name", value);

    public static By ClassName(string value) => new("class name", value);

    public static By CssSelector(string value) => new("css selector", value);

    public static By TagName(string value) => new("tag name", value);

    public static By LinkText(string value) => new("link text", value);

    public static By PartialLinkText(string value) => new("partial link text", value);

    // Mainstream OpenQA.Selenium spells it XPath (capital P); a script doing
    // By.XPath(...) must compile. Xpath kept as an alias for existing callers.
    public static By XPath(string value) => new("xpath", value);

    [Obsolete("Use By.XPath (mainstream capitalization).")]
    public static By Xpath(string value) => XPath(value);

    // --- desktop / native strategies (WinAppDriver, Appium) ----------------
    // Against a native driver the engine does NOT rewrite Id/Name/ClassName to
    // CSS: they are the driver's own UIA AutomationId / Name / ClassName, and a
    // native driver has no CSS engine. So the factories above keep working on
    // desktop; these add the strategies that only exist there. Values match
    // Appium's AppiumBy.

    public static By AccessibilityId(string value) => new("accessibility id", value);

    public static By AndroidUIAutomator(string value) => new("androidUIAutomator", value);

    public static By AndroidViewTag(string value) => new("androidViewTag", value);

    public static By AndroidDataMatcher(string value) => new("androidDataMatcher", value);

    public static By AndroidViewMatcher(string value) => new("androidViewMatcher", value);

    public static By IOSPredicate(string value) => new("iOSPredicateString", value);

    public static By IOSClassChain(string value) => new("iOSClassChain", value);

    public static By Image(string value) => new("image", value);

    public static By Custom(string value) => new("custom", value);

    public override string ToString() => $"By.{Strategy}: {Value}";
}
