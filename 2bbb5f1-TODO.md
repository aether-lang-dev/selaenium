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
  Add engine tests for any uncovered contract cases before changing the ABI.

- [ ] **Audit BiDi schema validation and malformed-message handling.**
  Upstream references: `9f4ca5a`, `e93424f`, `846ab62`, `27c86e2`, `bdb7ccc`,
  `1b26e32`, `083869c`, `7bfaedb`, and `8b8723b`. Upstream has been tightening
  schema-derived numeric bounds, unions, enum values, unknown discriminators,
  and Firefox vendor commands. Decide what belongs at Selaenium's generic JSON
  BiDi seam versus typed binding helpers. Pin the relevant W3C and Firefox
  schema sources if adopting validation; test out-of-range values, invalid
  unions, unknown response types, and vendor commands. Do not copy generated
  language-specific schema trees into the Aether engine.

- [ ] **Compare relative locators rooted at elements and shadow roots.**
  Upstream reference: `a347258` (`#17907`). Selaenium already has relative
  locator support through `selenium_core/atoms.ae` and the binding APIs. Verify
  that roots other than the document are represented and searched correctly,
  including shadow-root anchors, and that single- and multi-result behavior
  matches the intended Selenium API. Put shared behavior in the engine/ABI;
  keep language-specific object plumbing in each binding. Add focused tests
  for element and shadow-root anchors if absent.

- [ ] **Port applicable locator-atom regression cases.**
  Upstream references: `65ce702` and the atom tests added by `a347258`. The
  upstream `find-elements` implementation is not the same as Selaenium's
  relative-locator atom, so do not copy its TypeScript implementation. Review
  the edge cases and add only cases that describe behavior Selaenium supports.

- [ ] **Compare visible-text behavior with the upstream non-Latin fix.**
  Upstream reference: `5d90b1d`. Selaenium's `selenium_core/atoms.ae` has a
  compact custom text extraction path. Reproduce the upstream regression cases
  and determine whether capitalization/whitespace behavior diverges; then
  implement the needed semantics in the shared atom and test it against browser
  behavior. Do not transplant the upstream JS atom wholesale.

- [ ] **Audit Selenium Manager behavior without porting its Rust implementation.**
  Relevant upstream references include `7a54c93` (TLS validation), `f67fed5`
  (cache locking), and `ed2dda5` (Windows architecture detection under WOW64),
  alongside the manager metadata/update commits in this range. Compare the
  actual guarantees and regression tests with `selenium_core/drivermgr/`:
  validate TLS, concurrent cache population, and process-vs-OS architecture
  detection. Port a fix only where Selaenium has the same exposure, with an
  Aether test for the failure mode.

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

- [ ] **Legacy Java download endpoint removal.** Upstream reference: `f3ccc60`.
  Selaenium's engine routes the current `/session/:sessionId/se/files` download
  endpoints. Confirm no binding or engine path exposes the deprecated
  `/se/files/{fileName}` form; if none does, close this item without a change.

- [ ] **Appium-specific atom changes.** Review only where they affect the
  engine's shared browser/desktop behavior. Selaenium desktop mode targets W3C
  desktop drivers and intentionally routes commands without a browser DOM to
  W3C endpoints; do not import browser-only/Appium JavaScript atoms into the
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
