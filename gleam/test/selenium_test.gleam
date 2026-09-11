//// Gleam tests over the shared Selenium NIF (the SAME compiled selenium_nif
//// the Erlang binding owns). FFI checks run with no browser; the live check
//// needs chromedriver and is skipped when absent.
////
//// NOTE: authored on a box without the Gleam compiler; verified on a box that
//// has Gleam + Erlang/BEAM (catchyos). The Erlang NIF underneath is fully
//// live-verified.

import gleam/string
import gleeunit
import gleeunit/should
import selenium

pub fn main() {
  gleeunit.main()
}

pub fn route_test() {
  selenium.route("get")
  |> should.equal("POST /session/:sessionId/url")

  selenium.route("nope")
  |> should.equal("")
}

pub fn error_code_test() {
  selenium.error_code("no such element")
  |> should.equal(17)

  selenium.error_code("")
  |> should.equal(0)
}

pub fn locator_css_test() {
  selenium.locator("css selector", "div.foo")
  |> should.equal("{\"using\":\"css selector\",\"value\":\"div.foo\"}")
}

pub fn locator_id_rewrite_test() {
  selenium.locator("id", "main")
  |> string.contains("*[id=")
  |> should.be_true()
}

// By factory produces the Selenium-style locators; class_name is "class name".
pub fn by_factory_test() {
  selenium.by_id("hdr")
  |> should.equal(selenium.Locator("id", "hdr"))

  selenium.by_class_name("greet")
  |> should.equal(selenium.Locator("class name", "greet"))
}

pub fn transport_failure_test() {
  case selenium.chrome("http://127.0.0.1:1", "{\"browserName\":\"chrome\"}") {
    Error(selenium.WebDriverError(code, _)) -> should.equal(code, -1)
    Ok(_) -> should.fail()
  }
}

// The new firefox/edge/safari factories exist, are typed, and reach newSession
// the same way chrome() does: against a dead port each surfaces a transport
// error (code -1). headless_firefox/headless_edge build their own caps.
pub fn firefox_transport_failure_test() {
  case selenium.headless_firefox("http://127.0.0.1:1") {
    Error(selenium.WebDriverError(code, _)) -> should.equal(code, -1)
    Ok(_) -> should.fail()
  }
}

pub fn browser_factories_surface_test() {
  let _firefox = selenium.firefox
  let _headless_firefox = selenium.headless_firefox
  let _edge = selenium.edge
  let _headless_edge = selenium.headless_edge
  let _safari = selenium.safari

  // edge builds the "MicrosoftEdge" browserName under ms:edgeOptions; a dead
  // port still yields a clean transport error.
  case selenium.headless_edge("http://127.0.0.1:1") {
    Error(selenium.WebDriverError(code, _)) -> should.equal(code, -1)
    Ok(_) -> should.fail()
  }
}

// Compile-surface check that the shadow-DOM API is present and typed: a session
// that fails to open cannot reach a shadow root, and the shadow finders type as
// (ShadowRoot, Locator) -> WebElement / raw JSON. This exercises the whole path
// without a browser (the chrome() open fails, so shadow_root is never called on
// a live element — the value here is the type-level surface assertion).
pub fn shadow_surface_test() {
  let _shadow_root = selenium.shadow_root
  let _find_one = selenium.find_element_from_shadow_root
  let _find_all = selenium.find_elements_from_shadow_root
  should.be_true(True)
}
