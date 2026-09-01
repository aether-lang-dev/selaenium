package org.openqa.selenium;

/** Selenium 4.x {@code NoSuchElementException}. */
public class NoSuchElementException extends WebDriverException {
    public NoSuchElementException(String message, int code) {
        super(message, code);
    }
}
