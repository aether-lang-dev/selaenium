package org.openqa.selenium;

/** Selenium 4.x {@code StaleElementReferenceException}. */
public class StaleElementReferenceException extends WebDriverException {
    public StaleElementReferenceException(String message, int code) {
        super(message, code);
    }
}
