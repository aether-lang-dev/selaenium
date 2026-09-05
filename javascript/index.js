// selenium-webdriver — Selenium WebDriver for Node, re-glued to the shared
// pure-Aether WebDriver core. A thin koffi binding: the entire W3C protocol
// (command catalog, route table, path templating, By normalization, error
// decode, HTTP round-trip) lives ONCE in the in-repo Aether engine
// (core/selenium_core.ae) and is shared by every language binding via
// libselenium_core.so. This package is the Node face — it carries no protocol
// logic.
//
//   const { Builder, By, until, Key } = require('selenium-webdriver')
//   const driver = new Builder().forBrowser('chrome').build()  // engine launches chromedriver
//   await driver.get('https://example.com')
//   console.log(await driver.getTitle())
//   await driver.findElement(By.css('a')).click()
//   await driver.wait(until.titleContains('Example'), 5000)
//   await driver.quit()
//
// ABI: async/Promise-returning, matching mainstream selenium-webdriver exactly.
// The engine's FFI round-trip blocks internally, but the public surface is fully
// async (see lib/webdriver.js) so an unmodified mainstream await-style script
// runs unchanged.

'use strict'

const { configure } = require('./lib/native')
const webdriver = require('./lib/webdriver')
const by = require('./lib/by')
const error = require('./lib/error')
const input = require('./lib/input')
const until = require('./lib/until')
const select = require('./lib/select')
const capabilities = require('./lib/capabilities')
const logging = require('./lib/logging')

// Legacy `...Exception` names (this port's earlier ABI) aliased to the canonical
// upstream `...Error` classes — one source of truth in lib/error.js. Exported at
// top level so existing `instanceof s.NoSuchElementException` code keeps working.
const legacyExceptionAliases = {
  WebDriverException: error.WebDriverError,
  NoSuchElementException: error.NoSuchElementError,
  StaleElementReferenceException: error.StaleElementReferenceError,
  ElementClickInterceptedException: error.ElementClickInterceptedError,
  ElementNotInteractableException: error.ElementNotInteractableError,
  InvalidSelectorException: error.InvalidSelectorError,
  NoSuchWindowException: error.NoSuchWindowError,
  NoSuchFrameException: error.NoSuchFrameError,
  TimeoutException: error.TimeoutError,
  JavascriptException: error.JavascriptError,
  UnknownCommandException: error.UnknownCommandError,
}

module.exports = {
  // ---- entry points ----
  Builder: webdriver.Builder,
  WebDriver: webdriver.WebDriver,
  WebElement: webdriver.WebElement,
  LocalChrome: webdriver.LocalChrome,

  // ---- locators ----
  By: by.By,
  RelativeBy: by.RelativeBy,
  withTagName: by.withTagName,
  locateWith: by.locateWith,
  escapeCss: by.escapeCss,

  // ---- wait conditions ----
  until,
  Condition: webdriver.Condition,
  WebElementCondition: webdriver.WebElementCondition,

  // ---- input ----
  Key: input.Key,
  Keys: input.Key, // convenience alias (Python-style plural); Key is the upstream name
  Button: input.Button,
  Origin: input.Origin,
  Actions: input.Actions,
  FileDetector: input.FileDetector,

  // ---- support helpers ----
  Select: select.Select,

  // ---- capabilities ----
  Capabilities: capabilities.Capabilities,
  Capability: capabilities.Capability,
  Browser: capabilities.Browser,

  // ---- facades (also reachable via driver.manage()/navigate()/switchTo()) ----
  Navigation: webdriver.Navigation,
  Options: webdriver.Options,
  Window: webdriver.Window,
  TargetLocator: webdriver.TargetLocator,
  Alert: webdriver.Alert,

  // ---- error namespace (upstream shape) + top-level Error classes ----
  error,
  logging,
  ...error,
  ...legacyExceptionAliases,

  // ---- WebDriver-BiDi (binding-specific advanced surface) ----
  BiDi: webdriver.BiDi,
  BidiEvent: webdriver.BidiEvent,

  // ---- driver orchestration ----
  DriverProcess: webdriver.DriverProcess,
  resolveDriver: webdriver.resolveDriver,
  launchDriver: webdriver.launchDriver,
  ensureDriver: webdriver.ensureDriver,

  // ---- pure engine helpers ----
  route: webdriver.route,
  errorCode: webdriver.errorCode,
  locator: webdriver.locator,

  // ---- native lib config ----
  configureNativeLib: configure,
  VERSION: '0.1.0',
  version: '0.1.0',
}
