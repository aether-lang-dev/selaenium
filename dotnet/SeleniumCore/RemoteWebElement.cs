using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace OpenQA.Selenium;

/// <summary>
/// A remote element handle (the concrete <see cref="IWebElement"/>). Methods issue
/// element-scoped commands, passing this element's id as the <c>:id</c> path
/// parameter (the engine separates path params from the body). Named to match
/// Selenium 4.x's <c>RemoteWebElement</c> shape.
/// </summary>
public class RemoteWebElement : IWebElement
{
    private readonly RemoteWebDriver _driver;

    public string Id { get; }

    internal RemoteWebElement(RemoteWebDriver driver, string id)
    {
        _driver = driver;
        Id = id;
    }

    private JsonElement? Exec(string command, IDictionary<string, object?>? parameters)
    {
        var p = parameters == null
            ? new Dictionary<string, object?>()
            : new Dictionary<string, object?>(parameters);
        p["id"] = Id;
        return _driver.Execute(command, p);
    }

    public void Click() => Exec("clickElement", null);
    public void Clear() => Exec("clearElement", null);

    public void SendKeys(string text)
    {
        var chars = new List<object?>();
        foreach (char c in text)
        {
            chars.Add(c.ToString());
        }
        Exec("sendKeysToElement", new Dictionary<string, object?> { ["text"] = text, ["value"] = chars });
    }

    public string Text => Exec("getElementText", null)!.Value.GetString()!;
    public string TagName => Exec("getElementTagName", null)!.Value.GetString()!;

    /// <summary>Whether the element is shown (the isDisplayed atom — the visibility
    /// algorithm, run in-page by the engine — not a naive style check).</summary>
    public bool Displayed => _driver.AtomIsDisplayed(Id);

    /// <summary>The classic getAttribute(name): property-or-attribute (boolean attrs,
    /// live properties like value/checked), via the shared engine atom. Use
    /// <see cref="GetDomAttribute"/> for the raw W3C DOM attribute.</summary>
    public string? GetAttribute(string name) => _driver.AtomGetAttribute(Id, name);

    /// <summary>The literal DOM attribute (W3C getDomAttribute), no property fallback.</summary>
    public JsonElement? GetDomAttribute(string name) =>
        Exec("getDomAttribute", new Dictionary<string, object?> { ["name"] = name });

    public JsonElement? GetProperty(string name) =>
        Exec("getElementProperty", new Dictionary<string, object?> { ["name"] = name });

    public bool Enabled => Exec("isElementEnabled", null)!.Value.GetBoolean();
    public bool Selected => Exec("isElementSelected", null)!.Value.GetBoolean();

    public Rect Rect => Exec("getElementRect", null)?.Deserialize<Rect>() ?? new Rect();

    /// <summary>The first descendant matching <paramref name="by"/> (W3C
    /// <c>findChildElement</c>, scoped to this element via the <c>:id</c> path param).</summary>
    public IWebElement FindElement(By by)
    {
        JsonElement result = Exec("findChildElement", RemoteWebDriver.DecodeBy(by.Strategy, by.Value))!.Value;
        return new RemoteWebElement(_driver, result.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!);
    }

    /// <summary>All descendants matching <paramref name="by"/> (W3C
    /// <c>findChildElements</c>, scoped to this element).</summary>
    public IReadOnlyList<IWebElement> FindElements(By by)
    {
        JsonElement result = Exec("findChildElements", RemoteWebDriver.DecodeBy(by.Strategy, by.Value))!.Value;
        return result.EnumerateArray()
            .Select(e => (IWebElement)new RemoteWebElement(_driver, e.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!))
            .ToList();
    }
}
