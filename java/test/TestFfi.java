import org.seleniumhq.aether.By;
import org.seleniumhq.aether.WebDriver;
import org.seleniumhq.aether.WebDriverError;

/**
 * No-browser FFI test: proves the Java Panama FFM binding loads
 * libselenium_core.so and marshals correctly, exercising the pure engine
 * helpers and the transport error path. Needs only the .so (SELENIUM_CORE_LIB /
 * bundled native/). JUnit-free — a plain main() with assertions so it builds
 * with javac alone (no Maven).
 */
public class TestFfi {
    private static int failures = 0;

    static void check(boolean cond, String label) {
        if (cond) {
            System.out.println("  ok: " + label);
        } else {
            System.out.println("FAIL: " + label);
            failures++;
        }
    }

    public static void main(String[] args) {
        check(WebDriver.route("get").equals("POST /session/:sessionId/url"), "route get");
        check(WebDriver.route("nope").isEmpty(), "route unknown");
        check(WebDriver.errorCode("no such element") == 17, "errorCode no such element");
        check(WebDriver.errorCode("") == 0, "errorCode success");
        check(WebDriver.locator(By.CSS_SELECTOR, "div.foo")
                .equals("{\"using\":\"css selector\",\"value\":\"div.foo\"}"), "locator css");
        check(WebDriver.locator(By.ID, "main")
                .equals("{\"using\":\"css selector\",\"value\":\"*[id=\\\"main\\\"]\"}"), "locator id rewrite");

        boolean threw = false;
        try {
            WebDriver.chrome("http://127.0.0.1:1", null);
        } catch (WebDriverError e) {
            threw = e.code() == -1;
        }
        check(threw, "transport failure -> WebDriverError(-1)");

        if (failures == 0) {
            System.out.println("PASS: Java FFI tests green");
        } else {
            System.out.println("FAILED: " + failures + " Java FFI test(s)");
            System.exit(1);
        }
    }
}
