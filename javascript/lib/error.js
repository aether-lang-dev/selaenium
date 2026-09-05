// The Selenium error hierarchy, shaped to mainstream selenium-webdriver (npm).
//
// Upstream exposes an `error` namespace of `WebDriverError` + typed `...Error`
// subclasses (lib/error.js). This binding historically shipped `...Exception`
// names (WebDriverException, NoSuchElementException, …). BOTH are provided from
// one source of truth here: each canonical upstream `...Error` class is defined
// once, and the legacy `...Exception` name is exported as an alias to the SAME
// constructor — so `instanceof` works against either name. New code should use
// the upstream `...Error` names reached via the exported `error` namespace.

'use strict'

// Base error (upstream WebDriverError). `code` carries the engine's integer
// error code (0 when not from the wire, -1 for a transport failure).
class WebDriverError extends Error {
  constructor(message = '', code = 0) {
    super(message)
    this.name = this.constructor.name
    this.code = code
  }
}

class DetachedShadowRootError extends WebDriverError {}
class ElementClickInterceptedError extends WebDriverError {}
class ElementNotInteractableError extends WebDriverError {}
class ElementNotSelectableError extends WebDriverError {}
class InsecureCertificateError extends WebDriverError {}
class InvalidArgumentError extends WebDriverError {}
class InvalidCookieDomainError extends WebDriverError {}
class InvalidCoordinatesError extends WebDriverError {}
class InvalidElementStateError extends WebDriverError {}
class InvalidSelectorError extends WebDriverError {}
class NoSuchSessionError extends WebDriverError {}
class JavascriptError extends WebDriverError {}
class MoveTargetOutOfBoundsError extends WebDriverError {}
class NoSuchAlertError extends WebDriverError {}
class NoSuchCookieError extends WebDriverError {}
class NoSuchElementError extends WebDriverError {}
class NoSuchShadowRootError extends WebDriverError {}
class NoSuchFrameError extends WebDriverError {}
class NoSuchWindowError extends WebDriverError {}
class ScriptTimeoutError extends WebDriverError {}
class SessionNotCreatedError extends WebDriverError {}
class StaleElementReferenceError extends WebDriverError {}
class TimeoutError extends WebDriverError {}
class UnableToSetCookieError extends WebDriverError {}
class UnableToCaptureScreenError extends WebDriverError {}
class UnexpectedAlertOpenError extends WebDriverError {}
class UnknownCommandError extends WebDriverError {}
class UnknownMethodError extends WebDriverError {}
class UnsupportedOperationError extends WebDriverError {}

// Engine integer error code -> the typed error class raised for it (see the
// core error_code() catalog). Codes not listed fall back to WebDriverError.
const CODE_TO_ERROR = {
  3: ElementClickInterceptedError,
  4: ElementNotInteractableError,
  11: InvalidSelectorError,
  13: JavascriptError,
  17: NoSuchElementError,
  21: TimeoutError,
  23: StaleElementReferenceError,
  24: TimeoutError,
  28: UnknownCommandError,
}

// Raise the typed error for an engine error code (always throws).
function raiseFor(code, message) {
  const Ctor = CODE_TO_ERROR[code] || WebDriverError
  throw new Ctor(message, code)
}

module.exports = {
  WebDriverError,
  DetachedShadowRootError,
  ElementClickInterceptedError,
  ElementNotInteractableError,
  ElementNotSelectableError,
  InsecureCertificateError,
  InvalidArgumentError,
  InvalidCookieDomainError,
  InvalidCoordinatesError,
  InvalidElementStateError,
  InvalidSelectorError,
  NoSuchSessionError,
  JavascriptError,
  MoveTargetOutOfBoundsError,
  NoSuchAlertError,
  NoSuchCookieError,
  NoSuchElementError,
  NoSuchShadowRootError,
  NoSuchFrameError,
  NoSuchWindowError,
  ScriptTimeoutError,
  SessionNotCreatedError,
  StaleElementReferenceError,
  TimeoutError,
  UnableToSetCookieError,
  UnableToCaptureScreenError,
  UnexpectedAlertOpenError,
  UnknownCommandError,
  UnknownMethodError,
  UnsupportedOperationError,
  CODE_TO_ERROR,
  raiseFor,
}
