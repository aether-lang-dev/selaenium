package org.openqa.selenium;

/** Selenium 4.x {@code UnknownCommandException}. */
public class UnknownCommandException extends WebDriverException {
    public UnknownCommandException(String message, int code) {
        super(message, code);
    }
}
