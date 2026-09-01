package org.openqa.selenium;

/**
 * A locator: a (strategy, value) pair produced by one of the static factory
 * methods and passed to {@code findElement(By)} / {@code findElements(By)}.
 * Mirrors Selenium 4.x's {@code By.id("x")} grammar. The strategy strings are
 * exactly what the shared engine's {@code by_locator} accepts; className uses
 * the W3C-canonical {@code "class name"} form.
 */
public final class By {

    private final String strategy;
    private final String value;

    private By(String strategy, String value) {
        this.strategy = strategy;
        this.value = value;
    }

    /** The engine strategy string (e.g. {@code "css selector"}). */
    String strategy() {
        return strategy;
    }

    /** The raw selector value. */
    String value() {
        return value;
    }

    public static By id(String value) {
        return new By("id", value);
    }

    public static By name(String value) {
        return new By("name", value);
    }

    public static By className(String value) {
        return new By("class name", value);
    }

    public static By cssSelector(String value) {
        return new By("css selector", value);
    }

    public static By tagName(String value) {
        return new By("tag name", value);
    }

    public static By linkText(String value) {
        return new By("link text", value);
    }

    public static By partialLinkText(String value) {
        return new By("partial link text", value);
    }

    public static By xpath(String value) {
        return new By("xpath", value);
    }

    @Override
    public String toString() {
        return "By." + strategy + ": " + value;
    }
}
