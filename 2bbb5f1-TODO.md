# Upstream review TODO: `5b3666d` → `2bbb5f1`

This is a selective porting backlog for the 461-commit SeleniumHQ upstream
delta between the classic snapshot at `5b3666d` and `upstream/trunk` at
`2bbb5f1`. It is not a request to merge SeleniumHQ wholesale. Selaenium keeps
the protocol engine in Aether and the bindings thin; upstream Java, Python,
JavaScript, .NET, Bazel, and generated-code changes need to be translated into
that architecture or left upstream-only.

## Review first

- [ ] **Check BiDi connection and event semantics against the accepted low-level contract.**
  Upstream references: `08046d5` (low-level BiDi behavioral contract),
  `4d27eb3` (Network async/event API), `5b053b5` (connection-level event
  subscription), and `2b06948` (JS generator alignment). Compare the contract
  with `selenium_core/selenium_bidi.ae` and `selenium_core/bidi_demux.ae`:
  command/reply correlation while events arrive, subscription scope, event
  queue overflow/lost-event reporting, cancellation, and close behavior.
  The audit confirmed id correlation, bounded queues, lost-event counts, and
  late-reply cancellation. It also fixed timeout/send-failure slot cleanup and
  made method-filtered waits preserve unrelated queued events; pure demux tests
  cover the latter. Keep this open until a live/injected transport test covers
  command timeout and send failure, which cannot be driven through the current
  pure demux fixture.

- [x] **Audit BiDi schema validation and malformed-message handling.**
  Upstream references: `9f4ca5a`, `e93424f`, `846ab62`, `27c86e2`, `bdb7ccc`,
  `1b26e32`, `083869c`, `7bfaedb`, and `8b8723b`. Upstream has been tightening
  schema-derived numeric bounds, unions, enum values, unknown discriminators,
  and Firefox vendor commands. Selaenium deliberately exposes a generic JSON
  BiDi seam rather than generated typed command/event objects, so this upstream
  typed-schema validation work does not map to the engine contract. The engine
  rejects unparseable frames and preserves parseable replies/events as JSON;
  parameter and payload schema validation remains with the remote end or
  caller. No generated language-specific schema trees are needed.

- [x] **Pass existing element anchors through the relative-locator seam.**
  Upstream reference: `a347258` (`#17907`). The shared relative atom now accepts
  a W3C element reference in a filter, and the Java, .NET, Python, and
  JavaScript `RelativeBy` surfaces serialize element anchors that way. Verified
  by the engine atom probe, Java ABI suite, Python ABI test, JavaScript ABI
  test, and .NET filter-shape test. The .NET SDK is absent here, so its suite
  still needs a toolchain run.

- [x] **Support relative searches from element and shadow-root contexts.**
  Upstream reference: `a347258` (`#17907`). Selaenium already has relative
  locator support through `selenium_core/atoms.ae`; the shared atom and new
  `find_relative_in` ABI now scope candidate lookup to element and shadow-root
  references, while CSS anchor lookup checks that scope before the document.
  Java, .NET, Python, and JavaScript search-context APIs route relative searches
  through it; Swift's driver, element, and shadow-root surfaces expose the same
  scoped call. The engine atom probe and Java/Python/JavaScript suites cover
  reference marshalling and single-/multi-result routing. The Swift aeb node
  reported its test phase as unavailable (`swift` is not installed), and the
  .NET SDK is also absent, so those compile/test paths still need toolchain
  runs. The JavaScript declaration now accepts `RelativeBy` as a locator.

- [x] **Port applicable locator-atom regression cases.**
  Upstream references: `65ce702` and the atom tests added by `a347258`. The
  upstream `find-elements` implementation is not the same as Selaenium's
  relative-locator atom, so do not copy its TypeScript implementation. The
  newline-in-id/name case exposed incomplete shared CSS string escaping; the
  engine now escapes those values and Java/Python/.NET relative locators ask
  the engine to normalize their `By` values. The NBSP link-text case is handled
  by the remote end because Selaenium forwards link-text strategies unchanged.
  A live Chrome test now uses duplicate IDs and a positioned outer anchor to
  prove an element-scoped relative search resolves its local anchor rather than
  the document's first match (`java/.tests.ae`, `LiveTest.liveChromeAtoms`).

