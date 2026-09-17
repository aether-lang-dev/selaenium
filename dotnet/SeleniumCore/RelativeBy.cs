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
/// <para>The shared engine's relative-locators atom anchors by CSS selector, so
/// anchors given as a <see cref="By"/> (TagName / CssSelector / Id / ClassName /
/// Name) resolve to CSS. Anchoring by an already-found <see cref="IWebElement"/>
/// is not supported by this engine path and throws.</para>
/// </summary>
public sealed class RelativeBy : By
{
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
        if (anchor is IWebElement)
        {
            throw new ArgumentException(
                "This binding's relative locators anchor by CSS selector, not by a found "
                + "IWebElement; pass a By anchor (e.g. By.Id(\"x\")).", nameof(anchor));
        }
        var next = new List<Dictionary<string, object?>>(_filters)
        {
            new() { ["kind"] = kind, ["sel"] = ByToCss((By)anchor) },
        };
        return new RelativeBy(_root, next);
    }

    /// <summary>The engine base CSS selector (the root, as CSS).</summary>
    public string BaseCss => ByToCss(_root);

    /// <summary>The engine relative filters ({ kind, sel[, dist] } dictionaries).</summary>
    public IReadOnlyList<IDictionary<string, object?>> EngineFilters => _filters.AsReadOnly();

    private static string ByToCss(By by) => by.Strategy switch
    {
        "css selector" or "tag name" => by.Value,
        "id" => "#" + by.Value,
        "class name" => "." + by.Value,
        "name" => "[name=\"" + by.Value + "\"]",
        _ => throw new ArgumentException(
            $"Relative locators do not support the {by.Strategy} strategy for anchors; "
            + "use CssSelector, TagName, Id, ClassName or Name."),
    };
}
