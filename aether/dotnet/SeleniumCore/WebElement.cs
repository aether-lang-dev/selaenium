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

    public JsonElement? GetAttribute(string name) =>
        Exec("getDomAttribute", new Dictionary<string, object?> { ["name"] = name });

    public JsonElement? GetProperty(string name) =>
        Exec("getElementProperty", new Dictionary<string, object?> { ["name"] = name });

    public bool IsEnabled() => Exec("isElementEnabled", null)!.Value.GetBoolean();
    public bool IsSelected() => Exec("isElementSelected", null)!.Value.GetBoolean();

    public JsonElement Rect => Exec("getElementRect", null)!.Value;
}
