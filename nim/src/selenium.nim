## selenium — the Nim binding over the shared pure-Aether WebDriver core.
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

import std/[os, json, strutils, sequtils, unicode]

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
proc selBuildRequest(name, sessionId, paramsJson: cstring): cstring
  {.importc: "aether_sel_embed_build_request", cdecl.}
proc selErrorCode(w3cError: cstring): cint {.importc: "aether_sel_embed_error_code", cdecl.}
proc selFreeString(s: cstring) {.importc: "aether_sel_embed_free_string", cdecl.}

# ---- atom-backed commands (a shared JS atom run in-page by the engine) ----
proc selExecuteAtom(h: pointer, atom, elemId, extraJson: cstring): cint
  {.importc: "aether_sel_embed_execute_atom", cdecl.}
proc selIsDisplayed(h: pointer, elemId: cstring): cint
  {.importc: "aether_sel_embed_is_displayed", cdecl.}
proc selGetAttribute(h: pointer, elemId, name: cstring): cint
  {.importc: "aether_sel_embed_get_attribute", cdecl.}
proc selAtomStrArg(s: cstring): cstring
  {.importc: "aether_sel_embed_atom_str_arg", cdecl.}
proc selFindRelative(h: pointer, baseCss, filtersJson: cstring): cint
  {.importc: "aether_sel_embed_find_relative", cdecl.}

# ---- TLS config (per session handle; set on the `open` handle before newSession) ----
proc selSetCa(h: pointer, caPath: cstring) {.importc: "aether_sel_embed_set_ca", cdecl.}
proc selSetInsecure(h: pointer, on: cint) {.importc: "aether_sel_embed_set_insecure", cdecl.}

# ---- driver orchestration (spawn/adopt a driver process in-binding) ----
# An opaque driver handle, independent of the W3C session handle.
proc selResolveDriver(browser, hint: cstring): cstring
  {.importc: "aether_sel_embed_resolve_driver", cdecl.}
proc selLaunchDriver(driverPath: cstring, timeoutMs: cint): pointer
  {.importc: "aether_sel_embed_launch_driver", cdecl.}
proc selEnsureDriver(browser, hint: cstring, timeoutMs: cint): pointer
  {.importc: "aether_sel_embed_ensure_driver", cdecl.}
proc selDriverUrl(dh: pointer): cstring {.importc: "aether_sel_embed_driver_url", cdecl.}
proc selDriverPid(dh: pointer): cint {.importc: "aether_sel_embed_driver_pid", cdecl.}
proc selStopDriver(dh: pointer) {.importc: "aether_sel_embed_stop_driver", cdecl.}

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

