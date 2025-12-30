const std = @import("std");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE_EXTENDED", "1");
    @cInclude("ncurses.h");
});

const types = @import("types.zig");

const Droplet = struct {
    p_cloud: ?*Cloud = null,
    is_alive: bool = false,
    is_head_crawling: bool = false,
    is_tail_crawling: bool = false,
    bound_col: u16 = 0xFFFF,
    head_put_line: u16 = 0,
    head_cur_line: u16 = 0,
    tail_put_line: u16 = 0xFFFF,
    tail_cur_line: u16 = 0,
    end_line: u16 = 0xFFFF,
    char_pool_idx: u16 = 0xFFFF,
    length: u16 = 0xFFFF,
    chars_per_sec: f32 = 0.0,
    last_time: std.time.Instant = undefined,
    head_stop_time: std.time.Instant = undefined,
    time_to_linger: u64 = 0,

    pub fn init() Droplet {
        var self = Droplet{};
        self.reset();
        return self;
    }

    pub fn initFull(cl: *Cloud, col: u16, end_line: u16, cp_idx: u16, len: u16, cps: f32, ttl_ms: u64) Droplet {
        var self = Droplet{};
        self.reset();
        self.p_cloud = cl;
        self.bound_col = col;
        self.end_line = end_line;
        self.char_pool_idx = cp_idx;
        self.length = len;
        self.chars_per_sec = cps;
        self.time_to_linger = ttl_ms * std.time.ns_per_ms;
        return self;
    }

    pub fn reset(self: *Droplet) void {
        self.p_cloud = null;
        self.is_alive = false;
        self.is_head_crawling = false;
        self.is_tail_crawling = false;
        self.bound_col = 0xFFFF;
        self.head_put_line = 0;
        self.head_cur_line = 0;
        self.tail_put_line = 0xFFFF;
        self.tail_cur_line = 0;
        self.end_line = 0xFFFF;
        self.char_pool_idx = 0xFFFF;
        self.length = 0xFFFF;
        self.chars_per_sec = 0.0;
        self.last_time = std.time.Instant{};
        self.head_stop_time = std.time.Instant{};
        self.time_to_linger = 0;
    }

    pub fn activate(self: *Droplet, cur_time: std.time.Instant) void {
        self.is_alive = true;
        self.is_head_crawling = true;
        self.is_tail_crawling = true;
        self.last_time = cur_time;
    }

    pub fn advance(self: *Droplet, cur_time: std.time.Instant) void {
        const elapsed_ns = cur_time.since(self.last_time);
        const elapsed_sec = @as(f32, @floatFromInt(elapsed_ns)) / 1.0e9;
        const chars_advanced: u16 = @intFromFloat(@round(self.chars_per_sec * elapsed_sec));

        if (chars_advanced == 0) return;

        // Advance head
        if (self.is_head_crawling) {
            self.head_put_line +%= chars_advanced;
            if (self.head_put_line > self.end_line) {
                self.head_put_line = self.end_line;
            }

            if (self.head_put_line == self.end_line) {
                self.is_head_crawling = false;
                if (self.head_stop_time.since(std.time.nanoTimestamp()) > 0 or self.head_stop_time.ns_since_epoch == 0) {
                    self.head_stop_time = cur_time;
                    if (self.time_to_linger > 0) {
                        self.is_tail_crawling = false;
                    }
                }
            }
        }

        // Advance tail
        if (self.is_tail_crawling and (self.head_put_line >= self.length or self.head_put_line >= self.end_line)) {
            if (self.tail_put_line != 0xFFFF) {
                self.tail_put_line +%= chars_advanced;
            } else {
                self.tail_put_line = chars_advanced;
            }
            if (self.tail_put_line > self.end_line) {
                self.tail_put_line = self.end_line;
            }

            // Allow other droplets to spawn in this column
            const cloud = self.p_cloud orelse return;
            const thresh_line = cloud.lines / 4;
            if (self.tail_cur_line <= thresh_line and self.tail_put_line > thresh_line) {
                cloud.setColumnSpawn(self.bound_col, true);
            }
        }

        // Restart tail after lingering
        if (!self.is_tail_crawling) {
            const linger_elapsed = cur_time.since(self.head_stop_time);
            if (linger_elapsed >= self.time_to_linger) {
                self.is_tail_crawling = true;
            }
        }

        // Kill droplet when tail reaches head
        if (self.tail_put_line == self.head_put_line) {
            self.is_alive = false;
        }

        self.last_time = cur_time;
    }

    pub fn draw(self: *Droplet, cur_time: std.time.Instant, draw_everything: bool) void {
        const cloud = self.p_cloud orelse return;
        var start_line: u16 = 0;

        if (self.tail_put_line != 0xFFFF) {
            // Delete very end of tail
            var line = self.tail_cur_line;
            while (line <= self.tail_put_line) : (line +%= 1) {
                _ = c.mvaddch(@intCast(line), @intCast(self.bound_col), ' ');
            }
            self.tail_cur_line = self.tail_put_line;
            start_line = self.tail_put_line + 1;
        }

        var line = start_line;
        while (line <= self.head_put_line) : (line +%= 1) {
            const is_glitched = cloud.isGlitched(line, self.bound_col);
            const val = cloud.getChar(line, self.char_pool_idx);

            var cl = types.CharLoc.MIDDLE;
            if (self.tail_put_line != 0xFFFF and line == self.tail_put_line + 1) {
                cl = types.CharLoc.TAIL;
            } else if (line == self.head_put_line and self.isHeadBright(cur_time)) {
                cl = types.CharLoc.HEAD;
            }

            // Optimization: don't draw non-glitched chars between tail and head_cur_line
            if (cl == types.CharLoc.MIDDLE and line < self.head_cur_line and !is_glitched and line != self.end_line and
                cloud.shading_mode != .DISTANCE_FROM_HEAD and !draw_everything)
            {
                continue;
            }

            var attr = types.CharAttr{ .color_pair = 0, .is_bold = false };
            cloud.getAttr(line, self.bound_col, val, cl, &attr, cur_time, self.head_put_line, self.length);

            const attr2: c_long = if (attr.is_bold) c.A_BOLD else c.A_NORMAL;
            var wc: c.cchar_t = undefined;
            wc.attr = attr2;
            wc.chars[0] = val;

            if (cloud.color_mode != .MONO) {
                _ = c.attron(c.COLOR_PAIR(attr.color_pair));
                _ = c.mvadd_wch(@intCast(line), @intCast(self.bound_col), &wc);
                _ = c.attroff(c.COLOR_PAIR(attr.color_pair));
            } else {
                _ = c.mvadd_wch(@intCast(line), @intCast(self.bound_col), &wc);
            }
        }

        self.head_cur_line = self.head_put_line;
    }

    pub fn incrementTime(self: *Droplet, ms: u64) void {
        const elapsed = ms * std.time.ns_per_ms;
        self.last_time = self.last_time.add(elapsed);
        if (self.head_stop_time.ns_since_epoch > 0) {
            self.head_stop_time = self.head_stop_time.add(elapsed);
        }
    }

    pub fn isHeadBright(self: *const Droplet, cur_time: std.time.Instant) bool {
        if (self.is_head_crawling) return true;
        const elapsed = cur_time.since(self.head_stop_time);
        return elapsed <= 100 * std.time.ns_per_ms;
    }
};

const Cloud = opaque {};

pub fn main() !void {
    std.debug.print("Droplet module compiled\n", .{});
}
