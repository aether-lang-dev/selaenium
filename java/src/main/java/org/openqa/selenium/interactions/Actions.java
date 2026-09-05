package org.openqa.selenium.interactions;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;

/**
 * Fluent action builder. Mirrors Selenium 4.x's
 * {@code org.openqa.selenium.interactions.Actions}: queue gestures with chained
 * calls, then {@link #perform()}:
 *
 * <pre>{@code
 * new Actions(driver).moveToElement(menu).click(item).perform();
 * }</pre>
 *
 * Each call appends to a W3C actions sequence (a pointer + a key + a wheel
 * virtual device); {@link #perform()} posts the whole sequence in one
 * {@code actions} command through the driver seam — the same wire shape the
 * reference {@code aether/webdriver.ae} action helpers emit.
 */
public class Actions {

    private static final String W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf";

    private final WebDriver driver;
    private final int duration;
    private final List<Map<String, Object>> pointer = new ArrayList<>();
    private final List<Map<String, Object>> key = new ArrayList<>();
    private final List<Map<String, Object>> wheel = new ArrayList<>();

    public Actions(WebDriver driver) {
        this(driver, 250);
    }

    public Actions(WebDriver driver, int duration) {
        this.driver = driver;
        this.duration = duration;
    }

    // ---- pointer gestures ----

    public Actions moveToElement(WebElement element) {
        pointer.add(Map.of(
                "type", "pointerMove", "duration", 100, "x", 0, "y", 0,
                "origin", Map.of(W3C_ELEMENT_KEY, element.id())));
        sync();
        return this;
    }

    public Actions moveByOffset(int xOffset, int yOffset) {
        pointer.add(Map.of(
                "type", "pointerMove", "duration", duration,
                "x", xOffset, "y", yOffset, "origin", "pointer"));
        sync();
        return this;
    }

    public Actions moveToElement(WebElement toElement, int xOffset, int yOffset) {
        pointer.add(Map.of(
                "type", "pointerMove", "duration", duration,
                "x", xOffset, "y", yOffset,
                "origin", Map.of(W3C_ELEMENT_KEY, toElement.id())));
        sync();
        return this;
    }

    public Actions click() {
        pointer.add(Map.of("type", "pointerDown", "button", 0));
        pointer.add(Map.of("type", "pointerUp", "button", 0));
        sync();
        return this;
    }

    public Actions click(WebElement element) {
        moveToElement(element);
        return click();
    }

    public Actions contextClick() {
        pointer.add(Map.of("type", "pointerDown", "button", 2));
        pointer.add(Map.of("type", "pointerUp", "button", 2));
        sync();
        return this;
    }

    public Actions contextClick(WebElement element) {
        moveToElement(element);
        return contextClick();
    }

    public Actions doubleClick() {
        click();
        click();
        return this;
    }

    public Actions doubleClick(WebElement element) {
        moveToElement(element);
        return doubleClick();
    }

    public Actions clickAndHold() {
        pointer.add(Map.of("type", "pointerDown", "button", 0));
        sync();
        return this;
    }

    public Actions clickAndHold(WebElement element) {
        moveToElement(element);
        return clickAndHold();
    }

    public Actions release() {
        pointer.add(Map.of("type", "pointerUp", "button", 0));
        sync();
        return this;
    }

    public Actions release(WebElement element) {
        moveToElement(element);
        return release();
    }

    public Actions dragAndDrop(WebElement source, WebElement target) {
        clickAndHold(source);
        moveToElement(target);
        return release();
    }

    public Actions dragAndDropBy(WebElement source, int xOffset, int yOffset) {
        clickAndHold(source);
        moveByOffset(xOffset, yOffset);
        return release();
    }

    // ---- wheel gestures ----

    public Actions scrollToElement(WebElement element) {
        wheel.add(Map.of(
                "type", "scroll", "x", 0, "y", 0, "deltaX", 0, "deltaY", 0,
                "duration", 0, "origin", Map.of(W3C_ELEMENT_KEY, element.id())));
        sync();
        return this;
    }

    public Actions scrollByAmount(int deltaX, int deltaY) {
        wheel.add(Map.of(
                "type", "scroll", "x", 0, "y", 0,
                "deltaX", deltaX, "deltaY", deltaY,
                "duration", 0, "origin", "viewport"));
        sync();
        return this;
    }

    // ---- key gestures ----

    public Actions keyDown(CharSequence keyToPress) {
        key.add(Map.of("type", "keyDown", "value", String.valueOf(keyToPress)));
        sync();
        return this;
    }

    public Actions keyDown(WebElement element, CharSequence keyToPress) {
        click(element);
        return keyDown(keyToPress);
    }

    public Actions keyUp(CharSequence keyToRelease) {
        key.add(Map.of("type", "keyUp", "value", String.valueOf(keyToRelease)));
        sync();
        return this;
    }

    public Actions keyUp(WebElement element, CharSequence keyToRelease) {
        click(element);
        return keyUp(keyToRelease);
    }

    public Actions sendKeys(CharSequence... keysToSend) {
        for (CharSequence chunk : keysToSend) {
            chunk.toString().codePoints().forEach(cp -> {
                String ch = new String(Character.toChars(cp));
                key.add(Map.of("type", "keyDown", "value", ch));
                key.add(Map.of("type", "keyUp", "value", ch));
            });
        }
        sync();
        return this;
    }

    public Actions sendKeys(WebElement element, CharSequence... keysToSend) {
        click(element);
        return sendKeys(keysToSend);
    }

    public Actions pause(long millis) {
        pointer.add(Map.of("type", "pause", "duration", millis));
        sync();
        return this;
    }

    // ---- terminal ----

    public void perform() {
        List<Object> actions = new ArrayList<>();
        if (pointer.stream().anyMatch(a -> !"pause".equals(a.get("type")))) {
            actions.add(Map.of(
                    "type", "pointer", "id", "mouse",
                    "parameters", Map.of("pointerType", "mouse"),
                    "actions", new ArrayList<>(pointer)));
        }
        if (key.stream().anyMatch(a -> !"pause".equals(a.get("type")))) {
            actions.add(Map.of("type", "key", "id", "keyboard", "actions", new ArrayList<>(key)));
        }
        if (wheel.stream().anyMatch(a -> !"pause".equals(a.get("type")))) {
            actions.add(Map.of("type", "wheel", "id", "wheel", "actions", new ArrayList<>(wheel)));
        }
        if (!actions.isEmpty()) {
            driver.performActions(actions);
        }
    }

    /** W3C requires every device's action list to be the same length; pad the shorter ones. */
    private void sync() {
        int n = Math.max(pointer.size(), Math.max(key.size(), wheel.size()));
        while (pointer.size() < n) {
            pointer.add(Map.of("type", "pause", "duration", 0));
        }
        while (key.size() < n) {
            key.add(Map.of("type", "pause", "duration", 0));
        }
        while (wheel.size() < n) {
            wheel.add(Map.of("type", "pause", "duration", 0));
        }
    }
}
