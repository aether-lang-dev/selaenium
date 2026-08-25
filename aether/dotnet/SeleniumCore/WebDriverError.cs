using System;

namespace SeleniumCore;

/// <summary>
/// Base for all remote-end errors, carrying the engine's stable W3C error code
/// (0 = success, -1 = transport failure). <see cref="WebDriver.Classify"/> maps
/// codes to the typed subtypes below.
/// </summary>
public class WebDriverError : Exception
{
    public int Code { get; }

    public WebDriverError(string message, int code) : base(message)
    {
        Code = code;
    }
}

public sealed class NoSuchElementError : WebDriverError
{
    public NoSuchElementError(string m, int c) : base(m, c) { }
}

public sealed class StaleElementReferenceError : WebDriverError
{
    public StaleElementReferenceError(string m, int c) : base(m, c) { }
}

public sealed class ElementClickInterceptedError : WebDriverError
{
    public ElementClickInterceptedError(string m, int c) : base(m, c) { }
}

public sealed class ElementNotInteractableError : WebDriverError
{
    public ElementNotInteractableError(string m, int c) : base(m, c) { }
}

public sealed class InvalidSelectorError : WebDriverError
{
    public InvalidSelectorError(string m, int c) : base(m, c) { }
}

public sealed class TimeoutError : WebDriverError
{
    public TimeoutError(string m, int c) : base(m, c) { }
}

public sealed class JavascriptError : WebDriverError
{
    public JavascriptError(string m, int c) : base(m, c) { }
}

public sealed class UnknownCommandError : WebDriverError
{
    public UnknownCommandError(string m, int c) : base(m, c) { }
}
