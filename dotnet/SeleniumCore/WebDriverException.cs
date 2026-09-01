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
