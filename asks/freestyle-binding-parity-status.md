# Freestyle binding parity — status & known limitations

## AUDIT REFRESH (2026-09-17, ae 0.681, this session)
A full 27-binding parity+completion re-audit ran against the ~164-method Rust
feature bar (standalone-FFI), real mainstream Selenium ABI (historical clients),
and host inheritance (delegators). Every binding now carries a SURFACE GUARD TEST
(compile-time reference or reflection) so method removal/rename fails the build.
Real gaps found + closed this pass:
- zig: 8 browser factories, findElements/findChildElements, findRelativeCount,
  shadowRoot + ShadowRoot ctx (zig build test 18/18).
- elixir: public bidi_navigate/bidi_unsubscribe/bidi_lost_events (mix 8 passed).
- haskell: waitForVisible/waitForClickable/waitUntilEvery/localChrome/isMultiple/
  bidiNextEvent/bidiTopContext (source-review; exports confirmed).
- clojure: local-chrome/with-local-chrome (parity with the other JVM delegators;
  ran 1/1 here).
- python/ruby/javascript/java/dotnet (historical): the genuine mainstream methods
  still missing — RelativeBy/locate_with (py/java/dotnet) and aria_role/
  accessible_name (rb/js/dotnet). java/dotnet By relaxed final/sealed +
  protected ctor so RelativeBy extends By (ABI-safe, matches mainstream).
Guard tests ADDED where absent: julia, haskell, rust (the reference itself),
lua/erlang (strengthened), + offline sugar guards for kotlin/scala/groovy/fsharp.
Verified on this box (native toolchains, engine .so prebuilt): rust, zig, lua, go,
dart, erlang, elixir, clojure, gleam, python, ruby, javascript, java(compile).
Source-review only (toolchain absent here): crystal, julia, haskell, swift,
kotlin, scala, fsharp/dotnet, lfe, groovy(pre-existing JDK class-version mismatch).
The stale "Haskell/Swift Native FFI declares only the basic seam / deferred"
sections at the BOTTOM of this file are FALSE as of this audit — both seams are
fully wired (all aether_sel_embed_* incl BiDi). Left in place below only as
historical record; do not act on them.

---


## FINAL STATUS (all 12 standalone bindings at full parity)
Committed this session (newest first): lfe a9c2808, julia 9af1dfb, elixir af3b9a6,
crystal b15239d, erlang 35c917e, go ba7154d, zig c59df7e, swift e61ddaa,
lua 691c94c, haskell 779b897, dart d45235b, nim 45db4d7.
Cross-binding fix: css param name->propertyName in 10 bindings (17caaeb).
Delegating wrappers inherit their target: kotlin/scala/clojure/groovy->java (perfect-ABI),
fsharp->dotnet (perfect-ABI; By.XPath fix 69635f8). lfe->BEAM selenium_nif.
Historical perfect-ABI clients: python/ruby/dotnet/java/javascript.

Toolchain-verified (compile+tests here): nim, dart, lua, zig, go, erlang, elixir, lfe
(lfe compiled via bootstrapped rebar3_lfe — 18/18 offline). Source-reviewed here,
then compile+run verified on the `ssh macvm` Mac: haskell, swift (see below).
Still source-reviewed only (toolchain absent everywhere reachable): crystal, julia.

DEFERRALS CLOSED (commit 5747780 + fixes efdfbfe swift, 1f3b705 haskell):
Haskell and Swift's Native FFI layers were widened from the basic execute seam to
ALL aether_sel_embed_* symbols. isDisplayed/getAttribute (real atoms, not injected
scripts), find_relative(_count), TLS trust config, driver orchestration
(resolve/ensure/launch/stop, DriverProcess, localChrome), and the FULL WebDriver-BiDi
surface (open/send/pump/poll/subscribe/wait_event/get_tree/script_evaluate/navigate
+ network interception) are now first-class in BOTH. Nothing deferred or faked.
Verified on macvm (Mac, x86_64): built the macOS engine dylib with ae 0.640,
Swift 6.1.2 `swift build` clean + standalone runtime smoke exe green (XCTest absent
— CLT-only Mac), GHC 9.10.3 `cabal build`+`cabal test` green (ensureDriver actually
launched chromedriver 138). First real compile caught pre-existing source-review
misses: swift Actions.keyDown/keyUp bad signatures; haskell keysChord test literal
greedy-hex-escape. Both fixed.

Now EVERY binding reaches the full Rust bar with nothing deferred.

FINAL GAP SWEEP (normalized/idiom-aware, 140-method bar). Result: Rust & Dart
140/140; go/nim/zig/lua/crystal/julia effectively complete (remaining grep
"misses" are naming idioms — subscribe_timeout=timeout param, chrome_tls=default
TLS params, poll_every=interval variant). Historical clients py/rb/dotnet/java/js
intentionally differ from the Rust bar to keep their PERFECT upstream-ABI match
(mainstream Selenium has no chrome_tls/find_relative_count/subscribe_timeout under
those names) — left unchanged on purpose. Delegating wrappers inherit their target.
THREE genuine small gaps found + closed (commits 3db6453 elixir, 4b5f9ff swift+haskell),
all live-verified on macvm vs real Chrome for Testing 138:
- Elixir: added key_down/key_up/chord (keyboard action device) + exists/2,3.
- Swift: added BiDi bidiAvailable/nextEvent/topContext/evaluateValue/eventRequestId.
- Haskell: added the Actions fluent verbs (moveToElement/clickAndHold/release/
  contextClick/doubleClick/dragAndDrop/keyDown/keyUp) — it had only raw performActions.

