//! Live end-to-end + surface test (Zig): a real headless Chrome session driven
//! through the pure-Aether engine via the linked .so.
//!
//! Zig 0.16 reworked std.net/std.process around the new Io interface; to keep
//! this test free of that churn, chromedriver and a content server are started
//! by the .tests.ae shell, which passes their URLs in via env:
//!   SEL_CHROMEDRIVER_URL  — e.g. http://127.0.0.1:PORT (required; absent = skip)
//!   SEL_BASE_URL          — the content server base, e.g. http://127.0.0.1:PORT
//! Everything below is pure WebDriver + std.mem/json/fmt (stable APIs).
const std = @import("std");
const sel = @import("selenium_core");

fn getenv(name: [*:0]const u8) ?[]const u8 {
    const p = std.c.getenv(name) orelse return null;
    return std.mem.span(p);
}

/// Read a std.json number as f64 whether it parsed as .integer or .float.
fn numAsF64(v: std.json.Value) f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => 0,
    };
}

fn assert(cond: bool, msg: []const u8) void {
    if (!cond) {
        std.debug.print("FAIL: {s}\n", .{msg});
        std.process.exit(1);
    }
}

pub fn main() !void {
    var dbg = std.heap.DebugAllocator(.{}){};
    const a = dbg.allocator();

    const cd_url = getenv("SEL_CHROMEDRIVER_URL") orelse {
        std.debug.print("SKIPPED: SEL_CHROMEDRIVER_URL not set (no chromedriver)\n", .{});
        return;
    };
    const base = getenv("SEL_BASE_URL") orelse {
        std.debug.print("SKIPPED: SEL_BASE_URL not set\n", .{});
        return;
    };

    var d = try sel.WebDriver.headlessChrome(a, cd_url);
    defer d.deinit();

    const sid = try d.sessionId();
    defer a.free(sid);
    assert(sid.len > 0, "session id present");
    std.debug.print("  ok: session started\n", .{});

    // navigate
    const url_one = try std.fmt.allocPrint(a, "{s}/one", .{base});
    defer a.free(url_one);
    try d.get(url_one);
    {
        const t = try d.title();
        defer a.free(t);
        assert(std.mem.eql(u8, t, "Page One"), "title Page One");
    }
    {
        var hdr = try d.findElement(sel.By.id, "hdr");
        defer hdr.deinit();
        const txt = try d.elementText(&hdr);
        defer a.free(txt);
        assert(std.mem.eql(u8, txt, "One"), "hdr text One");
    }
    std.debug.print("  ok: navigate + find + text\n", .{});

    // navigation history
    {
        var go = try d.findElement(sel.By.id, "go");
        defer go.deinit();
        try d.elementClick(&go);
    }
    {
        const t = try d.title();
        defer a.free(t);
        assert(std.mem.eql(u8, t, "Page Two"), "after click");
    }
    try d.back();
    {
        const t = try d.title();
        defer a.free(t);
        assert(std.mem.eql(u8, t, "Page One"), "after back");
    }
    try d.forward();
    {
        const t = try d.title();
        defer a.free(t);
        assert(std.mem.eql(u8, t, "Page Two"), "after forward");
    }
    try d.back();
    std.debug.print("  ok: back / forward history\n", .{});

    // cookies
    try d.deleteAllCookies();
    try d.addCookie("{\"name\":\"flavor\",\"value\":\"mint\"}");
    {
        var v = try d.cookie("flavor");
        defer v.deinit();
        const val = switch (v.value) {
            .object => |o| switch (o.get("value") orelse std.json.Value{ .null = {} }) {
                .string => |s| s,
                else => "",
            },
            else => "",
        };
        assert(std.mem.eql(u8, val, "mint"), "cookie value mint");
    }
    std.debug.print("  ok: cookies\n", .{});

    // windows
    assert(try d.windowHandlesCount() >= 1, "window handles");
    try d.setWindowRect("{\"width\":900,\"height\":650}");
    std.debug.print("  ok: windows\n", .{});

    // execute_script shapes
    {
        var v = try d.executeScript("return 6*7;", "[]");
        defer v.deinit();
        const n = switch (v.value) {
            .integer => |x| x,
            else => -1,
        };
        assert(n == 42, "script scalar 42");
    }
    {
        var v = try d.executeScript("return arguments[0]+arguments[1];", "[40,2]");
        defer v.deinit();
        const n = switch (v.value) {
            .integer => |x| x,
            else => -1,
        };
        assert(n == 42, "script args 42");
    }
    std.debug.print("  ok: execute_script\n", .{});

    // W3C actions: pointer click on the button
    {
        var btn = try d.findElement(sel.By.id, "btn");
        defer btn.deinit();
        var rv = try d.elementRect(&btn);
        defer rv.deinit();
        const obj = rv.value.object;
        const x = numAsF64(obj.get("x").?);
        const y = numAsF64(obj.get("y").?);
        const w = numAsF64(obj.get("width").?);
        const h = numAsF64(obj.get("height").?);
        const cx: i64 = @intFromFloat(x + w / 2);
        const cy: i64 = @intFromFloat(y + h / 2);
        const actions = try std.fmt.allocPrint(a, "[{{\"type\":\"pointer\",\"id\":\"mouse\",\"parameters\":{{\"pointerType\":\"mouse\"}},\"actions\":[{{\"type\":\"pointerMove\",\"duration\":0,\"x\":{d},\"y\":{d}}},{{\"type\":\"pointerDown\",\"button\":0}},{{\"type\":\"pointerUp\",\"button\":0}}]}}]", .{ cx, cy });
        defer a.free(actions);
        try d.performActions(actions);
    }
    {
        var hdr = try d.findElement(sel.By.id, "hdr");
        defer hdr.deinit();
        const txt = try d.elementText(&hdr);
        defer a.free(txt);
        assert(std.mem.eql(u8, txt, "clicked"), "actions click fired");
    }
    try d.clearActions();
    std.debug.print("  ok: W3C actions\n", .{});

    // screenshot -> PNG
    {
        const b64 = try d.screenshotBase64();
        defer a.free(b64);
        const dec = std.base64.standard.Decoder;
        const len = try dec.calcSizeForSlice(b64);
        const raw = try a.alloc(u8, len);
        defer a.free(raw);
        try dec.decode(raw, b64);
        assert(raw.len > 8 and std.mem.eql(u8, raw[1..4], "PNG"), "screenshot is PNG");
    }
    std.debug.print("  ok: screenshot\n", .{});

    // negative path
    {
        const r = d.findElement(sel.By.id, "does-not-exist");
        assert(std.meta.isError(r), "findElement errored");
        assert(d.last != null and d.last.?.kind == .no_such_element, "no such element kind");
    }
    std.debug.print("  ok: no such element error\n", .{});

    // ---- WebDriver-BiDi (live) ----
    // Subscribe to log.entryAdded, navigate a data: page, emit a console.log
    // through the classic script channel, then drain the BiDi event queue for
    // the matching event and round-trip a session.status command.
    {
        assert(d.bidiAvailable(), "bidi available (webSocketUrl negotiated)");

        // A minimal, self-contained page so the log entry is ours alone.
        const bidi_page =
            "data:text/html;charset=utf-8,%3C!doctype%20html%3E%3Ctitle%3EBiDi%3C/title%3E%3Ch1%3EBiDi%3C/h1%3E";
        try d.get(bidi_page);

        const bidi = try d.bidi();

        // session.subscribe -> ack "type" == "success"
        {
            var ack = (try bidi.subscribe(&[_][]const u8{sel.BidiEvent.log_entry_added}, 10000)) orelse {
                assert(false, "subscribe returned an ack");
                unreachable;
            };
            defer ack.deinit();
            const ack_type = switch (ack.value) {
                .object => |o| switch (o.get("type") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, ack_type, "success"), "subscribe ack type success");
        }
        std.debug.print("  ok: bidi subscribe (log.entryAdded)\n", .{});

        // Emit a console.log through the classic script channel; BiDi observes it.
        {
            var v = try d.executeScript("console.log('bidi-hello');", "[]");
            v.deinit();
        }

        // Drain the queue for the matching event; serialize and assert it carries
        // our logged text.
        {
            var ev = (try bidi.nextEvent(sel.BidiEvent.log_entry_added, 8000)) orelse {
                assert(false, "nextEvent returned a log.entryAdded event");
                unreachable;
            };
            defer ev.deinit();

            const method = switch (ev.value) {
                .object => |o| switch (o.get("method") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, method, sel.BidiEvent.log_entry_added), "event method is log.entryAdded");

            // Stringify the whole event and look for our text anywhere in it.
            const serialized = try std.json.Stringify.valueAlloc(a, ev.value, .{});
            defer a.free(serialized);
            assert(std.mem.indexOf(u8, serialized, "bidi-hello") != null, "event carries bidi-hello");
        }
        std.debug.print("  ok: bidi log.entryAdded event (bidi-hello)\n", .{});

        // session.status round-trip -> reply "type" == "success"
        {
            var status = try bidi.command("session.status", "{}", 10000);
            defer status.deinit();
            const status_type = switch (status.value) {
                .object => |o| switch (o.get("type") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, status_type, "success"), "session.status reply type success");
        }
        std.debug.print("  ok: bidi session.status command\n", .{});

        // ---- typed BiDi convenience commands (getTree / evaluate / navigate) ----
        // topContext: non-empty context id from browsingContext.getTree.
        {
            const ctx = try bidi.topContext(10000);
            defer a.free(ctx);
            assert(ctx.len > 0, "bidi topContext non-empty");
        }
        std.debug.print("  ok: bidi topContext (non-empty)\n", .{});

        // script.evaluate 6*7 -> 42 (a plain expression in the real realm).
        {
            const n = try bidi.evaluateValue("6*7", "", 30000);
            assert(n == 42, "bidi evaluate 6*7 == 42");
        }
        std.debug.print("  ok: bidi evaluate (6*7 -> 42)\n", .{});

        // script.evaluate a promise -> awaited to 42 (promise-awaiting realm).
        {
            const n = try bidi.evaluateValue("Promise.resolve(41+1)", "", 30000);
            assert(n == 42, "bidi evaluate Promise.resolve(41+1) == 42");
        }
        std.debug.print("  ok: bidi evaluate (Promise.resolve(41+1) -> 42)\n", .{});

        // ---- network interception: observe + release a paused request ----
        {
            _ = (try bidi.subscribe(&[_][]const u8{sel.BidiEvent.before_request_sent}, 10000)) orelse {
                assert(false, "subscribe network.beforeRequestSent");
                return;
            };
            const intercept = try bidi.addIntercept("beforeRequestSent", "", 10000);
            defer a.free(intercept);
            assert(intercept.len > 0, "network.addIntercept -> intercept id");

            var fv = try d.executeScript("fetch('https://example.com/blocked').catch(function(){});", "[]");
            fv.deinit();

            var netev = (try bidi.nextEvent(sel.BidiEvent.before_request_sent, 8000)) orelse {
                assert(false, "network.beforeRequestSent event received");
                return;
            };
            defer netev.deinit();
            const rid = (try sel.BiDi.eventRequestId(a, netev.value)) orelse {
                assert(false, "intercepted request has a request id");
                return;
            };
            defer a.free(rid);
            assert(rid.len > 0, "request id non-empty");

            var cont = try bidi.continueRequest(rid, 10000);
            defer cont.deinit();
            const cont_type = switch (cont.value) {
                .object => |o| switch (o.get("type") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, cont_type, "success"), "network.continueRequest success");
        }
        std.debug.print("  ok: bidi network intercept -> beforeRequestSent -> continueRequest\n", .{});

        // request MOCKING: fulfill a paused request with a fake body.
        {
            var fv = try d.executeScript("window.__mock='';fetch('https://example.com/api').then(function(r){return r.text()}).then(function(t){window.__mock=t}).catch(function(){});", "[]");
            fv.deinit();
            var netev2 = (try bidi.nextEvent(sel.BidiEvent.before_request_sent, 8000)) orelse {
                assert(false, "mock: beforeRequestSent event received");
                return;
            };
            defer netev2.deinit();
            const rid2 = (try sel.BiDi.eventRequestId(a, netev2.value)) orelse {
                assert(false, "mock: request id");
                return;
            };
            defer a.free(rid2);
            var resp = try bidi.provideResponse(rid2, 200, "text/plain", "MOCKED-BODY", 10000);
            defer resp.deinit();
            const resp_type = switch (resp.value) {
                .object => |o| switch (o.get("type") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, resp_type, "success"), "network.provideResponse success");
            // poll window.__mock for the mocked body. Each executeScript is a
            // round-trip to chromedriver (~ms), which paces the loop without an
            // explicit sleep (zig 0.16 moved sleep behind the std.Io interface).
            var got = false;
            var tries: u32 = 0;
            while (tries < 200) : (tries += 1) {
                var mv = try d.executeScript("return window.__mock;", "[]");
                const m = switch (mv.value) {
                    .string => |s| s,
                    else => "",
                };
                if (std.mem.indexOf(u8, m, "MOCKED-BODY") != null) got = true;
                mv.deinit();
                if (got) break;
            }
            assert(got, "page received the mocked body");
        }
        std.debug.print("  ok: bidi network provideResponse mocked the body\n", .{});

        // network.setCacheBehavior: bypass disables the session HTTP cache, then
        // default restores it — each returns a success reply.
        {
            var bypass = try bidi.setCacheBehavior("bypass", 10000);
            defer bypass.deinit();
            const bt = switch (bypass.value) {
                .object => |o| switch (o.get("type") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, bt, "success"), "network.setCacheBehavior bypass success");

            var deflt = try bidi.setCacheBehavior("default", 10000);
            defer deflt.deinit();
            const dt = switch (deflt.value) {
                .object => |o| switch (o.get("type") orelse std.json.Value{ .null = {} }) {
                    .string => |s| s,
                    else => "",
                },
                else => "",
            };
            assert(std.mem.eql(u8, dt, "success"), "network.setCacheBehavior default success");
        }
        std.debug.print("  ok: bidi network setCacheBehavior (bypass/default)\n", .{});
        // continueWithAuth needs a WWW-Authenticate server; bind it for compile
        // coverage without invoking it here.
        _ = &sel.BiDi.continueWithAuth;
    }

    // ---- atom-backed commands (isDisplayed / getAttribute / findRelative) ----
    // Navigate a self-contained data: page and exercise the three atom verbs.
    {
        const atoms_page =
            "data:text/html;charset=utf-8," ++
            "%3C!doctype%20html%3E%3Ctitle%3EAtoms%3C/title%3E" ++
            "%3Ch1%20id='hdr'%3EAtoms%3C/h1%3E" ++
            "%3Cbutton%20id='btn'%3EGo%3C/button%3E" ++
            "%3Cp%20id='gone'%20style='display:none'%3Ehidden%3C/p%3E" ++
            "%3Ca%20id='lnk'%20href='https://example.com/x'%3Elink%3C/a%3E";
        try d.get(atoms_page);

        // isDisplayed: true for a visible header, false for display:none.
        {
            var hdr = try d.findElement(sel.By.id, "hdr");
            defer hdr.deinit();
            assert(try d.isDisplayed(&hdr), "isDisplayed #hdr true");

            var gone = try d.findElement(sel.By.id, "gone");
            defer gone.deinit();
            assert(!(try d.isDisplayed(&gone)), "isDisplayed #gone false");
        }
        std.debug.print("  ok: atom isDisplayed (#hdr true, #gone false)\n", .{});

        // getAttribute: the href of the anchor carries our target.
        {
            var lnk = try d.findElement(sel.By.id, "lnk");
            defer lnk.deinit();
            var href = try d.getAttribute(&lnk, "href");
            defer href.deinit();
            const s = switch (href.value) {
                .string => |x| x,
                else => "",
            };
            assert(std.mem.indexOf(u8, s, "example.com/x") != null, "getAttribute href has example.com/x");
        }
        std.debug.print("  ok: atom getAttribute (#lnk href has example.com/x)\n", .{});

        // findRelative: a button below the header — at least one match.
        {
            var rel = try d.findRelative("button", "[{\"kind\":\"below\",\"sel\":\"#hdr\"}]");
            defer rel.deinit();
            const count = switch (rel.value) {
                .array => |arr| arr.items.len,
                else => 0,
            };
            assert(count >= 1, "findRelative button below #hdr count>=1");
        }
        std.debug.print("  ok: atom findRelative (button below #hdr count>=1)\n", .{});
    }

    try d.quit();
    std.debug.print("PASS: Zig live surface test green\n", .{});
}
