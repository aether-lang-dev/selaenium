package org.seleniumhq.aether;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A remote element handle. Methods issue element-scoped commands, passing this
 * element's id as the {@code :id} path parameter (the engine separates path
 * params from the body).
 */
public final class WebElement {
    private final WebDriver driver;
    private final String id;

    WebElement(WebDriver driver, String id) {
        this.driver = driver;
        this.id = id;
    }

    public String id() {
        return id;
    }

    private Object exec(String command, Map<String, Object> params) {
        Map<String, Object> p = params == null ? new HashMap<>() : new HashMap<>(params);
        p.put("id", id);
        return driver.execute(command, p);
    }

    public void click() {
        exec("clickElement", null);
    }

    public void clear() {
        exec("clearElement", null);
    }

    public void sendKeys(String text) {
        List<Object> chars = text.chars().mapToObj(c -> String.valueOf((char) c)).map(Object.class::cast).toList();
        exec("sendKeysToElement", Map.of("text", text, "value", chars));
    }

    public String text() {
        return (String) exec("getElementText", null);
    }

    public String tagName() {
        return (String) exec("getElementTagName", null);
    }

    public Object getAttribute(String name) {
        return exec("getDomAttribute", Map.of("name", name));
    }

    public Object getProperty(String name) {
        return exec("getElementProperty", Map.of("name", name));
    }

    public boolean isEnabled() {
        return Boolean.TRUE.equals(exec("isElementEnabled", null));
    }

    public boolean isSelected() {
        return Boolean.TRUE.equals(exec("isElementSelected", null));
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> rect() {
        return (Map<String, Object>) exec("getElementRect", null);
    }
}
