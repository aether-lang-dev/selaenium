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
import std.digest.sha : sha1Of;
import std.base64 : Base64;
import selenium;

// A minimal RFC 6455 text-only WebSocket client, just enough to prove the runner
// control server end to end (handshake, one masked text frame out, one unmasked
// text frame in). Not a general client — the test's own, kept tiny on purpose.
private final class TinyWs {
    private Socket sock;
    private ubyte[] leftover;   // bytes read past the handshake's \r\n\r\n (a frame may share the segment)
    this(string host, ushort port, string path) {
        sock = new TcpSocket(new InternetAddress(host, port));
        // client key is arbitrary bytes, base64'd; we don't verify the accept hash
        // (the server is ours) but we do complete a valid handshake.
        string key = Base64.encode(cast(ubyte[]) "selaenium-test-16");
        string req = "GET " ~ path ~ " HTTP/1.1\r\nHost: " ~ host ~ "\r\n"
            ~ "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            ~ "Sec-WebSocket-Key: " ~ key ~ "\r\nSec-WebSocket-Version: 13\r\n\r\n";
        sock.send(req);
        // read until the header terminator; KEEP any bytes past it — the server
        // may have written the hello frame into the same TCP segment, and losing
        // them here is exactly the flake that dropped the hello event.
        ubyte[4096] buf; ubyte[] acc;
        ptrdiff_t term = -1;
        while (term < 0) {
            auto n = sock.receive(buf[]); if (n <= 0) break; acc ~= buf[0 .. n];
            term = (cast(string) acc.idup).indexOf("\r\n\r\n");
        }
        if (term >= 0 && term + 4 < acc.length) leftover = acc[term + 4 .. $].dup;
    }
    void sendText(string s) {
        ubyte[] payload = cast(ubyte[]) s.dup;
        ubyte[] f; f ~= 0x81;                       // FIN + text opcode
        ubyte mask = 0x80;
        if (payload.length < 126) f ~= cast(ubyte)(mask | payload.length);
        else { f ~= cast(ubyte)(mask | 126); f ~= cast(ubyte)(payload.length >> 8); f ~= cast(ubyte)(payload.length & 0xff); }
        ubyte[4] mk = [0x12, 0x34, 0x56, 0x78];
        f ~= mk[];
        foreach (i, b; payload) f ~= cast(ubyte)(b ^ mk[i % 4]);
        sock.send(f);
    }
    /// Read one text frame's payload (server frames are unmasked). Blocks up to
    /// `timeoutMs`; returns "" on timeout/close. Assumes payload < 65536.
    string recvText(int timeoutMs) {
        sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, timeoutMs.msecs);
        ubyte[2] h;
        if (!readN(h[], 2)) return "";
        size_t len = h[1] & 0x7f;
        if (len == 126) { ubyte[2] e; if (!readN(e[], 2)) return ""; len = (e[0] << 8) | e[1]; }
        auto pay = new ubyte[len];
        if (len && !readN(pay, len)) return "";
        return cast(string) pay.idup;
    }
    private bool readN(ubyte[] dst, size_t n) {
        size_t got = 0;
        // drain any handshake-segment leftover first, then the socket
        if (leftover.length) {
            auto take = leftover.length < n ? leftover.length : n;
            dst[0 .. take] = leftover[0 .. take]; got = take;
            leftover = leftover[take .. $];
        }
        while (got < n) { auto r = sock.receive(dst[got .. n]); if (r <= 0) return false; got += r; }
        return true;
    }
    void close() { if (sock !is null) { sock.close(); sock = null; } }
}

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

