# Selenium.WebDriver (.NET) — the CLR engine assembly

Selenium WebDriver for .NET — a thin P/Invoke binding over the shared pure-Aether
WebDriver engine (`libselenium_core`), in the mainstream `OpenQA.Selenium`
namespace (assembly `WebDriver`).

The **engine** is one pure, reentrant shared library — a single
`.so`/`.dylib`/`.dll` reached through P/Invoke (N independent sessions per
process). It is **not** an installation, a service, or a framework: no installer,
no daemon, no config, no special directories. The assembly carries no protocol
logic — the W3C command map, routing, `By` normalization, error decode and the
HTTP round trip all live in that one library.

This assembly is the **engine host for the CLR family** — the F# binding consumes
it (it adds no engine of its own; see `fsharp/README.md`).

> **Name note.** The package id is `Selenium.WebDriver` and the namespace is
> `OpenQA.Selenium` — an ABI/name match to mainstream Selenium-.NET (your code is
> identical to upstream). It is **NOT published to nuget.org**, so a bare
> `dotnet add package Selenium.WebDriver` installs the *classic* Selenium team's
> package, not this one — your platform team builds and publishes this one to your
> internal NuGet feed (below).

## Using it (.NET app developer)

Add the package from your internal NuGet feed, then:

```csharp
using OpenQA.Selenium;

var d = RemoteWebDriver.HeadlessChrome("http://127.0.0.1:9515");
d.Url = "https://example.com";
Console.WriteLine(d.Title);
Console.WriteLine(d.FindElement(By.Id("main")).Text);
d.Quit();
```

`new ChromeDriver()` (spawning its own chromedriver) and the other mainstream
constructors work too. The engine ships as a runtime-native asset inside the
package and P/Invoke loads it — nothing to install, compile, or configure. To
point at a specific engine, ahead of any discovery:
`NativeLoader.Configure("/abs/path/libselenium_core.so")`, or the
`SELENIUM_CORE_LIB` env var.

## Building & publishing the package (platform / DevOps)

The `SeleniumCore.csproj` bundles the engine as a runtime-specific native asset,
so the produced `.nupkg` carries it. The `NativeLoader` resolves the engine at
load: `SELENIUM_CORE_LIB` → `native/<lib>` → `runtimes/<rid>/native/<lib>`.

Build + pack, then push to your internal feed:

```sh
aeb dotnet/.tests.ae            # builds + tests the assembly with the engine
dotnet pack dotnet/SeleniumCore/SeleniumCore.csproj -c Release
dotnet nuget push bin/Release/Selenium.WebDriver.*.nupkg \
    --source https://nuget.your-shop.internal
```

The engine bundled into the package comes from the build; see
[`docs/Prebuilt-Engine-Packaging.md`](../docs/Prebuilt-Engine-Packaging.md) for
the fetch-vs-compile model the other bindings use.

## Layout

```
SeleniumCore/                 the OpenQA.Selenium surface (WebDriver / By / …)
  NativeMethods.cs            the P/Invoke binding over the aether_sel_embed_* C ABI
  NativeLoader.cs             resolves the engine (env → native/ → runtimes/<rid>/native)
  SeleniumCore.csproj         packs the assembly + the runtime-native engine asset
SeleniumCore.Tests/           the binding test suite
.tests.ae                     aeb node → builds + tests with the engine
```
