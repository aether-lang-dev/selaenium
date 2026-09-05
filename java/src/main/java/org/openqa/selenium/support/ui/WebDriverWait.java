package org.openqa.selenium.support.ui;

import java.time.Duration;
import java.util.function.Function;
import org.openqa.selenium.NoSuchElementException;
import org.openqa.selenium.TimeoutException;
import org.openqa.selenium.WebDriver;

/**
 * Explicit waits. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.support.ui.WebDriverWait}:
 * {@code new WebDriverWait(driver, Duration.ofSeconds(10)).until(condition)} polls
 * {@code condition.apply(driver)} until it returns a truthy value (or raises), and
 * {@link #until(Function)} returns as soon as the condition holds — unlike a fixed
 * sleep. The poll loop lives in the binding (the engine issues single commands and
 * holds no thread), exactly as the reference {@code aether/webdriver.ae} waits do.
 */
public class WebDriverWait {

    /** Default poll cadence between condition checks (mainstream default). */
    public static final Duration DEFAULT_SLEEP_TIMEOUT = Duration.ofMillis(500);

    private final WebDriver driver;
    private final Duration timeout;
    private final Duration interval;

    public WebDriverWait(WebDriver driver, Duration timeout) {
        this(driver, timeout, DEFAULT_SLEEP_TIMEOUT);
    }

    public WebDriverWait(WebDriver driver, Duration timeout, Duration sleep) {
        this.driver = driver;
        this.timeout = timeout;
        this.interval = sleep.isZero() || sleep.isNegative() ? DEFAULT_SLEEP_TIMEOUT : sleep;
    }

    /** Convenience overload taking a timeout in seconds. */
    public WebDriverWait(WebDriver driver, long timeoutSeconds) {
        this(driver, Duration.ofSeconds(timeoutSeconds));
    }

    /**
     * Poll {@code condition.apply(driver)} until it returns something truthy
     * (non-null, and not {@link Boolean#FALSE}); return it. Raise
     * {@link TimeoutException} if the deadline passes first. A thrown
     * {@link NoSuchElementException} during polling is swallowed and retried.
     */
    public <T> T until(Function<? super WebDriver, T> condition) {
        long end = System.nanoTime() + timeout.toNanos();
        Throwable last = null;
        while (true) {
            try {
                T value = condition.apply(driver);
                if (value != null && !Boolean.FALSE.equals(value)) {
                    return value;
                }
            } catch (NoSuchElementException e) {
                last = e;
            }
            if (System.nanoTime() > end) {
                break;
            }
            sleep();
        }
        throw new TimeoutException(
                "waited " + timeout.toSeconds() + "s for condition"
                        + (last == null ? "" : " (last error: " + last + ")"),
                21);
    }

    /**
     * Poll until {@code condition.apply(driver)} returns falsy (or raises a
     * swallowed {@link NoSuchElementException}); return {@code true}. Raise
     * {@link TimeoutException} on timeout.
     */
    public boolean until_not(Function<? super WebDriver, ?> condition) {
        return untilNot(condition);
    }

    /** Mainstream {@code until(not(condition))} equivalent. */
    public boolean untilNot(Function<? super WebDriver, ?> condition) {
        long end = System.nanoTime() + timeout.toNanos();
        while (true) {
            try {
                Object value = condition.apply(driver);
                if (value == null || Boolean.FALSE.equals(value)) {
                    return true;
                }
            } catch (NoSuchElementException e) {
                return true;
            }
            if (System.nanoTime() > end) {
                break;
            }
            sleep();
        }
        throw new TimeoutException("waited " + timeout.toSeconds() + "s for condition to stop", 21);
    }

    private void sleep() {
        try {
            Thread.sleep(interval.toMillis());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
