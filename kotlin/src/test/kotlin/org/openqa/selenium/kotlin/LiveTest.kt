package org.openqa.selenium.kotlin

import com.sun.net.httpserver.HttpServer
import org.openqa.selenium.NoSuchElementException
import org.openqa.selenium.RemoteWebDriver
import org.openqa.selenium.WebDriverException
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.Base64

// FFI + live surface test for the Kotlin binding. No JUnit — a plain main() with
// assertions, run by kotlin/.tests.ae with `kotlin -classpath ...`. Exercises the
// Kotlin sugar (which is pure Java-interop over the FFM binding → the shared
// engine). Live test needs chromedriver; skips otherwise.

private var failures = 0

private fun check(cond: Boolean, label: String) {
    if (cond) println("  ok: $label") else { println("FAIL: $label"); failures++ }
}

private const val PAGE_ONE =
    "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>" +
        "<a id=\"go\" href=\"/two\">to two</a>" +
        "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
private const val PAGE_TWO = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>"

fun main() {
    // ---- FFI (no browser) ----
    check(RemoteWebDriver.route("get") == "POST /session/:sessionId/url", "route get")
    check(RemoteWebDriver.errorCode("no such element") == 17, "errorCode no such element")
    check(RemoteWebDriver.locator("id", "main").contains("*[id="), "locator id rewrite")
    run {
        var threw = false
        try {
            RemoteWebDriver.chrome("http://127.0.0.1:1", null)
        } catch (e: WebDriverException) {
            threw = e.code() == -1
        }
        check(threw, "transport failure -> code -1")
    }

    // ---- live surface ----
    val driverBin = which("chromedriver")
    if (driverBin == null) {
        println("  (live) SKIPPED: chromedriver not on PATH")
    } else {
        liveSurface(driverBin)
    }

    if (failures == 0) {
        println("PASS: Kotlin tests green")
    } else {
        println("FAILED: $failures Kotlin test(s)")
        kotlin.system.exitProcess(1)
    }
}

private fun liveSurface(driverBin: String) {
    val web = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    web.createContext("/") { ex ->
        val body = (if (ex.requestURI.path.startsWith("/two")) PAGE_TWO else PAGE_ONE)
            .toByteArray(StandardCharsets.UTF_8)
        ex.responseHeaders.add("Content-Type", "text/html; charset=utf-8")
        ex.sendResponseHeaders(200, body.size.toLong())
        ex.responseBody.use { it.write(body) }
    }
    web.start()
    val base = "http://127.0.0.1:${web.address.port}"

    val cdPort = freePort()
    val cd = ProcessBuilder(driverBin, "--port=$cdPort")
        .redirectOutput(ProcessBuilder.Redirect.DISCARD)
        .redirectError(ProcessBuilder.Redirect.DISCARD)
        .start()
    try {
        if (!waitUp(cdPort, 10_000)) {
            println("  (live) SKIPPED: chromedriver did not come up")
            return
        }
        headlessChrome("http://127.0.0.1:$cdPort") { d ->
            check(d.sessionId().isNotEmpty(), "session started")

            d.get("$base/one")
            check(d.getTitle() == "Page One", "title")
            check(d.find(By.id("hdr")).getText() == "One", "hdr text")
            check(d.find(By.cssSelector("#go")).getTagName().lowercase() == "a", "tag name")

            // navigation
            d.find(By.id("go")).click()
            check(d.getTitle() == "Page Two", "after click")
            d.back(); check(d.getTitle() == "Page One", "after back")
            d.forward(); check(d.getTitle() == "Page Two", "after forward")
            d.back()

            // cookies
            d.deleteAllCookies()
            d.addCookie(mapOf("name" to "flavor", "value" to "mint"))
            @Suppress("UNCHECKED_CAST")
            val cookie = d.getCookie("flavor") as Map<String, Any?>
            check(cookie["value"] == "mint", "cookie value")
            d.deleteCookie("flavor")

            // windows
            check(d.windowHandles().isNotEmpty(), "window handles")
            d.setWindowRect(mapOf("width" to 900, "height" to 650))
            @Suppress("UNCHECKED_CAST")
            val rect = d.getWindowRect() as Map<String, Any?>
            check((rect["width"] as Number).toInt() == 900, "window width")

            // script shapes
            check((d.script("return 6*7;") as Number).toInt() == 42, "script scalar")
            check((d.script("return arguments[0]+arguments[1];", 40, 2) as Number).toInt() == 42, "script args")

            // W3C actions: pointer click on the button
            @Suppress("UNCHECKED_CAST")
            val br = d.find(By.id("btn")).rect() as Map<String, Any?>
            val cx = ((br["x"] as Number).toDouble() + (br["width"] as Number).toDouble() / 2).toInt()
            val cy = ((br["y"] as Number).toDouble() + (br["height"] as Number).toDouble() / 2).toInt()
            d.performActions(
                listOf(
                    mapOf(
                        "type" to "pointer", "id" to "mouse",
                        "parameters" to mapOf("pointerType" to "mouse"),
                        "actions" to listOf(
                            mapOf("type" to "pointerMove", "duration" to 0, "x" to cx, "y" to cy),
                            mapOf("type" to "pointerDown", "button" to 0),
                            mapOf("type" to "pointerUp", "button" to 0),
                        ),
                    ),
                ),
            )
            check(d.find(By.id("hdr")).getText() == "clicked", "actions click fired")
            d.clearActions()

            // screenshot -> PNG
            val png = Base64.getDecoder().decode(d.screenshotBase64())
            check(png.size > 8 && png[1] == 'P'.code.toByte() && png[2] == 'N'.code.toByte(), "screenshot is PNG")

            // negative path
            var nse = false
            try {
                d.find(By.id("does-not-exist"))
            } catch (e: NoSuchElementException) {
                nse = true
            }
            check(nse, "no such element error")
        }
    } finally {
        cd.destroy()
        web.stop(0)
    }
}

private fun which(cmd: String): String? {
    val path = System.getenv("PATH") ?: return null
    for (dir in path.split(":")) {
        val f = java.io.File(dir, cmd)
        if (f.canExecute() && !f.isDirectory) return f.absolutePath
    }
    return null
}

private fun freePort(): Int = ServerSocket(0, 0, java.net.InetAddress.getByName("127.0.0.1")).use { it.localPort }

private fun waitUp(port: Int, timeoutMs: Long): Boolean {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (System.currentTimeMillis() < deadline) {
        try {
            Socket("127.0.0.1", port).close()
            return true
        } catch (_: Exception) {
            Thread.sleep(100)
        }
    }
    return false
}
