# Desktop testing

selaenium drives desktop applications, not just browsers. There is no separate
product and no separate API: the same engine, the same bindings, the same
`find_element` you already use. You point a session at a desktop driver and
declare that intent in the capabilities.

```python
# Linux — KDE's selenium-webdriver-at-spi, driving Kate
d = WebDriver("http://127.0.0.1:4724", {"appium:app": "org.kde.kate.desktop"})
d.find_element(By.NAME, "New File").text          # 'New File'

# macOS — appium-mac2-driver, driving Calculator
d = WebDriver("http://127.0.0.1:4723", {"platformName": "mac",
              "appium:automationName": "Mac2",
              "appium:bundleId": "com.apple.calculator"})
for aid in ("One", "Add", "Two", "Equals"):
    d.find_element(By.ACCESSIBILITY_ID, aid).click()
```

Both of those are run as tests in this repo — `selenium_core/tests/atspi_live.ae`
and `mac2_live.ae` — against the real drivers and real applications.

## What makes it work

**WebDriver is a wire protocol, not a browser protocol.** A desktop driver
speaks the same `/session`, `/element`, `/click`, `/text` routes over the same
JSON envelopes. Two things differ, and the engine owns both, so no binding
carries any of it (see the one rule in `AGENTS.md`).

### 1. Locator strategies

For a browser, `By.id` / `By.name` / `By.className` are rewritten to CSS
selectors — correct, and what Selenium itself does. For a desktop driver they
are the driver's **own** properties: the UIA AutomationId, the accessible Name,
the ClassName. Rewriting them is fatal, because a desktop driver has no CSS
engine to receive the rewrite.

So in desktop mode the engine passes them through untouched, and adds Appium's
extended set. The names match `AppiumBy`, so a script written against an Appium
client reads the same here:

| | |
|---|---|
| `accessibility id` | AutomationId / accessible id / content-desc |
| `name`, `id`, `class name` | native properties, **not** CSS |
| `xpath` | the accessibility tree |
| `androidUIAutomator`, `androidViewTag`, `androidDataMatcher`, `androidViewMatcher` | `-android *` |
| `iOSPredicateString`, `iOSClassChain` | `-ios *` |
| `image`, `custom` | `-image`, `-custom` |

### 2. The atom-backed commands

`isDisplayed` / `getAttribute` / `getText` have no W3C route in mainstream
Selenium's world — it injects a JS "atom" through `executeScript`. A desktop
driver has no JavaScript engine at all, so that path is dead there. In desktop
mode the engine routes them to the real W3C endpoints instead
(`/element/:id/displayed`, `/text`, `/attribute/:name`), which every desktop
driver implements.

## How desktop mode is decided

From **your capabilities**, before the request is sent. Nobody sends
`appium:app` or `appium:automationName` to a browser, so declaring one is
taken as declaring the endpoint's nature:

- any `appium:*` capability in the request, **and** no `browserName` → desktop
- the newSession *response* can also trigger it (`appium:automationName`, or a
  native `platformName` such as `windows` / `mac` / `ios` / `android`)

It is deliberately asymmetric. Missing a desktop session costs one explicit
`session_set_native`; wrongly flipping a *browser* session would silently break
`By.id` for every browser user of every binding. So it only ever turns on, and
only on evidence.

**`appium:automationName` together with `browserName` stays a browser session** —
Appium drives browsers too.

## Which commands work

Support is **per driver, not per platform**. The engine does not keep a list of
"things desktop cannot do", because such a list would be wrong. Measured
against both drivers:

| command | KDE AT-SPI | mac2 |
|---|---|---|
| `findElement` / `findElements` | yes | yes |
| `clickElement`, `sendKeysToElement` | yes | yes |
| `getElementText`, `isElementDisplayed` | yes | yes |
| `isElementEnabled`, `isElementSelected` | yes | yes |
| `getElementRect`, `getDomAttribute` | yes | yes (driver-specific attribute names) |
| `getPageSource` | yes (accessibility tree as XML) | yes |
| `executeScript` | extension commands only | extension commands only |
| `screenshot` | needs the C++ helper | yes |
| `setTimeout`, `getElementTagName`, `get` | no | yes |
| `getTitle`, `getCurrentUrl`, `getCookies` | no | no |
| `switchToFrame`, window handles | no | no |

An unsupported command comes back as **`unknown command` (28)** naming the
command — not as a mystery error.

## Scripting

`executeScript` is the extension-command channel, since neither driver runs
JavaScript:

```python
d.execute_script("mobile: setClipboard", {"content": b64, "contentType": "plaintext"})
d.execute_script("macos: source", {"format": "xml"})
```

## Drivers

Anything that speaks W3C WebDriver over HTTP:

| platform | driver | notes |
|---|---|---|
| Windows | WinAppDriver, appium-windows-driver | UI Automation |
| macOS | appium-mac2-driver | XCTest/WebDriverAgentMac; needs **full Xcode** |
| Linux | KDE's `selenium-webdriver-at-spi` | AT-SPI2; the Flask server alone is enough for everything but screenshots |
| mobile | appium XCUITest / UiAutomator2 | same shape |

We are a **client** of these. selaenium does not implement OS-level automation
and does not fork the drivers that do — they speak the standard, and so do we.

### Not supported: the pre-W3C wire protocol

Tools built on Selenium 3 and earlier (Marathon, for example) speak the JSON
Wire Protocol: `desiredCapabilities`, a `{"sessionId","status","value"}`
envelope, and routes like `/accept_alert` and `/buttondown`. That is a
different dialect, not a locator difference, and it is not implemented here —
nor by Selenium's own 4.x clients. See
`asks/` for the analysis.
