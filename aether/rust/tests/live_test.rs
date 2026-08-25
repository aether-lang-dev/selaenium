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

use selenium_core::{json, By, ErrorKind, Json, WebDriver};

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
