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
    extern "c" fn aether_sel_embed_build_request(name: [*c]const u8, session_id: [*c]const u8, params_json: [*c]const u8) [*c]u8;
    extern "c" fn aether_sel_embed_error_code(w3c_error: [*c]const u8) c_int;
    extern "c" fn aether_sel_embed_free_string(s: [*c]u8) void;

    // ---- TLS config (per session handle; set before newSession) ----
    extern "c" fn aether_sel_embed_set_ca(h: ?*anyopaque, ca_path: [*c]const u8) void;
    extern "c" fn aether_sel_embed_set_insecure(h: ?*anyopaque, on: c_int) void;

    // ---- driver orchestration (spawn/adopt a driver process in-binding) ----
    // An opaque driver handle, independent of the W3C session handle.
    extern "c" fn aether_sel_embed_resolve_driver(browser: [*c]const u8, hint: [*c]const u8) [*c]u8;
    extern "c" fn aether_sel_embed_launch_driver(driver_path: [*c]const u8, timeout_ms: c_int) ?*anyopaque;
    extern "c" fn aether_sel_embed_ensure_driver(browser: [*c]const u8, hint: [*c]const u8, timeout_ms: c_int) ?*anyopaque;
    extern "c" fn aether_sel_embed_driver_url(dh: ?*anyopaque) [*c]u8;
    extern "c" fn aether_sel_embed_driver_pid(dh: ?*anyopaque) c_int;
    extern "c" fn aether_sel_embed_stop_driver(dh: ?*anyopaque) void;

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

/// A locator: a (strategy, value) pair produced by the `By` factory and passed
/// to `findElement`/`findElements` (Selenium 4.x's one-arg locator shape).
pub const Locator = struct {
    using: []const u8,
    value: []const u8,
};

/// Locator strategies as factory functions (Selenium 4.x `By.id("x")` shape).
/// Each returns a `Locator`; the engine rewrites id/name/class name to CSS.
pub const By = struct {
    pub fn id(value: []const u8) Locator {
        return .{ .using = "id", .value = value };
    }
    pub fn name(value: []const u8) Locator {
        return .{ .using = "name", .value = value };
    }
    pub fn cssSelector(value: []const u8) Locator {
        return .{ .using = "css selector", .value = value };
    }
    pub fn className(value: []const u8) Locator {
        return .{ .using = "class name", .value = value };
    }
    pub fn tagName(value: []const u8) Locator {
        return .{ .using = "tag name", .value = value };
    }
    pub fn linkText(value: []const u8) Locator {
        return .{ .using = "link text", .value = value };
    }
    pub fn partialLinkText(value: []const u8) Locator {
        return .{ .using = "partial link text", .value = value };
    }
    pub fn xpath(value: []const u8) Locator {
        return .{ .using = "xpath", .value = value };
    }
};

/// Special keys — the W3C WebDriver Unicode private-use code points for non-text
/// keys (W3C §17.4.2). Each constant is the UTF-8 encoding of a scalar in
/// U+E000..=U+E03D. Embed one in a `sendKeys` string, or build a modifier chord
/// with `Keys.chord`. Mirrors mainstream Selenium's `Keys`.
pub const Keys = struct {
    pub const null_key = "\u{E000}";
    pub const cancel = "\u{E001}";
    pub const help = "\u{E002}";
    pub const backspace = "\u{E003}";
    pub const tab = "\u{E004}";
    pub const clear = "\u{E005}";
    pub const @"return" = "\u{E006}";
    pub const enter = "\u{E007}";
    pub const shift = "\u{E008}";
    pub const control = "\u{E009}";
    pub const alt = "\u{E00A}";
    pub const pause = "\u{E00B}";
    pub const escape = "\u{E00C}";
    pub const space = "\u{E00D}";
    pub const page_up = "\u{E00E}";
    pub const page_down = "\u{E00F}";
    pub const end = "\u{E010}";
    pub const home = "\u{E011}";
    pub const left = "\u{E012}";
    pub const up = "\u{E013}";
    pub const right = "\u{E014}";
    pub const down = "\u{E015}";
    pub const insert = "\u{E016}";
    pub const delete = "\u{E017}";
    pub const semicolon = "\u{E018}";
    pub const equals = "\u{E019}";
    pub const numpad0 = "\u{E01A}";
    pub const numpad1 = "\u{E01B}";
    pub const numpad2 = "\u{E01C}";
    pub const numpad3 = "\u{E01D}";
    pub const numpad4 = "\u{E01E}";
    pub const numpad5 = "\u{E01F}";
    pub const numpad6 = "\u{E020}";
    pub const numpad7 = "\u{E021}";
    pub const numpad8 = "\u{E022}";
    pub const numpad9 = "\u{E023}";
    pub const multiply = "\u{E024}";
    pub const add = "\u{E025}";
    pub const separator = "\u{E026}";
    pub const subtract = "\u{E027}";
    pub const decimal = "\u{E028}";
    pub const divide = "\u{E029}";
    pub const f1 = "\u{E031}";
    pub const f2 = "\u{E032}";
    pub const f3 = "\u{E033}";
    pub const f4 = "\u{E034}";
    pub const f5 = "\u{E035}";
    pub const f6 = "\u{E036}";
    pub const f7 = "\u{E037}";
    pub const f8 = "\u{E038}";
    pub const f9 = "\u{E039}";
    pub const f10 = "\u{E03A}";
    pub const f11 = "\u{E03B}";
    pub const f12 = "\u{E03C}";
    pub const meta = "\u{E03D}";
    pub const command = "\u{E03D}";

    /// A modifier chord: `modifier` held while `text` is typed, then closed by
    /// the terminating NULL the protocol uses to release held modifiers — e.g.
    /// `Keys.chord(a, Keys.control, "a")` for select-all. Returns an owned slice
    /// (the caller frees). The classic `Keys.chord` helper.
    pub fn chord(allocator: std.mem.Allocator, modifier: []const u8, text: []const u8) Error![]u8 {
        return std.mem.concat(allocator, u8, &.{ modifier, text, null_key }) catch Error.OutOfMemory;
    }
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

/// Append `s` to `buf` as a JSON string literal (with surrounding quotes),
/// escaping the characters JSON requires. Used to build params where a value
/// may contain quotes, backslashes, or control chars (e.g. sendKeys text).
fn appendJsonString(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) Error!void {
    buf.append(allocator, '"') catch return Error.OutOfMemory;
    for (s) |ch| {
        switch (ch) {
            '"' => buf.appendSlice(allocator, "\\\"") catch return Error.OutOfMemory,
            '\\' => buf.appendSlice(allocator, "\\\\") catch return Error.OutOfMemory,
            '\n' => buf.appendSlice(allocator, "\\n") catch return Error.OutOfMemory,
            '\r' => buf.appendSlice(allocator, "\\r") catch return Error.OutOfMemory,
            '\t' => buf.appendSlice(allocator, "\\t") catch return Error.OutOfMemory,
            0x08 => buf.appendSlice(allocator, "\\b") catch return Error.OutOfMemory,
            0x0C => buf.appendSlice(allocator, "\\f") catch return Error.OutOfMemory,
            0...0x07, 0x0B, 0x0E...0x1F => {
                var tmp: [6]u8 = undefined;
                const esc = std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{ch}) catch return Error.OutOfMemory;
                buf.appendSlice(allocator, esc) catch return Error.OutOfMemory;
            },
            else => buf.append(allocator, ch) catch return Error.OutOfMemory,
        }
    }
    buf.append(allocator, '"') catch return Error.OutOfMemory;
}

