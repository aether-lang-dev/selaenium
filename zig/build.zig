//! Build for the Zig binding.
//!
//! This binding LINKS the engine (like Go's cgo and Nim), so
//! libselenium_core.so must exist at *build* time. Below tells the linker where
//! it is AND bakes an rpath so the binary finds it at run time without
//! LD_LIBRARY_PATH.
//!
//! Engine search order (first hit wins):
//!   1. -Dengine=/abs/path/to/libselenium_core.so  — what .tests.ae passes
//!      (the artifact path aeb published for core/.build.ae).
//!   2. $SELENIUM_CORE_LIB — the same env var every other binding honours.
//!   3. zig/native/  — a staged local copy (a distributable build).
//!   4. ../selenium_core/native/ — the in-tree monorepo layout.
//!
//! Both a directory and a full path to the .so are accepted for 1 and 2.
//!
//!     zig build test                       # in-tree, engine already built
//!     zig build test -Dengine=/path/to.so  # explicit
//!     zig build live                        # run the live-Chrome test binary

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const engine_opt = b.option([]const u8, "engine", "Path to libselenium_core.so (or its directory)");
    const dirs = engineSearchPath(b, engine_opt);

    // A downstream package can @import("selenium_core").
    _ = b.addModule("selenium_core", .{
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
    live_mod.addImport("selenium_core", b.createModule(.{
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
    example_mod.addImport("selenium_core", b.createModule(.{
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
    dirs.append(gpa, b.pathFromRoot("../selenium_core/native")) catch @panic("OOM");

    return dirs.toOwnedSlice(gpa) catch @panic("OOM");
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
