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

-- Keys: mainstream Selenium's special-key constants — the W3C Unicode
-- private-use code points (U+E000..U+E03D, W3C §17.4.2). Append one to a string
-- or use Keys.chord(...) to build a modifier chord, then pass to send_keys. The
-- values are the exact code points the protocol defines, so the engine forwards
-- them unchanged. Mirrors the Rust reference's Keys and Python's common.keys.
--
-- utf8_char renders a code point to its UTF-8 glyph; it is bound below to the
-- JSON codec's utf8_encode once that is defined (forward-declared here).
local utf8_char

M.Keys = {}
do
  local K = M.Keys
  K.NULL = 0xE000
  K.CANCEL = 0xE001
  K.HELP = 0xE002
  K.BACKSPACE = 0xE003
  K.TAB = 0xE004
  K.CLEAR = 0xE005
  K.RETURN = 0xE006
  K.ENTER = 0xE007
  K.SHIFT = 0xE008
  K.CONTROL = 0xE009
  K.ALT = 0xE00A
  K.PAUSE = 0xE00B
  K.ESCAPE = 0xE00C
  K.SPACE = 0xE00D
  K.PAGE_UP = 0xE00E
  K.PAGE_DOWN = 0xE00F
  K.END = 0xE010
  K.HOME = 0xE011
  K.LEFT = 0xE012
  K.UP = 0xE013
  K.RIGHT = 0xE014
  K.DOWN = 0xE015
  K.INSERT = 0xE016
  K.DELETE = 0xE017
  K.SEMICOLON = 0xE018
  K.EQUALS = 0xE019
  K.NUMPAD0 = 0xE01A
  K.NUMPAD1 = 0xE01B
  K.NUMPAD2 = 0xE01C
  K.NUMPAD3 = 0xE01D
  K.NUMPAD4 = 0xE01E
  K.NUMPAD5 = 0xE01F
  K.NUMPAD6 = 0xE020
  K.NUMPAD7 = 0xE021
  K.NUMPAD8 = 0xE022
  K.NUMPAD9 = 0xE023
  K.MULTIPLY = 0xE024
  K.ADD = 0xE025
  K.SEPARATOR = 0xE026
  K.SUBTRACT = 0xE027
  K.DECIMAL = 0xE028
  K.DIVIDE = 0xE029
  K.F1 = 0xE031
  K.F2 = 0xE032
  K.F3 = 0xE033
  K.F4 = 0xE034
  K.F5 = 0xE035
  K.F6 = 0xE036
  K.F7 = 0xE037
  K.F8 = 0xE038
  K.F9 = 0xE039
  K.F10 = 0xE03A
  K.F11 = 0xE03B
  K.F12 = 0xE03C
  K.META = 0xE03D
  K.COMMAND = 0xE03D
  -- Aliases matching mainstream (BACK_SPACE, LEFT_SHIFT, ARROW_* etc.).
  K.BACK_SPACE = K.BACKSPACE
  K.LEFT_SHIFT = K.SHIFT
  K.LEFT_CONTROL = K.CONTROL
  K.LEFT_ALT = K.ALT
  K.ARROW_LEFT = K.LEFT
  K.ARROW_UP = K.UP
  K.ARROW_RIGHT = K.RIGHT
  K.ARROW_DOWN = K.DOWN
end

-- The UTF-8 string for a key code point (Keys.char(Keys.ENTER)), for embedding
-- in send_keys text. A key constant is a number; this renders it to its glyph.
function M.Keys.char(cp) return utf8_char(cp) end

-- A modifier chord: hold `modifier` while `text` is typed, then release with the
-- terminating NULL the protocol uses to drop held modifiers — e.g.
-- Keys.chord(Keys.CONTROL, "a") for select-all. Returns a string for send_keys.
function M.Keys.chord(modifier, text)
  return utf8_char(modifier) .. text .. utf8_char(M.Keys.NULL)
end

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

-- Bind the forward-declared utf8_char (used by M.Keys.char/chord above) to the
-- codec's encoder now that it exists.
utf8_char = utf8_encode

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

