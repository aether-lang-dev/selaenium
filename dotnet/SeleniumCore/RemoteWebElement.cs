using System.Collections.Generic;
using System.Collections.ObjectModel;
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

    /// <summary>Submit the form containing this element (mainstream: walk up to the
    /// enclosing &lt;form&gt; and dispatch submit, in-page — the same atom script the
    /// other bindings use).</summary>
    public void Submit()
    {
        const string script =
            "/* submitForm */var form = arguments[0];\n" +
            "while (form.nodeName != \"FORM\" && form.parentNode) {\n" +
            "  form = form.parentNode;\n" +
            "}\n" +
            "if (!form) { throw Error('Unable to find containing form element'); }\n" +
            "if (!form.ownerDocument) { throw Error('Unable to find owning document'); }\n" +
            "var e = form.ownerDocument.createEvent('Event');\n" +
            "e.initEvent('submit', true, true);\n" +
            "if (form.dispatchEvent(e)) { HTMLFormElement.prototype.submit.call(form) }\n";
        try
        {
            _driver.ExecuteScript(script, this);
        }
        catch (JavaScriptException exc)
        {
            throw new WebDriverException("To submit an element, it must be nested inside a form element", exc);
        }
    }

    public string Text => Exec("getElementText", null)!.Value.GetString()!;
    public string TagName => Exec("getElementTagName", null)!.Value.GetString()!;

    /// <summary>Whether the element is shown (the isDisplayed atom — the visibility
    /// algorithm, run in-page by the engine — not a naive style check).</summary>
    public bool Displayed => _driver.AtomIsDisplayed(Id);

    /// <summary>The classic getAttribute(name): property-or-attribute (boolean attrs,
    /// live properties like value/checked), via the shared engine atom. Use
    /// <see cref="GetDomAttribute(string)"/> for the raw W3C DOM attribute.</summary>
    public string? GetAttribute(string name) => _driver.AtomGetAttribute(Id, name);

    /// <summary>The literal DOM attribute (W3C getDomAttribute), no property fallback.</summary>
    public string? GetDomAttribute(string name) => AsString(GetDomAttributeRaw(name));

    /// <summary>The literal DOM attribute as the raw command payload.</summary>
    public JsonElement? GetDomAttributeRaw(string name) =>
        Exec("getDomAttribute", new Dictionary<string, object?> { ["name"] = name });

    /// <summary>The current value of a DOM property (mainstream <c>GetDomProperty</c>).</summary>
    public string? GetDomProperty(string name) => AsString(GetPropertyRaw(name));

    /// <summary>Alias of <see cref="GetDomProperty"/> kept for existing callers; returns
    /// the raw command payload.</summary>
    public JsonElement? GetProperty(string name) => GetPropertyRaw(name);

    /// <summary>The DOM property as the raw command payload.</summary>
    public JsonElement? GetPropertyRaw(string name) =>
        Exec("getElementProperty", new Dictionary<string, object?> { ["name"] = name });

    /// <summary>The resolved value of a CSS property (mainstream <c>GetCssValue</c>).</summary>
    public string GetCssValue(string name)
    {
        JsonElement? v = Exec("getElementValueOfCssProperty",
            new Dictionary<string, object?> { ["propertyName"] = name });
        return AsString(v) ?? string.Empty;
    }

    /// <summary>This element's shadow root as a search context, or
    /// <see cref="NoSuchShadowRootException"/> if it has none.</summary>
    public ISearchContext GetShadowRoot()
    {
        JsonElement result = Exec("getShadowRoot", null)!.Value;
        if (result.ValueKind == JsonValueKind.Object &&
            result.TryGetProperty(ShadowRoot.ShadowRootKey, out JsonElement idEl))
        {
            return new ShadowRoot(_driver, idEl.GetString()!);
        }
        throw new NoSuchShadowRootException("no such shadow root");
    }

    public bool Enabled => Exec("isElementEnabled", null)!.Value.GetBoolean();
    public bool Selected => Exec("isElementSelected", null)!.Value.GetBoolean();

    public Rect Rect => Exec("getElementRect", null)?.Deserialize<Rect>() ?? new Rect();

    /// <summary>The element's top-left position in the renderable canvas.</summary>
    public System.Drawing.Point Location
    {
        get { Rect r = Rect; return new System.Drawing.Point((int)r.X, (int)r.Y); }
    }

    /// <summary>The element's rendered width and height.</summary>
    public System.Drawing.Size Size
    {
        get { Rect r = Rect; return new System.Drawing.Size((int)r.Width, (int)r.Height); }
    }

    /// <summary>The first descendant matching <paramref name="by"/> (W3C
    /// <c>findChildElement</c>, scoped to this element via the <c>:id</c> path param).</summary>
    public IWebElement FindElement(By by)
    {
        JsonElement result = Exec("findChildElement", RemoteWebDriver.DecodeBy(by.Strategy, by.Value))!.Value;
        return new RemoteWebElement(_driver, result.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!);
    }

    /// <summary>All descendants matching <paramref name="by"/> (W3C
    /// <c>findChildElements</c>, scoped to this element).</summary>
    public ReadOnlyCollection<IWebElement> FindElements(By by)
    {
        JsonElement result = Exec("findChildElements", RemoteWebDriver.DecodeBy(by.Strategy, by.Value))!.Value;
        return new ReadOnlyCollection<IWebElement>(result.EnumerateArray()
            .Select(e => (IWebElement)new RemoteWebElement(_driver, e.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!))
            .ToList());
    }

    // A DOM string value comes back as a JSON string (or null); other kinds
    // (numbers/bools) stringify so mainstream's string-typed accessors still work.
    private static string? AsString(JsonElement? v) => v switch
    {
        null => null,
        { ValueKind: JsonValueKind.Null } => null,
        { ValueKind: JsonValueKind.String } s => s.GetString(),
        { } e => e.ToString(),
    };
}

/// <summary>
/// A shadow root as a search context (mainstream <c>ShadowRoot</c>). Only
/// <see cref="ISearchContext.FindElement"/> / <see cref="ISearchContext.FindElements"/>
/// are supported, scoped inside the shadow tree.
/// </summary>
public sealed class ShadowRoot : ISearchContext
{
    // The W3C shadow-root reference key, distinct from the element key.
    internal const string ShadowRootKey = "shadow-6066-11e4-a52e-4f735466cecf";

    private readonly RemoteWebDriver _driver;

    public string Id { get; }

    internal ShadowRoot(RemoteWebDriver driver, string id)
    {
        _driver = driver;
        Id = id;
    }

    private JsonElement? Exec(string command, IDictionary<string, object?> parameters)
    {
        var p = new Dictionary<string, object?>(parameters) { ["id"] = Id };
        return _driver.Execute(command, p);
    }

    public IWebElement FindElement(By by)
    {
        JsonElement result = Exec("findElementFromShadowRoot", RemoteWebDriver.DecodeBy(by.Strategy, by.Value))!.Value;
        return new RemoteWebElement(_driver, result.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!);
    }

    public ReadOnlyCollection<IWebElement> FindElements(By by)
    {
        JsonElement result = Exec("findElementsFromShadowRoot", RemoteWebDriver.DecodeBy(by.Strategy, by.Value))!.Value;
        return new ReadOnlyCollection<IWebElement>(result.EnumerateArray()
            .Select(e => (IWebElement)new RemoteWebElement(_driver, e.GetProperty(RemoteWebDriver.W3CElementKey).GetString()!))
            .ToList());
    }
}
