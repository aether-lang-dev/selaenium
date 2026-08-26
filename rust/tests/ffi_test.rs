//! No-browser FFI test: proves the Rust binding links libselenium_core.so and
//! marshals correctly, exercising the pure engine helpers and the transport
//! error path. The .so is found via the build.rs link search + rpath.

use selenium_core::{error_code, locator, route, By, ErrorKind, WebDriver};

#[test]
fn test_route() {
    assert_eq!(route("get"), "POST /session/:sessionId/url");
    assert_eq!(route("nope"), "");
}

#[test]
fn test_error_code() {
    assert_eq!(error_code("no such element"), 17);
    assert_eq!(error_code(""), 0);
}

#[test]
fn test_locator_css() {
    assert_eq!(locator(By::CSS, "div.foo"), r#"{"using":"css selector","value":"div.foo"}"#);
}

#[test]
fn test_locator_id_rewrite() {
    assert_eq!(locator(By::ID, "main"), r#"{"using":"css selector","value":"*[id=\"main\"]"}"#);
}

#[test]
fn test_transport_failure() {
    let err = WebDriver::chrome("http://127.0.0.1:1", None).unwrap_err();
    assert_eq!(err.code, -1);
    assert_eq!(err.kind, ErrorKind::Transport);
}
