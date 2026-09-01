// selenium-webdriver — Selenium WebDriver for Node, re-glued to the shared
// pure-Aether WebDriver core. A thin koffi binding: the entire W3C protocol
// (command catalog, route table, path templating, By normalization, error
// decode, HTTP round-trip) lives ONCE in the in-repo Aether engine
// (core/selenium_core.ae) and is shared by every language binding via
// libselenium_core.so. This package is the Node face — it carries no protocol
// logic.
//
//   const { Builder, By } = require('selenium-webdriver')
//   const driver = new Builder().forBrowser('chrome').build()  // engine launches chromedriver
//   driver.get('https://example.com')
//   console.log(driver.title)
//   driver.findElement(By.css('a')).click()
//   driver.quit()
//
// NOTE: calls are synchronous (the engine's FFI round-trip blocks) — a
// deliberate deviation from upstream's async API; see lib/webdriver.js.

'use strict'

const { configure } = require('./lib/native')
const wd = require('./lib/webdriver')

module.exports = {
  ...wd,
  configureNativeLib: configure,
  VERSION: '0.1.0',
}
