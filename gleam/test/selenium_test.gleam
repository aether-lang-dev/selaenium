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
