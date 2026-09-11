# JS binding: chrome live tests fail with "transport failure" (firefox live is green)

Found 2026-09-11 during the browser-factory sweep. PRE-EXISTING (not caused by
the firefox()/edge()/safari() additions or the .d.ts).

## Symptom
`javascript/test/live_test.js` tests 9/10/11 ("live chrome + surface", "+ bidi",
"+ atoms") fail with `WebDriverError: transport failure`, surfaced as
"generated asynchronous activity after the test ended … unhandledRejection".
The NEW "live firefox" test (test 7) passes green through the SAME engine path.

## What's already fixed (this session, separate small bugs in the same file)
- Four sync property reads `elem.text` / `elem.tagName` in the chrome live tests
  were changed to `await elem.getText()` / `(await elem.getTagName())` — the JS
  WebElement is async (getText()/getTagName() only), so those assertions were
  comparing `undefined` and failing independent of any driver.
- ffi_test.js used `s.By.CSS_SELECTOR` / `s.By.ID` (undefined — the API is the
  method `By.css()`/`By.id()`, and `locator()` takes a strategy STRING) → fixed
  to `s.locator('css selector', …)` / `s.locator('id', …)`. ffi_test now 5/5.

## What REMAINS (this ask)
The chrome live SESSION itself won't connect (transport failure), yet:
- `resolveDriver('chrome')` returns the correct MATCHED driver
  (`~/.cache/selenium/chromedriver/linux64/138.0.7204.183/chromedriver`, matching
  system Chrome 138) — so it is NOT the chromedriver-152-vs-Chrome-138 PATH skew.
- Firefox live (same ensureDriver/launch/get path) is green.
So the fault is chrome-live-specific: likely the test's own driver/content-server
setup (test/content_server.js), a chrome launch-arg/binary issue, or a genuine
bug in the chrome path exercised only by these three tests. Async teardown ordering
("activity after the test ended") also suggests a not-awaited promise in the
setup/teardown of these specific subtests.

## Repro
```
cd javascript
export SELENIUM_CORE_LIB=$PWD/../selenium_core/native/libselenium_core.so
node --test test/live_test.js   # test 7 (firefox) PASS; 9/10/11 (chrome) FAIL transport
```

## Next step
Debug the chrome subtests' setup vs the firefox one (which works): compare how
each acquires the driver URL + content server, and ensure every promise in
setup/teardown is awaited. Not a binding-surface bug (the surface + firefox path
are proven); scoped to the chrome live-test harness / chrome launch.