/// A JSON-string-literal of `s` as an owned slice (quotes included, escaped).
fn jsonString(allocator: std.mem.Allocator, s: []const u8) Error![]u8 {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    try appendJsonString(allocator, &buf, s);
    return buf.toOwnedSlice(allocator) catch Error.OutOfMemory;
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

// ---- driver orchestration (spawn/adopt a driver process in-binding) ---------
// The engine can resolve, download-or-cache, and launch a browser driver itself,
// so a caller needs neither a driver on PATH nor a running Grid.

/// Resolve the local driver binary path for `browser` without launching it
/// (detect/download/cache as needed). `hint` pins a version/path; "" auto-
/// detects. Returns "" (owned, empty) if none resolvable (offline, no cache).
pub fn resolveDriver(allocator: std.mem.Allocator, browser: []const u8, hint: []const u8) Error![]u8 {
    const bc = try cstr(allocator, browser);
    defer allocator.free(bc);
    const hc = try cstr(allocator, hint);
    defer allocator.free(hc);
    return takeString(allocator, c.aether_sel_embed_resolve_driver(bc.ptr, hc.ptr));
}

/// A driver process launched by the engine. Owns the opaque driver handle; call
/// `stop` (idempotent) to terminate it. The handle is independent of any session.
pub const DriverProcess = struct {
    allocator: std.mem.Allocator,
    handle: ?*anyopaque,

    /// The base URL the driver is listening on (owned; "" if none). Pass to
    /// `WebDriver.chrome` as the command_executor.
    pub fn url(self: *DriverProcess) Error![]u8 {
        if (self.handle == null) return self.allocator.dupe(u8, "") catch Error.OutOfMemory;
        return takeString(self.allocator, c.aether_sel_embed_driver_url(self.handle));
    }

    /// The driver process id (0 if not running).
    pub fn pid(self: *DriverProcess) i32 {
        if (self.handle == null) return 0;
        return @intCast(c.aether_sel_embed_driver_pid(self.handle));
    }

    pub fn stop(self: *DriverProcess) void {
        if (self.handle) |h| {
            c.aether_sel_embed_stop_driver(h);
            self.handle = null;
        }
    }
};

/// Launch a driver at an explicit binary path. Returns a `DriverProcess`, or
/// `error.WebDriver` if it did not come up in `timeout_ms`.
pub fn launchDriver(allocator: std.mem.Allocator, driver_path: []const u8, timeout_ms: c_int) Error!DriverProcess {
    const pc = try cstr(allocator, driver_path);
    defer allocator.free(pc);
    const h = c.aether_sel_embed_launch_driver(pc.ptr, timeout_ms);
    if (h == null) return Error.WebDriver;
    return DriverProcess{ .allocator = allocator, .handle = h };
}

/// Resolve (detect/download/cache) AND launch a driver for `browser` in one
/// step. Returns a running `DriverProcess`, or `error.WebDriver` if none could
/// be resolved/launched.
pub fn ensureDriver(allocator: std.mem.Allocator, browser: []const u8, hint: []const u8, timeout_ms: c_int) Error!DriverProcess {
    const bc = try cstr(allocator, browser);
    defer allocator.free(bc);
    const hc = try cstr(allocator, hint);
    defer allocator.free(hc);
    const h = c.aether_sel_embed_ensure_driver(bc.ptr, hc.ptr, timeout_ms);
    if (h == null) return Error.WebDriver;
    return DriverProcess{ .allocator = allocator, .handle = h };
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
    /// A driver process this session owns (set by `localChrome`); stopped on
    /// `quit`/`deinit`. Null for sessions against a caller-supplied URL.
    owned_driver: ?DriverProcess = null,

    /// Per-session TLS trust config, applied on the handle BEFORE newSession.
    /// `ca_path` pins a private-CA bundle; `insecure` skips verification entirely
    /// (self-signed dev/staging Grid — trust the host out-of-band).
    pub const TlsConfig = struct {
        ca_path: ?[]const u8 = null,
        insecure: bool = false,
    };

    pub fn chrome(allocator: std.mem.Allocator, command_executor: []const u8, options_json: []const u8) Error!WebDriver {
        return chromeTls(allocator, command_executor, options_json, .{});
    }

    pub fn chromeTls(allocator: std.mem.Allocator, command_executor: []const u8, options_json: []const u8, tls: TlsConfig) Error!WebDriver {
        const cu = try cstr(allocator, command_executor);
        defer allocator.free(cu);
        const handle = c.aether_sel_embed_open(cu.ptr);
        if (handle == null) return Error.WebDriver;
        var d = WebDriver{ .allocator = allocator, .handle = handle };
        // TLS trust config must land on the handle before newSession.
        if (tls.ca_path) |ca| {
            const cac = try cstr(allocator, ca);
            defer allocator.free(cac);
            c.aether_sel_embed_set_ca(handle, cac.ptr);
        }
        if (tls.insecure) c.aether_sel_embed_set_insecure(handle, 1);
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

    /// A Chrome session that spawns its OWN chromedriver via the engine — no
    /// driver on PATH, no Grid. The driver process is owned by the session and
    /// stopped on `quit`/`deinit`. `options_json` is the caps object (as for
    /// `chrome`); pass `"{}"` for defaults. Returns `error.WebDriver` if no
    /// driver could be resolved/launched.
    pub fn localChrome(allocator: std.mem.Allocator, options_json: []const u8, hint: []const u8, timeout_ms: c_int, tls: TlsConfig) Error!WebDriver {
        var proc = try ensureDriver(allocator, "chrome", hint, timeout_ms);
        const url = proc.url() catch |e| {
            proc.stop();
            return e;
        };
        defer allocator.free(url);
        var d = chromeTls(allocator, url, options_json, tls) catch |e| {
            proc.stop();
            return e;
        };
        d.owned_driver = proc;
        return d;
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
        if (self.owned_driver) |*p| {
            p.stop();
            self.owned_driver = null;
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

    /// The current document URL as an owned slice (`getCurrentUrl`).
    pub fn currentUrl(self: *WebDriver) Error![]u8 {
        return self.stringCmd("getCurrentUrl", "{}");
    }

    /// The current page's serialized source as an owned slice (`getPageSource`).
    pub fn pageSource(self: *WebDriver) Error![]u8 {
        return self.stringCmd("getPageSource", "{}");
    }

    pub fn back(self: *WebDriver) Error!void {
        var v = try self.execute("goBack", "{}");
        v.deinit();
    }
    pub fn forward(self: *WebDriver) Error!void {
        var v = try self.execute("goForward", "{}");
        v.deinit();
    }
    pub fn refresh(self: *WebDriver) Error!void {
        var v = try self.execute("refresh", "{}");
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
    pub fn findElement(self: *WebDriver, by: Locator) Error!WebElement {
        const loc = try locator(self.allocator, by.using, by.value);
        defer self.allocator.free(loc);
        var v = try self.execute("findElement", loc);
        defer v.deinit();
        const id = self.extractElementId(v.value) catch return Error.WebDriver;
        return WebElement{ .driver = self, .id = id };
    }

    /// True if at least one element matching `by` is present right now — an
    /// immediate presence check with no implicit wait. A clean not-found maps
    /// to `false`; a transport failure still surfaces as `error.WebDriver`.
    pub fn exists(self: *WebDriver, by: Locator) Error!bool {
        var el = self.findElement(by) catch {
            if (self.last) |l| {
                if (l.kind == .no_such_element) return false;
            }
            return Error.WebDriver;
        };
        el.deinit();
        return true;
    }

    /// The active (focused) element (`getActiveElement`) — what would receive
    /// keyboard input.
    pub fn activeElement(self: *WebDriver) Error!WebElement {
        var v = try self.execute("getActiveElement", "{}");
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

    /// An element command whose response is a JSON string; returns it owned.
    fn elementStringCmd(self: *WebDriver, command: []const u8, element_id: []const u8, extra_json: []const u8) Error![]u8 {
        var v = try self.elementCmd(command, element_id, extra_json);
        defer v.deinit();
        const s = switch (v.value) {
            .string => |x| x,
            else => "",
        };
        return self.allocator.dupe(u8, s) catch Error.OutOfMemory;
    }

    /// An element command whose response is a JSON bool; false for anything else.
    fn elementBoolCmd(self: *WebDriver, command: []const u8, element_id: []const u8) Error!bool {
        var v = try self.elementCmd(command, element_id, "");
        defer v.deinit();
        return switch (v.value) {
            .bool => |b| b,
            else => false,
        };
    }

    /// Clear a text/input element (`clearElement`).
    pub fn elementClear(self: *WebDriver, e: *const WebElement) Error!void {
        var v = try self.elementCmd("clearElement", e.id, "");
        v.deinit();
    }

    /// Type `text` into the element (`sendKeysToElement`). Accepts `Keys`
    /// constants embedded in the string (they are forwarded unchanged). The
    /// value is sent both as the whole string and as the W3C per-scalar array.
    pub fn elementSendKeys(self: *WebDriver, e: *const WebElement, text: []const u8) Error!void {
        // Build the ["a","b",...] scalar array (one entry per Unicode scalar).
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(self.allocator);
        try buf.append(self.allocator, '[');
        var view = std.unicode.Utf8View.init(text) catch return Error.BadResponse;
        var it = view.iterator();
        var first = true;
        while (it.nextCodepointSlice()) |slice| {
            if (!first) try buf.append(self.allocator, ',');
            first = false;
            try appendJsonString(self.allocator, &buf, slice);
        }
        try buf.append(self.allocator, ']');
        const text_json = try jsonString(self.allocator, text);
        defer self.allocator.free(text_json);
        const extra = try std.fmt.allocPrint(self.allocator, ",\"text\":{s},\"value\":{s}", .{ text_json, buf.items });
        defer self.allocator.free(extra);
        var v = try self.elementCmd("sendKeysToElement", e.id, extra);
        v.deinit();
    }

    /// True if the element is enabled (`isElementEnabled`).
    pub fn isEnabled(self: *WebDriver, e: *const WebElement) Error!bool {
        return self.elementBoolCmd("isElementEnabled", e.id);
    }

    /// True if the element is selected/checked (`isElementSelected`).
    pub fn isSelected(self: *WebDriver, e: *const WebElement) Error!bool {
        return self.elementBoolCmd("isElementSelected", e.id);
    }

    /// A live DOM/JS property of the element (`getElementProperty`). Returns the
    /// parsed value (owned; `.deinit()`) — the property may be any JSON type or
    /// `null` when absent.
    pub fn elementProperty(self: *WebDriver, e: *const WebElement, name: []const u8) Error!std.json.Parsed(std.json.Value) {
        const extra = try std.fmt.allocPrint(self.allocator, ",\"name\":\"{s}\"", .{name});
        defer self.allocator.free(extra);
        return self.elementCmd("getElementProperty", e.id, extra);
    }

    /// The computed value of a CSS property (`getElementValueOfCssProperty`),
    /// e.g. "display", "color". Owned slice.
    pub fn cssValue(self: *WebDriver, e: *const WebElement, prop: []const u8) Error![]u8 {
        const extra = try std.fmt.allocPrint(self.allocator, ",\"propertyName\":\"{s}\"", .{prop});
        defer self.allocator.free(extra);
        return self.elementStringCmd("getElementValueOfCssProperty", e.id, extra);
    }

    /// Classic-Selenium-named alias of `cssValue`.
    pub fn valueOfCssProperty(self: *WebDriver, e: *const WebElement, prop: []const u8) Error![]u8 {
        return self.cssValue(e, prop);
    }

    /// A base64 PNG screenshot of just this element (`takeElementScreenshot`).
    pub fn elementScreenshotBase64(self: *WebDriver, e: *const WebElement) Error![]u8 {
        return self.elementStringCmd("takeElementScreenshot", e.id, "");
    }

    /// Submit the form this element belongs to. W3C removed the dedicated
    /// `submit` endpoint, so (like the reference binding and modern Selenium)
    /// this walks up to the enclosing `<form>` and calls `requestSubmit()`
    /// (falling back to `submit()`) via an injected script. `error.WebDriver`
    /// (kind other) if the element is not inside a form.
    pub fn submit(self: *WebDriver, e: *const WebElement) Error!void {
        const script =
            "var e=arguments[0];var f=e.form||e.closest('form');" ++
            "if(!f){throw new Error('Element is not within a form');}" ++
            "if(f.requestSubmit){f.requestSubmit();}else{f.submit();}";
        const args = try std.fmt.allocPrint(self.allocator, "[{{\"{s}\":\"{s}\"}}]", .{ w3c_element_key, e.id });
        defer self.allocator.free(args);
        var v = try self.executeScript(script, args);
        v.deinit();
    }

    /// Find the first descendant of `parent` matching `by` (element-scoped
    /// `findChildElement`).
    pub fn findChildElement(self: *WebDriver, parent: *const WebElement, by: Locator) Error!WebElement {
        const loc = try locator(self.allocator, by.using, by.value);
        defer self.allocator.free(loc);
        // {"id":"<parent>","using":"...","value":"..."} — merge the parent id
        // into the locator object by replacing its leading `{`.
        const p = try std.fmt.allocPrint(self.allocator, "{{\"id\":\"{s}\",{s}", .{ parent.id, loc[1..] });
        defer self.allocator.free(p);
        var v = try self.execute("findChildElement", p);
        defer v.deinit();
        const id = self.extractElementId(v.value) catch return Error.WebDriver;
        return WebElement{ .driver = self, .id = id };
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
    /// All cookies visible to the current page (`getCookies`); parsed array
    /// value (owned; `.deinit()`).
    pub fn cookies(self: *WebDriver) Error!std.json.Parsed(std.json.Value) {
        return self.execute("getCookies", "{}");
    }
    /// Delete the named cookie (`deleteCookie`).
    pub fn deleteCookie(self: *WebDriver, name: []const u8) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"name\":\"{s}\"}}", .{name});
        defer self.allocator.free(p);
        var v = try self.execute("deleteCookie", p);
        v.deinit();
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

    /// Turn a parsed JSON array-of-strings into an owned `[][]u8` the caller
    /// frees with `freeStringList`.
    fn ownStringArray(self: *WebDriver, value: std.json.Value) Error![][]u8 {
        const arr = switch (value) {
            .array => |a| a,
            else => return self.allocator.alloc([]u8, 0) catch Error.OutOfMemory,
        };
        var out = self.allocator.alloc([]u8, arr.items.len) catch return Error.OutOfMemory;
        var i: usize = 0;
        errdefer {
            var j: usize = 0;
            while (j < i) : (j += 1) self.allocator.free(out[j]);
            self.allocator.free(out);
        }
        while (i < arr.items.len) : (i += 1) {
            const s = switch (arr.items[i]) {
                .string => |x| x,
                else => "",
            };
            out[i] = self.allocator.dupe(u8, s) catch return Error.OutOfMemory;
        }
        return out;
    }

    /// Free a `[][]u8` returned by `windowHandles`/`newWindow`/etc.
    pub fn freeStringList(self: *WebDriver, list: [][]u8) void {
        for (list) |s| self.allocator.free(s);
        self.allocator.free(list);
    }

    /// All open window/tab handles (owned; free with `freeStringList`).
    pub fn windowHandles(self: *WebDriver) Error![][]u8 {
        var v = try self.execute("getWindowHandles", "{}");
        defer v.deinit();
        return self.ownStringArray(v.value);
    }

    /// The current window/tab handle as an owned slice (`getCurrentWindowHandle`).
    pub fn currentWindowHandle(self: *WebDriver) Error![]u8 {
        return self.stringCmd("getCurrentWindowHandle", "{}");
    }

    /// The current window rect ({x,y,width,height}); parsed value (owned).
    pub fn getWindowRect(self: *WebDriver) Error!std.json.Parsed(std.json.Value) {
        return self.execute("getWindowRect", "{}");
    }

    /// Open a new top-level browsing context (`newWindow`). `type_hint` is
    /// "tab" or "window". Returns the new window's handle (owned; "" if the
    /// remote end sent none) — pass it to `switchToWindow` to focus it.
    pub fn newWindow(self: *WebDriver, type_hint: []const u8) Error![]u8 {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"type\":\"{s}\"}}", .{type_hint});
        defer self.allocator.free(p);
        var v = try self.execute("newWindow", p);
        defer v.deinit();
        const h = switch (v.value) {
            .object => |o| if (o.get("handle")) |hv| switch (hv) {
                .string => |s| s,
                else => "",
            } else "",
            else => "",
        };
        return self.allocator.dupe(u8, h) catch Error.OutOfMemory;
    }

    /// Close the current window/tab (`close`). Returns the surviving handles
    /// (owned; free with `freeStringList`). Does NOT end the session (use
    /// `quit`); when the list empties, switch to a surviving handle first.
    pub fn closeWindow(self: *WebDriver) Error![][]u8 {
        var v = try self.execute("close", "{}");
        defer v.deinit();
        return self.ownStringArray(v.value);
    }

    // ---- frames ----

    /// Switch focus to a frame by 0-based index (`switchToFrame`).
    pub fn switchToFrame(self: *WebDriver, index: u32) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"id\":{d}}}", .{index});
        defer self.allocator.free(p);
        var v = try self.execute("switchToFrame", p);
        v.deinit();
    }

    /// Switch focus to the frame hosted by `element` (`switchToFrame` with an
    /// element-reference id).
    pub fn switchToFrameElement(self: *WebDriver, element: *const WebElement) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"id\":{{\"{s}\":\"{s}\"}}}}", .{ w3c_element_key, element.id });
        defer self.allocator.free(p);
        var v = try self.execute("switchToFrame", p);
        v.deinit();
    }

    /// Return focus to the top-level browsing context (`switchToFrame` null id).
    pub fn switchToDefaultContent(self: *WebDriver) Error!void {
        var v = try self.execute("switchToFrame", "{\"id\":null}");
        v.deinit();
    }

    /// Switch to the parent of the current frame — one level out, unlike
    /// `switchToDefaultContent` which jumps to the top (`switchToFrameParent`).
    pub fn switchToParentFrame(self: *WebDriver) Error!void {
        var v = try self.execute("switchToFrameParent", "{}");
        v.deinit();
    }

    pub fn setWindowRect(self: *WebDriver, rect_json: []const u8) Error!void {
        var v = try self.execute("setWindowRect", rect_json);
        v.deinit();
    }
    pub fn switchToWindow(self: *WebDriver, handle: []const u8) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"handle\":\"{s}\"}}", .{handle});
        defer self.allocator.free(p);
        var v = try self.execute("switchToWindow", p);
        v.deinit();
    }
    pub fn maximizeWindow(self: *WebDriver) Error!void {
        var v = try self.execute("maximizeWindow", "{}");
        v.deinit();
    }
    pub fn minimizeWindow(self: *WebDriver) Error!void {
        var v = try self.execute("minimizeWindow", "{}");
        v.deinit();
    }
    pub fn fullscreenWindow(self: *WebDriver) Error!void {
        var v = try self.execute("fullscreenWindow", "{}");
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

    // ---- alerts ----
    pub fn acceptAlert(self: *WebDriver) Error!void {
        var v = try self.execute("acceptAlert", "{}");
        v.deinit();
    }
    pub fn dismissAlert(self: *WebDriver) Error!void {
        var v = try self.execute("dismissAlert", "{}");
        v.deinit();
    }
    /// The current alert's text as an owned slice.
    pub fn alertText(self: *WebDriver) Error![]u8 {
        return self.stringCmd("getAlertText", "{}");
    }
    pub fn sendAlertText(self: *WebDriver, text: []const u8) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"text\":\"{s}\"}}", .{text});
        defer self.allocator.free(p);
        var v = try self.execute("setAlertValue", p);
        v.deinit();
    }
    /// True if a user-prompt / alert dialog is currently present (probed via
    /// `getAlertText`). A clean "no such alert" (code 15) maps to `false`; any
    /// other failure surfaces as `error.WebDriver`.
    pub fn alertPresent(self: *WebDriver) Error!bool {
        var v = self.execute("getAlertText", "{}") catch {
            if (self.last) |l| {
                if (l.code == 15) return false;
            }
            return Error.WebDriver;
        };
        v.deinit();
        return true;
    }

    // ---- timeouts ----
    /// Set one or more timeouts in a single call. `timeouts_json` is the W3C
    /// object body, e.g. `{"implicit":5000,"pageLoad":30000,"script":30000}`.
    pub fn setTimeouts(self: *WebDriver, timeouts_json: []const u8) Error!void {
        var v = try self.execute("setTimeout", timeouts_json);
        v.deinit();
    }
    pub fn setPageLoadTimeout(self: *WebDriver, ms: i64) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"pageLoad\":{d}}}", .{ms});
        defer self.allocator.free(p);
        var v = try self.execute("setTimeout", p);
        v.deinit();
    }
    pub fn setScriptTimeout(self: *WebDriver, ms: i64) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"script\":{d}}}", .{ms});
        defer self.allocator.free(p);
        var v = try self.execute("setTimeout", p);
        v.deinit();
    }
    pub fn implicitlyWait(self: *WebDriver, ms: i64) Error!void {
        const p = try std.fmt.allocPrint(self.allocator, "{{\"implicit\":{d}}}", .{ms});
        defer self.allocator.free(p);
        var v = try self.execute("setTimeout", p);
        v.deinit();
    }

    // ---- explicit waits ----

    /// Start an explicit wait with `timeout_ms`. Poll cadence defaults to
    /// `default_poll_ms`; override with `Wait.pollEvery`. Feed the returned
    /// `Wait` a predicate via `until`/`untilNot`, or use a `waitFor*` helper.
    pub fn wait(self: *WebDriver, timeout_ms: u64) Wait {
        return .{ .driver = self, .timeout_ms = timeout_ms };
    }

    /// `findElement` that maps a NoSuchElement miss to null instead of an error
    /// — the primitive the element-returning waits poll on.
    fn tryFind(self: *WebDriver, by: Locator) Error!?WebElement {
        return self.findElement(by) catch {
            if (self.last) |l| {
                if (l.kind == .no_such_element) return null;
            }
            return Error.WebDriver;
        };
    }

    /// Block until an element matching `by` is present in the DOM; return it
    /// (owned; `.deinit()`). `error.WebDriver` (kind timeout) on timeout.
    pub fn waitForElement(self: *WebDriver, by: Locator, timeout_ms: u64) Error!WebElement {
        var elapsed: u64 = 0;
        while (true) {
            if (try self.tryFind(by)) |el| return el;
            if (elapsed >= timeout_ms) {
                self.setLast(21, self.allocator.dupe(u8, "waited for element") catch "");
                return Error.WebDriver;
            }
            std.Thread.sleep(default_poll_ms * std.time.ns_per_ms);
            elapsed += default_poll_ms;
        }
    }

    /// Block until an element matching `by` is present AND displayed; return it.
    pub fn waitForVisible(self: *WebDriver, by: Locator, timeout_ms: u64) Error!WebElement {
        var elapsed: u64 = 0;
        while (true) {
            if (try self.tryFind(by)) |el| {
                if (try self.isDisplayed(&el)) return el;
                var mel = el;
                mel.deinit();
            }
            if (elapsed >= timeout_ms) {
                self.setLast(21, self.allocator.dupe(u8, "waited for visible element") catch "");
                return Error.WebDriver;
            }
            std.Thread.sleep(default_poll_ms * std.time.ns_per_ms);
            elapsed += default_poll_ms;
        }
    }

    /// Block until an element matching `by` is present, displayed AND enabled
    /// (clickable); return it.
    pub fn waitForClickable(self: *WebDriver, by: Locator, timeout_ms: u64) Error!WebElement {
        var elapsed: u64 = 0;
        while (true) {
            if (try self.tryFind(by)) |el| {
                if ((try self.isDisplayed(&el)) and (try self.isEnabled(&el))) return el;
                var mel = el;
                mel.deinit();
            }
            if (elapsed >= timeout_ms) {
                self.setLast(21, self.allocator.dupe(u8, "waited for clickable element") catch "");
                return Error.WebDriver;
            }
            std.Thread.sleep(default_poll_ms * std.time.ns_per_ms);
            elapsed += default_poll_ms;
        }
    }

    /// Block until NO element matches `by` — it is absent/removed. (classic
    /// staleness, by locator.) `error.WebDriver` (kind timeout) on timeout.
    pub fn waitUntilGone(self: *WebDriver, by: Locator, timeout_ms: u64) Error!void {
        var elapsed: u64 = 0;
        while (true) {
            if ((try self.tryFind(by)) == null) return;
            if (elapsed >= timeout_ms) {
                self.setLast(21, self.allocator.dupe(u8, "waited for element to disappear") catch "");
                return Error.WebDriver;
            }
            std.Thread.sleep(default_poll_ms * std.time.ns_per_ms);
            elapsed += default_poll_ms;
        }
    }

    fn waitTitleUrl(self: *WebDriver, comptime which: enum { title, url }, comptime mode: enum { is, contains }, needle: []const u8, timeout_ms: u64) Error!void {
        var elapsed: u64 = 0;
        while (true) {
            const cur = switch (which) {
                .title => try self.title(),
                .url => try self.currentUrl(),
            };
            defer self.allocator.free(cur);
            const ok = switch (mode) {
                .is => std.mem.eql(u8, cur, needle),
                .contains => std.mem.indexOf(u8, cur, needle) != null,
            };
            if (ok) return;
            if (elapsed >= timeout_ms) {
                self.setLast(21, self.allocator.dupe(u8, "waited for title/url condition") catch "");
                return Error.WebDriver;
            }
            std.Thread.sleep(default_poll_ms * std.time.ns_per_ms);
            elapsed += default_poll_ms;
        }
    }

    /// Block until the page title equals `title`.
    pub fn waitForTitleIs(self: *WebDriver, want: []const u8, timeout_ms: u64) Error!void {
        return self.waitTitleUrl(.title, .is, want, timeout_ms);
    }
    /// Block until the page title contains `substr`.
    pub fn waitForTitleContains(self: *WebDriver, substr: []const u8, timeout_ms: u64) Error!void {
        return self.waitTitleUrl(.title, .contains, substr, timeout_ms);
    }
    /// Block until the current URL equals `url`.
    pub fn waitForUrlIs(self: *WebDriver, want: []const u8, timeout_ms: u64) Error!void {
        return self.waitTitleUrl(.url, .is, want, timeout_ms);
    }
    /// Block until the current URL contains `substr`.
    pub fn waitForUrlContains(self: *WebDriver, substr: []const u8, timeout_ms: u64) Error!void {
        return self.waitTitleUrl(.url, .contains, substr, timeout_ms);
    }

    // ---- screenshots ----
    pub fn screenshotBase64(self: *WebDriver) Error![]u8 {
        return self.stringCmd("screenshot", "{}");
    }

    /// Print the current page to PDF (`printPage`), returning the PDF as an
    /// owned base64 slice. `options_json` is the W3C print-options object body
    /// (page size, margins, orientation, scale, pageRanges, …); pass "{}" for
    /// defaults.
    pub fn printPdf(self: *WebDriver, options_json: []const u8) Error![]u8 {
        return self.stringCmd("printPage", options_json);
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

// ---- Select: the <select> dropdown convenience tier ----

/// A read-only snapshot of one `<option>`'s matchable fields — the pure core of
/// the option scan, unit-testable with no browser.
pub const OptionInfo = struct {
    text: []const u8,
    value: []const u8,
};

/// The first option index whose visible text equals `text`, or null. First
/// match wins in document order (as the Python reference iterates).
pub fn findOptionByText(options: []const OptionInfo, text: []const u8) ?usize {
    for (options, 0..) |o, i| {
        if (std.mem.eql(u8, o.text, text)) return i;
    }
    return null;
}

/// The first option index whose `value` attribute equals `value`, or null.
pub fn findOptionByValue(options: []const OptionInfo, value: []const u8) ?usize {
    for (options, 0..) |o, i| {
        if (std.mem.eql(u8, o.value, value)) return i;
    }
    return null;
}

/// A wrapper over a `<select>` element that selects among its `<option>`
/// children by clicking them — the same approach mainstream Selenium's `Select`
/// uses. Build one with `Select.init`; it borrows the element (which borrows the
/// driver).
pub const Select = struct {
    driver: *WebDriver,
    element: *const WebElement,
    is_multiple: bool,

    /// Wrap `element` as a `<select>`. `error.WebDriver` (kind other) if the
    /// element is not a `<select>` tag.
    pub fn init(driver: *WebDriver, element: *const WebElement) Error!Select {
        const tag = try driver.elementTagName(element);
        defer driver.allocator.free(tag);
        if (!std.ascii.eqlIgnoreCase(tag, "select")) {
            driver.setLast(0, driver.allocator.dupe(u8, "Select only works on <select> elements") catch "");
            return Error.WebDriver;
        }
        // `multiple` is a boolean attribute: present (non-"false") == multi.
        var multi = false;
        var attr = try driver.getAttribute(element, "multiple");
        defer attr.deinit();
        switch (attr.value) {
            .string => |s| multi = s.len > 0 and !std.mem.eql(u8, s, "false"),
            .bool => |b| multi = b,
            else => {},
        }
        return Select{ .driver = driver, .element = element, .is_multiple = multi };
    }

    /// Whether this is a multi-select (`multiple` attribute present).
    pub fn isMultiple(self: *const Select) bool {
        return self.is_multiple;
    }

    /// All `<option>` children, in document order. Caller frees each with
    /// `.deinit()` and the slice with `allocator.free`.
    pub fn options(self: *const Select) Error![]WebElement {
        const loc = try locator(self.driver.allocator, "tag name", "option");
        defer self.driver.allocator.free(loc);
        const p = try std.fmt.allocPrint(self.driver.allocator, "{{\"id\":\"{s}\",{s}", .{ self.element.id, loc[1..] });
        defer self.driver.allocator.free(p);
        var v = try self.driver.execute("findChildElements", p);
        defer v.deinit();
        const arr = switch (v.value) {
            .array => |a| a,
            else => return self.driver.allocator.alloc(WebElement, 0) catch Error.OutOfMemory,
        };
        var out = self.driver.allocator.alloc(WebElement, arr.items.len) catch return Error.OutOfMemory;
        var i: usize = 0;
        errdefer {
            var j: usize = 0;
            while (j < i) : (j += 1) out[j].deinit();
            self.driver.allocator.free(out);
        }
        while (i < arr.items.len) : (i += 1) {
            const id = self.driver.extractElementId(arr.items[i]) catch return Error.WebDriver;
            out[i] = WebElement{ .driver = self.driver, .id = id };
        }
        return out;
    }

    fn freeOptions(self: *const Select, opts: []WebElement) void {
        for (opts) |*o| o.deinit();
        self.driver.allocator.free(opts);
    }

    /// Click `o` to select it, unless already selected (a second click would
    /// toggle a multi-select option back off).
    fn selectOption(self: *const Select, o: *const WebElement) Error!void {
        if (!try self.driver.isSelected(o)) try self.driver.elementClick(o);
    }

    /// The options currently selected (owned; free each `.deinit()` + slice).
    pub fn allSelectedOptions(self: *const Select) Error![]WebElement {
        const opts = try self.options();
        defer self.driver.allocator.free(opts);
        var list = std.ArrayList(WebElement).empty;
        errdefer {
            for (list.items) |*e| e.deinit();
            list.deinit(self.driver.allocator);
        }
        for (opts) |*o| {
            if (try self.driver.isSelected(o)) {
                list.append(self.driver.allocator, o.*) catch return Error.OutOfMemory;
            } else {
                var mo = o.*;
                mo.deinit();
            }
        }
        return list.toOwnedSlice(self.driver.allocator) catch Error.OutOfMemory;
    }

    /// The first selected option (owned; `.deinit()`). `error.WebDriver` (kind
    /// no_such_element) if none is selected.
    pub fn firstSelectedOption(self: *const Select) Error!WebElement {
        const opts = try self.options();
        defer self.driver.allocator.free(opts);
        for (opts, 0..) |*o, idx| {
            if (try self.driver.isSelected(o)) {
                // hand out this one; free the rest
                for (opts, 0..) |*other, j| {
                    if (j != idx) other.deinit();
                }
                return o.*;
            }
        }
        for (opts) |*o| o.deinit();
        self.driver.setLast(17, self.driver.allocator.dupe(u8, "no option is selected") catch "");
        return Error.WebDriver;
    }

    /// Select the option whose visible text equals `text`. `error.WebDriver`
    /// (kind no_such_element) if none matches.
    pub fn selectByVisibleText(self: *const Select, text: []const u8) Error!void {
        const opts = try self.options();
        defer self.freeOptions(opts);
        for (opts) |*o| {
            const t = try self.driver.elementText(o);
            defer self.driver.allocator.free(t);
            if (std.mem.eql(u8, t, text)) return self.selectOption(o);
        }
        self.driver.setLast(17, self.driver.allocator.dupe(u8, "no option with that visible text") catch "");
        return Error.WebDriver;
    }

    /// Select the option whose `value` attribute equals `value`.
    pub fn selectByValue(self: *const Select, value: []const u8) Error!void {
        const opts = try self.options();
        defer self.freeOptions(opts);
        for (opts) |*o| {
            var attr = try self.driver.getAttribute(o, "value");
            defer attr.deinit();
            const v = switch (attr.value) {
                .string => |s| s,
                else => "",
            };
            if (std.mem.eql(u8, v, value)) return self.selectOption(o);
        }
        self.driver.setLast(17, self.driver.allocator.dupe(u8, "no option with that value") catch "");
        return Error.WebDriver;
    }

    /// Select the option at `index` (0-based, document order).
    pub fn selectByIndex(self: *const Select, index: usize) Error!void {
        const opts = try self.options();
        defer self.freeOptions(opts);
        if (index >= opts.len) {
            self.driver.setLast(17, self.driver.allocator.dupe(u8, "no option at that index") catch "");
            return Error.WebDriver;
        }
        return self.selectOption(&opts[index]);
    }

    /// Deselect every selected option (multi-select only). `error.WebDriver`
    /// (kind other) on a single-select.
    pub fn deselectAll(self: *const Select) Error!void {
        if (!self.is_multiple) {
            self.driver.setLast(0, self.driver.allocator.dupe(u8, "deselect_all only makes sense on a multi-select") catch "");
            return Error.WebDriver;
        }
        const opts = try self.options();
        defer self.freeOptions(opts);
        for (opts) |*o| {
            if (try self.driver.isSelected(o)) try self.driver.elementClick(o);
        }
    }
};

// ---- Actions: the fluent W3C action-sequence builder ----

/// A queued sequence of W3C input actions, built by appending gestures and
/// posted in one `actions` command by `perform`. Mirrors the Rust `Actions` /
/// mainstream `ActionChains`. Two virtual devices (a mouse pointer and a
/// keyboard) are kept length-synced with pauses so ticks line up. Build with
/// `Actions.init`; call `deinit` if you never `perform`.
pub const Actions = struct {
    driver: *WebDriver,
    pointer: std.ArrayList(u8), // JSON array body (no brackets), comma-led
    key: std.ArrayList(u8),
    pointer_ticks: usize = 0,
    key_ticks: usize = 0,
    pointer_has_real: bool = false,
    key_has_real: bool = false,
    err: bool = false,

    pub fn init(driver: *WebDriver) Actions {
        return .{ .driver = driver, .pointer = .empty, .key = .empty };
    }

    pub fn deinit(self: *Actions) void {
        self.pointer.deinit(self.driver.allocator);
        self.key.deinit(self.driver.allocator);
    }

    fn a(self: *Actions) std.mem.Allocator {
        return self.driver.allocator;
    }

    fn pushPointer(self: *Actions, json: []const u8, real: bool) void {
        if (self.err) return;
        if (self.pointer.items.len > 0) self.pointer.append(self.a(), ',') catch {
            self.err = true;
            return;
        };
        self.pointer.appendSlice(self.a(), json) catch {
            self.err = true;
            return;
        };
        self.pointer_ticks += 1;
        if (real) self.pointer_has_real = true;
        self.syncLengths();
    }

    fn pushKey(self: *Actions, json: []const u8, real: bool) void {
        if (self.err) return;
        if (self.key.items.len > 0) self.key.append(self.a(), ',') catch {
            self.err = true;
            return;
        };
        self.key.appendSlice(self.a(), json) catch {
            self.err = true;
            return;
        };
        self.key_ticks += 1;
        if (real) self.key_has_real = true;
        self.syncLengths();
    }

    fn pauseJson() []const u8 {
        return "{\"type\":\"pause\",\"duration\":0}";
    }

    // W3C requires each device's action list to be the same length; pad the
    // shorter with zero-duration pauses so gestures don't desync ticks.
    fn syncLengths(self: *Actions) void {
        if (self.err) return;
        while (self.pointer_ticks < self.key_ticks) {
            if (self.pointer.items.len > 0) self.pointer.append(self.a(), ',') catch {
                self.err = true;
                return;
            };
            self.pointer.appendSlice(self.a(), pauseJson()) catch {
                self.err = true;
                return;
            };
            self.pointer_ticks += 1;
        }
        while (self.key_ticks < self.pointer_ticks) {
            if (self.key.items.len > 0) self.key.append(self.a(), ',') catch {
                self.err = true;
                return;
            };
            self.key.appendSlice(self.a(), pauseJson()) catch {
                self.err = true;
                return;
            };
            self.key_ticks += 1;
        }
    }

    fn moveTo(self: *Actions, id: []const u8) void {
        var buf: [512]u8 = undefined;
        const j = std.fmt.bufPrint(&buf, "{{\"type\":\"pointerMove\",\"duration\":100,\"x\":0,\"y\":0,\"origin\":{{\"{s}\":\"{s}\"}}}}", .{ w3c_element_key, id }) catch {
            self.err = true;
            return;
        };
        self.pushPointer(j, true);
    }
    fn buttonDown(self: *Actions, button: u8) void {
        var buf: [64]u8 = undefined;
        const j = std.fmt.bufPrint(&buf, "{{\"type\":\"pointerDown\",\"button\":{d}}}", .{button}) catch return;
        self.pushPointer(j, true);
    }
    fn buttonUp(self: *Actions, button: u8) void {
        var buf: [64]u8 = undefined;
        const j = std.fmt.bufPrint(&buf, "{{\"type\":\"pointerUp\",\"button\":{d}}}", .{button}) catch return;
        self.pushPointer(j, true);
    }

    /// Move the pointer to the centre of `element`.
    pub fn moveToElement(self: *Actions, element: *const WebElement) *Actions {
        self.moveTo(element.id);
        return self;
    }
    /// Left-click. With a non-null element, moves to it first.
    pub fn click(self: *Actions, element: ?*const WebElement) *Actions {
        if (element) |e| self.moveTo(e.id);
        self.buttonDown(0);
        self.buttonUp(0);
        return self;
    }
    /// Right-click (contextmenu). Moves to `element` first when given.
    pub fn contextClick(self: *Actions, element: ?*const WebElement) *Actions {
        if (element) |e| self.moveTo(e.id);
        self.buttonDown(2);
        self.buttonUp(2);
        return self;
    }
    /// Double-click. Moves to `element` first when given.
    pub fn doubleClick(self: *Actions, element: ?*const WebElement) *Actions {
        if (element) |e| self.moveTo(e.id);
        self.buttonDown(0);
        self.buttonUp(0);
        self.buttonDown(0);
        self.buttonUp(0);
        return self;
    }
    /// Press and hold the left button (the start of a drag).
    pub fn clickAndHold(self: *Actions, element: ?*const WebElement) *Actions {
        if (element) |e| self.moveTo(e.id);
        self.buttonDown(0);
        return self;
    }
    /// Release the held left button.
    pub fn release(self: *Actions, element: ?*const WebElement) *Actions {
        if (element) |e| self.moveTo(e.id);
        self.buttonUp(0);
        return self;
    }
    /// Drag `source` onto `target` (press at source, move to target, release).
    pub fn dragAndDrop(self: *Actions, source: *const WebElement, target: *const WebElement) *Actions {
        self.moveTo(source.id);
        self.buttonDown(0);
        self.moveTo(target.id);
        self.buttonUp(0);
        return self;
    }
    /// Press (and hold) a key on the keyboard device (`key` a single-scalar
    /// string, e.g. a `Keys` constant) — pair with `keyUp` for a chord.
    pub fn keyDown(self: *Actions, key: []const u8) *Actions {
        self.keyEvent("keyDown", key);
        return self;
    }
    /// Release a previously pressed key.
    pub fn keyUp(self: *Actions, key: []const u8) *Actions {
        self.keyEvent("keyUp", key);
        return self;
    }
    fn keyEvent(self: *Actions, kind: []const u8, key: []const u8) void {
        const kj = jsonString(self.a(), key) catch {
            self.err = true;
            return;
        };
        defer self.a().free(kj);
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(self.a());
        buf.appendSlice(self.a(), "{\"type\":\"") catch {
            self.err = true;
            return;
        };
        buf.appendSlice(self.a(), kind) catch {
            self.err = true;
            return;
        };
        buf.appendSlice(self.a(), "\",\"value\":") catch {
            self.err = true;
            return;
        };
        buf.appendSlice(self.a(), kj) catch {
            self.err = true;
            return;
        };
        buf.append(self.a(), '}') catch {
            self.err = true;
            return;
        };
        self.pushKey(buf.items, true);
    }
    /// Type `text` (a keyDown+keyUp per Unicode scalar) on the keyboard device.
    pub fn sendKeys(self: *Actions, text: []const u8) *Actions {
        var view = std.unicode.Utf8View.init(text) catch {
            self.err = true;
            return self;
        };
        var it = view.iterator();
        while (it.nextCodepointSlice()) |slice| {
            self.keyEvent("keyDown", slice);
            self.keyEvent("keyUp", slice);
        }
        return self;
    }
    /// Insert a pause (ms) on the pointer device.
    pub fn pauseMs(self: *Actions, duration_ms: i64) *Actions {
        var buf: [64]u8 = undefined;
        const j = std.fmt.bufPrint(&buf, "{{\"type\":\"pause\",\"duration\":{d}}}", .{duration_ms}) catch return self;
        self.pushPointer(j, false);
        return self;
    }

    /// The W3C `actions` array body this builder has accumulated, as an owned
    /// slice (a device sub-array is emitted only when it holds a real action).
    /// Exposed so a caller (or a test) can inspect the wire shape without a
    /// browser.
    pub fn build(self: *Actions) Error![]u8 {
        if (self.err) return Error.OutOfMemory;
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(self.a());
        out.append(self.a(), '[') catch return Error.OutOfMemory;
        var wrote = false;
        if (self.pointer_has_real) {
            out.appendSlice(self.a(), "{\"type\":\"pointer\",\"id\":\"mouse\",\"parameters\":{\"pointerType\":\"mouse\"},\"actions\":[") catch return Error.OutOfMemory;
            out.appendSlice(self.a(), self.pointer.items) catch return Error.OutOfMemory;
            out.appendSlice(self.a(), "]}") catch return Error.OutOfMemory;
            wrote = true;
        }
        if (self.key_has_real) {
            if (wrote) out.append(self.a(), ',') catch return Error.OutOfMemory;
            out.appendSlice(self.a(), "{\"type\":\"key\",\"id\":\"keyboard\",\"actions\":[") catch return Error.OutOfMemory;
            out.appendSlice(self.a(), self.key.items) catch return Error.OutOfMemory;
            out.appendSlice(self.a(), "]}") catch return Error.OutOfMemory;
        }
        out.append(self.a(), ']') catch return Error.OutOfMemory;
        return out.toOwnedSlice(self.a()) catch Error.OutOfMemory;
    }

    /// Post the queued gestures as one `actions` command. A no-op when nothing
    /// but pauses was queued. Consumes/cleans the builder.
    pub fn perform(self: *Actions) Error!void {
        defer self.deinit();
        if (!self.pointer_has_real and !self.key_has_real) return;
        const arr = try self.build();
        defer self.a().free(arr);
        try self.driver.performActions(arr);
    }
};

// ---- Wait: the explicit-wait convenience tier ----

/// The default poll cadence between condition checks (mainstream's 500ms).
pub const default_poll_ms: u64 = 500;

/// A configured waiter over a driver. Obtain one from `WebDriver.wait`, then
/// call `until` (or a `waitFor*` helper on `WebDriver`). The poll loop lives
/// here in the binding — the engine issues single commands and holds no thread,
/// exactly as the reference waits do. On timeout the wait returns
/// `error.WebDriver` of kind `.timeout`.
pub const Wait = struct {
    driver: *WebDriver,
    timeout_ms: u64,
    poll_ms: u64 = default_poll_ms,

    /// Override the poll cadence (default `default_poll_ms`). A zero interval is
    /// clamped up to the default.
    pub fn pollEvery(self: Wait, interval_ms: u64) Wait {
        var w = self;
        w.poll_ms = if (interval_ms == 0) default_poll_ms else interval_ms;
        return w;
    }

    /// Poll `condition(driver, ctx)` until it returns `Ok(true)`; then return.
    /// A NoSuchElement error from the condition is swallowed and retried (a
    /// not-yet-present element should wait, not fail), as the mainstream
    /// `ignored_exceptions` default does; any other error propagates. On
    /// timeout, `error.WebDriver` of kind `.timeout`.
    pub fn until(self: Wait, ctx: *anyopaque, condition: *const fn (*WebDriver, *anyopaque) Error!bool) Error!void {
        return self.poll(ctx, condition, true);
    }

    /// Poll until `condition` returns `Ok(false)` (or an ignored NoSuchElement,
    /// which counts as "gone"); then return. On timeout, kind `.timeout`.
    pub fn untilNot(self: Wait, ctx: *anyopaque, condition: *const fn (*WebDriver, *anyopaque) Error!bool) Error!void {
        return self.poll(ctx, condition, false);
    }

    fn poll(self: Wait, ctx: *anyopaque, condition: *const fn (*WebDriver, *anyopaque) Error!bool, want: bool) Error!void {
        var elapsed: u64 = 0;
        while (true) {
            const got: ?bool = condition(self.driver, ctx) catch |e| blk: {
                if (e == Error.WebDriver) {
                    if (self.driver.last) |l| {
                        if (l.kind == .no_such_element) break :blk if (want) @as(?bool, null) else @as(?bool, true);
                    }
                }
                return e;
            };
            if (got) |g| {
                if (g == want) return;
            }
            if (elapsed >= self.timeout_ms) {
                self.driver.setLast(21, self.driver.allocator.dupe(u8, "waited for condition") catch "");
                return Error.WebDriver;
            }
            std.Thread.sleep(self.poll_ms * std.time.ns_per_ms);
            elapsed += self.poll_ms;
        }
    }
};

test {
    _ = @import("ffi_test.zig");
}
