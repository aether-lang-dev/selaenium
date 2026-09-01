import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.openqa.selenium.RemoteWebDriver;
import org.openqa.selenium.WebDriverException;

/**
 * No-browser FFI test: proves the Java Panama FFM binding loads
 * libselenium_core.so and marshals correctly, exercising the pure engine
 * helpers and the transport error path. Needs only the .so (SELENIUM_CORE_LIB /
 * bundled native/); run with --enable-native-access (aeb's jvm_args).
 */
class FfiTest {

    @Test
    void route() {
        assertEquals("POST /session/:sessionId/url", RemoteWebDriver.route("get"));
        assertTrue(RemoteWebDriver.route("nope").isEmpty());
    }

    @Test
    void errorCode() {
        assertEquals(17, RemoteWebDriver.errorCode("no such element"));
        assertEquals(0, RemoteWebDriver.errorCode(""));
    }

    @Test
    void locatorCss() {
        assertEquals(
                "{\"using\":\"css selector\",\"value\":\"div.foo\"}",
                RemoteWebDriver.locator("css selector", "div.foo"));
    }

    @Test
    void locatorIdRewrite() {
        assertEquals(
                "{\"using\":\"css selector\",\"value\":\"*[id=\\\"main\\\"]\"}",
                RemoteWebDriver.locator("id", "main"));
    }

    @Test
    void transportFailure() {
        boolean threw = false;
        try {
            RemoteWebDriver.chrome("http://127.0.0.1:1", null);
        } catch (WebDriverException e) {
            threw = e.code() == -1;
        }
        assertTrue(threw, "transport failure should surface WebDriverException(-1)");
    }
}
