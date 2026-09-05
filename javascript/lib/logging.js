// A MINIMAL logging stub, shaped to mainstream selenium-webdriver (npm)
// lib/logging.js at the surface classic scripts touch: logging.Type,
// logging.Level, logging.getLogger(name) -> a no-op Logger, logging.Preferences,
// and the console-handler installers (no-ops).
//
// DEVIATION / LIMITATION: this is a STUB. The shared Aether engine does not
// surface a browser-log channel through this binding, so getLogger() returns a
// silent logger and there is no driver.manage().logs() log retrieval. The types
// exist so `require('selenium-webdriver').logging.*` resolves and code that
// merely references Level/Type/Preferences keeps working. If real log capture is
// needed, prefer the WebDriver-BiDi log surface (driver.bidi, log.entryAdded).

'use strict'

// syslog-style level table (name + numeric value), matching upstream ordering.
class Level {
  constructor(name, value) {
    this.name_ = name
    this.value_ = value
  }
  get name() {
    return this.name_
  }
  get value() {
    return this.value_
  }
  toString() {
    return this.name_
  }
}

Level.OFF = new Level('OFF', Infinity)
Level.SEVERE = new Level('SEVERE', 1000)
Level.WARNING = new Level('WARNING', 900)
Level.INFO = new Level('INFO', 800)
Level.DEBUG = new Level('DEBUG', 700)
Level.FINE = new Level('FINE', 500)
Level.FINER = new Level('FINER', 400)
Level.FINEST = new Level('FINEST', 300)
Level.ALL = new Level('ALL', 0)

// The standard log types.
const Type = {
  BROWSER: 'browser',
  CLIENT: 'client',
  DRIVER: 'driver',
  PERFORMANCE: 'performance',
  SERVER: 'server',
}

// A no-op logger. The methods exist so callers can log freely; nothing is
// emitted (see the module note).
class Logger {
  constructor(name, level = Level.OFF) {
    this.name = name
    this.level_ = level
  }
  getLevel() {
    return this.level_
  }
  setLevel(level) {
    this.level_ = level
  }
  isLoggable() {
    return false
  }
  log() {}
  severe() {}
  warning() {}
  info() {}
  debug() {}
  fine() {}
  finer() {}
  finest() {}
}

const ROOT = new Logger('')

function getLogger() {
  return ROOT
}

// A record of a single log entry (kept for type compatibility).
class Entry {
  constructor(level, message, timestamp = Date.now(), type = '') {
    this.level = level
    this.message = message
    this.timestamp = timestamp
    this.type = type
  }
  toJSON() {
    return {
      level: this.level && this.level.name ? this.level.name : this.level,
      message: this.message,
      timestamp: this.timestamp,
      type: this.type,
    }
  }
}

// Desired logging levels per type. Serializes to goog:loggingPrefs, as upstream.
class Preferences {
  constructor() {
    this.prefs_ = new Map()
  }
  setLevel(type, level) {
    this.prefs_.set(type, level instanceof Level ? level.name : level)
  }
  toJSON() {
    const out = {}
    for (const [type, level] of this.prefs_) out[type] = level
    return out
  }
}

function getLevel(nameOrValue) {
  if (nameOrValue instanceof Level) return nameOrValue
  for (const key of Object.keys(Level)) {
    const lvl = Level[key]
    if (lvl instanceof Level && (lvl.name === nameOrValue || lvl.value === nameOrValue)) return lvl
  }
  return Level.ALL
}

function noop() {}

module.exports = {
  Entry,
  Level,
  Logger,
  Preferences,
  Type,
  getLevel,
  getLogger,
  addConsoleHandler: noop,
  installConsoleHandler: noop,
  removeConsoleHandler: noop,
}
