const std = @import("std");

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

    exe.linkSystemLibrary("ncursesw");
    exe.linkLibC();

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

    test_exe.linkSystemLibrary("ncursesw");
    test_exe.linkLibC();

    const test_cmd = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run tests without ncurses");
    test_step.dependOn(&test_cmd.step);
}
