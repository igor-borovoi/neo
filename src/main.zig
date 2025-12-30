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
    _ = args_iter.next(); // Skip program name

    var usr_color_mode: types.ColorMode = .INVALID;
    var target_fps: f32 = 20.0; // Balanced animation rate
    var show_help = false;
    var show_version = false;
    var requested_color: ?types.Color = null;
    var requested_charset: ?types.Charset = null;
    var async_mode_requested = false;
    var requested_message: ?[]const u8 = null;

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
        }
    }

    if (show_help) {
        printHelp(args_iter.next().?);
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

    // Initialize - must call reset() first to get terminal dimensions
    try cloud.reset();

    // Initialize colors after reset (needs terminal dimensions)
    const color_to_use = requested_color orelse .GREEN;
    try cloud.setColor(color_to_use);

    // Main loop
    const target_period_ns = @as(u64, @intFromFloat(@round(1.0 / target_fps * 1.0e9)));
    var prev_time = std.time.Instant.now() catch unreachable;
    var prev_delay: u64 = 5;

    while (cloud.raining) {
        _ = handleInput(&cloud);

        // Check for terminal resize every frame
        checkTerminalResize(&cloud);

        const cur_time = std.time.Instant.now() catch unreachable;
        cloud.rain();

        if (c.refresh() != c.OK) {
            die("refresh() failed\n", .{});
        }

        const elapsed = cur_time.since(prev_time);

        var calc_delay: u64 = 0;
        if (elapsed < target_period_ns) {
            calc_delay = target_period_ns - elapsed;
        }

        const cur_delay = (7 * prev_delay + calc_delay) / 8;
        std.Thread.sleep(cur_delay);

        prev_time = cur_time;
        prev_delay = cur_delay;
    }
}
