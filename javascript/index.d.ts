// TypeScript declarations for selenium-webdriver (the Node/koffi binding over
// the shared pure-Aether WebDriver engine). Hand-written to match the public
// surface of index.js + lib/*.js, and named to mirror mainstream
// selenium-webdriver so existing TS code type-checks unchanged.
//
// The binding carries no protocol logic; every method here is a thin async
// wrapper over the engine's C ABI. Async methods return Promises (the engine's
// FFI round-trip blocks internally, but the public surface is fully async).

export as namespace seleniumWebdriver;

// ---- locators --------------------------------------------------------------

/** A W3C locator (mechanism + value). Mirrors mainstream `By`. */
export class By {
  constructor(using: string, value: string);
  using: string;
  value: string;
  static id(value: string): By;
  static name(value: string): By;
  static className(value: string): By;
  static css(selector: string): By;
  static cssSelector(selector: string): By;
  static tagName(name: string): By;
  static linkText(text: string): By;
  static partialLinkText(text: string): By;
  static xpath(xpath: string): By;
  /** A JavaScript-function locator (executed in the browser). */
  static js(script: string | Function, ...args: any[]): Function;
  toString(): string;
  toObject(): { using: string; value: string };
}

/** What `findElement`/`findElements` accept. */
export type Locator = By | Function | { using: string; value: string };

/** A relative locator (above/below/near/toLeftOf/toRightOf). */
export class RelativeBy {
  above(locatorOrElement: Locator | WebElement): RelativeBy;
  below(locatorOrElement: Locator | WebElement): RelativeBy;
  near(locatorOrElement: Locator | WebElement): RelativeBy;
  toLeftOf(locatorOrElement: Locator | WebElement): RelativeBy;
  toRightOf(locatorOrElement: Locator | WebElement): RelativeBy;
}
export function withTagName(tagName: string): RelativeBy;
export function locateWith(locator: Locator): RelativeBy;
export function escapeCss(selector: string): string;

// ---- input (keys, buttons, actions) ---------------------------------------

/** The W3C key constants (PUA code points). `Key.chord` joins + terminates. */
export const Key: {
  readonly [name: string]: string;
  chord(...keys: string[]): string;
};
export const Button: { readonly LEFT: number; readonly MIDDLE: number; readonly RIGHT: number; readonly [k: string]: number };
export const Origin: { readonly VIEWPORT: string; readonly POINTER: string; readonly [k: string]: string };

export interface MoveOptions {
  x?: number;
  y?: number;
  duration?: number;
  origin?: string | WebElement;
}

/** The W3C Actions builder. Chain gestures, then `perform()`. */
export class Actions {
  keyDown(key: string): Actions;
  keyUp(key: string): Actions;
  sendKeys(...keys: Array<string | number>): Actions;
  press(button?: number): Actions;
  release(button?: number): Actions;
  move(options?: MoveOptions): Actions;
  scroll(x: number, y: number, deltaX: number, deltaY: number, origin?: string | WebElement, duration?: number): Actions;
  click(element?: WebElement): Actions;
  contextClick(element?: WebElement): Actions;
  doubleClick(element?: WebElement): Actions;
  dragAndDrop(from: WebElement, to: WebElement | { x: number; y: number }): Actions;
  pause(duration?: number, ...devices: any[]): Actions;
  clear(): Promise<void>;
  perform(): Promise<void>;
  getSequences(): object[];
}

export class FileDetector {
  handleFile(driver: WebDriver, path: string): Promise<string>;
}

// ---- capabilities ----------------------------------------------------------

export const Browser: {
  readonly CHROME: string;
  readonly FIREFOX: string;
  readonly EDGE: string;
  readonly SAFARI: string;
  readonly [k: string]: string;
};
export const Capability: { readonly [k: string]: string };
export class Capabilities {
  constructor(other?: object | Map<string, any>);
  get(key: string): any;
  set(key: string, value: any): this;
  has(key: string): boolean;
  getBrowserName(): string | undefined;
  setBrowserName(name: string): this;
  toJSON(): object;
  static chrome(): Capabilities;
  static firefox(): Capabilities;
  static edge(): Capabilities;
  static safari(): Capabilities;
}

// ---- geometry / results ----------------------------------------------------

export interface IRectangle { x: number; y: number; width: number; height: number; }
export interface ISize { width: number; height: number; }
export interface ILocation { x: number; y: number; }
export interface Cookie {
  name: string;
  value: string;
  path?: string;
  domain?: string;
  secure?: boolean;
  httpOnly?: boolean;
  expiry?: number;
  sameSite?: string;
}

// ---- elements --------------------------------------------------------------

