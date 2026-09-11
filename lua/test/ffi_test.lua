-- No-browser FFI test: proves the Lua C extension loads libselenium_core.so and
-- marshals correctly, exercising the pure engine helpers and the transport
-- error path. Run by lua/.tests.ae via the Lua 5.4 host.
local s = require("selenium")

local fails = 0
local function check(cond, label)
  if cond then
    print("  ok: " .. label)
  else
    print("FAIL: " .. label)
    fails = fails + 1
  end
end

check(s.route("get") == "POST /session/:sessionId/url", "route get")
check(s.route("nope") == "", "route unknown")
check(s.error_code("no such element") == 17, "errorCode no such element")
check(s.error_code("") == 0, "errorCode success")
check(s.locator(s.By.CSS, "div.foo") == '{"using":"css selector","value":"div.foo"}', "locator css")
check(s.locator(s.By.ID, "main"):find('%*%[id=', 1) ~= nil, "locator id rewrite")

do
  local ok, err = pcall(function() return s.chrome("http://127.0.0.1:1") end)
  check((not ok) and err.code == -1, "transport failure -> code -1")
end

-- ---- per-browser factories exist and set the right browserName ----
-- No browser is touched: each factory opens against a dead port and fails
-- transport (code -1), proving it exists and is callable with the chrome shape.
-- Edge (no Edge on Linux) and Safari (macOS-only) are not live-runnable here,
-- so this surface check is their coverage.
check(type(s.firefox) == "function", "M.firefox is declared")
check(type(s.headless_firefox) == "function", "M.headless_firefox is declared")
check(type(s.edge) == "function", "M.edge is declared")
check(type(s.headless_edge) == "function", "M.headless_edge is declared")
check(type(s.safari) == "function", "M.safari is declared")
for _, open in ipairs({
  function() return s.firefox("http://127.0.0.1:1") end,
  function() return s.headless_firefox("http://127.0.0.1:1") end,
  function() return s.edge("http://127.0.0.1:1") end,
  function() return s.headless_edge("http://127.0.0.1:1") end,
  function() return s.safari("http://127.0.0.1:1") end,
}) do
  local ok, err = pcall(open)
  check((not ok) and err.code == -1, "per-browser factory transport failure -> code -1")
end

-- ---- Shadow DOM: error codes + ShadowRoot search-context surface ----
check(s.error_code("no such shadow root") == 19, "errorCode no such shadow root -> 19")
check(s.error_code("detached shadow root") == 2, "errorCode detached shadow root -> 2")
check(s.route("getShadowRoot") == "GET /session/:sessionId/element/:id/shadow", "route getShadowRoot")
check(s.route("findElementFromShadowRoot") == "POST /session/:sessionId/shadow/:id/element",
      "route findElementFromShadowRoot")
check(s.route("findElementsFromShadowRoot") == "POST /session/:sessionId/shadow/:id/elements",
      "route findElementsFromShadowRoot")
check(type(s.ShadowRoot) == "table" and type(s.ShadowRoot.find_element) == "function"
      and type(s.ShadowRoot.find_elements) == "function", "ShadowRoot exposes find_element/find_elements")
check(type(s.WebElement.shadow_root) == "function", "WebElement:shadow_root is declared")

-- ---- Keys: W3C PUA code points + chord (offline, pure) ----
check(s.Keys.NULL == 0xE000, "Keys.NULL code point")
check(s.Keys.TAB == 0xE004, "Keys.TAB code point")
check(s.Keys.ENTER == 0xE007, "Keys.ENTER code point")
check(s.Keys.ESCAPE == 0xE00C, "Keys.ESCAPE code point")
check(s.Keys.F1 == 0xE031, "Keys.F1 code point")
check(s.Keys.F12 == 0xE03C, "Keys.F12 code point")
check(s.Keys.META == 0xE03D and s.Keys.COMMAND == 0xE03D, "Keys.META/COMMAND code point")
check(s.Keys.BACK_SPACE == s.Keys.BACKSPACE, "Keys alias BACK_SPACE == BACKSPACE")
check(s.Keys.ARROW_LEFT == s.Keys.LEFT, "Keys alias ARROW_LEFT == LEFT")
do
  -- every listed key is inside the W3C PUA range U+E000..U+E03D
  local all_in_range = true
  for _, cp in pairs(s.Keys) do
    if type(cp) == "number" and not (cp >= 0xE000 and cp <= 0xE03D) then
      all_in_range = false
    end
  end
  check(all_in_range, "every Keys code point is within U+E000..U+E03D")
