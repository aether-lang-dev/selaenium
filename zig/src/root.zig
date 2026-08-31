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

    // ---- atom-backed commands (run a shared JS atom in-page via the engine) ----
    // Each returns an rc (0 ok, !=0 error like execute); drain via last_value.
    extern "c" fn aether_sel_embed_execute_atom(h: ?*anyopaque, atom: [*c]const u8, elem_id: [*c]const u8, extra_json: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_is_displayed(h: ?*anyopaque, elem_id: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_get_attribute(h: ?*anyopaque, elem_id: [*c]const u8, name: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_atom_str_arg(s: [*c]const u8) [*c]u8;
    extern "c" fn aether_sel_embed_find_relative(h: ?*anyopaque, base_css: [*c]const u8, filters_json: [*c]const u8) c_int;

    // ---- WebDriver-BiDi (over the session's webSocketUrl) ----
    // An opaque BiDi channel handle, independent of the W3C session handle.
    extern "c" fn aether_sel_embed_bidi_open(ws_url: [*c]const u8) ?*anyopaque;
    extern "c" fn aether_sel_embed_bidi_close(h: ?*anyopaque) void;
    extern "c" fn aether_sel_embed_bidi_send(h: ?*anyopaque, id: c_int, method: [*c]const u8, params_json: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_bidi_pump(h: ?*anyopaque, timeout_ms: c_int) c_int;
    extern "c" fn aether_sel_embed_bidi_fd(h: ?*anyopaque) c_int;
    extern "c" fn aether_sel_embed_bidi_poll_reply(h: ?*anyopaque, id: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_poll_event(h: ?*anyopaque) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_lost_events(h: ?*anyopaque) c_int;
    extern "c" fn aether_sel_embed_bidi_cancel(h: ?*anyopaque, id: c_int) void;
    extern "c" fn aether_sel_embed_bidi_subscribe(h: ?*anyopaque, id: c_int, events_csv: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_unsubscribe(h: ?*anyopaque, id: c_int, events_csv: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_wait_event(h: ?*anyopaque, method: [*c]const u8, timeout_ms: c_int) [*c]u8;

    // ---- typed BiDi convenience commands (send + wait for this id's reply) ----
    extern "c" fn aether_sel_embed_bidi_get_tree(h: ?*anyopaque, id: c_int, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_script_evaluate(h: ?*anyopaque, id: c_int, expr: [*c]const u8, context_id: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_navigate(h: ?*anyopaque, id: c_int, context_id: [*c]const u8, url: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_add_intercept(h: ?*anyopaque, id: c_int, phases_csv: [*c]const u8, url_pattern: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_remove_intercept(h: ?*anyopaque, id: c_int, intercept_id: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_continue_request(h: ?*anyopaque, id: c_int, request_id: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_fail_request(h: ?*anyopaque, id: c_int, request_id: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_provide_response(h: ?*anyopaque, id: c_int, request_id: [*c]const u8, status: c_int, content_type: [*c]const u8, body: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_continue_with_auth(h: ?*anyopaque, id: c_int, request_id: [*c]const u8, username: [*c]const u8, password: [*c]const u8, timeout_ms: c_int) [*c]u8;
    extern "c" fn aether_sel_embed_bidi_network_set_cache_behavior(h: ?*anyopaque, id: c_int, behavior: [*c]const u8, timeout_ms: c_int) [*c]u8;
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

/// Pull `capabilities.webSocketUrl` out of a newSession `value` as an owned
/// slice (empty if absent — the remote end granted no BiDi channel).
fn extractWsUrl(allocator: std.mem.Allocator, value: std.json.Value) Error![]u8 {
    switch (value) {
        .object => |o| {
            if (o.get("capabilities")) |caps| switch (caps) {
                .object => |co| {
                    if (co.get("webSocketUrl")) |wu| switch (wu) {
                        .string => |s| return allocator.dupe(u8, s) catch Error.OutOfMemory,
                        else => {},
                    };
                },
                else => {},
            };
        },
        else => {},
    }
    return allocator.dupe(u8, "") catch Error.OutOfMemory;
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
    /// The negotiated BiDi endpoint for this session (owned; "" if none). The
    /// WebSocket is not opened until `bidi` is first called.
    ws_url: []u8 = &.{},
    /// The lazily-opened BiDi channel for this session (opened on first `bidi`).
    bidi_channel: ?BiDi = null,

    pub fn chrome(allocator: std.mem.Allocator, command_executor: []const u8, options_json: []const u8) Error!WebDriver {
        const cu = try cstr(allocator, command_executor);
        defer allocator.free(cu);
        const handle = c.aether_sel_embed_open(cu.ptr);
        if (handle == null) return Error.WebDriver;
        var d = WebDriver{ .allocator = allocator, .handle = handle };
        // Request a BiDi channel so `bidi` is available on demand; the WebSocket
        // itself opens lazily (a classic script never opens it). options_json is
        // a JSON object, so merge `"webSocketUrl":true` by stripping the leading
        // `{`.
        // `tail` is the caps object's body plus its closing brace, e.g.
        // `"browserName":"chrome"}` (empty object -> just `}`).
        const trimmed = std.mem.trim(u8, options_json, " \t\r\n");
        const tail: []const u8 = if (trimmed.len >= 2 and trimmed[0] == '{')
            trimmed[1..]
        else
            "}";
        const sep: []const u8 = if (std.mem.eql(u8, tail, "}")) "" else ",";
        // {"capabilities":{"alwaysMatch":{"webSocketUrl":true[,<caps>]}}}
        const caps = try std.fmt.allocPrint(allocator, "{{\"capabilities\":{{\"alwaysMatch\":{{\"webSocketUrl\":true{s}{s}}}}}", .{ sep, tail });
        defer allocator.free(caps);
        var v = d.execute("newSession", caps) catch |e| {
            c.aether_sel_embed_close(handle);
            d.handle = null;
            if (d.last) |*l| l.deinit(allocator); // free the failure message
            return e;
        };
        // value.capabilities.webSocketUrl — the BiDi endpoint for this session.
        d.ws_url = extractWsUrl(allocator, v.value) catch &.{};
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
        if (self.bidi_channel) |*b| {
            b.close();
            self.bidi_channel = null;
        }
        if (self.handle) |h| {
            c.aether_sel_embed_close(h);
            self.handle = null;
        }
        if (self.last) |*l| l.deinit(self.allocator);
        self.allocator.free(self.ws_url);
        self.ws_url = &.{};
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

    // ---- atom-backed commands (run a shared JS atom in-page via the engine) ----

    /// Drain last_value after an atom call: on rc!=0 record the rich error and
    /// return `error.WebDriver`; otherwise return the parsed value (owned;
    /// `.deinit()`), an empty string parsing as JSON `null`.
    fn atomResult(self: *WebDriver, rc: i32) Error!std.json.Parsed(std.json.Value) {
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

    /// Whether the element is shown (the isDisplayed atom, run in-page by the
    /// engine — the visibility algorithm, not a naive style check).
    pub fn isDisplayed(self: *WebDriver, e: *const WebElement) Error!bool {
        const idc = try cstr(self.allocator, e.id);
        defer self.allocator.free(idc);
        var v = try self.atomResult(@intCast(c.aether_sel_embed_is_displayed(self.handle, idc.ptr)));
        defer v.deinit();
        return switch (v.value) {
            .bool => |b| b,
            else => false,
        };
    }

    /// The classic getAttribute(name): property-or-attribute (boolean attrs,
    /// live properties like value/checked), via the shared engine atom. Returns
    /// the parsed value (owned; `.deinit()`) — a JSON string, or `null` when the
    /// attribute is absent. Use `getDomAttribute` for the raw W3C DOM attribute.
    pub fn getAttribute(self: *WebDriver, e: *const WebElement, name: []const u8) Error!std.json.Parsed(std.json.Value) {
        const idc = try cstr(self.allocator, e.id);
        defer self.allocator.free(idc);
        const nc = try cstr(self.allocator, name);
        defer self.allocator.free(nc);
        return self.atomResult(@intCast(c.aether_sel_embed_get_attribute(self.handle, idc.ptr, nc.ptr)));
    }

    /// The literal DOM attribute (W3C getDomAttribute), no property fallback.
    /// Returns the parsed value (owned; `.deinit()`).
    pub fn getDomAttribute(self: *WebDriver, e: *const WebElement, name: []const u8) Error!std.json.Parsed(std.json.Value) {
        const extra = try std.fmt.allocPrint(self.allocator, ",\"name\":\"{s}\"", .{name});
        defer self.allocator.free(extra);
        return self.elementCmd("getDomAttribute", e.id, extra);
    }

    /// Relative locators: elements matching `base_css` filtered by spatial
    /// relation to anchors, nearest first. `filters_json` is a JSON array of
    /// `{"kind":"above"|"below"|"left"|"right"|"near","sel":"<css>"}`
    /// (`near` also accepts `"dist"`). Returns the parsed array of W3C element
    /// refs (owned; `.deinit()`); iterate its `.array` and read `w3c_element_key`.
    pub fn findRelative(self: *WebDriver, base_css: []const u8, filters_json: []const u8) Error!std.json.Parsed(std.json.Value) {
        const bc = try cstr(self.allocator, base_css);
        defer self.allocator.free(bc);
        const fc = try cstr(self.allocator, filters_json);
        defer self.allocator.free(fc);
        return self.atomResult(@intCast(c.aether_sel_embed_find_relative(self.handle, bc.ptr, fc.ptr)));
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

    /// The async script executor: the page calls the injected callback (last
    /// argument) to complete. Use for anything that must turn the event loop.
    pub fn executeAsyncScript(self: *WebDriver, script: []const u8, args_json: []const u8) Error!std.json.Parsed(std.json.Value) {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"script\":\"{s}\",\"args\":{s}}}", .{ script, args_json });
        defer self.allocator.free(p);
        return self.execute("executeAsyncScript", p);
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

    // ---- WebDriver-BiDi ----

    /// True if this session negotiated a webSocketUrl (BiDi usable).
    pub fn bidiAvailable(self: *WebDriver) bool {
        return self.ws_url.len > 0;
    }

    /// The event-driven BiDi surface for this session, opened lazily over the
    /// negotiated webSocketUrl. Returns `error.WebDriver` if the remote end
    /// granted no BiDi URL or the channel fails to open (read `driver.last`).
    ///
    ///     const bidi = try driver.bidi();
    ///     _ = try bidi.subscribe(&.{BidiEvent.log_entry_added});
    ///     try driver.get(url);
    ///     if (try bidi.nextEvent(BidiEvent.log_entry_added, 5000)) |ev| { ... }
    pub fn bidi(self: *WebDriver) Error!*BiDi {
        if (self.bidi_channel == null) {
            if (self.ws_url.len == 0) {
                self.setLast(0, self.allocator.dupe(u8, "BiDi not available: no webSocketUrl negotiated") catch "");
                return Error.WebDriver;
            }
            const wc = try cstr(self.allocator, self.ws_url);
            defer self.allocator.free(wc);
            const handle = c.aether_sel_embed_bidi_open(wc.ptr);
            if (handle == null) {
                self.setLast(-1, self.allocator.dupe(u8, "BiDi channel failed to open") catch "");
                return Error.WebDriver;
            }
            self.bidi_channel = BiDi{ .allocator = self.allocator, .handle = handle };
        }
        return &self.bidi_channel.?;
    }

    pub fn quit(self: *WebDriver) Error!void {
        if (self.bidi_channel) |*b| {
            b.close();
            self.bidi_channel = null;
        }
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

/// The common WebDriver-BiDi event names (W3C spec). Pass to
/// `bidi.subscribe(...)` and match in `nextEvent(...)`.
pub const BidiEvent = struct {
    pub const log_entry_added = "log.entryAdded";
    pub const context_created = "browsingContext.contextCreated";
    pub const context_destroyed = "browsingContext.contextDestroyed";
    pub const navigation_started = "browsingContext.navigationStarted";
    pub const dom_content_loaded = "browsingContext.domContentLoaded";
    pub const load = "browsingContext.load";
    pub const download_will_begin = "browsingContext.downloadWillBegin";
    pub const before_request_sent = "network.beforeRequestSent";
    pub const auth_required = "network.authRequired";
    pub const response_started = "network.responseStarted";
    pub const response_completed = "network.responseCompleted";
    pub const fetch_error = "network.fetchError";
    pub const realm_created = "script.realmCreated";
    pub const realm_destroyed = "script.realmDestroyed";
    pub const message = "script.message";
};

/// The event-driven BiDi channel for a session (over the demux C ABI).
///
/// Commands and events multiplex over one WebSocket via the engine's shape-C
/// demux (a single reader routes replies to an id table and events to a bounded
/// queue), so replies stay correlated while events stream. Command ids are
/// supplied automatically from a per-channel monotonic counter (from 1).
///
/// Every parsed reply/event/ack is owned (`std.json.Parsed`; call `.deinit()`).
pub const BiDi = struct {
    allocator: std.mem.Allocator,
    handle: ?*anyopaque,
    next_id: c_int = 1,

    fn takeId(self: *BiDi) c_int {
        const i = self.next_id;
        self.next_id += 1;
        return i;
    }

    /// Parse an owned ABI string into JSON, or `null` for an empty string.
    fn parseOwned(self: *BiDi, ptr: [*c]u8) Error!?std.json.Parsed(std.json.Value) {
        const raw = try takeString(self.allocator, ptr);
        defer self.allocator.free(raw);
        if (raw.len == 0) return null;
        return std.json.parseFromSlice(std.json.Value, self.allocator, raw, .{}) catch Error.BadResponse;
    }

    /// session.subscribe to one or more event names; wait for the ack. Returns
    /// the parsed ack (owned; `.deinit()`), or `null` if none. Matching events
    /// then arrive on the queue (drain via `nextEvent`).
    pub fn subscribe(self: *BiDi, events: []const []const u8, timeout_ms: c_int) Error!?std.json.Parsed(std.json.Value) {
        const csv = try joinCsv(self.allocator, events);
        defer self.allocator.free(csv);
        const cc = try cstr(self.allocator, csv);
        defer self.allocator.free(cc);
        return self.parseOwned(c.aether_sel_embed_bidi_subscribe(self.handle, self.takeId(), cc.ptr, timeout_ms));
    }

    pub fn unsubscribe(self: *BiDi, events: []const []const u8, timeout_ms: c_int) Error!?std.json.Parsed(std.json.Value) {
        const csv = try joinCsv(self.allocator, events);
        defer self.allocator.free(csv);
        const cc = try cstr(self.allocator, csv);
        defer self.allocator.free(cc);
        return self.parseOwned(c.aether_sel_embed_bidi_unsubscribe(self.handle, self.takeId(), cc.ptr, timeout_ms));
    }

    /// Block until an event whose `method` matches arrives, or timeout. Returns
    /// the parsed event (owned; `.deinit()`), or `null` on timeout/close.
    /// (Subscribe first.)
    pub fn nextEvent(self: *BiDi, method: []const u8, timeout_ms: c_int) Error!?std.json.Parsed(std.json.Value) {
        const mc = try cstr(self.allocator, method);
        defer self.allocator.free(mc);
        return self.parseOwned(c.aether_sel_embed_bidi_wait_event(self.handle, mc.ptr, timeout_ms));
    }

    /// Issue any BiDi command and return its parsed reply (owned; `.deinit()`).
    /// Reaches BiDi methods with no dedicated wrapper (script.evaluate,
    /// network.*, ...). Sends then pumps until this id's reply arrives.
    pub fn command(self: *BiDi, method: []const u8, params_json: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const mc = try cstr(self.allocator, method);
        defer self.allocator.free(mc);
        const pc = try cstr(self.allocator, params_json);
        defer self.allocator.free(pc);
        const cid = self.takeId();
        if (c.aether_sel_embed_bidi_send(self.handle, cid, mc.ptr, pc.ptr) != 0) {
            return Error.WebDriver;
        }
        var waited: c_int = 0;
        const step: c_int = 50;
        while (waited < timeout_ms) {
            if (try self.parseOwned(c.aether_sel_embed_bidi_poll_reply(self.handle, cid))) |reply| {
                return reply;
            }
            if (c.aether_sel_embed_bidi_pump(self.handle, step) < 0) break;
            waited += step;
        }
        return Error.WebDriver;
    }

    // ---- typed convenience commands ----

    /// browsingContext.getTree — the browsing contexts (each with a "context"
    /// id). Returns the parsed reply (owned; `.deinit()`).
    pub fn getTree(self: *BiDi, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        return (try self.parseOwned(c.aether_sel_embed_bidi_get_tree(self.handle, self.takeId(), timeout_ms))) orelse Error.BadResponse;
    }

    /// The top-level browsing context id (the anchor for evaluate/navigate), as
    /// an owned slice the caller frees. `error.BadResponse` if the tree carries
    /// no context.
    pub fn topContext(self: *BiDi, timeout_ms: c_int) Error![]u8 {
        var tree = try self.getTree(timeout_ms);
        defer tree.deinit();
        // reply.result.contexts[0].context
        const result = switch (tree.value) {
            .object => |o| o.get("result") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        const contexts = switch (result) {
            .object => |o| o.get("contexts") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        const arr = switch (contexts) {
            .array => |a| a,
            else => return Error.BadResponse,
        };
        if (arr.items.len == 0) return Error.BadResponse;
        const ctx = switch (arr.items[0]) {
            .object => |o| o.get("context") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        return switch (ctx) {
            .string => |s| self.allocator.dupe(u8, s) catch Error.OutOfMemory,
            else => Error.BadResponse,
        };
    }

    /// script.evaluate an expression in a context's realm, awaiting a returned
    /// promise. Returns the parsed reply (owned; `.deinit()`);
    /// `["result"]["result"]` is the BiDi-typed value (e.g.
    /// `{"type":"number","value":42}`). BiDi's richer alternative to
    /// executeScript — real realms, promise-awaiting, structured value types.
    /// `context` empty means "resolve the top-level context first".
    pub fn evaluate(self: *BiDi, expression: []const u8, context: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        var owned_ctx: ?[]u8 = null;
        defer if (owned_ctx) |oc| self.allocator.free(oc);
        const ctx: []const u8 = if (context.len > 0) context else blk: {
            owned_ctx = try self.topContext(timeout_ms);
            break :blk owned_ctx.?;
        };
        const ec = try cstr(self.allocator, expression);
        defer self.allocator.free(ec);
        const cc = try cstr(self.allocator, ctx);
        defer self.allocator.free(cc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_script_evaluate(self.handle, self.takeId(), ec.ptr, cc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// script.evaluate, returning just the unwrapped numeric value (the `.value`
    /// of the BiDi-typed result, read as f64). `error.BadResponse` if the result
    /// is not a simple number.
    pub fn evaluateValue(self: *BiDi, expression: []const u8, context: []const u8, timeout_ms: c_int) Error!f64 {
        var reply = try self.evaluate(expression, context, timeout_ms);
        defer reply.deinit();
        const result = switch (reply.value) {
            .object => |o| o.get("result") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        const inner = switch (result) {
            .object => |o| o.get("result") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        const value = switch (inner) {
            .object => |o| o.get("value") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => Error.BadResponse,
        };
    }

    /// browsingContext.navigate a context to `url` (wait: complete). `context`
    /// empty means "resolve the top-level context first". Returns the parsed
    /// reply (owned; `.deinit()`).
    pub fn navigate(self: *BiDi, url: []const u8, context: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        var owned_ctx: ?[]u8 = null;
        defer if (owned_ctx) |oc| self.allocator.free(oc);
        const ctx: []const u8 = if (context.len > 0) context else blk: {
            owned_ctx = try self.topContext(timeout_ms);
            break :blk owned_ctx.?;
        };
        const cc = try cstr(self.allocator, ctx);
        defer self.allocator.free(cc);
        const uc = try cstr(self.allocator, url);
        defer self.allocator.free(uc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_navigate(self.handle, self.takeId(), cc.ptr, uc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    // ---- network interception ----

    /// network.addIntercept for a URL pattern (a full parseable URL as a "string"
    /// pattern; empty intercepts all) at the given comma-separated phases (e.g.
    /// "beforeRequestSent"). Returns the intercept id as an owned slice the caller
    /// frees. `error.BadResponse` if the reply carries no intercept id.
    pub fn addIntercept(self: *BiDi, phases_csv: []const u8, url_pattern: []const u8, timeout_ms: c_int) Error![]u8 {
        const pc = try cstr(self.allocator, phases_csv);
        defer self.allocator.free(pc);
        const uc = try cstr(self.allocator, url_pattern);
        defer self.allocator.free(uc);
        var reply = (try self.parseOwned(c.aether_sel_embed_bidi_network_add_intercept(self.handle, self.takeId(), pc.ptr, uc.ptr, timeout_ms))) orelse return Error.BadResponse;
        defer reply.deinit();
        const result = switch (reply.value) {
            .object => |o| o.get("result") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        const iv = switch (result) {
            .object => |o| o.get("intercept") orelse return Error.BadResponse,
            else => return Error.BadResponse,
        };
        return switch (iv) {
            .string => |s| self.allocator.dupe(u8, s) catch Error.OutOfMemory,
            else => Error.BadResponse,
        };
    }

    /// network.removeIntercept. Returns the parsed reply (owned; `.deinit()`).
    pub fn removeIntercept(self: *BiDi, intercept_id: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const ic = try cstr(self.allocator, intercept_id);
        defer self.allocator.free(ic);
        return (try self.parseOwned(c.aether_sel_embed_bidi_network_remove_intercept(self.handle, self.takeId(), ic.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// network.continueRequest — let a paused request proceed unchanged.
    pub fn continueRequest(self: *BiDi, request_id: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const rc = try cstr(self.allocator, request_id);
        defer self.allocator.free(rc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_network_continue_request(self.handle, self.takeId(), rc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// network.failRequest — block a paused request.
    pub fn failRequest(self: *BiDi, request_id: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const rc = try cstr(self.allocator, request_id);
        defer self.allocator.free(rc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_network_fail_request(self.handle, self.takeId(), rc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// network.provideResponse — fulfill a paused request with a MOCK response
    /// (never hits the network). The engine adds Access-Control-Allow-Origin:* so
    /// the requesting page can read a cross-origin mocked body.
    pub fn provideResponse(self: *BiDi, request_id: []const u8, status: c_int, content_type: []const u8, body: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const rc = try cstr(self.allocator, request_id);
        defer self.allocator.free(rc);
        const ctc = try cstr(self.allocator, content_type);
        defer self.allocator.free(ctc);
        const bc = try cstr(self.allocator, body);
        defer self.allocator.free(bc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_network_provide_response(self.handle, self.takeId(), rc.ptr, status, ctc.ptr, bc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// network.continueWithAuth — answer a paused authRequired with credentials
    /// (action: provideCredentials). Returns the parsed reply (owned; `.deinit()`).
    pub fn continueWithAuth(self: *BiDi, request_id: []const u8, username: []const u8, password: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const rc = try cstr(self.allocator, request_id);
        defer self.allocator.free(rc);
        const uc = try cstr(self.allocator, username);
        defer self.allocator.free(uc);
        const pc = try cstr(self.allocator, password);
        defer self.allocator.free(pc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_network_continue_with_auth(self.handle, self.takeId(), rc.ptr, uc.ptr, pc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// network.setCacheBehavior — "bypass" disables the session HTTP cache (every
    /// request hits the network / an intercept), "default" restores it. Returns
    /// the parsed reply (owned; `.deinit()`).
    pub fn setCacheBehavior(self: *BiDi, behavior: []const u8, timeout_ms: c_int) Error!std.json.Parsed(std.json.Value) {
        const bc = try cstr(self.allocator, behavior);
        defer self.allocator.free(bc);
        return (try self.parseOwned(c.aether_sel_embed_bidi_network_set_cache_behavior(self.handle, self.takeId(), bc.ptr, timeout_ms))) orelse Error.BadResponse;
    }

    /// The network.request id out of a network.beforeRequestSent (or other
    /// network) event: `params.request.request`, as an owned slice. `null` if
    /// absent.
    pub fn eventRequestId(allocator: std.mem.Allocator, event: std.json.Value) Error!?[]u8 {
        const params = switch (event) {
            .object => |o| o.get("params") orelse return null,
            else => return null,
        };
        const request = switch (params) {
            .object => |o| o.get("request") orelse return null,
            else => return null,
        };
        const rid = switch (request) {
            .object => |o| o.get("request") orelse return null,
            else => return null,
        };
        return switch (rid) {
            .string => |s| allocator.dupe(u8, s) catch Error.OutOfMemory,
            else => null,
        };
    }

    /// How many events the bounded queue has dropped since the last call (then
    /// resets) — so a consumer knows it missed events.
    pub fn lostEvents(self: *BiDi) i32 {
        return @intCast(c.aether_sel_embed_bidi_lost_events(self.handle));
    }

    pub fn close(self: *BiDi) void {
        if (self.handle) |h| {
            c.aether_sel_embed_bidi_close(h);
            self.handle = null;
        }
    }
};

/// Join event names with commas into an owned slice (`bidi_*` events_csv arg).
fn joinCsv(allocator: std.mem.Allocator, events: []const []const u8) Error![]u8 {
    return std.mem.join(allocator, ",", events) catch Error.OutOfMemory;
}

test {
    _ = @import("ffi_test.zig");
}
