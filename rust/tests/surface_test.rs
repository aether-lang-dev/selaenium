//! Compile-time surface guard for the Rust binding — the STANDALONE-FFI
//! reference bar every other standalone-FFI binding (dart, nim, go, zig, lua,
//! crystal, haskell, swift, erlang, elixir, julia) is measured against.
//!
//! This file references every public WebDriver *feature* method so that
//! removing or renaming one breaks the build. It is the drift guard: the bar
//! cannot silently shrink. Nothing here is called against a browser — the
//! references live in `#[allow(dead_code)]` functions and `if false { ... }`
//! blocks that only need to *typecheck*, exactly the style of the compile-surface
//! checks already in `ffi_test.rs` (`_shadow_surface_compiles`,
//! `_browser_factories_compile`).
//!
//! Scope note: this guards the user-facing WebDriver feature surface. Pure
//! idiomatic-Rust helpers that leak into a `pub fn` grep — the `json` accessors
//! (`as_str`/`as_bool`/`as_array`/`as_f64`/`get`/`encode`), the `json`
//! constructors (`obj`/`s`/`n`/`parse`), and `By` field access — are Rust
//! plumbing, not feature-bar methods, so a sibling binding is NOT expected to
//! reproduce them by name. They are exercised elsewhere (json unit tests) and
//! are intentionally not asserted here as feature methods.

#![allow(dead_code, unused_variables, unreachable_code, clippy::diverging_sub_expression)]

use std::time::Duration;

use selenium::{
    ensure_driver, error_code, launch_driver, locator, resolve_driver, serve_runner_background, By,
    Frame, Json, Keys, Select, TlsConfig, WebDriver, WebElement,
};

