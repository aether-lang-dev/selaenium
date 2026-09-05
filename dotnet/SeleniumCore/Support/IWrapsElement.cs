namespace OpenQA.Selenium;

/// <summary>
/// Implemented by a type that wraps a single <see cref="IWebElement"/> (e.g.
/// <see cref="Support.UI.SelectElement"/>). Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.IWrapsElement</c>.
/// </summary>
public interface IWrapsElement
{
    /// <summary>The wrapped element.</summary>
    IWebElement WrappedElement { get; }
}