- [x] **Compare visible-text behavior with the upstream non-Latin fix.**
  Upstream reference: `5d90b1d`. Selaenium's `selenium_core/atoms.ae` has a
  compact custom text extraction path. Selaenium's public `getText` issues the
  W3C `getElementText` command, so the remote end's own atom supplies this
  behavior; the optional engine `getText` atom delegates to browser `innerText`
  (with a `textContent` fallback) rather than reimplementing Selenium's
  `getVisibleText` algorithm. The upstream fix is remote-driver work, not a
  client-engine port.

- [ ] **Audit Selenium Manager behavior without porting its Rust implementation.**
  Relevant upstream references include `7a54c93` (TLS validation), `f67fed5`
  (cache locking), and `ed2dda5` (Windows architecture detection under WOW64),
  alongside the manager metadata/update commits in this range. Compare the
  actual guarantees and regression tests with `selenium_core/drivermgr/`:
  TLS is validated by the pinned Aether TLS client (certificate chain, validity,
  and hostname); `_arch()` intentionally reports the engine target via
  `std.os.arch()`, matching the supported engine/download target on official
  builds. Driver misses now use unique staging directories and atomically
  publish the completed binary; a regression test covers a second installer
  accepting the first cache winner. Browser misses now download and extract
  into unique staging directories, merge the versioned support tree, and
  atomically publish the executable last as the cache-ready marker; the pure
  cache probe covers staged install and a concurrent winner. The audit remains
  open until x86-engine execution under WOW64 is either supported or explicitly
  excluded.

## Consider adding when we want the capability

- [ ] **BiDi screencast and viewport controls.** Upstream references:
  `c01a157` and `03002c9`. Search for equivalent commands in the current
  generic `bidi_send` path; if users need an ergonomic supported surface, add
  shared command construction/tests and expose it through the bindings. Avoid
  a new native ABI entry point when the generic BiDi command seam is sufficient.

- [ ] **BiDi emulation commands.** Upstream references: `2183264` and `718adc8`
  (media-feature and text-layout overrides). Validate parameter shapes and
  browser support, then add convenience wrappers only where they improve on
  `bidi_send` for real consumers.

- [ ] **BiDi browser extensions and vendor commands.** Upstream references:
  `0826d31`, `d32c5f2`, and `fd2fe0e`, plus the Firefox schema work above.
  Establish a cross-browser support contract first; keep vendor-specific
  commands explicit and do not imply that every browser implements them.

- [ ] **Other newly exposed BiDi domains and commands.** Review the upstream
  Network async/event API and Java BiDi generator (`229a802`, `46cfab1`) for
  commands or event shapes absent from the current engine and bindings. The
  generic command path may already make them usable; add typed helpers only
  with a clear consumer need and tests.

## Conditional / not currently a port

- [ ] **Grid downloadable-file handling.** Upstream reference: `989e662` fixes
  filenames with spaces in Grid downloads. The current Selaenium Grid hub has
  no matching file-download implementation, so there is no equivalent bug to
  transplant. Revisit this when adding Grid file downloads and include names
  with spaces in its tests.

- [x] **Legacy Java download endpoint removal.** Upstream reference: `f3ccc60`.
  Selaenium's engine routes the current `/session/:sessionId/se/files` download
  endpoints, and repository search found no binding or engine path for the
  deprecated `/se/files/{fileName}` form. No change is needed.

- [x] **Appium-specific atom changes.** Upstream reference: `5a09db1` ports
  Appium's JavaScript atom suite from Closure to TypeScript. Selaenium desktop
  mode targets W3C desktop drivers and routes commands without a browser DOM to
  W3C endpoints, so those browser/WebView atoms have no corresponding engine
  code to port. Do not import browser-only/Appium JavaScript atoms into the
  native desktop path.

## Explicitly out of scope for this delta

- Generated Chromium CDP / `devtools/vNNN` updates: Selaenium deliberately uses
  WebDriver-BiDi rather than porting CDP's generated trees.
- Selenium's per-language API implementations and generated BiDi classes as
  code: port semantics into the Aether engine and only then add thin binding
  conveniences as needed.
- Bazel, Selenium-specific CI, Java build/release, and upstream Selenium
  Manager packaging/cross-compilation changes: Selaenium has its own Aether
  build and native release matrix.
- Upstream changes with no corresponding engine, binding, or product capability
  in this repository. Keep the commit list as provenance, not as a mandate to
  reproduce every upstream change.

## Completion rule

For each reviewed item, record one of: **ported** (with Selaenium commit and
tests), **already covered** (with the existing implementation/test), **not
applicable** (with the architectural reason), or **deferred** (with the
capability or evidence needed to revisit it). Do not mark an item complete
because an upstream commit exists or because a binding-level test passes when
the shared engine behavior has not been exercised.
