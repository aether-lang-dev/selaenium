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

    // ---- upstream-shaped constructors (code defaults to 0) ----
    // ADDED alongside the (String, int) form so an unmodified mainstream program
    // that constructs these — and the NotFoundException/NoAlertPresentException
    // subclasses that chain super(message) — compile unchanged.

    public WebDriverException() {
        this((String) null, 0);
    }

    public WebDriverException(String message) {
        this(message, 0);
    }

    public WebDriverException(Throwable cause) {
        super(cause);
        this.code = 0;
    }

    public WebDriverException(String message, Throwable cause) {
        super(message, cause);
        this.code = 0;
    }

    public int code() {
        return code;
    }
}
