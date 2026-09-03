// FFI + live surface test for the Groovy binding — pure JVM interop over the one
// Java FFM binding (no second FFI). A plain script (no Spock), run by
// groovy/.tests.ae with the Java classes + groovy/src on the classpath. The live
// test needs chromedriver; skips otherwise.
//
// NOTE: authored on a box without a JDK-24-capable Groovy (Debian's 2.4 on JVM
// 17 can't read the Panama-FFM binding). Verified on a box with a modern Groovy
// + JDK >= 22 (catchyos). The Java binding underneath is fully live-verified.
import org.openqa.selenium.RemoteWebDriver
import org.openqa.selenium.By
import org.openqa.selenium.WebDriverException
import org.openqa.selenium.NoSuchElementException
import org.openqa.selenium.BidiEvent
import org.openqa.selenium.groovy.Selenium
import com.sun.net.httpserver.HttpServer
import com.sun.net.httpserver.HttpHandler
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.Base64

int failures = 0
def check = { boolean cond, String label ->
    if (cond) { println "  ok: ${label}" } else { println "FAIL: ${label}"; failures++ }
}

def PAGE_ONE = '<!doctype html><title>Page One</title><h1 id="hdr">One</h1>' +
    '<a id="go" href="/two">to two</a>' +
    '<button id="btn" onclick="document.getElementById(\'hdr\').textContent=\'clicked\'">b</button>'
def PAGE_TWO = '<!doctype html><title>Page Two</title><h1 id="hdr">Two</h1>'

def which = { String cmd ->
    (System.getenv("PATH") ?: "").split(":").findResult { dir ->
        def f = new File(dir, cmd)
        (f.canExecute() && !f.isDirectory()) ? f.absolutePath : null
    }
}
def freePort = { new ServerSocket(0, 0, InetAddress.getByName("127.0.0.1")).withCloseable { it.localPort } }
def waitUp = { int port, long timeoutMs ->
    def deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
        try { new Socket("127.0.0.1", port).close(); return true } catch (ignored) { Thread.sleep(100) }
    }
    false
}

// ---- FFI (no browser) ----
check(RemoteWebDriver.route("get") == "POST /session/:sessionId/url", "route get")
check(RemoteWebDriver.errorCode("no such element") == 17, "errorCode no such element")
check(RemoteWebDriver.locator("id", "main").contains('*[id='), "locator id rewrite")
try {
    RemoteWebDriver.chrome("http://127.0.0.1:1", null)
    check(false, "transport failure")
} catch (WebDriverException e) {
    check(e.code() == -1, "transport failure -> code -1")
}

// ---- live surface ----
def driverBin = which("chromedriver")
if (driverBin == null) {
    println "  (live) SKIPPED: chromedriver not on PATH"
} else {
    def web = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0)
    web.createContext("/", { ex ->
        def body = (ex.requestURI.path.startsWith("/two") ? PAGE_TWO : PAGE_ONE).getBytes(StandardCharsets.UTF_8)
        ex.responseHeaders.add("Content-Type", "text/html; charset=utf-8")
        ex.sendResponseHeaders(200, body.length)
        ex.responseBody.withCloseable { it.write(body) }
    } as HttpHandler)
    web.start()
    def base = "http://127.0.0.1:${web.address.port}"

    def cdPort = freePort()
    def cd = new ProcessBuilder(driverBin, "--port=${cdPort}")
        .redirectOutput(ProcessBuilder.Redirect.DISCARD)
        .redirectError(ProcessBuilder.Redirect.DISCARD)
        .start()
    try {
        if (!waitUp(cdPort, 10000)) {
            println "  (live) SKIPPED: chromedriver did not come up"
        } else {
            Selenium.withHeadlessChrome("http://127.0.0.1:${cdPort}") { d ->
                check(d.sessionId().length() > 0, "session started")

                d.get("${base}/one")
                check(d.getTitle() == "Page One", "title")
                check(d.findElement(By.id("hdr")).getText() == "One", "hdr text")
                check(d.findElement(By.cssSelector("#go")).getTagName().toLowerCase() == "a", "tag name")

                // navigation
                d.findElement(By.id("go")).click()
                check(d.getTitle() == "Page Two", "after click")
                d.back(); check(d.getTitle() == "Page One", "after back")
                d.forward(); check(d.getTitle() == "Page Two", "after forward")
                d.back()

                // cookies
                d.deleteAllCookies()
                d.addCookie([name: "flavor", value: "mint"])
                check(d.getCookie("flavor").get("value") == "mint", "cookie value")
                d.deleteCookie("flavor")

                // windows
                check(d.windowHandles().size() >= 1, "window handles")
                d.setWindowRect([width: 900, height: 650])
                check((d.getWindowRect().get("width") as Number).intValue() == 900, "window width")

                // script shapes
                check((d.executeScript("return 6*7;") as Number).intValue() == 42, "script scalar")
                check((d.executeScript("return arguments[0]+arguments[1];", 40, 2) as Number).intValue() == 42, "script args")

                // W3C actions
                def r = d.findElement(By.id("btn")).rect()
                def cx = ((r.get("x") as Number).doubleValue() + (r.get("width") as Number).doubleValue() / 2) as int
                def cy = ((r.get("y") as Number).doubleValue() + (r.get("height") as Number).doubleValue() / 2) as int
                d.performActions([[
                    type: "pointer", id: "mouse",
                    parameters: [pointerType: "mouse"],
                    actions: [
                        [type: "pointerMove", duration: 0, x: cx, y: cy],
                        [type: "pointerDown", button: 0],
                        [type: "pointerUp", button: 0]
                    ]
                ]])
                check(d.findElement(By.id("hdr")).getText() == "clicked", "actions click fired")
                d.clearActions()

                // screenshot
                def png = Base64.decoder.decode(d.screenshotBase64())
                check(png.length > 8 && png[1] == (byte) 'P' && png[2] == (byte) 'N', "screenshot is PNG")

                // WebDriver-BiDi over the shared Java Panama binding (Groovy
                // reaches the Java BiDi class directly — no Groovy-side FFI).
                check(d.bidiAvailable(), "bidi available (webSocketUrl negotiated)")
                def bidi = d.bidi()
                check(bidi.subscribe(BidiEvent.LOG_ENTRY_ADDED)["type"] == "success",
                    "bidi.subscribe(log.entryAdded)")
                d.executeScript("console.log('bidi-hello');")
                def ev = bidi.nextEvent(BidiEvent.LOG_ENTRY_ADDED, 8000)
                check(ev != null && ev.toString().contains("bidi-hello"),
                    "log.entryAdded event received async, carries the text")
                check(bidi.command("session.status", null, 10000)["type"] == "success",
                    "bidi.command(session.status)")
                check(!bidi.topContext(10000).isEmpty(), "bidi topContext")
                check(((Number) bidi.evaluateValue("6*7", 30000)).intValue() == 42,
                    "bidi.evaluate 6*7 -> 42")

                // negative path
                def nse = false
                try { d.findElement(By.id("does-not-exist")) }
                catch (NoSuchElementException ignored) { nse = true }
                check(nse, "no such element error")
            }
        }
    } finally {
        cd.destroy()
        web.stop(0)
    }
}

if (failures == 0) {
    println "PASS: Groovy tests green"
} else {
    println "FAILED: ${failures} Groovy test(s)"
    System.exit(1)
}
