// A compact `Capabilities` plus the `Browser` and `Capability` enums, matching
// mainstream selenium-webdriver (npm) lib/capabilities.js at the API level that
// classic scripts touch: the static browser factories (Capabilities.chrome()
// etc.), get/set/has/merge/forEach, setBrowserName/setPlatform/setPageLoadStrategy
// /setAcceptInsecureCerts, and toJSON(). Backed by a Map, like upstream.

'use strict'

const Browser = {
  CHROME: 'chrome',
  EDGE: 'MicrosoftEdge',
  FIREFOX: 'firefox',
  INTERNET_EXPLORER: 'internet explorer',
  SAFARI: 'safari',
}

const Capability = {
  ACCEPT_INSECURE_TLS_CERTS: 'acceptInsecureCerts',
  BROWSER_NAME: 'browserName',
  BROWSER_VERSION: 'browserVersion',
  LOGGING_PREFS: 'goog:loggingPrefs',
  PAGE_LOAD_STRATEGY: 'pageLoadStrategy',
  PLATFORM_NAME: 'platformName',
  PROXY: 'proxy',
  TIMEOUTS: 'timeouts',
  STRICT_FILE_INTERACTABILITY: 'strictFileInteractability',
  UNHANDLED_PROMPT_BEHAVIOR: 'unhandledPromptBehavior',
}

function toMap(other) {
  const m = new Map()
  for (const key of Object.keys(other)) {
    if (other[key] !== undefined && other[key] !== null) m.set(key, other[key])
  }
  return m
}

class Capabilities {
  constructor(other = undefined) {
    if (other instanceof Capabilities) {
      other = other.map_
    } else if (other && !(other instanceof Map)) {
      other = toMap(other)
    }
    this.map_ = new Map(other)
  }

  static chrome() {
    return new Capabilities().setBrowserName(Browser.CHROME)
  }
  static edge() {
    return new Capabilities().setBrowserName(Browser.EDGE)
  }
  static firefox() {
    return new Capabilities().setBrowserName(Browser.FIREFOX)
  }
  static ie() {
    return new Capabilities().setBrowserName(Browser.INTERNET_EXPLORER)
  }
  static safari() {
    return new Capabilities().setBrowserName(Browser.SAFARI)
  }

  get size() {
    return this.map_.size
  }
  get(key) {
    return this.map_.get(key)
  }
  has(key) {
    return this.map_.has(key)
  }
  keys() {
    return this.map_.keys()
  }
  set(key, value) {
    if (value !== undefined && value !== null) this.map_.set(key, value)
    else this.map_.delete(key)
    return this
  }
  delete(key) {
    this.map_.delete(key)
    return this
  }
  forEach(fn, self) {
    this.map_.forEach(fn, self)
  }
  merge(other) {
    if (other) {
      let otherMap
      if (other instanceof Capabilities) otherMap = other.map_
      else if (other instanceof Map) otherMap = other
      else otherMap = toMap(other)
      otherMap.forEach((value, key) => this.set(key, value))
    }
    return this
  }

  setBrowserName(name) {
    return this.set(Capability.BROWSER_NAME, name)
  }
  getBrowserName() {
    return this.get(Capability.BROWSER_NAME)
  }
  setPlatform(platform) {
    return this.set(Capability.PLATFORM_NAME, platform)
  }
  setPageLoadStrategy(strategy) {
    return this.set(Capability.PAGE_LOAD_STRATEGY, strategy)
  }
  setAcceptInsecureCerts(accept) {
    return this.set(Capability.ACCEPT_INSECURE_TLS_CERTS, accept)
  }
  getAcceptInsecureCerts() {
    return this.get(Capability.ACCEPT_INSECURE_TLS_CERTS)
  }

  toJSON() {
    const out = {}
    for (const [key, value] of this.map_) {
      out[key] = value && typeof value.toJSON === 'function' ? value.toJSON() : value
    }
    return out
  }
}

module.exports = { Browser, Capability, Capabilities }
