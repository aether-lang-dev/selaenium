import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.openqa.selenium.BidiEvent;
import org.openqa.selenium.By;
import org.openqa.selenium.ChromeDriver;
import org.openqa.selenium.NoSuchElementException;
import org.openqa.selenium.RemoteWebDriver;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.WebElement;

/**
 * Live end-to-end + surface test (Java): a real headless Chrome session driven
 * through the pure-Aether engine via Panama FFM, served by an in-process
 * com.sun.net.httpserver.HttpServer for a real cookie/nav origin (Java's FFM
 * downcalls block only the calling thread, so the server's own threads keep
 * answering). The whole pipeline — Java -> FFM -> libselenium_core.so ->
 * std.http.client -> chromedriver -> Chrome. assumeTrue-skips if chromedriver
 * is absent, so the suite is green on a box without a browser.
 */
class LiveTest {

    static final String PAGE_ONE =
            "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>"
            + "<a id=\"go\" href=\"/two\">to two</a>"
            + "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>";
    static final String PAGE_TWO = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>";

    // Headless Chrome against a running chromedriver, honoring SEL_CHROME_BINARY
    // when set (a box with no system Chrome but a cached Chrome-for-Testing).
    private static WebDriver headlessChromeAt(String commandExecutor) {
        Map<String, Object> chromeOpts = new HashMap<>();
        chromeOpts.put("args", List.of("--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"));
        String chromeBin = System.getenv("SEL_CHROME_BINARY");
        if (chromeBin != null && !chromeBin.isEmpty()) {
            chromeOpts.put("binary", chromeBin);
        }
        return RemoteWebDriver.chrome(commandExecutor, Map.of("goog:chromeOptions", chromeOpts));
    }

