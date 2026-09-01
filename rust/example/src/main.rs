//! Third-party consumer example: depends on the selenium-core crate and drives
//! the protocol. The engine .so is linked via the crate's own bundled native/
//! dir (build.rs) — no SELENIUM_CORE_LIB, and the packaged crate copy has no
//! core/ sibling, so only the bundled .so can satisfy the link/rpath.
//!
//! Modes (argv[1]): ffi | live.

use std::net::{TcpListener, TcpStream};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use selenium::{error_code, route, By, ErrorKind, WebDriver};

fn fail(msg: &str) -> ! {
    eprintln!("FAIL: {msg}");
    std::process::exit(1);
}

fn mode_ffi() {
    if std::env::var("SELENIUM_CORE_LIB").map(|v| !v.is_empty()).unwrap_or(false) {
        fail("SELENIUM_CORE_LIB is set; consumer must run without it");
    }
    if route("get") != "POST /session/:sessionId/url" {
        fail("route mismatch");
    }
    if error_code("no such element") != 17 {
        fail("error_code mismatch");
    }
    match WebDriver::chrome("http://127.0.0.1:1", None) {
        Ok(_) => fail("expected transport failure"),
        Err(e) if e.kind == ErrorKind::Transport => {}
        Err(e) => fail(&format!("wrong error kind: {:?}", e.kind)),
    }
    println!("consumer(ffi): OK — bundled crate linked its own .so via build.rs rpath");
}

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
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}

fn mode_live() {
    let Some(driver_bin) = which("chromedriver") else {
        println!("consumer(live): SKIPPED — chromedriver not on PATH");
        return;
    };
    let port = free_port();
    let mut cd = Command::new(&driver_bin)
        .arg(format!("--port={port}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn chromedriver");
    let result = (|| {
        if !wait_up(port, Duration::from_secs(10)) {
            println!("consumer(live): SKIPPED — chromedriver did not come up");
            return;
        }
        let d = WebDriver::headless_chrome(&format!("http://127.0.0.1:{port}")).expect("session");
        let html = "<!doctype html><title>Installed</title><h1 id=\"h\">Hi</h1>";
        let url = format!("data:text/html;charset=utf-8,{}", urlencode(html));
        d.get(&url).unwrap();
        if d.title().unwrap() != "Installed" {
            fail("title mismatch");
        }
        if d.find_element(By::id("h")).unwrap().text().unwrap() != "Hi" {
            fail("text mismatch");
        }
        d.quit().unwrap();
        println!("consumer(live): OK — bundled crate drove real headless Chrome");
    })();
    let _ = cd.kill();
    let _ = cd.wait();
    result
}

fn urlencode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn main() {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "ffi".to_string());
    match mode.as_str() {
        "ffi" => mode_ffi(),
        "live" => mode_live(),
        other => fail(&format!("unknown mode: {other}")),
    }
}
