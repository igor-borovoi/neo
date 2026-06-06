const std = @import("std");

/// Resolve the real path of a shared library, handling GNU linker scripts
/// that Zig's linker cannot parse. Uses pkg-config to find the library
/// directory, then locates the versioned .so file.
fn findNcursesLib(b: *std.Build) ?[]const u8 {
    const io = b.graph.io;

    // Try pkg-config first to get the library directory
    var out_code: u8 = undefined;
    const stdout = b.runAllowFail(
        &.{ "pkg-config", "--variable=libdir", "ncursesw" },
        &out_code,
        .ignore,
    ) catch return null;
    defer b.allocator.free(stdout);

    const libdir = std.mem.trim(u8, stdout, &std.ascii.whitespace);
    if (libdir.len == 0) return null;

    // Check if the .so is a linker script (text file) by reading its first bytes
    const so_path = std.fmt.allocPrint(b.allocator, "{s}/libncursesw.so", .{libdir}) catch return null;
    defer b.allocator.free(so_path);

    var buf: [64]u8 = undefined;
    const head = std.Io.Dir.cwd().readFile(io, so_path, &buf) catch return null;
    // ELF files start with \x7fELF — if so, no workaround needed
    if (head.len >= 4 and std.mem.eql(u8, head[0..4], "\x7fELF")) return null;

    // It's a linker script — find the versioned .so
    const versioned = std.fmt.allocPrint(b.allocator, "{s}/libncursesw.so.6", .{libdir}) catch return null;
    // Verify it exists
    std.Io.Dir.accessAbsolute(io, versioned, .{}) catch {
        b.allocator.free(versioned);
        return null;
    };
    return versioned;
}

/// Build args needed to link ncurses (and tinfo if .so is a linker script).
/// Always includes -lm for libc math routines used by the Zig stdlib.
fn ncursesLinkArgs(b: *std.Build, is_macos: bool) []const []const u8 {
    if (is_macos) return &.{ "-lncurses", "-lm" };
    if (findNcursesLib(b)) |lib_path| {
        return b.allocator.dupe([]const u8, &.{ lib_path, "-ltinfo", "-lm" }) catch @panic("OOM");
    }
    return &.{ "-lncursesw", "-lm" };
}

fn linkNcurses(b: *std.Build, compile: *std.Build.Step.Compile) void {
    const mod = compile.root_module;
    // Windows uses the Win32 console backend; no curses library involved.
    if (compile.rootModuleTarget().os.tag == .windows) return;
    const is_macos = compile.rootModuleTarget().os.tag == .macos;
    if (is_macos) {
        mod.linkSystemLibrary("ncurses", .{});
    } else if (findNcursesLib(b)) |lib_path| {
        mod.addObjectFile(.{ .cwd_relative = lib_path });
        mod.linkSystemLibrary("tinfo", .{});
    } else {
        mod.linkSystemLibrary("ncursesw", .{});
    }
    mod.link_libc = true;
}

/// Build via Zig as far as the object file, then link via system `cc`.
/// Workaround for Linux distros (e.g. Arch w/ GCC 16+) whose CRT objects
/// contain `.sframe` sections that bundled LLD and Zig's self-hosted linker
/// can't relocate. The system linker handles them.
///
/// Returns the LazyPath of the linked executable so callers can install/run it.
fn linuxExeViaCc(b: *std.Build, name: []const u8, mod: *std.Build.Module) std.Build.LazyPath {
    const obj = b.addObject(.{ .name = name, .root_module = mod });
    obj.root_module.link_libc = true;

    const link = b.addSystemCommand(&.{"cc"});
    link.addFileArg(obj.getEmittedBin());
    const out = link.addPrefixedOutputFileArg("-o", name);
    link.addArgs(ncursesLinkArgs(b, false));
    return out;
}

fn addArtifactInstall(b: *std.Build, name: []const u8, src: std.Build.LazyPath) *std.Build.Step.InstallFile {
    return b.addInstallFileWithDir(src, .bin, name);
}

/// Browser build: wasm32-freestanding module plus the static host page,
/// installed together under zig-out/web.
fn addWasmStep(b: *std.Build) void {
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/wasm_main.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = .ReleaseSmall,
    });
    const wasm_exe = b.addExecutable(.{ .name = "neo", .root_module = wasm_module });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const web_dir: std.Build.InstallDir = .{ .custom = "web" };
    const wasm_step = b.step("wasm", "Build the WebAssembly bundle into zig-out/web");
    wasm_step.dependOn(&b.addInstallFileWithDir(wasm_exe.getEmittedBin(), web_dir, "neo.wasm").step);
    wasm_step.dependOn(&b.addInstallFileWithDir(b.path("web/index.html"), web_dir, "index.html").step);
    wasm_step.dependOn(&b.addInstallFileWithDir(b.path("web/neo.js"), web_dir, "neo.js").step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    addWasmStep(b);

    const is_linux = target.result.os.tag == .linux;

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bench_module = b.createModule(.{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (is_linux) {
        // cc-linked binaries
        const exe_path = linuxExeViaCc(b, "neo-zig", root_module);
        const install_exe = addArtifactInstall(b, "neo-zig", exe_path);
        b.getInstallStep().dependOn(&install_exe.step);

        const test_path = linuxExeViaCc(b, "test-neo", test_module);
        const install_test = addArtifactInstall(b, "test-neo", test_path);

        const bench_path = linuxExeViaCc(b, "benchmark-neo", bench_module);
        const install_bench = addArtifactInstall(b, "benchmark-neo", bench_path);

        const run_cmd = std.Build.Step.Run.create(b, "run neo-zig");
        run_cmd.addFileArg(exe_path);
        run_cmd.step.dependOn(&install_exe.step);
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const test_cmd = std.Build.Step.Run.create(b, "run test-neo");
        test_cmd.addFileArg(test_path);
        test_cmd.step.dependOn(&install_test.step);
        const test_step = b.step("test", "Run tests without ncurses");
        test_step.dependOn(&test_cmd.step);

        const bench_cmd = std.Build.Step.Run.create(b, "run benchmark-neo");
        bench_cmd.addFileArg(bench_path);
        bench_cmd.step.dependOn(&install_bench.step);
        if (b.args) |args| bench_cmd.addArgs(args);
        const bench_step = b.step("bench", "Run performance benchmark");
        bench_step.dependOn(&bench_cmd.step);
    } else {
        const exe = b.addExecutable(.{ .name = "neo-zig", .root_module = root_module });
        linkNcurses(b, exe);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const test_exe = b.addExecutable(.{ .name = "test-neo", .root_module = test_module });
        linkNcurses(b, test_exe);
        const test_cmd = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests without ncurses");
        test_step.dependOn(&test_cmd.step);

        const bench_exe = b.addExecutable(.{ .name = "benchmark-neo", .root_module = bench_module });
        linkNcurses(b, bench_exe);
        const bench_cmd = b.addRunArtifact(bench_exe);
        if (b.args) |args| bench_cmd.addArgs(args);
        const bench_step = b.step("bench", "Run performance benchmark");
        bench_step.dependOn(&bench_cmd.step);
    }
}
