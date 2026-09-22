package org.openqa.selenium;

/**
 * A locator: a (strategy, value) pair produced by one of the static factory
 * methods and passed to {@code findElement(By)} / {@code findElements(By)}.
 * Mirrors Selenium 4.x's {@code By.id("x")} grammar. The strategy strings are
 * exactly what the shared engine's {@code by_locator} accepts; className uses
 * the W3C-canonical {@code "class name"} form.
 */
public class By {

    private final String strategy;
    private final String value;

    /**
     * Package/subclass constructor. Kept accessible so the relative-locator
     * support ({@code support.locators.RelativeLocator.RelativeBy}) can extend
     * {@code By} and flow through the ordinary {@code findElement(By)} path, as
     * in mainstream Selenium.
     */
    protected By(String strategy, String value) {
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

    // --- desktop / native strategies (WinAppDriver, Appium) ----------------
    // Against a native driver the engine does NOT rewrite id/name/className to
    // CSS: they are the driver's own UIA AutomationId / Name / ClassName, and a
    // native driver has no CSS engine. So the factories above keep working on
    // desktop; these add the strategies that only exist there. Values match
    // Appium's AppiumBy, so a script written against an Appium client reads the
    // same here.

    public static By accessibilityId(String value) {
        return new By("accessibility id", value);
    }

    public static By androidUIAutomator(String value) {
        return new By("androidUIAutomator", value);
    }

    public static By androidViewTag(String value) {
        return new By("androidViewTag", value);
    }

    public static By androidDataMatcher(String value) {
        return new By("androidDataMatcher", value);
    }

    public static By androidViewMatcher(String value) {
        return new By("androidViewMatcher", value);
    }

    public static By iOSPredicate(String value) {
        return new By("iOSPredicateString", value);
    }

    public static By iOSClassChain(String value) {
        return new By("iOSClassChain", value);
    }

    public static By image(String value) {
        return new By("image", value);
    }

    public static By custom(String value) {
        return new By("custom", value);
    }

    /**
     * Find the first element in {@code context} matching this locator (upstream
     * {@code by.findElement(driver)} form). Delegates to
     * {@link SearchContext#findElement(By)}.
     */
    public WebElement findElement(SearchContext context) {
        return context.findElement(this);
    }

    /**
     * Find all elements in {@code context} matching this locator (upstream
     * {@code by.findElements(driver)} form).
     */
    public java.util.List<WebElement> findElements(SearchContext context) {
        return context.findElements(this);
    }

    @Override
    public String toString() {
        return "By." + strategy + ": " + value;
    }

    @Override
    public boolean equals(Object o) {
        return (o instanceof By) && this.toString().equals(o.toString());
    }

    @Override
    public int hashCode() {
        return toString().hashCode();
    }
}
