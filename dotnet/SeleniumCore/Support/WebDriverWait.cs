using System;

namespace OpenQA.Selenium.Support.UI;

/// <summary>
/// Waits for a condition against an <see cref="IWebDriver"/>. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.WebDriverWait</c>:
/// <code>
/// IWait&lt;IWebDriver&gt; wait = new WebDriverWait(driver, TimeSpan.FromSeconds(3));
/// IWebElement el = wait.Until(d =&gt; d.FindElement(By.Name("q")));
/// </code>
/// Not-found exceptions are ignored while polling (this binding surfaces both the
/// engine's sealed <see cref="NoSuchElementException"/> and the
/// <see cref="NotFoundException"/> family), so a <c>FindElement</c> condition retries
/// until the element appears or the timeout fires.
/// </summary>
public class WebDriverWait : DefaultWait<IWebDriver>
{
    /// <summary>Wait up to <paramref name="timeout"/>, polling every 500 ms.</summary>
    public WebDriverWait(IWebDriver driver, TimeSpan timeout)
        : this(SystemClock.Instance, driver, timeout, DefaultSleepTimeout)
    {
    }

    /// <summary>Wait with an explicit clock and polling interval (a fake clock in a
    /// unit test drives the loop without real sleeping).</summary>
    public WebDriverWait(IClock clock, IWebDriver driver, TimeSpan timeout, TimeSpan sleepInterval)
        : base(driver, clock)
    {
        this.Timeout = timeout;
        this.PollingInterval = sleepInterval;
        this.IgnoreExceptionTypes(typeof(NotFoundException), typeof(NoSuchElementException));
    }

    private static TimeSpan DefaultSleepTimeout => TimeSpan.FromMilliseconds(500);
}
