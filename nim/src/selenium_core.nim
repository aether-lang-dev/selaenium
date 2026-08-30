## selenium_core — the Nim binding over the shared pure-Aether WebDriver core.
##
## There is NO protocol logic in this file, and there must never be any. The W3C
## command map, routing, By normalization, error decode and the HTTP round-trip
## all live in `core/selenium_core.ae`; the C ABI over it is `core/embed.ae`,
## whose exports `--emit=lib` mangles to `aether_sel_embed_<name>`. Everything
## below is marshalling: Nim values in, C scalars and cstrings out, and back.
##
## Why importc + a real link (not dynlib/dlopen): Nim is compiled and links by
## default, like Go/cgo and Rust. `{.passL.}` points the linker at nim/native
## and ../selenium_core/native and bakes both as rpath, so an in-tree binary finds the
## `.so` with no LD_LIBRARY_PATH. `nim/.tests.ae` stages the engine into
## nim/native/ before compiling. The engine must exist at BUILD time.
##
## Ownership: every cstring this ABI returns is caller-owned (malloc'd on the C
## side) and must be handed back to aether_sel_embed_free_string. Exactly one
## proc — takeString — touches a returned pointer, and it always frees.
##
## The int-not-long trap: use `cint` for every C int; Nim's `int` is
## pointer-sized (== C long on LP64), a 4-vs-8-byte mismatch.

import std/[os, json, strutils]

const
  srcDir = currentSourcePath().parentDir()
  nativeDir = srcDir & "/../native"
  coreNativeDir = srcDir & "/../../selenium_core/native"

{.passL: "-L" & nativeDir & " -L" & coreNativeDir & " -lselenium_core" &
         " -Wl,-rpath," & nativeDir & " -Wl,-rpath," & coreNativeDir.}

# ---- the C ABI (aether_sel_embed_*), linked at build time ----

proc selOpen(baseUrl: cstring): pointer {.importc: "aether_sel_embed_open", cdecl.}
proc selClose(h: pointer) {.importc: "aether_sel_embed_close", cdecl.}
proc selExecute(h: pointer, name, paramsJson: cstring): cint
  {.importc: "aether_sel_embed_execute", cdecl.}
proc selLastValue(h: pointer): cstring {.importc: "aether_sel_embed_last_value", cdecl.}
proc selLastStatus(h: pointer): cint {.importc: "aether_sel_embed_last_status", cdecl.}
proc selLastErrorCode(h: pointer): cint {.importc: "aether_sel_embed_last_error_code", cdecl.}
proc selLastError(h: pointer): cstring {.importc: "aether_sel_embed_last_error", cdecl.}
proc selSessionId(h: pointer): cstring {.importc: "aether_sel_embed_session_id", cdecl.}
proc selByLocator(strategy, value: cstring): cstring
  {.importc: "aether_sel_embed_by_locator", cdecl.}
proc selRoute(name: cstring): cstring {.importc: "aether_sel_embed_route", cdecl.}
proc selErrorCode(w3cError: cstring): cint {.importc: "aether_sel_embed_error_code", cdecl.}
proc selFreeString(s: cstring) {.importc: "aether_sel_embed_free_string", cdecl.}

# ---- WebDriver-BiDi (over the session's webSocketUrl) ----
# An opaque BiDi channel handle, independent of the W3C session handle.
proc selBidiOpen(wsUrl: cstring): pointer {.importc: "aether_sel_embed_bidi_open", cdecl.}
proc selBidiClose(h: pointer) {.importc: "aether_sel_embed_bidi_close", cdecl.}
proc selBidiSend(h: pointer, id: cint, meth, paramsJson: cstring): cint
  {.importc: "aether_sel_embed_bidi_send", cdecl.}
proc selBidiPump(h: pointer, timeoutMs: cint): cint {.importc: "aether_sel_embed_bidi_pump", cdecl.}
proc selBidiFd(h: pointer): cint {.importc: "aether_sel_embed_bidi_fd", cdecl.}
proc selBidiPollReply(h: pointer, id: cint): cstring
  {.importc: "aether_sel_embed_bidi_poll_reply", cdecl.}
