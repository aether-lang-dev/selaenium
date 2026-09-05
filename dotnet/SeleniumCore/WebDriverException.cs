using System;

namespace OpenQA.Selenium;

/// <summary>
/// Base for all remote-end errors, carrying the engine's stable W3C error code
/// (0 = success, -1 = transport failure). <see cref="RemoteWebDriver.Classify"/>
/// maps codes to the typed subtypes below. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.WebDriverException</c> naming.
///
/// The mainstream constructor shape is <c>(string)</c> / <c>(string, Exception)</c>,
/// so a script that writes <c>throw new NoSuchElementException("msg")</c> compiles
/// unchanged. The engine seam keeps the <c>(string, int)</c> constructor to carry
/// the W3C error code; when a message-only constructor is used, <see cref="Code"/>
/// defaults to 0. The classes are unsealed so callers may subclass them.
/// </summary>
public class WebDriverException : Exception
{
    public int Code { get; }

    public WebDriverException() : base() { }

    public WebDriverException(string? message) : base(message) { }

    public WebDriverException(string? message, Exception? innerException) : base(message, innerException) { }

    /// <summary>The engine seam: carry the W3C error <paramref name="code"/> alongside
    /// the message (used by <see cref="RemoteWebDriver.Classify"/>).</summary>
    public WebDriverException(string? message, int code) : base(message)
    {
        Code = code;
    }
}

public class NoSuchElementException : NotFoundException
{
    public NoSuchElementException() : base() { }
    public NoSuchElementException(string? message) : base(message) { }
    public NoSuchElementException(string? message, Exception? innerException) : base(message, innerException) { }
    public NoSuchElementException(string? message, int code) : base(message, code) { }
}

public class StaleElementReferenceException : WebDriverException
{
    public StaleElementReferenceException() : base() { }
    public StaleElementReferenceException(string? message) : base(message) { }
    public StaleElementReferenceException(string? message, Exception? innerException) : base(message, innerException) { }
    public StaleElementReferenceException(string? message, int code) : base(message, code) { }
}

public class ElementClickInterceptedException : WebDriverException
{
    public ElementClickInterceptedException() : base() { }
    public ElementClickInterceptedException(string? message) : base(message) { }
    public ElementClickInterceptedException(string? message, Exception? innerException) : base(message, innerException) { }
    public ElementClickInterceptedException(string? message, int code) : base(message, code) { }
}

public class ElementNotInteractableException : InvalidElementStateException
{
    public ElementNotInteractableException() : base() { }
    public ElementNotInteractableException(string? message) : base(message) { }
    public ElementNotInteractableException(string? message, Exception? innerException) : base(message, innerException) { }
    public ElementNotInteractableException(string? message, int code) : base(message, code) { }
}

public class InvalidSelectorException : WebDriverException
{
    public InvalidSelectorException() : base() { }
    public InvalidSelectorException(string? message) : base(message) { }
    public InvalidSelectorException(string? message, Exception? innerException) : base(message, innerException) { }
    public InvalidSelectorException(string? message, int code) : base(message, code) { }
}

public class TimeoutException : WebDriverException
{
    public TimeoutException() : base() { }
    public TimeoutException(string? message) : base(message) { }
    public TimeoutException(string? message, Exception? innerException) : base(message, innerException) { }
    public TimeoutException(string? message, int code) : base(message, code) { }
}

public class JavaScriptException : WebDriverException
{
    public JavaScriptException() : base() { }
    public JavaScriptException(string? message) : base(message) { }
    public JavaScriptException(string? message, Exception? innerException) : base(message, innerException) { }
    public JavaScriptException(string? message, int code) : base(message, code) { }
}

public class UnknownCommandException : WebDriverException
{
    public UnknownCommandException() : base() { }
    public UnknownCommandException(string? message) : base(message) { }
    public UnknownCommandException(string? message, Exception? innerException) : base(message, innerException) { }
    public UnknownCommandException(string? message, int code) : base(message, code) { }
}