    @Test
    void liveChromeSurface() throws Exception {
        String driverBin = which("chromedriver");
        assumeTrue(driverBin != null, "chromedriver not on PATH");

        HttpServer web = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        web.createContext("/", ex -> {
            byte[] body = (ex.getRequestURI().getPath().startsWith("/two") ? PAGE_TWO : PAGE_ONE)
                    .getBytes(StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("Content-Type", "text/html; charset=utf-8");
            ex.sendResponseHeaders(200, body.length);
            try (OutputStream os = ex.getResponseBody()) {
                os.write(body);
            }
        });
        web.start();
        String base = "http://127.0.0.1:" + web.getAddress().getPort();

        int cdPort = freePort();
        Process cd = new ProcessBuilder(driverBin, "--port=" + cdPort)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start();
        try {
            assumeTrue(waitUp(cdPort, 10000), "chromedriver did not come up");
            WebDriver d = headlessChromeAt("http://127.0.0.1:" + cdPort);
            try {
                assertTrue(!d.sessionId().isEmpty(), "session id present");

                d.get(base + "/one");
                assertEquals("Page One", d.getTitle(), "title");
                assertEquals("One", d.findElement(By.id("hdr")).getText(), "hdr text");
                assertEquals("a", d.findElement(By.cssSelector("#go")).getTagName().toLowerCase(), "tag name");

                // navigation history
                d.findElement(By.id("go")).click();
                assertEquals("Page Two", d.getTitle(), "after click");
                d.back();
                assertEquals("Page One", d.getTitle(), "after back");
                d.forward();
                assertEquals("Page Two", d.getTitle(), "after forward");
                d.back();

                // cookies
                d.deleteAllCookies();
                d.addCookie(Map.of("name", "flavor", "value", "mint"));
                assertEquals("mint", d.getCookie("flavor").get("value"), "cookie value");
                assertTrue(d.getCookies().stream().anyMatch(c -> "flavor".equals(c.get("name"))), "cookie present");
                d.deleteCookie("flavor");
                assertTrue(d.getCookies().stream().noneMatch(c -> "flavor".equals(c.get("name"))), "cookie deleted");

                // windows
                List<String> handles = d.windowHandles();
                assertTrue(handles.size() >= 1, "window handles");
                assertTrue(handles.contains(d.currentWindowHandle()), "current handle in list");
                d.setWindowRect(Map.of("width", 900, "height", 650));
                assertEquals(900.0, d.getWindowRect().get("width"), "window width");

                // execute_script shapes
                assertEquals(42.0, d.executeScript("return 6*7;"), "script scalar");
                assertEquals("hi", d.executeScript("return 'hi';"), "script string");
                assertEquals(List.of(1.0, 2.0, 3.0), d.executeScript("return [1,2,3];"), "script array");
                assertEquals(42.0, d.executeScript("return arguments[0]+arguments[1];", 40, 2), "script args");

                // W3C actions: pointer click on the button.
                WebElement btn = d.findElement(By.id("btn"));
                Map<String, Object> rect = btn.rect();
                int cx = (int) ((double) rect.get("x") + (double) rect.get("width") / 2);
                int cy = (int) ((double) rect.get("y") + (double) rect.get("height") / 2);
                d.performActions(List.of(Map.of(
                        "type", "pointer", "id", "mouse",
                        "parameters", Map.of("pointerType", "mouse"),
                        "actions", List.of(
                                Map.of("type", "pointerMove", "duration", 0, "x", cx, "y", cy),
                                Map.of("type", "pointerDown", "button", 0),
                                Map.of("type", "pointerUp", "button", 0)))));
                assertEquals("clicked", d.findElement(By.id("hdr")).getText(), "actions click fired");
                d.clearActions();

                // screenshot -> PNG
                byte[] png = Base64.getDecoder().decode(d.screenshotBase64());
                assertTrue(png.length > 8 && png[1] == 'P' && png[2] == 'N' && png[3] == 'G', "screenshot is PNG");

                // negative path: typed error
                boolean threw = false;
                try {
                    d.findElement(By.id("does-not-exist"));
                } catch (NoSuchElementException e) {
                    threw = true;
                }
                assertTrue(threw, "NoSuchElement raised");
            } finally {
                d.quit();
            }
        } finally {
            cd.destroy();
            web.stop(0);
        }
    }

    // Driver orchestration over the engine: resolve + spawn a chromedriver
    // in-binding (no chromedriver on PATH, no Grid), drive a page through the
    // self-launched driver, and tear the process down. Self-skips if the engine
    // cannot resolve a driver here (offline, empty cache).
    @Test
    void driverOrchestration() {
        String path = RemoteWebDriver.resolveDriver("chrome");
        assumeTrue(path != null && !path.isEmpty(),
                "engine cannot resolve a chromedriver (offline, no cache)");
        assertTrue(new java.io.File(path).isFile(), "resolve_driver returned a non-file: " + path);

        // ensureDriver spawns it; the handle exposes url + pid.
        RemoteWebDriver.DriverProcess proc = RemoteWebDriver.ensureDriver("chrome");
        assertTrue(proc != null, "ensureDriver returned null");
        try {
            assertTrue(proc.url().startsWith("http"), "driver url: " + proc.url());
            assertTrue(proc.pid() > 0, "driver pid: " + proc.pid());
        } finally {
            proc.stop();
            assertEquals(0, proc.pid(), "stop clears the handle");
        }

        // ChromeDriver spawns its own driver, runs a session, stops it on quit.
        Map<String, Object> chromeOpts = new HashMap<>();
        chromeOpts.put("args", List.of("--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"));
        String chromeBin = System.getenv("SEL_CHROME_BINARY");
        if (chromeBin != null && !chromeBin.isEmpty()) {
            chromeOpts.put("binary", chromeBin);
        }
        WebDriver d = new ChromeDriver(Map.of("goog:chromeOptions", chromeOpts));
        try {
            assertTrue(!d.sessionId().isEmpty(), "ChromeDriver session id present");
            d.get("data:text/html;charset=utf-8,"
                    + "%3Ctitle%3EAether%20Selenium%3C/title%3E%3Ch1%20id='hdr'%3EHello%3C/h1%3E");
            assertEquals("Aether Selenium", d.getTitle(), "localChrome title");
            assertEquals("Hello", d.findElement(By.id("hdr")).getText(), "localChrome #hdr text");
        } finally {
            d.quit();
        }
    }

    @Test
    void liveChromeBidi() throws Exception {
        String driverBin = which("chromedriver");
        assumeTrue(driverBin != null, "chromedriver not on PATH");

        int cdPort = freePort();
        Process cd = new ProcessBuilder(driverBin, "--port=" + cdPort)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start();
        try {
            assumeTrue(waitUp(cdPort, 10000), "chromedriver did not come up");
            WebDriver d = headlessChromeAt("http://127.0.0.1:" + cdPort);
            try {
                assertTrue(d.bidiAvailable(), "BiDi negotiated (webSocketUrl present)");

                d.get("data:text/html,<!doctype html><title>BiDi</title><h1>bidi</h1>");

                Map<String, Object> ack = d.bidi().subscribe(BidiEvent.LOG_ENTRY_ADDED);
                assertEquals("success", ack.get("type"), "subscribe ack success");

                d.executeScript("console.log('bidi-hello');");

                Map<String, Object> ev = d.bidi().nextEvent(BidiEvent.LOG_ENTRY_ADDED, 8000);
                assertTrue(ev != null, "log.entryAdded event arrived");
                assertEquals(BidiEvent.LOG_ENTRY_ADDED, ev.get("method"), "event method");
                assertTrue(ev.toString().contains("bidi-hello"), "event carries logged text");

                Map<String, Object> status = d.bidi().command("session.status", null, 10000);
                assertEquals("success", status.get("type"), "session.status success");

                // typed convenience commands: getTree / script.evaluate / navigate
                String topCtx = d.bidi().topContext(10000);
                assertTrue(topCtx != null, "topContext present");

                Object six7 = d.bidi().evaluateValue("6*7", 30000);
                assertTrue(six7 instanceof Number, "evaluateValue(6*7) is a Number, was: " + six7);
                assertEquals(42, ((Number) six7).intValue(), "evaluateValue(6*7) == 42");

                Object promised = d.bidi().evaluateValue("Promise.resolve(41+1)", 30000);
                assertTrue(promised instanceof Number, "evaluateValue(promise) is a Number, was: " + promised);
                assertEquals(42, ((Number) promised).intValue(), "evaluateValue(Promise.resolve(41+1)) == 42");

                // network interception: intercept a request, catch the paused event, continue it.
                d.bidi().subscribe(BidiEvent.BEFORE_REQUEST_SENT);
                String ic = d.bidi().addIntercept("beforeRequestSent", "", 10000);
                assertTrue(ic != null, "addIntercept returned an intercept id");
                d.executeScript("fetch('https://example.com/blocked').catch(function(){});");
                Map<String, Object> netEv = d.bidi().nextEvent(BidiEvent.BEFORE_REQUEST_SENT, 8000);
                assertTrue(netEv != null, "network.beforeRequestSent event arrived");
                String rid = org.openqa.selenium.BiDi.eventRequestId(netEv);
                assertTrue(rid != null, "event carried a request id");
                assertEquals("success", d.bidi().continueRequest(rid, 10000).get("type"),
                        "continueRequest succeeded");

                // request mocking: fulfill a paused request with a stub body (never hits network).
                d.executeScript("window.__mock='';"
                        + "fetch('https://example.com/api').then(function(r){return r.text()})"
                        + ".then(function(t){window.__mock=t}).catch(function(){});");
                Map<String, Object> ev2 = d.bidi().nextEvent(BidiEvent.BEFORE_REQUEST_SENT, 8000);
                assertTrue(ev2 != null, "network.beforeRequestSent for mocked request arrived");
                String rid2 = org.openqa.selenium.BiDi.eventRequestId(ev2);
                assertTrue(rid2 != null, "mocked event carried a request id");
                Map<String, Object> resp =
                        d.bidi().provideResponse(rid2, 200, "text/plain", "MOCKED-BODY", 10000);
                assertEquals("success", resp.get("type"), "provideResponse succeeded");

                boolean mocked = false;
                for (int i = 0; i < 25; i++) {
                    Object v = d.executeScript("return window.__mock;");
                    if (v instanceof String s && s.contains("MOCKED-BODY")) {
                        mocked = true;
                        break;
                    }
                    Thread.sleep(200);
                }
                assertTrue(mocked, "fetch received the MOCKED-BODY stub");

                // network.setCacheBehavior: bypass then restore default.
                assertEquals("success", d.bidi().setCacheBehavior("bypass", 10000).get("type"),
                        "setCacheBehavior(bypass) succeeded");
                assertEquals("success", d.bidi().setCacheBehavior("default", 10000).get("type"),
                        "setCacheBehavior(default) succeeded");
            } finally {
                d.quit();
            }
        } finally {
            cd.destroy();
        }
    }

    static final String ATOM_PAGE =
            "<!doctype html><title>Atoms</title>"
            + "<h1 id=\"hdr\">Header</h1>"
            + "<button id=\"btn\">click</button>"
            + "<p id=\"gone\" style=\"display:none\">hidden</p>"
            + "<a id=\"lnk\" href=\"https://example.com/x\">link</a>";

    @Test
    void liveChromeAtoms() throws Exception {
        String driverBin = which("chromedriver");
        assumeTrue(driverBin != null, "chromedriver not on PATH");

        int cdPort = freePort();
        Process cd = new ProcessBuilder(driverBin, "--port=" + cdPort)
                .redirectOutput(ProcessBuilder.Redirect.DISCARD)
                .redirectError(ProcessBuilder.Redirect.DISCARD)
                .start();
        try {
            assumeTrue(waitUp(cdPort, 10000), "chromedriver did not come up");
            WebDriver d = headlessChromeAt("http://127.0.0.1:" + cdPort);
            try {
                d.get("data:text/html," + ATOM_PAGE);

                // isDisplayed atom: visible header vs display:none paragraph.
                assertTrue(d.findElement(By.id("hdr")).isDisplayed(), "#hdr is displayed");
                assertTrue(!d.findElement(By.id("gone")).isDisplayed(), "#gone is not displayed");

                // getAttribute atom: resolves href to the property (absolute URL).
                Object href = d.findElement(By.id("lnk")).getAttribute("href");
                assertTrue(href instanceof String s && s.contains("example.com/x"),
                        "getAttribute(href) contains example.com/x, was: " + href);

                // relative locators: the button sits below the header.
                List<WebElement> below = d.findRelative(
                        "button", List.of(Map.of("kind", "below", "sel", "#hdr")));
                assertTrue(below.size() >= 1, "findRelative(button below #hdr) found at least one");
            } finally {
                d.quit();
            }
        } finally {
            cd.destroy();
        }
    }

    // ---- process/net helpers ----
    static String which(String cmd) {
        String path = System.getenv("PATH");
        if (path == null) {
            return null;
        }
        for (String dir : path.split(":")) {
            java.io.File f = new java.io.File(dir, cmd);
            if (f.canExecute() && !f.isDirectory()) {
                return f.getAbsolutePath();
            }
        }
        return null;
    }

    static int freePort() throws IOException {
        try (java.net.ServerSocket s = new java.net.ServerSocket(0, 0, java.net.InetAddress.getByName("127.0.0.1"))) {
            return s.getLocalPort();
        }
    }

    static boolean waitUp(int port, long timeoutMs) {
        long deadline = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < deadline) {
            try (Socket s = new Socket("127.0.0.1", port)) {
                return true;
            } catch (IOException e) {
                try {
                    Thread.sleep(100);
                } catch (InterruptedException ignored) {
                    Thread.currentThread().interrupt();
                }
            }
        }
        return false;
    }
}
