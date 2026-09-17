module OpenQA.Selenium.FSharp.FfiTest

open Xunit
open OpenQA.Selenium
open OpenQA.Selenium.FSharp

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
let ``shadow-DOM surface rides the C# types`` () =
    // F# adds no FFI: shadow DOM comes for free from the one C# binding. Assert
    // the surface is reachable through the shared types — IWebElement.GetShadowRoot
    // returns an ISearchContext, ShadowRoot IS an ISearchContext (so its
    // FindElement/FindElements are usable), and the typed error (code 19) exists.
    let getShadow = typeof<IWebElement>.GetMethod("GetShadowRoot")
    Assert.NotNull(getShadow)
    Assert.Equal<System.Type>(typeof<ISearchContext>, getShadow.ReturnType)
    Assert.True(typeof<ISearchContext>.IsAssignableFrom(typeof<ShadowRoot>))
    Assert.NotNull(typeof<ShadowRoot>.GetMethod("FindElement"))
    Assert.NotNull(typeof<ShadowRoot>.GetMethod("FindElements"))
    let ex = NoSuchShadowRootException("no such shadow root", 19)
    Assert.Equal<int>(19, ex.Code)

[<Fact>]
let ``transport failure`` () =
    let mutable threw = false
    try
        RemoteWebDriver.Chrome("http://127.0.0.1:1", null) |> ignore
    with :? WebDriverException as e ->
        threw <- e.Code = -1
    Assert.True(threw, "transport failure should surface code -1")

[<Fact>]
let ``F# Selenium module sugar delegates to the C# binding`` () =
    // The F# `Selenium` module adds thin idiomatic sugar over the one C# binding
    // (no second FFI). Assert its surface offline: the By re-export delegates to
    // the C# By factory (className -> W3C "class name"), and the pure engine
    // helpers agree with the RemoteWebDriver statics they forward to.
    Assert.Equal<string>("id", (Selenium.By.id "hdr").Strategy)
    Assert.Equal<string>("main", (Selenium.By.id "main").Value)
    Assert.Equal<string>("class name", (Selenium.By.className "g").Strategy)
    Assert.Equal<string>("css selector", (Selenium.By.cssSelector "a.x").Strategy)
    Assert.Equal<string>("name", (Selenium.By.name "n").Strategy)
    Assert.Equal<string>("tag name", (Selenium.By.tagName "a").Strategy)
    Assert.Equal<string>("link text", (Selenium.By.linkText "x").Strategy)
    Assert.Equal<string>("partial link text", (Selenium.By.partialLinkText "x").Strategy)
    Assert.Equal<string>("xpath", (Selenium.By.xpath "//a").Strategy)
    Assert.Equal<string>("POST /session/:sessionId/url", Selenium.route "get")
    Assert.Equal<int>(17, Selenium.errorCode "no such element")
    Assert.Contains("*[id=", Selenium.locator "id" "main")
    // The loan-pattern builder exists and is typed: a partial application (no
    // body) asserts the surface without opening a session.
    let _builder : (IWebDriver -> int) -> int = Selenium.headlessChrome "http://127.0.0.1:1"
    Assert.NotNull(box _builder)

[<Fact>]
let ``firefox/edge/safari factories ride the C# binding`` () =
    // F# adds no FFI: the browser factories come for free from the one C#
    // binding (RemoteWebDriver). Assert the static factories are reachable
    // through CLR interop — the same way chrome() already is.
    let t = typeof<RemoteWebDriver>
    Assert.NotNull(t.GetMethod("Firefox"))
    Assert.NotNull(t.GetMethod("HeadlessFirefox"))
    Assert.NotNull(t.GetMethod("Edge"))
    Assert.NotNull(t.GetMethod("HeadlessEdge"))
    Assert.NotNull(t.GetMethod("Safari"))
