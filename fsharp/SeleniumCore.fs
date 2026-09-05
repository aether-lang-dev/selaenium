namespace OpenQA.Selenium.FSharp

open OpenQA.Selenium

/// Idiomatic F# over the .NET binding.
///
/// There is NO second FFI here. The one CLR binding to the shared Aether
/// WebDriver engine is `dotnet/SeleniumCore` (P/Invoke); everything here is
/// ordinary F#/.NET interop on top of those classes — exactly as one C# binding
/// backs the whole CLR family (F#, VB.NET). An F#-specific FFI would be a second
/// copy of the marshalling rules to keep in sync with selenium_core/embed.ae.
///
/// What F# adds: a `headlessChrome url (fun d -> …)` loan-pattern that quits at
/// the end, a `By` module re-export, and the pure engine helpers as functions.
module Selenium =

    /// By strategies as F#-friendly functions over the Selenium 4.x `By` factory.
    /// Each returns a `By` locator carrying (strategy, value).
    module By =
        let id (value: string) : By = OpenQA.Selenium.By.Id(value)
        let name (value: string) : By = OpenQA.Selenium.By.Name(value)
        let cssSelector (value: string) : By = OpenQA.Selenium.By.CssSelector(value)
        let className (value: string) : By = OpenQA.Selenium.By.ClassName(value)
        let tagName (value: string) : By = OpenQA.Selenium.By.TagName(value)
        let linkText (value: string) : By = OpenQA.Selenium.By.LinkText(value)
        let partialLinkText (value: string) : By = OpenQA.Selenium.By.PartialLinkText(value)
        let xpath (value: string) : By = OpenQA.Selenium.By.XPath(value)

    /// Pure engine helpers (no session) — shared with every binding.
    let route (command: string) : string = RemoteWebDriver.Route(command)
    let errorCode (w3cError: string) : int = RemoteWebDriver.ErrorCode(w3cError)
    let locator (by: string) (value: string) : string = RemoteWebDriver.Locator(by, value)

    /// Loan-pattern: open a headless Chrome session, run `body`, always quit.
    let headlessChrome (commandExecutor: string) (body: IWebDriver -> 'a) : 'a =
        let d = RemoteWebDriver.HeadlessChrome(commandExecutor)
        try body (d :> IWebDriver)
        finally d.Quit()
