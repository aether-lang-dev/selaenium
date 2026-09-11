//! No-browser FFI test: proves the Rust binding links libselenium_core.so and
//! marshals correctly, exercising the pure engine helpers and the transport
//! error path. The .so is found via the build.rs link search + rpath.

use selenium::{error_code, locator, route, By, ErrorKind, WebDriver};

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
fn test_shadow_routes_and_error_codes() {
    assert_eq!(route("getShadowRoot"), "GET /session/:sessionId/element/:id/shadow");
    assert_eq!(route("findElementFromShadowRoot"), "POST /session/:sessionId/shadow/:id/element");
    assert_eq!(route("findElementsFromShadowRoot"), "POST /session/:sessionId/shadow/:id/elements");
    assert_eq!(error_code("no such shadow root"), 19);
    assert_eq!(error_code("detached shadow root"), 2);
}

// Compile-surface check: WebElement::shadow_root yields a ShadowRoot, itself a
// search context with find_element/find_elements. Never called — proves the
// signatures are declared and typecheck (no browser).
#[allow(dead_code)]
fn _shadow_surface_compiles(el: &selenium::WebElement, by: By) {
    let root: selenium::ShadowRoot = el.shadow_root().unwrap();
    let _one: selenium::WebElement = root.find_element(by.clone()).unwrap();
    let _many: Vec<selenium::WebElement> = root.find_elements(by).unwrap();
    let _id: &str = root.id();
}

#[test]
fn test_locator_css() {
    let by = By::css("div.foo");
    assert_eq!(locator(by.strategy, &by.value), r#"{"using":"css selector","value":"div.foo"}"#);
}

#[test]
fn test_locator_id_rewrite() {
    let by = By::id("main");
    assert_eq!(locator(by.strategy, &by.value), r#"{"using":"css selector","value":"*[id=\"main\"]"}"#);
}

#[test]
fn test_transport_failure() {
    let err = WebDriver::chrome("http://127.0.0.1:1", None).unwrap_err();
    assert_eq!(err.code, -1);
    assert_eq!(err.kind, ErrorKind::Transport);
}

// Compile-surface check: the per-browser factories (and their _tls / headless
// variants) are declared with the chrome shape. Never called — proves the
// signatures typecheck (no browser). Edge on Linux and Safari on macOS-only
// mean these are not live-runnable here, so a surface check is the coverage.
#[allow(dead_code)]
fn _browser_factories_compile() {
    let _ = WebDriver::firefox("http://127.0.0.1:1", None);
    let _ = WebDriver::firefox_tls("http://127.0.0.1:1", None, Default::default());
    let _ = WebDriver::headless_firefox("http://127.0.0.1:1");
    let _ = WebDriver::edge("http://127.0.0.1:1", None);
    let _ = WebDriver::edge_tls("http://127.0.0.1:1", None, Default::default());
    let _ = WebDriver::headless_edge("http://127.0.0.1:1");
    let _ = WebDriver::safari("http://127.0.0.1:1", None);
    let _ = WebDriver::safari_tls("http://127.0.0.1:1", None, Default::default());
}
