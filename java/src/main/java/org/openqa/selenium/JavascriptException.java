package org.openqa.selenium;

/** Selenium 4.x {@code JavascriptException}. */
public class JavascriptException extends WebDriverException {
    public JavascriptException(String message, int code) {
        super(message, code);
    }
}
