module OpenQA.Selenium.FSharp.LiveTest

open System
open Xunit
open OpenQA.Selenium

// LIVE browser facts for the F# binding. FfiTest proves the shadow finders and
// the firefox factory EXIST — which stays green even when the code behind them
// is broken. These drive real browsers through the engine so the shadow-DOM path
// and the firefox factory are actually executed.
//
// Both legs self-orchestrate via the engine's driver ABI (ResolveDriver +
// EnsureDriver, docs/Driver-Orchestration-ABI.md) — no driver on PATH, no Grid —
// and use data: pages, so no content server is needed.

/// An empty ResolveDriver means the engine genuinely could not provide the
/// driver; that is the only reason either leg is allowed not to run.
let private driverFor (browser: string) =
    if String.IsNullOrEmpty(RemoteWebDriver.ResolveDriver(browser)) then None
    else Option.ofObj (RemoteWebDriver.EnsureDriver(browser, "", 20000))

[<Fact>]
let ``live chrome drives a real shadow root`` () =
    match driverFor "chrome" with
    | None -> ()   // engine cannot resolve a chromedriver
    | Some proc ->
        try
            let d = RemoteWebDriver.HeadlessChrome(proc.Url)
            try
                Assert.NotEmpty(d.SessionId)
                d.Get("data:text/html,<!doctype html><title>FSharpLive</title>"
                      + "<h1 id=\"hdr\">plain</h1><div id=\"host\"></div>")
                Assert.Equal<string>("FSharpLive", d.Title)

                // Host an open shadow root, then reach an element INSIDE it —
                // the getShadowRoot -> findElementFromShadowRoot round trip.
                d.ExecuteScript(
                    "var h=document.getElementById('host');"
                    + "var r=h.attachShadow({mode:'open'});"
                    + "r.innerHTML='<p id=\"sinner\">fsharp-shadow</p>';") |> ignore

                let shadow = d.FindElement(By.Id("host")).GetShadowRoot()
                Assert.Equal<string>("fsharp-shadow",
                                     shadow.FindElement(By.CssSelector("#sinner")).Text)
                Assert.Single(shadow.FindElements(By.CssSelector("p"))) |> ignore

                // A non-host element has no shadow root: the binding maps W3C
                // code 19 to its own typed exception, not a bare WebDriverException.
                Assert.Throws<NoSuchShadowRootException>(fun () ->
                    d.FindElement(By.Id("hdr")).GetShadowRoot() |> ignore) |> ignore
            finally
                d.Quit()
        finally
            proc.Stop()

[<Fact>]
let ``live firefox opens a real session`` () =
    match driverFor "firefox" with
    | None -> ()   // engine cannot resolve a geckodriver
    | Some proc ->
        try
            let d = RemoteWebDriver.HeadlessFirefox(proc.Url)
            try
                Assert.NotEmpty(d.SessionId)
                d.Get("data:text/html,<!doctype html><title>Aether Firefox</title>"
                      + "<h1 id=\"hdr\">Hello FF</h1>")
                Assert.Equal<string>("Aether Firefox", d.Title)
                Assert.Equal<string>("Hello FF", d.FindElement(By.Id("hdr")).Text)
            finally
                d.Quit()
        finally
            proc.Stop()