/** A live element reference. All accessors are async. */
export class WebElement {
  constructor(driver: WebDriver, id: string);
  getId(): string;
  getDriver(): WebDriver;
  click(): Promise<void>;
  clear(): Promise<void>;
  sendKeys(...args: Array<string | number | Promise<string | number>>): Promise<void>;
  getText(): Promise<string>;
  getTagName(): Promise<string>;
  getCssValue(cssStyleProperty: string): Promise<string>;
  getRect(): Promise<IRectangle>;
  isDisplayed(): Promise<boolean>;
  getAttribute(name: string): Promise<string | null>;
  getDomAttribute(name: string): Promise<string | null>;
  getProperty(name: string): Promise<any>;
  getAriaRole(): Promise<string>;
  getAccessibleName(): Promise<string>;
  isEnabled(): Promise<boolean>;
  isSelected(): Promise<boolean>;
  submit(): Promise<void>;
  takeScreenshot(scroll?: boolean): Promise<string>;
  findElement(locator: Locator): WebElementPromise;
  findElements(locator: Locator): Promise<WebElement[]>;
  getShadowRoot(): Promise<ShadowRoot>;
}

/** A thenable WebElement (findElement returns this — awaitable or chainable). */
export interface WebElementPromise extends WebElement, Promise<WebElement> {}

/** A shadow root as a search context (only find* are supported). */
export class ShadowRoot {
  getId(): string;
  findElement(locator: Locator): WebElementPromise;
  findElements(locator: Locator): Promise<WebElement[]>;
}

// ---- facades ---------------------------------------------------------------

export class Navigation {
  to(url: string): Promise<void>;
  back(): Promise<void>;
  forward(): Promise<void>;
  refresh(): Promise<void>;
}

export class Window {
  getRect(): Promise<IRectangle>;
  setRect(rect: Partial<IRectangle>): Promise<IRectangle>;
  getSize(): Promise<ISize>;
  setSize(size: { x?: number; y?: number; width?: number; height?: number }): Promise<void>;
  maximize(): Promise<void>;
  minimize(): Promise<void>;
  fullscreen(): Promise<void>;
}

export class Options {
  addCookie(cookie: Cookie): Promise<void>;
  deleteAllCookies(): Promise<void>;
  deleteCookie(name: string): Promise<void>;
  getCookies(): Promise<Cookie[]>;
  getCookie(name: string): Promise<Cookie | null>;
  getTimeouts(): Promise<{ implicit?: number; pageLoad?: number; script?: number }>;
  setTimeouts(timeouts: { implicit?: number; pageLoad?: number; script?: number }): Promise<void>;
  window(): Window;
}

export class TargetLocator {
  defaultContent(): Promise<void>;
  frame(id: number | WebElement | null): Promise<void>;
  parentFrame(): Promise<void>;
  window(nameOrHandle: string): Promise<void>;
  newWindow(typeHint?: 'tab' | 'window'): Promise<string>;
  alert(): Promise<Alert>;
  activeElement(): WebElementPromise;
}

export class Alert {
  getText(): Promise<string>;
  accept(): Promise<void>;
  dismiss(): Promise<void>;
  sendKeys(text: string): Promise<void>;
}

// ---- waits -----------------------------------------------------------------

export class Condition<T> {
  constructor(message: string, fn: (driver: WebDriver) => T | Promise<T>);
  fn(driver: WebDriver): T | Promise<T>;
}
export class WebElementCondition extends Condition<WebElement> {}

// ---- the driver ------------------------------------------------------------

export interface PrintOptions {
  orientation?: 'portrait' | 'landscape';
  scale?: number;
  background?: boolean;
  pageRanges?: string[];
  [k: string]: any;
}

export class WebDriver {
  getCapabilities(): Promise<Capabilities>;
  getSession(): Promise<{ getId(): string }>;

  // navigation
  get(url: string): Promise<void>;
  getCurrentUrl(): Promise<string>;
  getTitle(): Promise<string>;
  getPageSource(): Promise<string>;
  back(): Promise<void>;
  forward(): Promise<void>;
  refresh(): Promise<void>;

  // find
  findElement(locator: Locator): WebElementPromise;
  findElements(locator: Locator): Promise<WebElement[]>;
  findRelative(baseCss: string, ...filters: any[]): Promise<WebElement[]>;

  // scripts
  executeScript<T = any>(script: string | Function, ...args: any[]): Promise<T>;
  executeAsyncScript<T = any>(script: string | Function, ...args: any[]): Promise<T>;

  // waits
  wait<T>(condition: Condition<T> | Promise<T> | ((d: WebDriver) => T | Promise<T>), timeout?: number, message?: string, pollTimeout?: number): Promise<T>;
  sleep(ms: number): Promise<void>;

  // actions
  actions(options?: { async?: boolean; bridge?: boolean }): Actions;

