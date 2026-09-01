package org.openqa.selenium;

/** Selenium 4.x {@code NoSuchWindowException}. */
public class NoSuchWindowException extends WebDriverException {
    public NoSuchWindowException(String message, int code) {
        super(message, code);
    }
}
