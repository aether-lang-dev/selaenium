package org.openqa.selenium;

/**
 * The shadow root is no longer attached to the DOM (W3C
 * {@code detached shadow root}, code 2). Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.DetachedShadowRootException}.
 */
public class DetachedShadowRootException extends WebDriverException {

    public DetachedShadowRootException(String message, int code) {
        super(message, code);
    }
}