  // windows
  getAllWindowHandles(): Promise<string[]>;
  getWindowHandle(): Promise<string>;
  close(): Promise<void>;
  switchToWindow(handle: string): Promise<void>;
  setWindowRect(rect: Partial<IRectangle>): Promise<IRectangle>;
  getWindowRect(): Promise<IRectangle>;
  maximizeWindow(): Promise<void>;
  minimizeWindow(): Promise<void>;
  fullscreenWindow(): Promise<void>;

  // cookies
  addCookie(cookie: Cookie): Promise<void>;
  getCookies(): Promise<Cookie[]>;
  getCookie(name: string): Promise<Cookie | null>;
  deleteCookie(name: string): Promise<void>;
  deleteAllCookies(): Promise<void>;

  // actions / alerts (low-level)
  performActions(actions: object): Promise<void>;
  clearActions(): Promise<void>;
  acceptAlert(): Promise<void>;
  dismissAlert(): Promise<void>;
  getAlertText(): Promise<string>;
  sendAlertText(text: string): Promise<void>;

  // timeouts
  setTimeouts(timeouts: { implicit?: number; pageLoad?: number; script?: number }): Promise<void>;
  setPageLoadTimeout(ms: number): Promise<void>;
  setScriptTimeout(ms: number): Promise<void>;
  implicitlyWait(ms: number): Promise<void>;

  // screenshots / print
  takeScreenshot(): Promise<string>;
  printPage(options?: PrintOptions): Promise<string>;

  // facades
  manage(): Options;
  navigate(): Navigation;
  switchTo(): TargetLocator;

  // BiDi
  bidiAvailable(): boolean;
  bidi(): Promise<BiDi>;

  quit(): Promise<void>;
}

// ---- Builder ---------------------------------------------------------------

/** Selenium 4.x session entry point: chain forBrowser/usingServer, then build(). */
export class Builder {
  forBrowser(name: string): this;
  usingServer(url: string): this;
  withCapabilities(caps: Capabilities | object): this;
  usingTls(tls: { caPath?: string; insecure?: boolean }): this;
  setChromeOptions(options: object): this;
  setFirefoxOptions(options: object): this;
  setEdgeOptions(options: object): this;
  /** Returns a ready WebDriver (this port builds synchronously; still awaitable). */
  build(): WebDriver;
}

// ---- session factories -----------------------------------------------------

/** A managed driver process (resolve + launch + health-wait). */
export class DriverProcess {
  url(): string;
  pid(): number;
  stop(): void;
}
export function resolveDriver(browser: string, hint?: string): string;
export function launchDriver(driverPath: string, timeoutMs?: number): DriverProcess;
export function ensureDriver(browser: string, hint?: string, timeoutMs?: number): DriverProcess;

/** Convenience: launch the engine's own chromedriver and build a WebDriver. */
export class LocalChrome {
  static build(options?: object, hint?: string, timeoutMs?: number): WebDriver;
}

// ---- WebDriver-BiDi (advanced) ---------------------------------------------

export class BidiEvent {
  method: string;
  params: any;
}
export class BiDi {
  subscribe(...events: string[]): Promise<any>;
  unsubscribe(...events: string[]): Promise<any>;
  nextEvent(method: string, timeoutMs?: number): Promise<BidiEvent | null>;
  command(method: string, params?: object, timeoutMs?: number): Promise<any>;
  getTree(timeoutMs?: number): Promise<any>;
  topContext(timeoutMs?: number): Promise<string>;
  evaluate(expression: string, timeoutMs?: number): Promise<any>;
  evaluateValue(expression: string, timeoutMs?: number): Promise<any>;
  navigate(url: string, timeoutMs?: number): Promise<any>;
  addIntercept(phasesCsv?: string, urlPattern?: string, timeoutMs?: number): Promise<string>;
  close(): void;
}

// ---- support helpers -------------------------------------------------------

/** A <select> wrapper mirroring Selenium's Select support. */
export class Select {
  constructor(element: WebElement);
  isMultiple(): Promise<boolean>;
  getOptions(): Promise<WebElement[]>;
  getAllSelectedOptions(): Promise<WebElement[]>;
  getFirstSelectedOption(): Promise<WebElement>;
  selectByVisibleText(text: string): Promise<void>;
  selectByValue(value: string): Promise<void>;
  selectByIndex(index: number): Promise<void>;
  deselectAll(): Promise<void>;
  deselectByVisibleText(text: string): Promise<void>;
  deselectByValue(value: string): Promise<void>;
  deselectByIndex(index: number): Promise<void>;
}

// ---- pure engine helpers ---------------------------------------------------

export function route(command: string): string;
export function errorCode(w3cError: string): number;
export function locator(by: string, value: string): string;
export function configureNativeLib(pathOrOptions: string | { path?: string }): void;

export const VERSION: string;
export const version: string;

// ---- errors ----------------------------------------------------------------

