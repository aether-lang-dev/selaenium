package org.openqa.selenium;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * A shadow root as a {@link SearchContext} (mainstream
 * {@code org.openqa.selenium.ShadowRoot}). Only {@link #findElement(By)} /
 * {@link #findElements(By)} are supported, scoped inside the shadow tree: they
 * issue the shadow-scoped commands ({@code findElementFromShadowRoot} /
 * {@code findElementsFromShadowRoot}), passing this shadow root's id as the
 * {@code :id} path parameter — exactly like {@link RemoteWebElement}'s
 * element-scoped finders, just with the shadow command names and the shadow id.
 */
public final class ShadowRoot implements SearchContext {

    /** The W3C shadow-root reference key, distinct from the element key. */
    static final String W3C_SHADOW_KEY = "shadow-6066-11e4-a52e-4f735466cecf";

    private final RemoteWebDriver driver;
    private final String id;

    ShadowRoot(RemoteWebDriver driver, String id) {
        this.driver = driver;
        this.id = id;
    }

    public String id() {
        return id;
    }

    @Override
    @SuppressWarnings("unchecked")
    public WebElement findElement(By by) {
        Map<String, Object> params = new HashMap<>(driver.decodeBy(by.strategy(), by.value()));
        params.put("id", id);
        Map<String, Object> result =
                (Map<String, Object>) driver.execute("findElementFromShadowRoot", params);
        return new RemoteWebElement(driver, (String) result.get(RemoteWebDriver.W3C_ELEMENT_KEY));
    }

    @Override
    @SuppressWarnings("unchecked")
    public List<WebElement> findElements(By by) {
        Map<String, Object> params = new HashMap<>(driver.decodeBy(by.strategy(), by.value()));
        params.put("id", id);
        List<Object> result = (List<Object>) driver.execute("findElementsFromShadowRoot", params);
        return result.stream()
                .map(e -> (WebElement) new RemoteWebElement(driver, (String) ((Map<String, Object>) e).get(RemoteWebDriver.W3C_ELEMENT_KEY)))
                .toList();
    }

    @Override
    public boolean equals(Object o) {
        return (o instanceof ShadowRoot other) && other.id.equals(this.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }

    @Override
    public String toString() {
        return "ShadowRoot[id=" + id + "]";
    }
}
