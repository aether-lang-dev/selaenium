import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.seleniumhq.aether.By;
import org.seleniumhq.aether.WebDriver;
import org.seleniumhq.aether.WebDriverError;

/**
 * No-browser FFI test: proves the Java Panama FFM binding loads
 * libselenium_core.so and marshals correctly, exercising the pure engine
 * helpers and the transport error path. Needs only the .so (SELENIUM_CORE_LIB /
 * bundled native/); run with --enable-native-access (aeb's jvm_args).
 */
class FfiTest {

    @Test
    void route() {
        assertEquals("POST /session/:sessionId/url", WebDriver.route("get"));
        assertTrue(WebDriver.route("nope").isEmpty());
    }

    @Test
    void errorCode() {
        assertEquals(17, WebDriver.errorCode("no such element"));
        assertEquals(0, WebDriver.errorCode(""));
    }

    @Test
    void locatorCss() {
        assertEquals(
                "{\"using\":\"css selector\",\"value\":\"div.foo\"}",
                WebDriver.locator(By.CSS_SELECTOR, "div.foo"));
    }

    @Test
    void locatorIdRewrite() {
        assertEquals(
                "{\"using\":\"css selector\",\"value\":\"*[id=\\\"main\\\"]\"}",
                WebDriver.locator(By.ID, "main"));
    }

    @Test
    void transportFailure() {
        boolean threw = false;
        try {
            WebDriver.chrome("http://127.0.0.1:1", null);
        } catch (WebDriverError e) {
            threw = e.code() == -1;
        }
        assertTrue(threw, "transport failure should surface WebDriverError(-1)");
    }
}
