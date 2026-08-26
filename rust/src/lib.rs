//! Selenium WebDriver for Rust, re-glued to the shared pure-Aether WebDriver
//! core. The entire W3C protocol — command catalog, route table, path
//! templating, By normalization, error decode, and the HTTP round-trip — lives
//! in and is maintained as the in-repo Aether engine (`core/selenium_core.ae`),
//! exposed via the `aether_sel_embed_*` C ABI (`core/embed.ae`). This crate
//! carries NO protocol logic; it links the one `libselenium_core.so` at build
//! time (see build.rs) and marshals strings/JSON across the boundary.
//!
//! ```no_run
//! use selenium_core::{WebDriver, By};
//! let d = WebDriver::headless_chrome("http://127.0.0.1:9515").unwrap();
//! d.get("https://example.com").unwrap();
//! println!("{}", d.title().unwrap());
//! d.find_element(By::CSS, "a").unwrap().click().unwrap();
//! d.quit().unwrap();
//! ```

use std::ffi::{c_char, c_int, c_void, CStr, CString};

pub mod json;
pub use json::Json;

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
    fn aether_sel_embed_error_code(w3c_error: *const c_char) -> c_int;
    fn aether_sel_embed_free_string(s: *mut c_char);
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

/// Locator strategies. Values match the engine's by_locator strategy strings;
/// ID/NAME/CLASS_NAME are rewritten to CSS in the engine.
pub struct By;
impl By {
    pub const ID: &'static str = "id";
    pub const NAME: &'static str = "name";
    pub const CSS: &'static str = "css selector";
    pub const CLASS_NAME: &'static str = "className";
    pub const TAG_NAME: &'static str = "tag name";
    pub const LINK_TEXT: &'static str = "link text";
    pub const PARTIAL_LINK_TEXT: &'static str = "partial link text";
    pub const XPATH: &'static str = "xpath";
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

fn decode_by(by: &str, value: &str) -> Json {
    json::parse(&locator(by, value)).unwrap_or(Json::Null)
}

const W3C_ELEMENT_KEY: &str = "element-6066-11e4-a52e-4f735466cecf";

// ---- WebDriver ----

/// A WebDriver session over the shared engine.
#[derive(Debug)]
pub struct WebDriver {
    handle: Handle,
}

// The handle is a plain pointer into the engine; sessions are used from one
// thread at a time in these bindings.
unsafe impl Send for WebDriver {}

impl WebDriver {
    /// Start a Chrome session against a running chromedriver (or Grid). `options`
    /// is a JSON object of extra capabilities merged under browserName: chrome.
    pub fn chrome(command_executor: &str, options: Option<Json>) -> Result<WebDriver> {
        let mut caps = match options {
            Some(Json::Obj(m)) => Json::Obj(m),
            _ => json::obj(vec![]),
        };
        if let Json::Obj(ref mut m) = caps {
            m.insert("browserName".into(), json::s("chrome"));
        }
        WebDriver::new(command_executor, caps)
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

    fn new(command_executor: &str, capabilities: Json) -> Result<WebDriver> {
        let cu = cstr(command_executor);
        let handle = unsafe { aether_sel_embed_open(cu.as_ptr()) };
        if handle.is_null() {
            return Err(WebDriverError::classify(-1, "failed to open session handle".into()));
        }
        let d = WebDriver { handle };
        let payload = json::obj(vec![(
            "capabilities",
            json::obj(vec![("alwaysMatch", capabilities)]),
        )]);
        d.execute("newSession", payload)?;
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
    pub fn find_element(&self, by: &str, value: &str) -> Result<WebElement> {
        let result = self.execute("findElement", decode_by(by, value))?;
        self.element_from(&result)
    }
    pub fn find_elements(&self, by: &str, value: &str) -> Result<Vec<WebElement>> {
        let result = self.execute("findElements", decode_by(by, value))?;
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

    // ---- script ----
    pub fn execute_script(&self, script: &str, args: Vec<Json>) -> Result<Json> {
        self.execute("executeScript", json::obj(vec![("script", json::s(script)), ("args", Json::Arr(args))]))
    }

    // ---- windows ----
    pub fn window_handles(&self) -> Result<Vec<String>> {
        let v = self.execute("getWindowHandles", json::obj(vec![]))?;
        Ok(v.as_array().cloned().unwrap_or_default().iter().filter_map(|e| e.as_str().map(String::from)).collect())
    }
    pub fn current_window_handle(&self) -> Result<String> {
        Ok(self.execute("getCurrentWindowHandle", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }
    pub fn set_window_rect(&self, rect: Json) -> Result<Json> {
        self.execute("setWindowRect", rect)
    }
    pub fn get_window_rect(&self) -> Result<Json> {
        self.execute("getWindowRect", json::obj(vec![]))
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

    // ---- screenshots ----
    pub fn screenshot_base64(&self) -> Result<String> {
        Ok(self.execute("screenshot", json::obj(vec![]))?.as_str().unwrap_or("").to_string())
    }

    // ---- lifecycle ----
    pub fn session_id(&self) -> String {
        take_string(unsafe { aether_sel_embed_session_id(self.handle) })
    }
    pub fn quit(self) -> Result<()> {
        let r = self.execute("quit", json::obj(vec![]));
        // Dropping self closes the handle.
        r.map(|_| ())
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
    pub fn get_attribute(&self, name: &str) -> Result<Json> {
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
}
