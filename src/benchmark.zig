const std = @import("std");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE_EXTENDED", "1");
    @cInclude("locale.h");
    @cInclude("ncurses.h");
});

const types = @import("types.zig");
const Cloud = @import("cloud.zig").Cloud;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var num_frames: usize = 100;
    var warmup_frames: usize = 10;
    var use_ncurses: bool = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--frames")) {
            i += 1;
            if (i < args.len) {
                num_frames = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (std.mem.eql(u8, args[i], "--warmup")) {
            i += 1;
            if (i < args.len) {
                warmup_frames = try std.fmt.parseInt(usize, args[i], 10);
            }
        } else if (std.mem.eql(u8, args[i], "--ncurses")) {
            use_ncurses = true;
        }
    }

    if (use_ncurses) {
        try runNcursesBenchmark(allocator, num_frames, warmup_frames);
    } else {
        try runHeadlessBenchmark(allocator, num_frames, warmup_frames);
    }
}

fn runHeadlessBenchmark(allocator: std.mem.Allocator, num_frames: usize, warmup_frames: usize) !void {
    std.debug.print("=== Headless Benchmark (no ncurses rendering) ===\n", .{});
    std.debug.print("Frames: {} (warmup: {})\n", .{ num_frames, warmup_frames });
    std.debug.print("Simulated terminal: 160x45\n\n", .{});

    var cloud = Cloud.init(allocator, .COLOR256, false);
    defer cloud.deinit();

    // First reset (will use default 24x80 since ncurses isn't initialized)
    try cloud.reset();

    // Now set our desired terminal size and reconfigure
    cloud.lines = 45;
    cloud.cols = 160;

    // Recalculate droplets_per_sec for new size
    const time_to_fill_screen = @as(f32, @floatFromInt(cloud.lines)) / cloud.chars_per_sec;
    cloud.droplets_per_sec = @as(f32, @floatFromInt(cloud.cols)) * cloud.droplet_density / time_to_fill_screen;

    // Resize droplets array for new terminal size
    const num_droplets = @as(usize, @intFromFloat(@round(2.0 * @as(f32, @floatFromInt(cloud.cols)))));
    try cloud.droplets.resize(allocator, num_droplets);
    for (cloud.droplets.items) |*droplet| {
        droplet.reset();
    }
    try cloud.active_droplets.resize(allocator, num_droplets);
    cloud.active_droplets.clearRetainingCapacity();

    // Reinitialize column status
    try cloud.col_stat.resize(allocator, cloud.cols);
    for (0..cloud.cols) |i| {
        cloud.col_stat.items[i] = types.ColumnStatus{};
    }

    cloud.raining = true;

    // Simulate 50ms per frame (20 FPS)
    const frame_time_ns: u64 = 50_000_000;
    var cur_time = std.time.Instant.now() catch unreachable;
    cloud.last_spawn_time = cur_time;

    std.debug.print("Running warmup... ", .{});
    for (0..warmup_frames) |_| {
        cloud.rain();
        std.Thread.sleep(frame_time_ns);
        cur_time = std.time.Instant.now() catch unreachable;
        cloud.last_spawn_time = cur_time;
    }
    std.debug.print("done\n", .{});

    std.debug.print("Running benchmark... ", .{});
    const start_time = std.time.Instant.now() catch unreachable;

    for (0..num_frames) |_| {
        cloud.rain();
        std.Thread.sleep(frame_time_ns);
        cur_time = std.time.Instant.now() catch unreachable;
        cloud.last_spawn_time = cur_time;
    }

    const end_time = std.time.Instant.now() catch unreachable;
    std.debug.print("done\n\n", .{});

    const total_ns = end_time.since(start_time);
    const total_ms = @as(f64, @floatFromInt(total_ns)) / 1_000_000.0;
    const actual_frame_time_ms = total_ms / @as(f64, @floatFromInt(num_frames));

    // Subtract sleep time to get actual processing time
    const sleep_time_ms = @as(f64, @floatFromInt(frame_time_ns)) / 1_000_000.0;
    const processing_time_ms = actual_frame_time_ms - sleep_time_ms;
    const processing_time_ns = @as(u64, @intFromFloat(processing_time_ms * 1_000_000.0));

    std.debug.print("=== Results ===\n", .{});
    std.debug.print("Total time: {d:.2} ms\n", .{total_ms});
    std.debug.print("Actual frame time: {d:.3} ms (includes {d:.1}ms sleep)\n", .{ actual_frame_time_ms, sleep_time_ms });
    std.debug.print("Processing time per frame: {d:.3} ms ({d} ns)\n", .{ processing_time_ms, processing_time_ns });
    std.debug.print("Effective FPS (processing only): {d:.1}\n", .{1000.0 / processing_time_ms});
    std.debug.print("Active droplets: {}\n", .{cloud.active_droplets.items.len});
}

fn runNcursesBenchmark(allocator: std.mem.Allocator, num_frames: usize, warmup_frames: usize) !void {
    _ = c.setlocale(c.LC_ALL, "");
    _ = c.initscr();
    _ = c.cbreak();
    _ = c.noecho();
    _ = c.curs_set(0);
    _ = c.nodelay(c.stdscr, true);
    _ = c.keypad(c.stdscr, true);

    defer _ = c.endwin();

    std.debug.print("=== Ncurses Benchmark (with rendering) ===\n", .{});
    std.debug.print("Frames: {} (warmup: {})\n", .{ num_frames, warmup_frames });
    std.debug.print("Terminal: {}x{}\n\n", .{ c.COLS, c.LINES });

    var cloud = Cloud.init(allocator, .COLOR256, false);
    defer cloud.deinit();
    try cloud.reset();
    try cloud.setColor(.GREEN);
    cloud.raining = true;

    var cur_time = std.time.Instant.now() catch unreachable;

    std.debug.print("Running warmup... ", .{});
    for (0..warmup_frames) |_| {
        cloud.rain();
        _ = c.refresh();
        cur_time = std.time.Instant.now() catch unreachable;
        cloud.last_spawn_time = cur_time;
        std.Thread.sleep(16_000_000);
    }
    std.debug.print("done\n", .{});

    _ = c.mvprintw(0, 0, "Benchmarking...");
    _ = c.refresh();

    std.debug.print("Running benchmark... ", .{});
    const start_time = std.time.Instant.now() catch unreachable;

    for (0..num_frames) |_| {
        cloud.rain();
        _ = c.refresh();
        cur_time = std.time.Instant.now() catch unreachable;
        cloud.last_spawn_time = cur_time;
        std.Thread.sleep(16_000_000);
    }

    const end_time = std.time.Instant.now() catch unreachable;
    std.debug.print("done\n\n", .{});

    _ = c.endwin();

    const total_ns = end_time.since(start_time);
    const total_ms = @as(f64, @floatFromInt(total_ns)) / 1_000_000.0;
    const fps = @as(f64, @floatFromInt(num_frames)) / (total_ms / 1000.0);
    const ms_per_frame = total_ms / @as(f64, @floatFromInt(num_frames));
    const ns_per_frame = total_ns / num_frames;

    std.debug.print("=== Results ===\n", .{});
    std.debug.print("Total time: {d:.2} ms\n", .{total_ms});
    std.debug.print("Time per frame: {d:.3} ms ({d} ns)\n", .{ ms_per_frame, ns_per_frame });
    std.debug.print("Effective FPS: {d:.1}\n", .{fps});
    std.debug.print("Active droplets: {}\n", .{cloud.active_droplets.items.len});
    std.debug.print("Note: Includes 16ms sleep per frame for realistic timing\n", .{});
}
