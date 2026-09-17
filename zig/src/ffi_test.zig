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
    const loc = try sel.locator(a, "css selector", "div.foo");
    defer a.free(loc);
    try std.testing.expectEqualStrings("{\"using\":\"css selector\",\"value\":\"div.foo\"}", loc);
}

test "locator id rewrite" {
    const a = std.testing.allocator;
    const loc = try sel.locator(a, "id", "main");
    defer a.free(loc);
    try std.testing.expect(std.mem.indexOf(u8, loc, "*[id=") != null);
}

test "By factory yields the right strategy" {
    try std.testing.expectEqualStrings("css selector", sel.By.cssSelector("div").using);
    try std.testing.expectEqualStrings("id", sel.By.id("main").using);
    try std.testing.expectEqualStrings("xpath", sel.By.xpath("//a").using);
}

test "transport failure" {
    const a = std.testing.allocator;
    const result = sel.WebDriver.chrome(a, "http://127.0.0.1:1", "{\"browserName\":\"chrome\"}");
    try std.testing.expectError(sel.Error.WebDriver, result);
}

// ---- Keys ----

test "Keys code points match the W3C spec" {
    // The UTF-8 encoding of the private-use scalars U+E000..U+E03D.
    try std.testing.expectEqualStrings("\u{E000}", sel.Keys.null_key);
    try std.testing.expectEqualStrings("\u{E004}", sel.Keys.tab);
    try std.testing.expectEqualStrings("\u{E007}", sel.Keys.enter);
    try std.testing.expectEqualStrings("\u{E00C}", sel.Keys.escape);
    try std.testing.expectEqualStrings("\u{E03D}", sel.Keys.meta);
    try std.testing.expectEqualStrings(sel.Keys.meta, sel.Keys.command);
}

test "Keys.chord holds modifier then releases with NULL" {
    const a = std.testing.allocator;
    const s = try sel.Keys.chord(a, sel.Keys.control, "a");
    defer a.free(s);
    // control + "a" + NULL, all in UTF-8.
    try std.testing.expectEqualStrings("\u{E009}a\u{E000}", s);
}

// ---- Select option-matching core (browser-free) ----

fn sampleOptions() [3]sel.OptionInfo {
    return .{
        .{ .text = "Argentina", .value = "ar" },
        .{ .text = "Spain", .value = "es" },
        .{ .text = "Sweden", .value = "se" },
    };
}

test "Select find by visible text picks the right option" {
    const opts = sampleOptions();
    try std.testing.expectEqual(@as(?usize, 1), sel.findOptionByText(&opts, "Spain"));
    try std.testing.expectEqual(@as(?usize, 2), sel.findOptionByText(&opts, "Sweden"));
    try std.testing.expectEqual(@as(?usize, null), sel.findOptionByText(&opts, "Narnia"));
}

test "Select find by value picks the right option" {
    const opts = sampleOptions();
    try std.testing.expectEqual(@as(?usize, 1), sel.findOptionByValue(&opts, "es"));
    try std.testing.expectEqual(@as(?usize, 0), sel.findOptionByValue(&opts, "ar"));
    try std.testing.expectEqual(@as(?usize, null), sel.findOptionByValue(&opts, "zz"));
}

test "Select first match wins in document order" {
    const opts = [_]sel.OptionInfo{
        .{ .text = "Dup", .value = "a" },
        .{ .text = "Dup", .value = "b" },
    };
    try std.testing.expectEqual(@as(?usize, 0), sel.findOptionByText(&opts, "Dup"));
}

// ---- Actions builder (browser-free wire-shape checks) ----

test "Actions click builds move/down/up on the mouse device" {
    const a = std.testing.allocator;
    var driver = sel.WebDriver{ .allocator = a, .handle = null };
    var acts = sel.Actions.init(&driver);
    const el = sel.WebElement{ .driver = &driver, .id = @constCast("E1") };
    _ = acts.click(&el);
    const built = try acts.build();
    defer a.free(built);
    acts.deinit();
    try std.testing.expect(std.mem.indexOf(u8, built, "\"type\":\"pointer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"pointerType\":\"mouse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"element-6066-11e4-a52e-4f735466cecf\":\"E1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"pointerDown\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"pointerUp\"") != null);
    // no key device: only the pointer had a real action.
    try std.testing.expect(std.mem.indexOf(u8, built, "\"keyboard\"") == null);
}

test "Actions contextClick uses button 2" {
    const a = std.testing.allocator;
    var driver = sel.WebDriver{ .allocator = a, .handle = null };
    var acts = sel.Actions.init(&driver);
    const el = sel.WebElement{ .driver = &driver, .id = @constCast("E1") };
    _ = acts.contextClick(&el);
    const built = try acts.build();
    defer a.free(built);
    acts.deinit();
    try std.testing.expect(std.mem.indexOf(u8, built, "\"button\":2") != null);
}

