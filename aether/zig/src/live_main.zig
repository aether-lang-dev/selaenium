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
        const actions = try std.fmt.allocPrint(a,
            "[{{\"type\":\"pointer\",\"id\":\"mouse\",\"parameters\":{{\"pointerType\":\"mouse\"}},\"actions\":[{{\"type\":\"pointerMove\",\"duration\":0,\"x\":{d},\"y\":{d}}},{{\"type\":\"pointerDown\",\"button\":0}},{{\"type\":\"pointerUp\",\"button\":0}}]}}]",
            .{ cx, cy });
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

    try d.quit();
    std.debug.print("PASS: Zig live surface test green\n", .{});
}