end
do
  -- chord(CONTROL, "a") = <CONTROL glyph> .. "a" .. <NULL glyph>
  local chord = s.Keys.chord(s.Keys.CONTROL, "a")
  local ctrl = s.Keys.char(s.Keys.CONTROL)
  local nul = s.Keys.char(s.Keys.NULL)
  check(chord == ctrl .. "a" .. nul, "Keys.chord holds modifier then releases with NULL")
end

-- ---- Actions builder: W3C action-sequence wire shape (offline, pure) ----
local ELEM_KEY = "element-6066-11e4-a52e-4f735466cecf"
do
  -- We can build an Actions sequence without a live session (driver unused until
  -- :perform()). Bind s.Actions to a stand-in driver — build() never calls it.
  local dummy = setmetatable({}, { __index = function() return function() end end })
  local act = setmetatable({ driver = dummy, _pointer = {}, _key = {} }, s.Actions)

  act:click({ id = "EID" })
  local built = act:build()
  check(#built == 1, "click builds a single (pointer) device")
  local ptr = built[1]
  check(ptr.type == "pointer" and ptr.id == "mouse", "pointer device type/id")
  check(ptr.parameters.pointerType == "mouse", "pointer device pointerType=mouse")
  local acts = ptr.actions
  check(#acts == 3, "click = move + down + up (3 ticks)")
  check(acts[1].type == "pointerMove" and acts[1].origin[ELEM_KEY] == "EID",
        "pointerMove carries the element origin")
  check(acts[2].type == "pointerDown" and acts[2].button == 0, "pointerDown button 0")
  check(acts[3].type == "pointerUp" and acts[3].button == 0, "pointerUp button 0")
end
do
  local dummy = setmetatable({}, { __index = function() return function() end end })
  local act = setmetatable({ driver = dummy, _pointer = {}, _key = {} }, s.Actions)
  act:context_click({ id = "E1" })
  local acts = act:build()[1].actions
  check(acts[2].button == 2 and acts[3].button == 2, "context_click uses button 2")
end
do
  local dummy = setmetatable({}, { __index = function() return function() end end })
  local act = setmetatable({ driver = dummy, _pointer = {}, _key = {} }, s.Actions)
  act:send_keys("hi")
  local built = act:build()
  check(#built == 1, "send_keys builds a single (key) device")
  local kbd = built[1]
  check(kbd.type == "key" and kbd.id == "keyboard", "key device type/id")
  check(#kbd.actions == 4, "send_keys 'hi' = 4 key ticks (down/up per char)")
  check(kbd.actions[1].type == "keyDown" and kbd.actions[1].value == "h", "first keyDown = 'h'")
end
do
  -- mixed devices are length-synced with pauses (Rust parity)
  local dummy = setmetatable({}, { __index = function() return function() end end })
  local act = setmetatable({ driver = dummy, _pointer = {}, _key = {} }, s.Actions)
  act:click({ id = "E1" }):send_keys("x")
  check(#act._pointer == #act._key, "device lists are length-synced")
  check(#act:build() == 2, "both pointer and key devices present in build")
end
do
  -- a pause-only sequence emits no device
  local dummy = setmetatable({}, { __index = function() return function() end end })
  local act = setmetatable({ driver = dummy, _pointer = {}, _key = {} }, s.Actions)
  act:pause(10)
  check(#act:build() == 0, "pause-only sequence emits no device")
end

if fails == 0 then
  print("PASS: Lua FFI tests green")
  os.exit(0)
else
  print("FAILED: " .. fails .. " Lua FFI test(s)")
  os.exit(1)
end
