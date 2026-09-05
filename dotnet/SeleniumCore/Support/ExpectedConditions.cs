using System;

namespace OpenQA.Selenium.Support.UI;

/// <summary>
/// A small set of canned conditions for <see cref="WebDriverWait"/>, mirroring the
/// most-used members of Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.ExpectedConditions</c>. Each returns a
/// <c>Func&lt;IWebDriver, T&gt;</c> to pass straight to
/// <see cref="IWait{T}.Until{TResult}(Func{T, TResult})"/>. A plain lambda works just
/// as well — these are the ergonomic shortcuts mainstream scripts reach for.
/// </summary>
public static class ExpectedConditions
{
    /// <summary>An expectation that an element is present in the DOM. Returns the
    /// element once found (retrying on not-found, which the wait ignores).</summary>
    public static Func<IWebDriver, IWebElement> ElementExists(By locator)
    {
        return driver => driver.FindElement(locator);
    }

    /// <summary>An expectation that an element is present and visible.</summary>
    public static Func<IWebDriver, IWebElement?> ElementIsVisible(By locator)
    {
        return driver =>
        {
            IWebElement element = driver.FindElement(locator);
            return element.Displayed ? element : null;
        };
    }

    /// <summary>An expectation that an element is visible and enabled (clickable).</summary>
    public static Func<IWebDriver, IWebElement?> ElementToBeClickable(By locator)
    {
        return driver =>
        {
            IWebElement element = driver.FindElement(locator);
            return element.Displayed && element.Enabled ? element : null;
        };
    }

    /// <summary>An expectation that the page title equals <paramref name="title"/>.</summary>
    public static Func<IWebDriver, bool> TitleIs(string title)
    {
        return driver => driver.Title == title;
    }

    /// <summary>An expectation that the page title contains <paramref name="text"/>.</summary>
    public static Func<IWebDriver, bool> TitleContains(string text)
    {
        return driver => driver.Title?.Contains(text) == true;
    }

    /// <summary>An expectation that an element's visible text contains
    /// <paramref name="text"/>.</summary>
    public static Func<IWebDriver, bool> TextToBePresentInElementLocated(By locator, string text)
    {
        return driver =>
        {
            IWebElement element = driver.FindElement(locator);
            return element.Text?.Contains(text) == true;
        };
    }
}
