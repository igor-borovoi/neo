const std = @import("std");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE_EXTENDED", "1");
    @cInclude("ncurses.h");
});

const types = @import("types.zig");

pub const Cloud = struct {
    allocator: std.mem.Allocator,
    droplets: std.ArrayList(Droplet),
    lines: u16 = 25,
    cols: u16 = 80,
    charset: types.Charset = .MIX,
    chars: std.ArrayList(u21),
    user_chars: std.ArrayList(u21),
    char_pool: std.ArrayList(u21),
    glitch_pool: std.ArrayList(u21),
    glitch_pool_idx: usize = 0,
    glitch_map: std.ArrayList(bool),
    color_pair_map: std.ArrayList(c_int),
    droplet_density: f32 = 1.0,
    droplets_per_sec: f32 = 5.0,
    col_stat: std.ArrayList(types.ColumnStatus),

    chars_per_sec: f32 = 4.0,  // Slower speed for classic Matrix effect
    shading_mode: types.ShadingMode = .RANDOM,
    force_draw_everything: bool = false,
    pause: bool = false,
    full_width: bool = false,
    color: types.Color = .GREEN,
    default_background: bool = false,
    async_mode: bool = false,
    raining: bool = true,
    bold_mode: types.BoldMode = .RANDOM,
    glitch_pct: f32 = 0.1,
    glitch_low_ms: u16 = 300,
    glitch_high_ms: u16 = 400,
    glitchy: bool = true,
    short_pct: f32 = 0.5,
    die_early_pct: f32 = 0.3333333,
    linger_low_ms: u16 = 1,
    linger_high_ms: u16 = 3000,
    max_droplets_per_column: u8 = 3,
    default_to_ascii: bool = false,
    message: std.ArrayList(types.MsgChr),

    last_glitch_time: std.time.Instant = undefined,
    next_glitch_time: std.time.Instant = undefined,
    pause_time: std.time.Instant = undefined,
    last_spawn_time: std.time.Instant = undefined,

    // Time-based glitch system: one glitch per 30 seconds per ~20" diagonal display equivalent
    // Reference: 160x45 terminal ≈ 7200 cells ≈ 20" diagonal at typical font size
    glitch_interval_base_ms: u64 = 30000, // 30 seconds base interval
    glitch_reference_area: u32 = 7200, // reference terminal area (cols × lines)
    active_glitch_line: u16 = 0xFFFF,
    active_glitch_col: u16 = 0xFFFF,
    glitch_duration_ms: u64 = 150, // how long each glitch lasts
    next_glitch_interval_ns: u64 = 0, // time until next glitch (calculated)

    seed: u64,

    color_mode: types.ColorMode = .MONO,
    num_color_pairs: c_int = 7,
    usr_colors: std.ArrayList(types.ColorContent),

    const Droplet = struct {
        p_cloud: ?*Cloud = null,
        is_alive: bool = false,
        bound_col: u16 = 0xFFFF,
        char_pool_idx: u16 = 0xFFFF,
        length: u16 = 0xFFFF,
        chars_per_sec: f32 = 0.0,
        last_time: std.time.Instant = undefined,
        // Virtual position (can be negative = above screen, or > lines = below screen)
        // This is the "infinite canvas" model - screen is just a window into it
        head_pos: f32 = 0.0,
        // Track what we've drawn for efficient updates
        last_drawn_head: i32 = -1000,
        last_drawn_tail: i32 = -1000,

        pub fn reset(self: *Droplet) void {
            self.p_cloud = null;
            self.is_alive = false;
            self.bound_col = 0xFFFF;
            self.char_pool_idx = 0xFFFF;
            self.length = 0xFFFF;
            self.chars_per_sec = 0.0;
            self.head_pos = 0.0;
            self.last_drawn_head = -1000;
            self.last_drawn_tail = -1000;
        }

        pub fn activate(self: *Droplet, cur_time: std.time.Instant) void {
            self.is_alive = true;
            self.last_time = cur_time;
        }

        /// Get virtual tail position (head - length)
        pub fn getTailPos(self: *const Droplet) f32 {
            return self.head_pos - @as(f32, @floatFromInt(self.length));
        }

        pub fn advance(self: *Droplet, cur_time: std.time.Instant) void {
            const cloud = self.p_cloud orelse return;
            const elapsed_ns = cur_time.since(self.last_time);
            const elapsed_sec = @as(f32, @floatFromInt(elapsed_ns)) / 1.0e9;

            // Advance head position continuously
            self.head_pos += self.chars_per_sec * elapsed_sec;

            // Allow other droplets to spawn once our tail clears the top quarter
            const tail_pos = self.getTailPos();
            const thresh = @as(f32, @floatFromInt(cloud.lines)) / 4.0;
            if (tail_pos > thresh) {
                cloud.setColumnSpawn(self.bound_col, true);
            }

            // Kill droplet when tail exits bottom of screen
            if (tail_pos >= @as(f32, @floatFromInt(cloud.lines))) {
                self.is_alive = false;
            }

            self.last_time = cur_time;
        }

        pub fn draw(self: *Droplet, cur_time: std.time.Instant, draw_everything: bool) void {
            _ = cur_time;
            const cloud = self.p_cloud orelse return;

            const head_int = @as(i32, @intFromFloat(@floor(self.head_pos)));
            const tail_int = @as(i32, @intFromFloat(@floor(self.getTailPos())));
            const lines_i32 = @as(i32, cloud.lines);

            // Clear characters that the tail has passed (erase old trail)
            if (self.last_drawn_tail >= 0 and self.last_drawn_tail < lines_i32) {
                var erase_line = self.last_drawn_tail;
                const erase_end = @min(tail_int, lines_i32);
                while (erase_line < erase_end) : (erase_line += 1) {
                    if (erase_line >= 0) {
                        _ = c.mvaddch(@intCast(erase_line), @intCast(self.bound_col), ' ');
                    }
                }
            }

            // Calculate visible range (clipped to screen)
            const visible_start = @max(tail_int + 1, 0);
            const visible_end = @min(head_int, lines_i32 - 1);

            if (visible_start > visible_end) {
                // Nothing visible on screen
                self.last_drawn_head = head_int;
                self.last_drawn_tail = tail_int;
                return;
            }

            // Draw visible portion of the droplet
            var line = visible_start;
            while (line <= visible_end) : (line += 1) {
                const line_u16 = @as(u16, @intCast(line));
                const is_glitched = cloud.isGlitched(line_u16, self.bound_col);
                const val = cloud.getChar(line_u16, self.char_pool_idx);

                // Determine character location type
                var cl = types.CharLoc.MIDDLE;
                if (line == tail_int + 1) {
                    cl = types.CharLoc.TAIL;
                } else if (line == head_int) {
                    cl = types.CharLoc.HEAD;
                }

                // Optimization: skip unchanged middle chars unless forced
                if (!draw_everything and !is_glitched and cl == types.CharLoc.MIDDLE and
                    line < self.last_drawn_head and line > self.last_drawn_tail and
                    cloud.shading_mode != .DISTANCE_FROM_HEAD)
                {
                    continue;
                }

                // Get attributes based on position in droplet
                var attr = types.CharAttr{ .color_pair = 0, .is_bold = false };
                const dist_from_head = @as(u16, @intCast(head_int - line));
                cloud.getAttr(line_u16, self.bound_col, val, cl, &attr, dist_from_head, self.length);

                // Draw character with proper attributes
                if (attr.is_bold) {
                    _ = c.attron(c.A_BOLD);
                }
                if (cloud.color_mode != .MONO and attr.color_pair > 0) {
                    _ = c.attron(c.COLOR_PAIR(attr.color_pair));
                }

                var utf8_buf: [4]u8 = undefined;
                const utf8_len = std.unicode.utf8Encode(val, &utf8_buf) catch 1;
                utf8_buf[utf8_len] = 0;
                _ = c.mvaddstr(@intCast(line), @intCast(self.bound_col), &utf8_buf);

                if (cloud.color_mode != .MONO and attr.color_pair > 0) {
                    _ = c.attroff(c.COLOR_PAIR(attr.color_pair));
                }
                if (attr.is_bold) {
                    _ = c.attroff(c.A_BOLD);
                }
            }

            self.last_drawn_head = head_int;
            self.last_drawn_tail = tail_int;
        }
    };

    pub fn init(allocator: std.mem.Allocator, cm: types.ColorMode, def2ascii: bool) Cloud {
        var self: Cloud = undefined;
        self.allocator = allocator;
        self.droplets = std.ArrayList(Droplet).initCapacity(allocator, 0) catch @panic("OOM");
        self.chars = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.user_chars = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.char_pool = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.glitch_pool = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.glitch_map = std.ArrayList(bool).initCapacity(allocator, 0) catch @panic("OOM");
        self.color_pair_map = std.ArrayList(c_int).initCapacity(allocator, 0) catch @panic("OOM");
        self.col_stat = std.ArrayList(types.ColumnStatus).initCapacity(allocator, 0) catch @panic("OOM");
        self.message = std.ArrayList(types.MsgChr).initCapacity(allocator, 0) catch @panic("OOM");
        self.usr_colors = std.ArrayList(types.ColorContent).initCapacity(allocator, 0) catch @panic("OOM");

        self.lines = 25;
        self.cols = 80;
        self.charset = .MIX; // Default to mixed mode: Japanese 80%, Cyrillic 10%, Braille 6%, ASCII 4%
        self.droplet_density = 1.5; // Denser rain for fuller effect
        self.droplets_per_sec = 8.0;
        self.chars_per_sec = 5.0;  // Slightly faster for smoother animation
        self.shading_mode = .DISTANCE_FROM_HEAD; // Gradual brightness fade like in the movie
        self.force_draw_everything = false;
        self.pause = false;
        self.full_width = false;
        self.color = .GREEN;
        self.default_background = true; // Use terminal default background (usually black)
        self.async_mode = false;
        self.raining = true;
        self.bold_mode = .RANDOM;
        self.glitch_pct = 0.0; // Not used anymore (time-based system)
        self.glitch_low_ms = 300;
        self.glitch_high_ms = 400;
        self.glitchy = true; // Time-based glitch: ~1 per 30s per 20" display diagonal
        self.short_pct = 0.2; // Only 20% short droplets (was 50%)
        self.die_early_pct = 0.15; // Only 15% die early (was 33%)
        self.linger_low_ms = 1;
        self.linger_high_ms = 2000;
        self.max_droplets_per_column = 4; // Allow more droplets per column
        self.default_to_ascii = def2ascii;
        // Initialize time-based glitch system
        self.glitch_interval_base_ms = 30000; // 30 seconds
        self.glitch_reference_area = 7200; // ~160x45 terminal
        self.active_glitch_line = 0xFFFF;
        self.active_glitch_col = 0xFFFF;
        self.glitch_duration_ms = 150;
        self.next_glitch_interval_ns = 0;
        // Initialize timestamps later when needed
        self.color_mode = cm;
        self.num_color_pairs = 7;
        self.seed = 0x1234567;

        return self;
    }

    pub fn deinit(self: *Cloud) void {
        self.droplets.deinit();
        self.chars.deinit();
        self.user_chars.deinit();
        self.char_pool.deinit();
        self.glitch_pool.deinit();
        self.glitch_map.deinit();
        self.color_pair_map.deinit();
        self.col_stat.deinit();
        self.message.deinit();
        self.usr_colors.deinit();
    }

    pub fn rain(self: *Cloud) void {
        if (self.pause) return;

        const cur_time = std.time.Instant.now() catch unreachable;

        // Handle time-based glitch system
        if (self.glitchy) {
            self.updateGlitch(cur_time);
        }

        self.spawnDroplets(cur_time);

        if (self.force_draw_everything) {
            _ = c.clear();
        }

        // Update and draw all active droplets
        for (self.droplets.items) |*droplet| {
            if (!droplet.is_alive) continue;

            droplet.advance(cur_time);
            if (!droplet.is_alive) {
                // Droplet died, allow spawning in this column
                self.col_stat.items[droplet.bound_col].num_droplets -= 1;
                self.col_stat.items[droplet.bound_col].can_spawn = true;
            } else {
                droplet.draw(cur_time, self.force_draw_everything);
            }
        }

        // Calculate and draw message
        if (self.message.items.len > 0) {
            self.calcMessage();
            self.drawMessage();
        }

        self.force_draw_everything = false;
    }

    /// Update time-based glitch: trigger new glitch or expire current one
    fn updateGlitch(self: *Cloud, cur_time: std.time.Instant) void {
        // Check if current glitch has expired (after glitch_duration_ms)
        if (self.active_glitch_line != 0xFFFF) {
            const elapsed_since_glitch = cur_time.since(self.last_glitch_time);
            if (elapsed_since_glitch >= self.glitch_duration_ms * std.time.ns_per_ms) {
                // Expire the glitch
                self.active_glitch_line = 0xFFFF;
                self.active_glitch_col = 0xFFFF;
            }
        }

        // Check if it's time for a new glitch
        if (self.active_glitch_line == 0xFFFF) {
            const elapsed_since_schedule = cur_time.since(self.next_glitch_time);
            if (elapsed_since_schedule >= self.next_glitch_interval_ns) {
                // Trigger a new glitch at random position
                self.active_glitch_line = @as(u16, @intCast(self.randomInt(@as(u32, self.lines))));
                self.active_glitch_col = @as(u16, @intCast(self.randomInt(@as(u32, self.cols))));
                self.last_glitch_time = cur_time;
                self.next_glitch_time = cur_time;

                // Schedule next glitch interval
                self.scheduleNextGlitch();
            }
        }
    }

    fn randomFloat(self: *Cloud) f32 {
        // Simple linear congruential generator for demonstration
        self.seed = self.seed *% 1103515245 +% 12345;
        return @as(f32, @floatFromInt(self.seed % 1000)) / 1000.0;
    }

    fn randomInt(self: *Cloud, max: u32) u32 {
        return @intFromFloat(self.randomFloat() * @as(f32, @floatFromInt(max)));
    }

    pub fn reset(self: *Cloud) !void {
        self.lines = @intCast(c.LINES);
        self.cols = @intCast(c.COLS);

        // Handle invalid terminal dimensions (e.g., headless environments)
        if (self.lines == 0) self.lines = 24;
        if (self.cols == 0) self.cols = 80;

        // Calculate droplets_per_sec based on screen size (like C++ version)
        // Formula: cols * density / (lines / chars_per_sec)
        const time_to_fill_screen = @as(f32, @floatFromInt(self.lines)) / self.chars_per_sec;
        self.droplets_per_sec = @as(f32, @floatFromInt(self.cols)) * self.droplet_density / time_to_fill_screen;

        // Resize droplets array based on terminal size
        const max_droplets = self.cols; // One potential droplet per column
        try self.droplets.resize(max_droplets);
        // Initialize all droplets as inactive
        for (self.droplets.items) |*droplet| {
            droplet.reset();
        }

        const num_droplets = @as(usize, @intFromFloat(@round(2.0 * @as(f32, @floatFromInt(self.cols)))));
        try self.droplets.resize(num_droplets);
        for (self.droplets.items) |*droplet| {
            droplet.* = Droplet{};
        }

        // Reset seed
        self.seed = 0x1234567;

        const screen_size = self.lines * self.cols;
        try self.glitch_map.resize(screen_size);
        try self.color_pair_map.resize(screen_size);
        try self.col_stat.resize(self.cols);

        for (0..screen_size) |i| {
            self.glitch_map.items[i] = false; // Not used anymore, time-based glitch instead
            self.color_pair_map.items[i] = @as(c_int, @intCast(self.randomInt(@as(u32, @intCast(self.num_color_pairs - 1))) + 1));
        }

        // Reset active glitch
        self.active_glitch_line = 0xFFFF;
        self.active_glitch_col = 0xFFFF;

        // Initialize column status
        for (0..self.cols) |i| {
            self.col_stat.items[i] = types.ColumnStatus{
                .max_speed_pct = 1.0,
                .num_droplets = 0,
                .can_spawn = true,
            };
        }

        try self.char_pool.resize(types.CHAR_POOL_SIZE);
        try self.glitch_pool.resize(types.GLITCH_POOL_SIZE);

        // Build character pool based on charset
        try self.buildCharacterPool();
        try self.buildGlitchPool();

        // Reset message positions
        self.resetMessage();

        // Initialize timestamps
        const now = std.time.Instant.now() catch unreachable;
        self.last_glitch_time = now;
        self.next_glitch_time = now;
        self.pause_time = now;
        self.last_spawn_time = now;

        // Schedule first glitch based on terminal size
        self.scheduleNextGlitch();
    }

    /// Calculate and schedule the next glitch interval based on terminal size.
    /// Larger terminals (more cells) get more frequent glitches to maintain
    /// roughly 1 glitch per 30 seconds per 20" diagonal display equivalent.
    fn scheduleNextGlitch(self: *Cloud) void {
        const terminal_area = @as(u64, self.lines) * @as(u64, self.cols);

        // Scale interval inversely with terminal size
        // Larger terminal = shorter interval (more glitches proportionally)
        // Formula: interval = base_interval * (reference_area / terminal_area)
        var interval_ms: u64 = self.glitch_interval_base_ms;
        if (terminal_area > 0) {
            // Use u64 for all calculations to avoid overflow
            const base = @as(u64, self.glitch_interval_base_ms);
            const ref_area = @as(u64, self.glitch_reference_area);
            interval_ms = (base * ref_area) / terminal_area;
            // Clamp to reasonable bounds (5s to 120s)
            interval_ms = @max(interval_ms, 5000);
            interval_ms = @min(interval_ms, 120000);
        }

        // Add some randomness (±30%)
        const jitter = self.randomInt(60); // 0-59
        const jitter_factor: u64 = 70 + jitter; // 70-129 (representing 0.7x to 1.29x)
        interval_ms = (interval_ms * jitter_factor) / 100;

        self.next_glitch_interval_ns = interval_ms * std.time.ns_per_ms;
    }

    pub fn setColumnSpeeds(self: *Cloud) void {
        for (self.col_stat.items) |*col| {
            col.max_speed_pct = if (self.async_mode) self.randomFloat() else 1.0;
        }
    }

    pub fn updateDropletSpeeds(self: *Cloud) void {
        for (self.droplets.items) |*droplet| {
            if (!droplet.is_alive) continue;
            const col_speed_pct = self.col_stat.items[droplet.bound_col].max_speed_pct;
            droplet.chars_per_sec = col_speed_pct * self.chars_per_sec;
        }
    }

    pub fn setAsync(self: *Cloud, enabled: bool) void {
        self.async_mode = enabled;
        self.setColumnSpeeds();
        self.updateDropletSpeeds();
    }

    pub fn setMessage(self: *Cloud, message: []const u8) !void {
        self.message.clearRetainingCapacity();
        for (message) |char| {
            try self.message.append(types.MsgChr.init(@as(u8, char)));
        }
    }

    fn resetMessage(self: *Cloud) void {
        const first_col = self.cols / 4;
        const last_col = 3 * self.cols / 4;
        const chars_per_col = last_col - first_col + 1;
        const msg_lines = @as(u16, @intCast((self.message.items.len + chars_per_col - 1) / chars_per_col));
        const first_line = self.lines / 2 - msg_lines / 2;

        var chars_remaining = self.message.items.len;
        var line = first_line;
        var col = first_col;

        if (chars_remaining < chars_per_col) {
            col += (chars_per_col - @as(u16, @intCast(chars_remaining))) / 2;
        }

        for (self.message.items) |*msg_char| {
            msg_char.draw = false;
            if (line < self.lines) {
                msg_char.line = line;
                msg_char.col = col;
                col += 1;
                if (col > last_col) {
                    col = first_col;
                    line += 1;
                }
            } else {
                msg_char.line = 0xFFFF;
                msg_char.col = 0xFFFF;
            }
            if (chars_remaining > 0) {
                chars_remaining -= 1;
            }
        }
    }

    fn calcMessage(self: *Cloud) void {
        for (self.message.items) |*msg_char| {
            if (msg_char.line == 0xFFFF or msg_char.col == 0xFFFF) {
                break;
            }

            // Check if there's already a character at this position
            const ch = c.mvinch(@intCast(msg_char.line), @intCast(msg_char.col));
            if (ch == c.ERR or ch == 0 or ch == ' ') {
                msg_char.draw = true;
            } else {
                msg_char.draw = false;
            }
        }
    }

    fn drawMessage(self: *Cloud) void {
        for (self.message.items) |msg_char| {
            if (!msg_char.draw) continue;

            const attr: c.attr_t = if (self.bold_mode == .OFF) c.A_NORMAL else c.A_BOLD;
            if (self.color_mode != .MONO) {
                _ = c.attron(c.COLOR_PAIR(@intCast(self.num_color_pairs)));
            }

            _ = c.mvaddch(@intCast(msg_char.line), @intCast(msg_char.col), @intCast(msg_char.val));
            _ = c.attroff(@intCast(attr));
        }
    }

    fn buildCharacterPool(self: *Cloud) !void {
        // Build character pool based on selected charset
        const charset = self.charset;

        // Define character ranges for each charset
        const CharRange = struct { start: u21, end: u21 };

        var ranges: [16]CharRange = undefined;
        var num_ranges: usize = 0;

        if (charset == .NONE or charset == .DEFAULT or charset == .EXTENDED_DEFAULT) {
            // Default ASCII printable characters
            ranges[num_ranges] = .{ .start = 33, .end = 126 };
            num_ranges += 1;
        } else if (charset == .KATAKANA) {
            // Half-width Katakana: U+FF66 to U+FF9D (single cell width, no horizontal jitter)
            ranges[num_ranges] = .{ .start = 0xFF66, .end = 0xFF9D };
            num_ranges += 1;
        } else if (charset == .GREEK) {
            // Greek uppercase and lowercase: U+0391 to U+03C9
            ranges[num_ranges] = .{ .start = 0x0391, .end = 0x03A9 }; // Uppercase
            num_ranges += 1;
            ranges[num_ranges] = .{ .start = 0x03B1, .end = 0x03C9 }; // Lowercase
            num_ranges += 1;
        } else if (charset == .CYRILLIC) {
            // Cyrillic: U+0410 to U+044F
            ranges[num_ranges] = .{ .start = 0x0410, .end = 0x042F }; // Uppercase
            num_ranges += 1;
            ranges[num_ranges] = .{ .start = 0x0430, .end = 0x044F }; // Lowercase
            num_ranges += 1;
        } else if (charset == .ARABIC) {
            // Arabic: U+0621 to U+064A
            ranges[num_ranges] = .{ .start = 0x0621, .end = 0x064A };
            num_ranges += 1;
        } else if (charset == .HEBREW) {
            // Hebrew: U+05D0 to U+05EA
            ranges[num_ranges] = .{ .start = 0x05D0, .end = 0x05EA };
            num_ranges += 1;
        } else if (charset == .BINARY) {
            // Binary: just 0 and 1
            ranges[num_ranges] = .{ .start = '0', .end = '1' };
            num_ranges += 1;
        } else if (charset == .HEX) {
            // Hex: 0-9, A-F
            ranges[num_ranges] = .{ .start = '0', .end = '9' };
            num_ranges += 1;
            ranges[num_ranges] = .{ .start = 'A', .end = 'F' };
            num_ranges += 1;
        } else if (charset == .BRAILLE) {
            // Braille: U+2800 to U+28FF
            ranges[num_ranges] = .{ .start = 0x2800, .end = 0x28FF };
            num_ranges += 1;
        } else if (charset == .RUNIC) {
            // Runic: U+16A0 to U+16F0
            ranges[num_ranges] = .{ .start = 0x16A0, .end = 0x16F0 };
            num_ranges += 1;
        } else if (charset == .DEVANAGARI) {
            // Devanagari: U+0904 to U+0939
            ranges[num_ranges] = .{ .start = 0x0904, .end = 0x0939 };
            num_ranges += 1;
        } else if (charset == .MIX) {
            // Mixed mode: Japanese 80%, Cyrillic 10%, Braille 6%, ASCII 4%
            self.buildMixedCharacterPool();
            return;
        } else {
            // Fallback to ASCII
            ranges[num_ranges] = .{ .start = 33, .end = 126 };
            num_ranges += 1;
        }

        // Count total characters available
        var total_chars: usize = 0;
        for (0..num_ranges) |r| {
            total_chars += @as(usize, ranges[r].end - ranges[r].start + 1);
        }

        // Fill the character pool
        for (0..types.CHAR_POOL_SIZE) |i| {
            // Pick a random character from available ranges
            var char_idx = i % total_chars;
            var selected_char: u21 = 33; // fallback

            for (0..num_ranges) |r| {
                const range_size = @as(usize, ranges[r].end - ranges[r].start + 1);
                if (char_idx < range_size) {
                    selected_char = ranges[r].start + @as(u21, @intCast(char_idx));
                    break;
                }
                char_idx -= range_size;
            }

            self.char_pool.items[i] = selected_char;
        }
    }

    /// Shape groups for visual continuity across scripts
    /// Each group contains visually similar characters from different scripts
    const ShapeGroup = struct {
        katakana: []const u21,
        cyrillic: []const u21,
        braille: []const u21,
        ascii: []const u21,
    };

    /// Shape equivalence table - characters grouped by visual similarity
    /// Characters are shuffled to avoid alphabetical patterns
    const shape_groups = [_]ShapeGroup{
        // Angular/pointed shapes
        .{
            .katakana = &[_]u21{ 0xFF76, 0xFF79, 0xFF77, 0xFF7A, 0xFF78 },
            .cyrillic = &[_]u21{ 0x0416, 0x043A, 0x041A, 0x0436, 0x0425 },
            .braille = &[_]u21{ 0x284D, 0x2847, 0x2857, 0x284B, 0x284E },
            .ascii = &[_]u21{ 'x', 'V', 'K', 'y', 'W', 'X', 'k', 'Y' },
        },
        // Round/curved shapes
        .{
            .katakana = &[_]u21{ 0xFF9B, 0xFF66, 0xFF7A, 0xFF75, 0xFF9E },
            .cyrillic = &[_]u21{ 0x0444, 0x041E, 0x043E, 0x0424, 0x0421 },
            .braille = &[_]u21{ 0x28DF, 0x28FF, 0x28BF, 0x28F7, 0x28EF },
            .ascii = &[_]u21{ '@', 'c', 'Q', '0', 'O', 'G', 'o', 'C' },
        },
        // Vertical line shapes
        .{
            .katakana = &[_]u21{ 0xFF7C, 0xFF89, 0xFF72, 0xFF82, 0xFF6F },
            .cyrillic = &[_]u21{ 0x0457, 0x041B, 0x0406, 0x0456, 0x0407 },
            .braille = &[_]u21{ 0x28C6, 0x2847, 0x2807, 0x28C7, 0x2846 },
            .ascii = &[_]u21{ '|', 'j', '1', 'I', '!', 'l', 'i' },
        },
        // Horizontal/wide shapes
        .{
            .katakana = &[_]u21{ 0xFF88, 0xFF83, 0xFF8C, 0xFF86, 0xFF84 },
            .cyrillic = &[_]u21{ 0x0433, 0x0422, 0x0403, 0x0442, 0x0413 },
            .braille = &[_]u21{ 0x28E0, 0x283C, 0x2824, 0x28F0, 0x2834 },
            .ascii = &[_]u21{ '7', 'L', 'T', '-', 'f', 'E', 't', 'F' },
        },
        // Complex/dense shapes
        .{
            .katakana = &[_]u21{ 0xFF92, 0xFF8E, 0xFF93, 0xFF90, 0xFF91 },
            .cyrillic = &[_]u21{ 0x042F, 0x0449, 0x0416, 0x042E, 0x0429 },
            .braille = &[_]u21{ 0x28FB, 0x28FF, 0x28F7, 0x28FE, 0x28FD },
            .ascii = &[_]u21{ '#', 'w', 'M', '&', 'N', '%', 'W', 'm', 'H' },
        },
        // Sparse/simple shapes
        .{
            .katakana = &[_]u21{ 0xFF6A, 0xFF67, 0xFF6B, 0xFF69, 0xFF68 },
            .cyrillic = &[_]u21{ 0x044A, 0x0472, 0x0433, 0x0463, 0x044C },
            .braille = &[_]u21{ 0x2808, 0x2801, 0x2810, 0x2804, 0x2802 },
            .ascii = &[_]u21{ '*', '"', '.', '+', '`', ',', '\'' },
        },
        // Diagonal shapes
        .{
            .katakana = &[_]u21{ 0xFF9D, 0xFF7F, 0xFF9C, 0xFF81, 0xFF80 },
            .cyrillic = &[_]u21{ 0x0443, 0x0418, 0x0438, 0x0423, 0x0419 },
            .braille = &[_]u21{ 0x2852, 0x2858, 0x2851, 0x2850, 0x2854 },
            .ascii = &[_]u21{ 'N', '/', '2', 'z', '\\', 'Z' },
        },
        // Box/square shapes
        .{
            .katakana = &[_]u21{ 0xFF99, 0xFF9B, 0xFF9A, 0xFF97, 0xFF98 },
            .cyrillic = &[_]u21{ 0x0446, 0x041F, 0x043F, 0x0428, 0x0426 },
            .braille = &[_]u21{ 0x28DF, 0x28FF, 0x28EF, 0x287F, 0x28BF },
            .ascii = &[_]u21{ 'u', '=', 'H', ']', 'n', '[', 'U' },
        },
    };

    /// Build character pool for MIX mode with shape continuity
    /// Japanese 80%, Cyrillic 10%, Braille 6%, ASCII 4%
    fn buildMixedCharacterPool(self: *Cloud) void {
        var current_shape: usize = self.randomInt(@as(u32, shape_groups.len));

        for (0..types.CHAR_POOL_SIZE) |i| {
            // 75% chance to keep same shape group for visual continuity
            const shape_roll = self.randomInt(100);
            if (shape_roll >= 75) {
                current_shape = self.randomInt(@as(u32, shape_groups.len));
            }

            const group = shape_groups[current_shape];

            // Pick script based on weighted distribution
            const script_roll = self.randomInt(100);
            var selected_char: u21 = undefined;

            if (script_roll < 80) {
                // 80% Japanese Katakana
                const idx = self.randomInt(@as(u32, @intCast(group.katakana.len)));
                selected_char = group.katakana[idx];
            } else if (script_roll < 90) {
                // 10% Cyrillic
                const idx = self.randomInt(@as(u32, @intCast(group.cyrillic.len)));
                selected_char = group.cyrillic[idx];
            } else if (script_roll < 96) {
                // 6% Braille
                const idx = self.randomInt(@as(u32, @intCast(group.braille.len)));
                selected_char = group.braille[idx];
            } else {
                // 4% ASCII
                const idx = self.randomInt(@as(u32, @intCast(group.ascii.len)));
                selected_char = group.ascii[idx];
            }

            self.char_pool.items[i] = selected_char;
        }
    }

    fn buildGlitchPool(self: *Cloud) !void {
        // Use same ASCII characters for glitching
        for (0..types.GLITCH_POOL_SIZE) |i| {
            self.glitch_pool.items[i] = @as(u21, @intCast(33 + (i % 94)));
        }
    }

    pub fn spawnDroplets(self: *Cloud, cur_time: std.time.Instant) void {
        const elapsed_ns = cur_time.since(self.last_spawn_time);
        const elapsed_sec = @as(f32, @floatFromInt(elapsed_ns)) / 1.0e9;
        const droplets_to_spawn = @min(@as(usize, @intFromFloat(@round(elapsed_sec * self.droplets_per_sec))), self.droplets.items.len);

        if (droplets_to_spawn == 0) return;

        var spawned: usize = 0;
        for (0..droplets_to_spawn) |_| {
            const col = @as(u16, @intCast(self.randomInt(@as(u32, self.cols))));
            const col_status = &self.col_stat.items[col];

            if (!col_status.can_spawn or col_status.num_droplets >= self.max_droplets_per_column) {
                continue;
            }

            // Find inactive droplet
            for (self.droplets.items) |*droplet| {
                if (!droplet.is_alive) {
                    // Fill droplet with proper parameters
                    droplet.reset();
                    droplet.p_cloud = self;
                    droplet.bound_col = col;

                    // Random character pool index
                    droplet.char_pool_idx = @as(u16, @intCast(self.randomInt(types.CHAR_POOL_SIZE)));

                    // Random length with minimum of 5 for visible trail
                    const min_length: u32 = 5;
                    const max_length: u32 = @max(@as(u32, self.lines) - 1, min_length);
                    const length_range = max_length - min_length + 1;
                    droplet.length = @as(u16, @intCast(self.randomInt(length_range) + min_length));

                    // Random speed
                    droplet.chars_per_sec = self.chars_per_sec * (0.3333333 + self.randomFloat() * 0.6666667);

                    // Start head position above screen so droplet enters with trail already formed
                    // Random start: from just above screen (0) to fully above (-length)
                    // This creates the illusion of an infinite stream we're viewing through a window
                    const start_offset = self.randomFloat() * @as(f32, @floatFromInt(droplet.length));
                    droplet.head_pos = -start_offset;

                    droplet.activate(cur_time);
                    col_status.can_spawn = false;
                    col_status.num_droplets += 1;
                    spawned += 1;
                    break;
                }
            }
        }

        if (spawned > 0) {
            self.last_spawn_time = cur_time;
        }
    }

    pub fn setColor(self: *Cloud, color: types.Color) !void {
        self.color = color;
        _ = c.use_default_colors();

        // For MONO mode, don't set any colors - use terminal defaults
        if (self.color_mode == .MONO) {
            self.num_color_pairs = 0;
            return;
        }

        var bg_color: c_int = 16; // Default background color index
        if (self.color_mode == .COLOR16) {
            bg_color = 0;
        }
        if (self.default_background) {
            bg_color = -1;
        }

        switch (color) {
            .GREEN => {
                if (self.color_mode == .TRUECOLOR) {
                    // Rich 16-step gradient from dark green to bright white-green for Kitty/truecolor terminals
                    // Colors go from very dim (pair 1) to glowing white-green (pair 16)
                    self.num_color_pairs = 16;

                    // Define custom RGB colors (ncurses uses 0-1000 scale)
                    // Dark to bright green gradient with white glow at the end
                    _ = c.init_color(230, 0, 150, 0);       // Very dark green
                    _ = c.init_color(231, 0, 220, 0);       // Dark green
                    _ = c.init_color(232, 0, 300, 20);      // Dark green
                    _ = c.init_color(233, 20, 380, 40);     // Medium-dark green
                    _ = c.init_color(234, 40, 460, 60);     // Medium green
                    _ = c.init_color(235, 60, 540, 80);     // Medium green
                    _ = c.init_color(236, 80, 620, 100);    // Medium-bright green
                    _ = c.init_color(237, 100, 700, 130);   // Bright green
                    _ = c.init_color(238, 130, 780, 170);   // Bright green
                    _ = c.init_color(239, 170, 850, 220);   // Very bright green
                    _ = c.init_color(240, 220, 900, 280);   // Bright green with hint of white
                    _ = c.init_color(241, 300, 940, 360);   // Brighter
                    _ = c.init_color(242, 400, 970, 460);   // Near-white green
                    _ = c.init_color(243, 550, 990, 600);   // White-green glow
                    _ = c.init_color(244, 750, 1000, 780);  // Bright white-green
                    _ = c.init_color(245, 950, 1000, 960);  // Almost white (head glow)

                    // Create color pairs
                    var i: c_short = 1;
                    while (i <= 16) : (i += 1) {
                        _ = c.init_pair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    // 256-color mode - use more color pairs for smoother gradient
                    self.num_color_pairs = 12;
                    _ = c.init_pair(1, 22, @intCast(bg_color));   // Very dark green
                    _ = c.init_pair(2, 28, @intCast(bg_color));   // Dark green
                    _ = c.init_pair(3, 34, @intCast(bg_color));   // Medium-dark green
                    _ = c.init_pair(4, 40, @intCast(bg_color));   // Medium green
                    _ = c.init_pair(5, 41, @intCast(bg_color));   // Medium green
                    _ = c.init_pair(6, 42, @intCast(bg_color));   // Medium-bright green
                    _ = c.init_pair(7, 48, @intCast(bg_color));   // Bright green
                    _ = c.init_pair(8, 83, @intCast(bg_color));   // Bright green
                    _ = c.init_pair(9, 84, @intCast(bg_color));   // Very bright green
                    _ = c.init_pair(10, 120, @intCast(bg_color)); // Bright green-white
                    _ = c.init_pair(11, 157, @intCast(bg_color)); // Near white-green
                    _ = c.init_pair(12, 15, @intCast(bg_color));  // White (head glow)
                } else if (self.color_mode == .COLOR16) {
                    self.num_color_pairs = 3;
                    _ = c.init_pair(1, 2, @intCast(bg_color));   // Dark green
                    _ = c.init_pair(2, 10, @intCast(bg_color));  // Bright green
                    _ = c.init_pair(3, 15, @intCast(bg_color));  // White (head)
                } else {
                    self.num_color_pairs = 7;
                    _ = c.init_pair(1, 234, @intCast(bg_color));
                    _ = c.init_pair(2, 22, @intCast(bg_color));
                    _ = c.init_pair(3, 28, @intCast(bg_color));
                    _ = c.init_pair(4, 35, @intCast(bg_color));
                    _ = c.init_pair(5, 78, @intCast(bg_color));
                    _ = c.init_pair(6, 84, @intCast(bg_color));
                    _ = c.init_pair(7, 159, @intCast(bg_color));
                }
            },
            .USER => {
                if (self.color_mode == .TRUECOLOR) {
                    // Initialize user-defined truecolor colors
                    for (self.usr_colors.items) |color_content| {
                        if (color_content.r != 0x7FFF and color_content.g != 0x7FFF and color_content.b != 0x7FFF) {
                            _ = c.init_color(@intCast(color_content.color), @intCast(color_content.r), @intCast(color_content.g), @intCast(color_content.b));
                        }
                    }
                }
                bg_color = @intCast(self.usr_colors.items[0].color);
                self.num_color_pairs = 0;
                for (1..self.usr_colors.items.len) |i| {
                    _ = c.init_pair(@intCast(i), @intCast(self.usr_colors.items[i].color), @intCast(bg_color));
                    self.num_color_pairs += 1;
                }
            },
            else => {
                // Default to green for other colors
                if (self.color_mode == .COLOR16) {
                    self.num_color_pairs = 2;
                    _ = c.init_pair(1, 10, @intCast(bg_color));
                    _ = c.init_pair(2, 15, @intCast(bg_color));
                } else {
                    self.num_color_pairs = 7;
                    // Use bright colors from 256-color palette
                    _ = c.init_pair(1, 46, @intCast(bg_color)); // Bright green
                    _ = c.init_pair(2, 47, @intCast(bg_color)); // Bright green
                    _ = c.init_pair(3, 48, @intCast(bg_color)); // Bright green
                    _ = c.init_pair(4, 49, @intCast(bg_color)); // Bright green
                    _ = c.init_pair(5, 50, @intCast(bg_color)); // Bright green
                    _ = c.init_pair(6, 51, @intCast(bg_color)); // Bright green
                    _ = c.init_pair(7, 46, @intCast(bg_color)); // Bright green (head)
                }
            },
        }
        const screen_size = self.lines * self.cols;
        try self.color_pair_map.resize(screen_size);
        for (0..screen_size) |i| {
            self.color_pair_map.items[i] = @as(c_int, @intCast(self.randomInt(@as(u32, @intCast(self.num_color_pairs - 1))) + 1));
        }

        if (self.color_mode != .MONO) {
            _ = c.bkgdset(@intCast(c.COLOR_PAIR(1)));
        }
        self.force_draw_everything = true;
    }

    /// Get character attributes based on position in the droplet
    /// dist_from_head: how many lines behind the head this character is (0 = at head)
    /// length: total droplet length (dist_from_head at tail = length - 1)
    pub fn getAttr(self: *const Cloud, line: u16, col: u16, val: u21, ct: types.CharLoc, attr: *types.CharAttr, dist_from_head: u16, length: u16) void {
        switch (ct) {
            .TAIL => {
                // Tail is the dimmest
                attr.color_pair = 1;
                attr.is_bold = false;
            },
            .HEAD => {
                // Head gets the "glow" effect - brightest white/green
                attr.color_pair = self.num_color_pairs;
                attr.is_bold = true;
            },
            .MIDDLE => {
                if (self.shading_mode == .DISTANCE_FROM_HEAD) {
                    // Calculate brightness based on position in droplet (not screen position)
                    // This creates consistent shading regardless of where droplet is on screen
                    const effective_length = @max(length, 1);
                    const distance_ratio = @as(f32, @floatFromInt(dist_from_head)) / @as(f32, @floatFromInt(effective_length));

                    // Smooth gradient from head (bright) to tail (dim)
                    const brightness_level = 1.0 - @min(distance_ratio, 1.0);

                    // Map to color pairs: pair 1 is dimmest, num_color_pairs-1 is brightest for middle
                    const color_range = @as(f32, @floatFromInt(self.num_color_pairs - 2));
                    var calculated_pair = @as(c_int, @intFromFloat(brightness_level * color_range)) + 1;
                    calculated_pair = @max(calculated_pair, 1);
                    calculated_pair = @min(calculated_pair, self.num_color_pairs - 1);
                    attr.color_pair = calculated_pair;

                    // Glow effect near the head
                    if (dist_from_head <= 1) {
                        attr.color_pair = self.num_color_pairs - 1;
                        attr.is_bold = true;
                    } else if (dist_from_head <= 3) {
                        attr.color_pair = @max(calculated_pair, self.num_color_pairs - 3);
                        attr.is_bold = true;
                    } else if (dist_from_head <= 6) {
                        attr.is_bold = (line % 3 == 0);
                    } else {
                        attr.is_bold = (line % 7 == 0);
                    }
                } else {
                    // Random shading mode (original behavior)
                    const idx = @as(usize, col) * @as(usize, self.lines) + @as(usize, line);
                    attr.color_pair = self.color_pair_map.items[idx];
                    attr.color_pair = @min(attr.color_pair, self.num_color_pairs - 1);
                    attr.color_pair = @max(attr.color_pair, 1);
                    attr.is_bold = (line ^ @as(u16, @intCast(val))) % 2 == 1;
                }
            },
        }

        if (self.bold_mode == .OFF) {
            attr.is_bold = false;
        } else if (self.bold_mode == .ALL) {
            attr.is_bold = true;
        }
    }

    pub fn isGlitched(self: *const Cloud, line: u16, col: u16) bool {
        if (!self.glitchy) return false;
        // Time-based glitch: only the active glitch position returns true
        return (line == self.active_glitch_line and col == self.active_glitch_col);
    }

    pub fn getChar(self: *const Cloud, line: u16, char_pool_idx: u16) u21 {
        const pool_idx = @as(usize, char_pool_idx) % self.char_pool.items.len;
        const line_val = @as(usize, line);
        // Prime stride and XOR mixing to avoid sequential/alphabetical patterns
        const stride: usize = 37;
        const mix = (pool_idx *% 7) ^ (line_val *% 13);
        const char_idx = (pool_idx +% line_val *% stride +% mix) % self.char_pool.items.len;
        return self.char_pool.items[char_idx];
    }

    pub fn setColumnSpawn(self: *Cloud, col: u16, b: bool) void {
        if (col < self.col_stat.items.len) {
            self.col_stat.items[col].can_spawn = b;
        }
    }

    pub fn togglePause(self: *Cloud) void {
        self.pause = !self.pause;
        if (self.pause) {
            self.pause_time = std.time.Instant.now() catch unreachable;
        } else {
            const now = std.time.Instant.now() catch unreachable;
            const elapsed = now.since(self.pause_time);
            _ = elapsed; // For now, just reset spawn time
            self.last_spawn_time = now;
        }
    }
};
