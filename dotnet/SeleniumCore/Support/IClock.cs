using System;

namespace OpenQA.Selenium.Support.UI;

/// <summary>
/// Time handling for timeouts. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.IClock</c> so a test can inject a fake clock and
/// drive <see cref="DefaultWait{T}"/> without sleeping wall-clock time.
/// </summary>
public interface IClock
{
    /// <summary>The current date and time.</summary>
    DateTime Now { get; }

    /// <summary>The <see cref="DateTime"/> at <paramref name="delay"/> in the future.</summary>
    DateTime LaterBy(TimeSpan delay);

    /// <summary>True if "now" is still before <paramref name="otherDateTime"/>.</summary>
    bool IsNowBefore(DateTime otherDateTime);
}

/// <summary>
/// The default <see cref="IClock"/> backed by the system clock. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.SystemClock</c>.
/// </summary>
public class SystemClock : IClock
{
    /// <summary>A shared instance of the <see cref="SystemClock"/>.</summary>
    public static SystemClock Instance { get; } = new();

    public DateTime Now => DateTime.Now;

    public DateTime LaterBy(TimeSpan delay) => DateTime.Now.Add(delay);

    public bool IsNowBefore(DateTime otherDateTime) => DateTime.Now < otherDateTime;
}