proc selBidiPollEvent(h: pointer): cstring {.importc: "aether_sel_embed_bidi_poll_event", cdecl.}
proc selBidiLostEvents(h: pointer): cint {.importc: "aether_sel_embed_bidi_lost_events", cdecl.}
proc selBidiCancel(h: pointer, id: cint) {.importc: "aether_sel_embed_bidi_cancel", cdecl.}
proc selBidiSubscribe(h: pointer, id: cint, eventsCsv: cstring, timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_subscribe", cdecl.}
proc selBidiUnsubscribe(h: pointer, id: cint, eventsCsv: cstring, timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_unsubscribe", cdecl.}
proc selBidiWaitEvent(h: pointer, meth: cstring, timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_wait_event", cdecl.}

proc takeString(p: cstring): string =
  ## Copy an ABI-returned string into a Nim string and free the original. Every
  ## cstring this module returns goes through here; the pointer is dead after.
  if p.isNil:
    return ""
  result = $p
  selFreeString(p)

# ---- errors ----

type
  ErrorKind* = enum
    ekTransport, ekNoSuchElement, ekStaleElementReference,
    ekElementClickIntercepted, ekElementNotInteractable, ekInvalidSelector,
    ekTimeout, ekJavascript, ekUnknownCommand, ekOther

  WebDriverError* = object of CatchableError
    code*: int
    kind*: ErrorKind

proc classify(code: int, message: string): ref WebDriverError =
  let k =
    case code
    of -1: ekTransport
    of 3: ekElementClickIntercepted
    of 4: ekElementNotInteractable
    of 11: ekInvalidSelector
    of 13: ekJavascript
    of 17: ekNoSuchElement
    of 21, 24: ekTimeout
    of 23: ekStaleElementReference
    of 28: ekUnknownCommand
    else: ekOther
  result = newException(WebDriverError, message)
  result.code = code
  result.kind = k

# ---- By ----

type By* = object
const
  ById* = "id"
  ByName* = "name"
  ByCss* = "css selector"
  ByClassName* = "className"
  ByTagName* = "tag name"
  ByLinkText* = "link text"
  ByPartialLinkText* = "partial link text"
  ByXpath* = "xpath"

const w3cElementKey = "element-6066-11e4-a52e-4f735466cecf"

# ---- pure engine helpers ----

proc route*(command: string): string =
  ## The "METHOD PATH" route for a command name, or "" if unknown.
  takeString(selRoute(command.cstring))

proc errorCode*(w3cError: string): int =
  ## Map a W3C error string to its stable integer code (0 = success).
  selErrorCode(w3cError.cstring).int

proc locator*(by, value: string): string =
  ## The W3C {"using","value"} locator JSON for a (by, value) pair.
  takeString(selByLocator(by.cstring, value.cstring))

proc decodeBy(by, value: string): JsonNode =
  parseJson(locator(by, value))

# ---- WebDriver ----

type
  BiDi* = ref object
    ## The event-driven BiDi channel for a session (over the demux C ABI).
    ## Commands and events multiplex over one WebSocket via the engine's shape-C
    ## demux (a single reader routes replies to an id table and events to a
    ## bounded queue), so replies stay correlated while events stream. Command
    ## ids are supplied automatically from a per-channel monotonic counter.
    handle: pointer
    nextId: cint

  WebDriver* = ref object
    handle: pointer
    wsUrl: string
    bidi: BiDi

  WebElement* = object
    driver: WebDriver
    id: string

proc `=destroy`(d: typeof(WebDriver()[])) =
  if d.handle != nil:
    selClose(d.handle)

proc execute(d: WebDriver, command: string, params: JsonNode): JsonNode =
  let paramsJson = $params
  let rc = selExecute(d.handle, command.cstring, paramsJson.cstring).int
  if rc != 0:
    let code = selLastErrorCode(d.handle).int
    let message = takeString(selLastError(d.handle))
    if rc == -1 and code == 0:
      raise classify(-1, if message.len == 0: "transport failure" else: message)
    raise classify(code, message)
  let raw = takeString(selLastValue(d.handle))
  if raw.len == 0:
    return newJNull()
  parseJson(raw)

proc chrome*(commandExecutor: string, options: JsonNode = newJObject()): WebDriver =
  ## Start a Chrome session against a running chromedriver (or Grid).
  var caps = newJObject()
  for k, v in options: caps[k] = v
  caps["browserName"] = %"chrome"
  # Request a BiDi channel so `.bidi` is available on demand; the WebSocket
  # itself opens lazily (a classic script never opens it).
  caps["webSocketUrl"] = %true
  let handle = selOpen(commandExecutor.cstring)
  if handle == nil:
    raise classify(-1, "failed to open session handle")
  result = WebDriver(handle: handle)
  let session = result.execute("newSession", %*{"capabilities": {"alwaysMatch": caps}})
  # value.capabilities.webSocketUrl — the BiDi endpoint for this session.
  if session.kind == JObject and session.hasKey("capabilities"):
    let negotiated = session["capabilities"]
    if negotiated.kind == JObject and negotiated.hasKey("webSocketUrl"):
      result.wsUrl = negotiated["webSocketUrl"].getStr

proc headlessChrome*(commandExecutor: string): WebDriver =
  ## Convenience: a headless Chrome session with the standard launch args.
  chrome(commandExecutor, %*{
    "goog:chromeOptions": {
      "args": ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
    }
  })

# ---- navigation ----
proc get*(d: WebDriver, url: string) = discard d.execute("get", %*{"url": url})
proc title*(d: WebDriver): string = d.execute("getTitle", newJObject()).getStr
proc currentUrl*(d: WebDriver): string = d.execute("getCurrentUrl", newJObject()).getStr
proc pageSource*(d: WebDriver): string = d.execute("getPageSource", newJObject()).getStr
proc back*(d: WebDriver) = discard d.execute("goBack", newJObject())
proc forward*(d: WebDriver) = discard d.execute("goForward", newJObject())
proc refresh*(d: WebDriver) = discard d.execute("refresh", newJObject())

# ---- elements ----
proc elementFrom(d: WebDriver, v: JsonNode): WebElement =
  if v.kind != JObject or not v.hasKey(w3cElementKey):
    raise classify(17, "element reference key missing")
  WebElement(driver: d, id: v[w3cElementKey].getStr)

proc findElement*(d: WebDriver, by, value: string): WebElement =
  d.elementFrom(d.execute("findElement", decodeBy(by, value)))

proc findElements*(d: WebDriver, by, value: string): seq[WebElement] =
  for e in d.execute("findElements", decodeBy(by, value)):
    result.add d.elementFrom(e)

proc elExec(e: WebElement, command: string, params: JsonNode): JsonNode =
  var p = params
  p["id"] = %e.id
  e.driver.execute(command, p)

proc click*(e: WebElement) = discard e.elExec("clickElement", newJObject())
proc clear*(e: WebElement) = discard e.elExec("clearElement", newJObject())
proc sendKeys*(e: WebElement, text: string) =
  var value = newJArray()
  for ch in text: value.add %($ch)
  discard e.elExec("sendKeysToElement", %*{"text": text, "value": value})
proc text*(e: WebElement): string = e.elExec("getElementText", newJObject()).getStr
proc tagName*(e: WebElement): string = e.elExec("getElementTagName", newJObject()).getStr
proc getProperty*(e: WebElement, name: string): JsonNode =
  e.elExec("getElementProperty", %*{"name": name})
proc rect*(e: WebElement): JsonNode = e.elExec("getElementRect", newJObject())

# ---- script ----
proc executeScript*(d: WebDriver, script: string, args: JsonNode = newJArray()): JsonNode =
  d.execute("executeScript", %*{"script": script, "args": args})

# ---- windows ----
proc windowHandles*(d: WebDriver): seq[string] =
  for h in d.execute("getWindowHandles", newJObject()): result.add h.getStr
proc currentWindowHandle*(d: WebDriver): string =
  d.execute("getCurrentWindowHandle", newJObject()).getStr
proc setWindowRect*(d: WebDriver, rect: JsonNode): JsonNode = d.execute("setWindowRect", rect)
proc getWindowRect*(d: WebDriver): JsonNode = d.execute("getWindowRect", newJObject())

# ---- cookies ----
proc addCookie*(d: WebDriver, cookie: JsonNode) = discard d.execute("addCookie", %*{"cookie": cookie})
proc cookies*(d: WebDriver): JsonNode = d.execute("getCookies", newJObject())
proc cookie*(d: WebDriver, name: string): JsonNode = d.execute("getCookie", %*{"name": name})
proc deleteCookie*(d: WebDriver, name: string) = discard d.execute("deleteCookie", %*{"name": name})
proc deleteAllCookies*(d: WebDriver) = discard d.execute("deleteAllCookies", newJObject())

# ---- actions ----
proc performActions*(d: WebDriver, actions: JsonNode) = discard d.execute("actions", %*{"actions": actions})
proc clearActions*(d: WebDriver) = discard d.execute("clearActions", newJObject())

# ---- timeouts / screenshots ----
proc setTimeouts*(d: WebDriver, timeouts: JsonNode) = discard d.execute("setTimeout", timeouts)
proc screenshotBase64*(d: WebDriver): string = d.execute("screenshot", newJObject()).getStr

# ---- WebDriver-BiDi ----

const
  ## The common WebDriver-BiDi event names (W3C spec). Pass to `subscribe` and
  ## match in `nextEvent`.
  LogEntryAdded* = "log.entryAdded"
  ContextCreated* = "browsingContext.contextCreated"
  ContextDestroyed* = "browsingContext.contextDestroyed"
  NavigationStarted* = "browsingContext.navigationStarted"
  DomContentLoaded* = "browsingContext.domContentLoaded"
  Load* = "browsingContext.load"
  DownloadWillBegin* = "browsingContext.downloadWillBegin"
  BeforeRequestSent* = "network.beforeRequestSent"
  ResponseStarted* = "network.responseStarted"
  ResponseCompleted* = "network.responseCompleted"
  FetchError* = "network.fetchError"
  RealmCreated* = "script.realmCreated"
  RealmDestroyed* = "script.realmDestroyed"
  Message* = "script.message"

proc nextBidiId(b: BiDi): cint =
  result = b.nextId
  b.nextId.inc

proc subscribe*(b: BiDi, events: varargs[string], timeoutMs = 10000): JsonNode =
  ## session.subscribe to one or more event names; wait for the ack. Returns the
  ## ack payload. After this, matching events arrive on the queue (drain via
  ## `nextEvent`).
  let csv = events.join(",")
  let raw = takeString(selBidiSubscribe(b.handle, b.nextBidiId, csv.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc unsubscribe*(b: BiDi, events: varargs[string], timeoutMs = 10000): JsonNode =
  let csv = events.join(",")
  let raw = takeString(selBidiUnsubscribe(b.handle, b.nextBidiId, csv.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc nextEvent*(b: BiDi, meth: string, timeoutMs = 5000): JsonNode =
  ## Block until an event whose `method` matches arrives, or timeout. Returns the
  ## event JSON, or nil on timeout/close. (Subscribe first.)
  let raw = takeString(selBidiWaitEvent(b.handle, meth.cstring, timeoutMs.cint))
  if raw.len == 0: nil else: parseJson(raw)

proc command*(b: BiDi, meth: string, params: JsonNode = newJObject(),
              timeoutMs = 10000): JsonNode =
  ## Issue any BiDi command and return its reply payload. Reaches BiDi methods
  ## with no dedicated wrapper (script.evaluate, network.*, ...).
  let cid = b.nextBidiId
  let paramsJson = $params
  if selBidiSend(b.handle, cid, meth.cstring, paramsJson.cstring) != 0:
    raise classify(-1, "BiDi send failed: " & meth)
  var waited = 0
  const step = 50
  while waited < timeoutMs:
    let reply = takeString(selBidiPollReply(b.handle, cid))
    if reply.len != 0:
      return parseJson(reply)
    if selBidiPump(b.handle, step.cint) < 0:
      break
    waited += step
  raise classify(21, "BiDi command timed out: " & meth)

proc lostEvents*(b: BiDi): int =
  ## How many events the bounded queue has dropped since the last call (then
  ## resets) — so a consumer knows it missed events.
  selBidiLostEvents(b.handle).int

proc close*(b: BiDi) =
  if b.handle != nil:
    selBidiClose(b.handle)
    b.handle = nil

proc bidiAvailable*(d: WebDriver): bool =
  ## True if this session can use BiDi (a webSocketUrl was negotiated).
  d.wsUrl.len != 0

proc bidi*(d: WebDriver): BiDi =
  ## The event-driven BiDi surface for this session, opened lazily over the
  ## negotiated webSocketUrl. Raises if the remote end granted no BiDi URL.
  ##
  ##   d.bidi.subscribe(LogEntryAdded)
  ##   d.get(url)
  ##   let ev = d.bidi.nextEvent(LogEntryAdded, timeoutMs = 5000)
  if d.bidi == nil:
    if d.wsUrl.len == 0:
      raise classify(0, "BiDi not available: the session negotiated no webSocketUrl")
    let handle = selBidiOpen(d.wsUrl.cstring)
    if handle == nil:
      raise classify(-1, "BiDi channel failed to open")
    d.bidi = BiDi(handle: handle, nextId: 1)
  d.bidi

# ---- lifecycle ----
proc sessionId*(d: WebDriver): string = takeString(selSessionId(d.handle))
proc quit*(d: WebDriver) =
  try:
    if d.bidi != nil:
      d.bidi.close()
      d.bidi = nil
    discard d.execute("quit", newJObject())
  finally:
    if d.handle != nil:
      selClose(d.handle)
      d.handle = nil

# Re-export for tests that want strutils.contains etc.
export strutils, json
