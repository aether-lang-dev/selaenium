package org.openqa.selenium;

/** Selenium 4.x {@code InvalidSelectorException}. */
public class InvalidSelectorException extends WebDriverException {
    public InvalidSelectorException(String message, int code) {
        super(message, code);
    }
}