int main() {
    string driverBin = resolveChromedriver();
    if (driverBin.length == 0) {
        writeln("SKIPPED: chromedriver could not be resolved");
        return 0;   // a skip is success
    }

    ushort port = freePort();
    auto server = new Thread(() => contentServer(port)).start();
    scope(exit) { serverStop = true; server.join(false); }
    Thread.sleep(150.msecs); // let it bind

    auto proc = launchDriver(driverBin);
    if (proc is null) {
        writeln("SKIPPED: chromedriver did not launch");
        return 0;   // a skip is success
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

    // Runner Phase 0: structured trace + named timers (engine-backed, opt-in).
    {
        d.setTrace(true);
        d.timerStart("phase0");
        d.get("data:text/html,<title>Trace</title><h1 id=x>t</h1>");
        d.findElement(By.id("x")).text();
        d.timerStop("phase0");
        auto ev = d.traceEvents();
        check(ev.type == JSONType.array && ev.array.length >= 2, "trace: records an Event per command");
        bool hasGet = false, allPassed = true;
        long durSum = 0;
        foreach (e; ev.array) {
            if (e["command"].str == "get") hasGet = true;
            if (!e["passed"].boolean) allPassed = false;
            durSum += e["duration_ms"].integer;
        }
        check(hasGet, "trace: the 'get' command is in the trace");
        check(allPassed, "trace: successful commands mark passed=true");
        check(durSum >= 0, "trace: duration_ms is a real (long) number, no int32 overflow");
        check(d.traceEvents().array.length == 0, "trace: draining resets the buffer");
        auto tm = d.timers();
        check(tm.type == JSONType.array && tm.array.length == 1 && tm[0]["name"].str == "phase0",
              "timers: a named span is recorded with its duration");
        d.setTrace(false);
    }

    // Runner shell: drive the session through the engine-side "wee shell language"
    // (shell.ae, exposed over the C ABI as shell_eval). Front-end-agnostic — the
    // same lines a REPL / SUT-adjacent iframe / editor would send.
    {
        auto ro = d.shell("open data:text/html,<title>Sh</title><h1 id=q>hey</h1>");
        check(ro["ok"].boolean, "shell: open ok");
        check(d.shell("title")["value"].str == "Sh", "shell: title through the shell");
        check(d.shell("text #q")["value"].str == "hey", "shell: text #q through the shell");
        check(d.shell("eval return 6*7;")["value"].integer == 42, "shell: eval");
        auto err = d.shell("bogusverb");
        check(!err["ok"].boolean && err["error"].str.indexOf("unknown command") >= 0,
              "shell: unknown verb -> ok:false with error");
    }

    // Runner controller: the interactive run/step/continue surface the terminal
    // REPL (and the iframe/editor front-ends) drive. Same session.
    {
        auto r = d.runner();
        scope(exit) r.close();
        // run mode: eval executes immediately, reply carries the shell result
        auto rr = r.eval("open data:text/html,<title>Run</title><h1 id=z>go</h1>");
        check(("result" in rr) !is null && rr["result"]["ok"].boolean, "runner: run-mode eval ok");
        check(r.eval("title")["result"]["value"].str == "Run", "runner: title via runner");
        // a command-finished event fired
        bool sawFinished = false;
        for (auto ev = r.nextEvent(); ev.type == JSONType.object; ev = r.nextEvent())
            if (ev["method"].str == "command-finished") sawFinished = true;
        check(sawFinished, "runner: command-finished event emitted");
        // step mode: queue then step
        check(r.mode("step")["result"]["mode"].str == "step", "runner: mode step");
        auto q = r.eval("text #z");
        check(("queued" in q["result"]) !is null, "runner: step-mode eval queues");
        auto st = r.step()["result"];   // unwrap the runner-lane frame's result
        check(st["stepped"].boolean && st["result"]["value"].str == "go",
              "runner: step runs the queued line -> 'go'");
    }

    // SUT-adjacent console bridge: the executeScript transport half (the unit
    // probe covers the pure correlation core). Inject the shim, simulate the
    // console posting a request into the page outbox, pump once, and assert the
    // driving client ran it through the runner and pushed a reply back into the
    // page inbox — the full "down to the driving client and back up" round trip
    // against a real browser.
    {
        d.get(base ~ "/one");                 // Page One: <h1 id=hdr>One</h1>
        auto br = d.bridge();
        scope(exit) br.close();
        br.inject();                          // installs window.__selaenium + console iframe
        // The console would postMessage this up; simulate by pushing straight
        // into the outbox the shim drains (bypassing the iframe for the test).
        d.executeScript(
            "window.__selaenium.out.push(JSON.stringify("
            ~ "{id:7001,method:'eval',params:{line:'text #hdr'}}));"
            ~ "window.__selaenium.__replies=[];"
            ~ "window.addEventListener('message',function(e){"
            ~ "  if(e.data&&e.data.selaenium==='rep')window.__selaenium.__replies.push(e.data.body);});");
        check(br.pump() >= 1, "bridge: pump processed the queued console request");
        // the shim delivered the reply via postMessage; it lands in __replies
        // asynchronously, so poll briefly for it.
        JSONValue captured = JSONValue(null);
        foreach (_; 0 .. 20) {
            auto reps = d.executeScript("return JSON.stringify(window.__selaenium.__replies||[]);");
            auto arr = parseJSON(reps.str);
            if (arr.type == JSONType.array && arr.array.length > 0) {
                foreach (item; arr.array)
                    if (item.type == JSONType.object && ("result" in item) !is null) captured = item;
                if (captured.type == JSONType.object) break;
            }
            Thread.sleep(50.msecs);
        }
        check(captured.type == JSONType.object, "bridge: a reply was delivered back into the page");
        check(captured.type == JSONType.object && captured["result"]["value"].str == "One",
              "bridge: the round-tripped 'text #hdr' returned 'One'");
    }

    // Runner control server: the OUT-OF-PROCESS host path. Stand up the WS server
    // on this session, connect a bare WebSocket client (as a dashboard / VS Code /
    // Tauri / DAP host would), and drive the session over the wire — the same
    // runner protocol, now across a socket. Proves the whole step-4 substrate.
    {
        d.get("data:text/html,<title>Srv</title><h1 id=hh>served</h1>");
        ushort sp = freePort();
        auto srv = new RunnerServer(d, sp);
        // give the listener thread a moment to bind
        TinyWs c = null;
        foreach (_; 0 .. 40) {
            try { c = new TinyWs("127.0.0.1", sp, "/runner"); break; }
            catch (Exception) { Thread.sleep(50.msecs); }
        }
        check(c !is null, "server: WebSocket client connected to ws://…/runner");
        if (c !is null) {
            scope(exit) c.close();
            // the server greets with a hello event carrying the session id; poll
            // a few frames for it (don't assume it is literally the first read).
            bool sawHello = false;
            foreach (_; 0 .. 10) {
                auto raw = c.recvText(3000);
                if (raw.length == 0) break;
                auto f = parseJSON(raw);
                if (f.type == JSONType.object && ("method" in f) !is null && f["method"].str == "hello") { sawHello = true; break; }
            }
            check(sawHello, "server: hello event announces the session on connect");
            // drive an eval over the wire; reply is the id-correlated runner frame
            c.sendText(`{"id":42,"method":"eval","params":{"line":"text #hh"}}`);
            JSONValue reply = JSONValue(null);
            foreach (_; 0 .. 20) {
                auto raw = c.recvText(3000);
                if (raw.length == 0) break;
                auto f = parseJSON(raw);
                if (f.type == JSONType.object && ("id" in f) !is null && f["id"].integer == 42) { reply = f; break; }
                // (may first read a command-finished event; keep reading for id 42)
            }
            check(reply.type == JSONType.object, "server: an id-correlated reply came back over the wire");
            check(reply.type == JSONType.object && reply["result"]["value"].str == "served",
                  "server: 'text #hh' over the socket returned 'served'");
        }
    }

    // .side playback: play a real Selenium IDE project against this session and
    // check the report. Two commands — open a data: page, assert its title — so
    // the whole parse -> per-command shell dispatch -> pass/fail report path runs
    // against a live browser. (The playback engine is shell.side_run, engine-side.)
    {
        string side =
            `{"name":"demo","tests":[{"name":"opens-and-checks","commands":[` ~
            `{"command":"open","target":"data:text/html,<title>SideOK</title><h1 id=z>hi</h1>","value":""},` ~
            `{"command":"assertTitle","target":"","value":"SideOK"},` ~
            `{"command":"assertText","target":"id=z","value":"hi"}]}]}`;
        auto rep = d.playSide(side);
        check(rep["tests"].integer == 1, "side: one test in the report");
        check(rep["passed"].integer == 1 && rep["failed"].integer == 0,
              "side: the .side test passed against live Chrome");
        check(rep["results"][0]["ok"].boolean, "side: per-test ok flag set");
        // a deliberately-wrong assertion must fail the test + stop it
        string bad =
            `{"name":"demo","tests":[{"name":"wrong-title","commands":[` ~
            `{"command":"open","target":"data:text/html,<title>Real</title>","value":""},` ~
            `{"command":"assertTitle","target":"","value":"NotReal"}]}]}`;
        auto rep2 = d.playSide(bad);
        check(rep2["failed"].integer == 1, "side: a wrong assertion fails the test");
    }

    // Grid client: drive a session THROUGH a real Selenium Grid hub (the
    // grid/run-grid-test.sh harness stands one up in a container and exports
    // SEL_GRID_URL). openSession(hubUrl) -> HTTP -> router -> node -> browser.
    // Self-skips when SEL_GRID_URL is unset (the no-Grid `aeb d/.tests.ae` run).
    {
        string gridUrl = environment.get("SEL_GRID_URL", "");
        if (gridUrl.length == 0) {
            writeln("  skip grid — SEL_GRID_URL unset");
        } else {
            auto gd = chrome(gridUrl);
            scope(exit) gd.quit();
            check(gd.sessionId().length > 0, "grid: session established via hub");
            gd.get("data:text/html,<title>Grid</title><h1 id=h>Hello Grid</h1>");
            check(gd.title() == "Grid", "grid: nav+title through the hub");
            check(gd.findElement(By.id("h")).text() == "Hello Grid", "grid: find+text through the hub");
        }
    }

    writeln(failures == 0 ? "ALL PASSED" : "FAILURES");
    // RETURN, never core.stdc.stdlib.exit(): a C exit() terminates the process
    // without unwinding, so every scope(exit) above it is skipped — the driver
    // is never stopped and the session never quit. The orphaned chromedriver +
    // Chrome then keep this process's inherited stdout pipe open, and whatever
    // is reading it (aeb) blocks forever on a test that itself finished in
    // seconds. An int main() sets the same exit status and still unwinds.
    return failures == 0 ? 0 : 1;
}
