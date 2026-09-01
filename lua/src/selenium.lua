-- selenium — the idiomatic Lua WebDriver API over the shared Aether core.
--
-- Carries NO protocol logic: the W3C command map, routing, By normalization,
-- error decode and HTTP round-trip all live in the Aether engine, reached
-- through the C extension `selenium_core_native` (which dlopen's
-- libselenium_core.so). This module marshals Lua tables <-> JSON and presents a
-- small idiomatic surface.
--
-- Values are decoded JSON: tables (string-keyed for objects, 1-indexed arrays),
-- strings, numbers, booleans, and a `null` sentinel. A session is an opaque
-- handle (light userdata). Commands return (value) on success or raise an error
-- table {code=..., message=...} via error().

local native = require("selenium_core_native")

local M = {}

-- By: a factory in the Selenium 4.x shape. Each constructor returns a locator
-- table {strategy=..., value=...}; find_element/find_elements take that one
-- table. The strategy-name CONSTANTS remain on By (By.ID etc.) so the legacy
-- two-arg form find_element(By.ID, "x") keeps working (additive).
--
-- CLASS_NAME is the W3C "class name" (not "className").
M.By = {
  ID = "id",
  NAME = "name",
  CSS = "css selector",
  CLASS_NAME = "class name",
  TAG_NAME = "tag name",
  LINK_TEXT = "link text",
  PARTIAL_LINK_TEXT = "partial link text",
  XPATH = "xpath",
}

-- A By locator carries (strategy, value); find_element unpacks it into the
-- existing engine call. Mirrors Java's By.id("x") static factory.
local function by_locator(strategy)
  return function(value) return { strategy = strategy, value = value } end
end
M.By.id = by_locator("id")
M.By.name = by_locator("name")
M.By.css_selector = by_locator("css selector")
M.By.class_name = by_locator("class name")
M.By.tag_name = by_locator("tag name")
M.By.link_text = by_locator("link text")
M.By.partial_link_text = by_locator("partial link text")
M.By.xpath = by_locator("xpath")

local W3C_ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"

-- A distinct value for JSON null (so it round-trips distinct from Lua nil).
M.null = setmetatable({}, { __tostring = function() return "null" end })

-- Tag a table as a JSON array (needed for an EMPTY array, which is otherwise
-- indistinguishable from an empty object). Non-empty numeric tables are
-- detected automatically.
M.array_mt = {}
function M.array(t) return setmetatable(t or {}, M.array_mt) end

-- ==== minimal JSON (tables <-> JSON), dependency-free ====

local json = {}

-- Pure-Lua UTF-8 encode of a codepoint (Lua 5.1/LuaJIT have no `utf8` library;
-- 5.3+ do). Used by the JSON decoder for \uXXXX escapes and by send_keys.
local function utf8_encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000),
                       0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
  else
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + (math.floor(cp / 0x1000) % 0x40),
                       0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
  end
end

local function esc(s)
  return (s:gsub('[%z\1-\31\\"]', function(c)
    if c == '"' then return '\\"'
    elseif c == '\\' then return '\\\\'
    elseif c == '\n' then return '\\n'
    elseif c == '\r' then return '\\r'
    elseif c == '\t' then return '\\t'
    else return string.format('\\u%04x', string.byte(c)) end
  end))
end

-- An empty table is ambiguous; treat it as an OBJECT ({}), because WebDriver
-- command params are always objects. An explicit empty array must be tagged
-- with M.array (see below).
local function is_array(t)
  if getmetatable(t) == M.array_mt then return true end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n > 0 and n == #t
end