-- Mainstream/reference-named aliases for element state (is_enabled/is_selected).
function WebElement:is_enabled() return self:enabled() end
function WebElement:is_selected() return self:selected() end
-- getElementProperty(name) — reference name get_property (alias of :property).
function WebElement:get_property(name) return self:property(name) end
-- getDomAttribute alias matching the reference's get_dom_attribute name.
function WebElement:get_dom_attribute(name) return self:dom_attribute(name) end

-- getElementValueOfCssProperty: the computed value of CSS property `prop`
-- (e.g. "display", "color"). value_of_css_property is the classic-Selenium name.
function WebElement:css_value(prop)
  return self.driver:execute("getElementValueOfCssProperty", { id = self.id, name = prop })
end
function WebElement:value_of_css_property(prop) return self:css_value(prop) end

-- A PNG screenshot of just this element (takeElementScreenshot), base64. The
-- element-scoped counterpart to driver:screenshot_base64().
function WebElement:screenshot_base64()
  return self.driver:execute("takeElementScreenshot", { id = self.id })
end

-- NOTE: :submit(), :find_element() and :find_elements() are attached to
-- WebElement further down, after the driver-level locator helpers they reuse are
-- defined (Lua resolves those as upvalues, which must exist by definition time).

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

-- Reference-named alias of M.chrome: options merged under browserName=chrome,
-- with explicit TLS trust config ({ ca_path=..., insecure=... }) applied before
-- newSession. Matches the Rust binding's chrome_tls.
function M.chrome_tls(command_executor, options, tls)
  return M.chrome(command_executor, options, tls)
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

-- Element-scoped find (findChildElement / findChildElements): search only within
-- this element's subtree. Defined here so decode_by/locator_args/wrap_element are
-- in scope. Used by Select to enumerate <option> children.
function WebElement:find_element(by, value)
  local strategy, v = locator_args(by, value)
  local params = decode_by(strategy, v)
  params.id = self.id
  local r = self.driver:execute("findChildElement", params)
  return wrap_element(self.driver, r[W3C_ELEMENT_KEY])
end
function WebElement:find_elements(by, value)
  local strategy, v = locator_args(by, value)
  local params = decode_by(strategy, v)
  params.id = self.id
  local r = self.driver:execute("findChildElements", params)
  local out = {}
  for i = 1, #r do out[i] = wrap_element(self.driver, r[i][W3C_ELEMENT_KEY]) end
  return out
end

-- Submit the form this element belongs to. W3C removed the dedicated submit
-- endpoint, so — like the reference binding and modern Selenium — walk up to the
-- enclosing <form> and requestSubmit() (falling back to submit()) via a script.
-- Raises (no such element) if the element is not inside a form.
local SUBMIT_SCRIPT =
  "var e=arguments[0];var f=e.form||e.closest('form');" ..
  "if(!f){throw new Error('Element is not within a form');}" ..
  "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}"
function WebElement:submit()
  self.driver:execute_script(SUBMIT_SCRIPT, M.array({ { [W3C_ELEMENT_KEY] = self.id } }))
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

-- The NUMBER of elements a relative-locator query matches, without materializing
-- handles — the count-only counterpart to find_relative (matches the reference).
function WebDriver:find_relative_count(base_css, filters)
  local r = self:_atom_result(native.find_relative(self.handle, base_css, json.encode(filters or M.array({}))))
  if type(r) == "table" then return #r end
  return 0
end

-- getPageSource — the current DOM serialized to an HTML string.
function WebDriver:page_source() return self:execute("getPageSource", {}) end

-- getActiveElement — the focused element (what would receive keyboard input).
function WebDriver:active_element()
  local r = self:execute("getActiveElement", {})
  return wrap_element(self, r[W3C_ELEMENT_KEY])
end

-- True if at least one element matching the locator is present RIGHT NOW (an
-- immediate presence check, no implicit wait). A clean "no such element" yields
-- false; a transport failure still raises. Pairs with wait_for_element.
function WebDriver:exists(by, value)
  local ok, err = pcall(function() return self:find_element(by, value) end)
  if ok then return true end
  if type(err) == "table" and err.code == 17 then return false end
  error(err, 0)
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

