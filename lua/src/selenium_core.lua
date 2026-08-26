-- selenium_core — the idiomatic Lua WebDriver API over the shared Aether core.
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

M.By = {
  ID = "id",
  NAME = "name",
  CSS = "css selector",
  CLASS_NAME = "className",
  TAG_NAME = "tag name",
  LINK_TEXT = "link text",
  PARTIAL_LINK_TEXT = "partial link text",
  XPATH = "xpath",
}

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
          buf[#buf + 1] = utf8.char(tonumber(hex, 16))
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

-- ==== WebDriver ====

local WebDriver = {}
WebDriver.__index = WebDriver

local function new(command_executor, caps)
  local handle = native.open(command_executor)
  if not handle then raise(-1, "failed to open session handle") end
  local self = setmetatable({ handle = handle }, WebDriver)
  self:execute("newSession", { capabilities = { alwaysMatch = caps } })
  return self
end

function M.chrome(command_executor, options)
  local caps = { browserName = "chrome" }
  if options then for k, v in pairs(options) do caps[k] = v end end
  return new(command_executor, caps)
end

function M.headless_chrome(command_executor)
  return M.chrome(command_executor, {
    ["goog:chromeOptions"] = {
      args = { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" },
    },
  })
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

function WebDriver:find_element(by, value)
  local r = self:execute("findElement", decode_by(by, value))
  return r[W3C_ELEMENT_KEY]
end

function WebDriver:find_elements(by, value)
  local r = self:execute("findElements", decode_by(by, value))
  local out = {}
  for i = 1, #r do out[i] = r[i][W3C_ELEMENT_KEY] end
  return out
end

function WebDriver:click(element_id) self:execute("clickElement", { id = element_id }) end
function WebDriver:send_keys(element_id, text)
  local value = {}
  for _, cp in utf8.codes(text) do value[#value + 1] = utf8.char(cp) end
  self:execute("sendKeysToElement", { id = element_id, text = text, value = value })
end
function WebDriver:element_text(element_id) return self:execute("getElementText", { id = element_id }) end
function WebDriver:tag_name(element_id) return self:execute("getElementTagName", { id = element_id }) end
function WebDriver:element_rect(element_id) return self:execute("getElementRect", { id = element_id }) end
function WebDriver:element_property(element_id, name)
  return self:execute("getElementProperty", { id = element_id, name = name })
end

-- script
function WebDriver:execute_script(script, args)
  return self:execute("executeScript", { script = script, args = args or M.array({}) })
end

-- windows
function WebDriver:window_handles() return self:execute("getWindowHandles", {}) end
function WebDriver:current_window_handle() return self:execute("getCurrentWindowHandle", {}) end
function WebDriver:set_window_rect(rect) return self:execute("setWindowRect", rect) end
function WebDriver:get_window_rect() return self:execute("getWindowRect", {}) end

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
function WebDriver:screenshot_base64() return self:execute("screenshot", {}) end

-- lifecycle
function WebDriver:session_id() return native.session_id(self.handle) end
function WebDriver:quit()
  local ok, err = pcall(function() self:execute("quit", {}) end)
  native.close(self.handle)
  self.handle = nil
  if not ok then error(err, 0) end
end

-- pure engine helpers
function M.route(command) return native.route(command) end
function M.error_code(w3c_error) return native.error_code(w3c_error) end
function M.locator(by, value) return native.by_locator(by, value) end
function M.configure_native_lib(path) native.configure(path) end

return M
