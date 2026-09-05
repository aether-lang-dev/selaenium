// The Selenium 4.x `By` locator factory and relative-locator support, shaped to
// mainstream selenium-webdriver (npm). Names and signatures match upstream
// (lib/by.js): By.id/name/className/css/linkText/partialLinkText/tagName/xpath,
// plus By.js(scriptOrFunction, ...args), locateWith(...)/RelativeBy, withTagName,
// checkedLocator, and escapeCss.
//
// DEVIATION FROM UPSTREAM (deliberate, engine-driven): upstream `By.id` etc.
// pre-escape to a `css selector` value in JS. Here the raw strategy string is
// preserved on `.using` and the shared Aether engine performs the id/name/
// className -> CSS rewrite (see lib/native byLocator). Every locator still
// carries upstream's `.using`/`.value` fields plus `toObject()`, so mainstream
// code that inspects a locator behaves identically.

'use strict'

class InvalidCharacterError extends Error {
  constructor() {
    super()
    this.name = this.constructor.name
  }
}

// Upstream's CSS.escape shim — retained verbatim so By.className()/escapeCss()
// match mainstream character handling exactly.
function escapeCss(css) {
  if (typeof css !== 'string') {
    throw new TypeError('input must be a string')
  }
  let ret = ''
  const n = css.length
  for (let i = 0; i < n; i++) {
    const c = css.charCodeAt(i)
    if (c == 0x0) {
      throw new InvalidCharacterError()
    }
    if (
      (c >= 0x0001 && c <= 0x001f) ||
      c == 0x007f ||
      (i == 0 && c >= 0x0030 && c <= 0x0039) ||
      (i == 1 && c >= 0x0030 && c <= 0x0039 && css.charCodeAt(0) == 0x002d)
    ) {
      ret += '\\' + c.toString(16) + ' '
      continue
    }
    if (i == 0 && c == 0x002d && n == 1) {
      ret += '\\' + css.charAt(i)
      continue
    }
    if (
      c >= 0x0080 ||
      c == 0x002d ||
      c == 0x005f ||
      (c >= 0x0030 && c <= 0x0039) ||
      (c >= 0x0041 && c <= 0x005a) ||
      (c >= 0x0061 && c <= 0x007a)
    ) {
      ret += css.charAt(i)
      continue
    }
    ret += '\\' + css.charAt(i)
  }
  return ret
}

// A W3C locator: { using, value }. `using` is the strategy string the engine
// understands (id/name/"class name"/"css selector"/"tag name"/link text/…); the
// engine rewrites id/name/class name to CSS on the wire.
class By {
  constructor(using, value) {
    this.using = using
    this.value = value
  }

  static id(value) {
    return new By('id', value)
  }
  static name(value) {
    return new By('name', value)
  }
  static className(value) {
    return new By('class name', value)
  }
  static css(selector) {
    return new By('css selector', selector)
  }
  static cssSelector(selector) {
    return new By('css selector', selector)
  }
  static tagName(name) {
    return new By('tag name', name)
  }
  static linkText(text) {
    return new By('link text', text)
  }
  static partialLinkText(text) {
    return new By('partial link text', text)
  }
  static xpath(xpath) {
    return new By('xpath', xpath)
  }

  // A locator backed by JavaScript: pass either a snippet returning the element
  // (with the injected `var_args` available as `arguments`) or a function that
  // takes the search context. findElement/findElements accept the returned
  // function, running it via executeScript. Matches upstream By.js.
  static js(script, ...var_args) {
    return function (driver) {
      return driver.executeScript.call(driver, script, ...var_args)
    }
  }

  toString() {
    return `By(${this.using}, ${this.value})`
  }

  toObject() {
    const tmp = {}
    tmp[this.using] = this.value
    return tmp
  }
}

function getLocator(locatorOrElement) {
  let toFind
  if (locatorOrElement instanceof By) {
    toFind = locatorOrElement.toObject()
  } else {
    toFind = locatorOrElement
  }
  return toFind
}

// Begin a relative-locator chain with a base tag name: withTagName('div').above(el)
function withTagName(tagName) {
  return new RelativeBy({ 'css selector': tagName })
}

// Begin a relative-locator chain from a By/locator: locateWith(By.css('p')).below(header)
function locateWith(by) {
  return new RelativeBy(getLocator(by))
}

// A spatial (relative) locator: a base match filtered by proximity/direction to
// anchors. marshall() emits the W3C `{relative:{root, filters}}` shape upstream
// uses. This binding's engine drives relative queries through its find-relative
// atom (see WebDriver.findElement/findElements handling of RelativeBy).
class RelativeBy {
  constructor(findDetails, filters = null) {
    this.root = findDetails
    this.filters = filters || []
  }
  above(locatorOrElement) {
    this.filters.push({ kind: 'above', args: [getLocator(locatorOrElement)] })
    return this
  }
  below(locatorOrElement) {
    this.filters.push({ kind: 'below', args: [getLocator(locatorOrElement)] })
    return this
  }
  toLeftOf(locatorOrElement) {
    this.filters.push({ kind: 'left', args: [getLocator(locatorOrElement)] })
    return this
  }
  toRightOf(locatorOrElement) {
    this.filters.push({ kind: 'right', args: [getLocator(locatorOrElement)] })
    return this
  }
  straightAbove(locatorOrElement) {
    this.filters.push({ kind: 'straightAbove', args: [getLocator(locatorOrElement)] })
    return this
  }
  straightBelow(locatorOrElement) {
    this.filters.push({ kind: 'straightBelow', args: [getLocator(locatorOrElement)] })
    return this
  }
  straightToLeftOf(locatorOrElement) {
    this.filters.push({ kind: 'straightLeft', args: [getLocator(locatorOrElement)] })
    return this
  }
  straightToRightOf(locatorOrElement) {
    this.filters.push({ kind: 'straightRight', args: [getLocator(locatorOrElement)] })
    return this
  }
  near(locatorOrElement) {
    this.filters.push({ kind: 'near', args: [getLocator(locatorOrElement)] })
    return this
  }
  marshall() {
    return { relative: { root: this.root, filters: this.filters } }
  }
  toString() {
    return `RelativeBy(${JSON.stringify(this.marshall())})`
  }
}

// Normalize any accepted locator form (By, RelativeBy, function, {using,value},
// or a { strategyName: value } shorthand) into a By/RelativeBy/function.
// Matches upstream by.checkedLocator.
function checkedLocator(locator) {
  if (locator instanceof By || locator instanceof RelativeBy || typeof locator === 'function') {
    return locator
  }
  if (
    locator &&
    typeof locator === 'object' &&
    typeof locator.using === 'string' &&
    typeof locator.value === 'string'
  ) {
    return new By(locator.using, locator.value)
  }
  for (let key in locator) {
    if (
      Object.prototype.hasOwnProperty.call(locator, key) &&
      Object.prototype.hasOwnProperty.call(By, key)
    ) {
      return By[key](locator[key])
    }
  }
  throw new TypeError('Invalid locator')
}

module.exports = {
  By,
  RelativeBy,
  withTagName,
  locateWith,
  escapeCss,
  checkedLocator,
}