-- Open a new top-level browsing context (newWindow). type_hint is "tab" or
-- "window" (a hint the browser may honor or ignore). Returns the new window's
-- handle — pass to switch_to_window to focus it. "" if the remote sent none.
function WebDriver:new_window(type_hint)
  local r = self:execute("newWindow", { type = type_hint or "tab" })
  if type(r) == "table" and type(r.handle) == "string" then return r.handle end
  return ""
end

-- Close the current window/tab (close). Returns the remaining window handles;
-- when it empties the session is gone. Does NOT end the session (use :quit()).
function WebDriver:close_window() return self:execute("close", {}) end

-- frames: switch focus into/out of a frame. switch_to_frame accepts a 0-based
-- index (number), a WebElement/id (the <iframe> element), or nil (top-level).
function WebDriver:switch_to_frame(frame)
  local id
  if frame == nil then
    id = M.null
  elseif type(frame) == "number" then
    id = frame
  elseif type(frame) == "table" and frame.id ~= nil then
    id = { [W3C_ELEMENT_KEY] = frame.id }
  elseif type(frame) == "string" then
    id = { [W3C_ELEMENT_KEY] = frame }
  else
    id = frame
  end
  self:execute("switchToFrame", { id = id })
end

-- Switch to the parent of the current frame (one level out).
function WebDriver:switch_to_parent_frame() self:execute("switchToFrameParent", {}) end

-- Return focus to the top-level browsing context (switchToFrame with null id).
function WebDriver:switch_to_default_content() self:switch_to_frame(nil) end

-- alerts
function WebDriver:accept_alert() self:execute("acceptAlert", {}) end
function WebDriver:dismiss_alert() self:execute("dismissAlert", {}) end
function WebDriver:alert_text() return self:execute("getAlertText", {}) end
function WebDriver:send_alert_text(text) self:execute("setAlertValue", { text = text }) end

-- True if a user-prompt/alert dialog is present (probing via getAlertText). A
-- clean "no such alert" (code 15) yields false; a transport failure still raises.
function WebDriver:alert_present()
  local ok, err = pcall(function() return self:execute("getAlertText", {}) end)
  if ok then return true end
  if type(err) == "table" and err.code == 15 then return false end
  error(err, 0)
end

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

-- Print the current page to PDF (printPage), returning the PDF as base64.
-- options is the W3C print-options object (page size, margins, orientation,
-- scale, pageRanges, ...); pass nil for defaults.
function WebDriver:print_pdf(options) return self:execute("printPage", options or {}) end

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

-- ==== Actions (fluent action builder) ====
-- Queue pointer/key gestures, then :perform(). Each call appends to a W3C
-- actions sequence (a pointer virtual device + a key virtual device); :perform()
-- posts the whole sequence in one `actions` command. Same wire shape as the Rust
-- reference and Python's ActionChains. Obtain one from driver:actions().

local Actions = {}
Actions.__index = Actions

local function _pause(duration_ms)
  return { type = "pause", duration = duration_ms }
end
local function _move_to(id)
  return { type = "pointerMove", duration = 100, x = 0, y = 0,
           origin = { [W3C_ELEMENT_KEY] = id } }
end
local function _button_down(button) return { type = "pointerDown", button = button } end
local function _button_up(button) return { type = "pointerUp", button = button } end
local function _key_event(kind, cp)
  return { type = kind, value = utf8_char(cp) }
end
local function _is_pause(a) return a.type == "pause" end

