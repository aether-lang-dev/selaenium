package org.seleniumhq.aether;

/**
 * Base for all remote-end errors, carrying the engine's stable W3C error code
 * (0 = success, -1 = transport failure). Subtypes map specific codes to typed
 * exceptions; {@link WebDriver#classify} does the dispatch.
 */
public class WebDriverError extends RuntimeException {
    private final int code;

    public WebDriverError(String message, int code) {
        super(message);
        this.code = code;
    }

    public int code() {
        return code;
    }

    public static final class NoSuchElement extends WebDriverError {
        public NoSuchElement(String m, int c) {
            super(m, c);
        }
    }

    public static final class StaleElementReference extends WebDriverError {
        public StaleElementReference(String m, int c) {
            super(m, c);
        }
    }

    public static final class ElementClickIntercepted extends WebDriverError {
        public ElementClickIntercepted(String m, int c) {
            super(m, c);
        }
    }

    public static final class ElementNotInteractable extends WebDriverError {
        public ElementNotInteractable(String m, int c) {
            super(m, c);
        }
    }

    public static final class InvalidSelector extends WebDriverError {
        public InvalidSelector(String m, int c) {
            super(m, c);
        }
    }

    public static final class Timeout extends WebDriverError {
        public Timeout(String m, int c) {
            super(m, c);
        }
    }

    public static final class Javascript extends WebDriverError {
        public Javascript(String m, int c) {
            super(m, c);
        }
    }

    public static final class UnknownCommand extends WebDriverError {
        public UnknownCommand(String m, int c) {
            super(m, c);
        }
    }
}
