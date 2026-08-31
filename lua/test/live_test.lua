-- Live end-to-end + surface test (Lua): a real headless Chrome session driven
-- through the pure-Aether engine via the C extension. Lua's stdlib has no
-- sockets/process, so chromedriver and a content server are started by
-- lua/.tests.ae, which passes their URLs in via env:
--   SEL_CHROMEDRIVER_URL, SEL_BASE_URL  (absent = skip)
local s = require("selenium_core")

local cd_url = os.getenv("SEL_CHROMEDRIVER_URL")
local base = os.getenv("SEL_BASE_URL")
if not cd_url or not base then
  print("SKIPPED: SEL_CHROMEDRIVER_URL / SEL_BASE_URL not set (no chromedriver)")
  os.exit(0)
end

local function assert_eq(got, want, label)
  if got ~= want then
    print("FAIL: " .. label .. " — got '" .. tostring(got) .. "' want '" .. tostring(want) .. "'")
    os.exit(1)
  end
end

-- Headless Chrome; point at an explicit binary when SEL_CHROME_BINARY is set
-- (a box with no system Chrome but a cached Chrome-for-Testing).
local chrome_opts = { args = { "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage" } }
local chrome_bin = os.getenv("SEL_CHROME_BINARY")
if chrome_bin and #chrome_bin > 0 then chrome_opts.binary = chrome_bin end
local d = s.chrome(cd_url, { ["goog:chromeOptions"] = chrome_opts })
local ok, err = pcall(function()
  assert(#d:session_id() > 0, "session id present")
  print("  ok: session started")

  d:get(base .. "/one")
  assert_eq(d:title(), "Page One", "title")
  assert_eq(d:element_text(d:find_element(s.By.ID, "hdr")), "One", "hdr text")
  assert_eq(d:tag_name(d:find_element(s.By.CSS, "#go")):lower(), "a", "tag name")
  print("  ok: navigate + find + text/tag")

  -- navigation history
  d:click(d:find_element(s.By.ID, "go"))
  assert_eq(d:title(), "Page Two", "after click")
  d:back()
  assert_eq(d:title(), "Page One", "after back")
  d:forward()
  assert_eq(d:title(), "Page Two", "after forward")
  d:back()
  print("  ok: back / forward history")

  -- cookies
  d:delete_all_cookies()
  d:add_cookie({ name = "flavor", value = "mint" })
  assert_eq(d:cookie("flavor").value, "mint", "cookie value")
  d:delete_cookie("flavor")
  print("  ok: cookies")

  -- windows
  assert(#d:window_handles() >= 1, "window handles")
  d:set_window_rect({ width = 900, height = 650 })
  assert_eq(d:get_window_rect().width, 900, "window width")
  print("  ok: windows")

  -- execute_script shapes
  assert_eq(d:execute_script("return 6*7;"), 42, "script scalar")
  assert_eq(d:execute_script("return 'hi';"), "hi", "script string")
  assert_eq(d:execute_script("return arguments[0]+arguments[1];", { 40, 2 }), 42, "script args")
  print("  ok: execute_script")

  -- W3C actions: pointer click on the button
  local btn = d:find_element(s.By.ID, "btn")
  local r = d:element_rect(btn)
  local cx = math.floor(r.x + r.width / 2)
  local cy = math.floor(r.y + r.height / 2)
  d:perform_actions({ {
    type = "pointer", id = "mouse",
    parameters = { pointerType = "mouse" },
    actions = {
      { type = "pointerMove", duration = 0, x = cx, y = cy },
      { type = "pointerDown", button = 0 },
      { type = "pointerUp", button = 0 },
    },
  } })
  assert_eq(d:element_text(d:find_element(s.By.ID, "hdr")), "clicked", "actions click fired")
  d:clear_actions()
  print("  ok: W3C actions")

  -- screenshot -> PNG (check the header bytes)
  local shot = d:screenshot_base64()
  assert(#shot > 100 and shot:sub(1, 5) == "iVBOR", "screenshot base64 PNG header")
  print("  ok: screenshot")

  -- negative path
  local nok, nerr = pcall(function() return d:find_element(s.By.ID, "does-not-exist") end)
  assert((not nok) and nerr.code == 17, "no such element error")
  print("  ok: no such element error")

  -- atom-backed commands: isDisplayed / getAttribute / relative locators, run
  -- in-page by the engine (the same atoms every binding uses) via the C extension.
  d:get("data:text/html,<h1 id='hdr'>H</h1><button id='btn'>b</button>"
        .. "<p id='gone' style='display:none'>x</p>"
        .. "<a id='lnk' href='https://example.com/x'>l</a>")
  local a_hdr = d:find_element(s.By.ID, "hdr")
  local a_gone = d:find_element(s.By.ID, "gone")
  local a_lnk = d:find_element(s.By.ID, "lnk")
  assert(d:is_displayed(a_hdr) == true, "is_displayed #hdr true")
  assert(d:is_displayed(a_gone) == false, "is_displayed #gone false")
  local href = d:get_attribute(a_lnk, "href")
  assert(type(href) == "string" and href:find("example.com/x", 1, true), "get_attribute href")
  local rel = d:find_relative("button", { { kind = "below", sel = "#hdr" } })
  assert(#rel >= 1, "find_relative below #hdr")
  print("  ok: atoms (is_displayed / get_attribute / find_relative)")

  -- WebDriver-BiDi: subscribe to console log entries, emit one via the classic
  -- script channel, and receive the event asynchronously over the demux — the
  -- bidirectional half, over this session's negotiated webSocketUrl.
  assert(d:bidi_available(), "bidi available (webSocketUrl negotiated)")
  local ack = d:bidi():subscribe(s.BidiEvent.LOG_ENTRY_ADDED)
  assert_eq(ack.type, "success", "bidi subscribe ack")
  d:execute_script("console.log('bidi-hello');")
  local ev = d:bidi():next_event(s.BidiEvent.LOG_ENTRY_ADDED, 8000)
  assert(ev ~= nil, "log.entryAdded event received")
  assert_eq(ev.method, s.BidiEvent.LOG_ENTRY_ADDED, "event method")
  -- the logged text rides in params.args[1].value (Lua 1-indexed)
  local logged = ev.params and ev.params.args and ev.params.args[1] and ev.params.args[1].value
  assert_eq(logged, "bidi-hello", "event carries logged text")
  local status = d:bidi():command("session.status")
  assert_eq(status.type, "success", "bidi session.status command")
  print("  ok: BiDi (log.entryAdded event + session.status command)")

  -- script.evaluate — the richer alternative to execute_script.
  assert(d:bidi():top_context(), "bidi top_context non-nil")
  assert_eq(d:bidi():evaluate_value("6*7"), 42, "bidi evaluate 6*7")
  assert_eq(d:bidi():evaluate_value("Promise.resolve(41+1)"), 42, "bidi evaluate promise")
  print("  ok: BiDi evaluate (6*7 -> 42, Promise -> 42)")

  -- network interception — observe + release a paused request (one BiDi channel).
  local bidi = d:bidi()
  bidi:subscribe(s.BidiEvent.BEFORE_REQUEST_SENT)
  local ic = bidi:add_intercept("beforeRequestSent", "")  -- all URLs
  assert(ic, "network.addIntercept -> intercept id")
  d:execute_script("fetch('https://example.com/blocked').catch(function(){});")
  local nev = bidi:next_event(s.BidiEvent.BEFORE_REQUEST_SENT, 8000)
  assert(nev, "network.beforeRequestSent event received")
  local rid = s.BiDi.event_request_id(nev)
  assert(rid, "intercepted request has a request id")
  assert_eq(bidi:continue_request(rid).type, "success", "network.continueRequest")
  print("  ok: BiDi network intercept -> beforeRequestSent -> continueRequest")

  -- request mocking — provideResponse fulfills a paused request with a fake body.
  d:execute_script("window.__mock='';fetch('https://example.com/api').then(function(r){return r.text()}).then(function(t){window.__mock=t}).catch(function(){});")
  local nev2 = bidi:next_event(s.BidiEvent.BEFORE_REQUEST_SENT, 8000)
  local rid2 = s.BiDi.event_request_id(nev2)
  assert(rid2, "mock: request id")
  assert_eq(bidi:provide_response(rid2, 200, "text/plain", "MOCKED-BODY").type, "success", "provideResponse")
  local got = ""
  for _ = 1, 25 do
    got = tostring(d:execute_script("return window.__mock;"))
    if got:find("MOCKED-BODY", 1, true) then break end
    os.execute("sleep 0.2")
  end
  assert(got:find("MOCKED-BODY", 1, true), "page received the mocked body")
  print("  ok: BiDi network provideResponse mocked the body")

  -- network.setCacheBehavior — disable then restore the session HTTP cache.
  assert_eq(bidi:set_cache_behavior("bypass").type, "success", "setCacheBehavior bypass")
  assert_eq(bidi:set_cache_behavior("default").type, "success", "setCacheBehavior default")
  print("  ok: BiDi network setCacheBehavior (bypass/default)")
end)

d:quit()
if not ok then
  print("FAIL: " .. tostring(err and err.message or err))
  os.exit(1)
end
print("PASS: Lua live surface test green")
