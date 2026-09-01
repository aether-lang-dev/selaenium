package org.openqa.selenium;

/**
 * Base for all remote-end errors, carrying the engine's stable W3C error code
 * (0 = success, -1 = transport failure). Subtypes map specific codes to typed
 * exceptions; {@link RemoteWebDriver#classify} does the dispatch. Named to match
 * Selenium 4.x ({@code org.openqa.selenium.WebDriverException}).
 */
public class WebDriverException extends RuntimeException {
    private final int code;

    public WebDriverException(String message, int code) {
        super(message);
        this.code = code;
    }

    public int code() {
        return code;
    }
}
