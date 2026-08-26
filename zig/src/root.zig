//! selenium_core — the Zig binding over the shared pure-Aether WebDriver core.
//!
//! No protocol logic lives here. The W3C command map, routing, By
//! normalization, error decode and the HTTP round-trip all live in
//! `core/selenium_core.ae`; the C ABI is `core/embed.ae`, whose exports
//! `--emit=lib` mangles to `aether_sel_embed_<name>`. This is pure marshalling.
//!
//! Like Go/cgo and Nim, this binding LINKS the engine (see build.zig) rather
//! than dlopen'ing it, so `libselenium_core.so` must exist at BUILD time.
//!
//! Ownership: every `[*c]u8` this ABI returns is caller-owned; it goes through
//! exactly one helper, `takeString`, which copies into a caller-owned Zig slice
//! and frees the original via `aether_sel_embed_free_string`.

const std = @import("std");

const c = struct {
    extern "c" fn aether_sel_embed_open(base_url: [*c]const u8) ?*anyopaque;
    extern "c" fn aether_sel_embed_close(h: ?*anyopaque) void;
    extern "c" fn aether_sel_embed_execute(h: ?*anyopaque, name: [*c]const u8, params_json: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_last_value(h: ?*anyopaque) [*c]u8;
    extern "c" fn aether_sel_embed_last_status(h: ?*anyopaque) c_int;
    extern "c" fn aether_sel_embed_last_error_code(h: ?*anyopaque) c_int;
    extern "c" fn aether_sel_embed_last_error(h: ?*anyopaque) [*c]u8;
    extern "c" fn aether_sel_embed_session_id(h: ?*anyopaque) [*c]u8;
    extern "c" fn aether_sel_embed_by_locator(strategy: [*c]const u8, value: [*c]const u8) [*c]u8;
    extern "c" fn aether_sel_embed_route(name: [*c]const u8) [*c]u8;
    extern "c" fn aether_sel_embed_error_code(w3c_error: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_free_string(s: [*c]u8) void;
};

pub const w3c_element_key = "element-6066-11e4-a52e-4f735466cecf";

/// Locator strategies (engine strategy strings; id/name/class rewrite to CSS).
pub const By = struct {
    pub const id = "id";
    pub const name = "name";
    pub const css = "css selector";
    pub const class_name = "className";
    pub const tag_name = "tag name";
    pub const link_text = "link text";
    pub const partial_link_text = "partial link text";
    pub const xpath = "xpath";
};

pub const ErrorKind = enum {
    transport,
    no_such_element,
    stale_element_reference,
    element_click_intercepted,
    element_not_interactable,
    invalid_selector,
    timeout,
    javascript,
    unknown_command,
    other,
};

/// A protocol error: the engine's W3C code (0 success, -1 transport), a kind,
/// and an owned message. Free with `deinit`.
pub const WebDriverError = struct {
    code: i32,
    kind: ErrorKind,
    message: []u8,

    pub fn deinit(self: *WebDriverError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

/// Anything a command can fail with. The rich `WebDriverError` is carried out
/// of band on the WebDriver (see `last_error`) because Zig error sets are
/// enums, not payloads.
pub const Error = error{ WebDriver, OutOfMemory, BadResponse };

fn classifyKind(code: i32) ErrorKind {
    return switch (code) {
        -1 => .transport,
        3 => .element_click_intercepted,
        4 => .element_not_interactable,
        11 => .invalid_selector,
        13 => .javascript,
        17 => .no_such_element,
        21, 24 => .timeout,
        23 => .stale_element_reference,
        28 => .unknown_command,
        else => .other,
    };
}

/// Copy an ABI-returned string into an owned slice and free the original.
fn takeString(allocator: std.mem.Allocator, ptr: [*c]u8) Error![]u8 {
    if (ptr == null) return allocator.dupe(u8, "") catch return Error.OutOfMemory;
    defer c.aether_sel_embed_free_string(ptr);
    const slice = std.mem.span(@as([*:0]u8, @ptrCast(ptr)));
    return allocator.dupe(u8, slice) catch Error.OutOfMemory;
}

/// NUL-terminate a slice into a caller buffer for a C `const char*`. Falls back
/// to a heap allocation for long strings (JSON params).
fn cstr(allocator: std.mem.Allocator, s: []const u8) Error![:0]u8 {
    return allocator.dupeZ(u8, s) catch Error.OutOfMemory;
}

// ---- pure engine helpers (caller owns the returned slice) ----

pub fn route(allocator: std.mem.Allocator, command: []const u8) Error![]u8 {
    const cc = try cstr(allocator, command);
    defer allocator.free(cc);
    return takeString(allocator, c.aether_sel_embed_route(cc.ptr));
}

pub fn errorCode(allocator: std.mem.Allocator, w3c_error: []const u8) Error!i32 {
    const cc = try cstr(allocator, w3c_error);
    defer allocator.free(cc);
    return @intCast(c.aether_sel_embed_error_code(cc.ptr));
}

pub fn locator(allocator: std.mem.Allocator, by: []const u8, value: []const u8) Error![]u8 {
    const bc = try cstr(allocator, by);
    defer allocator.free(bc);
    const vc = try cstr(allocator, value);
    defer allocator.free(vc);
    return takeString(allocator, c.aether_sel_embed_by_locator(bc.ptr, vc.ptr));
}

// ---- WebDriver ----

pub const WebElement = struct {
    driver: *WebDriver,
    id: []u8, // owned

    pub fn deinit(self: *WebElement) void {
        self.driver.allocator.free(self.id);
    }
};

pub const WebDriver = struct {
    allocator: std.mem.Allocator,
    handle: ?*anyopaque,
    /// The rich error from the most recent failing command (owned; replaced
    /// each failure). Read after a command returns `error.WebDriver`.
    last: ?WebDriverError = null,

    pub fn chrome(allocator: std.mem.Allocator, command_executor: []const u8, options_json: []const u8) Error!WebDriver {
        const cu = try cstr(allocator, command_executor);
        defer allocator.free(cu);
        const handle = c.aether_sel_embed_open(cu.ptr);
        if (handle == null) return Error.WebDriver;
        var d = WebDriver{ .allocator = allocator, .handle = handle };
        // {"capabilities":{"alwaysMatch":<merged caps>}}
        const caps = try std.fmt.allocPrint(allocator,
            "{{\"capabilities\":{{\"alwaysMatch\":{s}}}}}", .{options_json});
        defer allocator.free(caps);
        var v = d.execute("newSession", caps) catch |e| {
            c.aether_sel_embed_close(handle);
            d.handle = null;
            if (d.last) |*l| l.deinit(allocator); // free the failure message
            return e;
        };
        v.deinit();
        return d;
    }

    pub fn headlessChrome(allocator: std.mem.Allocator, command_executor: []const u8) Error!WebDriver {
        const caps =
            \\{"browserName":"chrome","goog:chromeOptions":{"args":["--headless=new","--no-sandbox","--disable-gpu","--disable-dev-shm-usage"]}}
        ;
        return chrome(allocator, command_executor, caps);
    }

    pub fn deinit(self: *WebDriver) void {
        if (self.handle) |h| {
            c.aether_sel_embed_close(h);
            self.handle = null;
        }
        if (self.last) |*l| l.deinit(self.allocator);
    }

    fn setLast(self: *WebDriver, code: i32, message: []u8) void {
        if (self.last) |*l| l.deinit(self.allocator);
        self.last = .{ .code = code, .kind = classifyKind(code), .message = message };
    }

    /// Execute a command by name with a JSON-object params string. Returns the
    /// parsed response `value` (owned; call `.deinit()`), or `error.WebDriver`
    /// (read `driver.last`).
    pub fn execute(self: *WebDriver, command: []const u8, params_json: []const u8) Error!std.json.Parsed(std.json.Value) {
        const cn = try cstr(self.allocator, command);
        defer self.allocator.free(cn);
        const cp = try cstr(self.allocator, params_json);
        defer self.allocator.free(cp);
        const rc: i32 = @intCast(c.aether_sel_embed_execute(self.handle, cn.ptr, cp.ptr));
        if (rc != 0) {
            const code: i32 = @intCast(c.aether_sel_embed_last_error_code(self.handle));
            const msg = try takeString(self.allocator, c.aether_sel_embed_last_error(self.handle));
            if (rc == -1 and code == 0) {
                self.setLast(-1, msg);
            } else {
                self.setLast(code, msg);
            }
            return Error.WebDriver;
        }
        const raw = try takeString(self.allocator, c.aether_sel_embed_last_value(self.handle));
        defer self.allocator.free(raw);
        const body = if (raw.len == 0) "null" else raw;
        return std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch Error.BadResponse;
    }

    // ---- navigation ----
    pub fn get(self: *WebDriver, url: []const u8) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"url\":\"{s}\"}}", .{url});
        defer self.allocator.free(p);
        var v = try self.execute("get", p);
        v.deinit();
    }

    /// Title as an owned slice.
    pub fn title(self: *WebDriver) Error![]u8 {
        return self.stringCmd("getTitle", "{}");
    }

    pub fn back(self: *WebDriver) Error!void {
        var v = try self.execute("goBack", "{}");
        v.deinit();
    }
    pub fn forward(self: *WebDriver) Error!void {
        var v = try self.execute("goForward", "{}");
        v.deinit();
    }

    fn stringCmd(self: *WebDriver, command: []const u8, params: []const u8) Error![]u8 {
        var v = try self.execute(command, params);
        defer v.deinit();
        const s = switch (v.value) {
            .string => |x| x,
            else => "",
        };
        return self.allocator.dupe(u8, s) catch Error.OutOfMemory;
    }

    // ---- elements ----
    pub fn findElement(self: *WebDriver, by: []const u8, value: []const u8) Error!WebElement {
        const loc = try locator(self.allocator, by, value);
        defer self.allocator.free(loc);
        var v = try self.execute("findElement", loc);
        defer v.deinit();
        const id = self.extractElementId(v.value) catch return Error.WebDriver;
        return WebElement{ .driver = self, .id = id };
    }

    fn extractElementId(self: *WebDriver, value: std.json.Value) Error![]u8 {
        switch (value) {
            .object => |o| {
                if (o.get(w3c_element_key)) |idv| {
                    switch (idv) {
                        .string => |s| return self.allocator.dupe(u8, s) catch Error.OutOfMemory,
                        else => {},
                    }
                }
            },
            else => {},
        }
        self.setLast(17, self.allocator.dupe(u8, "element reference key missing") catch "");
        return Error.WebDriver;
    }

    /// Element command with an `{"id":...}` (plus optional extra) body.
    fn elementCmd(self: *WebDriver, command: []const u8, element_id: []const u8, extra_json: []const u8) Error!std.json.Parsed(std.json.Value) {
        // extra_json is the inner object fields, e.g. `,"name":"x"` or "".
        const p = try std.fmt.allocPrint(self.allocator, "{{\"id\":\"{s}\"{s}}}", .{ element_id, extra_json });
        defer self.allocator.free(p);
        return self.execute(command, p);
    }

    pub fn elementClick(self: *WebDriver, e: *const WebElement) Error!void {
        var v = try self.elementCmd("clickElement", e.id, "");
        v.deinit();
    }

    pub fn elementText(self: *WebDriver, e: *const WebElement) Error![]u8 {
        var v = try self.elementCmd("getElementText", e.id, "");
        defer v.deinit();
        const s = switch (v.value) {
            .string => |x| x,
            else => "",
        };
        return self.allocator.dupe(u8, s) catch Error.OutOfMemory;
    }

    pub fn elementTagName(self: *WebDriver, e: *const WebElement) Error![]u8 {
        var v = try self.elementCmd("getElementTagName", e.id, "");
        defer v.deinit();
        const s = switch (v.value) {
            .string => |x| x,
            else => "",
        };
        return self.allocator.dupe(u8, s) catch Error.OutOfMemory;
    }

    /// Element rect ({x,y,width,height}); returns the parsed value (owned).
    pub fn elementRect(self: *WebDriver, e: *const WebElement) Error!std.json.Parsed(std.json.Value) {
        return self.elementCmd("getElementRect", e.id, "");
    }

    // ---- cookies ----
    pub fn deleteAllCookies(self: *WebDriver) Error!void {
        var v = try self.execute("deleteAllCookies", "{}");
        v.deinit();
    }
    pub fn addCookie(self: *WebDriver, cookie_json: []const u8) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"cookie\":{s}}}", .{cookie_json});
        defer self.allocator.free(p);
        var v = try self.execute("addCookie", p);
        v.deinit();
    }
    pub fn cookie(self: *WebDriver, name: []const u8) Error!std.json.Parsed(std.json.Value) {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"name\":\"{s}\"}}", .{name});
        defer self.allocator.free(p);
        return self.execute("getCookie", p);
    }

    // ---- windows ----
    pub fn windowHandlesCount(self: *WebDriver) Error!usize {
        var v = try self.execute("getWindowHandles", "{}");
        defer v.deinit();
        return switch (v.value) {
            .array => |a| a.items.len,
            else => 0,
        };
    }
    pub fn setWindowRect(self: *WebDriver, rect_json: []const u8) Error!void {
        var v = try self.execute("setWindowRect", rect_json);
        v.deinit();
    }

    // ---- script ----
    pub fn executeScript(self: *WebDriver, script: []const u8, args_json: []const u8) Error!std.json.Parsed(std.json.Value) {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"script\":\"{s}\",\"args\":{s}}}", .{ script, args_json });
        defer self.allocator.free(p);
        return self.execute("executeScript", p);
    }

    // ---- actions ----
    pub fn performActions(self: *WebDriver, actions_json: []const u8) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"actions\":{s}}}", .{actions_json});
        defer self.allocator.free(p);
        var v = try self.execute("actions", p);
        v.deinit();
    }
    pub fn clearActions(self: *WebDriver) Error!void {
        var v = try self.execute("clearActions", "{}");
        v.deinit();
    }

    // ---- screenshots ----
    pub fn screenshotBase64(self: *WebDriver) Error![]u8 {
        return self.stringCmd("screenshot", "{}");
    }

    // ---- lifecycle ----
    pub fn sessionId(self: *WebDriver) Error![]u8 {
        return takeString(self.allocator, c.aether_sel_embed_session_id(self.handle));
    }

    pub fn quit(self: *WebDriver) Error!void {
        var v = self.execute("quit", "{}") catch |e| {
            if (self.handle) |h| {
                c.aether_sel_embed_close(h);
                self.handle = null;
            }
            return e;
        };
        v.deinit();
        if (self.handle) |h| {
            c.aether_sel_embed_close(h);
            self.handle = null;
        }
    }
};

test {
    _ = @import("ffi_test.zig");
}
