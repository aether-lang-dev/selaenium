//! Third-party consumer example: imports the selenium_core Zig module and drives
//! the protocol. The engine .so is linked via build.zig's search path (the
//! staged copy has NO core/ sibling, so only the package's own native/ .so
//! links). Modes: ffi | live. Run with SELENIUM_CORE_LIB unset.
//!
//! Zig 0.16's std.net/std.process are Io-reworked; to stay clear of that churn
//! the live mode reads SEL_CHROMEDRIVER_URL from env (the .example.ae shell
//! spawns chromedriver) and navigates a data: URL — no in-process networking.
const std = @import("std");
const sel = @import("selenium");

fn getenv(name: [*:0]const u8) ?[]const u8 {
    const p = std.c.getenv(name) orelse return null;
    return std.mem.span(p);
}

fn fail(msg: []const u8) noreturn {
    std.debug.print("FAIL: {s}\n", .{msg});
    std.process.exit(1);
}

fn modeFfi(a: std.mem.Allocator) !void {
    if (getenv("SELENIUM_CORE_LIB")) |v| {
        if (v.len > 0) fail("SELENIUM_CORE_LIB is set; consumer must run without it");
    }
    const r = try sel.route(a, "get");
    defer a.free(r);
    if (!std.mem.eql(u8, r, "POST /session/:sessionId/url")) fail("route mismatch");
    if (try sel.errorCode(a, "no such element") != 17) fail("errorCode mismatch");
    const by = sel.By.id("main");
    const loc = try sel.locator(a, by.using, by.value);
    defer a.free(loc);
    if (std.mem.indexOf(u8, loc, "*[id=") == null) fail("locator mismatch");
    const res = sel.WebDriver.chrome(a, "http://127.0.0.1:1", "{\"browserName\":\"chrome\"}");
    if (!std.meta.isError(res)) fail("expected transport failure");
    std.debug.print("consumer(ffi): OK — bundled package linked its own .so via build.zig rpath\n", .{});
}

fn modeLive(a: std.mem.Allocator) !void {
    const cd_url = getenv("SEL_CHROMEDRIVER_URL") orelse {
        std.debug.print("consumer(live): SKIPPED — SEL_CHROMEDRIVER_URL not set (no chromedriver)\n", .{});
        return;
    };
    var d = try sel.WebDriver.headlessChrome(a, cd_url);
    defer d.deinit();
    const page =
        "data:text/html;charset=utf-8,%3C!doctype%20html%3E%3Ctitle%3EInstalled%3C/title%3E%3Ch1%20id=%22h%22%3EHi%3C/h1%3E";
    try d.get(page);
    const t = try d.title();
    defer a.free(t);
    if (!std.mem.eql(u8, t, "Installed")) fail("title mismatch");
    var h = try d.findElement(sel.By.id("h"));
    defer h.deinit();
    const txt = try d.elementText(&h);
    defer a.free(txt);
    if (!std.mem.eql(u8, txt, "Hi")) fail("text mismatch");
    try d.quit();
    std.debug.print("consumer(live): OK — bundled package drove real headless Chrome\n", .{});
}

pub fn main() !void {
    var dbg = std.heap.DebugAllocator(.{}){};
    const a = dbg.allocator();
    // Mode via env (SEL_MODE) — dodges Zig 0.16's reworked argv/process APIs.
    const mode: []const u8 = getenv("SEL_MODE") orelse "ffi";
    if (std.mem.eql(u8, mode, "ffi")) {
        try modeFfi(a);
    } else if (std.mem.eql(u8, mode, "live")) {
        try modeLive(a);
    } else {
        fail("unknown mode");
    }
}
