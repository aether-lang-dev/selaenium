package org.openqa.selenium;

/** Selenium 4.x {@code TimeoutException}. */
public class TimeoutException extends WebDriverException {
    public TimeoutException(String message, int code) {
        super(message, code);
    }
}
