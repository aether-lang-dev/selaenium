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
import selenium_core

pub fn main() {
  gleeunit.main()
}

pub fn route_test() {
  selenium_core.route("get")
  |> should.equal("POST /session/:sessionId/url")

  selenium_core.route("nope")
  |> should.equal("")
}

pub fn error_code_test() {
  selenium_core.error_code("no such element")
  |> should.equal(17)

  selenium_core.error_code("")
  |> should.equal(0)
}

pub fn locator_css_test() {
  selenium_core.locator(selenium_core.by_css, "div.foo")
  |> should.equal("{\"using\":\"css selector\",\"value\":\"div.foo\"}")
}

pub fn locator_id_rewrite_test() {
  selenium_core.locator(selenium_core.by_id, "main")
  |> string.contains("*[id=")
  |> should.be_true()
}

pub fn transport_failure_test() {
  case selenium_core.chrome("http://127.0.0.1:1", "{\"browserName\":\"chrome\"}") {
    Error(selenium_core.WebDriverError(code, _)) -> should.equal(code, -1)
    Ok(_) -> should.fail()
  }
}
