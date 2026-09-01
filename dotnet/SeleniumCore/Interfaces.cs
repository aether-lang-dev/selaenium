using System.Collections.Generic;
using System.Text.Json;

namespace OpenQA.Selenium;

/// <summary>
/// Runs JavaScript in the page. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.IJavaScriptExecutor</c>; <see cref="IWebDriver"/> extends it
/// so every session can execute scripts.
/// </summary>
public interface IJavaScriptExecutor
{
    JsonElement? ExecuteScript(string script, params object?[] args);

    JsonElement? ExecuteAsyncScript(string script, params object?[] args);
}

/// <summary>
/// A WebDriver session. Mirrors Selenium 4.x's <c>OpenQA.Selenium.IWebDriver</c>
/// surface (property getters, one-arg <see cref="FindElement(By)"/>). The concrete
/// implementation is <see cref="RemoteWebDriver"/> (and its subclass
/// <see cref="ChromeDriver"/>). Extends <see cref="IJavaScriptExecutor"/>.
/// </summary>
public interface IWebDriver : IJavaScriptExecutor, System.IDisposable
{
    // ---- navigation ----
    void Get(string url);

    string CurrentUrl { get; }

    string Title { get; }

    string PageSource { get; }

    void Back();

    void Forward();

    void Refresh();

    // ---- elements ----
    IWebElement FindElement(By by);

    IReadOnlyList<IWebElement> FindElements(By by);

    // ---- windows ----
    IReadOnlyList<string> WindowHandles { get; }

    string CurrentWindowHandle { get; }

    void SwitchToWindow(string handle);

    // ---- lifecycle ----
    string SessionId { get; }

    void Quit();
}

/// <summary>
/// A located element. Mirrors Selenium 4.x's <c>OpenQA.Selenium.IWebElement</c>
/// surface. The concrete implementation is <see cref="RemoteWebElement"/>. Boolean
/// element state is exposed as properties (<see cref="Enabled"/>,
/// <see cref="Selected"/>, <see cref="Displayed"/>), matching the .NET grammar.
/// </summary>
public interface IWebElement
{
    string Id { get; }

    void Click();

    void Clear();

    void SendKeys(string text);

    string Text { get; }

    string TagName { get; }

    bool Enabled { get; }

    bool Selected { get; }

    bool Displayed { get; }

    string? GetAttribute(string name);

    Rect Rect { get; }
}
