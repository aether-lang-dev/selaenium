//// Selenium WebDriver for Gleam, re-glued to the shared pure-Aether WebDriver
//// core. This binding carries NO protocol logic — the W3C command map, routing,
//// By normalization, error decode and HTTP round-trip all live in the Aether
//// engine, reached over the BEAM through the C NIF `selenium_nif` (owned by the
//// Erlang binding and shared by the whole BEAM family — Erlang/Elixir/Gleam
//// load the SAME compiled NIF, no second C source).
////
//// Command params are passed as JSON strings (build them with `gleam/json`),
//// and command results come back as the raw JSON string of the response
//// `value` (decode with `gleam/json`/`gleam/dynamic` as needed). This keeps the
//// binding thin; the engine is the source of truth for every wire shape.

import gleam/int
import gleam/string

// ---- raw NIF surface (FFI to the selenium_nif Erlang module) ----
// The opaque session handle is a 64-bit integer (uintptr_t); 0 from `open`
// means failure. String args/results are Erlang binaries == Gleam String.

@external(erlang, "selenium_nif", "open")
fn nif_open(base_url: String) -> Int

@external(erlang, "selenium_nif", "close")
fn nif_close(handle: Int) -> a

@external(erlang, "selenium_nif", "execute")
fn nif_execute(handle: Int, name: String, params_json: String) -> Int

@external(erlang, "selenium_nif", "last_value")
fn nif_last_value(handle: Int) -> String

@external(erlang, "selenium_nif", "last_error_code")
fn nif_last_error_code(handle: Int) -> Int

@external(erlang, "selenium_nif", "last_error")
fn nif_last_error(handle: Int) -> String

@external(erlang, "selenium_nif", "session_id")
fn nif_session_id(handle: Int) -> String

@external(erlang, "selenium_nif", "by_locator")
fn nif_by_locator(strategy: String, value: String) -> String

@external(erlang, "selenium_nif", "route")
fn nif_route(name: String) -> String

@external(erlang, "selenium_nif", "error_code")
fn nif_error_code(w3c_error: String) -> Int

// ---- public types ----

/// A live WebDriver session. Treat it as an opaque token.
pub opaque type WebDriver {
  WebDriver(handle: Int)
}

/// A remote element handle.
pub opaque type WebElement {
  WebElement(driver: WebDriver, id: String)
}

/// A protocol error: the engine's W3C error code (0 success, -1 transport) plus
/// a message.
pub type WebDriverError {
  WebDriverError(code: Int, message: String)
}

/// Locator strategies (engine strategy strings; id/name/class rewrite to CSS).
pub const by_id = "id"

pub const by_name = "name"

pub const by_css = "css selector"

pub const by_class_name = "className"

pub const by_tag_name = "tag name"

pub const by_link_text = "link text"

pub const by_partial_link_text = "partial link text"

pub const by_xpath = "xpath"

const w3c_element_key = "element-6066-11e4-a52e-4f735466cecf"

// ---- pure engine helpers ----

/// The "METHOD PATH" route for a command name, or "" if unknown.
pub fn route(command: String) -> String {
  nif_route(command)
}

/// Map a W3C error string to its stable integer code (0 = success).
pub fn error_code(w3c_error: String) -> Int {
  nif_error_code(w3c_error)
}

/// The W3C {"using","value"} locator JSON for a (by, value) pair.
pub fn locator(by: String, value: String) -> String {
  nif_by_locator(by, value)
}

// ---- session lifecycle ----

/// Start a Chrome session. `caps_json` is the alwaysMatch capabilities object as
/// a JSON string (e.g. `{"browserName":"chrome","goog:chromeOptions":{...}}`).
pub fn chrome(command_executor: String, caps_json: String) -> Result(WebDriver, WebDriverError) {
  let handle = nif_open(command_executor)
  case handle {
    0 -> Error(WebDriverError(-1, "failed to open session handle"))
    _ -> {
      let driver = WebDriver(handle)
      let payload = "{\"capabilities\":{\"alwaysMatch\":" <> caps_json <> "}}"
      case execute(driver, "newSession", payload) {
        Ok(_) -> Ok(driver)
        Error(e) -> {
          nif_close(handle)
          Error(e)
        }
      }
    }
  }
}