function json.encode(v)
  local ty = type(v)
  if v == M.null then
    return "null"
  elseif ty == "nil" then
    return "null"
  elseif ty == "boolean" then
    return v and "true" or "false"
  elseif ty == "number" then
    if math.type and math.type(v) == "integer" then
      return string.format("%d", v)
    else
      return tostring(v)
    end
  elseif ty == "string" then
    return '"' .. esc(v) .. '"'
  elseif ty == "table" then
    if is_array(v) then
      local parts = {}
      for i = 1, #v do parts[i] = json.encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, val in pairs(v) do
        parts[#parts + 1] = '"' .. esc(tostring(k)) .. '":' .. json.encode(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

function json.decode(s)
  local i = 1
  local function skip_ws()
    local _, e = s:find("^[ \t\r\n]+", i)
    if e then i = e + 1 end
  end
  local parse_value
  local function parse_string()
    i = i + 1 -- opening quote
    local buf = {}
    while true do
      local c = s:sub(i, i)
      if c == '"' then i = i + 1; return table.concat(buf) end
      if c == '\\' then
        local n = s:sub(i + 1, i + 1)
        if n == "u" then
          local hex = s:sub(i + 2, i + 5)
          buf[#buf + 1] = utf8_encode(tonumber(hex, 16))
          i = i + 6
        else
          local map = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', n = '\n', r = '\r', t = '\t', b = '\b', f = '\f' }
          buf[#buf + 1] = map[n] or n
          i = i + 2
        end
      else
        buf[#buf + 1] = c
        i = i + 1
      end
    end
  end
  local function parse_object()
    i = i + 1 -- {
    local obj = {}
    skip_ws()
    if s:sub(i, i) == "}" then i = i + 1; return obj end
    while true do
      skip_ws()
      local key = parse_string()
      skip_ws()
      i = i + 1 -- :
      obj[key] = parse_value()
      skip_ws()
      local c = s:sub(i, i); i = i + 1
      if c == "}" then return obj end
      -- else c == ','
    end
  end
  local function parse_array()
    i = i + 1 -- [
    local arr = {}
    skip_ws()
    if s:sub(i, i) == "]" then i = i + 1; return arr end
    while true do
      arr[#arr + 1] = parse_value()
      skip_ws()
      local c = s:sub(i, i); i = i + 1
      if c == "]" then return arr end
    end
  end
  parse_value = function()
    skip_ws()
    local c = s:sub(i, i)
    if c == "{" then return parse_object()
    elseif c == "[" then return parse_array()
    elseif c == '"' then return parse_string()
    elseif c == "t" then i = i + 4; return true
    elseif c == "f" then i = i + 5; return false
    elseif c == "n" then i = i + 4; return M.null
    else
      local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
      i = i + #num
      return tonumber(num)
    end
  end
  return parse_value()
end

M.json = json

-- ==== error classification ====

local CODE_NAME = {
  [3] = "element click intercepted",
  [4] = "element not interactable",
  [11] = "invalid selector",
  [13] = "javascript error",
  [17] = "no such element",
  [21] = "script timeout",
  [23] = "stale element reference",
  [24] = "timeout",
  [28] = "unknown command",
}

local function raise(code, message)
  error({ code = code, message = message, kind = CODE_NAME[code] or "webdriver" }, 0)
end

-- ==== WebElement ====
-- A remote element handle wrapping the driver + its W3C element id. Methods
-- issue element-scoped commands, so a user writes `el:text()` / `el:click()`
-- rather than threading the id back through driver methods. The driver-level
-- methods (driver:element_text(id) etc.) remain for backward compatibility.

local WebElement = {}
WebElement.__index = WebElement

local function wrap_element(driver, id)
  return setmetatable({ driver = driver, id = id }, WebElement)
end

function WebElement:click() self.driver:click(self.id) end
function WebElement:clear() self.driver:execute("clearElement", { id = self.id }) end
function WebElement:send_keys(text) self.driver:send_keys(self.id, text) end
function WebElement:text() return self.driver:element_text(self.id) end
function WebElement:tag_name() return self.driver:tag_name(self.id) end
function WebElement:rect() return self.driver:element_rect(self.id) end
function WebElement:property(name) return self.driver:element_property(self.id, name) end
function WebElement:enabled() return self.driver:execute("isElementEnabled", { id = self.id }) == true end
function WebElement:selected() return self.driver:execute("isElementSelected", { id = self.id }) == true end
-- the isDisplayed atom (the visibility algorithm, not a naive style check).
function WebElement:is_displayed() return self.driver:is_displayed(self.id) end
-- the classic getAttribute(name): property-or-attribute, via the shared atom.
function WebElement:get_attribute(name) return self.driver:get_attribute(self.id, name) end
-- the raw W3C DOM attribute (no property fallback).
function WebElement:dom_attribute(name) return self.driver:dom_attribute(self.id, name) end

M.WebElement = WebElement

-- ==== WebDriver ====

local WebDriver = {}
WebDriver.__index = WebDriver

local function new(command_executor, caps, tls)
  local handle = native.open(command_executor)
  if not handle then raise(-1, "failed to open session handle") end
  local self = setmetatable({ handle = handle }, WebDriver)
  -- TLS trust config must land on the handle BEFORE newSession (the first
  -- request). ca_path pins a private-CA bundle; insecure skips verification
  -- entirely (self-signed dev/staging Grid — trust the host out-of-band).
  if tls then
    if tls.ca_path and #tls.ca_path > 0 then native.set_ca(handle, tls.ca_path) end
    if tls.insecure then native.set_insecure(handle, 1) end
  end
  -- Request a BiDi channel so :bidi() is available on demand; the WebSocket
  -- itself opens lazily (a classic script never opens it).
  local bidi_caps = { webSocketUrl = true }
  for k, v in pairs(caps) do bidi_caps[k] = v end
  local result = self:execute("newSession", { capabilities = { alwaysMatch = bidi_caps } })
  -- value.capabilities.webSocketUrl — the BiDi endpoint for this session.
  self._ws_url = ""
  if type(result) == "table" and type(result.capabilities) == "table" then
    local url = result.capabilities.webSocketUrl
    if type(url) == "string" then self._ws_url = url end
  end
  self._bidi = nil
  return self
end

-- options: a raw capabilities table merged under browserName=chrome.
-- tls (optional): { ca_path=..., insecure=... } — applied before newSession.
function M.chrome(command_executor, options, tls)
  local caps = { browserName = "chrome" }
  if options then for k, v in pairs(options) do caps[k] = v end end
  return new(command_executor, caps, tls)
end

function M.headless_chrome(command_executor, tls)
  return M.chrome(command_executor, {
    ["goog:chromeOptions"] = {
      args = { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" },
    },
  }, tls)
end

-- ==== driver orchestration (spawn/adopt a driver process in-binding) ====
-- The engine resolves, download-or-caches, and launches a browser driver itself,
-- so a caller needs neither a driver on PATH nor a running Grid.

-- Resolve the local driver binary path for `browser` without launching it.
-- `hint` pins a version/path; "" auto-detects. Returns "" if none resolvable.
function M.resolve_driver(browser, hint)
  return native.resolve_driver(browser or "chrome", hint or "")
end

-- A driver process launched by the engine. :url()/:pid()/:stop() (idempotent).
local DriverProcess = {}
DriverProcess.__index = DriverProcess

local function wrap_driver(handle)
  if not handle then return nil end
  return setmetatable({ handle = handle }, DriverProcess)
end

function DriverProcess:url()
  if not self.handle then return "" end
  return native.driver_url(self.handle)
end

function DriverProcess:pid()
  if not self.handle then return 0 end
  return native.driver_pid(self.handle)
end

function DriverProcess:stop()
  if self.handle then
    native.stop_driver(self.handle)
    self.handle = nil
  end
end

M.DriverProcess = DriverProcess

-- Launch a driver at an explicit binary path. Returns a DriverProcess or nil.
function M.launch_driver(driver_path, timeout_ms)
  return wrap_driver(native.launch_driver(driver_path, timeout_ms or 15000))
end

-- Resolve (detect/download/cache) AND launch a driver in one step.
function M.ensure_driver(browser, hint, timeout_ms)
  return wrap_driver(native.ensure_driver(browser or "chrome", hint or "", timeout_ms or 15000))
end

-- A Chrome session that spawns its OWN chromedriver via the engine — no driver
-- on PATH, no Grid. The driver is stopped on :quit(). opts:
--   { options=<caps>, hint="", timeout_ms=15000, ca_path=..., insecure=... }
function M.local_chrome(opts)
  opts = opts or {}
  local proc = M.ensure_driver("chrome", opts.hint or "", opts.timeout_ms or 15000)
  if not proc then raise(-1, "could not resolve/launch chromedriver") end
  local ok, driver = pcall(function()
    return M.chrome(proc:url(), opts.options,
      { ca_path = opts.ca_path, insecure = opts.insecure })
  end)
  if not ok then
    proc:stop()
    error(driver, 0)
  end
  driver._owned_driver = proc
  return driver
end

-- The FFI seam: one command with a params table. Returns the decoded value, or
-- raises {code, message}.
function WebDriver:execute(command, params)
  local rc = native.execute(self.handle, command, json.encode(params or {}))
  if rc ~= 0 then
    local code = native.last_error_code(self.handle)
    local message = native.last_error(self.handle)
    if rc == -1 and code == 0 then
      raise(-1, message ~= "" and message or "transport failure")
    end
    raise(code, message)
  end
  local raw = native.last_value(self.handle)
  if raw == "" then return M.null end
  return json.decode(raw)
end

-- navigation
function WebDriver:get(url) self:execute("get", { url = url }) end
function WebDriver:title() return self:execute("getTitle", {}) end
function WebDriver:current_url() return self:execute("getCurrentUrl", {}) end
function WebDriver:back() self:execute("goBack", {}) end
function WebDriver:forward() self:execute("goForward", {}) end
function WebDriver:refresh() self:execute("refresh", {}) end

-- elements (return an element id string)
local function decode_by(by, value)
  return json.decode(native.by_locator(by, value))
end

-- Normalize find args to (strategy, value). The Selenium 4.x shape is a single
-- By locator table {strategy, value} (from By.id("x") etc.); the legacy
-- (By.ID, "x") two-string form is still accepted (additive).
local function locator_args(by, value)
  if type(by) == "table" and by.strategy ~= nil then
    return by.strategy, by.value
  end
  return by, value
end

function WebDriver:find_element(by, value)
  local strategy, v = locator_args(by, value)
  local r = self:execute("findElement", decode_by(strategy, v))
  return wrap_element(self, r[W3C_ELEMENT_KEY])
end

function WebDriver:find_elements(by, value)
  local strategy, v = locator_args(by, value)
  local r = self:execute("findElements", decode_by(strategy, v))
  local out = {}
  for i = 1, #r do out[i] = wrap_element(self, r[i][W3C_ELEMENT_KEY]) end
  return out
end

-- Element-scoped driver methods accept either a raw W3C id string or a
-- WebElement (from find_element). `_eid` normalizes to the id string, so both
-- the object API (el:click()) and the legacy id API (driver:click(id)) work.
local function _eid(element)
  if type(element) == "table" and element.id ~= nil then return element.id end
  return element
end

function WebDriver:click(element_id) self:execute("clickElement", { id = _eid(element_id) }) end
function WebDriver:send_keys(element_id, text)
  element_id = _eid(element_id)
  -- Split the UTF-8 `text` into one entry per character (W3C wants a `value`
  -- array of single-code-point strings). Pure-5.1: walk UTF-8 lead bytes (no
  -- `utf8` library on LuaJIT/5.1). Continuation bytes are 0x80..0xBF.
  local value = {}
  local i, n = 1, #text
  while i <= n do
    local b = text:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3 elseif b >= 0xC0 then len = 2 end
    value[#value + 1] = text:sub(i, i + len - 1)
    i = i + len
  end
  self:execute("sendKeysToElement", { id = element_id, text = text, value = value })
end
function WebDriver:element_text(element_id) return self:execute("getElementText", { id = _eid(element_id) }) end
function WebDriver:tag_name(element_id) return self:execute("getElementTagName", { id = _eid(element_id) }) end
function WebDriver:element_rect(element_id) return self:execute("getElementRect", { id = _eid(element_id) }) end
function WebDriver:element_property(element_id, name)
  return self:execute("getElementProperty", { id = _eid(element_id), name = name })
end

-- atom-backed commands (a shared JS atom run in-page by the engine) ----------
-- Drain last_value after an atom native call, raising a typed error on rc ~= 0.
function WebDriver:_atom_result(rc)
  if rc ~= 0 then
    local code = native.last_error_code(self.handle)
    local message = native.last_error(self.handle)
    if rc == -1 and code == 0 then raise(-1, message ~= "" and message or "transport failure") end
    raise(code, message)
  end
  local raw = native.last_value(self.handle)
  if raw == "" then return M.null end
  return json.decode(raw)
end

-- is the element displayed? (the isDisplayed atom — the visibility algorithm)
function WebDriver:is_displayed(element_id)
  return self:_atom_result(native.is_displayed(self.handle, _eid(element_id))) == true
end

-- the classic getAttribute(name): property-or-attribute (via the atom).
-- dom_attribute(name) keeps the raw W3C getDomAttribute.
function WebDriver:get_attribute(element_id, name)
  local v = self:_atom_result(native.get_attribute(self.handle, _eid(element_id), name))
  if v == M.null then return nil end
  return v
end
function WebDriver:dom_attribute(element_id, name)
  return self:execute("getDomAttribute", { id = _eid(element_id), name = name })
end

-- relative locators: element ids matching base_css filtered by spatial relation
-- to anchors, nearest first. filters is a list of tables {kind=..., sel=...}.
function WebDriver:find_relative(base_css, filters)
  local r = self:_atom_result(native.find_relative(self.handle, base_css, json.encode(filters or M.array({}))))
  local out = {}
  if type(r) == "table" then
    for i = 1, #r do out[i] = r[i][W3C_ELEMENT_KEY] end
  end
  return out
end

-- script
function WebDriver:execute_script(script, args)
  return self:execute("executeScript", { script = script, args = args or M.array({}) })
end
function WebDriver:execute_async_script(script, args)
  return self:execute("executeAsyncScript", { script = script, args = args or M.array({}) })
end

-- windows
function WebDriver:window_handles() return self:execute("getWindowHandles", {}) end
function WebDriver:current_window_handle() return self:execute("getCurrentWindowHandle", {}) end
function WebDriver:switch_to_window(handle) self:execute("switchToWindow", { handle = handle }) end
function WebDriver:maximize_window() return self:execute("maximizeWindow", {}) end
function WebDriver:minimize_window() return self:execute("minimizeWindow", {}) end
function WebDriver:fullscreen_window() return self:execute("fullscreenWindow", {}) end
function WebDriver:set_window_rect(rect) return self:execute("setWindowRect", rect) end
function WebDriver:get_window_rect() return self:execute("getWindowRect", {}) end

-- alerts
function WebDriver:accept_alert() self:execute("acceptAlert", {}) end
function WebDriver:dismiss_alert() self:execute("dismissAlert", {}) end
function WebDriver:alert_text() return self:execute("getAlertText", {}) end
function WebDriver:send_alert_text(text) self:execute("setAlertValue", { text = text }) end

-- cookies
function WebDriver:add_cookie(cookie) self:execute("addCookie", { cookie = cookie }) end
function WebDriver:cookies() return self:execute("getCookies", {}) end
function WebDriver:cookie(name) return self:execute("getCookie", { name = name }) end
function WebDriver:delete_cookie(name) self:execute("deleteCookie", { name = name }) end
function WebDriver:delete_all_cookies() self:execute("deleteAllCookies", {}) end

-- actions
function WebDriver:perform_actions(actions) self:execute("actions", { actions = actions }) end
function WebDriver:clear_actions() self:execute("clearActions", {}) end

-- timeouts / screenshots
function WebDriver:set_timeouts(timeouts) self:execute("setTimeout", timeouts) end
function WebDriver:set_page_load_timeout(ms) self:execute("setTimeout", { pageLoad = ms }) end
function WebDriver:set_script_timeout(ms) self:execute("setTimeout", { script = ms }) end
function WebDriver:implicitly_wait(ms) self:execute("setTimeout", { implicit = ms }) end
function WebDriver:screenshot_base64() return self:execute("screenshot", {}) end

-- ==== WebDriver-BiDi ====

-- The common WebDriver-BiDi event names (W3C spec). Pass to
-- driver:bidi():subscribe(...) and match in :next_event(...).
M.BidiEvent = {
  LOG_ENTRY_ADDED     = "log.entryAdded",
  CONTEXT_CREATED     = "browsingContext.contextCreated",
  CONTEXT_DESTROYED   = "browsingContext.contextDestroyed",
  NAVIGATION_STARTED  = "browsingContext.navigationStarted",
  DOM_CONTENT_LOADED  = "browsingContext.domContentLoaded",
  LOAD                = "browsingContext.load",
  DOWNLOAD_WILL_BEGIN = "browsingContext.downloadWillBegin",
  BEFORE_REQUEST_SENT = "network.beforeRequestSent",
  AUTH_REQUIRED = "network.authRequired",
  RESPONSE_STARTED    = "network.responseStarted",
  RESPONSE_COMPLETED  = "network.responseCompleted",
  FETCH_ERROR         = "network.fetchError",
  REALM_CREATED       = "script.realmCreated",
  REALM_DESTROYED     = "script.realmDestroyed",
  MESSAGE             = "script.message",
}

-- The event-driven BiDi channel for a session (over the demux C ABI).
-- Commands and events multiplex over one WebSocket via the engine's shape-C
-- demux (single reader -> id-keyed replies + bounded event queue), so replies
-- stay correlated while events stream. Command ids are supplied automatically.
local BiDi = {}
BiDi.__index = BiDi

local function new_bidi(handle)
  return setmetatable({ _handle = handle, _next_id = 1 }, BiDi)
end

function BiDi:_id()
  local i = self._next_id
  self._next_id = i + 1
  return i
end

-- session.subscribe to one or more event names; wait for the ack. Returns the
-- ack payload table. Matching events then arrive on the queue (drain via
-- :next_event).
function BiDi:subscribe(...)
  local csv = table.concat({ ... }, ",")
  local raw = native.bidi_subscribe(self._handle, self:_id(), csv, 10000)
  if raw == "" then return {} end
  return json.decode(raw)
end

function BiDi:unsubscribe(...)
  local csv = table.concat({ ... }, ",")
  local raw = native.bidi_unsubscribe(self._handle, self:_id(), csv, 10000)
  if raw == "" then return {} end
  return json.decode(raw)
end

-- Block until an event whose `method` matches arrives, or timeout. Returns the
-- event table, or nil on timeout/close. (Subscribe first.)
function BiDi:next_event(method, timeout_ms)
  local raw = native.bidi_wait_event(self._handle, method, timeout_ms or 5000)
  if raw == "" then return nil end
  return json.decode(raw)
end

-- Issue any BiDi command and return its reply payload table. Reaches BiDi
-- methods with no dedicated wrapper (script.evaluate, network.*, ...).
function BiDi:command(method, params, timeout_ms)
  timeout_ms = timeout_ms or 10000
  local cid = self:_id()
  if native.bidi_send(self._handle, cid, method, json.encode(params or {})) ~= 0 then
    raise(-1, "BiDi send failed: " .. method)
  end
  local waited, step = 0, 50
  while waited < timeout_ms do
    local reply = native.bidi_poll_reply(self._handle, cid)
    if reply ~= "" then return json.decode(reply) end
    if native.bidi_pump(self._handle, step) < 0 then break end
    waited = waited + step
  end
  raise(24, "BiDi command timed out: " .. method)
end

-- typed convenience commands ----------------------------------------------
-- browsingContext.getTree — the browsing contexts (each with a "context" id).
function BiDi:get_tree(timeout_ms)
  local raw = native.bidi_get_tree(self._handle, self:_id(), timeout_ms or 10000)
  if raw == "" then return {} end
  return json.decode(raw)
end

-- the top-level browsing context id (anchor for evaluate/navigate), or nil.
function BiDi:top_context(timeout_ms)
  local tree = self:get_tree(timeout_ms)
  local ctxs = tree.result and tree.result.contexts
  if ctxs and ctxs[1] then return ctxs[1].context end
  return nil
end

-- script.evaluate an expression in a context's realm (awaits promises). Returns
-- the reply; reply.result.result is the BiDi-typed value {type=..., value=...}.
function BiDi:evaluate(expr, context, timeout_ms)
  local ctx = context or self:top_context(timeout_ms)
  if not ctx then raise(0, "no browsing context for script.evaluate") end
  local raw = native.bidi_script_evaluate(self._handle, self:_id(), expr, ctx, timeout_ms or 30000)
  if raw == "" then return {} end
  return json.decode(raw)
end

-- script.evaluate returning just the unwrapped .value.
function BiDi:evaluate_value(expr, context, timeout_ms)
  local reply = self:evaluate(expr, context, timeout_ms)
  local r = reply.result and reply.result.result
  if r then return r.value end
  return nil
end

-- browsingContext.navigate a context to url (wait: complete).
function BiDi:navigate(url, context, timeout_ms)
  local ctx = context or self:top_context(timeout_ms)
  if not ctx then raise(0, "no browsing context for navigate") end
  local raw = native.bidi_navigate(self._handle, self:_id(), ctx, url, timeout_ms or 30000)
  if raw == "" then return {} end
  return json.decode(raw)
end

-- network interception (observe / release / block requests) -------------------
-- network.addIntercept for a URL pattern (full parseable URL as a "string"
-- pattern; "" intercepts all) at the given phases. Returns the intercept id or nil.
function BiDi:add_intercept(phases, url_pattern, timeout_ms)
  local raw = native.bidi_network_add_intercept(self._handle, self:_id(),
    phases or "beforeRequestSent", url_pattern or "", timeout_ms or 10000)
  if raw == "" then return nil end
  local reply = json.decode(raw)
  return reply.result and reply.result.intercept or nil
end

function BiDi:remove_intercept(intercept_id, timeout_ms)
  local raw = native.bidi_network_remove_intercept(self._handle, self:_id(), intercept_id, timeout_ms or 10000)
  return raw == "" and {} or json.decode(raw)
end

-- Let a paused request proceed. request_id comes from a network event's
-- params.request.request.
function BiDi:continue_request(request_id, timeout_ms)
  local raw = native.bidi_network_continue_request(self._handle, self:_id(), request_id, timeout_ms or 10000)
  return raw == "" and {} or json.decode(raw)
end

function BiDi:fail_request(request_id, timeout_ms)
  local raw = native.bidi_network_fail_request(self._handle, self:_id(), request_id, timeout_ms or 10000)
  return raw == "" and {} or json.decode(raw)
end

-- Fulfill a paused request with a MOCK response (never hits the network).
function BiDi:provide_response(request_id, status, content_type, body, timeout_ms)
  local raw = native.bidi_network_provide_response(self._handle, self:_id(), request_id,
    status or 200, content_type or "", body or "", timeout_ms or 10000)
  return raw == "" and {} or json.decode(raw)
end

-- Answer a paused authRequired with credentials (action provideCredentials).
-- Needs a WWW-Authenticate challenge to exercise.
function BiDi:continue_with_auth(request_id, username, password, timeout_ms)
  local raw = native.bidi_network_continue_with_auth(self._handle, self:_id(), request_id,
    username or "", password or "", timeout_ms or 10000)
  return raw == "" and {} or json.decode(raw)
end

-- Disable ("bypass") or restore ("default") the session HTTP cache.
function BiDi:set_cache_behavior(behavior, timeout_ms)
  local raw = native.bidi_network_set_cache_behavior(self._handle, self:_id(),
    behavior or "bypass", timeout_ms or 10000)
  return raw == "" and {} or json.decode(raw)
end

-- The network.request id out of a network event: params.request.request.
function BiDi.event_request_id(event)
  local p = event.params
  local r = p and p.request
  return r and r.request or nil
end

-- How many events the bounded queue dropped since the last call (then resets).
function BiDi:lost_events() return native.bidi_lost_events(self._handle) end

function BiDi:close()
  if self._handle then
    native.bidi_close(self._handle)
    self._handle = nil
  end
end

-- The event-driven BiDi surface for this session, opened lazily over the
-- negotiated webSocketUrl. Raises if the remote end granted no BiDi URL.
--
--   driver:bidi():subscribe(M.BidiEvent.LOG_ENTRY_ADDED)
--   driver:get(url)
--   local ev = driver:bidi():next_event(M.BidiEvent.LOG_ENTRY_ADDED, 5000)
function WebDriver:bidi()
  if self._bidi == nil then
    if self._ws_url == "" then
      raise(0, "BiDi not available: the session negotiated no webSocketUrl")
    end
    local handle = native.bidi_open(self._ws_url)
    if not handle then raise(-1, "BiDi channel failed to open") end
    self._bidi = new_bidi(handle)
  end
  return self._bidi
end

-- True if this session negotiated a webSocketUrl (BiDi usable).
function WebDriver:bidi_available() return self._ws_url ~= "" end

-- lifecycle
function WebDriver:session_id() return native.session_id(self.handle) end
function WebDriver:quit()
  if self._bidi ~= nil then
    self._bidi:close()
    self._bidi = nil
  end
  local ok, err = pcall(function() self:execute("quit", {}) end)
  native.close(self.handle)
  self.handle = nil
  -- Stop a driver this session spawned (local_chrome), if any.
  if self._owned_driver ~= nil then
    self._owned_driver:stop()
    self._owned_driver = nil
  end
  if not ok then error(err, 0) end
end

-- pure engine helpers
function M.route(command) return native.route(command) end
function M.error_code(w3c_error) return native.error_code(w3c_error) end
function M.locator(by, value) return native.by_locator(by, value) end
function M.configure_native_lib(path) native.configure(path) end

M.BiDi = BiDi

return M