# Typed BiDi convenience commands (the engine issues the command and returns its
# reply JSON; the caller frees via takeString).
proc selBidiGetTree(h: pointer, id: cint, timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_get_tree", cdecl.}
proc selBidiScriptEvaluate(h: pointer, id: cint, expr, contextId: cstring,
                           timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_script_evaluate", cdecl.}
proc selBidiNavigate(h: pointer, id: cint, contextId, url: cstring,
                     timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_navigate", cdecl.}

# ---- BiDi network interception (observe / release / block requests) ----
proc selBidiNetworkAddIntercept(h: pointer, id: cint, phasesCsv, urlPattern: cstring,
                                timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_add_intercept", cdecl.}
proc selBidiNetworkRemoveIntercept(h: pointer, id: cint, interceptId: cstring,
                                   timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_remove_intercept", cdecl.}
proc selBidiNetworkContinueRequest(h: pointer, id: cint, requestId: cstring,
                                   timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_continue_request", cdecl.}
proc selBidiNetworkFailRequest(h: pointer, id: cint, requestId: cstring,
                               timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_fail_request", cdecl.}
proc selBidiNetworkProvideResponse(h: pointer, id: cint, requestId: cstring,
                                   status: cint, contentType, body: cstring,
                                   timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_provide_response", cdecl.}
proc selBidiNetworkContinueWithAuth(h: pointer, id: cint, requestId: cstring,
                                    username, password: cstring,
                                    timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_continue_with_auth", cdecl.}
proc selBidiNetworkSetCacheBehavior(h: pointer, id: cint, behavior: cstring,
                                    timeoutMs: cint): cstring
  {.importc: "aether_sel_embed_bidi_network_set_cache_behavior", cdecl.}

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
  ## A locator: a Selenium-style mechanism/value pair, built through the
  ## `By.id`/`By.cssSelector`/... factory procs and passed to `findElement`/
  ## `findElements`. Mirrors Java's `By`.
  ##
  ##   d.findElement(By.id("hdr"))
  ##   d.findElements(By.cssSelector("a"))
  ##
  ## `strategy` matches the engine's by_locator inputs; the engine rewrites
  ## id/name/"class name" to CSS.
  strategy*: string
  value*: string

proc id*(_: typedesc[By], value: string): By = By(strategy: "id", value: value)
proc name*(_: typedesc[By], value: string): By = By(strategy: "name", value: value)
proc className*(_: typedesc[By], value: string): By =
  By(strategy: "class name", value: value)
proc cssSelector*(_: typedesc[By], value: string): By =
  By(strategy: "css selector", value: value)
proc tagName*(_: typedesc[By], value: string): By =
  By(strategy: "tag name", value: value)
proc linkText*(_: typedesc[By], value: string): By =
  By(strategy: "link text", value: value)
proc partialLinkText*(_: typedesc[By], value: string): By =
  By(strategy: "partial link text", value: value)
proc xpath*(_: typedesc[By], value: string): By =
  By(strategy: "xpath", value: value)

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

proc decodeBy(by: By): JsonNode =
  parseJson(locator(by.strategy, by.value))

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
    id*: string  ## the W3C element reference; also the Actions/Select origin key

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

proc atomResult(d: WebDriver, rc: cint): JsonNode =
  ## Drain last_value after an atom call, mapping rc!=0 to a typed error exactly
  ## like `execute`. The atom verbs report success/failure through the same
  ## last_status / last_error_code / last_error channel as a W3C command.
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

proc chrome*(commandExecutor: string, options: JsonNode = newJObject(),
             caPath = "", insecure = false): WebDriver =
  ## Start a Chrome session against a running chromedriver (or Grid).
  ##
  ## `caPath` pins a private-CA bundle and `insecure` skips TLS verification
  ## entirely (a self-signed dev/staging Grid — trust the host out-of-band). Both
  ## land on the handle BEFORE newSession (the first request), which is the only
  ## point they can take effect.
  var caps = newJObject()
  for k, v in options: caps[k] = v
  caps["browserName"] = %"chrome"
  # Request a BiDi channel so `.bidi` is available on demand; the WebSocket
  # itself opens lazily (a classic script never opens it).
  caps["webSocketUrl"] = %true
  let handle = selOpen(commandExecutor.cstring)
  if handle == nil:
    raise classify(-1, "failed to open session handle")
  if caPath.len != 0:
    selSetCa(handle, caPath.cstring)
  if insecure:
    selSetInsecure(handle, 1)
  result = WebDriver(handle: handle)
  let session = result.execute("newSession", %*{"capabilities": {"alwaysMatch": caps}})
  # value.capabilities.webSocketUrl — the BiDi endpoint for this session.
  if session.kind == JObject and session.hasKey("capabilities"):
    let negotiated = session["capabilities"]
    if negotiated.kind == JObject and negotiated.hasKey("webSocketUrl"):
      result.wsUrl = negotiated["webSocketUrl"].getStr

proc headlessChrome*(commandExecutor: string, caPath = "", insecure = false): WebDriver =
  ## Convenience: a headless Chrome session with the standard launch args.
  chrome(commandExecutor, %*{
    "goog:chromeOptions": {
      "args": ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"]
    }
  }, caPath = caPath, insecure = insecure)

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

proc findElement*(d: WebDriver, by: By): WebElement =
  d.elementFrom(d.execute("findElement", decodeBy(by)))

proc findElements*(d: WebDriver, by: By): seq[WebElement] =
  for e in d.execute("findElements", decodeBy(by)):
    result.add d.elementFrom(e)

proc findRelative*(d: WebDriver, baseCss: string,
                   filters: varargs[JsonNode]): seq[WebElement] =
  ## Relative locators: elements matching `baseCss` filtered by spatial relation
  ## to anchors, nearest first. Each filter is a JSON object
  ## `{"kind": "above"|"below"|"left"|"right"|"near", "sel": "<css>"}`
  ## (`near` also accepts `"dist"`). Returns a seq of WebElement.
  var arr = newJArray()
  for f in filters: arr.add f
  let rc = selFindRelative(d.handle, baseCss.cstring, ($arr).cstring)
  let refs = d.atomResult(rc)
  if refs.kind == JArray:
    for r in refs:
      result.add d.elementFrom(r)

proc findRelativeCount*(d: WebDriver, baseCss: string,
                        filters: varargs[JsonNode]): int =
  ## The NUMBER of elements a relative-locator query matches, without
  ## materializing WebElement handles — the count-only counterpart to
  ## `findRelative`. Filters have the same shape.
  var arr = newJArray()
  for f in filters: arr.add f
  let rc = selFindRelative(d.handle, baseCss.cstring, ($arr).cstring)
  let refs = d.atomResult(rc)
  if refs.kind == JArray: refs.len else: 0

proc exists*(d: WebDriver, by: By): bool =
  ## True if at least one element matching `by` is present RIGHT NOW — an
  ## immediate presence check with no implicit wait. A clean not-found resolves
  ## to false; a transport failure still raises.
  try:
    discard d.findElement(by)
    true
  except WebDriverError as e:
    if e.kind == ekNoSuchElement: false
    else: raise

proc activeElement*(d: WebDriver): WebElement =
  ## The active (focused) element (getActiveElement) — the element that would
  ## receive keyboard input, e.g. after `sendKeys` or a programmatic focus.
  d.elementFrom(d.execute("getActiveElement", newJObject()))

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

proc isDisplayed*(e: WebElement): bool =
  ## Whether the element is shown (the isDisplayed atom, run in-page by the
  ## engine — the real visibility algorithm, not a naive style check).
  e.driver.atomResult(selIsDisplayed(e.driver.handle, e.id.cstring)).getBool

proc isEnabled*(e: WebElement): bool =
  ## Whether the element is enabled (W3C isElementEnabled) — false for a disabled
  ## form control. The clickable-wait predicate builds on this.
  e.elExec("isElementEnabled", newJObject()).getBool

proc isSelected*(e: WebElement): bool =
  ## Whether the element is selected (W3C isElementSelected) — a checked
  ## checkbox/radio, or a chosen <option>. `Select` uses this to read state.
  e.elExec("isElementSelected", newJObject()).getBool

proc getAttribute*(e: WebElement, name: string): JsonNode =
  ## The classic getAttribute(name): property-or-attribute (boolean attrs, live
  ## properties like value/checked), via the shared engine atom. Returns a JSON
  ## string, or JNull when absent. Use `getDomAttribute` for the raw W3C DOM
  ## attribute.
  e.driver.atomResult(selGetAttribute(e.driver.handle, e.id.cstring, name.cstring))

proc getDomAttribute*(e: WebElement, name: string): string =
  ## The literal DOM attribute (W3C getDomAttribute), no property fallback.
  e.elExec("getDomAttribute", %*{"name": name}).getStr

proc cssValue*(e: WebElement, prop: string): string =
  ## The computed value of the CSS property `prop` on this element
  ## (getElementValueOfCssProperty) — e.g. "display", "color", "font-size".
  ## Aliased as `valueOfCssProperty` for the classic Selenium name.
  e.elExec("getElementValueOfCssProperty", %*{"name": prop}).getStr

proc valueOfCssProperty*(e: WebElement, prop: string): string =
  ## Classic-Selenium-named alias of `cssValue`.
  e.cssValue(prop)

proc screenshotBase64*(e: WebElement): string =
  ## A PNG screenshot of just this element (takeElementScreenshot), base64 —
  ## the element-scoped counterpart to the driver's `screenshotBase64`.
  e.elExec("takeElementScreenshot", newJObject()).getStr

proc findElement*(e: WebElement, by: By): WebElement =
  ## Find a single descendant of this element (W3C findChildElement). The search
  ## is scoped to `e`'s subtree, not the whole document.
  var params = decodeBy(by)
  params["id"] = %e.id
  e.driver.elementFrom(e.driver.execute("findChildElement", params))

proc findElements*(e: WebElement, by: By): seq[WebElement] =
  ## Find all descendants of this element matching `by` (W3C findChildElements),
  ## scoped to `e`'s subtree. Empty seq if none.
  var params = decodeBy(by)
  params["id"] = %e.id
  for child in e.driver.execute("findChildElements", params):
    result.add e.driver.elementFrom(child)

# ---- script ----
proc executeScript*(d: WebDriver, script: string, args: JsonNode = newJArray()): JsonNode =
  d.execute("executeScript", %*{"script": script, "args": args})

proc executeAsyncScript*(d: WebDriver, script: string, args: JsonNode = newJArray()): JsonNode =
  ## Run an async script: the page signals completion via the injected callback
  ## (`arguments[arguments.length - 1]`). Returns the callback value.
  d.execute("executeAsyncScript", %*{"script": script, "args": args})

proc submit*(e: WebElement) =
  ## Submit the form this element belongs to. W3C WebDriver removed the dedicated
  ## `submit` endpoint, so — like the reference binding and modern Selenium —
  ## this walks up to the enclosing <form> and calls requestSubmit() (falling
  ## back to submit()) via an injected script. Raises if the element is not
  ## inside a form.
  const script = "var e=arguments[0];var f=e.form||e.closest('form');" &
    "if(!f){throw new Error('Element is not within a form');}" &
    "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"
  discard e.driver.executeScript(script, %*[{w3cElementKey: e.id}])

# ---- windows ----
proc windowHandles*(d: WebDriver): seq[string] =
  for h in d.execute("getWindowHandles", newJObject()): result.add h.getStr
proc currentWindowHandle*(d: WebDriver): string =
  d.execute("getCurrentWindowHandle", newJObject()).getStr
proc switchToWindow*(d: WebDriver, handle: string) =
  ## Switch the session's top-level browsing context to the window `handle`.
  discard d.execute("switchToWindow", %*{"handle": handle})
proc newWindow*(d: WebDriver, typeHint = "tab"): string =
  ## Open a new top-level browsing context (newWindow). `typeHint` is "tab" or
  ## "window" (a hint the browser may honor or ignore). Returns the new window's
  ## handle — pass it to `switchToWindow` to focus it. "" only if the remote end
  ## sent no handle.
  let v = d.execute("newWindow", %*{"type": typeHint})
  if v.kind == JObject and v.hasKey("handle"): v["handle"].getStr else: ""
proc closeWindow*(d: WebDriver): seq[string] =
  ## Close the current window/tab (close). Returns the window handles that
  ## remain; when it empties, the session is gone — switch to a surviving handle
  ## before issuing further commands. Does NOT end the session (use `quit`).
  let v = d.execute("close", newJObject())
  if v.kind == JArray:
    for h in v: result.add h.getStr
proc setWindowRect*(d: WebDriver, rect: JsonNode): JsonNode = d.execute("setWindowRect", rect)
proc getWindowRect*(d: WebDriver): JsonNode = d.execute("getWindowRect", newJObject())
proc maximizeWindow*(d: WebDriver): JsonNode =
  ## Maximize the current window. Returns the resulting window rect.
  d.execute("maximizeWindow", newJObject())
proc minimizeWindow*(d: WebDriver): JsonNode =
  ## Minimize (hide) the current window. Returns the resulting window rect.
  d.execute("minimizeWindow", newJObject())
proc fullscreenWindow*(d: WebDriver): JsonNode =
  ## Put the current window into fullscreen. Returns the resulting window rect.
  d.execute("fullscreenWindow", newJObject())

# ---- frames ----
type
  FrameKind* = enum
    ## How a frame is addressed: by index, by <iframe>/<frame> element, or the
    ## top-level (default) content.
    fkIndex, fkElement, fkDefault
  Frame* = object
    ## The frame to switch focus to. Build with `frameIndex`, `frame(element)`,
    ## or `defaultFrame`.
    case kind*: FrameKind
    of fkIndex: index*: int
    of fkElement: elementId*: string
    of fkDefault: discard

proc frameIndex*(index: int): Frame = Frame(kind: fkIndex, index: index)
proc frame*(element: WebElement): Frame = Frame(kind: fkElement, elementId: element.id)
proc defaultFrame*(): Frame = Frame(kind: fkDefault)

proc idJson(f: Frame): JsonNode =
  case f.kind
  of fkIndex: %f.index
  of fkElement: %*{w3cElementKey: f.elementId}
  of fkDefault: newJNull()

proc switchToFrame*(d: WebDriver, frame: Frame) =
  ## Switch the session's focus to a frame (switchToFrame): by `frameIndex(i)`,
  ## by `frame(element)`, or `defaultFrame()` for the top-level context. All
  ## subsequent element commands run inside the chosen frame until the next
  ## frame switch.
  discard d.execute("switchToFrame", %*{"id": frame.idJson})
proc switchToParentFrame*(d: WebDriver) =
  ## Switch to the parent of the current frame (switchToFrameParent) — one level
  ## out, unlike `switchToDefaultContent` which jumps to the top.
  discard d.execute("switchToFrameParent", newJObject())
proc switchToDefaultContent*(d: WebDriver) =
  ## Return focus to the top-level browsing context (switchToFrame with a null
  ## id) — equivalent to `switchToFrame(defaultFrame())`.
  d.switchToFrame(defaultFrame())

# ---- alerts ----
proc acceptAlert*(d: WebDriver) =
  ## Accept (OK) the current user-prompt / alert dialog.
  discard d.execute("acceptAlert", newJObject())
proc dismissAlert*(d: WebDriver) =
  ## Dismiss (Cancel) the current user-prompt / alert dialog.
  discard d.execute("dismissAlert", newJObject())
proc alertText*(d: WebDriver): string =
  ## The message text of the current dialog.
  d.execute("getAlertText", newJObject()).getStr
proc sendAlertText*(d: WebDriver, text: string) =
  ## Type `text` into the current prompt dialog's input field.
  discard d.execute("setAlertValue", %*{"text": text})
proc alertPresent*(d: WebDriver): bool =
  ## True if a user-prompt / alert dialog is currently present (probing it via
  ## getAlertText). A clean "no such alert" (code 15) resolves to false; other
  ## errors propagate.
  try:
    discard d.execute("getAlertText", newJObject())
    true
  except WebDriverError as e:
    if e.code == 15: false
    else: raise

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
proc setPageLoadTimeout*(d: WebDriver, ms: int) =
  ## Set the page-load timeout (ms): how long navigation may take before timing out.
  discard d.execute("setTimeout", %*{"pageLoad": ms})
proc setScriptTimeout*(d: WebDriver, ms: int) =
  ## Set the script timeout (ms): how long `executeAsyncScript` may run before timing out.
  discard d.execute("setTimeout", %*{"script": ms})
proc implicitlyWait*(d: WebDriver, ms: int) =
  ## Set the implicit wait (ms): how long `findElement` retries before failing.
  discard d.execute("setTimeout", %*{"implicit": ms})
proc screenshotBase64*(d: WebDriver): string = d.execute("screenshot", newJObject()).getStr
proc printPdf*(d: WebDriver, options: JsonNode = newJObject()): string =
  ## Print the current page to PDF (printPage), returned as a base64 string.
  ## `options` is the W3C print params (page size, margins, orientation, scale,
  ## pageRanges, ...); pass an empty object for defaults.
  d.execute("printPage", options).getStr

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
  AuthRequired* = "network.authRequired"
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

# ---- typed convenience commands ----

proc getTree*(b: BiDi, timeoutMs = 10000): JsonNode =
  ## browsingContext.getTree — the browsing contexts (each with a "context" id).
  let raw = takeString(selBidiGetTree(b.handle, b.nextBidiId, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc topContext*(b: BiDi, timeoutMs = 10000): string =
  ## The top-level browsing context id (the anchor for evaluate/navigate),
  ## or "" if there is none.
  let tree = b.getTree(timeoutMs)
  if tree.kind == JObject and tree.hasKey("result"):
    let res = tree["result"]
    if res.kind == JObject and res.hasKey("contexts"):
      let contexts = res["contexts"]
      if contexts.kind == JArray and contexts.len > 0:
        let first = contexts[0]
        if first.kind == JObject and first.hasKey("context"):
          return first["context"].getStr
  ""

proc evaluate*(b: BiDi, expr: string, timeoutMs = 30000): JsonNode =
  ## script.evaluate an expression in the top context's realm, awaiting a
  ## returned promise. Returns the reply; `["result"]["result"]` is the
  ## BiDi-typed value (e.g. {"type": "number", "value": 42}). BiDi's richer
  ## alternative to executeScript — real realms, promise-awaiting, structured
  ## value types.
  let ctx = b.topContext(timeoutMs)
  if ctx.len == 0:
    raise classify(0, "no browsing context for script.evaluate")
  let raw = takeString(selBidiScriptEvaluate(b.handle, b.nextBidiId,
    expr.cstring, ctx.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc evaluateValue*(b: BiDi, expr: string, timeoutMs = 30000): JsonNode =
  ## script.evaluate, returning just the unwrapped value (the `.value` of the
  ## BiDi-typed result), or JNull if it wasn't a simple value.
  let reply = b.evaluate(expr, timeoutMs)
  if reply.kind == JObject and reply.hasKey("result"):
    let res = reply["result"]
    if res.kind == JObject and res.hasKey("result"):
      let inner = res["result"]
      if inner.kind == JObject and inner.hasKey("value"):
        return inner["value"]
  newJNull()

proc navigate*(b: BiDi, url: string, timeoutMs = 30000): JsonNode =
  ## browsingContext.navigate the top context to url (wait: complete).
  let ctx = b.topContext(timeoutMs)
  if ctx.len == 0:
    raise classify(0, "no browsing context for navigate")
  let raw = takeString(selBidiNavigate(b.handle, b.nextBidiId,
    ctx.cstring, url.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

# ---- network interception (observe / release / block requests) ----

proc addIntercept*(b: BiDi, phases = "beforeRequestSent", urlPattern = "",
                   timeoutMs = 10000): string =
  ## network.addIntercept for a URL pattern (a full parseable URL as a "string"
  ## pattern; empty intercepts all) at the given comma-separated phases.
  ## Subscribe to the matching network.* event first if you want the
  ## paused-request events. Returns the intercept id, or "" if none.
  let raw = takeString(selBidiNetworkAddIntercept(b.handle, b.nextBidiId,
    phases.cstring, urlPattern.cstring, timeoutMs.cint))
  if raw.len == 0: return ""
  let reply = parseJson(raw)
  if reply.kind == JObject and reply.hasKey("result"):
    let res = reply["result"]
    if res.kind == JObject and res.hasKey("intercept"):
      return res["intercept"].getStr
  ""

proc removeIntercept*(b: BiDi, interceptId: string, timeoutMs = 10000): JsonNode =
  ## network.removeIntercept — stop intercepting for a previously added id.
  let raw = takeString(selBidiNetworkRemoveIntercept(b.handle, b.nextBidiId,
    interceptId.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc continueRequest*(b: BiDi, requestId: string, timeoutMs = 10000): JsonNode =
  ## Let a paused (intercepted) request proceed unchanged. requestId comes from a
  ## network event's `params.request.request` (see `eventRequestId`).
  let raw = takeString(selBidiNetworkContinueRequest(b.handle, b.nextBidiId,
    requestId.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc failRequest*(b: BiDi, requestId: string, timeoutMs = 10000): JsonNode =
  ## Block a paused request (the ad/tracker-blocking case).
  let raw = takeString(selBidiNetworkFailRequest(b.handle, b.nextBidiId,
    requestId.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc provideResponse*(b: BiDi, requestId: string, status = 200,
                      contentType = "", body = "", timeoutMs = 10000): JsonNode =
  ## Fulfill a paused (intercepted) request with a MOCK response
  ## (network.provideResponse), never hitting the network — mock an API, serve
  ## stub content, or test an error status. The mock auto-allows any origin to
  ## read the body. requestId comes from a network event's
  ## `params.request.request` (see `eventRequestId`).
  let raw = takeString(selBidiNetworkProvideResponse(b.handle, b.nextBidiId,
    requestId.cstring, status.cint, contentType.cstring, body.cstring,
    timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc continueWithAuth*(b: BiDi, requestId, username, password: string,
                       timeoutMs = 10000): JsonNode =
  ## Answer an HTTP auth challenge (a paused authRequired request) with
  ## credentials — automates basic/digest auth that classic WebDriver can't
  ## handle in headless. requestId comes from a network event's
  ## `params.request.request` (see `eventRequestId`).
  let raw = takeString(selBidiNetworkContinueWithAuth(b.handle, b.nextBidiId,
    requestId.cstring, username.cstring, password.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc setCacheBehavior*(b: BiDi, behavior = "bypass", timeoutMs = 10000): JsonNode =
  ## Set the session HTTP cache behavior: "bypass" to disable it (so every
  ## request hits the network / an intercept), "default" to restore it.
  let raw = takeString(selBidiNetworkSetCacheBehavior(b.handle, b.nextBidiId,
    behavior.cstring, timeoutMs.cint))
  if raw.len == 0: newJObject() else: parseJson(raw)

proc eventRequestId*(event: JsonNode): string =
  ## The network.request id out of a network.beforeRequestSent (or other network)
  ## event: `params.request.request`. Returns "" if absent.
  if event == nil or event.kind != JObject or not event.hasKey("params"):
    return ""
  let params = event["params"]
  if params.kind != JObject or not params.hasKey("request"):
    return ""
  let request = params["request"]
  if request.kind != JObject or not request.hasKey("request"):
    return ""
  request["request"].getStr

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

# ---- driver orchestration (spawn / adopt a driver process in-binding) --------
# The engine can resolve, download-or-cache, and launch a browser driver process
# itself — so a caller needs neither a driver on PATH nor a running Grid. These
# wrap the driver-handle C ABI (independent of the W3C session handle).

type
  DriverProcess* = ref object
    ## A driver process launched by the engine. Owns the driver handle; call
    ## `stop` (or let it fall out of scope — `=destroy` stops it) to terminate.
    handle: pointer

proc resolveDriver*(browser = "chrome", hint = ""): string =
  ## Resolve the local driver binary path for `browser` without launching it
  ## (detect/download/cache as needed). `hint` pins a version or path; ""
  ## auto-detects. Returns "" if none resolvable (offline, no cache).
  takeString(selResolveDriver(browser.cstring, hint.cstring))

proc url*(p: DriverProcess): string =
  ## The base URL the driver is listening on — pass to `chrome`/`headlessChrome`.
  if p.handle == nil: "" else: takeString(selDriverUrl(p.handle))

proc pid*(p: DriverProcess): int =
  ## The driver process id (0 if not running).
  if p.handle == nil: 0 else: selDriverPid(p.handle).int

proc stop*(p: DriverProcess) =
  ## Terminate the driver process. Idempotent.
  if p.handle != nil:
    selStopDriver(p.handle)
    p.handle = nil

proc `=destroy`(p: typeof(DriverProcess()[])) =
  if p.handle != nil:
    selStopDriver(p.handle)

proc launchDriver*(path: string, timeoutMs = 15000): DriverProcess =
  ## Launch a driver at an explicit binary path. Returns a running
  ## `DriverProcess`, or nil if it did not come up in `timeoutMs`.
  let h = selLaunchDriver(path.cstring, timeoutMs.cint)
  if h == nil: nil else: DriverProcess(handle: h)

proc ensureDriver*(browser = "chrome", hint = "", timeoutMs = 15000): DriverProcess =
  ## Resolve (detect/download/cache) AND launch a driver for `browser` in one
  ## step. Returns a running `DriverProcess`, or nil if none could be
  ## resolved/launched.
  let h = selEnsureDriver(browser.cstring, hint.cstring, timeoutMs.cint)
  if h == nil: nil else: DriverProcess(handle: h)

type
  LocalChrome* = ref object
    ## A Chrome session that spawns its own chromedriver via the engine — no
    ## driver on PATH, no Grid. The driver process is stopped on `quit`.
    driver*: WebDriver
    proc0: DriverProcess

proc localChrome*(options: JsonNode = newJObject(), hint = "", timeoutMs = 15000,
                  caPath = "", insecure = false): LocalChrome =
  ## Open a Chrome session against a chromedriver the engine spawns for us. Raises
  ## a WebDriverError if the driver can't be resolved/launched. Call `quit` to end
  ## the session and stop the driver.
  let p = ensureDriver("chrome", hint, timeoutMs)
  if p == nil:
    raise classify(-1, "could not resolve/launch chromedriver")
  result = LocalChrome(proc0: p)
  try:
    result.driver = chrome(p.url, options, caPath = caPath, insecure = insecure)
  except CatchableError:
    p.stop()
    raise

proc sessionId*(lc: LocalChrome): string = lc.driver.sessionId
proc get*(lc: LocalChrome, url: string) = lc.driver.get(url)
proc title*(lc: LocalChrome): string = lc.driver.title
proc findElement*(lc: LocalChrome, by: By): WebElement =
  lc.driver.findElement(by)

proc quit*(lc: LocalChrome) =
  ## Quit the session, then stop the self-spawned driver.
  try:
    lc.driver.quit()
  finally:
    lc.proc0.stop()

# ============================================================================
# Convenience tier — the idiomatic sugar over the thin command surface above.
# None of it adds protocol; each helper composes the primitive procs (find,
# click, executeScript, performActions, title/currentUrl, is* predicates). The
# semantics mirror the reference native binding (aether/webdriver.ae) and the
# Python support/common modules, spelled the Nim way (camelCase procs, a fluent
# ref-object Actions builder, a Keys enum-free const block).
# ============================================================================

# ---- Keys (W3C Unicode private-use code points, spec §17.4.2) ---------------
#
# The non-text keys, as the exact PUA code points the protocol defines
# (U+E000..U+E03D). Send them through sendKeys / an Actions key gesture just as
# mainstream Selenium's Keys does; the engine forwards them unchanged.
#
#   d.findElement(By.id("q")).sendKeys("selenium" & Keys.Enter)

type KeysTable* = object
  ## The key-constant table type. There is exactly one value — the `Keys` const
  ## below — so callers write `Keys.enter`, `Keys.tab`, ... The aliases
  ## (arrowLeft, command, backSpace, leftShift...) are fields sharing a value.
  null*, cancel*, help*, backspace*: string
  tab*, clear*, `return`*, enter*: string
  shift*, leftShift*, control*, leftControl*, alt*, leftAlt*: string
  pause*, escape*, space*: string
  pageUp*, pageDown*, `end`*, home*: string
  left*, arrowLeft*, up*, arrowUp*: string
  right*, arrowRight*, down*, arrowDown*: string
  insert*, delete*, semicolon*, equals*: string
  numpad0*, numpad1*, numpad2*, numpad3*, numpad4*: string
  numpad5*, numpad6*, numpad7*, numpad8*, numpad9*: string
  multiply*, add*, separator*, subtract*, decimal*, divide*: string
  f1*, f2*, f3*, f4*, f5*, f6*, f7*, f8*, f9*, f10*, f11*, f12*: string
  meta*, command*: string

const Keys* = KeysTable(
  null: "\uE000", cancel: "\uE001", help: "\uE002",
  backspace: "\uE003",
  tab: "\uE004", clear: "\uE005", `return`: "\uE006", enter: "\uE007",
  shift: "\uE008", leftShift: "\uE008",
  control: "\uE009", leftControl: "\uE009",
  alt: "\uE00A", leftAlt: "\uE00A",
  pause: "\uE00B", escape: "\uE00C", space: "\uE00D",
  pageUp: "\uE00E", pageDown: "\uE00F", `end`: "\uE010", home: "\uE011",
  left: "\uE012", arrowLeft: "\uE012",
  up: "\uE013", arrowUp: "\uE013",
  right: "\uE014", arrowRight: "\uE014",
  down: "\uE015", arrowDown: "\uE015",
  insert: "\uE016", delete: "\uE017",
  semicolon: "\uE018", equals: "\uE019",
  numpad0: "\uE01A", numpad1: "\uE01B", numpad2: "\uE01C", numpad3: "\uE01D",
  numpad4: "\uE01E", numpad5: "\uE01F", numpad6: "\uE020", numpad7: "\uE021",
  numpad8: "\uE022", numpad9: "\uE023",
  multiply: "\uE024", add: "\uE025", separator: "\uE026",
  subtract: "\uE027", decimal: "\uE028", divide: "\uE029",
  f1: "\uE031", f2: "\uE032", f3: "\uE033", f4: "\uE034",
  f5: "\uE035", f6: "\uE036", f7: "\uE037", f8: "\uE038",
  f9: "\uE039", f10: "\uE03A", f11: "\uE03B", f12: "\uE03C",
  meta: "\uE03D", command: "\uE03D")

# The one mainstream alias that can't be a distinct field (Nim folds
# backSpace/backspace to a single identifier): expose it as its own const.
const BackSpace* = Keys.backspace

proc chord*(modifier, text: string): string =
  ## A modifier chord: `modifier` held while `text` is typed, then a trailing
  ## NULL releases all held modifiers — e.g. `chord(Keys.control, "a")` for
  ## select-all. The classic `Keys.chord` helper, rendered as a single string
  ## you pass to `sendKeys`.
  modifier & text & Keys.null

# ---- explicit waits (WebDriverWait + the common ExpectedConditions) ---------
#
# Each wait polls every WAIT_POLL_MS until the condition holds or timeoutMs
# elapses, then raises WebDriverError(ekTimeout). The loop lives here in Nim —
# the engine issues single commands and holds no thread — exactly as the
# reference aether/webdriver.ae waits do. Poll cadence is 500ms, mainstream's
# default.

const WaitPollMs* = 500

proc raiseTimeout(msg: string) {.noreturn.} =
  raise classify(21, msg)

proc waitUntil*(d: WebDriver, timeoutMs: int,
                pred: proc (d: WebDriver): bool,
                pollMs = WaitPollMs): bool {.discardable.} =
  ## Poll `pred(d)` every `pollMs` (default WAIT_POLL_MS) until it returns true;
  ## return true. Raises a timeout WebDriverError if the budget elapses first.
  ## The general escape hatch behind every wait* — the predicate re-reads the
  ## live DOM each attempt, which is what an app that re-renders from a server
  ## push needs (click returns before the page settles, so poll the state, don't
  ## sleep()).
  ##
  ##   d.waitUntil(4000, proc (d: WebDriver): bool =
  ##     d.findElement(By.id("status")).text == "Approved")
  var waited = 0
  while true:
    if pred(d): return true
    if waited >= timeoutMs: break
    sleep(pollMs)
    waited += pollMs
  raiseTimeout("timed out after " & $timeoutMs & "ms waiting for condition")

proc waitUntilNot*(d: WebDriver, timeoutMs: int,
                   pred: proc (d: WebDriver): bool,
                   pollMs = WaitPollMs): bool {.discardable.} =
  ## The negation of `waitUntil`: poll `pred(d)` every `pollMs` until it returns
  ## false; return true. Raises a timeout WebDriverError if it stays true past
  ## the budget. (mainstream Wait.until_not)
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = not pred(d), pollMs)

proc tryFind(d: WebDriver, by: By): WebElement =
  ## findElement that yields a default (empty-id) WebElement instead of raising
  ## when absent — the polling primitive under the element waits.
  try:
    result = d.findElement(by)
  except WebDriverError as e:
    if e.kind == ekNoSuchElement:
      return WebElement(driver: d, id: "")
    raise

proc waitForElement*(d: WebDriver, by: By, timeoutMs: int): WebElement =
  ## Wait until an element matching `by` is present in the DOM; return it, or
  ## raise a timeout WebDriverError. (mainstream until.elementLocated)
  var waited = 0
  while true:
    let el = d.tryFind(by)
    if el.id.len > 0: return el
    if waited >= timeoutMs: break
    sleep(WaitPollMs)
    waited += WaitPollMs
  raiseTimeout("timed out after " & $timeoutMs & "ms waiting for " &
    by.strategy & "=" & by.value)

proc waitForVisible*(d: WebDriver, by: By, timeoutMs: int): WebElement =
  ## Wait until the element is present AND displayed; return it or raise on
  ## timeout. (mainstream until.elementIsVisible, folded with elementLocated)
  var waited = 0
  while true:
    let el = d.tryFind(by)
    if el.id.len > 0:
      try:
        if el.isDisplayed: return el
      except WebDriverError as e:
        if e.kind != ekStaleElementReference: raise
    if waited >= timeoutMs: break
    sleep(WaitPollMs)
    waited += WaitPollMs
  raiseTimeout("timed out after " & $timeoutMs & "ms waiting for visible " &
    by.strategy & "=" & by.value)

proc waitForClickable*(d: WebDriver, by: By, timeoutMs: int): WebElement =
  ## Wait until the element is present, displayed AND enabled (clickable); return
  ## it or raise on timeout.
  var waited = 0
  while true:
    let el = d.tryFind(by)
    if el.id.len > 0:
      try:
        if el.isDisplayed and el.isEnabled: return el
      except WebDriverError as e:
        if e.kind != ekStaleElementReference: raise
    if waited >= timeoutMs: break
    sleep(WaitPollMs)
    waited += WaitPollMs
  raiseTimeout("timed out after " & $timeoutMs & "ms waiting for clickable " &
    by.strategy & "=" & by.value)

proc waitUntilGone*(d: WebDriver, by: By, timeoutMs: int): bool {.discardable.} =
  ## Wait until NO element matches `by` (it's absent/removed); return true, or
  ## raise on timeout. (mainstream stalenessOf, by locator)
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = d.tryFind(by).id.len == 0)

proc waitForTitleIs*(d: WebDriver, want: string, timeoutMs: int): bool {.discardable.} =
  ## Wait until the page title equals `want`; return true or raise on timeout.
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = d.title == want)

proc waitForTitleContains*(d: WebDriver, substr: string, timeoutMs: int): bool {.discardable.} =
  ## Wait until the page title contains `substr`; return true or raise on timeout.
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = d.title.contains(substr))

proc waitForUrlIs*(d: WebDriver, want: string, timeoutMs: int): bool {.discardable.} =
  ## Wait until the current URL equals `want`; return true or raise on timeout.
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = d.currentUrl == want)

proc waitForUrlContains*(d: WebDriver, substr: string, timeoutMs: int): bool {.discardable.} =
  ## Wait until the current URL contains `substr`; return true or raise on timeout.
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = d.currentUrl.contains(substr))

proc waitForTextIs*(d: WebDriver, el: WebElement, want: string,
                    timeoutMs: int): bool {.discardable.} =
  ## Wait until `el`'s text equals `want`; return true or raise on timeout.
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = el.text == want)

proc waitForTextContains*(d: WebDriver, el: WebElement, substr: string,
                          timeoutMs: int): bool {.discardable.} =
  ## Wait until `el`'s text contains `substr`; return true or raise on timeout.
  d.waitUntil(timeoutMs, proc (d: WebDriver): bool = el.text.contains(substr))

# ---- Select (native <select> dropdown helper) -------------------------------
#
# Wraps a <select> WebElement and drives it by its <option> children — the same
# approach mainstream's Select uses. Mirrors the Python support/select surface.
#
#   Select(d.findElement(By.id("country"))).selectByVisibleText("Spain")

type Select* = object
  ## A <select> dropdown wrapper. Construct with `newSelect(element)`.
  element*: WebElement
  isMultiple*: bool

proc newSelect*(element: WebElement): Select =
  ## Wrap a <select> element. Raises WebDriverError if `element` is not a
  ## <select>. Reads the `multiple` attribute to know single vs multi-select.
  let tag = element.tagName.toLowerAscii
  if tag != "select":
    raise classify(11, "Select only works on <select> elements, not <" & tag & ">")
  result.element = element
  let multi = element.getAttribute("multiple")
  result.isMultiple = multi.kind == JString and multi.getStr.len > 0 and
    multi.getStr != "false"

proc options*(s: Select): seq[WebElement] =
  ## Every <option> child of the wrapped <select>, in document order.
  s.element.findElements(By.tagName("option"))

proc allSelectedOptions*(s: Select): seq[WebElement] =
  ## The currently-selected options (one for a single-select).
  for o in s.options:
    if o.isSelected: result.add o

proc firstSelectedOption*(s: Select): WebElement =
  ## The first selected option; raises WebDriverError if none is selected.
  for o in s.options:
    if o.isSelected: return o
  raise classify(17, "no option is selected")

type
  SelectBy* = enum
    ## How a `Select` matches an option: by its `value` attribute, its displayed
    ## text, or its position.
    sbValue, sbText, sbIndex

  OptionData* = object
    ## The plain data a Select match needs from one <option>: its `value`
    ## attribute and its displayed text. The pure matcher works over these, so
    ## the selection logic is testable without a browser.
    value*, text*: string

proc firstMatchIndex*(opts: openArray[OptionData], by: SelectBy, key: string): int =
  ## The index of the first option matching `key` under strategy `by`, or -1 if
  ## none (or `key` isn't a valid index for sbIndex). The pure core of the
  ## selectBy* procs.
  case by
  of sbValue:
    for i, o in opts:
      if o.value == key: return i
  of sbText:
    for i, o in opts:
      if o.text == key: return i
  of sbIndex:
    try:
      let idx = parseInt(key)
      if idx >= 0 and idx < opts.len: return idx
    except ValueError:
      discard
  -1

proc selectOption(s: Select, o: WebElement) =
  if not o.isSelected: o.click()

proc optionData(o: WebElement): OptionData =
  let v = o.getAttribute("value")
  OptionData(value: (if v.kind == JString: v.getStr else: ""), text: o.text)

proc selectMatching(s: Select, by: SelectBy, key: string) =
  let opts = s.options
  var data = newSeq[OptionData](opts.len)
  for i, o in opts:
    data[i] = o.optionData
  let hit = firstMatchIndex(data, by, key)
  if hit < 0:
    let what =
      case by
      of sbValue: "value " & key
      of sbText: "visible text " & key
      of sbIndex: "index " & key
    raise classify(17, "no option with " & what)
  s.selectOption(opts[hit])

proc selectByValue*(s: Select, value: string) =
  ## Select the option whose `value` attribute equals `value`. Raises if none.
  s.selectMatching(sbValue, value)

proc selectByVisibleText*(s: Select, text: string) =
  ## Select the option whose displayed text equals `text`. Raises if none.
  s.selectMatching(sbText, text)

proc selectByIndex*(s: Select, index: int) =
  ## Select the option at `index` (0-based). Raises if out of range.
  s.selectMatching(sbIndex, $index)

proc deselectAll*(s: Select) =
  ## Deselect every selected option (multi-select only). Raises on a
  ## single-select, mirroring mainstream's NotImplementedError.
  if not s.isMultiple:
    raise classify(0, "deselectAll only makes sense on a multi-select")
  for o in s.options:
    if o.isSelected: o.click()

# ---- Actions (fluent W3C input builder) -------------------------------------
#
# Queue gestures with chained calls, then `.perform()`. Each call appends to the
# pointer/key virtual-device sequences; perform() posts the whole thing in one
# `actions` command. Same wire shape the reference action_* helpers emit.
#
#   d.actions.moveToElement(menu).click(item).perform()
#   d.actions.keyDown(Keys.Control).sendKeys("a").keyUp(Keys.Control).perform()

type Actions* = ref object
  ## A fluent action-chain builder, obtained from `d.actions`.
  driver: WebDriver
  pointer: seq[JsonNode]
  keyActions: seq[JsonNode]

proc actions*(d: WebDriver): Actions =
  ## A fresh action-chain builder for this driver.
  Actions(driver: d, pointer: @[], keyActions: @[])

proc syncLengths(a: Actions) =
  ## W3C requires every device's action list to be the same length; pad the
  ## shorter with zero-duration pauses so ticks stay aligned across devices.
  let n = max(a.pointer.len, a.keyActions.len)
  while a.pointer.len < n:
    a.pointer.add %*{"type": "pause", "duration": 0}
  while a.keyActions.len < n:
    a.keyActions.add %*{"type": "pause", "duration": 0}

proc moveToElement*(a: Actions, el: WebElement): Actions {.discardable.} =
  ## Move the pointer to the centre of `el`.
  a.pointer.add %*{
    "type": "pointerMove", "duration": 100, "x": 0, "y": 0,
    "origin": {w3cElementKey: el.id}}
  a.syncLengths()
  a

proc click*(a: Actions, el: WebElement): Actions {.discardable.} =
  ## Move to `el` (if given) and left-click.
  a.moveToElement(el)
  a.pointer.add %*{"type": "pointerDown", "button": 0}
  a.pointer.add %*{"type": "pointerUp", "button": 0}
  a.syncLengths()
  a

proc click*(a: Actions): Actions {.discardable.} =
  ## Left-click at the current pointer position (no move).
  a.pointer.add %*{"type": "pointerDown", "button": 0}
  a.pointer.add %*{"type": "pointerUp", "button": 0}
  a.syncLengths()
  a

proc contextClick*(a: Actions, el: WebElement): Actions {.discardable.} =
  ## Move to `el` and right-click (contextmenu).
  a.moveToElement(el)
  a.pointer.add %*{"type": "pointerDown", "button": 2}
  a.pointer.add %*{"type": "pointerUp", "button": 2}
  a.syncLengths()
  a

proc doubleClick*(a: Actions, el: WebElement): Actions {.discardable.} =
  ## Move to `el` and double-click.
  a.moveToElement(el)
  for _ in 0 ..< 2:
    a.pointer.add %*{"type": "pointerDown", "button": 0}
    a.pointer.add %*{"type": "pointerUp", "button": 0}
  a.syncLengths()
  a

proc clickAndHold*(a: Actions, el: WebElement): Actions {.discardable.} =
  ## Move to `el` and press (and hold) the left button — the drag start.
  a.moveToElement(el)
  a.pointer.add %*{"type": "pointerDown", "button": 0}
  a.syncLengths()
  a

proc release*(a: Actions): Actions {.discardable.} =
  ## Release the left button at the current position — the drag end.
  a.pointer.add %*{"type": "pointerUp", "button": 0}
  a.syncLengths()
  a

proc dragAndDrop*(a: Actions, source, target: WebElement): Actions {.discardable.} =
  ## Press at `source`, move to `target`, release.
  a.clickAndHold(source)
  a.moveToElement(target)
  a.release()
  a

proc keyDown*(a: Actions, key: string): Actions {.discardable.} =
  ## Press (and hold) a key — a modifier (Keys.Control) or any character.
  a.keyActions.add %*{"type": "keyDown", "value": key}
  a.syncLengths()
  a

proc keyUp*(a: Actions, key: string): Actions {.discardable.} =
  ## Release a previously pressed key.
  a.keyActions.add %*{"type": "keyUp", "value": key}
  a.syncLengths()
  a

proc sendKeys*(a: Actions, text: string): Actions {.discardable.} =
  ## Type `text`, one keyDown/keyUp pair per character (Runes, so a PUA key
  ## constant counts as one).
  for r in text.runes:
    let ch = $r
    a.keyActions.add %*{"type": "keyDown", "value": ch}
    a.keyActions.add %*{"type": "keyUp", "value": ch}
  a.syncLengths()
  a

proc build*(a: Actions): JsonNode =
  ## The W3C actions array this chain would post (the value of the top-level
  ## "actions" key). Exposed for inspection/testing; perform() sends it.
  result = newJArray()
  if a.pointer.anyIt(it["type"].getStr != "pause"):
    var seqJson = newJArray()
    for act in a.pointer: seqJson.add act
    result.add %*{
      "type": "pointer", "id": "mouse",
      "parameters": {"pointerType": "mouse"},
      "actions": seqJson}
  if a.keyActions.anyIt(it["type"].getStr != "pause"):
    var seqJson = newJArray()
    for act in a.keyActions: seqJson.add act
    result.add %*{"type": "key", "id": "keyboard", "actions": seqJson}

proc perform*(a: Actions) =
  ## Post the queued gestures in one `actions` command.
  let built = a.build()
  if built.len > 0:
    a.driver.performActions(built)

# Re-export for tests that want strutils.contains etc.
export strutils, json