HISTORICAL CLIENTS — additions ARE allowed (adding a new method/type never breaks
ABI; only removing/changing does). Re-inventoried all 5 vs their REAL mainstream API
(not the Rust bar). Python & Ruby complete (print/Select/facades present under
mainstream names). One genuine mainstream-present-but-missing method in the other 3:
the print-to-PDF command, now added (commits 8f50ca8 js, 1b5973b java, c6cbb1c dotnet):
- JS: WebDriver.printPage(options) — 20/20 abi_test.
- Java: PrintsPage.print(PrintOptions)->Pdf + org.openqa.selenium.print.{PrintOptions,
  PageSize,PageMargin} + Pdf. AbiSurfaceTest 29/29.
- .NET: WebDriver.Print(PrintOptions)->PrintDocument + PrintOptions(nested PageSize/
  Margins, conditional ToDictionary) + EncodedFile/PrintDocument. Verified on macvm
  with .NET SDK 8.0.424 (dotnet build 0 errors; the new print xUnit test passes 1/1;
  the 14 other "failures" in a scratch test project are pre-existing engine-FFI tests
  that don't resolve the native lib in an ad-hoc project — unrelated to print).
Everything else the grep flagged for the historical clients was a naming-idiom false
positive (mainstream uses different names our bindings already have: JS Actions
move/press/release not clickAndHold; getCssValue not valueOfCssProperty; Ruby
select_by_text not select_by_visible_text; alerts via switchTo().alert(); etc.).

Aether toolchain pinned to v0.641.0 (ci/versions.env, commit fc3c01f) — engine
rebuilds clean on it. macvm now also has .NET SDK 8.0 (~/.dotnet) + GHC/Swift.

LIVE-BROWSER VERIFIED on macvm (real Chrome for Testing 138 + chromedriver 138):
- Swift LiveExe (swift run): PASS — localChrome drives a data: page; isDisplayed
  (atom), getAttribute (atom, after sendKeys), cssValue, AND BiDi getTree over a
  live WebSocket channel all green. Proves the newly-wired FFI end-to-end, not just
  compile/offline. macvm has /Applications/Google Chrome for Testing.app.
- Haskell live suite (cabal test with content_server.py + chromedriver + Chrome):
  FULL PASS — 35 checks green (element text/click/find(s), cookies, alerts, waits,
  window handles + the new resolveDriver/ensureDriver/bidiOpen FFI). Commit e16e506.

LIVE-BROWSER BUGS CAUGHT (only a real browser surfaced these; commits e16e506):
- Haskell extractElementId/extractElementIds/extractField double-dropped
  `length needle` (afterInfix already skips the needle) — truncated Chrome 138's
  ~70-char element ids → "malformed element id" (err 17) → every element command
  broke. Real correctness bug for all Haskell users, invisible to compile/offline.
- Haskell Live.hs stray `back d` (test-navigation off-by-one).
macvm has /Applications/Google Chrome for Testing.app; chromedriver 138 cached at
~/.cache/selenium/chromedriver/mac-x64/138.0.7204.183. The macvm repo is NOT a git
checkout (rsync'd trees, no .git) — restore files by re-rsync, not `git checkout`.

---


Tracking the push to bring every standalone-FFI binding to full parity with the
Rust reference client (`rust/src/*.rs`, the ~141-method feature bar). Historical
clients (python/ruby/dotnet/java/javascript) are perfect-ABI; delegating wrappers
(kotlin/scala/clojure/groovy→java, fsharp→dotnet, lfe→BEAM NIF) inherit their
target's surface. This file tracks the standalone-FFI group.

## Verification note
Toolchains installed on the build box: go, nim, dart, zig, lua, erlang, elixir
(compile + unit-test verified). NOT installed: swift, crystal, haskell (ghc),
julia, lfe — those are source-reviewed only, stated in each commit.

## Known freestyle-list limitations (features intentionally NOT added / faked)

### Haskell — Native FFI declares only the basic seam
`haskell/src/Selenium/Native.hs` foreign-imports only the 13 basic symbols
(open/close/execute/last_*/session_id/by_locator/route/error_code/free_string).
It does NOT declare `aether_sel_embed_{execute_atom, is_displayed, get_attribute,
find_relative, bidi_*}`. Consequently the Haskell binding cannot reach:
- `isDisplayed` (atom-backed)
- property-fallback `getAttribute` (uses get_attribute atom; getDomAttribute /
  getProperty via plain execute ARE provided)
- `findRelative` / `findRelativeCount`
- the entire BiDi surface (subscribe / network intercept / events)
These were deferred, not faked. Closing them needs added `foreign import` lines
in Native.hs AND a GHC toolchain to verify — do when GHC is available.

### Swift — C shim header (selenium_core.h) declares only the basic seam
Same shape as Haskell. The Swift C-shim module `CSeleniumCore` header exposes the
generic execute seam but not the atom/relative/driver-mgmt/bidi symbols. Deferred
(documented in swift/Sources/Selenium/Selenium.swift, not faked):
- TLS trust config (ca_path / insecure)
- atom-backed `isDisplayed` and property-fallback `getAttribute` (approximated via
  injected scripts)
- relative locators (`find_relative` / `find_relative_count`)
- in-binding driver orchestration (`local_chrome` / `ensure_driver` /
  `resolve_driver` / `launch_driver`)
- WebDriver-BiDi channel + all `bidi_*` verbs
Closing them needs a widened selenium_core.h + a Swift toolchain to verify.

<!-- append other bindings' deferrals below as their agents report -->
