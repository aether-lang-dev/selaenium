using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
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
/// Something that elements can be found within (a driver or an element). Mirrors
/// Selenium 4.x's <c>OpenQA.Selenium.ISearchContext</c>. Both <see cref="IWebDriver"/>
/// and <see cref="IWebElement"/> extend it, so a helper can take either.
/// </summary>
public interface ISearchContext
{
    /// <summary>Find the first element matching <paramref name="by"/>.</summary>
    IWebElement FindElement(By by);

    /// <summary>Find all elements matching <paramref name="by"/>.</summary>
    ReadOnlyCollection<IWebElement> FindElements(By by);
}

/// <summary>
/// Captures a screenshot. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.ITakesScreenshot</c>; <see cref="RemoteWebDriver"/> implements it.
/// </summary>
public interface ITakesScreenshot
{
    /// <summary>Take a screenshot of the current page.</summary>
    Screenshot GetScreenshot();
}

/// <summary>
/// A WebDriver session. Mirrors Selenium 4.x's <c>OpenQA.Selenium.IWebDriver</c>
/// surface: the <see cref="Navigate"/> / <see cref="SwitchTo"/> / <see cref="Manage"/>
/// facades plus <see cref="Url"/>, <see cref="Close"/> and the inherited
/// <see cref="ISearchContext"/> finds. The concrete implementation is
/// <see cref="RemoteWebDriver"/> (and its subclass <see cref="ChromeDriver"/>).
///
/// The binding's original flat methods (<see cref="Get"/>, <see cref="Back"/>,
/// <see cref="SwitchToWindow"/>, …) remain on the concrete class so both styles work;
/// this interface carries the upstream-shaped surface a drop-in script uses.
/// </summary>
public interface IWebDriver : ISearchContext, IJavaScriptExecutor, IDisposable
{
    // ---- navigation ----
    /// <summary>The current page URL. The getter reads it; the setter navigates
    /// (mainstream <c>driver.Url = "..."</c>).</summary>
    string Url { get; set; }

    /// <summary>Navigate to <paramref name="url"/> (the binding's original flat
    /// method; <c>Navigate().GoToUrl(url)</c> and <c>Url = url</c> do the same).</summary>
    void Get(string url);

    string CurrentUrl { get; }

    string Title { get; }

    string PageSource { get; }

    void Back();

    void Forward();

    void Refresh();

    // ---- windows ----
    ReadOnlyCollection<string> WindowHandles { get; }

    string CurrentWindowHandle { get; }

    void SwitchToWindow(string handle);

    // ---- facades (upstream reaches everything through these) ----
    /// <summary>The navigation facade (<c>Back/Forward/Refresh/GoToUrl</c>).</summary>
    INavigation Navigate();

    /// <summary>The focus-switching facade (frames, windows, alerts, active element).</summary>
    ITargetLocator SwitchTo();

    /// <summary>The session-management facade (cookies, window, timeouts).</summary>
    IOptions Manage();

    // ---- actions ----
    /// <summary>Post a raw W3C "actions" payload (the low-level input-source list).
    /// <see cref="Interactions.Actions"/> builds this list fluently.</summary>
    void PerformActions(IList<object?> actions);

    /// <summary>Release all input state (W3C <c>clearActions</c>).</summary>
    void ClearActions();

    // ---- lifecycle ----
    string SessionId { get; }

    /// <summary>Close the current window (W3C <c>closeWindow</c>).</summary>
    void Close();

    void Quit();
}

/// <summary>
/// A located element. Mirrors Selenium 4.x's <c>OpenQA.Selenium.IWebElement</c>
/// surface, and extends <see cref="ISearchContext"/> so descendants can be found
/// within it. The concrete implementation is <see cref="RemoteWebElement"/>. Boolean
/// element state is exposed as properties (<see cref="Enabled"/>,
/// <see cref="Selected"/>, <see cref="Displayed"/>), matching the .NET grammar.
/// </summary>
public interface IWebElement : ISearchContext
{
    string Id { get; }

    void Click();

    void Clear();

    void SendKeys(string text);

    /// <summary>Submit the form containing this element (mainstream <c>Submit()</c>).</summary>
    void Submit();

    string Text { get; }

    string TagName { get; }

    bool Enabled { get; }

    bool Selected { get; }

    bool Displayed { get; }

    /// <summary>The element's top-left position in the renderable canvas.</summary>
    System.Drawing.Point Location { get; }

    /// <summary>The element's rendered width and height.</summary>
    System.Drawing.Size Size { get; }

    string? GetAttribute(string name);

    /// <summary>The literal DOM attribute (W3C getDomAttribute), no property fallback.</summary>
    string? GetDomAttribute(string name);

    /// <summary>The current value of a DOM property (mainstream <c>GetDomProperty</c>).</summary>
    string? GetDomProperty(string name);

    /// <summary>The resolved value of a CSS property (mainstream <c>GetCssValue</c>).</summary>
    string GetCssValue(string name);

    /// <summary>The element's shadow root as a search context, or throws
    /// <see cref="NoSuchShadowRootException"/> if it has none.</summary>
    ISearchContext GetShadowRoot();

    Rect Rect { get; }
}
