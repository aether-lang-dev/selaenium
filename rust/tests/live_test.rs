//! Live end-to-end + surface test (Rust): a real headless Chrome session driven
//! through the pure-Aether engine, served by a tiny std-only HTTP server for a
//! real cookie/nav origin (std threads, so a blocking FFI call on the test
//! thread doesn't stall the server). The whole pipeline — Rust -> extern "C" ->
//! libselenium_core.so -> std.http.client -> chromedriver -> Chrome. Skips if
//! chromedriver is absent. No external crates (a hand-rolled server + `which`).

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use selenium_core::{json, BidiEvent, By, ErrorKind, Json, WebDriver};

const PAGE_ONE: &str = concat!(
    "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>",
    "<a id=\"go\" href=\"/two\">to two</a>",
    "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
);
const PAGE_TWO: &str = "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>";

fn which(cmd: &str) -> Option<String> {
    let path = std::env::var("PATH").ok()?;
    for dir in path.split(':') {
        let full = format!("{dir}/{cmd}");
        if std::path::Path::new(&full).is_file() {
            return Some(full);
        }
    }
    None
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port()
}

fn wait_up(port: u16, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if TcpStream::connect(("127.0.0.1", port)).is_ok() {
            return true;
        }
        thread::sleep(Duration::from_millis(100));
    }
    false
}

/// A minimal HTTP/1.1 server serving PAGE_ONE / PAGE_TWO, run on its own thread.
fn start_content_server() -> (u16, Arc<AtomicBool>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    listener.set_nonblocking(true).unwrap();
    let stop = Arc::new(AtomicBool::new(false));
    let stop_c = stop.clone();
    thread::spawn(move || {
        while !stop_c.load(Ordering::Relaxed) {
            match listener.accept() {
                Ok((stream, _)) => handle_conn(stream),
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(20));
                }
                Err(_) => break,
            }
        }
    });
    (port, stop)
}

fn handle_conn(mut stream: TcpStream) {
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    // Drain headers.
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap_or(0) == 0 || line == "\r\n" || line == "\n" {
            break;
        }
    }
    let path = request_line.split_whitespace().nth(1).unwrap_or("/");
    let body = if path.starts_with("/two") { PAGE_TWO } else { PAGE_ONE };
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.flush();
}

struct DriverGuard(Child);
impl Drop for DriverGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn live_chrome_surface() {
    let Some(driver_bin) = which("chromedriver") else {
        eprintln!("SKIPPED: chromedriver not on PATH");
        return;
    };

    let (web_port, stop) = start_content_server();
    let base = format!("http://127.0.0.1:{web_port}");

