const std = @import("std");

/// Resolve the real path of a shared library, handling GNU linker scripts
/// that Zig's linker cannot parse. Uses pkg-config to find the library
/// directory, then locates the versioned .so file.
fn findNcursesLib(allocator: std.mem.Allocator) ?[]const u8 {
    // Try pkg-config first to get the library directory
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "pkg-config", "--variable=libdir", "ncursesw" },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const libdir = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    if (libdir.len == 0) return null;

    // Check if the .so is a linker script (text file) by trying to open and read it
    const so_path = std.fmt.allocPrint(allocator, "{s}/libncursesw.so", .{libdir}) catch return null;
    defer allocator.free(so_path);

    if (std.fs.cwd().openFile(so_path, .{})) |file| {
        defer file.close();
        var buf: [64]u8 = undefined;
        const n = file.read(&buf) catch return null;
        // ELF files start with \x7fELF — if not, it's likely a linker script
        if (n >= 4 and std.mem.eql(u8, buf[0..4], "\x7fELF")) {
            return null; // Real ELF, no workaround needed
        }
    } else |_| {
        return null;
    }

    // It's a linker script — find the versioned .so
    const versioned = std.fmt.allocPrint(allocator, "{s}/libncursesw.so.6", .{libdir}) catch return null;
    // Verify it exists
    std.fs.cwd().access(versioned, .{}) catch {
        allocator.free(versioned);
        return null;
    };
    return versioned;
}

fn linkNcurses(b: *std.Build, compile: *std.Build.Step.Compile) void {
    if (findNcursesLib(b.allocator)) |lib_path| {
        // Linker script detected — link versioned .so directly + tinfo
        compile.addObjectFile(.{ .cwd_relative = lib_path });
        compile.linkSystemLibrary("tinfo");
    } else {
        // Normal system — pkg-config or plain -lncursesw works fine
        compile.linkSystemLibrary("ncursesw");
    }
    compile.linkLibC();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "neo-zig",
        .root_module = root_module,
    });

    linkNcurses(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step (needs ncurses for Cloud)
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_exe = b.addExecutable(.{
        .name = "test-neo",
        .root_module = test_module,
    });

    linkNcurses(b, test_exe);

    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests without ncurses");
    test_step.dependOn(&test_cmd.step);
}
