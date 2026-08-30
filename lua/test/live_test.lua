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

local d = s.headless_chrome(cd_url)
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
end)

d:quit()
if not ok then
  print("FAIL: " .. tostring(err and err.message or err))
  os.exit(1)
end
print("PASS: Lua live surface test green")
