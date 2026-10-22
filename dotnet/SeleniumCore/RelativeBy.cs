using System;
using System.Collections.Generic;

namespace OpenQA.Selenium;

/// <summary>
/// Relative locators, mirroring mainstream Selenium .NET's
/// <c>OpenQA.Selenium.RelativeBy</c>. Start a chain with
/// <see cref="WithLocator(By)"/>, add spatial relations, then pass the result
/// straight to <c>driver.FindElement(By)</c> / <c>driver.FindElements(By)</c> (a
/// <see cref="RelativeBy"/> is-a <see cref="By"/>):
/// <code>
///   var cell = driver.FindElement(RelativeBy.WithLocator(By.TagName("td")).Below(header));
/// </code>
/// <para>Anchors given as a <see cref="By"/> (TagName / CssSelector / Id /
/// ClassName / Name) resolve to CSS. Existing <see cref="IWebElement"/> anchors
/// are passed to the engine as W3C element references.</para>
/// </summary>
public sealed class RelativeBy : By
{
    private const string W3CElementKey = "element-6066-11e4-a52e-4f735466cecf";
    private readonly By _root;
    private readonly List<Dictionary<string, object?>> _filters;

    private RelativeBy(By root, List<Dictionary<string, object?>> filters)
        // The strategy/value are informational; the driver detects a RelativeBy
        // by type and routes it through the relative-locators atom.
        : base("relative", ByToCss(root))
    {
        _root = root;
        _filters = filters;
    }

    /// <summary>Start a relative locator rooted at the given <see cref="By"/>.</summary>
    public static RelativeBy WithLocator(By by)
    {
        if (by is null)
        {
            throw new ArgumentNullException(nameof(by));
        }
        return new RelativeBy(by, new List<Dictionary<string, object?>>());
    }

    public RelativeBy Above(By anchor) => Add("above", anchor);

    public RelativeBy Above(IWebElement anchor) => Add("above", anchor);

    public RelativeBy Below(By anchor) => Add("below", anchor);

    public RelativeBy Below(IWebElement anchor) => Add("below", anchor);

    public RelativeBy LeftOf(By anchor) => Add("left", anchor);

    public RelativeBy LeftOf(IWebElement anchor) => Add("left", anchor);

    public RelativeBy RightOf(By anchor) => Add("right", anchor);

    public RelativeBy RightOf(IWebElement anchor) => Add("right", anchor);

    public RelativeBy Near(By anchor) => Add("near", anchor);

    public RelativeBy Near(IWebElement anchor) => Add("near", anchor);

    private RelativeBy Add(string kind, object anchor)
    {
        if (anchor is null)
        {
            throw new ArgumentNullException(nameof(anchor));
        }
        var filter = new Dictionary<string, object?> { ["kind"] = kind };
        if (anchor is IWebElement element)
        {
            filter["anchor"] = new Dictionary<string, string> { [W3CElementKey] = element.Id };
        }
        else
        {
            filter["sel"] = ByToCss((By)anchor);
        }
        var next = new List<Dictionary<string, object?>>(_filters)
        {
            filter,
        };
        return new RelativeBy(_root, next);
    }

    /// <summary>The engine base CSS selector (the root, as CSS).</summary>
    public string BaseCss => ByToCss(_root);

    /// <summary>The engine relative filters ({ kind, sel[, dist] } dictionaries).</summary>
    public IReadOnlyList<IDictionary<string, object?>> EngineFilters => _filters.AsReadOnly();

    private static string ByToCss(By by)
    {
        if (by.Strategy is not ("css selector" or "tag name" or "id" or "class name" or "name"))
        {
            throw new ArgumentException(
            $"Relative locators do not support the {by.Strategy} strategy for anchors; "
            + "use CssSelector, TagName, Id, ClassName or Name.");
        }

        return RemoteWebDriver.LocatorValue(by.Strategy, by.Value);
    }
}
