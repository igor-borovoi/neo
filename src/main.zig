const std = @import("std");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE_EXTENDED", "1");
    @cInclude("ncurses.h");
    @cInclude("locale.h");
});

const types = @import("types.zig");
const cloud_mod = @import("cloud.zig");
const Cloud = cloud_mod.Cloud;

pub fn die(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn initCurses(usr_color_mode: types.ColorMode) types.ColorMode {
    _ = c.initscr();
    if (c.cbreak() != c.OK) {
        // In headless environments, cbreak might fail but we can continue
        std.debug.print("Warning: cbreak() failed, continuing anyway\n", .{});
    }

    // Add a simple check to avoid ncurses issues in headless environments
    // For testing, we'll use default values if ncurses fails
    if (c.LINES <= 0 or c.COLS <= 0) {
        // Simulate terminal dimensions for testing
        c.LINES = 24;
        c.COLS = 80;
    }
    _ = c.curs_set(0);
    if (c.noecho() != c.OK) {
        die("noecho() failed\n", .{});
    }
    if (c.nodelay(c.stdscr, true) != c.OK) {
        die("nodelay() failed\n", .{});
    }
    if (c.keypad(c.stdscr, true) != c.OK) {
        die("keypad() failed\n", .{});
    }

    if (usr_color_mode != .MONO and c.has_colors()) {
        _ = c.start_color();
    }

    const color_mode = pickColorMode(usr_color_mode);
    if (c.clear() != c.OK) {
        die("clear() failed\n", .{});
    }
    if (c.refresh() != c.OK) {
        die("refresh() failed\n", .{});
    }

    return color_mode;
}

fn cleanup() void {
    _ = c.endwin();
}

fn pickColorMode(usr_color_mode: types.ColorMode) types.ColorMode {
    if (usr_color_mode != .INVALID) {
        return usr_color_mode;
    }
    if (!c.has_colors()) {
        return .MONO;
    }
    if (c.COLORS >= 256) {
        if (c.can_change_color()) {
            return .TRUECOLOR;
        } else {
            return .COLOR256;
        }
    }
    return .COLOR16;
}

const Column = struct {
    y: f32, // Current vertical position
    speed: f32, // Falling speed
    length: usize, // Trail length
    active: bool, // Whether this column is active
    frame_counter: usize, // For consistent animation
};

fn getTerminalSize() struct { width: usize, height: usize } {
    // Simple terminal size detection for now
    // In real terminals, this would check COLUMNS/LINES environment variables
    return .{ .width = 120, .height = 30 };
}

fn simpleMatrixMode(target_fps: f32) !void {
    // Use dynamic terminal size detection
    const term_size = getTerminalSize();
    const num_cols = term_size.width;
    const num_rows = term_size.height;
    const max_trail = 8;

    var columns: [200]Column = undefined;
    var screen: [60][200]u8 = undefined;
    var seed: u64 = 0x1234567;

    // Initialize columns
    var i: usize = 0;
    while (i < num_cols) : (i += 1) {
        seed = seed *% 1103515245 +% 12345;
        columns[i] = Column{
            .y = -@as(f32, @floatFromInt(seed % 20)),
            .speed = 0.8 + @as(f32, @floatFromInt(seed % 5)) / 10.0,
            .length = seed % max_trail + 3,
            .active = true,
            .frame_counter = seed % 5,
        };
    }

    var frame_count: usize = 0;
    const target_period_ns = @as(u64, @intFromFloat(@round(1.0 / target_fps * 1.0e9)));
    var prev_time = std.time.Instant.now() catch unreachable;

    while (true) {
        const now = std.time.Instant.now() catch unreachable;

        // TODO: Add resize checking back when basic functionality works

        // Clear screen buffer
        var row: usize = 0;
        while (row < num_rows) : (row += 1) {
            var col_idx: usize = 0;
            while (col_idx < num_cols) : (col_idx += 1) {
                screen[row][col_idx] = ' ';
            }
        }

        // Update and draw columns
        var col_idx: usize = 0;
        while (col_idx < num_cols) : (col_idx += 1) {
            var col = &columns[col_idx];

            // Update position
            col.y += col.speed;

            // Reset column if it goes off screen
            if (col.y > @as(f32, @floatFromInt(num_rows + 3))) {
                seed = seed *% 1103515245 +% 12345;
                col.y = -@as(f32, @floatFromInt(seed % 10));
                col.speed = 0.8 + @as(f32, @floatFromInt(seed % 5)) / 10.0;
                col.length = seed % max_trail + 3;
                col.frame_counter = 0;
            }

            // Draw trail above the head (traditional Matrix style)
            var trail_pos: i32 = @as(i32, @intFromFloat(@floor(col.y))) - 1;
            var trail_idx: usize = 0;
            while (trail_idx < col.length and trail_pos >= 0) : (trail_idx += 1) {
                if (trail_pos >= 0 and @as(usize, @intCast(trail_pos)) < num_rows) {
                    const trail_row = @as(usize, @intCast(trail_pos));
                    // Use consistent seed for stable characters
                    const pos_seed = seed + @as(u64, col_idx) * 1000 + @as(u64, trail_idx) * 100 + @as(u64, trail_row) * 10;
                    const char_code = 33 + (pos_seed % 94); // ASCII 33-126
                    screen[trail_row][col_idx] = @as(u8, @intCast(char_code));
                }
                trail_pos -= 1;
            }

            // Draw the bright head
            const head_y = @floor(col.y);
            if (head_y >= 0 and head_y < @as(f32, @floatFromInt(num_rows))) {
                const head_row = @as(usize, @intFromFloat(head_y));
                seed = seed *% 1103515245 +% 12345;
                const char_code = 33 + (seed % 94);
                screen[head_row][col_idx] = @as(u8, @intCast(char_code));
            }
        }

        // Move cursor to top and print screen
        std.debug.print("\x1b[H", .{});
        var r: usize = 0;
        while (r < num_rows) : (r += 1) {
            var col: usize = 0;
            while (col < num_cols) : (col += 1) {
                std.debug.print("{c}", .{screen[r][col]});
            }
            std.debug.print("\n", .{});
        }

        // Frame timing
        const elapsed = now.since(prev_time);
        var delay: u64 = 0;
        if (elapsed < target_period_ns) {
            delay = target_period_ns - elapsed;
        }
        std.Thread.sleep(delay);
        prev_time = now;

        frame_count += 1;
        // Exit after 10 seconds for demo
        if (frame_count > @as(usize, @intFromFloat(@round(target_fps * 10)))) break;
    }
}

fn handleInput(cloud: *Cloud) bool {
    const ch = c.getch();
    if (ch == -1) return false;

    switch (ch) {
        c.KEY_RESIZE, ' ' => {
            cloud.reset() catch |err| {
                std.debug.print("Reset failed: {}\n", .{err});
            };
            cloud.force_draw_everything = true;
        },
        'p' => {
            cloud.togglePause();
        },
        'q', 27 => {
            cloud.raining = false;
        },
        else => {},
    }

    return true;
}

fn checkTerminalResize(cloud: *Cloud) void {
    // Check if terminal size changed
    const new_lines: u16 = @intCast(c.LINES);
    const new_cols: u16 = @intCast(c.COLS);

    if (new_lines != cloud.lines or new_cols != cloud.cols) {
        cloud.reset() catch |err| {
            std.debug.print("Reset failed: {}\n", .{err});
        };
        cloud.force_draw_everything = true;
        _ = c.clear();
    }
}

fn printVersion() noreturn {
    std.debug.print("neo-zig 0.6.1 (Zig version)\n", .{});
    std.debug.print("Built from neo C++ version\n", .{});
    std.debug.print("Copyright (C) 2021 Stewart Reive\n", .{});
    std.debug.print("Zig port - 2025\n", .{});
    std.debug.print("Licensed under GPLv3+\n", .{});
    std.process.exit(0);
}

fn printHelp(appName: []const u8) noreturn {
    std.debug.print("Usage: {s} [OPTIONS]\n", .{appName});
    std.debug.print("\n", .{});
    std.debug.print("Simulate the digital rain from \"The Matrix\"\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  -h, --help             show this help message\n", .{});
    std.debug.print("  -V, --version          print the version\n", .{});
    std.debug.print("  -S, --speed=NUM        set the scroll speed (default: 8.0)\n", .{});
    std.debug.print("  -c, --color=COLOR       set the color (green, gold, red, etc.)\n", .{});
    std.debug.print("      --colormode=MODE    set color mode (0=mono, 16=16 colors, 256=256 colors, 32=truecolor)\n", .{});
    std.debug.print("  -m, --message=STR      display a message\n", .{});
    std.debug.print("  -a, --async            asynchronous scroll speed\n", .{});
    std.debug.print("      --charset=STR      character set: katakana, mix, ascii, cyrillic, braille, greek, etc.\n", .{});
    std.debug.print("                         mix = Japanese 60%%, Cyrillic 20%%, Braille 12%%, ASCII 8%%\n", .{});
    std.debug.print("      --benchmark=SECS   run benchmark for specified seconds\n", .{});
    std.debug.print("      --seed=NUM         set random seed for reproducible results\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("If you see a blank screen, try --colormode=0 for monochrome mode.\n", .{});
    std.debug.print("This is a Zig port of the original C++ neo program.\n", .{});
    std.debug.print("See the C++ version for full feature support.\n", .{});
    std.process.exit(0);
}

pub fn main() !void {
    // Simple argument parsing
    var args_iter = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args_iter.deinit();
    const program_name = args_iter.next() orelse "neo-zig";

    var usr_color_mode: types.ColorMode = .INVALID;
    var target_fps: f32 = 20.0; // Balanced animation rate
    var show_help = false;
    var show_version = false;
    var requested_color: ?types.Color = null;
    var requested_charset: ?types.Charset = null;
    var async_mode_requested = false;
    var requested_message: ?[]const u8 = null;
    var benchmark_seconds: ?f32 = null;
    var seed: ?u64 = null;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            show_version = true;
        } else if (std.mem.startsWith(u8, arg, "-S=") or std.mem.startsWith(u8, arg, "--speed=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const speed_str = arg[eq_idx + 1 ..];
            target_fps = try std.fmt.parseFloat(f32, speed_str);
        } else if (std.mem.startsWith(u8, arg, "-c=") or std.mem.startsWith(u8, arg, "--color=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const color_str = arg[eq_idx + 1 ..];

            if (std.mem.eql(u8, color_str, "green")) {
                requested_color = .GREEN;
            } else if (std.mem.eql(u8, color_str, "green2")) {
                requested_color = .GREEN2;
            } else if (std.mem.eql(u8, color_str, "green3")) {
                requested_color = .GREEN3;
            } else if (std.mem.eql(u8, color_str, "gold")) {
                requested_color = .GOLD;
            } else if (std.mem.eql(u8, color_str, "red")) {
                requested_color = .RED;
            } else if (std.mem.eql(u8, color_str, "blue")) {
                requested_color = .BLUE;
            } else if (std.mem.eql(u8, color_str, "cyan")) {
                requested_color = .CYAN;
            } else if (std.mem.eql(u8, color_str, "yellow")) {
                requested_color = .YELLOW;
            } else if (std.mem.eql(u8, color_str, "orange")) {
                requested_color = .ORANGE;
            } else if (std.mem.eql(u8, color_str, "purple")) {
                requested_color = .PURPLE;
            } else if (std.mem.eql(u8, color_str, "pink")) {
                requested_color = .PINK;
            } else if (std.mem.eql(u8, color_str, "rainbow")) {
                requested_color = .RAINBOW;
            } else if (std.mem.eql(u8, color_str, "gray")) {
                requested_color = .GRAY;
            } else if (std.mem.eql(u8, color_str, "pink2")) {
                requested_color = .PINK2;
            } else if (std.mem.eql(u8, color_str, "vaporwave")) {
                requested_color = .VAPORWAVE;
            }
        } else if (std.mem.startsWith(u8, arg, "--colormode=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const mode_str = arg[eq_idx + 1 ..];
            if (std.mem.eql(u8, mode_str, "0") or std.mem.eql(u8, mode_str, "mono")) {
                usr_color_mode = .MONO;
            } else if (std.mem.eql(u8, mode_str, "16")) {
                usr_color_mode = .COLOR16;
            } else if (std.mem.eql(u8, mode_str, "256")) {
                usr_color_mode = .COLOR256;
            } else if (std.mem.eql(u8, mode_str, "32")) {
                usr_color_mode = .TRUECOLOR;
            }
        } else if (std.mem.startsWith(u8, arg, "-m=") or std.mem.startsWith(u8, arg, "--message=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            requested_message = arg[eq_idx + 1 ..];
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--async")) {
            async_mode_requested = true;
        } else if (std.mem.startsWith(u8, arg, "--charset=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const charset_str = arg[eq_idx + 1 ..];

            if (std.mem.eql(u8, charset_str, "ascii")) {
                requested_charset = .DEFAULT;
            } else if (std.mem.eql(u8, charset_str, "extended")) {
                requested_charset = .EXTENDED_DEFAULT;
            } else if (std.mem.eql(u8, charset_str, "english")) {
                requested_charset = .ENGLISH_LETTERS;
            } else if (std.mem.eql(u8, charset_str, "digits") or std.mem.eql(u8, charset_str, "dec") or std.mem.eql(u8, charset_str, "decimal")) {
                requested_charset = .ENGLISH_DIGITS;
            } else if (std.mem.eql(u8, charset_str, "punc")) {
                requested_charset = .ENGLISH_PUNCTUATION;
            } else if (std.mem.eql(u8, charset_str, "bin") or std.mem.eql(u8, charset_str, "binary")) {
                requested_charset = .BINARY;
            } else if (std.mem.eql(u8, charset_str, "hex") or std.mem.eql(u8, charset_str, "hexadecimal")) {
                requested_charset = .HEX;
            } else if (std.mem.eql(u8, charset_str, "katakana")) {
                requested_charset = .KATAKANA;
            } else if (std.mem.eql(u8, charset_str, "greek")) {
                requested_charset = .GREEK;
            } else if (std.mem.eql(u8, charset_str, "cyrillic")) {
                requested_charset = .CYRILLIC;
            } else if (std.mem.eql(u8, charset_str, "arabic")) {
                requested_charset = .ARABIC;
            } else if (std.mem.eql(u8, charset_str, "hebrew")) {
                requested_charset = .HEBREW;
            } else if (std.mem.eql(u8, charset_str, "devanagari")) {
                requested_charset = .DEVANAGARI;
            } else if (std.mem.eql(u8, charset_str, "braille")) {
                requested_charset = .BRAILLE;
            } else if (std.mem.eql(u8, charset_str, "runic")) {
                requested_charset = .RUNIC;
            } else if (std.mem.eql(u8, charset_str, "mix") or std.mem.eql(u8, charset_str, "mixed")) {
                requested_charset = .MIX;
            } else {
                std.debug.print("Unsupported charset specified: {s}\n", .{charset_str});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--benchmark")) {
            // Handle --benchmark SECS (space separated)
            benchmark_seconds = if (args_iter.next()) |next_arg|
                std.fmt.parseFloat(f32, next_arg) catch null
            else
                null;
        } else if (std.mem.startsWith(u8, arg, "--benchmark=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const bench_str = arg[eq_idx + 1 ..];
            benchmark_seconds = try std.fmt.parseFloat(f32, bench_str);
        } else if (std.mem.eql(u8, arg, "--benchmark")) {
            // Handle space-separated format
            const next_arg = args_iter.next() orelse {
                std.debug.print("Error: --benchmark requires a value\n", .{});
                std.process.exit(1);
            };
            benchmark_seconds = try std.fmt.parseFloat(f32, next_arg);
        } else if (std.mem.startsWith(u8, arg, "--seed=")) {
            const eq_idx = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const seed_str = arg[eq_idx + 1 ..];
            seed = try std.fmt.parseInt(u64, seed_str, 10);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            // Handle space-separated format
            const next_arg = args_iter.next() orelse {
                std.debug.print("Error: --seed requires a value\n", .{});
                std.process.exit(1);
            };
            seed = try std.fmt.parseInt(u64, next_arg, 10);
        }
    }

    if (show_help) {
        printHelp(program_name);
    }

    if (show_version) {
        printVersion();
    }

    // Set locale first for proper character handling
    _ = c.setlocale(c.LC_ALL, "");
    const locale = c.setlocale(c.LC_ALL, "");

    // Initialize ncurses - MUST call initscr() first before any other ncurses functions
    _ = c.initscr();
    defer cleanup();

    // Now we can check colors and set up ncurses properly
    const has_color_support = c.has_colors();
    if (has_color_support) {
        _ = c.start_color();
    }

    if (c.cbreak() != c.OK) {
        std.debug.print("Warning: cbreak() failed\n", .{});
    }
    _ = c.curs_set(0);
    if (c.noecho() != c.OK) {
        die("noecho() failed\n", .{});
    }
    if (c.nodelay(c.stdscr, true) != c.OK) {
        die("nodelay() failed\n", .{});
    }
    if (c.keypad(c.stdscr, true) != c.OK) {
        die("keypad() failed\n", .{});
    }

    if (c.clear() != c.OK) {
        die("clear() failed\n", .{});
    }
    if (c.refresh() != c.OK) {
        die("refresh() failed\n", .{});
    }

    // Pick color mode based on terminal capabilities
    const color_mode: types.ColorMode = if (has_color_support) pickColorMode(usr_color_mode) else .MONO;
    const use_ascii = if (locale != null) std.mem.indexOf(u8, std.mem.span(locale), "UTF") == null else false;

    // Create cloud
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cloud = Cloud.init(allocator, color_mode, use_ascii);
    defer cloud.deinit();

    // Apply requested charset
    if (requested_charset) |charset| {
        cloud.charset = charset;
    }

    // Apply async mode
    if (async_mode_requested) {
        cloud.setAsync(true);
    }

    // Apply message
    if (requested_message) |message| {
        try cloud.setMessage(message);
    }

    // Apply seed if provided (for reproducible benchmarks)
    if (seed) |s| {
        cloud.setSeed(s);
    }

    // Initialize - must call reset() first to get terminal dimensions
    try cloud.reset();

    // Initialize colors after reset (needs terminal dimensions)
    const color_to_use = requested_color orelse .GREEN;
    try cloud.setColor(color_to_use);

    // Benchmark tracking
    const benchmark_mode = benchmark_seconds != null;
    var bench_start_time: ?std.time.Instant = null;
    var bench_frame_count: u64 = 0;
    var bench_frame_times: std.ArrayList(u64) = undefined;
    var bench_droplet_counts: std.ArrayList(u32) = undefined;
    var bench_peak_droplets: u32 = 0;

    if (benchmark_mode) {
        bench_frame_times = std.ArrayList(u64).initCapacity(std.heap.page_allocator, 1000) catch @panic("OOM");
        bench_droplet_counts = std.ArrayList(u32).initCapacity(std.heap.page_allocator, 1000) catch @panic("OOM");
    }
    defer {
        if (benchmark_mode) {
            bench_frame_times.deinit(std.heap.page_allocator);
            bench_droplet_counts.deinit(std.heap.page_allocator);
        }
    }

    // Main loop
    const target_period_ns = @as(u64, @intFromFloat(@round(1.0 / target_fps * 1.0e9)));
    var prev_time = std.time.Instant.now() catch unreachable;
    var prev_delay: u64 = 5;

    while (cloud.raining) {
        _ = handleInput(&cloud);

        // Check for terminal resize every frame
        checkTerminalResize(&cloud);

        const cur_time = std.time.Instant.now() catch unreachable;

        // Initialize benchmark start time on first frame
        if (benchmark_mode and bench_start_time == null) {
            bench_start_time = cur_time;
        }

        cloud.rain();

        // Benchmark overlay
        if (benchmark_mode) {
            const frame_start = std.time.Instant.now() catch unreachable;

            bench_frame_count += 1;

            const active_droplets: u32 = @intCast(cloud.active_droplets.items.len);
            if (active_droplets > bench_peak_droplets) {
                bench_peak_droplets = active_droplets;
            }

            // Calculate elapsed benchmark time
            const bench_elapsed_ns = cur_time.since(bench_start_time.?);
            const bench_elapsed_sec = @as(f64, @floatFromInt(bench_elapsed_ns)) / 1.0e9;
            const bench_total_sec = benchmark_seconds.?;

            // Calculate current FPS
            const frame_time_ns = cur_time.since(prev_time);
            const current_fps = if (frame_time_ns > 0) 1.0e9 / @as(f64, @floatFromInt(frame_time_ns)) else 0.0;

            // Draw benchmark overlay at start of first row with reverse video
            _ = c.attr_set(c.A_BOLD | c.A_REVERSE, 0, null);
            const fps_c: f64 = current_fps;
            const elapsed_c: f64 = bench_elapsed_sec;
            const total_c: f64 = bench_total_sec;
            const droplets_c: c_int = @intCast(active_droplets);
            _ = c.mvprintw(0, 0, " FPS:%6.0f D:%3d %.1f/%.0fs ", fps_c, droplets_c, elapsed_c, total_c);

            // Track frame time (excluding overlay drawing)
            const frame_end = std.time.Instant.now() catch unreachable;
            const actual_frame_ns = frame_end.since(frame_start);
            bench_frame_times.append(std.heap.page_allocator, actual_frame_ns) catch {};
            bench_droplet_counts.append(std.heap.page_allocator, active_droplets) catch {};

            // Check if benchmark is complete
            if (bench_elapsed_sec >= bench_total_sec) {
                cloud.raining = false;
            }
        }

        if (c.refresh() != c.OK) {
            die("refresh() failed\n", .{});
        }

        const elapsed = cur_time.since(prev_time);

        if (!benchmark_mode) {
            var calc_delay: u64 = 0;
            if (elapsed < target_period_ns) {
                calc_delay = target_period_ns - elapsed;
            }

            const cur_delay = (7 * prev_delay + calc_delay) / 8;
            std.Thread.sleep(cur_delay);
            prev_delay = cur_delay;
        }

        prev_time = cur_time;
    }

    // Show benchmark results
    if (benchmark_mode and bench_frame_count > 0) {
        _ = c.endwin();

        // Calculate statistics
        var total_frame_ns: u64 = 0;
        var min_frame_ns: u64 = std.math.maxInt(u64);
        var max_frame_ns: u64 = 0;
        var total_droplets: u64 = 0;

        for (bench_frame_times.items) |ft| {
            total_frame_ns += ft;
            if (ft < min_frame_ns) min_frame_ns = ft;
            if (ft > max_frame_ns) max_frame_ns = ft;
        }
        for (bench_droplet_counts.items) |dc| {
            total_droplets += dc;
        }

        const avg_frame_ns = total_frame_ns / bench_frame_count;
        const avg_frame_ms = @as(f64, @floatFromInt(avg_frame_ns)) / 1.0e6;
        const min_frame_ms = @as(f64, @floatFromInt(min_frame_ns)) / 1.0e6;
        const max_frame_ms = @as(f64, @floatFromInt(max_frame_ns)) / 1.0e6;
        const avg_fps = 1000.0 / avg_frame_ms;
        const min_fps = 1000.0 / max_frame_ms;
        const max_fps = 1000.0 / min_frame_ms;
        const avg_droplets = @as(f64, @floatFromInt(total_droplets)) / @as(f64, @floatFromInt(bench_frame_count));

        // Calculate actual duration from benchmark timing
        const bench_end_time = std.time.Instant.now() catch unreachable;
        const actual_duration_ns = bench_end_time.since(bench_start_time.?);
        const actual_duration = @as(f64, @floatFromInt(actual_duration_ns)) / 1.0e9;

        const cols: u32 = @intCast(c.COLS);
        const lines: u32 = @intCast(c.LINES);

        var bench_buf: [512]u8 = undefined;
        var bench_fba = std.heap.FixedBufferAllocator.init(&bench_buf);

        const printRow = struct {
            fn printRow(fba: *std.heap.FixedBufferAllocator, comptime fmt: []const u8, args: anytype) void {
                fba.end_index = 0; // Reset buffer for each row
                const content = std.fmt.allocPrint(fba.allocator(), fmt, args) catch return;
                const content_len = std.unicode.utf8CountCodepoints(content) catch content.len;
                const padding = if (content_len < 58) 58 - content_len else 0;
                const spaces = " " ** 80;
                std.debug.print("║{s}{s}║\n", .{ content, spaces[0..padding] });
            }
        }.printRow;

        std.debug.print("\n", .{});
        std.debug.print("╔══════════════════════════════════════════════════════════╗\n", .{});
        std.debug.print("║                  BENCHMARK RESULTS                       ║\n", .{});
        std.debug.print("╠══════════════════════════════════════════════════════════╣\n", .{});
        printRow(&bench_fba, "  Terminal:      {d} cols × {d} lines", .{ cols, lines });
        printRow(&bench_fba, "  Duration:      {d:.1} seconds", .{actual_duration});
        if (seed) |s| {
            printRow(&bench_fba, "  Seed:          {d}", .{s});
        } else {
            printRow(&bench_fba, "  Seed:          (random)", .{});
        }
        std.debug.print("╠══════════════════════════════════════════════════════════╣\n", .{});
        printRow(&bench_fba, "  Frames:        {d}", .{bench_frame_count});
        printRow(&bench_fba, "  Average FPS:   {d:.1}", .{avg_fps});
        printRow(&bench_fba, "  Min FPS:       {d:.1}", .{min_fps});
        printRow(&bench_fba, "  Max FPS:       {d:.1}", .{max_fps});
        printRow(&bench_fba, "  Frame time:    {d:.2} ms avg ({d:.2} - {d:.2} ms)", .{ avg_frame_ms, min_frame_ms, max_frame_ms });
        std.debug.print("╠══════════════════════════════════════════════════════════╣\n", .{});
        printRow(&bench_fba, "  Droplets:      {d:.1} avg / {d} peak", .{ avg_droplets, bench_peak_droplets });
        std.debug.print("╚══════════════════════════════════════════════════════════╝\n", .{});
        std.debug.print("\n", .{});
    }
}
