package org.openqa.selenium;

import java.util.ArrayList;
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

    /**
     * Type into the element. Variadic (mainstream): accepts multiple strings and
     * {@link Keys} constants, joined into one keystroke sequence. W3C expects
     * {@code {"text": full, "value": [chars...]}} — send both for broad driver
     * compatibility.
     */
    @Override
    public void sendKeys(CharSequence... keysToSend) {
        StringBuilder joined = new StringBuilder();
        for (CharSequence cs : keysToSend) {
            joined.append(cs);
        }
        String text = joined.toString();
        List<Object> chars = new ArrayList<>();
        text.codePoints().forEach(cp -> chars.add(new String(Character.toChars(cp))));
        exec("sendKeysToElement", Map.of("text", text, "value", chars));
    }

    /**
     * Submit the form containing this element (mainstream: walks up to the
     * enclosing {@code <form>} and dispatches submit, in-page).
     */
    @Override
    public void submit() {
        String script =
                "/* submitForm */var form = arguments[0];\n"
                + "while (form.nodeName != \"FORM\" && form.parentNode) {\n"
                + "  form = form.parentNode;\n"
                + "}\n"
                + "if (!form) { throw Error('Unable to find containing form element'); }\n"
                + "if (!form.ownerDocument) { throw Error('Unable to find owning document'); }\n"
                + "var e = form.ownerDocument.createEvent('Event');\n"
                + "e.initEvent('submit', true, true);\n"
                + "if (form.dispatchEvent(e)) { HTMLFormElement.prototype.submit.call(form) }\n";
        try {
            driver.executeScript(script, this);
        } catch (JavascriptException e) {
            throw new WebDriverException(
                    "To submit an element, it must be nested inside a form element", 0);
        }
    }

    @Override
    public String getText() {
        return (String) exec("getElementText", null);
    }

    @Override
    public String getTagName() {
        return (String) exec("getElementTagName", null);
    }

    @Override
    public String getAriaRole() {
        return (String) exec("getAriaRole", null);
    }

    @Override
    public String getAccessibleName() {
        return (String) exec("getAccessibleName", null);
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
    public String getAttribute(String name) {
        return asString(driver.atomResult(Native.getAttribute(driver.handle(), id, name)));
    }

    /** The literal DOM attribute (W3C getDomAttribute), no property fallback. */
    @Override
    public String getDomAttribute(String name) {
        return asString(exec("getDomAttribute", Map.of("name", name)));
    }

    @Override
    public String getDomProperty(String name) {
        return asString(exec("getElementProperty", Map.of("name", name)));
    }

    @Override
    public Object getProperty(String name) {
        return exec("getElementProperty", Map.of("name", name));
    }

    @Override
    public String getCssValue(String propertyName) {
        return asString(exec("getElementValueOfCssProperty", Map.of("propertyName", propertyName)));
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

    @Override
    public Rectangle getRect() {
        return RemoteWebDriver.toRectangle(rect());
    }

    @Override
    public Point getLocation() {
        Map<String, Object> r = rect();
        return new Point(RemoteWebDriver.intOf(r.get("x")), RemoteWebDriver.intOf(r.get("y")));
    }

    @Override
    public Dimension getSize() {
        Map<String, Object> r = rect();
        return new Dimension(
                RemoteWebDriver.intOf(r.get("width")), RemoteWebDriver.intOf(r.get("height")));
    }

    /** Per-element screenshot (upstream TakesScreenshot on an element). */
    @Override
    public <X> X getScreenshotAs(OutputType<X> target) throws WebDriverException {
        String base64 = (String) exec("takeElementScreenshot", null);
        return target.convertFromBase64Png(base64);
    }

    /** The element's shadow root as a {@link SearchContext} (upstream). */
    @Override
    @SuppressWarnings("unchecked")
    public SearchContext getShadowRoot() {
        Object result = exec("getElementShadowRoot", null);
        if (result instanceof Map<?, ?> m) {
            Object ref = ((Map<String, Object>) m).get("shadow-6066-11e4-a52e-4f735466cecf");
            if (ref == null) {
                ref = ((Map<String, Object>) m).get(RemoteWebDriver.W3C_ELEMENT_KEY);
            }
            return new RemoteWebElement(driver, String.valueOf(ref));
        }
        throw new WebDriverException("element has no shadow root", 0);
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

    private static String asString(Object v) {
        return v == null ? null : (v instanceof String s ? s : String.valueOf(v));
    }

    @Override
    public boolean equals(Object o) {
        return (o instanceof RemoteWebElement other) && other.id.equals(this.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }

    @Override
    public String toString() {
        return "RemoteWebElement[id=" + id + "]";
    }
}
