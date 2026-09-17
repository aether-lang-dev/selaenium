# selenium (F#) — idiomatic F# over the .NET assembly

Selenium WebDriver for F# — a thin layer of F#/.NET interop over the .NET
binding's `OpenQA.Selenium` types (F# sugar in the `OpenQA.Selenium.FSharp`
namespace).

F# adds **no engine of its own**. The engine is one pure, reentrant shared
library — a single .so/.dylib/.dll … NOT an installation, a service, or a
framework: no installer, no daemon, no config, no special directories. F#
reaches it **through the host artifact — the .NET assembly** (the one CLR
binding to the engine, P/Invoke; assembly `WebDriver`), so the whole engine
story — packing the assembly, how the `.so` travels, `SELENIUM_CORE_LIB` — lives
in [`dotnet/README.md`](../dotnet/README.md). One C# binding backs the whole CLR
family; an F#-specific FFI would only be a second copy of the marshalling rules
to drift.

> **Name note.** The types are the mainstream `OpenQA.Selenium` — an ABI/name
> match to upstream Selenium-.NET. Nothing here is on nuget.org; your platform
> team builds and publishes the assembly to your internal NuGet feed (see
> `dotnet/README.md`).

## Using it (F# app developer)

Reference the .NET package from your internal NuGet feed, then use the F# sugar
(`OpenQA.Selenium.FSharp.Selenium`), or the `OpenQA.Selenium` types directly:

```fsharp
open OpenQA.Selenium
open OpenQA.Selenium.FSharp

Selenium.headlessChrome "http://127.0.0.1:9515" (fun d ->
    d.Get("https://example.com")
    printfn "%s" d.Title
    printfn "%s" (d.FindElement(By.Id("main")).Text))
    // the driver is quit for you at the end of the body
```

What F# adds: a `headlessChrome url (fun d -> …)` loan-pattern that always quits;
a `By` module re-exporting the `By` factory (`By.id`, `By.cssSelector`, …); and
the pure engine helpers (`route`, `errorCode`, `locator`) as functions.
Everything else is the C# surface reached over CLR interop.

## Layout

```
SeleniumCore.fs    the F# sugar (loan-pattern, By module, engine helpers)
FfiTest.fs         no-browser FFI xUnit facts (interop over the C# assembly)
LiveTest.fs        live-browser xUnit facts (shadow DOM, firefox), self-orchestrated
FfiTest.fsproj     ProjectReference to dotnet/SeleniumCore; runs as xUnit
.tests.ae          aeb node → deps dotnet/SeleniumCore + the engine, runs dotnet test
```

F# adds no engine — see [`dotnet/README.md`](../dotnet/README.md) for the .NET
package and how the engine is bundled.
