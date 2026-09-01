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

if fails == 0 then
  print("PASS: Lua FFI tests green")
  os.exit(0)
else
  print("FAILED: " .. fails .. " Lua FFI test(s)")
  os.exit(1)
end
