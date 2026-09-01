package org.openqa.selenium;

/** Selenium 4.x {@code ElementClickInterceptedException}. */
public class ElementClickInterceptedException extends WebDriverException {
    public ElementClickInterceptedException(String message, int code) {
        super(message, code);
    }
}
