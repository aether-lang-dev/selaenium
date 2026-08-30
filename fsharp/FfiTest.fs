module SeleniumCore.FSharp.FfiTest

open Xunit
open SeleniumCore

// No-browser FFI test: proves the F# binding drives the ONE C# P/Invoke binding
// (over CLR interop — no second FFI) and that the shared engine helpers marshal
// correctly. Needs only the .so (SELENIUM_CORE_LIB / bundled native/). Real
// xUnit facts, exactly like the C# SeleniumCore.Tests.

[<Fact>]
let ``route`` () =
    Assert.Equal<string>("POST /session/:sessionId/url", WebDriver.Route("get"))
    Assert.Equal<string>("", WebDriver.Route("nope"))

[<Fact>]
let ``errorCode`` () =
    Assert.Equal<int>(17, WebDriver.ErrorCode("no such element"))
    Assert.Equal<int>(0, WebDriver.ErrorCode(""))

[<Fact>]
let ``locator css`` () =
    Assert.Equal<string>(
        "{\"using\":\"css selector\",\"value\":\"div.foo\"}",
        WebDriver.Locator(By.CssSelector, "div.foo")
    )

[<Fact>]
let ``locator id rewrite`` () =
    Assert.Contains("*[id=", WebDriver.Locator(By.Id, "main"))

[<Fact>]
let ``transport failure`` () =
    let mutable threw = false
    try
        WebDriver.Chrome("http://127.0.0.1:1", null) |> ignore
    with :? WebDriverError as e ->
        threw <- e.Code = -1
    Assert.True(threw, "transport failure should surface code -1")
