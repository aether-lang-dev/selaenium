package org.openqa.selenium;

/** Selenium 4.x {@code SessionNotCreatedException}. */
public class SessionNotCreatedException extends WebDriverException {
    public SessionNotCreatedException(String message, int code) {
        super(message, code);
    }
}
