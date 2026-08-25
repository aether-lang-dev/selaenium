-- Third-party consumer example: requires the INSTALLED selenium_core Lua package
-- (the packaged copy staged under target/lua-pkg, carrying selenium_core.lua +
-- the C extension + a bundled native/ .so, but NO core/ sibling — so the
-- extension's own native/ fallback is the only way the engine loads). Run with
-- SELENIUM_CORE_LIB unset. Modes: ffi | discovery | live (via SEL_MODE).
local s = require("selenium_core")

local function fail(msg)
  io.stderr:write("FAIL: " .. msg .. "\n")
  os.exit(1)
end

local function mode_ffi()
  if (os.getenv("SELENIUM_CORE_LIB") or "") ~= "" then
    fail("SELENIUM_CORE_LIB is set; consumer must run without it")
  end
  if s.route("get") ~= "POST /session/:sessionId/url" then fail("route mismatch") end
  if s.error_code("no such element") ~= 17 then fail("errorCode mismatch") end
  if not s.locator(s.By.ID, "main"):find("%*%[id=") then fail("locator mismatch") end
  local ok, err = pcall(function() return s.chrome("http://127.0.0.1:1") end)
  if ok or err.code ~= -1 then fail("expected transport failure") end
  print("consumer(ffi): OK — installed package loaded its bundled .so and marshalled")
end

local function mode_discovery()
  if (os.getenv("SELENIUM_CORE_LIB") or "") ~= "" then
    fail("SELENIUM_CORE_LIB set; discovery must run without it")
  end
  -- A pure call forces the extension to dlopen its bundled native/ .so.
  if s.route("newSession") ~= "POST /session" then fail("route mismatch (bundled .so did not load)") end
  print("consumer(discovery): OK — zero-config bundled-.so discovery works")
end

local function mode_live()
  local cd_url = os.getenv("SEL_CHROMEDRIVER_URL")
  if not cd_url then
    print("consumer(live): SKIPPED — SEL_CHROMEDRIVER_URL not set (no chromedriver)")
    return
  end
  local d = s.headless_chrome(cd_url)
  local ok, err = pcall(function()
    local html = "<!doctype html><title>Installed</title><h1 id=\"h\">Hi</h1>"
    -- percent-encode spaces/quotes for the data: URL
    local enc = html:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end)
    d:get("data:text/html;charset=utf-8," .. enc)
    if d:title() ~= "Installed" then fail("title mismatch") end
    if d:element_text(d:find_element(s.By.ID, "h")) ~= "Hi" then fail("text mismatch") end
  end)
  d:quit()
  if not ok then error(err, 0) end
  print("consumer(live): OK — installed package drove real headless Chrome")
end

local mode = os.getenv("SEL_MODE") or "ffi"
if mode == "ffi" then mode_ffi()
elseif mode == "discovery" then mode_discovery()
elseif mode == "live" then mode_live()
else fail("unknown mode: " .. mode) end