/// <summary>
/// Raised when a required element or window is not present. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.NotFoundException</c>; it is the family the convenience tier's
/// <see cref="Support.UI.WebDriverWait"/> ignores while polling. It is the base of
/// <see cref="NoSuchElementException"/>, <see cref="NoSuchWindowException"/>,
/// <see cref="NoSuchFrameException"/>, <see cref="NoAlertPresentException"/> and
/// <see cref="NoSuchShadowRootException"/>, matching upstream's hierarchy.
/// </summary>
public class NotFoundException : WebDriverException
{
    public NotFoundException() : base() { }
    public NotFoundException(string? message) : base(message) { }
    public NotFoundException(string? message, Exception? innerException) : base(message, innerException) { }
    public NotFoundException(string? message, int code) : base(message, code) { }
}

/// <summary>Raised when a target window handle is not present (W3C "no such window").</summary>
public class NoSuchWindowException : NotFoundException
{
    public NoSuchWindowException() : base() { }
    public NoSuchWindowException(string? message) : base(message) { }
    public NoSuchWindowException(string? message, Exception? innerException) : base(message, innerException) { }
    public NoSuchWindowException(string? message, int code) : base(message, code) { }
}

/// <summary>Raised when a target frame is not present (W3C "no such frame").</summary>
public class NoSuchFrameException : NotFoundException
{
    public NoSuchFrameException() : base() { }
    public NoSuchFrameException(string? message) : base(message) { }
    public NoSuchFrameException(string? message, Exception? innerException) : base(message, innerException) { }
    public NoSuchFrameException(string? message, int code) : base(message, code) { }
}

/// <summary>Raised when switching to an alert but none is present (W3C "no such alert").</summary>
public class NoAlertPresentException : NotFoundException
{
    public NoAlertPresentException() : base() { }
    public NoAlertPresentException(string? message) : base(message) { }
    public NoAlertPresentException(string? message, Exception? innerException) : base(message, innerException) { }
    public NoAlertPresentException(string? message, int code) : base(message, code) { }
}

/// <summary>Raised when an element has no shadow root (W3C "no such shadow root").</summary>
public class NoSuchShadowRootException : NotFoundException
{
    public NoSuchShadowRootException() : base() { }
    public NoSuchShadowRootException(string? message) : base(message) { }
    public NoSuchShadowRootException(string? message, Exception? innerException) : base(message, innerException) { }
    public NoSuchShadowRootException(string? message, int code) : base(message, code) { }
}

/// <summary>Raised when a command needs an element in a different state (W3C
/// "invalid element state"). Base of <see cref="ElementNotInteractableException"/>,
/// matching upstream.</summary>
public class InvalidElementStateException : WebDriverException
{
    public InvalidElementStateException() : base() { }
    public InvalidElementStateException(string? message) : base(message) { }
    public InvalidElementStateException(string? message, Exception? innerException) : base(message, innerException) { }
    public InvalidElementStateException(string? message, int code) : base(message, code) { }
}

/// <summary>Raised when an open modal blocks a command (W3C "unexpected alert open").</summary>
public class UnexpectedAlertOpenException : WebDriverException
{
    public UnexpectedAlertOpenException() : base() { }
    public UnexpectedAlertOpenException(string? message) : base(message) { }
    public UnexpectedAlertOpenException(string? message, Exception? innerException) : base(message, innerException) { }
    public UnexpectedAlertOpenException(string? message, int code) : base(message, code) { }

    /// <summary>The text of the alert that was open, if the remote end reported it.</summary>
    public string? AlertText { get; init; }
}

/// <summary>
/// Raised by <see cref="Support.UI.WebDriverWait"/> when a condition does not become
/// truthy before the timeout. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.WebDriverTimeoutException</c>.
/// </summary>
public class WebDriverTimeoutException : TimeoutException
{
    public WebDriverTimeoutException() : base() { }

    public WebDriverTimeoutException(string? message) : base(message, 21) { }

    /// <summary>The last exception thrown by the polled condition, if any (the wait
    /// swallows ignored exceptions, then attaches the final one here on timeout).</summary>
    public WebDriverTimeoutException(string? message, Exception? lastException)
        : base(message, 21)
    {
        LastException = lastException;
    }

    public Exception? LastException { get; }
}
