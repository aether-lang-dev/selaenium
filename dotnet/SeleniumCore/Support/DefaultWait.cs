using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Linq;
using System.Threading;

namespace OpenQA.Selenium.Support.UI;

/// <summary>
/// Waits for an arbitrary condition. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.IWait&lt;T&gt;</c>.
/// </summary>
/// <typeparam name="T">The type the condition is applied to (an
/// <see cref="IWebDriver"/> for a <see cref="WebDriverWait"/>).</typeparam>
public interface IWait<T>
{
    /// <summary>How long to wait for the condition to become true.</summary>
    TimeSpan Timeout { get; set; }

    /// <summary>How often the condition is evaluated.</summary>
    TimeSpan PollingInterval { get; set; }

    /// <summary>The message appended to the timeout exception.</summary>
    string Message { get; set; }

    /// <summary>Exception types to swallow (and retry) while polling.</summary>
    void IgnoreExceptionTypes(params Type[] exceptionTypes);

    /// <summary>Poll <paramref name="condition"/> until it returns a non-null (or,
    /// for a bool, true) value, or the timeout elapses.</summary>
    [return: NotNull]
    TResult Until<TResult>(Func<T, TResult?> condition);
}

/// <summary>
/// The configurable <see cref="IWait{T}"/>. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Support.UI.DefaultWait&lt;T&gt;</c>: the poll loop lives entirely
/// here in the binding (the engine holds no thread), sleeping
/// <see cref="PollingInterval"/> between attempts and throwing
/// <see cref="WebDriverTimeoutException"/> at <see cref="Timeout"/>.
/// </summary>
/// <typeparam name="T">The type the condition is applied to.</typeparam>
public class DefaultWait<T> : IWait<T>
{
    private readonly T input;
    private readonly IClock clock;
    private readonly List<Type> ignoredExceptions = new List<Type>();

    /// <summary>Wait over <paramref name="input"/> using the system clock.</summary>
    public DefaultWait(T input)
        : this(input, SystemClock.Instance)
    {
    }

    /// <summary>Wait over <paramref name="input"/> using an explicit clock (inject a
    /// fake clock in a unit test).</summary>
    public DefaultWait(T input, IClock clock)
    {
        this.input = input ?? throw new ArgumentNullException(nameof(input), "input cannot be null");
        this.clock = clock ?? throw new ArgumentNullException(nameof(clock), "clock cannot be null");
    }

    public TimeSpan Timeout { get; set; } = DefaultSleepTimeout;

    public TimeSpan PollingInterval { get; set; } = DefaultSleepTimeout;

    public string Message { get; set; } = string.Empty;

    private static TimeSpan DefaultSleepTimeout => TimeSpan.FromMilliseconds(500);

    public void IgnoreExceptionTypes(params Type[] exceptionTypes)
    {
        if (exceptionTypes == null)
        {
            throw new ArgumentNullException(nameof(exceptionTypes), "exceptionTypes cannot be null");
        }

        foreach (Type exceptionType in exceptionTypes)
        {
            if (!typeof(Exception).IsAssignableFrom(exceptionType))
            {
                throw new ArgumentException("All types to be ignored must derive from System.Exception", nameof(exceptionTypes));
            }
        }

        this.ignoredExceptions.AddRange(exceptionTypes);
    }

    [return: NotNull]
    public virtual TResult Until<TResult>(Func<T, TResult?> condition)
    {
        return Until(condition, CancellationToken.None);
    }

    [return: NotNull]
    public virtual TResult Until<TResult>(Func<T, TResult?> condition, CancellationToken token)
    {
        if (condition == null)
        {
            throw new ArgumentNullException(nameof(condition), "condition cannot be null");
        }

        var resultType = typeof(TResult);
        if ((resultType.IsValueType && resultType != typeof(bool)) || !typeof(object).IsAssignableFrom(resultType))
        {
            throw new ArgumentException($"Can only wait on an object or boolean response, tried to use type: {resultType}", nameof(condition));
        }

        Exception? lastException = null;
        var endTime = this.clock.LaterBy(this.Timeout);
        while (true)
        {
            token.ThrowIfCancellationRequested();

            try
            {
                var result = condition(this.input);
                if (resultType == typeof(bool))
                {
                    if (result is true)
                    {
                        return result;
                    }
                }
                else
                {
                    if (result != null)
                    {
                        return result;
                    }
                }
            }
            catch (Exception ex)
            {
                if (!this.IsIgnoredException(ex))
                {
                    throw;
                }

                lastException = ex;
            }

            // Check the timeout after evaluating the function so a zero-timeout
            // condition still gets one attempt.
            if (!this.clock.IsNowBefore(endTime))
            {
                string timeoutMessage = string.Format(CultureInfo.InvariantCulture, "Timed out after {0} seconds", this.Timeout.TotalSeconds);
                if (!string.IsNullOrEmpty(this.Message))
                {
                    timeoutMessage += ": " + this.Message;
                }

                this.ThrowTimeoutException(timeoutMessage, lastException);
            }

            Thread.Sleep(this.PollingInterval);
        }
    }

    /// <summary>Throw the timeout exception (overridable for a custom exception).</summary>
    protected virtual void ThrowTimeoutException(string exceptionMessage, Exception? lastException)
    {
        throw new WebDriverTimeoutException(exceptionMessage, lastException);
    }

    private bool IsIgnoredException(Exception exception)
    {
        return this.ignoredExceptions.Any(type => type.IsAssignableFrom(exception.GetType()));
    }
}