/// Convenience: a headless Chrome session with the standard launch args.
pub fn headless_chrome(command_executor: String) -> Result(WebDriver, WebDriverError) {
  let caps =
    "{\"browserName\":\"chrome\",\"goog:chromeOptions\":{\"args\":[\"--headless=new\",\"--no-sandbox\",\"--disable-gpu\",\"--disable-dev-shm-usage\"]}}"
  chrome(command_executor, caps)
}

/// Execute a command by name with JSON params (a JSON object string, or "{}").
/// Returns the response `value` as a JSON string on success, or a typed error.
pub fn execute(
  driver: WebDriver,
  command: String,
  params_json: String,
) -> Result(String, WebDriverError) {
  let WebDriver(handle) = driver
  let rc = nif_execute(handle, command, params_json)
  case rc {
    0 -> Ok(nif_last_value(handle))
    _ -> {
      let code = nif_last_error_code(handle)
      let msg = nif_last_error(handle)
      case rc == -1 && code == 0 {
        True -> Error(WebDriverError(-1, "transport failure"))
        False -> Error(WebDriverError(code, msg))
      }
    }
  }
}

// ---- navigation ----

pub fn get(driver: WebDriver, url: String) -> Result(String, WebDriverError) {
  execute(driver, "get", "{\"url\":" <> json_string(url) <> "}")
}

pub fn title(driver: WebDriver) -> Result(String, WebDriverError) {
  execute(driver, "getTitle", "{}")
}

pub fn current_url(driver: WebDriver) -> Result(String, WebDriverError) {
  execute(driver, "getCurrentUrl", "{}")
}

pub fn back(driver: WebDriver) -> Result(String, WebDriverError) {
  execute(driver, "goBack", "{}")
}

pub fn forward(driver: WebDriver) -> Result(String, WebDriverError) {
  execute(driver, "goForward", "{}")
}

// ---- elements ----

/// Find one element. The returned value is the element JSON; use
/// [`element_id`](#element_id) to extract the reference, then the element_*
/// functions below.
pub fn find_element(
  driver: WebDriver,
  by: String,
  value: String,
) -> Result(WebElement, WebDriverError) {
  case execute(driver, "findElement", nif_by_locator(by, value)) {
    Ok(json_value) ->
      case extract_element_id(json_value) {
        Ok(id) -> Ok(WebElement(driver, id))
        Error(_) -> Error(WebDriverError(17, "element reference key missing"))
      }
    Error(e) -> Error(e)
  }
}

pub fn click(element: WebElement) -> Result(String, WebDriverError) {
  let WebElement(driver, id) = element
  execute(driver, "clickElement", "{\"id\":" <> json_string(id) <> "}")
}

pub fn element_text(element: WebElement) -> Result(String, WebDriverError) {
  let WebElement(driver, id) = element
  execute(driver, "getElementText", "{\"id\":" <> json_string(id) <> "}")
}

pub fn tag_name(element: WebElement) -> Result(String, WebDriverError) {
  let WebElement(driver, id) = element
  execute(driver, "getElementTagName", "{\"id\":" <> json_string(id) <> "}")
}

// ---- script ----

/// Execute a script. `args_json` is a JSON array string (e.g. "[]" or "[40,2]").
pub fn execute_script(
  driver: WebDriver,
  script: String,
  args_json: String,
) -> Result(String, WebDriverError) {
  execute(
    driver,
    "executeScript",
    "{\"script\":" <> json_string(script) <> ",\"args\":" <> args_json <> "}",
  )
}

// ---- lifecycle ----

pub fn session_id(driver: WebDriver) -> String {
  let WebDriver(handle) = driver
  nif_session_id(handle)
}

pub fn quit(driver: WebDriver) -> Result(String, WebDriverError) {
  let WebDriver(handle) = driver
  let r = execute(driver, "quit", "{}")
  nif_close(handle)
  r
}

// ---- tiny helpers ----

/// JSON-encode a string (quote + escape " and \).
fn json_string(s: String) -> String {
  let escaped =
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
  "\"" <> escaped <> "\""
}

/// Pull the element-reference id out of a findElement value JSON string. The
/// value looks like {"element-6066-...":"<id>"}; a small textual extraction
/// keeps this binding dependency-free for the common case.
fn extract_element_id(json_value: String) -> Result(String, Nil) {
  let needle = "\"" <> w3c_element_key <> "\":\""
  case string.split_once(json_value, needle) {
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\"") {
        Ok(#(id, _)) -> Ok(id)
        Error(_) -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

/// Format an int (handy for building args_json).
pub fn int_to_string(i: Int) -> String {
  int.to_string(i)
}
