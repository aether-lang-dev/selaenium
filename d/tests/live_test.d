/**
 * Live end-to-end test (D): a real headless Chrome session driven through the
 * pure-Aether engine via the linked .so, against a tiny in-process content
 * server (own thread — a blocking FFI call on the main thread won't stall it).
 * Exercises navigation, find, click, text, cookies, executeScript, waits, the
 * Select wrapper, an Actions gesture, and the NoSuchElement error path.
 *
 * Self-skips (exit 0) when chromedriver cannot be resolved, so it is safe in a
 * headless CI without a browser. Built by d/.tests.ae with the engine .so on
 * the link path + rpath.
 */
import std.json;
import std.stdio : writeln, stderr;
import std.socket;
import std.conv : to;
import std.string : indexOf, toLower, startsWith;
import std.process : environment;
import core.thread : Thread;
import core.time : msecs, seconds;
import selenium;

// --- fixture pages ---
enum pageOne =
    "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>" ~
    "<a id=\"go\" href=\"/two\">to two</a>" ~
    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>" ~
    "<select id=\"country\"><option value=\"us\">United States</option>" ~
    "<option value=\"es\">Spain</option><option value=\"fr\">France</option></select>" ~
    "<button id=\"reveal\" onclick=\"setTimeout(function(){var p=document.createElement('p');" ~
    "p.id='late';p.textContent='here';document.body.appendChild(p);},300)\">reveal</button>";
enum pageTwo = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>";

private int failures = 0;
private void check(bool cond, string msg) {
    if (cond) { writeln("  ok   ", msg); }
    else { writeln("  FAIL ", msg); failures++; }
}

private shared bool serverStop = false;

private void contentServer(ushort port) {
    auto listener = new TcpSocket();
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    listener.bind(new InternetAddress("127.0.0.1", port));
    listener.listen(16);
    listener.blocking = false;
    while (!serverStop) {
        Socket client;
        try {
            client = listener.accept();
        } catch (SocketAcceptException) {
            Thread.sleep(20.msecs);
            continue;
        }
        scope(exit) client.close();
        client.blocking = true;
        char[4096] buf;
        auto n = client.receive(buf[]);
        if (n <= 0) continue;
        string req = buf[0 .. n].idup;
        string body = (req.indexOf("GET /two") >= 0) ? pageTwo : pageOne;
        string resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: "
            ~ to!string(body.length) ~ "\r\nConnection: close\r\n\r\n" ~ body;
        client.send(resp);
    }
    listener.close();
}

private ushort freePort() {
    auto s = new TcpSocket();
    s.bind(new InternetAddress("127.0.0.1", 0));
    auto addr = cast(InternetAddress) s.localAddress;
    ushort p = addr.port;
    s.close();
    return p;
}

private string resolveChromedriver() {
    // Prefer the engine's driver manager; fall back to PATH.
    string p = resolveDriver("chrome");
    if (p.length > 0) return p;
    foreach (dir; environment.get("PATH", "").split(":")) {
        import std.path : buildPath;
        import std.file : exists;
        auto cand = buildPath(dir, "chromedriver");
        if (exists(cand)) return cand;
    }
    return "";
}
import std.array : split;