// ---- By: the eight locator strategies ----
fn _by_strategies() {
    let _: fn(&'static str) -> By = By::id;
    let _: fn(&'static str) -> By = By::name;
    let _: fn(&'static str) -> By = By::css;
    let _: fn(&'static str) -> By = By::class_name;
    let _: fn(&'static str) -> By = By::tag_name;
    let _: fn(&'static str) -> By = By::link_text;
    let _: fn(&'static str) -> By = By::partial_link_text;
    let _: fn(&'static str) -> By = By::xpath;
}

// ---- pure engine helpers (protocol/route/error mapping) ----
fn _pure_helpers() {
    let _: fn(&str) -> String = locator_wrap;
    let _r: fn(&str) -> String = selenium::route;
    let _e: fn(&str) -> i32 = error_code;
}
fn locator_wrap(_: &str) -> String {
    locator("id", "x")
}

// ---- driver orchestration (resolve / ensure / launch / stop / DriverProcess) ----
fn _orchestration() {
    let _resolve: fn(&str, &str) -> selenium::Result<String> = resolve_driver;
    let _launch: fn(&str, i32) -> selenium::Result<Option<selenium::DriverProcess>> = launch_driver;
    let _ensure: fn(&str, &str, i32) -> selenium::Result<Option<selenium::DriverProcess>> =
        ensure_driver;
    if false {
        let mut p: selenium::DriverProcess = launch_driver("x", 1).unwrap().unwrap();
        let _u: selenium::Result<String> = p.url();
        let _pid: i32 = p.pid();
        p.stop();
    }
}

// ---- browser factories, TLS variants, headless variants, local_chrome ----
fn _factories() {
    let _: fn(&str, Option<Json>) -> selenium::Result<WebDriver> = WebDriver::chrome;
    let _: fn(&str, Option<Json>, TlsConfig) -> selenium::Result<WebDriver> = WebDriver::chrome_tls;
    let _: fn(&str) -> selenium::Result<WebDriver> = WebDriver::headless_chrome;
    let _: fn(&str, Option<Json>) -> selenium::Result<WebDriver> = WebDriver::firefox;
    let _: fn(&str, Option<Json>, TlsConfig) -> selenium::Result<WebDriver> = WebDriver::firefox_tls;
    let _: fn(&str) -> selenium::Result<WebDriver> = WebDriver::headless_firefox;
    let _: fn(&str, Option<Json>) -> selenium::Result<WebDriver> = WebDriver::edge;
    let _: fn(&str, Option<Json>, TlsConfig) -> selenium::Result<WebDriver> = WebDriver::edge_tls;
    let _: fn(&str) -> selenium::Result<WebDriver> = WebDriver::headless_edge;
    let _: fn(&str, Option<Json>) -> selenium::Result<WebDriver> = WebDriver::safari;
    let _: fn(&str, Option<Json>, TlsConfig) -> selenium::Result<WebDriver> = WebDriver::safari_tls;
    let _: fn(Option<Json>, &str, i32, TlsConfig) -> selenium::Result<WebDriver> =
        WebDriver::local_chrome;
    // TlsConfig builder: ca_path / insecure.
    let t = TlsConfig::default().ca_path("/x").insecure(true);
    let _ = t;
}

// ---- WebDriver: navigation, windows, frames, alerts, cookies, timeouts, etc. ----
fn _driver_surface(d: &mut WebDriver) {
    if false {
        // navigation
        let _: selenium::Result<()> = d.get("u");
        let _: selenium::Result<String> = d.current_url();
        let _: selenium::Result<String> = d.title();
        let _: selenium::Result<String> = d.page_source();
        let _: selenium::Result<()> = d.back();
        let _: selenium::Result<()> = d.forward();
        let _: selenium::Result<()> = d.refresh();

        // finding
        let _: selenium::Result<WebElement> = d.find_element(By::id("x"));
        let _: selenium::Result<Vec<WebElement>> = d.find_elements(By::id("x"));
        let _: selenium::Result<bool> = d.exists(By::id("x"));
        let _: selenium::Result<WebElement> = d.active_element();
        let _: selenium::Result<Vec<WebElement>> = d.find_relative("css", &[]);
        let _: selenium::Result<usize> = d.find_relative_count("css", &[]);

        // scripts
        let _: selenium::Result<Json> = d.execute_script("s", vec![]);
        let _: selenium::Result<Json> = d.execute_async_script("s", vec![]);

        // windows
        let _: selenium::Result<Vec<String>> = d.window_handles();
        let _: selenium::Result<String> = d.current_window_handle();
        let _: selenium::Result<()> = d.switch_to_window("h");
        let _: selenium::Result<Json> = d.set_window_rect(Json::Null);
        let _: selenium::Result<Json> = d.get_window_rect();
        let _: selenium::Result<Json> = d.maximize_window();
        let _: selenium::Result<Json> = d.minimize_window();
        let _: selenium::Result<Json> = d.fullscreen_window();
        let _: selenium::Result<String> = d.new_window("tab");
        let _: selenium::Result<Vec<String>> = d.close_window();

        // frames
        let _: selenium::Result<()> = d.switch_to_frame(Frame::Index(0));
        let _: selenium::Result<()> = d.switch_to_parent_frame();
        let _: selenium::Result<()> = d.switch_to_default_content();

        // alerts
        let _: selenium::Result<()> = d.accept_alert();
        let _: selenium::Result<()> = d.dismiss_alert();
        let _: selenium::Result<String> = d.alert_text();
        let _: selenium::Result<()> = d.send_alert_text("t");
        let _: selenium::Result<bool> = d.alert_present();

        // cookies
        let _: selenium::Result<()> = d.add_cookie(Json::Null);
        let _: selenium::Result<Json> = d.get_cookies();
        let _: selenium::Result<Json> = d.get_cookie("n");
        let _: selenium::Result<()> = d.delete_cookie("n");
        let _: selenium::Result<()> = d.delete_all_cookies();

        // actions
        let _: selenium::Actions = d.actions();
        let _: selenium::Result<()> = d.perform_actions(vec![]);
        let _: selenium::Result<()> = d.clear_actions();

        // timeouts
        let _: selenium::Result<()> = d.set_timeouts(Json::Null);
        let _: selenium::Result<()> = d.set_page_load_timeout(1);
        let _: selenium::Result<()> = d.set_script_timeout(1);
        let _: selenium::Result<()> = d.implicitly_wait(1);

        // capture
        let _: selenium::Result<String> = d.screenshot_base64();
        let _: selenium::Result<String> = d.print_pdf(None);

        // session/bidi
        let _: String = d.session_id();
        let _: bool = d.bidi_available();
        let _: selenium::Result<&mut selenium::BiDi> = d.bidi();

        // interactive console / IDE tier
        let _: selenium::Result<Json> = d.shell("open");
        let _: selenium::Result<selenium::Runner> = d.runner();
        let _: selenium::Result<selenium::Bridge> = d.bridge();
        let _: i32 = d.serve_runner(0);
        let _: selenium::Result<Json> = d.play_side("{}");
        let _: selenium::RunnerServer = serve_runner_background(d, 0);
    }
}

// ---- WebElement ----
fn _element_surface(e: &WebElement) {
    if false {
        let _: &str = e.id();
        let _: selenium::Result<()> = e.click();
        let _: selenium::Result<()> = e.clear();
        let _: selenium::Result<()> = e.send_keys("t");
        let _: selenium::Result<String> = e.text();
        let _: selenium::Result<String> = e.tag_name();
        let _: selenium::Result<bool> = e.is_displayed();
        let _: selenium::Result<Option<String>> = e.get_attribute("a");
        let _: selenium::Result<Json> = e.get_dom_attribute("a");
        let _: selenium::Result<Json> = e.get_property("p");
        let _: selenium::Result<bool> = e.is_enabled();
        let _: selenium::Result<bool> = e.is_selected();
        let _: selenium::Result<Json> = e.rect();
        let _: selenium::Result<String> = e.css_value("c");
        let _: selenium::Result<String> = e.value_of_css_property("c");
        let _: selenium::Result<String> = e.screenshot_base64();
        let _: selenium::Result<()> = e.submit();
        let _: selenium::Result<WebElement> = e.find_element(By::id("x"));
        let _: selenium::Result<Vec<WebElement>> = e.find_elements(By::id("x"));
        let _: selenium::Result<selenium::ShadowRoot> = e.shadow_root();
    }
}

// ---- Actions verbs (fluent builder) ----
fn _actions_surface(a: selenium::Actions, el: &WebElement) {
    let _ = a
        .move_to_element(el)
        .click(Some(el))
        .context_click(None)
        .double_click(None)
        .click_and_hold(None)
        .release(None)
        .drag_and_drop(el, el)
        .key_down('a')
        .key_up('a')
        .send_keys("x")
        .pause(1);
    // terminal verbs
    fn _terminal(a: selenium::Actions) -> selenium::Result<()> {
        let _built: Vec<Json> = a.build();
        a.perform()
    }
}

// ---- Select methods ----
fn _select_surface(s: &Select) {
    if false {
        let _: bool = s.is_multiple();
        let _: selenium::Result<Vec<WebElement>> = s.options();
        let _: selenium::Result<Vec<WebElement>> = s.all_selected_options();
        let _: selenium::Result<WebElement> = s.first_selected_option();
        let _: selenium::Result<()> = s.select_by_visible_text("t");
        let _: selenium::Result<()> = s.select_by_value("v");
        let _: selenium::Result<()> = s.select_by_index(0);
        let _: selenium::Result<()> = s.deselect_all();
    }
    // Select::new constructor.
    fn _ctor<'a>(e: &'a WebElement<'a>) -> selenium::Result<Select<'a>> {
        Select::new(e)
    }
}

// ---- Wait conditions ----
fn _wait_surface(d: &WebDriver) {
    if false {
        let w = d.wait(Duration::from_secs(1)).poll_every(Duration::from_millis(10));
        let _: selenium::Result<()> = w.until(|_| Ok(true));
        let _: selenium::Result<()> = w.until_not(|_| Ok(false));

        let _: selenium::Result<WebElement> = d.wait_for_element(By::id("x"), Duration::ZERO);
        let _: selenium::Result<WebElement> = d.wait_for_visible(By::id("x"), Duration::ZERO);
        let _: selenium::Result<WebElement> = d.wait_for_clickable(By::id("x"), Duration::ZERO);
        let _: selenium::Result<()> = d.wait_until_gone(By::id("x"), Duration::ZERO);
        let _: selenium::Result<()> = d.wait_for_title_is("t", Duration::ZERO);
        let _: selenium::Result<()> = d.wait_for_title_contains("t", Duration::ZERO);
        let _: selenium::Result<()> = d.wait_for_url_is("u", Duration::ZERO);
        let _: selenium::Result<()> = d.wait_for_url_contains("u", Duration::ZERO);
    }
}

// ---- Keys constants + chord ----
fn _keys_surface() {
    let _: char = Keys::ENTER;
    let _: char = Keys::CONTROL;
    let _: char = Keys::NULL;
    let _: String = Keys::chord(Keys::CONTROL, "a");
}

// ---- BiDi surface ----
fn _bidi_surface(b: &mut selenium::BiDi) {
    if false {
        let _: selenium::Result<Json> = b.subscribe(&["e"]);
        let _: selenium::Result<Json> = b.subscribe_timeout(&["e"], 1);
        let _: selenium::Result<Json> = b.unsubscribe(&["e"]);
        let _: selenium::Result<Json> = b.unsubscribe_timeout(&["e"], 1);
        let _: selenium::Result<Option<Json>> = b.next_event("m", 1);
        let _: selenium::Result<Json> = b.command("m", Json::Null, 1);
        let _: selenium::Result<Json> = b.get_tree(1);
        let _: selenium::Result<Option<String>> = b.top_context(1);
        let _: selenium::Result<Json> = b.evaluate("e", 1);
        let _: selenium::Result<Option<Json>> = b.evaluate_value("e", 1);
        let _: selenium::Result<Json> = b.navigate("u", 1);
        let _: selenium::Result<Option<String>> = b.add_intercept("beforeRequestSent", "*", 1);
        let _: selenium::Result<Json> = b.remove_intercept("id", 1);
        let _: selenium::Result<Json> = b.continue_request("rid", 1);
        let _: selenium::Result<Json> = b.fail_request("rid", 1);
        let _: selenium::Result<Json> = b.provide_response("rid", 200, "text/html", "body", 1);
        let _: selenium::Result<Json> = b.continue_with_auth("rid", "u", "p", 1);
        let _: selenium::Result<Json> = b.set_cache_behavior("default", 1);
        let _: i32 = b.lost_events();
    }
    let _evt_id: fn(&Json) -> Option<String> = selenium::BiDi::event_request_id;
}

// ---- Runner / Bridge (interactive console controllers) ----
fn _runner_surface(r: &mut selenium::Runner) {
    let _: Json = r.send("m", None);
    let _: Json = r.eval("l");
    let _: Json = r.mode("m");
    let _: Json = r.step();
    let _: Json = r.cont();
    let _: Json = r.inspect("w");
    let _: Option<Json> = r.next_event();
}
fn _bridge_surface(b: &mut selenium::Bridge) {
    let _: selenium::Result<()> = b.inject();
    let _: i32 = b.pump();
    let _: selenium::Result<()> = b.serve(1, || true);
}
fn _runner_server_surface(rs: &selenium::RunnerServer) {
    let _: i32 = rs.port();
    let _: String = rs.url();
    let _: String = rs.ws_url();
}

// A real (compiled AND run) assertion so the file is a live test target, not
// only a typecheck. The pure route/error helpers are browser-free.
#[test]
fn surface_pure_helpers_resolve() {
    assert_eq!(selenium::route("get"), "POST /session/:sessionId/url");
    assert_eq!(error_code("no such element"), 17);
    assert_eq!(Keys::ENTER as u32, 0xE007);
    let by = By::css("div");
    assert_eq!(locator(by.strategy, &by.value), r#"{"using":"css selector","value":"div"}"#);
}
