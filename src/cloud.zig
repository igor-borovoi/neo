const std = @import("std");
const term = @import("term.zig");
const types = @import("types.zig");
const time = @import("time.zig");

pub const Cloud = struct {
    allocator: std.mem.Allocator,
    io: time.Io,
    droplets: std.ArrayList(Droplet),
    active_droplets: std.ArrayList(usize),
    lines: u16 = 25,
    cols: u16 = 80,
    charset: types.Charset = .MIX,
    chars: std.ArrayList(u21),
    user_chars: std.ArrayList(u21),
    char_pool: std.ArrayList(types.CharEntry),
    glitch_pool: std.ArrayList(u21),
    glitch_pool_idx: usize = 0,
    glitch_map: std.ArrayList(bool),
    color_pair_map: std.ArrayList(c_int),
    droplet_density: f32 = 1.0,
    droplets_per_sec: f32 = 5.0,
    col_stat: std.ArrayList(types.ColumnStatus),
    row_stat: std.ArrayList(types.ColumnStatus),
    current_attr: ?types.CharAttr = null,

    chars_per_sec: f32 = 4.0, // Slower speed for classic Matrix effect
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
    max_droplets_per_column: u8 = 2,
    default_to_ascii: bool = false,
    message: std.ArrayList(types.MsgChr),

    last_glitch_time: time.Instant = undefined,
    next_glitch_time: time.Instant = undefined,
    pause_time: time.Instant = undefined,
    last_spawn_time: time.Instant = undefined,

    // Time-based glitch system: one glitch per 30 seconds per ~20" diagonal display equivalent
    // Reference: 160x45 terminal ≈ 7200 cells ≈ 20" diagonal at typical font size
    glitch_interval_base_ms: u64 = 30000, // 30 seconds base interval
    glitch_reference_area: u32 = 7200, // reference terminal area (cols × lines)
    active_glitch_line: u16 = 0xFFFF,
    active_glitch_col: u16 = 0xFFFF,
    glitch_duration_ms: u64 = 150, // how long each glitch lasts
    next_glitch_interval_ns: u64 = 0, // time until next glitch (calculated)

    seed: u64,
    initial_seed: u64,

    color_mode: types.ColorMode = .MONO,
    num_color_pairs: c_int = 7,
    usr_colors: std.ArrayList(types.ColorContent),

    const Droplet = struct {
        p_cloud: ?*Cloud = null,
        is_alive: bool = false,
        // When horizontal=false: bound_col is the fixed x column, head_pos moves downward (rows).
        // When horizontal=true:  bound_col is the fixed y row,    head_pos moves rightward (cols).
        horizontal: bool = false,
        bound_col: u16 = 0xFFFF,
        char_pool_idx: u16 = 0xFFFF,
        length: u16 = 0xFFFF,
        chars_per_sec: f32 = 0.0,
        last_time: time.Instant = undefined,
        head_pos: f32 = 0.0,
        last_drawn_head: i32 = -1000,
        last_drawn_tail: i32 = -1000,

        pub fn reset(self: *Droplet) void {
            self.p_cloud = null;
            self.is_alive = false;
            self.horizontal = false;
            self.bound_col = 0xFFFF;
            self.char_pool_idx = 0xFFFF;
            self.length = 0xFFFF;
            self.chars_per_sec = 0.0;
            self.head_pos = 0.0;
            self.last_drawn_head = -1000;
            self.last_drawn_tail = -1000;
        }

        pub fn activate(self: *Droplet, cur_time: time.Instant) void {
            self.is_alive = true;
            self.last_time = cur_time;
        }

        /// Get virtual tail position (head - length)
        pub fn getTailPos(self: *const Droplet) f32 {
            return self.head_pos - @as(f32, @floatFromInt(self.length));
        }

        pub fn advance(self: *Droplet, cur_time: time.Instant) void {
            const cloud = self.p_cloud orelse return;
            const elapsed_ns = cur_time.since(self.last_time);
            const elapsed_sec = @as(f32, @floatFromInt(elapsed_ns)) / 1.0e9;

            self.head_pos += self.chars_per_sec * elapsed_sec;

            const tail_pos = self.getTailPos();

            if (self.horizontal) {
                // Kill when tail exits the right edge
                if (tail_pos >= @as(f32, @floatFromInt(cloud.cols))) {
                    self.is_alive = false;
                }
            } else {
                // Allow other droplets to spawn once our tail clears the top quarter
                const thresh = @as(f32, @floatFromInt(cloud.lines)) / 4.0;
                if (tail_pos > thresh) {
                    cloud.setColumnSpawn(self.bound_col, true);
                }
                // Kill when tail exits the bottom
                if (tail_pos >= @as(f32, @floatFromInt(cloud.lines))) {
                    self.is_alive = false;
                }
            }

            self.last_time = cur_time;
        }

        pub fn draw(self: *Droplet, cur_time: time.Instant, draw_everything: bool) void {
            _ = cur_time;
            const cloud = self.p_cloud orelse return;

            const head_int = @as(i32, @intFromFloat(@floor(self.head_pos)));
            const tail_int = @as(i32, @intFromFloat(@floor(self.getTailPos())));
            // For vertical droplets the axis limit is lines; for horizontal it is cols.
            const axis_limit_i32: i32 = if (self.horizontal) @as(i32, cloud.cols) else @as(i32, cloud.lines);

            // Erase the positions the tail has passed since the last frame.
            if (self.last_drawn_tail + 1 >= 0 and self.last_drawn_tail < axis_limit_i32) {
                var erase_pos = self.last_drawn_tail + 1;
                const erase_end = @min(tail_int + 1, axis_limit_i32);
                while (erase_pos < erase_end) : (erase_pos += 1) {
                    if (erase_pos >= 0) {
                        if (cloud.current_attr != null) {
                            term.attrReset();
                            cloud.current_attr = null;
                        }
                        if (self.horizontal) {
                            term.putAscii(self.bound_col, @intCast(erase_pos), ' ');
                        } else {
                            term.putAscii(@intCast(erase_pos), self.bound_col, ' ');
                        }
                    }
                }
            }

            // Calculate visible range (clipped to screen).
            const visible_start = @max(tail_int + 1, 0);
            const visible_end = @min(head_int, axis_limit_i32 - 1);

            if (visible_start > visible_end) {
                self.last_drawn_head = head_int;
                self.last_drawn_tail = tail_int;
                return;
            }

            var pos = visible_start;
            while (pos <= visible_end) : (pos += 1) {
                const pos_u16 = @as(u16, @intCast(pos));
                // For glitch / char lookup keep the same coordinate convention as vertical.
                const is_glitched = if (self.horizontal) false else cloud.isGlitched(pos_u16, self.bound_col);
                const char_entry = cloud.getChar(pos_u16, self.char_pool_idx);

                var cl = types.CharLoc.MIDDLE;
                if (pos == tail_int + 1) {
                    cl = types.CharLoc.TAIL;
                } else if (pos == head_int) {
                    cl = types.CharLoc.HEAD;
                }

                if (!draw_everything and !is_glitched and cl == types.CharLoc.MIDDLE and
                    pos < self.last_drawn_head and pos > self.last_drawn_tail and
                    cloud.shading_mode != .DISTANCE_FROM_HEAD)
                {
                    continue;
                }

                var attr = types.CharAttr{ .color_pair = 0, .is_bold = false };
                const dist_from_head = @as(u16, @intCast(head_int - pos));
                cloud.getAttr(pos_u16, self.bound_col, char_entry.codepoint, cl, &attr, dist_from_head, self.length);

                const needs_attr_change = if (cloud.current_attr) |ca|
                    ca.color_pair != attr.color_pair or ca.is_bold != attr.is_bold
                else
                    true;

                if (needs_attr_change) {
                    if (cloud.color_mode != .MONO and attr.color_pair > 0) {
                        term.attrSet(attr.is_bold, @intCast(attr.color_pair));
                    } else if (attr.is_bold) {
                        term.attrBoldOn();
                    } else {
                        term.attrReset();
                    }
                    cloud.current_attr = attr;
                }

                if (self.horizontal) {
                    term.putEntry(self.bound_col, pos_u16, char_entry);
                } else {
                    term.putEntry(pos_u16, self.bound_col, char_entry);
                }
            }

            self.last_drawn_head = head_int;
            self.last_drawn_tail = tail_int;
        }
    };

    pub fn init(allocator: std.mem.Allocator, io: time.Io, cm: types.ColorMode, def2ascii: bool) Cloud {
        var self: Cloud = undefined;
        self.allocator = allocator;
        self.io = io;
        self.droplets = std.ArrayList(Droplet).initCapacity(allocator, 0) catch @panic("OOM");
        self.active_droplets = std.ArrayList(usize).initCapacity(allocator, 0) catch @panic("OOM");
        self.chars = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.user_chars = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.char_pool = std.ArrayList(types.CharEntry).initCapacity(allocator, 0) catch @panic("OOM");
        self.glitch_pool = std.ArrayList(u21).initCapacity(allocator, 0) catch @panic("OOM");
        self.glitch_map = std.ArrayList(bool).initCapacity(allocator, 0) catch @panic("OOM");
        self.color_pair_map = std.ArrayList(c_int).initCapacity(allocator, 0) catch @panic("OOM");
        self.col_stat = std.ArrayList(types.ColumnStatus).initCapacity(allocator, 0) catch @panic("OOM");
        self.row_stat = std.ArrayList(types.ColumnStatus).initCapacity(allocator, 0) catch @panic("OOM");
        self.message = std.ArrayList(types.MsgChr).initCapacity(allocator, 0) catch @panic("OOM");
        self.usr_colors = std.ArrayList(types.ColorContent).initCapacity(allocator, 0) catch @panic("OOM");
        self.current_attr = null;

        self.lines = 25;
        self.cols = 80;
        self.charset = .MIX; // Default to mixed mode: Japanese 80%, Cyrillic 10%, Braille 6%, ASCII 4%
        self.droplet_density = 1.5; // Denser rain for fuller effect
        self.droplets_per_sec = 8.0;
        self.chars_per_sec = 5.0; // Slightly faster for smoother animation
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
        self.max_droplets_per_column = 3; // Allow more droplets per column
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
        self.initial_seed = 0x1234567;

        return self;
    }

    pub fn deinit(self: *Cloud) void {
        self.droplets.deinit(self.allocator);
        self.active_droplets.deinit(self.allocator);
        self.chars.deinit(self.allocator);
        self.user_chars.deinit(self.allocator);
        self.char_pool.deinit(self.allocator);
        self.glitch_pool.deinit(self.allocator);
        self.glitch_map.deinit(self.allocator);
        self.color_pair_map.deinit(self.allocator);
        self.col_stat.deinit(self.allocator);
        self.row_stat.deinit(self.allocator);
        self.message.deinit(self.allocator);
        self.usr_colors.deinit(self.allocator);
    }

    pub fn setSeed(self: *Cloud, s: u64) void {
        self.seed = s;
        self.initial_seed = s;
    }

    pub fn setCharset(self: *Cloud, new_charset: types.Charset) void {
        self.charset = new_charset;
        self.buildCharacterPool() catch {};
    }

    pub fn rain(self: *Cloud) void {
        if (self.pause) return;

        const cur_time = time.Instant.now(self.io);

        // Handle time-based glitch system
        if (self.glitchy) {
            self.updateGlitch(cur_time);
        }

        self.spawnDroplets(cur_time);

        if (self.force_draw_everything) {
            term.clearScreen();
        }

        // Update and draw all active droplets
        // Use index-based iteration to allow removal during iteration
        var i: usize = 0;
        while (i < self.active_droplets.items.len) {
            const droplet_idx = self.active_droplets.items[i];
            const droplet = &self.droplets.items[droplet_idx];

            droplet.advance(cur_time);
            // Always draw even when the droplet just died so the erase pass runs
            // and clears any characters remaining at the bottom of the screen.
            droplet.draw(cur_time, self.force_draw_everything);

            if (!droplet.is_alive) {
                // Droplet died — release the slot in whichever axis it occupied
                if (droplet.horizontal) {
                    self.row_stat.items[droplet.bound_col].num_droplets -= 1;
                    self.row_stat.items[droplet.bound_col].can_spawn = true;
                } else {
                    self.col_stat.items[droplet.bound_col].num_droplets -= 1;
                    self.col_stat.items[droplet.bound_col].can_spawn = true;
                }

                // Remove from active list using swap-with-last
                self.active_droplets.items[i] = self.active_droplets.items[self.active_droplets.items.len - 1];
                _ = self.active_droplets.pop();
                // Don't increment i since we swapped a new element to position i
            } else {
                i += 1;
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
    fn updateGlitch(self: *Cloud, cur_time: time.Instant) void {
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
        // Xorshift32 - much better distribution than simple LCG
        self.seed ^= self.seed << 13;
        self.seed ^= self.seed >> 17;
        self.seed ^= self.seed << 5;
        return @as(f32, @floatFromInt(self.seed & 0xFFFFFF)) / 16777216.0;
    }

    fn randomInt(self: *Cloud, max: u32) u32 {
        return @intFromFloat(self.randomFloat() * @as(f32, @floatFromInt(max)));
    }

    pub fn reset(self: *Cloud) !void {
        self.lines = term.lines();
        self.cols = term.cols();

        // Handle invalid terminal dimensions (e.g., headless environments)
        if (self.lines == 0) self.lines = 24;
        if (self.cols == 0) self.cols = 80;

        // Calculate droplets_per_sec based on screen size (like C++ version)
        // Formula: cols * density / (lines / chars_per_sec)
        const time_to_fill_screen = @as(f32, @floatFromInt(self.lines)) / self.chars_per_sec;
        self.droplets_per_sec = @as(f32, @floatFromInt(self.cols)) * self.droplet_density / time_to_fill_screen;

        // Resize droplets array based on terminal size
        const max_droplets = self.cols; // One potential droplet per column
        try self.droplets.resize(self.allocator, max_droplets);
        // Initialize all droplets as inactive
        for (self.droplets.items) |*droplet| {
            droplet.reset();
        }

        const num_droplets = @as(usize, @intFromFloat(@round(2.0 * @as(f32, @floatFromInt(self.cols)))));
        try self.droplets.resize(self.allocator, num_droplets);
        for (self.droplets.items) |*droplet| {
            droplet.* = Droplet{};
        }

        // Initialize active droplets tracking (same capacity as droplets)
        try self.active_droplets.resize(self.allocator, num_droplets);
        self.active_droplets.clearRetainingCapacity();

        // Reset seed
        self.seed = self.initial_seed;

        const screen_size = self.lines * self.cols;
        try self.glitch_map.resize(self.allocator, screen_size);
        try self.color_pair_map.resize(self.allocator, screen_size);
        try self.col_stat.resize(self.allocator, self.cols);
        try self.row_stat.resize(self.allocator, self.lines);

        for (0..screen_size) |i| {
            self.glitch_map.items[i] = false; // Not used anymore, time-based glitch instead
            self.color_pair_map.items[i] = @as(c_int, @intCast(self.randomInt(@as(u32, @intCast(self.num_color_pairs - 1))) + 1));
        }

        // Reset active glitch
        self.active_glitch_line = 0xFFFF;
        self.active_glitch_col = 0xFFFF;

        // Initialize column and row status
        for (0..self.cols) |i| {
            self.col_stat.items[i] = types.ColumnStatus{
                .max_speed_pct = 1.0,
                .num_droplets = 0,
                .can_spawn = true,
            };
        }
        for (0..self.lines) |i| {
            self.row_stat.items[i] = types.ColumnStatus{
                .max_speed_pct = 1.0,
                .num_droplets = 0,
                .can_spawn = true,
            };
        }

        try self.char_pool.resize(self.allocator, types.CHAR_POOL_SIZE);
        try self.glitch_pool.resize(self.allocator, types.GLITCH_POOL_SIZE);

        // Build character pool based on charset
        try self.buildCharacterPool();
        try self.buildGlitchPool();

        // Reset message positions
        self.resetMessage();

        // Initialize timestamps
        const now = time.Instant.now(self.io);
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
            try self.message.append(self.allocator, types.MsgChr.init(@as(u8, char)));
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

            msg_char.draw = term.isCellEmpty(msg_char.line, msg_char.col);
        }
    }

    fn drawMessage(self: *Cloud) void {
        for (self.message.items) |msg_char| {
            if (!msg_char.draw) continue;

            const bold = self.bold_mode != .OFF;
            if (self.color_mode != .MONO) {
                term.attrSet(bold, @intCast(self.num_color_pairs));
            } else if (bold) {
                term.attrBoldOn();
            }

            term.putAscii(msg_char.line, msg_char.col, msg_char.val);
            term.attrReset();
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
            // Runic: U+16A0 to U+16EA (actual Runic letters, avoiding undefined code points)
            ranges[num_ranges] = .{ .start = 0x16A0, .end = 0x16EA };
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

            self.char_pool.items[i] = .{
                .codepoint = selected_char,
                .utf8 = blk: {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(selected_char, &buf) catch 1;
                    buf[len] = 0;
                    break :blk buf;
                },
                .utf8_len = std.unicode.utf8CodepointSequenceLength(selected_char) catch 1,
            };
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

            self.char_pool.items[i] = .{
                .codepoint = selected_char,
                .utf8 = blk: {
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(selected_char, &buf) catch 1;
                    buf[len] = 0;
                    break :blk buf;
                },
                .utf8_len = std.unicode.utf8CodepointSequenceLength(selected_char) catch 1,
            };
        }
    }

    fn buildGlitchPool(self: *Cloud) !void {
        // Use same ASCII characters for glitching
        for (0..types.GLITCH_POOL_SIZE) |i| {
            self.glitch_pool.items[i] = @as(u21, @intCast(33 + (i % 94)));
        }
    }

    pub fn spawnDroplets(self: *Cloud, cur_time: time.Instant) void {
        const elapsed_ns = cur_time.since(self.last_spawn_time);
        const elapsed_sec = @as(f32, @floatFromInt(elapsed_ns)) / 1.0e9;
        const droplets_to_spawn = @min(@as(usize, @intFromFloat(@round(elapsed_sec * self.droplets_per_sec))), self.droplets.items.len);

        if (droplets_to_spawn == 0) return;

        const horizontal = (self.charset == .ARABIC);

        var spawned: usize = 0;
        for (0..droplets_to_spawn) |_| {
            // For Arabic, droplets travel left→right along a fixed row.
            // For all other charsets, droplets travel top→bottom along a fixed column.
            const axis_bound: u16 = if (horizontal)
                @as(u16, @intCast(self.randomInt(@as(u32, self.lines))))
            else
                @as(u16, @intCast(self.randomInt(@as(u32, self.cols))));

            const stat = if (horizontal)
                &self.row_stat.items[axis_bound]
            else
                &self.col_stat.items[axis_bound];

            if (!stat.can_spawn or stat.num_droplets >= self.max_droplets_per_column) {
                continue;
            }

            // Find inactive droplet
            for (self.droplets.items, 0..) |*droplet, idx| {
                if (!droplet.is_alive) {
                    droplet.reset();
                    droplet.p_cloud = self;
                    droplet.horizontal = horizontal;
                    droplet.bound_col = axis_bound;
                    droplet.char_pool_idx = @as(u16, @intCast(self.randomInt(types.CHAR_POOL_SIZE)));

                    // Length relative to the axis being traveled
                    const axis_size: u32 = if (horizontal) @as(u32, self.cols) else @as(u32, self.lines);
                    const min_length: u32 = 5;
                    const max_length: u32 = @max(axis_size - 1, min_length);
                    const length_range = max_length - min_length + 1;
                    droplet.length = @as(u16, @intCast(self.randomInt(length_range) + min_length));

                    droplet.chars_per_sec = self.chars_per_sec * (0.3333333 + self.randomFloat() * 0.6666667);

                    // Start off-screen so the droplet enters with its trail already forming
                    const start_offset = self.randomFloat() * @as(f32, @floatFromInt(droplet.length));
                    droplet.head_pos = -start_offset;

                    droplet.activate(cur_time);
                    stat.can_spawn = false;
                    stat.num_droplets += 1;

                    self.active_droplets.appendAssumeCapacity(idx);

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
        term.useDefaultColors();

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
                    // 16-step gradient using standard 256-color palette green entries.
                    // Avoids init_color() which silently fails on macOS ncurses.
                    self.num_color_pairs = 16;
                    term.initPair(1, 22, @intCast(bg_color)); // #005f00 very dark green
                    term.initPair(2, 28, @intCast(bg_color)); // #008700
                    term.initPair(3, 34, @intCast(bg_color)); // #00af00
                    term.initPair(4, 40, @intCast(bg_color)); // #00d700
                    term.initPair(5, 46, @intCast(bg_color)); // #00ff00 pure bright green
                    term.initPair(6, 47, @intCast(bg_color)); // #00ff5f
                    term.initPair(7, 48, @intCast(bg_color)); // #00ff87
                    term.initPair(8, 83, @intCast(bg_color)); // #5fff5f
                    term.initPair(9, 84, @intCast(bg_color)); // #5fff87
                    term.initPair(10, 118, @intCast(bg_color)); // #87ff00
                    term.initPair(11, 119, @intCast(bg_color)); // #87ff5f
                    term.initPair(12, 120, @intCast(bg_color)); // #87ff87
                    term.initPair(13, 121, @intCast(bg_color)); // #87ffaf
                    term.initPair(14, 157, @intCast(bg_color)); // #afffaf
                    term.initPair(15, 194, @intCast(bg_color)); // #d7ffd7
                    term.initPair(16, 15, @intCast(bg_color)); // white head glow
                } else if (self.color_mode == .COLOR256) {
                    // 256-color mode - use more color pairs for smoother gradient
                    self.num_color_pairs = 12;
                    term.initPair(1, 22, @intCast(bg_color)); // Very dark green
                    term.initPair(2, 28, @intCast(bg_color)); // Dark green
                    term.initPair(3, 34, @intCast(bg_color)); // Medium-dark green
                    term.initPair(4, 40, @intCast(bg_color)); // Medium green
                    term.initPair(5, 41, @intCast(bg_color)); // Medium green
                    term.initPair(6, 42, @intCast(bg_color)); // Medium-bright green
                    term.initPair(7, 48, @intCast(bg_color)); // Bright green
                    term.initPair(8, 83, @intCast(bg_color)); // Bright green
                    term.initPair(9, 84, @intCast(bg_color)); // Very bright green
                    term.initPair(10, 120, @intCast(bg_color)); // Bright green-white
                    term.initPair(11, 157, @intCast(bg_color)); // Near white-green
                    term.initPair(12, 15, @intCast(bg_color)); // White (head glow)
                } else if (self.color_mode == .COLOR16) {
                    self.num_color_pairs = 3;
                    term.initPair(1, 2, @intCast(bg_color)); // Dark green
                    term.initPair(2, 10, @intCast(bg_color)); // Bright green
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 7;
                    term.initPair(1, 234, @intCast(bg_color));
                    term.initPair(2, 22, @intCast(bg_color));
                    term.initPair(3, 28, @intCast(bg_color));
                    term.initPair(4, 35, @intCast(bg_color));
                    term.initPair(5, 78, @intCast(bg_color));
                    term.initPair(6, 84, @intCast(bg_color));
                    term.initPair(7, 159, @intCast(bg_color));
                }
            },
            .USER => {
                if (self.color_mode == .TRUECOLOR) {
                    // Initialize user-defined truecolor colors
                    for (self.usr_colors.items) |color_content| {
                        if (color_content.r != 0x7FFF and color_content.g != 0x7FFF and color_content.b != 0x7FFF) {
                            term.initColor(@intCast(color_content.color), @intCast(color_content.r), @intCast(color_content.g), @intCast(color_content.b));
                        }
                    }
                }
                bg_color = @intCast(self.usr_colors.items[0].color);
                self.num_color_pairs = 0;
                for (1..self.usr_colors.items.len) |i| {
                    term.initPair(@intCast(i), @intCast(self.usr_colors.items[i].color), @intCast(bg_color));
                    self.num_color_pairs += 1;
                }
            },
            .GOLD => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 400, 300, 0); // Dark gold
                    term.initColor(231, 500, 380, 0); // Medium-dark gold
                    term.initColor(232, 600, 450, 0); // Medium gold
                    term.initColor(233, 700, 520, 0); // Medium gold
                    term.initColor(234, 780, 600, 50); // Bright gold
                    term.initColor(235, 850, 680, 100); // Bright gold
                    term.initColor(236, 900, 750, 150); // Very bright gold
                    term.initColor(237, 940, 820, 250); // Near white gold
                    term.initColor(238, 960, 880, 400); // White-gold
                    term.initColor(239, 980, 920, 550); // Bright white-gold
                    term.initColor(240, 990, 960, 750); // Almost white
                    term.initColor(241, 1000, 1000, 900); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 94, @intCast(bg_color)); // Dark orange/brown
                    term.initPair(2, 136, @intCast(bg_color)); // Dark gold
                    term.initPair(3, 178, @intCast(bg_color)); // Gold
                    term.initPair(4, 214, @intCast(bg_color)); // Orange-gold
                    term.initPair(5, 220, @intCast(bg_color)); // Bright gold
                    term.initPair(6, 221, @intCast(bg_color)); // Bright gold
                    term.initPair(7, 227, @intCast(bg_color)); // Yellow-gold
                    term.initPair(8, 228, @intCast(bg_color)); // Light yellow
                    term.initPair(9, 229, @intCast(bg_color)); // Very light yellow
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 3, @intCast(bg_color)); // Yellow/brown
                    term.initPair(2, 11, @intCast(bg_color)); // Bright yellow
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .RED => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 300, 0, 0); // Dark red
                    term.initColor(231, 450, 0, 0); // Medium-dark red
                    term.initColor(232, 580, 0, 0); // Medium red
                    term.initColor(233, 700, 50, 50); // Medium red
                    term.initColor(234, 800, 100, 100); // Bright red
                    term.initColor(235, 880, 150, 150); // Bright red
                    term.initColor(236, 940, 250, 250); // Very bright red
                    term.initColor(237, 970, 400, 400); // Pink-red
                    term.initColor(238, 990, 550, 550); // Light red
                    term.initColor(239, 1000, 700, 700); // Very light red
                    term.initColor(240, 1000, 850, 850); // Near white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 52, @intCast(bg_color)); // Very dark red
                    term.initPair(2, 88, @intCast(bg_color)); // Dark red
                    term.initPair(3, 124, @intCast(bg_color)); // Medium red
                    term.initPair(4, 160, @intCast(bg_color)); // Red
                    term.initPair(5, 196, @intCast(bg_color)); // Bright red
                    term.initPair(6, 203, @intCast(bg_color)); // Light red
                    term.initPair(7, 210, @intCast(bg_color)); // Pink-red
                    term.initPair(8, 217, @intCast(bg_color)); // Light pink
                    term.initPair(9, 224, @intCast(bg_color)); // Very light pink
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 1, @intCast(bg_color)); // Red
                    term.initPair(2, 9, @intCast(bg_color)); // Bright red
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .BLUE => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 0, 0, 300); // Dark blue
                    term.initColor(231, 0, 50, 450); // Medium-dark blue
                    term.initColor(232, 0, 100, 580); // Medium blue
                    term.initColor(233, 50, 150, 700); // Medium blue
                    term.initColor(234, 100, 200, 800); // Bright blue
                    term.initColor(235, 150, 300, 880); // Bright blue
                    term.initColor(236, 250, 400, 940); // Very bright blue
                    term.initColor(237, 400, 550, 970); // Light blue
                    term.initColor(238, 550, 700, 990); // Very light blue
                    term.initColor(239, 700, 820, 1000); // Near white blue
                    term.initColor(240, 850, 920, 1000); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 17, @intCast(bg_color)); // Very dark blue
                    term.initPair(2, 18, @intCast(bg_color)); // Dark blue
                    term.initPair(3, 19, @intCast(bg_color)); // Medium-dark blue
                    term.initPair(4, 20, @intCast(bg_color)); // Medium blue
                    term.initPair(5, 21, @intCast(bg_color)); // Blue
                    term.initPair(6, 27, @intCast(bg_color)); // Bright blue
                    term.initPair(7, 33, @intCast(bg_color)); // Light blue
                    term.initPair(8, 39, @intCast(bg_color)); // Cyan-blue
                    term.initPair(9, 117, @intCast(bg_color)); // Very light blue
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 4, @intCast(bg_color)); // Blue
                    term.initPair(2, 12, @intCast(bg_color)); // Bright blue
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .CYAN => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 0, 200, 200); // Dark cyan
                    term.initColor(231, 0, 320, 320); // Medium-dark cyan
                    term.initColor(232, 0, 440, 440); // Medium cyan
                    term.initColor(233, 0, 560, 560); // Medium cyan
                    term.initColor(234, 0, 680, 680); // Bright cyan
                    term.initColor(235, 100, 780, 780); // Bright cyan
                    term.initColor(236, 200, 860, 860); // Very bright cyan
                    term.initColor(237, 350, 920, 920); // Light cyan
                    term.initColor(238, 500, 960, 960); // Very light cyan
                    term.initColor(239, 700, 980, 980); // Near white cyan
                    term.initColor(240, 850, 1000, 1000); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 23, @intCast(bg_color)); // Very dark cyan
                    term.initPair(2, 30, @intCast(bg_color)); // Dark cyan
                    term.initPair(3, 37, @intCast(bg_color)); // Medium cyan
                    term.initPair(4, 44, @intCast(bg_color)); // Cyan
                    term.initPair(5, 51, @intCast(bg_color)); // Bright cyan
                    term.initPair(6, 80, @intCast(bg_color)); // Light cyan
                    term.initPair(7, 87, @intCast(bg_color)); // Very light cyan
                    term.initPair(8, 123, @intCast(bg_color)); // Pale cyan
                    term.initPair(9, 159, @intCast(bg_color)); // Very pale cyan
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 6, @intCast(bg_color)); // Cyan
                    term.initPair(2, 14, @intCast(bg_color)); // Bright cyan
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .PURPLE => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 200, 0, 300); // Dark purple
                    term.initColor(231, 300, 0, 450); // Medium-dark purple
                    term.initColor(232, 400, 50, 580); // Medium purple
                    term.initColor(233, 500, 100, 700); // Medium purple
                    term.initColor(234, 600, 150, 800); // Bright purple
                    term.initColor(235, 700, 250, 880); // Bright purple
                    term.initColor(236, 780, 350, 940); // Very bright purple
                    term.initColor(237, 850, 500, 970); // Light purple
                    term.initColor(238, 900, 650, 990); // Very light purple
                    term.initColor(239, 950, 780, 1000); // Near white purple
                    term.initColor(240, 980, 900, 1000); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 53, @intCast(bg_color)); // Very dark purple
                    term.initPair(2, 54, @intCast(bg_color)); // Dark purple
                    term.initPair(3, 55, @intCast(bg_color)); // Medium-dark purple
                    term.initPair(4, 56, @intCast(bg_color)); // Medium purple
                    term.initPair(5, 93, @intCast(bg_color)); // Purple
                    term.initPair(6, 129, @intCast(bg_color)); // Bright purple
                    term.initPair(7, 165, @intCast(bg_color)); // Magenta-purple
                    term.initPair(8, 177, @intCast(bg_color)); // Light purple
                    term.initPair(9, 183, @intCast(bg_color)); // Very light purple
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 5, @intCast(bg_color)); // Magenta
                    term.initPair(2, 13, @intCast(bg_color)); // Bright magenta
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .PINK, .PINK2 => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 500, 100, 300); // Dark pink
                    term.initColor(231, 600, 150, 400); // Medium-dark pink
                    term.initColor(232, 700, 200, 480); // Medium pink
                    term.initColor(233, 800, 280, 550); // Medium pink
                    term.initColor(234, 880, 350, 620); // Bright pink
                    term.initColor(235, 940, 450, 700); // Bright pink
                    term.initColor(236, 980, 550, 780); // Very bright pink
                    term.initColor(237, 1000, 650, 850); // Light pink
                    term.initColor(238, 1000, 750, 900); // Very light pink
                    term.initColor(239, 1000, 850, 950); // Near white pink
                    term.initColor(240, 1000, 930, 980); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 125, @intCast(bg_color)); // Dark pink
                    term.initPair(2, 161, @intCast(bg_color)); // Medium-dark pink
                    term.initPair(3, 162, @intCast(bg_color)); // Medium pink
                    term.initPair(4, 198, @intCast(bg_color)); // Pink
                    term.initPair(5, 199, @intCast(bg_color)); // Bright pink
                    term.initPair(6, 206, @intCast(bg_color)); // Hot pink
                    term.initPair(7, 213, @intCast(bg_color)); // Light pink
                    term.initPair(8, 218, @intCast(bg_color)); // Very light pink
                    term.initPair(9, 225, @intCast(bg_color)); // Pale pink
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 5, @intCast(bg_color)); // Magenta
                    term.initPair(2, 13, @intCast(bg_color)); // Bright magenta
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .YELLOW => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 400, 400, 0); // Dark yellow
                    term.initColor(231, 520, 520, 0); // Medium-dark yellow
                    term.initColor(232, 640, 640, 0); // Medium yellow
                    term.initColor(233, 750, 750, 0); // Medium yellow
                    term.initColor(234, 850, 850, 0); // Bright yellow
                    term.initColor(235, 920, 920, 100); // Bright yellow
                    term.initColor(236, 960, 960, 250); // Very bright yellow
                    term.initColor(237, 980, 980, 400); // Light yellow
                    term.initColor(238, 1000, 1000, 550); // Very light yellow
                    term.initColor(239, 1000, 1000, 700); // Near white yellow
                    term.initColor(240, 1000, 1000, 850); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 58, @intCast(bg_color)); // Dark yellow
                    term.initPair(2, 100, @intCast(bg_color)); // Olive
                    term.initPair(3, 142, @intCast(bg_color)); // Medium yellow
                    term.initPair(4, 184, @intCast(bg_color)); // Yellow
                    term.initPair(5, 226, @intCast(bg_color)); // Bright yellow
                    term.initPair(6, 227, @intCast(bg_color)); // Light yellow
                    term.initPair(7, 228, @intCast(bg_color)); // Very light yellow
                    term.initPair(8, 229, @intCast(bg_color)); // Pale yellow
                    term.initPair(9, 230, @intCast(bg_color)); // Very pale yellow
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 3, @intCast(bg_color)); // Yellow
                    term.initPair(2, 11, @intCast(bg_color)); // Bright yellow
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .ORANGE => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 500, 200, 0); // Dark orange
                    term.initColor(231, 620, 280, 0); // Medium-dark orange
                    term.initColor(232, 740, 360, 0); // Medium orange
                    term.initColor(233, 840, 440, 0); // Medium orange
                    term.initColor(234, 920, 520, 0); // Bright orange
                    term.initColor(235, 970, 600, 50); // Bright orange
                    term.initColor(236, 1000, 680, 150); // Very bright orange
                    term.initColor(237, 1000, 760, 300); // Light orange
                    term.initColor(238, 1000, 840, 450); // Very light orange
                    term.initColor(239, 1000, 900, 600); // Near white orange
                    term.initColor(240, 1000, 950, 780); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 94, @intCast(bg_color)); // Dark orange
                    term.initPair(2, 130, @intCast(bg_color)); // Brown-orange
                    term.initPair(3, 166, @intCast(bg_color)); // Medium orange
                    term.initPair(4, 202, @intCast(bg_color)); // Orange
                    term.initPair(5, 208, @intCast(bg_color)); // Bright orange
                    term.initPair(6, 214, @intCast(bg_color)); // Light orange
                    term.initPair(7, 215, @intCast(bg_color)); // Very light orange
                    term.initPair(8, 216, @intCast(bg_color)); // Pale orange
                    term.initPair(9, 223, @intCast(bg_color)); // Very pale orange
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 1, @intCast(bg_color)); // Red (closest to orange)
                    term.initPair(2, 3, @intCast(bg_color)); // Yellow
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .GRAY => {
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 150, 150, 150); // Very dark gray
                    term.initColor(231, 250, 250, 250); // Dark gray
                    term.initColor(232, 350, 350, 350); // Medium-dark gray
                    term.initColor(233, 450, 450, 450); // Medium gray
                    term.initColor(234, 550, 550, 550); // Medium gray
                    term.initColor(235, 650, 650, 650); // Light gray
                    term.initColor(236, 730, 730, 730); // Light gray
                    term.initColor(237, 810, 810, 810); // Very light gray
                    term.initColor(238, 880, 880, 880); // Near white
                    term.initColor(239, 930, 930, 930); // Almost white
                    term.initColor(240, 970, 970, 970); // Almost white
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 236, @intCast(bg_color)); // Very dark gray
                    term.initPair(2, 238, @intCast(bg_color)); // Dark gray
                    term.initPair(3, 240, @intCast(bg_color)); // Medium-dark gray
                    term.initPair(4, 242, @intCast(bg_color)); // Medium gray
                    term.initPair(5, 245, @intCast(bg_color)); // Medium gray
                    term.initPair(6, 248, @intCast(bg_color)); // Light gray
                    term.initPair(7, 250, @intCast(bg_color)); // Very light gray
                    term.initPair(8, 252, @intCast(bg_color)); // Near white
                    term.initPair(9, 254, @intCast(bg_color)); // Almost white
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 8, @intCast(bg_color)); // Dark gray
                    term.initPair(2, 7, @intCast(bg_color)); // Light gray
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .VAPORWAVE => {
                // Pink to cyan gradient
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 600, 100, 400); // Dark magenta
                    term.initColor(231, 700, 150, 500); // Medium magenta
                    term.initColor(232, 800, 200, 600); // Magenta
                    term.initColor(233, 900, 300, 700); // Bright magenta
                    term.initColor(234, 950, 400, 800); // Pink-magenta
                    term.initColor(235, 900, 500, 900); // Purple-pink
                    term.initColor(236, 700, 600, 950); // Blue-purple
                    term.initColor(237, 500, 700, 1000); // Cyan-blue
                    term.initColor(238, 300, 800, 1000); // Cyan
                    term.initColor(239, 200, 900, 1000); // Bright cyan
                    term.initColor(240, 400, 950, 1000); // Light cyan
                    term.initColor(241, 1000, 1000, 1000); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 53, @intCast(bg_color)); // Dark purple
                    term.initPair(2, 127, @intCast(bg_color)); // Magenta
                    term.initPair(3, 163, @intCast(bg_color)); // Pink
                    term.initPair(4, 199, @intCast(bg_color)); // Hot pink
                    term.initPair(5, 171, @intCast(bg_color)); // Purple-pink
                    term.initPair(6, 135, @intCast(bg_color)); // Blue-purple
                    term.initPair(7, 75, @intCast(bg_color)); // Blue
                    term.initPair(8, 39, @intCast(bg_color)); // Cyan-blue
                    term.initPair(9, 51, @intCast(bg_color)); // Cyan
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 5, @intCast(bg_color)); // Magenta
                    term.initPair(2, 14, @intCast(bg_color)); // Cyan
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
            .RAINBOW => {
                // Rainbow cycles through colors
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 1000, 0, 0); // Red
                    term.initColor(231, 1000, 500, 0); // Orange
                    term.initColor(232, 1000, 1000, 0); // Yellow
                    term.initColor(233, 500, 1000, 0); // Yellow-green
                    term.initColor(234, 0, 1000, 0); // Green
                    term.initColor(235, 0, 1000, 500); // Cyan-green
                    term.initColor(236, 0, 1000, 1000); // Cyan
                    term.initColor(237, 0, 500, 1000); // Blue-cyan
                    term.initColor(238, 0, 0, 1000); // Blue
                    term.initColor(239, 500, 0, 1000); // Purple
                    term.initColor(240, 1000, 0, 1000); // Magenta
                    term.initColor(241, 1000, 0, 500); // Pink-red
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 12;
                    term.initPair(1, 196, @intCast(bg_color)); // Red
                    term.initPair(2, 208, @intCast(bg_color)); // Orange
                    term.initPair(3, 226, @intCast(bg_color)); // Yellow
                    term.initPair(4, 118, @intCast(bg_color)); // Yellow-green
                    term.initPair(5, 46, @intCast(bg_color)); // Green
                    term.initPair(6, 48, @intCast(bg_color)); // Cyan-green
                    term.initPair(7, 51, @intCast(bg_color)); // Cyan
                    term.initPair(8, 33, @intCast(bg_color)); // Blue-cyan
                    term.initPair(9, 21, @intCast(bg_color)); // Blue
                    term.initPair(10, 93, @intCast(bg_color)); // Purple
                    term.initPair(11, 201, @intCast(bg_color)); // Magenta
                    term.initPair(12, 199, @intCast(bg_color)); // Pink
                } else {
                    self.num_color_pairs = 6;
                    term.initPair(1, 1, @intCast(bg_color)); // Red
                    term.initPair(2, 3, @intCast(bg_color)); // Yellow
                    term.initPair(3, 2, @intCast(bg_color)); // Green
                    term.initPair(4, 6, @intCast(bg_color)); // Cyan
                    term.initPair(5, 4, @intCast(bg_color)); // Blue
                    term.initPair(6, 5, @intCast(bg_color)); // Magenta
                }
            },
            .GREEN2, .GREEN3 => {
                // Alternative green - brighter/different shade
                if (self.color_mode == .TRUECOLOR) {
                    self.num_color_pairs = 12;
                    term.initColor(230, 0, 200, 100); // Dark teal-green
                    term.initColor(231, 0, 300, 150); // Medium-dark
                    term.initColor(232, 0, 400, 200); // Medium
                    term.initColor(233, 50, 520, 260); // Medium
                    term.initColor(234, 100, 640, 320); // Bright
                    term.initColor(235, 150, 760, 380); // Bright
                    term.initColor(236, 220, 860, 430); // Very bright
                    term.initColor(237, 320, 930, 500); // Light
                    term.initColor(238, 450, 970, 600); // Very light
                    term.initColor(239, 600, 990, 720); // Near white
                    term.initColor(240, 780, 1000, 850); // Almost white
                    term.initColor(241, 950, 1000, 960); // White (head glow)
                    var i: c_short = 1;
                    while (i <= 12) : (i += 1) {
                        term.initPair(i, 229 + i, @intCast(bg_color));
                    }
                } else if (self.color_mode == .COLOR256) {
                    self.num_color_pairs = 10;
                    term.initPair(1, 22, @intCast(bg_color)); // Very dark green
                    term.initPair(2, 29, @intCast(bg_color)); // Dark green
                    term.initPair(3, 36, @intCast(bg_color)); // Teal-green
                    term.initPair(4, 43, @intCast(bg_color)); // Medium green
                    term.initPair(5, 49, @intCast(bg_color)); // Bright green
                    term.initPair(6, 86, @intCast(bg_color)); // Light green
                    term.initPair(7, 122, @intCast(bg_color)); // Very light green
                    term.initPair(8, 158, @intCast(bg_color)); // Pale green
                    term.initPair(9, 194, @intCast(bg_color)); // Very pale green
                    term.initPair(10, 15, @intCast(bg_color)); // White (head)
                } else {
                    self.num_color_pairs = 3;
                    term.initPair(1, 2, @intCast(bg_color)); // Green
                    term.initPair(2, 10, @intCast(bg_color)); // Bright green
                    term.initPair(3, 15, @intCast(bg_color)); // White (head)
                }
            },
        }
        const screen_size = self.lines * self.cols;
        try self.color_pair_map.resize(self.allocator, screen_size);
        for (0..screen_size) |i| {
            self.color_pair_map.items[i] = @as(c_int, @intCast(self.randomInt(@as(u32, @intCast(self.num_color_pairs - 1))) + 1));
        }

        if (self.color_mode != .MONO) {
            term.setBackgroundPair(1);
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

    pub fn getChar(self: *const Cloud, line: u16, char_pool_idx: u16) *const types.CharEntry {
        const pool_idx = @as(usize, char_pool_idx) % self.char_pool.items.len;
        const line_val = @as(usize, line);
        // Prime stride and XOR mixing to avoid sequential/alphabetical patterns
        const stride: usize = 37;
        const mix = (pool_idx *% 7) ^ (line_val *% 13);
        const char_idx = (pool_idx +% line_val *% stride +% mix) % self.char_pool.items.len;
        return &self.char_pool.items[char_idx];
    }

    pub fn setColumnSpawn(self: *Cloud, col: u16, b: bool) void {
        if (col < self.col_stat.items.len) {
            self.col_stat.items[col].can_spawn = b;
        }
    }

    pub fn togglePause(self: *Cloud) void {
        self.pause = !self.pause;
        if (self.pause) {
            self.pause_time = time.Instant.now(self.io);
        } else {
            const now = time.Instant.now(self.io);
            const elapsed = now.since(self.pause_time);
            _ = elapsed; // For now, just reset spawn time
            self.last_spawn_time = now;
        }
    }
};
