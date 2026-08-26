//! No-browser FFI test: proves the Zig binding links libselenium_core.so and
//! marshals correctly, exercising the pure engine helpers and the transport
//! error path. Run via `zig build test`.
const std = @import("std");
const sel = @import("root.zig");

test "route" {
    const a = std.testing.allocator;
    const r = try sel.route(a, "get");
    defer a.free(r);
    try std.testing.expectEqualStrings("POST /session/:sessionId/url", r);

    const n = try sel.route(a, "nope");
    defer a.free(n);
    try std.testing.expectEqualStrings("", n);
}

test "errorCode" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(i32, 17), try sel.errorCode(a, "no such element"));
    try std.testing.expectEqual(@as(i32, 0), try sel.errorCode(a, ""));
}

test "locator css" {
    const a = std.testing.allocator;
    const loc = try sel.locator(a, sel.By.css, "div.foo");
    defer a.free(loc);
    try std.testing.expectEqualStrings("{\"using\":\"css selector\",\"value\":\"div.foo\"}", loc);
}

test "locator id rewrite" {
    const a = std.testing.allocator;
    const loc = try sel.locator(a, sel.By.id, "main");
    defer a.free(loc);
    try std.testing.expect(std.mem.indexOf(u8, loc, "*[id=") != null);
}

test "transport failure" {
    const a = std.testing.allocator;
    const result = sel.WebDriver.chrome(a, "http://127.0.0.1:1", "{\"browserName\":\"chrome\"}");
    try std.testing.expectError(sel.Error.WebDriver, result);
}
