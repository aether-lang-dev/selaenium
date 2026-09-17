package org.openqa.selenium.support.locators;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.openqa.selenium.By;
import org.openqa.selenium.WebElement;

/**
 * Relative locators, mirroring mainstream Selenium's {@code
 * org.openqa.selenium.support.locators.RelativeLocator}. Start a chain with
 * {@link #with(By)} or {@link #withTagName(String)}, add spatial relations, then
 * pass the result straight to {@code driver.findElement(By)} /
 * {@code driver.findElements(By)} (a {@link RelativeBy} is-a {@link By}):
 *
 * <pre>{@code
 *   import static org.openqa.selenium.support.locators.RelativeLocator.with;
 *   WebElement cell = driver.findElement(with(By.tagName("td")).below(header));
 * }</pre>
 *
 * <p>The shared engine's relative-locators atom anchors by CSS selector, so
 * anchors given as a {@link By} (tag name / css / id / class name / name) resolve
 * to CSS. Anchoring by an already-found {@link WebElement} is not supported by
 * this engine path and throws {@link IllegalArgumentException}.
 */
public final class RelativeLocator {

    private RelativeLocator() {}

    /** Start a relative locator rooted at the given {@link By}. */
    public static RelativeBy with(By by) {
        return new RelativeBy(by);
    }

    /** Start a relative locator rooted at a tag name (mainstream convenience). */
    public static RelativeBy withTagName(String tagName) {
        if (tagName == null || tagName.isEmpty()) {
            throw new IllegalArgumentException("tagName must be set");
        }
        return new RelativeBy(By.tagName(tagName));
    }

    /**
     * A relative locator. Because it extends {@link By} it flows through the
     * ordinary {@code findElement(By)} / {@code findElements(By)} path, exactly
     * like mainstream Selenium's {@code RelativeBy}.
     */
    public static final class RelativeBy extends By {

        private final By root;
        private final List<Map<String, Object>> filters;

        RelativeBy(By root) {
            this(root, new ArrayList<>());
        }

        private RelativeBy(By root, List<Map<String, Object>> filters) {
            // The strategy/value are informational here; the driver detects a
            // RelativeBy by type and routes it through the relative-locators atom.
            super("relative", byToCss(root));
            this.root = root;
            this.filters = filters;
        }

        public RelativeBy above(By anchor) {
            return add("above", anchor);
        }

        public RelativeBy above(WebElement anchor) {
            return add("above", anchor);
        }

        public RelativeBy below(By anchor) {
            return add("below", anchor);
        }

        public RelativeBy below(WebElement anchor) {
            return add("below", anchor);
        }

        public RelativeBy toLeftOf(By anchor) {
            return add("left", anchor);
        }

        public RelativeBy toLeftOf(WebElement anchor) {
            return add("left", anchor);
        }

        public RelativeBy toRightOf(By anchor) {
            return add("right", anchor);
        }

        public RelativeBy toRightOf(WebElement anchor) {
            return add("right", anchor);
        }

        public RelativeBy near(By anchor) {
            return add("near", anchor);
        }

        public RelativeBy near(WebElement anchor) {
            return add("near", anchor);
        }

        private RelativeBy add(String kind, Object anchor) {
            if (anchor == null) {
                throw new IllegalArgumentException("Cannot use a null anchor for a relative locator");
            }
            if (anchor instanceof WebElement) {
                throw new IllegalArgumentException(
                        "This binding's relative locators anchor by CSS selector, not by a found "
                                + "WebElement; pass a By anchor (e.g. By.id(\"x\"))");
            }
            Map<String, Object> filter = new LinkedHashMap<>();
            filter.put("kind", kind);
            filter.put("sel", byToCss((By) anchor));
            List<Map<String, Object>> next = new ArrayList<>(filters);
            next.add(filter);
            return new RelativeBy(root, next);
        }

        /** The engine base CSS selector (the root, as CSS). */
        public String baseCss() {
            return byToCss(root);
        }

        /** The engine relative filters ({@code {kind, sel[, dist]}} maps). */
        public List<Map<String, Object>> engineFilters() {
            return List.copyOf(filters);
        }
    }

    private static String byToCss(By by) {
        String s = by.toString(); // "By.<strategy>: <value>"
        int sep = s.indexOf(": ");
        String strategy = s.substring(3, sep);
        String value = s.substring(sep + 2);
        return switch (strategy) {
            case "css selector", "tag name" -> value;
            case "id" -> "#" + value;
            case "class name" -> "." + value;
            case "name" -> "[name=\"" + value + "\"]";
            default -> throw new IllegalArgumentException(
                    "Relative locators do not support the " + strategy
                            + " strategy for anchors; use cssSelector, tagName, id, className or name");
        };
    }
}