    let cd_port = free_port();
    let cd = Command::new(&driver_bin)
        .arg(format!("--port={cd_port}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn chromedriver");
    let _guard = DriverGuard(cd);

    if !wait_up(cd_port, Duration::from_secs(10)) {
        stop.store(true, Ordering::Relaxed);
        eprintln!("SKIPPED: chromedriver did not come up");
        return;
    }

    let d = WebDriver::headless_chrome(&format!("http://127.0.0.1:{cd_port}")).expect("new session");
    assert!(!d.session_id().is_empty(), "session id present");

    d.get(&format!("{base}/one")).unwrap();
    assert_eq!(d.title().unwrap(), "Page One");
    assert_eq!(d.find_element(By::ID, "hdr").unwrap().text().unwrap(), "One");
    assert_eq!(d.find_element(By::CSS, "#go").unwrap().tag_name().unwrap().to_lowercase(), "a");

    // navigation history
    d.find_element(By::ID, "go").unwrap().click().unwrap();
    assert_eq!(d.title().unwrap(), "Page Two");
    d.back().unwrap();
    assert_eq!(d.title().unwrap(), "Page One");
    d.forward().unwrap();
    assert_eq!(d.title().unwrap(), "Page Two");
    d.back().unwrap();

    // cookies
    d.delete_all_cookies().unwrap();
    d.add_cookie(json::obj(vec![("name", json::s("flavor")), ("value", json::s("mint"))])).unwrap();
    assert_eq!(d.get_cookie("flavor").unwrap().get("value").and_then(|v| v.as_str()), Some("mint"));
    d.delete_cookie("flavor").unwrap();

    // windows
    let handles = d.window_handles().unwrap();
    assert!(!handles.is_empty());
    assert!(handles.contains(&d.current_window_handle().unwrap()));
    d.set_window_rect(json::obj(vec![("width", json::n(900.0)), ("height", json::n(650.0))])).unwrap();
    assert_eq!(d.get_window_rect().unwrap().get("width").and_then(|v| v.as_f64()), Some(900.0));

    // execute_script shapes
    assert_eq!(d.execute_script("return 6*7;", vec![]).unwrap().as_f64(), Some(42.0));
    assert_eq!(d.execute_script("return 'hi';", vec![]).unwrap().as_str(), Some("hi"));
    assert_eq!(
        d.execute_script("return arguments[0]+arguments[1];", vec![json::n(40.0), json::n(2.0)]).unwrap().as_f64(),
        Some(42.0)
    );

    // W3C actions: pointer click on the button.
    let rect = d.find_element(By::ID, "btn").unwrap().rect().unwrap();
    let x = rect.get("x").and_then(|v| v.as_f64()).unwrap();
    let y = rect.get("y").and_then(|v| v.as_f64()).unwrap();
    let w = rect.get("width").and_then(|v| v.as_f64()).unwrap();
    let h = rect.get("height").and_then(|v| v.as_f64()).unwrap();
    let cx = (x + w / 2.0) as i64;
    let cy = (y + h / 2.0) as i64;
    d.perform_actions(vec![json::obj(vec![
        ("type", json::s("pointer")),
        ("id", json::s("mouse")),
        ("parameters", json::obj(vec![("pointerType", json::s("mouse"))])),
        (
            "actions",
            Json::Arr(vec![
                json::obj(vec![("type", json::s("pointerMove")), ("duration", json::n(0.0)), ("x", json::n(cx as f64)), ("y", json::n(cy as f64))]),
                json::obj(vec![("type", json::s("pointerDown")), ("button", json::n(0.0))]),
                json::obj(vec![("type", json::s("pointerUp")), ("button", json::n(0.0))]),
            ]),
        ),
    ])])
    .unwrap();
    assert_eq!(d.find_element(By::ID, "hdr").unwrap().text().unwrap(), "clicked");
    d.clear_actions().unwrap();

    // screenshot -> PNG
    let shot = d.screenshot_base64().unwrap();
    let raw = base64_decode(&shot);
    assert!(raw.len() > 8 && &raw[1..4] == b"PNG", "screenshot is not a PNG");

    // negative path
    let err = d.find_element(By::ID, "does-not-exist").unwrap_err();
    assert_eq!(err.kind, ErrorKind::NoSuchElement);

    d.quit().unwrap();
    stop.store(true, Ordering::Relaxed);
}

/// A LIVE WebDriver-BiDi round-trip against real Chrome: negotiate a
/// webSocketUrl, subscribe to log.entryAdded, trigger a console.log, and drain
/// the matching event; then a plain BiDi command (session.status). Mirrors the
/// `live_chrome_surface` fixture (own chromedriver on an ephemeral port,
/// self-skip if chromedriver absent, a data: URL for a real document).
#[test]
fn live_bidi() {
    let Some(driver_bin) = which("chromedriver") else {
        eprintln!("SKIPPED: chromedriver not on PATH");
        return;
    };

    let cd_port = free_port();
    let cd = Command::new(&driver_bin)
        .arg(format!("--port={cd_port}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn chromedriver");
    let _guard = DriverGuard(cd);

    if !wait_up(cd_port, Duration::from_secs(10)) {
        eprintln!("SKIPPED: chromedriver did not come up");
        return;
    }

    let mut d =
        WebDriver::headless_chrome(&format!("http://127.0.0.1:{cd_port}")).expect("new session");
    assert!(d.bidi_available(), "session negotiated a webSocketUrl (BiDi available)");

    // A real document origin for the console.log to run against.
    d.get("data:text/html,<!doctype html><title>bidi</title><h1>bidi</h1>").unwrap();

    // Subscribe to log entries; the ack must report success.
    let ack = d.bidi().unwrap().subscribe(&[BidiEvent::LOG_ENTRY_ADDED]).unwrap();
    assert_eq!(ack.get("type").and_then(|v| v.as_str()), Some("success"), "subscribe ack: {ack:?}");

    // Trigger a console.log in the page (classic executeScript).
    d.execute_script("console.log('bidi-hello');", vec![]).unwrap();

    // Drain the matching log.entryAdded event; it must carry our text.
    let ev = d
        .bidi()
        .unwrap()
        .next_event(BidiEvent::LOG_ENTRY_ADDED, 8000)
        .unwrap()
        .expect("a log.entryAdded event within the timeout");
    assert_eq!(
        ev.get("method").and_then(|v| v.as_str()),
        Some(BidiEvent::LOG_ENTRY_ADDED),
        "event method matches: {ev:?}"
    );
    let serialized = format!("{ev:?}");
    assert!(serialized.contains("bidi-hello"), "logged text present in event: {serialized}");

    // A plain BiDi command round-trip: session.status -> success.
    let status = d.bidi().unwrap().command("session.status", json::obj(vec![]), 10000).unwrap();
    assert_eq!(
        status.get("type").and_then(|v| v.as_str()),
        Some("success"),
        "session.status reply: {status:?}"
    );

    // ---- typed BiDi convenience verbs (getTree / script.evaluate) ----

    // top_context resolves to the top-level browsing context id.
    let ctx = d.bidi().unwrap().top_context(10000).unwrap();
    assert!(ctx.is_some(), "top_context should be Some, got {ctx:?}");

    // script.evaluate a plain expression -> a BiDi number value of 42.
    let v = d.bidi().unwrap().evaluate_value("6*7", 30000).unwrap();
    assert_eq!(v.and_then(|j| j.as_f64()), Some(42.0), "evaluate_value(6*7) should be 42");

    // script.evaluate a promise -> the awaited value is 42 (promise-await).
    let p = d.bidi().unwrap().evaluate_value("Promise.resolve(41+1)", 30000).unwrap();
    assert_eq!(
        p.and_then(|j| j.as_f64()),
        Some(42.0),
        "evaluate_value(Promise.resolve(41+1)) should await to 42"
    );

    // ---- BiDi network interception (add intercept -> pause -> continue) ----

    // Subscribe to the paused-request phase, then intercept all requests at it.
    let sub = d.bidi().unwrap().subscribe(&[BidiEvent::BEFORE_REQUEST_SENT]).unwrap();
    assert_eq!(
        sub.get("type").and_then(|v| v.as_str()),
        Some("success"),
        "beforeRequestSent subscribe ack: {sub:?}"
    );
    let intercept = d.bidi().unwrap().add_intercept("beforeRequestSent", "", 10000).unwrap();
    assert!(intercept.is_some(), "add_intercept should return an intercept id, got {intercept:?}");

    // Trigger a request; it will pause at beforeRequestSent (caught catch swallows
    // the eventual failure/abort so executeScript doesn't throw).
    d.execute_script("fetch('https://example.com/blocked').catch(()=>{});", vec![]).unwrap();

    // The paused-request event must arrive and carry a request id.
    let ev = d
        .bidi()
        .unwrap()
        .next_event(BidiEvent::BEFORE_REQUEST_SENT, 8000)
        .unwrap()
        .expect("a network.beforeRequestSent event within the timeout");
    let rid = selenium_core::BiDi::event_request_id(&ev)
        .expect("beforeRequestSent event should carry params.request.request");

    // Release the paused request; the reply must be a success.
    let cont = d.bidi().unwrap().continue_request(&rid, 10000).unwrap();
    assert_eq!(
        cont.get("type").and_then(|v| v.as_str()),
        Some("success"),
        "continue_request reply: {cont:?}"
    );

    // ---- BiDi request mocking (provide_response fulfills a paused request) ----

    // A fresh fetch that pauses at beforeRequestSent; the caught catch keeps
    // executeScript from throwing while the request is held.
    d.execute_script(
        "window.__mock='';fetch('https://example.com/api').then(r=>r.text()).then(t=>{window.__mock=t}).catch(()=>{});",
        vec![],
    )
    .unwrap();

    let ev2 = d
        .bidi()
        .unwrap()
        .next_event(BidiEvent::BEFORE_REQUEST_SENT, 8000)
        .unwrap()
        .expect("a network.beforeRequestSent event for the mocked fetch");
    let rid2 = selenium_core::BiDi::event_request_id(&ev2)
        .expect("beforeRequestSent event should carry params.request.request");

    // Fulfill it with a mock body; the reply must be a success.
    let mock = d
        .bidi()
        .unwrap()
        .provide_response(&rid2, 200, "text/plain", "MOCKED-BODY", 10000)
        .unwrap();
    assert_eq!(
        mock.get("type").and_then(|v| v.as_str()),
        Some("success"),
        "provide_response reply: {mock:?}"
    );

    // The fetch resolves in-page with the mocked body; poll until it lands.
    let mut got = String::new();
    for _ in 0..25 {
        let v = d.execute_script("return window.__mock;", vec![]).unwrap();
        got = v.as_str().unwrap_or("").to_string();
        if got.contains("MOCKED-BODY") {
            break;
        }
        thread::sleep(Duration::from_millis(200));
    }
    assert!(got.contains("MOCKED-BODY"), "fetch should see the mocked body, got {got:?}");

    // ---- BiDi cache behavior (network.setCacheBehavior: bypass / default) ----

    // Disable the HTTP cache session-wide, then restore it; both replies succeed.
    let bypass = d.bidi().unwrap().set_cache_behavior("bypass", 10000).unwrap();
    assert_eq!(
        bypass.get("type").and_then(|v| v.as_str()),
        Some("success"),
        "set_cache_behavior(bypass) reply: {bypass:?}"
    );
    let default = d.bidi().unwrap().set_cache_behavior("default", 10000).unwrap();
    assert_eq!(
        default.get("type").and_then(|v| v.as_str()),
        Some("success"),
        "set_cache_behavior(default) reply: {default:?}"
    );

    // continue_with_auth needs a real auth-challenging server to exercise; here we
    // only pin its signature so it stays compiled (never actually called).
    #[allow(unused)]
    fn _continue_with_auth_compiles(bidi: &mut selenium_core::BiDi) {
        let _ = bidi.continue_with_auth("req-1", "user", "pass", 10000);
    }

    d.quit().unwrap();
}

/// A LIVE test of the atom-backed commands against real Chrome: isDisplayed,
/// the classic getAttribute (property-or-attribute atom), and relative locators.
/// Mirrors the `live_chrome_surface` fixture (own chromedriver on an ephemeral
/// port, self-skip if chromedriver absent, a data: URL for a real document).
#[test]
fn live_atoms() {
    let Some(driver_bin) = which("chromedriver") else {
        eprintln!("SKIPPED: chromedriver not on PATH");
        return;
    };

    let cd_port = free_port();
    let cd = Command::new(&driver_bin)
        .arg(format!("--port={cd_port}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn chromedriver");
    let _guard = DriverGuard(cd);

    if !wait_up(cd_port, Duration::from_secs(10)) {
        eprintln!("SKIPPED: chromedriver did not come up");
        return;
    }

    let d = WebDriver::headless_chrome(&format!("http://127.0.0.1:{cd_port}")).expect("new session");

    d.get(concat!(
        "data:text/html,<!doctype html><title>atoms</title>",
        "<h1 id='hdr'>Header</h1>",
        "<button id='btn'>press</button>",
        "<p id='gone' style='display:none'>hidden</p>",
        "<a id='lnk' href='https://example.com/x'>link</a>"
    ))
    .unwrap();

    // isDisplayed atom: a visible header, a display:none paragraph.
    assert!(d.find_element(By::ID, "hdr").unwrap().is_displayed().unwrap(), "#hdr should be displayed");
    assert!(!d.find_element(By::ID, "gone").unwrap().is_displayed().unwrap(), "#gone should be hidden");

    // getAttribute atom: the href resolves to the absolute URL.
    let href = d.find_element(By::ID, "lnk").unwrap().get_attribute("href").unwrap();
    assert!(href.as_deref().unwrap_or("").contains("example.com/x"), "href atom: {href:?}");

    // relative locators: a <button> positioned below the #hdr anchor.
    let below = d
        .find_relative("button", &[json::obj(vec![("kind", json::s("below")), ("sel", json::s("#hdr"))])])
        .unwrap();
    assert!(!below.is_empty(), "expected a button below #hdr, got {}", below.len());
    assert_eq!(below[0].tag_name().unwrap().to_lowercase(), "button");

    d.quit().unwrap();
}

/// Driver orchestration over the engine: resolve + spawn a chromedriver
/// in-binding (NO chromedriver on PATH, no Grid), drive a page through the
/// self-launched driver, and tear the process down — the ensure_driver ->
/// driver_url -> open -> stop flow the C ABI exposes for FFI bindings. Mirrors
/// the Python `test_live_driver_orchestration`.
#[test]
fn driver_orchestration() {
    use selenium_core::{ensure_driver, resolve_driver, DriverProcess};

    // Resolve only — self-skip loudly if the engine can't produce a driver here
    // (offline + empty cache). Same self-skip the other live tests use.
    let path = resolve_driver("chrome", "").unwrap();
    if path.is_empty() {
        eprintln!("SKIPPED: engine cannot resolve a chromedriver (offline, no cache)");
        return;
    }
    assert!(
        std::path::Path::new(&path).is_file(),
        "resolve_driver returned a non-file: {path:?}"
    );
    println!("  ok: resolve_driver -> {path}");

    // ensure_driver spawns it; the handle exposes url + pid, independent of any
    // W3C session.
    let mut proc: DriverProcess = ensure_driver("chrome", "", 15000)
        .unwrap()
        .expect("ensure_driver should spawn a chromedriver");
    let url = proc.url().unwrap();
    assert!(url.starts_with("http"), "driver url={url:?}");
    assert!(proc.pid() > 0, "driver pid={}", proc.pid());
    println!("  ok: ensure_driver -> pid {} at {url}", proc.pid());

    proc.stop();
    assert_eq!(proc.pid(), 0, "stop() should clear the handle");
    println!("  ok: stop terminated the process");

    // local_chrome ties it together: spawn its own driver, run a session, and
    // stop the driver on quit — the whole point of the orchestration ABI.
    let mut chrome_args = vec![
        json::s("--headless=new"),
        json::s("--no-sandbox"),
        json::s("--disable-gpu"),
        json::s("--disable-dev-shm-usage"),
    ];
    let mut chrome_opts = vec![("args", Json::Arr(std::mem::take(&mut chrome_args)))];
    if let Ok(bin) = std::env::var("SEL_CHROME_BINARY") {
        if !bin.is_empty() {
            chrome_opts.push(("binary", json::s(&bin)));
        }
    }
    let options = json::obj(vec![("goog:chromeOptions", json::obj(chrome_opts))]);

    let page = concat!(
        "data:text/html,<!doctype html><title>Aether Selenium</title>",
        "<h1 id='hdr'>Hello</h1>"
    );
    let d = WebDriver::local_chrome(Some(options), "", 15000, Default::default())
        .expect("local_chrome should spawn its own driver and open a session");
    assert!(!d.session_id().is_empty(), "no session id from local_chrome");
    d.get(page).unwrap();
    assert_eq!(d.title().unwrap(), "Aether Selenium", "title mismatch");
    assert_eq!(d.find_element(By::ID, "hdr").unwrap().text().unwrap(), "Hello");
    println!("PASS: live driver-orchestration test green (self-spawned driver)");
    d.quit().unwrap();
}

/// Minimal std-only base64 decoder (screenshot PNG check only).
fn base64_decode(s: &str) -> Vec<u8> {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut lut = [255u8; 256];
    for (i, &c) in T.iter().enumerate() {
        lut[c as usize] = i as u8;
    }
    let mut out = Vec::new();
    let mut buf = 0u32;
    let mut bits = 0;
    for &c in s.as_bytes() {
        if c == b'=' || c == b'\n' || c == b'\r' {
            continue;
        }
        let v = lut[c as usize];
        if v == 255 {
            continue;
        }
        buf = (buf << 6) | v as u32;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
        }
    }
    out
}