-- W3C requires each device's action list to be the same length; pad the shorter
-- device with zero-duration pauses so gestures on one device don't desync the
-- other's ticks. Mirrors the reference's sync_lengths.
local function _sync_lengths(self)
  local n = math.max(#self._pointer, #self._key)
  while #self._pointer < n do self._pointer[#self._pointer + 1] = _pause(0) end
  while #self._key < n do self._key[#self._key + 1] = _pause(0) end
end

local function new_actions(driver)
  return setmetatable({ driver = driver, _pointer = {}, _key = {} }, Actions)
end

-- Normalize an element/id arg to its W3C id string (or nil).
local function _opt_eid(element)
  if element == nil then return nil end
  return _eid(element)
end

function Actions:move_to_element(element)
  self._pointer[#self._pointer + 1] = _move_to(_eid(element))
  _sync_lengths(self)
  return self
end
function Actions:click(element)
  local id = _opt_eid(element)
  if id then self._pointer[#self._pointer + 1] = _move_to(id) end
  self._pointer[#self._pointer + 1] = _button_down(0)
  self._pointer[#self._pointer + 1] = _button_up(0)
  _sync_lengths(self)
  return self
end
function Actions:context_click(element)
  local id = _opt_eid(element)
  if id then self._pointer[#self._pointer + 1] = _move_to(id) end
  self._pointer[#self._pointer + 1] = _button_down(2)
  self._pointer[#self._pointer + 1] = _button_up(2)
  _sync_lengths(self)
  return self
end
function Actions:double_click(element)
  local id = _opt_eid(element)
  if id then self._pointer[#self._pointer + 1] = _move_to(id) end
  for _ = 1, 2 do
    self._pointer[#self._pointer + 1] = _button_down(0)
    self._pointer[#self._pointer + 1] = _button_up(0)
  end
  _sync_lengths(self)
  return self
end
function Actions:click_and_hold(element)
  local id = _opt_eid(element)
  if id then self._pointer[#self._pointer + 1] = _move_to(id) end
  self._pointer[#self._pointer + 1] = _button_down(0)
  _sync_lengths(self)
  return self
end
function Actions:release(element)
  local id = _opt_eid(element)
  if id then self._pointer[#self._pointer + 1] = _move_to(id) end
  self._pointer[#self._pointer + 1] = _button_up(0)
  _sync_lengths(self)
  return self
end
function Actions:drag_and_drop(source, target)
  self:click_and_hold(source)
  self:move_to_element(target)
  self:release(nil)
  return self
end
-- key gestures accept a Keys.* code point (number) or a single-char string.
-- Resolve either to a code point (utf8 library on 5.3+, else the first byte).
local function _key_cp(key)
  if type(key) == "number" then return key end
  if utf8 and utf8.codepoint then return utf8.codepoint(key) end
  return key:byte(1)
end
function Actions:key_down(key)
  self._key[#self._key + 1] = _key_event("keyDown", _key_cp(key))
  _sync_lengths(self)
  return self
end
function Actions:key_up(key)
  self._key[#self._key + 1] = _key_event("keyUp", _key_cp(key))
  _sync_lengths(self)
  return self
end
function Actions:send_keys(text)
  -- One keyDown+keyUp per UTF-8 character (walk lead bytes, like send_keys).
  local i, n = 1, #text
  while i <= n do
    local b = text:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3 elseif b >= 0xC0 then len = 2 end
    local ch = text:sub(i, i + len - 1)
    self._key[#self._key + 1] = { type = "keyDown", value = ch }
    self._key[#self._key + 1] = { type = "keyUp", value = ch }
    i = i + len
  end
  _sync_lengths(self)
  return self
end
function Actions:pause(duration_ms)
  self._pointer[#self._pointer + 1] = _pause(duration_ms)
  _sync_lengths(self)
  return self
end

-- The W3C actions array assembled from the two device lists. A device sub-array
-- is emitted only when it holds a real (non-pause) action.
function Actions:build()
  local out = M.array({})
  local has_ptr = false
  for _, a in ipairs(self._pointer) do if not _is_pause(a) then has_ptr = true; break end end
  local has_key = false
  for _, a in ipairs(self._key) do if not _is_pause(a) then has_key = true; break end end
  if has_ptr then
    out[#out + 1] = {
      type = "pointer", id = "mouse",
      parameters = { pointerType = "mouse" },
      actions = M.array(self._pointer),
    }
  end
  if has_key then
    out[#out + 1] = { type = "key", id = "keyboard", actions = M.array(self._key) }
  end
  return out
end

-- Post the queued gestures as one `actions` command (a no-op if only pauses).
function Actions:perform()
  local actions = self:build()
  if #actions == 0 then return end
  self.driver:perform_actions(actions)
end

M.Actions = Actions

-- Start a fluent Actions builder bound to this driver.
function WebDriver:actions() return new_actions(self) end

-- ==== Select (<select> dropdown helper) ====
-- Wraps a <select> WebElement and drives it by finding/clicking its <option>
-- children — the same approach mainstream Selenium's Select uses. Build with
-- Select.new(element).

local Select = {}
Select.__index = Select

function Select.new(element)
  local tag = element:tag_name()
  if type(tag) == "string" then tag = tag:lower() end
  if tag ~= "select" then
    raise(0, "Select only works on <select> elements, not <" .. tostring(tag) .. ">")
  end
  -- `multiple` is a boolean attribute: present (non-"false") => multi-select.
  local multi = element:get_attribute("multiple")
  local is_multiple = multi ~= nil and multi ~= "" and multi ~= "false"
  return setmetatable({ element = element, is_multiple = is_multiple }, Select)
end

function Select:multiple() return self.is_multiple end

-- All <option> children in document order.
function Select:options() return self.element:find_elements(M.By.tag_name("option")) end

-- The options currently selected.
function Select:all_selected_options()
  local out = {}
  for _, o in ipairs(self:options()) do
    if o:is_selected() then out[#out + 1] = o end
  end
  return out
end

-- The first selected option; raises (no such element) if none is selected.
function Select:first_selected_option()
  for _, o in ipairs(self:options()) do
    if o:is_selected() then return o end
  end
  raise(17, "no option is selected")
end

-- Click an option to select it, but only if not already selected (a second
-- click would toggle a multi-select option off). Mirrors the reference _select.
local function _select_option(option)
  if not option:is_selected() then option:click() end
end

function Select:select_by_visible_text(text)
  for _, o in ipairs(self:options()) do
    if o:text() == text then _select_option(o); return end
  end
  raise(17, "no option with visible text " .. tostring(text))
end

function Select:select_by_value(value)
  for _, o in ipairs(self:options()) do
    if o:get_attribute("value") == value then _select_option(o); return end
  end
  raise(17, "no option with value " .. tostring(value))
end

function Select:select_by_index(index)
  local opts = self:options()
  -- 0-based index to match mainstream/reference; opts is 1-indexed in Lua.
  local o = opts[index + 1]
  if not o then raise(17, "no option at index " .. tostring(index)) end
  _select_option(o)
end

-- Deselect every selected option (multi-select only). Raises on a single-select.
function Select:deselect_all()
  if not self.is_multiple then
    raise(0, "deselect_all only makes sense on a multi-select")
  end
  for _, o in ipairs(self:options()) do
    if o:is_selected() then o:click() end
  end
end

M.Select = Select

-- ==== Wait (explicit waits) ====
-- driver:wait(timeout_ms):until_(cond) polls cond(driver) until it returns true
-- (or the deadline passes); :until_not(cond) waits for it to become false. A
-- NoSuchElement (code 17) raised by the condition is swallowed and retried, as
-- mainstream's ignored_exceptions default does. On timeout, raises code 21.
-- (Method is spelled until_ because `until` is a Lua keyword.)

local POLL_INTERVAL_MS = 500

local Wait = {}
Wait.__index = Wait

local function new_wait(driver, timeout_ms)
  return setmetatable({ driver = driver, timeout_ms = timeout_ms or 30000,
                        poll_ms = POLL_INTERVAL_MS }, Wait)
end

-- Override the poll cadence (ms); a non-positive value resets to the default.
function Wait:poll_every(interval_ms)
  self.poll_ms = (interval_ms and interval_ms > 0) and interval_ms or POLL_INTERVAL_MS
  return self
end

-- Monotonic-ish clock in seconds. os.clock measures CPU time (wrong for waits);
-- os.time has 1s resolution. Prefer a high-res clock if the host exposes one.
local function _now_s()
  if native.monotonic_s then return native.monotonic_s() end
  return os.time()
end

local function _sleep_ms(ms)
  if native.sleep_ms then native.sleep_ms(ms); return end
  -- Fallback busy-wait bounded by os.time (coarse, but correct for polling).
  local target = os.time() + math.max(1, math.floor(ms / 1000))
  while os.time() < target do end
end

-- Run `attempt` (returns "done"|"retry"|error via pcall) each tick until done or
-- the deadline. `attempt` is a function returning (settled_boolean). A raised
-- non-ignored error propagates; an ignored NoSuchElement is treated per caller.
local function _poll(self, attempt)
  local deadline = _now_s() + (self.timeout_ms / 1000)
  while true do
    local settled = attempt()
    if settled then return end
    if _now_s() >= deadline then
      raise(21, string.format("waited %.3fs for condition", self.timeout_ms / 1000))
    end
    _sleep_ms(self.poll_ms)
  end
end

-- cond(driver) -> boolean. Swallow+retry a NoSuchElement; propagate others.
function Wait:until_(cond)
  _poll(self, function()
    local ok, res = pcall(cond, self.driver)
    if ok then return res == true end
    if type(res) == "table" and res.code == 17 then return false end
    error(res, 0)
  end)
end

function Wait:until_not(cond)
  _poll(self, function()
    local ok, res = pcall(cond, self.driver)
    if ok then return res == false end
    if type(res) == "table" and res.code == 17 then return true end -- gone
    error(res, 0)
  end)
end

M.Wait = Wait

-- Start an explicit wait with the given timeout (ms).
function WebDriver:wait(timeout_ms) return new_wait(self, timeout_ms) end

-- find_element that maps a NoSuchElement miss to nil instead of raising — the
-- primitive the element-returning waits poll on.
local function _try_find(driver, by, value)
  local ok, res = pcall(function() return driver:find_element(by, value) end)
  if ok then return res end
  if type(res) == "table" and res.code == 17 then return nil end
  error(res, 0)
end

-- Block until an element matching the locator is present; return it.
function WebDriver:wait_for_element(by, value, timeout_ms)
  -- Support wait_for_element(By.id("x"), timeout_ms) 2-arg and 3-arg forms.
  if type(value) == "number" and timeout_ms == nil then
    timeout_ms, value = value, nil
  end
  local found
  self:wait(timeout_ms):until_(function(d)
    found = _try_find(d, by, value)
    return found ~= nil
  end)
  return found
end

-- Block until an element is present AND displayed; return it.
function WebDriver:wait_for_visible(by, value, timeout_ms)
  if type(value) == "number" and timeout_ms == nil then
    timeout_ms, value = value, nil
  end
  local found
  self:wait(timeout_ms):until_(function(d)
    local el = _try_find(d, by, value)
    if el and el:is_displayed() then found = el; return true end
    return false
  end)
  return found
end

-- Block until an element is present, displayed AND enabled (clickable); return it.
function WebDriver:wait_for_clickable(by, value, timeout_ms)
  if type(value) == "number" and timeout_ms == nil then
    timeout_ms, value = value, nil
  end
  local found
  self:wait(timeout_ms):until_(function(d)
    local el = _try_find(d, by, value)
    if el and el:is_displayed() and el:is_enabled() then found = el; return true end
    return false
  end)
  return found
end

-- Block until NO element matches the locator (absent/removed).
function WebDriver:wait_until_gone(by, value, timeout_ms)
  if type(value) == "number" and timeout_ms == nil then
    timeout_ms, value = value, nil
  end
  self:wait(timeout_ms):until_not(function(d)
    return _try_find(d, by, value) ~= nil
  end)
end

function WebDriver:wait_for_title_is(title, timeout_ms)
  self:wait(timeout_ms):until_(function(d) return d:title() == title end)
end
function WebDriver:wait_for_title_contains(substr, timeout_ms)
  self:wait(timeout_ms):until_(function(d) return d:title():find(substr, 1, true) ~= nil end)
end
function WebDriver:wait_for_url_is(url, timeout_ms)
  self:wait(timeout_ms):until_(function(d) return d:current_url() == url end)
end
function WebDriver:wait_for_url_contains(substr, timeout_ms)
  self:wait(timeout_ms):until_(function(d) return d:current_url():find(substr, 1, true) ~= nil end)
end

-- pure engine helpers
function M.route(command) return native.route(command) end
function M.error_code(w3c_error) return native.error_code(w3c_error) end
function M.locator(by, value) return native.by_locator(by, value) end
function M.configure_native_lib(path) native.configure(path) end

M.BiDi = BiDi

return M
