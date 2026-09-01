using System.Collections.Generic;
using System.Text.Json;

namespace SeleniumCore;

/// <summary>
/// A remote element handle. Methods issue element-scoped commands, passing this
/// element's id as the <c>:id</c> path parameter (the engine separates path
/// params from the body).
/// </summary>
public sealed class WebElement
{
    private readonly WebDriver _driver;

    public string Id { get; }

    internal WebElement(WebDriver driver, string id)
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
    public bool IsDisplayed() => _driver.AtomIsDisplayed(Id);

    /// <summary>The classic getAttribute(name): property-or-attribute (boolean attrs,
    /// live properties like value/checked), via the shared engine atom. Use
    /// <see cref="GetDomAttribute"/> for the raw W3C DOM attribute.</summary>
    public string? GetAttribute(string name) => _driver.AtomGetAttribute(Id, name);

    /// <summary>The literal DOM attribute (W3C getDomAttribute), no property fallback.</summary>
    public JsonElement? GetDomAttribute(string name) =>
        Exec("getDomAttribute", new Dictionary<string, object?> { ["name"] = name });

    public JsonElement? GetProperty(string name) =>
        Exec("getElementProperty", new Dictionary<string, object?> { ["name"] = name });

    public bool IsEnabled() => Exec("isElementEnabled", null)!.Value.GetBoolean();
    public bool IsSelected() => Exec("isElementSelected", null)!.Value.GetBoolean();

    public Rect Rect => Exec("getElementRect", null)?.Deserialize<Rect>() ?? new Rect();
}
