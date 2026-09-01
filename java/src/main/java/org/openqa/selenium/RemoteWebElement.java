package org.openqa.selenium;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A remote element handle (the concrete {@link WebElement}). Methods issue
 * element-scoped commands, passing this element's id as the {@code :id} path
 * parameter (the engine separates path params from the body).
 */
public final class RemoteWebElement implements WebElement {
    private final RemoteWebDriver driver;
    private final String id;

    RemoteWebElement(RemoteWebDriver driver, String id) {
        this.driver = driver;
        this.id = id;
    }

    @Override
    public String id() {
        return id;
    }

    private Object exec(String command, Map<String, Object> params) {
        Map<String, Object> p = params == null ? new HashMap<>() : new HashMap<>(params);
        p.put("id", id);
        return driver.execute(command, p);
    }

    @Override
    public void click() {
        exec("clickElement", null);
    }

    @Override
    public void clear() {
        exec("clearElement", null);
    }

    @Override
    public void sendKeys(String text) {
        List<Object> chars = text.chars().mapToObj(c -> String.valueOf((char) c)).map(Object.class::cast).toList();
        exec("sendKeysToElement", Map.of("text", text, "value", chars));
    }

    @Override
    public String getText() {
        return (String) exec("getElementText", null);
    }

    @Override
    public String getTagName() {
        return (String) exec("getElementTagName", null);
    }

    /**
     * Whether the element is shown (the isDisplayed atom, run in-page by the
     * engine — the visibility algorithm, not a naive style check).
     */
    @Override
    public boolean isDisplayed() {
        return Boolean.TRUE.equals(driver.atomResult(Native.isDisplayed(driver.handle(), id)));
    }

    /**
     * The classic getAttribute(name): property-or-attribute (boolean attrs, live
     * properties like value/checked), via the shared engine atom. Use
     * {@link #getDomAttribute(String)} for the raw W3C DOM attribute.
     */
    @Override
    public Object getAttribute(String name) {
        return driver.atomResult(Native.getAttribute(driver.handle(), id, name));
    }

    /** The literal DOM attribute (W3C getDomAttribute), no property fallback. */
    @Override
    public Object getDomAttribute(String name) {
        return exec("getDomAttribute", Map.of("name", name));
    }

    @Override
    public Object getProperty(String name) {
        return exec("getElementProperty", Map.of("name", name));
    }

    @Override
    public boolean isEnabled() {
        return Boolean.TRUE.equals(exec("isElementEnabled", null));
    }

    @Override
    public boolean isSelected() {
        return Boolean.TRUE.equals(exec("isElementSelected", null));
    }

    @Override
    @SuppressWarnings("unchecked")
    public Map<String, Object> rect() {
        return (Map<String, Object>) exec("getElementRect", null);
    }

    // ---- element-scoped finders (search within this element's subtree) ----
    @Override
    @SuppressWarnings("unchecked")
    public WebElement findElement(By by) {
        Map<String, Object> locator = driver.decodeBy(by.strategy(), by.value());
        Map<String, Object> params = new HashMap<>(locator);
        params.put("id", id);
        Map<String, Object> result = (Map<String, Object>) driver.execute("findChildElement", params);
        return new RemoteWebElement(driver, (String) result.get(RemoteWebDriver.W3C_ELEMENT_KEY));
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<WebElement> findElements(By by) {
        Map<String, Object> locator = driver.decodeBy(by.strategy(), by.value());
        Map<String, Object> params = new HashMap<>(locator);
        params.put("id", id);
        List<Object> result = (List<Object>) driver.execute("findChildElements", params);
        return result.stream()
                .map(e -> (WebElement) new RemoteWebElement(driver, (String) ((Map<String, Object>) e).get(RemoteWebDriver.W3C_ELEMENT_KEY)))
                .toList();
    }
}
