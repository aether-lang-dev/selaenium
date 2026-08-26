package org.seleniumhq.aether;

/**
 * Locator strategies. Values match the engine's by_locator strategy strings;
 * ID/NAME/CLASS_NAME are rewritten to CSS in the engine.
 */
public final class By {
    public static final String ID = "id";
    public static final String NAME = "name";
    public static final String CSS_SELECTOR = "css selector";
    public static final String CLASS_NAME = "className";
    public static final String TAG_NAME = "tag name";
    public static final String LINK_TEXT = "link text";
    public static final String PARTIAL_LINK_TEXT = "partial link text";
    public static final String XPATH = "xpath";

    private By() {
    }
}
