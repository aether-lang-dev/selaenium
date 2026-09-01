module OpenQA.Selenium.FSharp.FfiTest

open Xunit
open OpenQA.Selenium

// No-browser FFI test: proves the F# binding drives the ONE C# P/Invoke binding
// (over CLR interop — no second FFI) and that the shared engine helpers marshal
// correctly. Needs only the .so (SELENIUM_CORE_LIB / bundled native/). Real
// xUnit facts, exactly like the C# SeleniumCore.Tests.

[<Fact>]
let ``route`` () =
    Assert.Equal<string>("POST /session/:sessionId/url", RemoteWebDriver.Route("get"))
    Assert.Equal<string>("", RemoteWebDriver.Route("nope"))

[<Fact>]
let ``errorCode`` () =
    Assert.Equal<int>(17, RemoteWebDriver.ErrorCode("no such element"))
    Assert.Equal<int>(0, RemoteWebDriver.ErrorCode(""))

[<Fact>]
let ``locator css`` () =
    Assert.Equal<string>(
        "{\"using\":\"css selector\",\"value\":\"div.foo\"}",
        RemoteWebDriver.Locator("css selector", "div.foo")
    )

[<Fact>]
let ``locator id rewrite`` () =
    Assert.Contains("*[id=", RemoteWebDriver.Locator("id", "main"))

[<Fact>]
let ``By factory carries strategy and value`` () =
    let by = By.Id("main")
    Assert.Equal<string>("id", by.Strategy)
    Assert.Equal<string>("main", by.Value)
    Assert.Equal<string>("class name", By.ClassName("x").Strategy)

[<Fact>]
let ``transport failure`` () =
    let mutable threw = false
    try
        RemoteWebDriver.Chrome("http://127.0.0.1:1", null) |> ignore
    with :? WebDriverException as e ->
        threw <- e.Code = -1
    Assert.True(threw, "transport failure should surface code -1")
