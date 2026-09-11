package org.openqa.selenium;

/**
 * The element has no shadow root (W3C {@code no such shadow root}, code 19).
 * Mirrors Selenium 4.x's {@code org.openqa.selenium.NoSuchShadowRootException}.
 */
public class NoSuchShadowRootException extends NotFoundException {

    public NoSuchShadowRootException(String message) {
        super(message, 19);
    }

    public NoSuchShadowRootException(String message, int code) {
        super(message, code);
    }
}
