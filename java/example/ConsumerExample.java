import org.openqa.selenium.By;
import org.openqa.selenium.RemoteWebDriver;
import org.openqa.selenium.WebDriverException;
import org.openqa.selenium.WebDriver;


/**
 * Third-party consumer example. Uses the INSTALLED selenium-core JAR (on the
 * classpath — NOT the source tree) and proves the bundled engine .so (a
 * /native/ jar resource) loads and drives the protocol, with SELENIUM_CORE_LIB
 * unset so only the jar's own bundled .so can satisfy the load.
 *
 * Modes (argv[0]): ffi | discovery | live.
 */
public class ConsumerExample {

    public static void main(String[] args) throws Exception {
        String mode = args.length > 0 ? args[0] : "ffi";
        switch (mode) {
            case "ffi" -> modeFfi();
            case "discovery" -> modeDiscovery();
            case "live" -> modeLive();
            default -> fail("unknown mode: " + mode);
        }
    }

    static void modeFfi() {
        if (!RemoteWebDriver.route("get").equals("POST /session/:sessionId/url")) {
            fail("route mismatch");
        }
        if (RemoteWebDriver.errorCode("no such element") != 17) {
            fail("errorCode mismatch");
        }
        if (!RemoteWebDriver.locator("id", "main").contains("*[id=")) {
            fail("locator mismatch");
        }
        boolean threw = false;
        try {
            RemoteWebDriver.chrome("http://127.0.0.1:1", null);
        } catch (WebDriverException e) {
            threw = e.code() == -1;
        }
        if (!threw) {
            fail("expected transport failure");
        }
        System.out.println("consumer(ffi): OK — installed jar loaded its bundled .so and marshalled");
    }

    static void modeDiscovery() {
        if (System.getenv("SELENIUM_CORE_LIB") != null && !System.getenv("SELENIUM_CORE_LIB").isEmpty()) {
            fail("SELENIUM_CORE_LIB set; discovery must run without it");
        }
        // The bundled .so is a jar resource; if it weren't present, the first
        // native call would fail to load. This call forces the load.
        if (!RemoteWebDriver.route("newSession").equals("POST /session")) {
            fail("route mismatch (bundled .so did not load)");
        }
        System.out.println("consumer(discovery): OK — zero-config bundled-.so (jar resource) discovery works");
    }

    static void modeLive() throws Exception {
        // The engine starts the driver, so the whole tree (browser included) ends
        // on stop() and when this JVM dies.
        RemoteWebDriver.DriverProcess cd = RemoteWebDriver.ensureDriver("chrome");
        if (cd == null) {
            System.out.println("consumer(live): SKIPPED — the engine cannot resolve a chromedriver");
            return;
        }
        try {
            WebDriver d = RemoteWebDriver.headlessChrome(cd.url());
            try {
                String html = "<!doctype html><title>Installed</title><h1 id=\"h\">Hi</h1>";
                d.get("data:text/html;charset=utf-8," + java.net.URLEncoder.encode(html, java.nio.charset.StandardCharsets.UTF_8)
                        .replace("+", "%20"));
                if (!d.getTitle().equals("Installed")) {
                    fail("title=" + d.getTitle());
                }
                if (!d.findElement(By.id("h")).getText().equals("Hi")) {
                    fail("text mismatch");
                }
                System.out.println("consumer(live): OK — installed jar drove real headless Chrome");
            } finally {
                d.quit();
            }
        } finally {
            cd.stop();
        }
    }

    static void fail(String msg) {
        System.err.println("FAIL: " + msg);
        System.exit(1);
    }
}
