//! Selenium WebDriver for Rust, re-glued to the shared pure-Aether WebDriver
//! core. The entire W3C protocol — command catalog, route table, path
//! templating, By normalization, error decode, and the HTTP round-trip — lives
//! in and is maintained as the in-repo Aether engine (`core/selenium_core.ae`),
//! exposed via the `aether_sel_embed_*` C ABI (`core/embed.ae`). This crate
//! carries NO protocol logic; it links the one `libselenium_core.so` at build
//! time (see build.rs) and marshals strings/JSON across the boundary.
//!
//! ```no_run
//! use selenium::{WebDriver, By};
//! let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
//! d.get("https://example.com").unwrap();
//! println!("{}", d.title().unwrap());
//! d.find_element(By::css("a")).unwrap().click().unwrap();
//! d.quit().unwrap();
//! ```

use std::ffi::{c_char, c_int, c_void, CStr, CString};

pub mod json;
pub use json::Json;

pub mod actions;
pub mod keys;
pub mod select;
pub mod wait;
pub use actions::Actions;
pub use keys::Keys;
pub use select::Select;
pub use wait::Wait;

// ---- the C ABI (aether_sel_embed_*), linked at build time ----
type Handle = *mut c_void;

// last_status is part of the ABI surface but not yet exposed through the
// ergonomic API; keep the declaration for completeness.
#[allow(dead_code)]
extern "C" {
    fn aether_sel_embed_open(base_url: *const c_char) -> Handle;
    fn aether_sel_embed_close(h: Handle);
    fn aether_sel_embed_execute(h: Handle, name: *const c_char, params_json: *const c_char) -> c_int;
    fn aether_sel_embed_last_value(h: Handle) -> *mut c_char;
    fn aether_sel_embed_last_status(h: Handle) -> c_int;
    fn aether_sel_embed_last_error_code(h: Handle) -> c_int;
    fn aether_sel_embed_last_error(h: Handle) -> *mut c_char;
    fn aether_sel_embed_session_id(h: Handle) -> *mut c_char;
    fn aether_sel_embed_by_locator(strategy: *const c_char, value: *const c_char) -> *mut c_char;
    fn aether_sel_embed_route(name: *const c_char) -> *mut c_char;
    fn aether_sel_embed_build_request(name: *const c_char, session_id: *const c_char, params_json: *const c_char) -> *mut c_char;
    fn aether_sel_embed_error_code(w3c_error: *const c_char) -> c_int;
    fn aether_sel_embed_free_string(s: *mut c_char);

    // ---- TLS config (per session handle; set before newSession) ----
    fn aether_sel_embed_set_ca(h: Handle, ca_path: *const c_char);
    fn aether_sel_embed_set_insecure(h: Handle, on: c_int);

    // ---- driver orchestration (spawn/adopt a driver process in-binding) ----
    // An opaque driver handle, independent of the W3C session handle.
    fn aether_sel_embed_resolve_driver(browser: *const c_char, hint: *const c_char) -> *mut c_char;
    fn aether_sel_embed_launch_driver(driver_path: *const c_char, timeout_ms: c_int) -> Handle;
    fn aether_sel_embed_ensure_driver(browser: *const c_char, hint: *const c_char, timeout_ms: c_int) -> Handle;
    fn aether_sel_embed_driver_url(dh: Handle) -> *mut c_char;
    fn aether_sel_embed_driver_pid(dh: Handle) -> c_int;
    fn aether_sel_embed_stop_driver(dh: Handle);

    // ---- atom-backed commands (run a shared JS atom in-page via the engine) ----
    fn aether_sel_embed_execute_atom(h: Handle, atom: *const c_char, elem_id: *const c_char, extra_json: *const c_char) -> c_int;
    fn aether_sel_embed_is_displayed(h: Handle, elem_id: *const c_char) -> c_int;
    fn aether_sel_embed_get_attribute(h: Handle, elem_id: *const c_char, name: *const c_char) -> c_int;
    fn aether_sel_embed_atom_str_arg(s: *const c_char) -> *mut c_char;
    fn aether_sel_embed_find_relative(h: Handle, base_css: *const c_char, filters_json: *const c_char) -> c_int;

    // ---- WebDriver-BiDi (over the session's webSocketUrl) ----
    // An opaque BiDi channel handle, independent of the W3C session handle.
    fn aether_sel_embed_bidi_open(ws_url: *const c_char) -> Handle;
    fn aether_sel_embed_bidi_close(h: Handle);
    fn aether_sel_embed_bidi_send(h: Handle, id: c_int, method: *const c_char, params_json: *const c_char) -> c_int;
    fn aether_sel_embed_bidi_pump(h: Handle, timeout_ms: c_int) -> c_int;
    fn aether_sel_embed_bidi_fd(h: Handle) -> c_int;
    fn aether_sel_embed_bidi_poll_reply(h: Handle, id: c_int) -> *mut c_char;
    fn aether_sel_embed_bidi_poll_event(h: Handle) -> *mut c_char;
    fn aether_sel_embed_bidi_lost_events(h: Handle) -> c_int;
    fn aether_sel_embed_bidi_cancel(h: Handle, id: c_int);
    fn aether_sel_embed_bidi_subscribe(h: Handle, id: c_int, events_csv: *const c_char, timeout_ms: c_int) -> *mut c_char;
    fn aether_sel_embed_bidi_unsubscribe(h: Handle, id: c_int, events_csv: *const c_char, timeout_ms: c_int) -> *mut c_char;
    fn aether_sel_embed_bidi_wait_event(h: Handle, method: *const c_char, timeout_ms: c_int) -> *mut c_char;

    // ---- typed BiDi convenience verbs (each returns a BiDi reply JSON) ----
    fn aether_sel_embed_bidi_get_tree(h: Handle, id: c_int, timeout_ms: c_int) -> *mut c_char;
    fn aether_sel_embed_bidi_script_evaluate(
        h: Handle,
        id: c_int,
        expr: *const c_char,
        context_id: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_navigate(
        h: Handle,
        id: c_int,
        context_id: *const c_char,
        url: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;

    // ---- BiDi network interception (each returns a BiDi reply JSON) ----
    fn aether_sel_embed_bidi_network_add_intercept(
        h: Handle,
        id: c_int,
        phases_csv: *const c_char,
        url_pattern: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_network_remove_intercept(
        h: Handle,
        id: c_int,
        intercept_id: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_network_continue_request(
        h: Handle,
        id: c_int,
        request_id: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_network_fail_request(
        h: Handle,
        id: c_int,
        request_id: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_network_provide_response(
        h: Handle,
        id: c_int,
        request_id: *const c_char,
        status: c_int,
        content_type: *const c_char,
        body: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_network_continue_with_auth(
        h: Handle,
        id: c_int,
        request_id: *const c_char,
        username: *const c_char,
        password: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
    fn aether_sel_embed_bidi_network_set_cache_behavior(
        h: Handle,
        id: c_int,
        behavior: *const c_char,
        timeout_ms: c_int,
    ) -> *mut c_char;
}

/// Copy a caller-owned native `char*` into a Rust `String`, then free it per the
/// ABI ownership rule. Returns "" for NULL.
fn take_string(ptr: *mut c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    // SAFETY: the ABI guarantees a NUL-terminated, caller-owned buffer.
    unsafe {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        aether_sel_embed_free_string(ptr);
        s
    }
}

fn cstr(s: &str) -> CString {
    CString::new(s).unwrap_or_else(|_| CString::new("").unwrap())
}

// ---- errors ----

/// A WebDriver protocol error carrying the engine's stable W3C error code
/// (0 = success, -1 = transport failure) and its category.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WebDriverError {
    pub code: i32,
    pub message: String,
    pub kind: ErrorKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    Transport,
    NoSuchElement,
    StaleElementReference,
    ElementClickIntercepted,
    ElementNotInteractable,
    InvalidSelector,
    Timeout,
    Javascript,
    UnknownCommand,
    Other,
}

impl WebDriverError {
    fn classify(code: i32, message: String) -> Self {
        let kind = match code {
            -1 => ErrorKind::Transport,
            3 => ErrorKind::ElementClickIntercepted,
            4 => ErrorKind::ElementNotInteractable,
            11 => ErrorKind::InvalidSelector,
            13 => ErrorKind::Javascript,
            17 => ErrorKind::NoSuchElement,
            21 | 24 => ErrorKind::Timeout,
            23 => ErrorKind::StaleElementReference,
            28 => ErrorKind::UnknownCommand,
            _ => ErrorKind::Other,
        };
        WebDriverError { code, message, kind }
    }
}

impl std::fmt::Display for WebDriverError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} (code {})", self.message, self.code)
    }
}
impl std::error::Error for WebDriverError {}

pub type Result<T> = std::result::Result<T, WebDriverError>;

// ---- By ----

/// A locator: a (strategy, value) pair built by a `By::*` constructor and passed
/// to [`WebDriver::find_element`] / [`WebDriver::find_elements`]. The strategy
/// strings match the engine's by_locator strings; id/name/"class name" are
/// rewritten to CSS in the engine.
///
/// Mirrors Selenium's Java By-factory shape (`By.id("x")` -> a locator; one-arg
/// `findElement`) in Rust idiom:
///
/// ```no_run
/// # use selenium::{WebDriver, By};
/// # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
/// let el = d.find_element(By::id("hdr")).unwrap();
/// let nav = d.find_elements(By::class_name("nav")).unwrap();
/// ```
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct By {
    pub strategy: &'static str,
    pub value: String,
}

impl By {
    pub fn id(value: impl Into<String>) -> By {
        By { strategy: "id", value: value.into() }
    }
    pub fn name(value: impl Into<String>) -> By {
        By { strategy: "name", value: value.into() }
    }
    pub fn css(value: impl Into<String>) -> By {
        By { strategy: "css selector", value: value.into() }
    }
    pub fn class_name(value: impl Into<String>) -> By {
        By { strategy: "class name", value: value.into() }
    }
    pub fn tag_name(value: impl Into<String>) -> By {
        By { strategy: "tag name", value: value.into() }
    }
    pub fn link_text(value: impl Into<String>) -> By {
        By { strategy: "link text", value: value.into() }
    }
    pub fn partial_link_text(value: impl Into<String>) -> By {
        By { strategy: "partial link text", value: value.into() }
    }
    pub fn xpath(value: impl Into<String>) -> By {
        By { strategy: "xpath", value: value.into() }
    }
}

// ---- Frame ----

/// A frame target for [`WebDriver::switch_to_frame`]. The W3C `switchToFrame`
/// command's `id` may be an unsigned index, a frame element reference, or `null`
/// (return to the top-level context) — this enum makes those three shapes
/// explicit rather than overloading one stringly-typed argument.
///
/// ```no_run
/// # use selenium::{WebDriver, By, Frame};
/// # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
/// d.switch_to_frame(Frame::Index(0)).unwrap();
/// // or, by the frame's <iframe> element:
/// let f = d.find_element(By::css("iframe")).unwrap();
/// d.switch_to_frame(Frame::from(&f)).unwrap();
/// d.switch_to_default_content().unwrap();
/// ```
#[derive(Debug, Clone)]
pub enum Frame {
    /// The frame at this 0-based index among the current context's child frames.
    Index(u16),
    /// The frame whose `<iframe>`/`<frame>` element has this W3C element id.
    Element(String),
    /// The top-level browsing context (equivalent to
    /// [`WebDriver::switch_to_default_content`]).
    Default,
}

impl Frame {
    /// The W3C `id` value for this frame target: a number, an element-reference
    /// object, or JSON null.
    fn id_json(&self) -> Json {
        match self {
            Frame::Index(i) => json::n(*i as f64),
            Frame::Element(id) => json::obj(vec![(W3C_ELEMENT_KEY, json::s(id))]),
            Frame::Default => Json::Null,
        }
    }
}

impl<'a> From<&WebElement<'a>> for Frame {
    fn from(e: &WebElement<'a>) -> Frame {
        Frame::Element(e.id().to_string())
    }
}

// ---- pure engine helpers (no session) ----

/// The "METHOD PATH" route for a command name, or "" if unknown.
pub fn route(command: &str) -> String {
    let c = cstr(command);
    take_string(unsafe { aether_sel_embed_route(c.as_ptr()) })
}

/// Map a W3C error string to its stable integer code (0 = success).
pub fn error_code(w3c_error: &str) -> i32 {
    let c = cstr(w3c_error);
    unsafe { aether_sel_embed_error_code(c.as_ptr()) }
}

/// The W3C {"using","value"} locator JSON for a (by, value) pair.
pub fn locator(by: &str, value: &str) -> String {
    let bc = cstr(by);
    let vc = cstr(value);
    take_string(unsafe { aether_sel_embed_by_locator(bc.as_ptr(), vc.as_ptr()) })
}

fn decode_by(by: &By) -> Json {
    json::parse(&locator(by.strategy, &by.value)).unwrap_or(Json::Null)
}

pub(crate) const W3C_ELEMENT_KEY: &str = "element-6066-11e4-a52e-4f735466cecf";

// ---- TLS ----

/// TLS trust configuration for a session, applied on the handle before
/// `newSession`. Defaults to the platform trust store with verification on.
#[derive(Debug, Clone, Default)]
pub struct TlsConfig {
    /// Path to a private-CA bundle to trust (e.g. a self-signed Grid's CA).
    pub ca_path: Option<String>,
    /// Skip TLS verification entirely (trust the host out-of-band). Dev/staging
    /// only.
    pub insecure: bool,
}

impl TlsConfig {
    /// Trust the CA bundle at `path` (chainable).
    pub fn ca_path(mut self, path: impl Into<String>) -> Self {
        self.ca_path = Some(path.into());
        self
    }
    /// Skip TLS verification entirely (chainable). Dev/staging only.
    pub fn insecure(mut self, on: bool) -> Self {
        self.insecure = on;
        self
    }
}

// ---- WebDriver ----

/// A WebDriver session over the shared engine.
#[derive(Debug)]
pub struct WebDriver {
    handle: Handle,
    // The negotiated BiDi endpoint (value.capabilities.webSocketUrl), or "" if
    // the remote end granted none. The channel is opened lazily on first use.
    ws_url: String,
    bidi: Option<BiDi>,
    // A driver process owned by this session (populated by `local_chrome`): the
    // engine-spawned chromedriver, stopped when this WebDriver is dropped —
    // after the session `quit`, since drop order is declaration order.
    driver: Option<DriverProcess>,
}

// The handle is a plain pointer into the engine; sessions are used from one
// thread at a time in these bindings.
unsafe impl Send for WebDriver {}

impl WebDriver {
    /// Start a Chrome session against a running chromedriver (or Grid). `options`
    /// is a JSON object of extra capabilities merged under browserName: chrome.
    pub fn chrome(command_executor: &str, options: Option<Json>) -> Result<WebDriver> {
        WebDriver::chrome_tls(command_executor, options, TlsConfig::default())
    }

    /// Like [`WebDriver::chrome`], but with TLS trust configuration applied on
    /// the session handle before `newSession` (pin a private-CA bundle via
    /// [`TlsConfig::ca_path`], or skip verification entirely via
    /// [`TlsConfig::insecure`] for a self-signed dev/staging Grid).
    pub fn chrome_tls(command_executor: &str, options: Option<Json>, tls: TlsConfig) -> Result<WebDriver> {
        let mut caps = match options {
            Some(Json::Obj(m)) => Json::Obj(m),
            _ => json::obj(vec![]),
        };
        if let Json::Obj(ref mut m) = caps {
            m.insert("browserName".into(), json::s("chrome"));
        }
        WebDriver::new(command_executor, caps, tls)
    }

    /// Convenience: headless-Chrome launch args baked in.
    pub fn headless_chrome(command_executor: &str) -> Result<WebDriver> {
        let opts = json::obj(vec![(
            "goog:chromeOptions",
            json::obj(vec![(
                "args",
                Json::Arr(vec![
                    json::s("--headless=new"),
                    json::s("--no-sandbox"),
                    json::s("--disable-gpu"),
                    json::s("--disable-dev-shm-usage"),
                ]),
            )]),
        )]);
        WebDriver::chrome(command_executor, Some(opts))
    }

    fn new(command_executor: &str, mut capabilities: Json, tls: TlsConfig) -> Result<WebDriver> {
        let cu = cstr(command_executor);
        let handle = unsafe { aether_sel_embed_open(cu.as_ptr()) };
        if handle.is_null() {
            return Err(WebDriverError::classify(-1, "failed to open session handle".into()));
        }
        // TLS trust config must land on the handle BEFORE newSession (the first
        // request). ca_path pins a private-CA bundle; insecure skips verification
        // entirely (self-signed dev/staging Grid — trust the host out-of-band).
        if let Some(ca) = tls.ca_path.as_deref() {
            let c = cstr(ca);
            unsafe { aether_sel_embed_set_ca(handle, c.as_ptr()) };
        }
        if tls.insecure {
            unsafe { aether_sel_embed_set_insecure(handle, 1) };
        }
        // Request a BiDi channel so `.bidi()` is available on demand; the channel
        // itself is opened lazily (a classic script never opens the WebSocket).
        if let Json::Obj(ref mut m) = capabilities {
            m.insert("webSocketUrl".into(), Json::Bool(true));
        }
        let mut d = WebDriver { handle, ws_url: String::new(), bidi: None, driver: None };
        let payload = json::obj(vec![(
            "capabilities",
            json::obj(vec![("alwaysMatch", capabilities)]),
        )]);
        let result = d.execute("newSession", payload)?;
        // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
        d.ws_url = result
            .get("capabilities")
            .and_then(|c| c.get("webSocketUrl"))
            .and_then(|u| u.as_str())
            .unwrap_or("")
            .to_string();
        Ok(d)
    }

    /// The FFI seam: one command by name with JSON params. Returns the decoded
    /// `value` payload (or Json::Null), or a typed error.
    fn execute(&self, command: &str, params: Json) -> Result<Json> {
        let name = cstr(command);
        let pj = cstr(&params.encode());
        let rc = unsafe { aether_sel_embed_execute(self.handle, name.as_ptr(), pj.as_ptr()) };
        if rc != 0 {
            let code = unsafe { aether_sel_embed_last_error_code(self.handle) };
            let message = take_string(unsafe { aether_sel_embed_last_error(self.handle) });
            if rc == -1 && code == 0 {
                let m = if message.is_empty() { "transport failure".into() } else { message };
                return Err(WebDriverError::classify(-1, m));
            }
            return Err(WebDriverError::classify(code, message));
        }
        let raw = take_string(unsafe { aether_sel_embed_last_value(self.handle) });
        if raw.is_empty() {
            return Ok(Json::Null);
        }
        json::parse(&raw).map_err(|e| WebDriverError::classify(1, format!("bad response JSON: {e}")))
    }

    // ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

    /// Drain the last_value after an atom call, mapping rc != 0 to a typed error
    /// exactly as [`WebDriver::execute`] does. Returns the decoded value (or
    /// Json::Null when the atom produced no value).
    fn atom_result(&self, rc: c_int) -> Result<Json> {
        if rc != 0 {
            let code = unsafe { aether_sel_embed_last_error_code(self.handle) };
            let message = take_string(unsafe { aether_sel_embed_last_error(self.handle) });
            if rc == -1 && code == 0 {
                let m = if message.is_empty() { "transport failure".into() } else { message };
                return Err(WebDriverError::classify(-1, m));
            }
            return Err(WebDriverError::classify(code, message));
        }
        let raw = take_string(unsafe { aether_sel_embed_last_value(self.handle) });
        if raw.is_empty() {
            return Ok(Json::Null);
        }
        json::parse(&raw).map_err(|e| WebDriverError::classify(1, format!("bad atom JSON: {e}")))
    }

    /// Relative locators: elements matching `base_css` filtered by spatial
    /// relation to anchors, nearest first. Each filter is a JSON object
    /// `{"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"}`
    /// (`near` also accepts `"dist"`). Returns the matching elements.
    pub fn find_relative(&self, base_css: &str, filters: &[Json]) -> Result<Vec<WebElement>> {
        let base = cstr(base_css);
        let fj = cstr(&Json::Arr(filters.to_vec()).encode());
        let rc = unsafe { aether_sel_embed_find_relative(self.handle, base.as_ptr(), fj.as_ptr()) };
        let result = self.atom_result(rc)?;
        let refs = result.as_array().cloned().unwrap_or_default();
        refs.iter().map(|r| self.element_from(r)).collect()
    }

    /// The NUMBER of elements a relative-locator query matches, without
    /// materializing [`WebElement`] handles — the count-only counterpart to
    /// [`find_relative`](WebDriver::find_relative) (mirrors the reference
    /// `find_relative_count`). Filters have the same shape as `find_relative`.
    pub fn find_relative_count(&self, base_css: &str, filters: &[Json]) -> Result<usize> {
        let base = cstr(base_css);
        let fj = cstr(&Json::Arr(filters.to_vec()).encode());
        let rc = unsafe { aether_sel_embed_find_relative(self.handle, base.as_ptr(), fj.as_ptr()) };
        let result = self.atom_result(rc)?;
        Ok(result.as_array().map(|a| a.len()).unwrap_or(0))
    }

    // ---- navigation ----
    pub fn get(&self, url: &str) -> Result<()> {
        self.execute("get", json::obj(vec![("url", json::s(url))]))?;
        Ok(())
    }
    pub fn current_url(&self) -> Result<String> {
        Ok(self.execute("getCurrentUrl", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    pub fn title(&self) -> Result<String> {
        Ok(self.execute("getTitle", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    pub fn page_source(&self) -> Result<String> {
        Ok(self.execute("getPageSource", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    pub fn back(&self) -> Result<()> {
        self.execute("goBack", json::obj(vec![]))?;
        Ok(())
    }
    pub fn forward(&self) -> Result<()> {
        self.execute("goForward", json::obj(vec![]))?;
        Ok(())
    }
    pub fn refresh(&self) -> Result<()> {
        self.execute("refresh", json::obj(vec![]))?;
        Ok(())
    }

    // ---- elements ----
    pub fn find_element(&self, by: By) -> Result<WebElement> {
        let result = self.execute("findElement", decode_by(&by))?;
        self.element_from(&result)
    }
    pub fn find_elements(&self, by: By) -> Result<Vec<WebElement>> {
        let result = self.execute("findElements", decode_by(&by))?;
        let arr = result.as_array().cloned().unwrap_or_default();
        arr.iter().map(|e| self.element_from(e)).collect()
    }
    fn element_from(&self, v: &Json) -> Result<WebElement> {
        let id = v
            .get(W3C_ELEMENT_KEY)
            .and_then(|x| x.as_str())
            .ok_or_else(|| WebDriverError::classify(17, "element reference key missing".into()))?;
        Ok(WebElement { driver: self, id: id.to_string() })
    }

    /// True if at least one element matching `by` is present RIGHT NOW — an
    /// immediate presence check with no implicit wait. Spells the intent "is
    /// this here?" distinctly from [`find_element`], whose `NoSuchElement` error
    /// you would otherwise match on. Pairs with the [`wait`](crate::wait) module:
    /// use `exists` for a snapshot, [`Wait`] to block until present.
    ///
    /// A transport-level failure still surfaces as `Err`; only a clean
    /// element-not-found resolves to `Ok(false)`.
    ///
    /// [`find_element`]: WebDriver::find_element
    pub fn exists(&self, by: By) -> Result<bool> {
        match self.find_element(by) {
            Ok(_) => Ok(true),
            Err(e) if e.kind == ErrorKind::NoSuchElement => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// The active (focused) element (`getActiveElement`) — the element that would
    /// receive keyboard input, e.g. after a `send_keys` or a programmatic focus.
    pub fn active_element(&self) -> Result<WebElement> {
        let result = self.execute("getActiveElement", json::obj(vec![]))?;
        self.element_from(&result)
    }

    // ---- script ----
    pub fn execute_script(&self, script: &str, args: Vec<Json>) -> Result<Json> {
        self.execute("executeScript", json::obj(vec![("script", json::s(script)), ("args", Json::Arr(args))]))
    }
    /// Run an async script: the page signals completion via the injected
    /// callback (`arguments[arguments.length - 1]`). Returns the callback value.
    pub fn execute_async_script(&self, script: &str, args: Vec<Json>) -> Result<Json> {
        self.execute("executeAsyncScript", json::obj(vec![("script", json::s(script)), ("args", Json::Arr(args))]))
    }

    // ---- windows ----
    pub fn window_handles(&self) -> Result<Vec<String>> {
        let v = self.execute("getWindowHandles", json::obj(vec![]))?;
        Ok(v.as_array().cloned().unwrap_or_default().iter().filter_map(|e| e.as_str().map(String::from)).collect())
    }
    pub fn current_window_handle(&self) -> Result<String> {
        Ok(self.execute("getCurrentWindowHandle", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    /// Switch the session's top-level browsing context to the window `handle`.
    pub fn switch_to_window(&self, handle: &str) -> Result<()> {
        self.execute("switchToWindow", json::obj(vec![("handle", json::s(handle))]))?;
        Ok(())
    }
    pub fn set_window_rect(&self, rect: Json) -> Result<Json> {
        self.execute("setWindowRect", rect)
    }
    pub fn get_window_rect(&self) -> Result<Json> {
        self.execute("getWindowRect", json::obj(vec![]))
    }
    /// Maximize the current window. Returns the resulting window rect.
    pub fn maximize_window(&self) -> Result<Json> {
        self.execute("maximizeWindow", json::obj(vec![]))
    }
    /// Minimize (hide) the current window. Returns the resulting window rect.
    pub fn minimize_window(&self) -> Result<Json> {
        self.execute("minimizeWindow", json::obj(vec![]))
    }
    /// Put the current window into fullscreen. Returns the resulting window rect.
    pub fn fullscreen_window(&self) -> Result<Json> {
        self.execute("fullscreenWindow", json::obj(vec![]))
    }

    /// Open a new top-level browsing context (`newWindow`). `type_hint` is
    /// `"tab"` or `"window"` (a hint the browser may honor or ignore). Returns
    /// the new window's handle — pass it to [`switch_to_window`] to focus it.
    /// Returns `""` only if the remote end sent no handle.
    ///
    /// [`switch_to_window`]: WebDriver::switch_to_window
    pub fn new_window(&self, type_hint: &str) -> Result<String> {
        let v = self.execute("newWindow", json::obj(vec![("type", json::s(type_hint))]))?;
        Ok(v.get("handle").and_then(|h| h.as_str()).unwrap_or("").to_string())
    }

    /// Close the current window/tab (`close`). Returns the window handles that
    /// remain; when it empties, the session is gone — switch to a surviving
    /// handle before issuing further commands. Note this does NOT end the
    /// session (use [`quit`] for that).
    ///
    /// [`quit`]: WebDriver::quit
    pub fn close_window(&self) -> Result<Vec<String>> {
        let v = self.execute("close", json::obj(vec![]))?;
        Ok(v.as_array().cloned().unwrap_or_default().iter().filter_map(|e| e.as_str().map(String::from)).collect())
    }

    // ---- frames ----

    /// Switch the session's focus to a frame (`switchToFrame`): by
    /// [`Frame::Index`], by [`Frame::Element`] (or `Frame::from(&webelement)`),
    /// or [`Frame::Default`] for the top-level context. All subsequent element
    /// commands run inside the chosen frame until the next frame switch.
    pub fn switch_to_frame(&self, frame: Frame) -> Result<()> {
        self.execute("switchToFrame", json::obj(vec![("id", frame.id_json())]))?;
        Ok(())
    }

    /// Switch to the parent of the current frame (`switchToFrameParent`) — one
    /// level out, unlike [`switch_to_default_content`] which jumps to the top.
    ///
    /// [`switch_to_default_content`]: WebDriver::switch_to_default_content
    pub fn switch_to_parent_frame(&self) -> Result<()> {
        self.execute("switchToFrameParent", json::obj(vec![]))?;
        Ok(())
    }

    /// Return focus to the top-level browsing context (`switchToFrame` with a
    /// null id) — equivalent to `switch_to_frame(Frame::Default)`.
    pub fn switch_to_default_content(&self) -> Result<()> {
        self.switch_to_frame(Frame::Default)
    }

    // ---- alerts ----
    /// Accept (OK) the current user-prompt / alert dialog.
    pub fn accept_alert(&self) -> Result<()> {
        self.execute("acceptAlert", json::obj(vec![]))?;
        Ok(())
    }
    /// Dismiss (Cancel) the current user-prompt / alert dialog.
    pub fn dismiss_alert(&self) -> Result<()> {
        self.execute("dismissAlert", json::obj(vec![]))?;
        Ok(())
    }
    /// The message text of the current dialog.
    pub fn alert_text(&self) -> Result<String> {
        Ok(self.execute("getAlertText", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    /// Type `text` into the current prompt dialog's input field.
    pub fn send_alert_text(&self, text: &str) -> Result<()> {
        self.execute("setAlertValue", json::obj(vec![("text", json::s(text))]))?;
        Ok(())
    }
    /// True if a user-prompt / alert dialog is currently present (probing it via
    /// `getAlertText`). A clean "no such alert" resolves to `Ok(false)`; a
    /// transport-level failure still surfaces as `Err`. Pairs with
    /// [`Wait`](crate::Wait) for the "block until an alert appears" case.
    pub fn alert_present(&self) -> Result<bool> {
        match self.execute("getAlertText", json::obj(vec![])) {
            Ok(_) => Ok(true),
            // 15 = "no such alert" (none open). Other codes (e.g. 28 unknown
            // command) are real failures and propagate.
            Err(e) if e.code == 15 => Ok(false),
            Err(e) => Err(e),
        }
    }

    // ---- cookies ----
    pub fn add_cookie(&self, cookie: Json) -> Result<()> {
        self.execute("addCookie", json::obj(vec![("cookie", cookie)]))?;
        Ok(())
    }
    pub fn get_cookies(&self) -> Result<Json> {
        self.execute("getCookies", json::obj(vec![]))
    }
    pub fn get_cookie(&self, name: &str) -> Result<Json> {
        self.execute("getCookie", json::obj(vec![("name", json::s(name))]))
    }
    pub fn delete_cookie(&self, name: &str) -> Result<()> {
        self.execute("deleteCookie", json::obj(vec![("name", json::s(name))]))?;
        Ok(())
    }
    pub fn delete_all_cookies(&self) -> Result<()> {
        self.execute("deleteAllCookies", json::obj(vec![]))?;
        Ok(())
    }

    // ---- actions ----

    /// Start a fluent [`Actions`] builder bound to this driver: queue pointer /
    /// key gestures, then `.perform()`. See the [`actions`](crate::actions)
    /// module.
    pub fn actions(&self) -> Actions<'_> {
        Actions::new(self)
    }

    pub fn perform_actions(&self, actions: Vec<Json>) -> Result<()> {
        self.execute("actions", json::obj(vec![("actions", Json::Arr(actions))]))?;
        Ok(())
    }
    pub fn clear_actions(&self) -> Result<()> {
        self.execute("clearActions", json::obj(vec![]))?;
        Ok(())
    }

    // ---- timeouts ----
    pub fn set_timeouts(&self, timeouts: Json) -> Result<()> {
        self.execute("setTimeout", timeouts)?;
        Ok(())
    }
    /// Set the page-load timeout (ms): how long navigation may take before
    /// timing out.
    pub fn set_page_load_timeout(&self, ms: i64) -> Result<()> {
        self.execute("setTimeout", json::obj(vec![("pageLoad", json::n(ms as f64))]))?;
        Ok(())
    }
    /// Set the script timeout (ms): how long `execute_async_script` may run
    /// before timing out.
    pub fn set_script_timeout(&self, ms: i64) -> Result<()> {
        self.execute("setTimeout", json::obj(vec![("script", json::n(ms as f64))]))?;
        Ok(())
    }
    /// Set the implicit wait (ms): how long `find_element` retries before failing.
    pub fn implicitly_wait(&self, ms: i64) -> Result<()> {
        self.execute("setTimeout", json::obj(vec![("implicit", json::n(ms as f64))]))?;
        Ok(())
    }

    // ---- screenshots ----
    pub fn screenshot_base64(&self) -> Result<String> {
        Ok(self.execute("screenshot", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }

    /// Print the current page to PDF (`printPage`), returning the PDF as a
    /// base64 string. `options` is the W3C print-options object (page size,
    /// margins, orientation, scale, `pageRanges`, …); pass [`None`] for defaults.
    ///
    /// ```no_run
    /// # use selenium::WebDriver;
    /// # let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
    /// let pdf_b64 = d.print_pdf(None).unwrap();
    /// ```
    pub fn print_pdf(&self, options: Option<Json>) -> Result<String> {
        let params = match options {
            Some(o @ Json::Obj(_)) => o,
            _ => json::obj(vec![]),
        };
        Ok(self.execute("printPage", params)?.as_str().unwrap_or("").to_string())
    }

    // ---- lifecycle ----
    pub fn session_id(&self) -> String {
        take_string(unsafe { aether_sel_embed_session_id(self.handle) })
    }
    pub fn quit(mut self) -> Result<()> {
        // Close the BiDi channel first, then end the session.
        self.bidi = None;
        let r = self.execute("quit", json::obj(vec![]));
        // Dropping self closes the handle.
        r.map(|_| ())
    }

    // ---- WebDriver-BiDi ----

    /// True if this session negotiated a webSocketUrl (BiDi usable).
    pub fn bidi_available(&self) -> bool {
        !self.ws_url.is_empty()
    }

    /// The event-driven BiDi surface for this session, opened lazily over the
    /// negotiated webSocketUrl. Errors if the remote end granted no BiDi URL.
    ///
    /// ```no_run
    /// # use selenium::{WebDriver, BidiEvent};
    /// # let mut d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
    /// d.bidi().unwrap().subscribe(&[BidiEvent::LOG_ENTRY_ADDED]).unwrap();
    /// d.get("https://example.com").unwrap();
    /// let ev = d.bidi().unwrap().next_event(BidiEvent::LOG_ENTRY_ADDED, 5000).unwrap();
    /// ```
    pub fn bidi(&mut self) -> Result<&mut BiDi> {
        if self.bidi.is_none() {
            if self.ws_url.is_empty() {
                return Err(WebDriverError::classify(
                    0,
                    "BiDi not available: the session negotiated no webSocketUrl".into(),
                ));
            }
            let url = cstr(&self.ws_url);
            let handle = unsafe { aether_sel_embed_bidi_open(url.as_ptr()) };
            if handle.is_null() {
                return Err(WebDriverError::classify(-1, "BiDi channel failed to open".into()));
            }
            self.bidi = Some(BiDi { handle, next_id: 1 });
        }
        Ok(self.bidi.as_mut().unwrap())
    }
}

impl Drop for WebDriver {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe { aether_sel_embed_close(self.handle) };
            self.handle = std::ptr::null_mut();
        }
    }
}

// ---- driver orchestration (spawn / adopt a driver process in-binding) --------
// The engine can resolve, download-or-cache, and launch a browser driver process
// itself — so a caller needs neither a driver on PATH nor a running Grid. These
// wrap the driver-handle C ABI (independent of the W3C session handle).

/// Resolve the local driver binary path for `browser` without launching it
/// (detect/download/cache as needed). `hint` pins a version or path; `""`
/// auto-detects. Returns `""` if none resolvable (offline, no cache).
pub fn resolve_driver(browser: &str, hint: &str) -> Result<String> {
    let b = cstr(browser);
    let h = cstr(hint);
    Ok(take_string(unsafe { aether_sel_embed_resolve_driver(b.as_ptr(), h.as_ptr()) }))
}

/// A driver process launched by the engine. Owns the opaque driver handle; call
/// [`DriverProcess::stop`] (or let it drop) to terminate the process.
#[derive(Debug)]
pub struct DriverProcess {
    handle: Handle,
}

// The handle is a plain pointer into the engine; used from one thread at a time.
unsafe impl Send for DriverProcess {}

impl DriverProcess {
    /// The base URL the driver is listening on — pass to [`WebDriver::chrome`].
    pub fn url(&self) -> Result<String> {
        if self.handle.is_null() {
            return Ok(String::new());
        }
        Ok(take_string(unsafe { aether_sel_embed_driver_url(self.handle) }))
    }

    /// The driver process id (0 if not running / stopped).
    pub fn pid(&self) -> i32 {
        if self.handle.is_null() {
            return 0;
        }
        unsafe { aether_sel_embed_driver_pid(self.handle) }
    }

    /// Terminate the driver process and clear the handle (idempotent).
    pub fn stop(&mut self) {
        if !self.handle.is_null() {
            unsafe { aether_sel_embed_stop_driver(self.handle) };
            self.handle = std::ptr::null_mut();
        }
    }
}

impl Drop for DriverProcess {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Launch a driver at an explicit binary path. Returns a running
/// [`DriverProcess`], or `None` if it did not come up within `timeout_ms`.
pub fn launch_driver(driver_path: &str, timeout_ms: i32) -> Result<Option<DriverProcess>> {
    let p = cstr(driver_path);
    let h = unsafe { aether_sel_embed_launch_driver(p.as_ptr(), timeout_ms) };
    Ok(if h.is_null() { None } else { Some(DriverProcess { handle: h }) })
}

/// Resolve (detect/download/cache) AND launch a driver for `browser` in one
/// step. Returns a running [`DriverProcess`], or `None` if none could be
/// resolved/launched within `timeout_ms`.
pub fn ensure_driver(browser: &str, hint: &str, timeout_ms: i32) -> Result<Option<DriverProcess>> {
    let b = cstr(browser);
    let hn = cstr(hint);
    let h = unsafe { aether_sel_embed_ensure_driver(b.as_ptr(), hn.as_ptr(), timeout_ms) };
    Ok(if h.is_null() { None } else { Some(DriverProcess { handle: h }) })
}

impl WebDriver {
    /// A Chrome session that spawns its own chromedriver via the engine — no
    /// driver on PATH, no Grid. The driver process is owned by the returned
    /// [`WebDriver`] and stopped when it is quit or dropped.
    ///
    /// `options` is a JSON object of extra capabilities merged under
    /// `browserName: chrome`; `hint` pins a driver version/path (`""`
    /// auto-detects); `tls` configures trust for the (loopback) driver.
    ///
    /// ```no_run
    /// # use selenium::WebDriver;
    /// let d = WebDriver::local_chrome(None, "", 15000, Default::default()).unwrap();
    /// d.get("https://example.com").unwrap();
    /// d.quit().unwrap();
    /// ```
    pub fn local_chrome(
        options: Option<Json>,
        hint: &str,
        timeout_ms: i32,
        tls: TlsConfig,
    ) -> Result<WebDriver> {
        let proc = ensure_driver("chrome", hint, timeout_ms)?
            .ok_or_else(|| WebDriverError::classify(-1, "could not resolve/launch chromedriver".into()))?;
        let url = proc.url()?;
        let mut d = WebDriver::chrome_tls(&url, options, tls)?;
        d.driver = Some(proc);
        Ok(d)
    }
}

// ---- WebElement ----

/// A remote element handle. Methods issue element-scoped commands, passing this
/// element's id as the `:id` path parameter.
#[derive(Debug)]
pub struct WebElement<'a> {
    driver: &'a WebDriver,
    id: String,
}

impl<'a> WebElement<'a> {
    pub fn id(&self) -> &str {
        &self.id
    }

    fn exec(&self, command: &str, mut params: Json) -> Result<Json> {
        if let Json::Obj(ref mut m) = params {
            m.insert("id".into(), json::s(&self.id));
        } else {
            params = json::obj(vec![("id", json::s(&self.id))]);
        }
        self.driver.execute(command, params)
    }

    pub fn click(&self) -> Result<()> {
        self.exec("clickElement", json::obj(vec![]))?;
        Ok(())
    }
    pub fn clear(&self) -> Result<()> {
        self.exec("clearElement", json::obj(vec![]))?;
        Ok(())
    }
    pub fn send_keys(&self, text: &str) -> Result<()> {
        let chars: Vec<Json> = text.chars().map(|c| json::s(&c.to_string())).collect();
        self.exec("sendKeysToElement", json::obj(vec![("text", json::s(text)), ("value", Json::Arr(chars))]))?;
        Ok(())
    }
    pub fn text(&self) -> Result<String> {
        Ok(self.exec("getElementText", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    pub fn tag_name(&self) -> Result<String> {
        Ok(self.exec("getElementTagName", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    /// Whether the element is shown (the isDisplayed atom, run in-page by the
    /// engine — the visibility algorithm, not a naive style check).
    pub fn is_displayed(&self) -> Result<bool> {
        let eid = cstr(&self.id);
        let rc = unsafe { aether_sel_embed_is_displayed(self.driver.handle, eid.as_ptr()) };
        Ok(self.driver.atom_result(rc)?.as_bool().unwrap_or(false))
    }

    /// The classic getAttribute(name): property-or-attribute (boolean attrs,
    /// live properties like value/checked), via the shared engine atom. Returns
    /// `None` when the attribute is absent (JSON null). Use [`get_dom_attribute`]
    /// for the raw W3C DOM attribute.
    ///
    /// [`get_dom_attribute`]: WebElement::get_dom_attribute
    pub fn get_attribute(&self, name: &str) -> Result<Option<String>> {
        let eid = cstr(&self.id);
        let nm = cstr(name);
        let rc = unsafe { aether_sel_embed_get_attribute(self.driver.handle, eid.as_ptr(), nm.as_ptr()) };
        Ok(self.driver.atom_result(rc)?.as_str().map(String::from))
    }

    /// The literal DOM attribute (W3C getDomAttribute), no property fallback.
    pub fn get_dom_attribute(&self, name: &str) -> Result<Json> {
        self.exec("getDomAttribute", json::obj(vec![("name", json::s(name))]))
    }
    pub fn get_property(&self, name: &str) -> Result<Json> {
        self.exec("getElementProperty", json::obj(vec![("name", json::s(name))]))
    }
    pub fn is_enabled(&self) -> Result<bool> {
        Ok(self.exec("isElementEnabled", json::obj(vec![]))?.as_bool().unwrap_or(false))
    }
    pub fn is_selected(&self) -> Result<bool> {
        Ok(self.exec("isElementSelected", json::obj(vec![]))?.as_bool().unwrap_or(false))
    }
    pub fn rect(&self) -> Result<Json> {
        self.exec("getElementRect", json::obj(vec![]))
    }

    /// The computed value of the CSS property `prop` on this element
    /// (`getElementValueOfCssProperty`) — e.g. `"display"`, `"color"`,
    /// `"font-size"`. Aliased as [`value_of_css_property`] for parity with the
    /// classic Selenium name.
    ///
    /// [`value_of_css_property`]: WebElement::value_of_css_property
    pub fn css_value(&self, prop: &str) -> Result<String> {
        Ok(self
            .exec("getElementValueOfCssProperty", json::obj(vec![("name", json::s(prop))]))?
            .as_str()
            .unwrap_or("")
            .to_string())
    }

    /// Classic-Selenium-named alias of [`css_value`](WebElement::css_value).
    pub fn value_of_css_property(&self, prop: &str) -> Result<String> {
        self.css_value(prop)
    }

    /// A PNG screenshot of just this element (`takeElementScreenshot`), returned
    /// as a base64 string — the element-scoped counterpart to
    /// [`WebDriver::screenshot_base64`].
    pub fn screenshot_base64(&self) -> Result<String> {
        Ok(self.exec("takeElementScreenshot", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }

    /// Submit the form this element belongs to. W3C WebDriver removed the
    /// dedicated `submit` endpoint, so — like the reference binding and modern
    /// Selenium — this walks up to the enclosing `<form>` and calls
    /// `requestSubmit()` (falling back to `submit()`) via an injected script.
    /// Errors (kind `NoSuchElement`) if the element is not inside a form.
    pub fn submit(&self) -> Result<()> {
        // arguments[0] is this element; find its owning form and submit it the
        // way a real user gesture would (requestSubmit fires validation + the
        // submit event; submit() is the legacy fallback for older engines).
        const SCRIPT: &str = "var e=arguments[0];var f=e.form||e.closest('form');\
if(!f){throw new Error('Element is not within a form');}\
if(f.requestSubmit){f.requestSubmit();}else{f.submit();}";
        let arg = json::obj(vec![(W3C_ELEMENT_KEY, json::s(&self.id))]);
        self.driver.execute_script(SCRIPT, vec![arg]).map(|_| ())
    }

    /// Find one descendant of this element matching `by` (element-scoped
    /// `findChildElement`). The returned element is tied to the same driver
    /// borrow as this one.
    pub fn find_element(&self, by: By) -> Result<WebElement<'a>> {
        let result = self.exec("findChildElement", decode_by(&by))?;
        self.driver.element_from(&result)
    }

    /// Find all descendants of this element matching `by` (element-scoped
    /// `findChildElements`). Used by [`Select`] to enumerate `<option>` children.
    pub fn find_elements(&self, by: By) -> Result<Vec<WebElement<'a>>> {
        let result = self.exec("findChildElements", decode_by(&by))?;
        let arr = result.as_array().cloned().unwrap_or_default();
        arr.iter().map(|e| self.driver.element_from(e)).collect()
    }
}

// ---- WebDriver-BiDi ----

/// The common WebDriver-BiDi event names (W3C spec). Pass to
/// [`BiDi::subscribe`] and match in [`BiDi::next_event`].
pub struct BidiEvent;
impl BidiEvent {
    pub const LOG_ENTRY_ADDED: &'static str = "log.entryAdded";
    pub const CONTEXT_CREATED: &'static str = "browsingContext.contextCreated";
    pub const CONTEXT_DESTROYED: &'static str = "browsingContext.contextDestroyed";
    pub const NAVIGATION_STARTED: &'static str = "browsingContext.navigationStarted";
    pub const DOM_CONTENT_LOADED: &'static str = "browsingContext.domContentLoaded";
    pub const LOAD: &'static str = "browsingContext.load";
    pub const DOWNLOAD_WILL_BEGIN: &'static str = "browsingContext.downloadWillBegin";
    pub const BEFORE_REQUEST_SENT: &'static str = "network.beforeRequestSent";
    pub const AUTH_REQUIRED: &'static str = "network.authRequired";
    pub const RESPONSE_STARTED: &'static str = "network.responseStarted";
    pub const RESPONSE_COMPLETED: &'static str = "network.responseCompleted";
    pub const FETCH_ERROR: &'static str = "network.fetchError";
    pub const REALM_CREATED: &'static str = "script.realmCreated";
    pub const REALM_DESTROYED: &'static str = "script.realmDestroyed";
    pub const MESSAGE: &'static str = "script.message";
}

/// The event-driven BiDi channel for a session (over the demux C ABI).
///
/// Commands and events multiplex over one WebSocket via the engine's shape-C
/// demux (a single reader routes replies to an id table and events to a bounded
/// queue), so replies stay correlated while events stream. Command ids are
/// supplied automatically from a monotonic per-channel counter (from 1).
#[derive(Debug)]
pub struct BiDi {
    handle: Handle,
    next_id: c_int,
}

// The handle is a plain pointer into the engine; used from one thread at a time.
unsafe impl Send for BiDi {}

impl BiDi {
    fn next_id(&mut self) -> c_int {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// `session.subscribe` to one or more event names; wait for the ack. Returns
    /// the ack payload. Matching events then arrive on the queue (drain via
    /// [`BiDi::next_event`]).
    pub fn subscribe(&mut self, events: &[&str]) -> Result<Json> {
        self.subscribe_timeout(events, 10000)
    }

    pub fn subscribe_timeout(&mut self, events: &[&str], timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let csv = cstr(&events.join(","));
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_subscribe(self.handle, id, csv.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    pub fn unsubscribe(&mut self, events: &[&str]) -> Result<Json> {
        self.unsubscribe_timeout(events, 10000)
    }

    pub fn unsubscribe_timeout(&mut self, events: &[&str], timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let csv = cstr(&events.join(","));
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_unsubscribe(self.handle, id, csv.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    /// Block until an event whose `method` matches arrives, or timeout. Returns
    /// the event, or `None` on timeout/close. (Subscribe first.)
    pub fn next_event(&mut self, method: &str, timeout_ms: i32) -> Result<Option<Json>> {
        let m = cstr(method);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_wait_event(self.handle, m.as_ptr(), timeout_ms)
        });
        if raw.is_empty() {
            return Ok(None);
        }
        Self::decode(&raw).map(Some)
    }

    /// Issue any BiDi command and return its reply payload. Reaches BiDi methods
    /// with no dedicated wrapper (script.evaluate, network.*, ...). Sends, then
    /// pumps until this id's reply arrives or the timeout elapses.
    pub fn command(&mut self, method: &str, params: Json, timeout_ms: i32) -> Result<Json> {
        let cid = self.next_id();
        let m = cstr(method);
        let pj = cstr(&params.encode());
        if unsafe { aether_sel_embed_bidi_send(self.handle, cid, m.as_ptr(), pj.as_ptr()) } != 0 {
            return Err(WebDriverError::classify(-1, format!("BiDi send failed: {method}")));
        }
        let mut waited = 0;
        let step = 50;
        while waited < timeout_ms {
            let reply = take_string(unsafe { aether_sel_embed_bidi_poll_reply(self.handle, cid) });
            if !reply.is_empty() {
                return Self::decode(&reply);
            }
            if unsafe { aether_sel_embed_bidi_pump(self.handle, step) } < 0 {
                break;
            }
            waited += step;
        }
        Err(WebDriverError::classify(21, format!("BiDi command timed out: {method}")))
    }

    // ---- typed convenience commands ----

    /// `browsingContext.getTree` — the browsing contexts (each with a `context`
    /// id). Returns the full reply payload.
    pub fn get_tree(&mut self, timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let raw = take_string(unsafe { aether_sel_embed_bidi_get_tree(self.handle, id, timeout_ms) });
        Self::decode(&raw)
    }

    /// The top-level browsing context id (the anchor for evaluate/navigate), or
    /// `None` when the tree is empty.
    pub fn top_context(&mut self, timeout_ms: i32) -> Result<Option<String>> {
        let tree = self.get_tree(timeout_ms)?;
        let ctx = tree
            .get("result")
            .and_then(|r| r.get("contexts"))
            .and_then(|c| c.as_array())
            .and_then(|a| a.first())
            .and_then(|c| c.get("context"))
            .and_then(|c| c.as_str())
            .map(String::from);
        Ok(ctx)
    }

    /// `script.evaluate` an expression in the top-level context's realm, awaiting
    /// a returned promise. Returns the reply; `["result"]["result"]` is the
    /// BiDi-typed value (e.g. `{"type": "number", "value": 42}`). BiDi's richer
    /// alternative to execute_script — real realms, promise-awaiting, structured
    /// value types.
    pub fn evaluate(&mut self, expr: &str, timeout_ms: i32) -> Result<Json> {
        let ctx = self
            .top_context(timeout_ms)?
            .ok_or_else(|| WebDriverError::classify(0, "no browsing context for script.evaluate".into()))?;
        let e = cstr(expr);
        let c = cstr(&ctx);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_script_evaluate(self.handle, self.next_id(), e.as_ptr(), c.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    /// `script.evaluate`, returning just the unwrapped value (the `.value` of the
    /// BiDi-typed result), or `None` if it wasn't a simple value.
    pub fn evaluate_value(&mut self, expr: &str, timeout_ms: i32) -> Result<Option<Json>> {
        let reply = self.evaluate(expr, timeout_ms)?;
        let value = reply
            .get("result")
            .and_then(|r| r.get("result"))
            .and_then(|r| r.get("value"))
            .cloned();
        Ok(value)
    }

    /// `browsingContext.navigate` the top-level context to `url` (wait: complete).
    /// Returns the reply payload.
    pub fn navigate(&mut self, url: &str, timeout_ms: i32) -> Result<Json> {
        let ctx = self
            .top_context(timeout_ms)?
            .ok_or_else(|| WebDriverError::classify(0, "no browsing context for navigate".into()))?;
        let c = cstr(&ctx);
        let u = cstr(url);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_navigate(self.handle, self.next_id(), c.as_ptr(), u.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    // ---- network interception (observe / release / block requests) ----

    /// `network.addIntercept` for a URL pattern (a full parseable URL as a
    /// "string" pattern; empty intercepts all) at the given comma-separated
    /// phases. Subscribe to the matching `network.*` event first if you want the
    /// paused-request events. Returns the intercept id (`result.intercept`), or
    /// `None`.
    pub fn add_intercept(
        &mut self,
        phases_csv: &str,
        url_pattern: &str,
        timeout_ms: i32,
    ) -> Result<Option<String>> {
        let id = self.next_id();
        let phases = cstr(phases_csv);
        let pattern = cstr(url_pattern);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_add_intercept(
                self.handle,
                id,
                phases.as_ptr(),
                pattern.as_ptr(),
                timeout_ms,
            )
        });
        let reply = Self::decode(&raw)?;
        Ok(reply
            .get("result")
            .and_then(|r| r.get("intercept"))
            .and_then(|i| i.as_str())
            .map(String::from))
    }

    /// `network.removeIntercept` — stop intercepting for a prior intercept id.
    /// Returns the reply payload.
    pub fn remove_intercept(&mut self, intercept_id: &str, timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let iid = cstr(intercept_id);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_remove_intercept(self.handle, id, iid.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    /// Let a paused (intercepted) request proceed unchanged. `request_id` comes
    /// from a network event's `params.request.request` (see
    /// [`BiDi::event_request_id`]). Returns the reply payload.
    pub fn continue_request(&mut self, request_id: &str, timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let rid = cstr(request_id);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_continue_request(self.handle, id, rid.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    /// Block a paused request (the ad/tracker-blocking case). `request_id` comes
    /// from a network event's `params.request.request`. Returns the reply payload.
    pub fn fail_request(&mut self, request_id: &str, timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let rid = cstr(request_id);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_fail_request(self.handle, id, rid.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    /// Fulfill a paused request with a mock response (`network.provideResponse`),
    /// bypassing the network. `request_id` comes from a network event's
    /// `params.request.request`. The engine adds `Access-Control-Allow-Origin: *`
    /// so cross-origin fetches can read the mocked body. Returns the reply payload.
    pub fn provide_response(
        &mut self,
        request_id: &str,
        status: i32,
        content_type: &str,
        body: &str,
        timeout_ms: i32,
    ) -> Result<Json> {
        let id = self.next_id();
        let rid = cstr(request_id);
        let ct = cstr(content_type);
        let b = cstr(body);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_provide_response(
                self.handle,
                id,
                rid.as_ptr(),
                status,
                ct.as_ptr(),
                b.as_ptr(),
                timeout_ms,
            )
        });
        Self::decode(&raw)
    }

    /// Answer an HTTP auth challenge (a paused `authRequired` request) with
    /// credentials — automates basic/digest auth that classic WebDriver can't
    /// handle in headless. `request_id` comes from a network event's
    /// `params.request.request`. Returns the reply payload.
    pub fn continue_with_auth(
        &mut self,
        request_id: &str,
        username: &str,
        password: &str,
        timeout_ms: i32,
    ) -> Result<Json> {
        let id = self.next_id();
        let rid = cstr(request_id);
        let user = cstr(username);
        let pass = cstr(password);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_continue_with_auth(
                self.handle,
                id,
                rid.as_ptr(),
                user.as_ptr(),
                pass.as_ptr(),
                timeout_ms,
            )
        });
        Self::decode(&raw)
    }

    /// Set the session HTTP cache behavior (`network.setCacheBehavior`):
    /// `"bypass"` disables it (so every request hits the network / an intercept),
    /// `"default"` restores it. Returns the reply payload.
    pub fn set_cache_behavior(&mut self, behavior: &str, timeout_ms: i32) -> Result<Json> {
        let id = self.next_id();
        let b = cstr(behavior);
        let raw = take_string(unsafe {
            aether_sel_embed_bidi_network_set_cache_behavior(self.handle, id, b.as_ptr(), timeout_ms)
        });
        Self::decode(&raw)
    }

    /// The `network.request` id out of a `network.beforeRequestSent` (or other
    /// network) event: `params.request.request`.
    pub fn event_request_id(event: &Json) -> Option<String> {
        event
            .get("params")
            .and_then(|p| p.get("request"))
            .and_then(|r| r.get("request"))
            .and_then(|r| r.as_str())
            .map(String::from)
    }

    /// How many events the bounded queue has dropped since the last call (then
    /// resets) — so a consumer knows it missed events.
    pub fn lost_events(&self) -> i32 {
        unsafe { aether_sel_embed_bidi_lost_events(self.handle) }
    }

    fn decode(raw: &str) -> Result<Json> {
        if raw.is_empty() {
            return Ok(Json::Null);
        }
        json::parse(raw).map_err(|e| WebDriverError::classify(1, format!("bad BiDi JSON: {e}")))
    }
}

impl Drop for BiDi {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe { aether_sel_embed_bidi_close(self.handle) };
            self.handle = std::ptr::null_mut();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The switchToFrame `id` payload is the one piece of new pure logic worth
    // pinning without a browser: the three W3C shapes (index number, element
    // reference object, JSON null) must encode exactly, since the engine passes
    // the `id` value straight into the /frame request body.

    #[test]
    fn frame_index_encodes_as_a_bare_number() {
        let body = json::obj(vec![("id", Frame::Index(2).id_json())]);
        assert_eq!(body.encode(), "{\"id\":2}");
    }

    #[test]
    fn frame_default_encodes_as_null() {
        let body = json::obj(vec![("id", Frame::Default.id_json())]);
        assert_eq!(body.encode(), "{\"id\":null}");
    }

    #[test]
    fn frame_element_encodes_as_the_w3c_element_ref() {
        let body = json::obj(vec![("id", Frame::Element("FID".into()).id_json())]);
        // The `id` value is the element-reference object, not a bare string.
        let encoded = body.encode();
        assert!(encoded.contains(&format!("\"{W3C_ELEMENT_KEY}\":\"FID\"")), "{encoded}");
        assert!(encoded.starts_with("{\"id\":{"), "id must be an object: {encoded}");
    }

    #[test]
    fn frame_from_element_ref_carries_the_id() {
        // Frame::from(&WebElement) captures the element id without a driver call.
        // (Construct a bare WebElement id via the enum directly — the From impl
        // just moves the id string, which we assert through id_json.)
        let f = Frame::Element("abc123".into());
        let encoded = json::obj(vec![("id", f.id_json())]).encode();
        assert!(encoded.contains("abc123"));
    }
}
