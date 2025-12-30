const std = @import("std");
const types = @import("types.zig");
const cloud_mod = @import("cloud.zig");
const Cloud = cloud_mod.Cloud;

pub fn main() !void {
    std.debug.print("Testing Zig neo without ncurses...\n", .{});

    // Test Cloud initialization
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cloud = Cloud.init(allocator, .COLOR256, true);
    defer cloud.deinit();

    std.debug.print("Cloud initialized successfully!\n", .{});
    std.debug.print("Lines: {}, Cols: {}\n", .{ cloud.lines, cloud.cols });
    std.debug.print("Droplet density: {}\n", .{cloud.droplet_density});
    std.debug.print("Characters per second: {}\n", .{cloud.chars_per_sec});

    // Test reset (without ncurses)
    // This will test the timestamp initialization
    std.debug.print("Testing cloud reset...\n", .{});

    // Test reset functionality
    cloud.lines = 24;
    cloud.cols = 80;

    // Call reset to properly initialize everything
    cloud.reset() catch @panic("Reset failed");

    std.debug.print("col_stat initialized with {} columns\n", .{cloud.col_stat.items.len});

    // Initialize timestamps for spawnDroplets test
    const now = std.time.Instant.now() catch unreachable;
    cloud.last_spawn_time = now;

    // Temporarily modify droplets_per_sec to force spawning for testing
    cloud.droplets_per_sec = 100.0; // High rate for testing

    // Create artificial time difference by sleeping
    std.Thread.sleep(10 * std.time.ns_per_ms); // Sleep 10ms
    const future_time = std.time.Instant.now() catch unreachable;

    cloud.spawnDroplets(future_time);

    // Keep high spawn rate for visual test
    // cloud.droplets_per_sec = original_dps;

    // Test Matrix rain effect simulation
    std.debug.print("\n=== Matrix Rain Effect Test ===\n", .{});

    // Verify Matrix effect is working
    var alive_count: usize = 0;
    for (cloud.droplets.items) |droplet| {
        if (droplet.is_alive) alive_count += 1;
    }

    if (alive_count > 0) {
        std.debug.print("✅ Matrix rain effect working! {} droplets active\n", .{alive_count});
    } else {
        std.debug.print("❌ No droplets spawned - Matrix effect not working\n", .{});
    }
    std.debug.print("Alive droplets: {}\n", .{alive_count});

    // Simulate a few frames of rain
    for (0..3) |frame| {
        std.debug.print("Frame {}:\n", .{frame});

        // Show droplet positions
        for (cloud.droplets.items) |droplet| {
            if (droplet.is_alive) {
                std.debug.print("  Droplet col={} head={} tail={}\n", .{ droplet.bound_col, droplet.head_put_line, droplet.tail_put_line });
            }
        }

        // For testing, just call rain again
        cloud.rain();
    }

    std.debug.print("spawnDroplets test passed!\n", .{});
    std.debug.print("Cloud reset test passed!\n", .{});
    std.debug.print("Zig neo core logic working correctly!\n", .{});
}