void main() {
    string driverBin = resolveChromedriver();
    if (driverBin.length == 0) {
        writeln("SKIPPED: chromedriver could not be resolved");
        return;
    }

    ushort port = freePort();
    auto server = new Thread(() => contentServer(port)).start();
    scope(exit) { serverStop = true; server.join(false); }
    Thread.sleep(150.msecs); // let it bind

    auto proc = launchDriver(driverBin);
    if (proc is null) {
        writeln("SKIPPED: chromedriver did not launch");
        return;
    }
    scope(exit) proc.stop();

    auto d = headlessChrome(proc.url());
    scope(exit) d.quit();

    string base = "http://127.0.0.1:" ~ to!string(port);

    check(d.sessionId().length > 0, "session established");

    // navigation + find + text
    d.get(base ~ "/one");
    check(d.title() == "Page One", "title is Page One");
    check(d.findElement(By.id("hdr")).text() == "One", "hdr text One");
    check(d.findElement(By.cssSelector("#go")).tagName().toLower == "a", "#go is <a>");

    // click a JS button, re-read text
    d.findElement(By.id("btn")).click();
    check(d.findElement(By.id("hdr")).text() == "clicked", "button updated hdr");

    // link navigation + back/forward
    d.get(base ~ "/one");
    d.findElement(By.id("go")).click();
    check(d.title() == "Page Two", "navigated to Page Two");
    d.back();
    check(d.title() == "Page One", "back to Page One");
    d.forward();
    check(d.title() == "Page Two", "forward to Page Two");

    // cookies
    d.get(base ~ "/one");
    d.addCookie(JSONValue(["name": JSONValue("flavor"), "value": JSONValue("mint")]));
    check(d.cookie("flavor")["value"].str == "mint", "cookie round-trips");

    // executeScript
    check(d.executeScript("return 6*7;").integer == 42, "executeScript arithmetic");
    check(d.executeScript("return 'hi';").str == "hi", "executeScript string");
    check(d.executeScript("return arguments[0]+arguments[1];",
        JSONValue([JSONValue(40), JSONValue(2)])).integer == 42, "executeScript args");

    // window handles
    check(d.windowHandles().length >= 1, "at least one window handle");

    // Select wrapper
    auto sel = Select(d.findElement(By.id("country")));
    sel.selectByValue("es");
    check(d.executeScript("return document.getElementById('country').value;").str == "es",
        "Select.selectByValue");
    sel.selectByVisibleText("France");
    check(d.executeScript("return document.getElementById('country').value;").str == "fr",
        "Select.selectByVisibleText");

    // explicit wait for a late-revealed node
    d.findElement(By.id("reveal")).click();
    auto late = d.waitForElement(By.id("late"), 3000);
    check(late.text() == "here", "waitForElement sees revealed node");

    // accessibility: computed ARIA role + accessible name
    d.executeScript("var s=document.createElement('button');s.id='savebtn';"
        ~ "s.setAttribute('aria-label','Save');document.body.appendChild(s);");
    auto savebtn = d.findElement(By.id("savebtn"));
    check(savebtn.ariaRole() == "button", "getAriaRole computes role");
    check(savebtn.accessibleName() == "Save", "getAccessibleName computes name");

    // logs (se vendor extension): available types + a log fetch
    check(d.logTypes().length >= 1, "getAvailableLogTypes returns types");
    check(d.log("browser").type == JSONType.array, "getLog(browser) returns an array");

    // shadow root: host an open shadow root, find inside it
    d.executeScript(
        "var h=document.createElement('div');h.id='shost';document.body.appendChild(h);"
        ~ "var r=h.attachShadow({mode:'open'});r.innerHTML='<p id=\"sinner\">shadowtext</p>';");
    auto host = d.findElement(By.id("shost"));
    auto sr = host.shadowRoot();
    check(sr.id.length > 0, "getShadowRoot returns a shadow id");
    auto inner = sr.findElement(By.cssSelector("#sinner"));
    check(inner.text() == "shadowtext", "findElementFromShadowRoot reaches shadow content");
    check(sr.findElements(By.cssSelector("p")).length == 1, "findElementsFromShadowRoot counts shadow children");
    // an element with no shadow root raises noSuchShadowRoot (code 19)
    bool nsr = false;
    try {
        d.findElement(By.id("hdr")).shadowRoot();
    } catch (WebDriverException e) {
        nsr = e.code == 19;
    }
    check(nsr, "shadowRoot() on a non-host raises noSuchShadowRoot");

    // NoSuchElement path
    bool nse = false;
    try {
        d.findElement(By.id("does-not-exist"));
    } catch (WebDriverException e) {
        nse = e.kind == ErrorKind.noSuchElement;
    }
    check(nse, "findElement(missing) raises noSuchElement");

    // Firefox factory: drive a real headless Firefox via the firefox() factory
    // (engine-resolved geckodriver). Self-skips when Firefox/geckodriver absent.
    {
        string gecko = resolveDriver("firefox");
        if (gecko.length == 0) {
            writeln("  skip firefox() — no geckodriver");
        } else {
            auto fp = launchDriver(gecko);
            if (fp is null) {
                writeln("  skip firefox() — geckodriver did not launch");
            } else {
                scope(exit) fp.stop();
                auto ff = headlessFirefox(fp.url());
                scope(exit) ff.quit();
                ff.get("data:text/html,<title>FF</title><h1 id=h>Hello FF</h1>");
                check(ff.title() == "FF", "firefox() drives a real Firefox session");
                check(ff.findElement(By.id("h")).text() == "Hello FF", "firefox() find+text");
            }
        }
    }

    writeln(failures == 0 ? "ALL PASSED" : "FAILURES");
    import core.stdc.stdlib : exit;
    exit(failures == 0 ? 0 : 1);
}