test "Actions sendKeys builds the key device with down/up per char" {
    const a = std.testing.allocator;
    var driver = sel.WebDriver{ .allocator = a, .handle = null };
    var acts = sel.Actions.init(&driver);
    _ = acts.sendKeys("hi");
    const built = try acts.build();
    defer a.free(built);
    acts.deinit();
    try std.testing.expect(std.mem.indexOf(u8, built, "\"type\":\"key\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"id\":\"keyboard\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"keyDown\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"value\":\"h\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"value\":\"i\"") != null);
    // no pointer device.
    try std.testing.expect(std.mem.indexOf(u8, built, "\"mouse\"") == null);
}

test "Actions mixed devices are length-synced with pauses" {
    const a = std.testing.allocator;
    var driver = sel.WebDriver{ .allocator = a, .handle = null };
    var acts = sel.Actions.init(&driver);
    const el = sel.WebElement{ .driver = &driver, .id = @constCast("E1") };
    _ = acts.click(&el); // 3 pointer ticks
    _ = acts.sendKeys("x"); // +2 key ticks
    const built = try acts.build();
    defer a.free(built);
    acts.deinit();
    // both devices present, and the ticks were length-synced (a pause appears).
    try std.testing.expect(std.mem.indexOf(u8, built, "\"pointer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"key\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, built, "\"type\":\"pause\"") != null);
}

test "Actions only pauses builds no device" {
    const a = std.testing.allocator;
    var driver = sel.WebDriver{ .allocator = a, .handle = null };
    var acts = sel.Actions.init(&driver);
    _ = acts.pauseMs(10);
    const built = try acts.build();
    defer a.free(built);
    acts.deinit();
    try std.testing.expectEqualStrings("[]", built);
}

// ---- Public-surface guard (compile-time) ----
//
// References every public method by address so this test binary fails to
// compile if any of them is removed or renamed — the Zig equivalent of the
// other bindings' reflection-based surface tests. It never runs anything; the
// mere `_ = &Type.method` forces semantic analysis of each declaration.
test "public surface is present (ABI parity with the Rust bar)" {
    // Browser session factories (all seven, incl. per-browser TLS + headless).
    _ = &sel.WebDriver.chrome;
    _ = &sel.WebDriver.chromeTls;
    _ = &sel.WebDriver.headlessChrome;
    _ = &sel.WebDriver.firefox;
    _ = &sel.WebDriver.firefoxTls;
    _ = &sel.WebDriver.headlessFirefox;
    _ = &sel.WebDriver.edge;
    _ = &sel.WebDriver.edgeTls;
    _ = &sel.WebDriver.headlessEdge;
    _ = &sel.WebDriver.safari;
    _ = &sel.WebDriver.safariTls;
    _ = &sel.WebDriver.localChrome;

    // Element discovery: singular + plural, driver- and element-scoped, relative.
    _ = &sel.WebDriver.findElement;
    _ = &sel.WebDriver.findElements;
    _ = &sel.WebDriver.findChildElement;
    _ = &sel.WebDriver.findChildElements;
    _ = &sel.WebDriver.findRelative;
    _ = &sel.WebDriver.findRelativeCount;
    _ = &sel.WebDriver.exists;
    _ = &sel.WebDriver.activeElement;

    // Shadow DOM: getShadowRoot + the ShadowRoot search context.
    _ = &sel.WebDriver.shadowRoot;
    _ = &sel.ShadowRoot.findElement;
    _ = &sel.ShadowRoot.findElements;

    // A representative sweep of the rest of the driver surface so the guard
    // notices wholesale regressions, not only the additions above.
    _ = &sel.WebDriver.get;
    _ = &sel.WebDriver.title;
    _ = &sel.WebDriver.currentUrl;
    _ = &sel.WebDriver.pageSource;
    _ = &sel.WebDriver.back;
    _ = &sel.WebDriver.forward;
    _ = &sel.WebDriver.refresh;
    _ = &sel.WebDriver.executeScript;
    _ = &sel.WebDriver.executeAsyncScript;
    _ = &sel.WebDriver.performActions;
    _ = &sel.WebDriver.clearActions;
    _ = &sel.WebDriver.screenshotBase64;
    _ = &sel.WebDriver.printPdf;
    _ = &sel.WebDriver.addCookie;
    _ = &sel.WebDriver.cookies;
    _ = &sel.WebDriver.deleteAllCookies;
    _ = &sel.WebDriver.windowHandles;
    _ = &sel.WebDriver.newWindow;
    _ = &sel.WebDriver.closeWindow;
    _ = &sel.WebDriver.switchToWindow;
    _ = &sel.WebDriver.switchToFrame;
    _ = &sel.WebDriver.switchToParentFrame;
    _ = &sel.WebDriver.switchToDefaultContent;
    _ = &sel.WebDriver.acceptAlert;
    _ = &sel.WebDriver.dismissAlert;
    _ = &sel.WebDriver.alertText;
    _ = &sel.WebDriver.sendAlertText;
    _ = &sel.WebDriver.alertPresent;
    _ = &sel.WebDriver.setTimeouts;
    _ = &sel.WebDriver.implicitlyWait;
    _ = &sel.WebDriver.bidi;
    _ = &sel.WebDriver.bidiAvailable;
    _ = &sel.BiDi.subscribe;
    _ = &sel.BiDi.unsubscribe;
    _ = &sel.BiDi.nextEvent;
}
