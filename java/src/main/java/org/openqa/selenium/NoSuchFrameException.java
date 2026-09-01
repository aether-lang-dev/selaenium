package org.openqa.selenium;

/** Selenium 4.x {@code NoSuchFrameException}. */
public class NoSuchFrameException extends WebDriverException {
    public NoSuchFrameException(String message, int code) {
        super(message, code);
    }
}
