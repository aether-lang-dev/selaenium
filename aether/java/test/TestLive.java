import com.sun.net.httpserver.HttpServer;
import org.seleniumhq.aether.By;
import org.seleniumhq.aether.WebDriver;
import org.seleniumhq.aether.WebDriverError;
import org.seleniumhq.aether.WebElement;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;

/**
 * Live end-to-end + surface test (Java): a real headless Chrome session driven
 * through the pure-Aether engine via Panama FFM, served by an in-process
 * com.sun.net.httpserver.HttpServer for a real cookie/nav origin (Java's FFM
 * downcalls block only the calling thread, so the server's own threads keep
 * answering). The whole pipeline — Java -> FFM -> libselenium_core.so ->
 * std.http.client -> chromedriver -> Chrome. Skips if chromedriver is absent.
 */
public class TestLive {

    static final String PAGE_ONE =
            "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>"
            + "<a id=\"go\" href=\"/two\">to two</a>"
            + "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>";
    static final String PAGE_TWO = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>";

    public static void main(String[] args) throws Exception {
        String driverBin = which("chromedriver");
        if (driverBin == null) {
            System.out.println("SKIPPED: chromedriver not on PATH");
            return;
        }

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
            if (!waitUp(cdPort, 10000)) {
                System.out.println("SKIPPED: chromedriver did not come up");
                return;
            }
            WebDriver d = WebDriver.headlessChrome("http://127.0.0.1:" + cdPort);
            try {
                assertTrue(!d.sessionId().isEmpty(), "session id present");
                System.out.println("  ok: session started (" + d.sessionId().substring(0, 8) + "...)");

                d.get(base + "/one");
                assertEq("Page One", d.title(), "title");
                assertEq("One", d.findElement(By.ID, "hdr").text(), "hdr text");
                assertEq("a", d.findElement(By.CSS_SELECTOR, "#go").tagName().toLowerCase(), "tag name");
                System.out.println("  ok: navigate + find + text/tag");

                // navigation history
                d.findElement(By.ID, "go").click();
                assertEq("Page Two", d.title(), "after click");
                d.back();
                assertEq("Page One", d.title(), "after back");
                d.forward();
                assertEq("Page Two", d.title(), "after forward");
                d.back();
                System.out.println("  ok: back / forward history");

                // cookies
                d.deleteAllCookies();
                d.addCookie(Map.of("name", "flavor", "value", "mint"));
                assertEq("mint", d.getCookie("flavor").get("value"), "cookie value");
                assertTrue(d.getCookies().stream().anyMatch(c -> "flavor".equals(c.get("name"))), "cookie present");
                d.deleteCookie("flavor");
                assertTrue(d.getCookies().stream().noneMatch(c -> "flavor".equals(c.get("name"))), "cookie deleted");
                System.out.println("  ok: add / get / get-one / delete cookies");

                // windows
                List<String> handles = d.windowHandles();
                assertTrue(handles.size() >= 1, "window handles");
                assertTrue(handles.contains(d.currentWindowHandle()), "current handle in list");
                d.setWindowRect(Map.of("width", 900, "height", 650));
                assertEq(900.0, d.getWindowRect().get("width"), "window width");
                System.out.println("  ok: window handles + set/get rect");

                // execute_script shapes
                assertEq(42.0, d.executeScript("return 6*7;"), "script scalar");
                assertEq("hi", d.executeScript("return 'hi';"), "script string");
                assertEq(List.of(1.0, 2.0, 3.0), d.executeScript("return [1,2,3];"), "script array");
                assertEq(42.0, d.executeScript("return arguments[0]+arguments[1];", 40, 2), "script args");
                System.out.println("  ok: execute_script scalar/string/array/args");

                // W3C actions: pointer click on the button.
                WebElement btn = d.findElement(By.ID, "btn");
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
                assertEq("clicked", d.findElement(By.ID, "hdr").text(), "actions click fired");
                d.clearActions();
                System.out.println("  ok: W3C actions (pointer click) + clearActions");

                // screenshot -> PNG
                byte[] png = Base64.getDecoder().decode(d.screenshotBase64());
                assertTrue(png.length > 8 && png[1] == 'P' && png[2] == 'N' && png[3] == 'G', "screenshot is PNG");
                System.out.println("  ok: screenshot (" + png.length + " bytes PNG)");

                // negative path: typed error
                boolean threw = false;
                try {
                    d.findElement(By.ID, "does-not-exist");
                } catch (WebDriverError.NoSuchElement e) {
                    threw = true;
                }
                assertTrue(threw, "NoSuchElement raised");
                System.out.println("  ok: NoSuchElement raised for missing element");

                System.out.println("PASS: Java live surface test green");
            } finally {
                d.quit();
            }
        } finally {
            cd.destroy();
            web.stop(0);
        }
    }

    // ---- assertion helpers ----
    static void assertTrue(boolean cond, String what) {
        if (!cond) {
            throw new AssertionError("FAIL: " + what);
        }
    }

    static void assertEq(Object expected, Object actual, String what) {
        if (!java.util.Objects.equals(expected, actual)) {
            throw new AssertionError("FAIL: " + what + " — expected " + expected + " got " + actual);
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
