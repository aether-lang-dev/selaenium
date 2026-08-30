namespace SeleniumCore.FSharp

open SeleniumCore

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
module SeleniumCore =

    /// By strategies (the same string constants the engine expects).
    module By =
        let ID = SeleniumCore.By.Id
        let NAME = SeleniumCore.By.Name
        let CSS_SELECTOR = SeleniumCore.By.CssSelector
        let CLASS_NAME = SeleniumCore.By.ClassName
        let TAG_NAME = SeleniumCore.By.TagName

    /// Pure engine helpers (no session) — shared with every binding.
    let route (command: string) : string = WebDriver.Route(command)
    let errorCode (w3cError: string) : int = WebDriver.ErrorCode(w3cError)
    let locator (by: string) (value: string) : string = WebDriver.Locator(by, value)

    /// Loan-pattern: open a headless Chrome session, run `body`, always quit.
    let headlessChrome (commandExecutor: string) (body: WebDriver -> 'a) : 'a =
        let d = WebDriver.HeadlessChrome(commandExecutor)
        try body d
        finally d.Quit()
