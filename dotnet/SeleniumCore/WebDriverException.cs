using System;

namespace OpenQA.Selenium;

/// <summary>
/// Base for all remote-end errors, carrying the engine's stable W3C error code
/// (0 = success, -1 = transport failure). <see cref="RemoteWebDriver.Classify"/>
/// maps codes to the typed subtypes below. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.WebDriverException</c> naming.
/// </summary>
public class WebDriverException : Exception
{
    public int Code { get; }

    public WebDriverException(string message, int code) : base(message)
    {
        Code = code;
    }
}

public sealed class NoSuchElementException : WebDriverException
{
    public NoSuchElementException(string m, int c) : base(m, c) { }
}

public sealed class StaleElementReferenceException : WebDriverException
{
    public StaleElementReferenceException(string m, int c) : base(m, c) { }
}

public sealed class ElementClickInterceptedException : WebDriverException
{
    public ElementClickInterceptedException(string m, int c) : base(m, c) { }
}

public sealed class ElementNotInteractableException : WebDriverException
{
    public ElementNotInteractableException(string m, int c) : base(m, c) { }
}

public sealed class InvalidSelectorException : WebDriverException
{
    public InvalidSelectorException(string m, int c) : base(m, c) { }
}

public sealed class TimeoutException : WebDriverException
{
    public TimeoutException(string m, int c) : base(m, c) { }
}

public sealed class JavaScriptException : WebDriverException
{
    public JavaScriptException(string m, int c) : base(m, c) { }
}

public sealed class UnknownCommandException : WebDriverException
{
    public UnknownCommandException(string m, int c) : base(m, c) { }
}

/// <summary>
/// Raised when a required element or window is not present. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.NotFoundException</c>; it is the family the convenience tier's
/// <see cref="Support.UI.WebDriverWait"/> ignores while polling. (The engine's own
/// "no such element" still surfaces as the sealed <see cref="NoSuchElementException"/>;
/// the wait ignores both.)
/// </summary>
public class NotFoundException : WebDriverException
{
    public NotFoundException(string message) : base(message, 0) { }

    public NotFoundException(string message, int code) : base(message, code) { }
}

/// <summary>
/// Raised by <see cref="Support.UI.WebDriverWait"/> when a condition does not become
/// truthy before the timeout. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.WebDriverTimeoutException</c>.
/// </summary>
public sealed class WebDriverTimeoutException : WebDriverException
{
    public WebDriverTimeoutException(string message) : base(message, 21) { }

    /// <summary>The last exception thrown by the polled condition, if any (the wait
    /// swallows ignored exceptions, then attaches the final one here on timeout).</summary>
    public WebDriverTimeoutException(string message, System.Exception? lastException)
        : base(message, 21)
    {
        LastException = lastException;
    }

    public System.Exception? LastException { get; }
}