export class WebDriverError extends Error {
  code: number;
  constructor(message?: string, code?: number);
}
export class DetachedShadowRootError extends WebDriverError {}
export class ElementClickInterceptedError extends WebDriverError {}
export class ElementNotInteractableError extends WebDriverError {}
export class ElementNotSelectableError extends WebDriverError {}
export class InsecureCertificateError extends WebDriverError {}
export class InvalidArgumentError extends WebDriverError {}
export class InvalidCookieDomainError extends WebDriverError {}
export class InvalidCoordinatesError extends WebDriverError {}
export class InvalidElementStateError extends WebDriverError {}
export class InvalidSelectorError extends WebDriverError {}
export class NoSuchSessionError extends WebDriverError {}
export class JavascriptError extends WebDriverError {}
export class MoveTargetOutOfBoundsError extends WebDriverError {}
export class NoSuchAlertError extends WebDriverError {}
export class NoSuchCookieError extends WebDriverError {}
export class NoSuchElementError extends WebDriverError {}
export class NoSuchShadowRootError extends WebDriverError {}
export class NoSuchFrameError extends WebDriverError {}
export class NoSuchWindowError extends WebDriverError {}
export class ScriptTimeoutError extends WebDriverError {}
export class SessionNotCreatedError extends WebDriverError {}
export class StaleElementReferenceError extends WebDriverError {}
export class TimeoutError extends WebDriverError {}
export class UnableToSetCookieError extends WebDriverError {}
export class UnableToCaptureScreenError extends WebDriverError {}
export class UnexpectedAlertOpenError extends WebDriverError {}
export class UnknownCommandError extends WebDriverError {}
export class UnknownMethodError extends WebDriverError {}
export class UnsupportedOperationError extends WebDriverError {}

// Legacy `...Exception` aliases (this port's earlier ABI), kept for compat.
export { WebDriverError as WebDriverException };
export { NoSuchElementError as NoSuchElementException };
export { StaleElementReferenceError as StaleElementReferenceException };
export { ElementClickInterceptedError as ElementClickInterceptedException };
export { ElementNotInteractableError as ElementNotInteractableException };
export { InvalidSelectorError as InvalidSelectorException };
export { NoSuchWindowError as NoSuchWindowException };
export { NoSuchFrameError as NoSuchFrameException };
export { TimeoutError as TimeoutException };
export { JavascriptError as JavascriptException };
export { UnknownCommandError as UnknownCommandException };

// ---- namespaces (upstream shape) -------------------------------------------

export namespace until {
  function ableToSwitchToFrame(frame: number | WebElement | Locator): Condition<boolean>;
  function alertIsPresent(): Condition<Alert>;
  function elementIsDisabled(element: WebElement): WebElementCondition;
  function elementIsEnabled(element: WebElement): WebElementCondition;
  function elementIsNotSelected(element: WebElement): WebElementCondition;
  function elementIsNotVisible(element: WebElement): WebElementCondition;
  function elementIsSelected(element: WebElement): WebElementCondition;
  function elementIsVisible(element: WebElement): WebElementCondition;
  function elementLocated(locator: Locator): WebElementCondition;
  function elementsLocated(locator: Locator): Condition<WebElement[]>;
  function elementTextContains(element: WebElement, substr: string): WebElementCondition;
  function elementTextIs(element: WebElement, text: string): WebElementCondition;
  function elementTextMatches(element: WebElement, regex: RegExp): WebElementCondition;
  function stalenessOf(element: WebElement): Condition<boolean>;
  function titleContains(substr: string): Condition<boolean>;
  function titleIs(title: string): Condition<boolean>;
  function titleMatches(regex: RegExp): Condition<boolean>;
  function urlContains(substrUrl: string): Condition<boolean>;
  function urlIs(url: string): Condition<boolean>;
  function urlMatches(regex: RegExp): Condition<boolean>;
}

export namespace error {
  export {
    WebDriverError, DetachedShadowRootError, ElementClickInterceptedError,
    ElementNotInteractableError, ElementNotSelectableError, InsecureCertificateError,
    InvalidArgumentError, InvalidCookieDomainError, InvalidCoordinatesError,
    InvalidElementStateError, InvalidSelectorError, NoSuchSessionError, JavascriptError,
    MoveTargetOutOfBoundsError, NoSuchAlertError, NoSuchCookieError, NoSuchElementError,
    NoSuchShadowRootError, NoSuchFrameError, NoSuchWindowError, ScriptTimeoutError,
    SessionNotCreatedError, StaleElementReferenceError, TimeoutError, UnableToSetCookieError,
    UnableToCaptureScreenError, UnexpectedAlertOpenError, UnknownCommandError,
    UnknownMethodError, UnsupportedOperationError,
  };
}

export namespace logging {
  class Level { name: string; value: number; }
  interface Entry { level: Level; message: string; timestamp: number; type: string; }
}
