//! Build for the Zig binding.
//!
//! This binding LINKS the engine (like Go's cgo and Nim), so
//! libselenium_core.so must exist at *build* time. Below tells the linker where
//! it is AND bakes an rpath so the binary finds it at run time without
//! LD_LIBRARY_PATH.
//!
//! Engine search order (first hit wins), mirroring rust/build.rs:
//!   1. -Dengine=/abs/path/to/libselenium_core.so  — what .tests.ae passes
//!      (the artifact path aeb published for core/.build.ae).
//!   2. $SELENIUM_CORE_LIB — the same env var every other binding honours.
//!   3. zig/native/  — a staged local copy (a distributable build).
//!   4. the shared fetch cache: $XDG_CACHE_HOME/selaenium/<tag>/ (or the OS
//!      default — ~/Library/Caches on macOS, ~/.cache elsewhere), populated by
//!      scripts/fetch-engine.sh so a dev with no Aether toolchain runs that
//!      once, then `zig build` just works.
//!   5. ../selenium_core/native/ — the in-tree monorepo layout.
//!
//! Both a directory and a full path to the .so are accepted for 1 and 2.
//!
//!     zig build test                       # in-tree, engine already built
//!     zig build test -Dengine=/path/to.so  # explicit
//!     zig build live                        # run the live-Chrome test binary

const std = @import("std");

// The engine gh-release tag whose fetch-cache this binding searches (matches
// scripts/fetch-engine.sh's default TAG and every other binding's SELENIUM_CORE_VERSION).
const SELENIUM_CORE_VERSION = "v0.8.0";

pub fn build(b: *std.Build) void {
    assertEngineVersionPinned(b);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engine_opt = b.option([]const u8, "engine", "Path to libselenium_core.so (or its directory)");
    const dirs = engineSearchPath(b, engine_opt);

    // A downstream package can @import("selenium_core").
    _ = b.addModule("selenium", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ---- unit tests (FFI) ----
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    linkEngine(tests, dirs);
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;
    const test_step = b.step("test", "Run the FFI unit tests");
    test_step.dependOn(&run_tests.step);

    // ---- the live-Chrome surface test (an executable, skips if no driver) ----
    const live_mod = b.createModule(.{
        .root_source_file = b.path("src/live_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    live_mod.addImport("selenium", b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const live = b.addExecutable(.{ .name = "selenium-live", .root_module = live_mod });
    linkEngine(live, dirs);
    b.installArtifact(live);
    const run_live = b.addRunArtifact(live);
    run_live.step.dependOn(b.getInstallStep());
    run_live.has_side_effects = true;
    const live_step = b.step("live", "Build and run the live-Chrome surface test");
    live_step.dependOn(&run_live.step);

    // ---- the consumer example ----
    const example_mod = b.createModule(.{
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("selenium", b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const example = b.addExecutable(.{ .name = "selenium-example", .root_module = example_mod });
    linkEngine(example, dirs);
    b.installArtifact(example);
    const run_example = b.addRunArtifact(example);
    run_example.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_example.addArgs(args);
    const example_step = b.step("example", "Build and run the consumer example");
    example_step.dependOn(&run_example.step);
}

// Drift guard: the repo-root SELENIUM_CORE_VERSION file is the single source of
// truth for the libselenium_core release tag. Zig's @embedFile cannot reach a
// parent directory, so this binding keeps the literal SELENIUM_CORE_VERSION above — but
// this build-time check reads the file (build runs from zig/, so the path is
// ../SELENIUM_CORE_VERSION) and panics if the literal drifts from it, so the two
// cannot silently diverge. Every `zig build` (including `zig build test`) runs it.
// Do NOT "fix" a mismatch by editing the file to match — update SELENIUM_CORE_VERSION.
fn assertEngineVersionPinned(b: *std.Build) void {
    const io = b.graph.io;
    const raw = b.build_root.handle.readFileAlloc(
        io,
        "../SELENIUM_CORE_VERSION",
        b.allocator,
        .limited(64),
    ) catch |err| {
        std.debug.panic("reading ../SELENIUM_CORE_VERSION: {s}", .{@errorName(err)});
    };
    const want = std.mem.trim(u8, raw, " \t\r\n");
    if (!std.mem.eql(u8, want, SELENIUM_CORE_VERSION)) {
        std.debug.panic(
            "SELENIUM_CORE_VERSION = \"{s}\", but SELENIUM_CORE_VERSION says \"{s}\" — update the constant in build.zig",
            .{ SELENIUM_CORE_VERSION, want },
        );
    }
}

fn linkEngine(step: *std.Build.Step.Compile, dirs: []const []const u8) void {
    const mod = step.root_module;
    mod.link_libc = true;
    for (dirs) |d| {
        mod.addLibraryPath(.{ .cwd_relative = d });
        mod.addRPath(.{ .cwd_relative = d });
    }
    mod.linkSystemLibrary("selenium_core", .{});
}

fn engineSearchPath(b: *std.Build, engine_opt: ?[]const u8) []const []const u8 {
    const gpa = b.allocator;
    var dirs: std.ArrayList([]const u8) = .empty;

    if (engine_opt) |e| dirs.append(gpa, asDir(e)) catch @panic("OOM");
    if (b.graph.environ_map.get("SELENIUM_CORE_LIB")) |e| {
        if (e.len > 0) dirs.append(gpa, asDir(e)) catch @panic("OOM");
    }
    dirs.append(gpa, b.pathFromRoot("native")) catch @panic("OOM");
    if (fetchCacheDir(b)) |cache| dirs.append(gpa, cache) catch @panic("OOM");
    dirs.append(gpa, b.pathFromRoot("../selenium_core/native")) catch @panic("OOM");

    return dirs.toOwnedSlice(gpa) catch @panic("OOM");
}

// The shared fetch cache dir: $XDG_CACHE_HOME/selaenium/<tag>/ (or the OS
// default — ~/Library/Caches on macOS, ~/.cache elsewhere). Mirrors
// scripts/fetch-engine.sh and rust/build.rs's fetch_cache_dir(). Returns null
// when neither XDG_CACHE_HOME nor HOME is set.
fn fetchCacheDir(b: *std.Build) ?[]const u8 {
    const env = b.graph.environ_map;
    if (env.get("XDG_CACHE_HOME")) |x| {
        if (x.len > 0)
            return std.fs.path.join(b.allocator, &.{ x, "selaenium", SELENIUM_CORE_VERSION }) catch @panic("OOM");
    }
    const home = env.get("HOME") orelse return null;
    if (home.len == 0) return null;
    const sub: []const u8 = switch (@import("builtin").os.tag) {
        .macos => "Library/Caches",
        else => ".cache",
    };
    return std.fs.path.join(b.allocator, &.{ home, sub, "selaenium", SELENIUM_CORE_VERSION }) catch @panic("OOM");
}

fn asDir(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".so") or
        std.mem.endsWith(u8, path, ".dylib") or
        std.mem.endsWith(u8, path, ".dll"))
    {
        return std.fs.path.dirname(path) orelse ".";
    }
    return path;
}
