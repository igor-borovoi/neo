const std = @import("std");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE_EXTENDED", "1");
    @cInclude("ncurses.h");
    @cInclude("locale.h");
});

const types = @import("types.zig");

var locale_str: ?[]const u8 = null;

pub fn initTerm(usr_color_mode: types.ColorMode) types.ColorMode {
    if (c.setlocale(c.LC_ALL, "")) |loc| locale_str = std.mem.span(loc);

    _ = c.initscr();
    if (c.has_colors()) {
        _ = c.start_color();
    }
    _ = c.cbreak();
    _ = c.curs_set(0);
    _ = c.noecho();
    _ = c.nodelay(c.stdscr, true);
    _ = c.keypad(c.stdscr, true);
    _ = c.clear();
    _ = c.refresh();

    if (!c.has_colors()) return .MONO;
    if (usr_color_mode != .INVALID) return usr_color_mode;
    if (c.COLORS >= 256) {
        return if (c.can_change_color()) .TRUECOLOR else .COLOR256;
    }
    return .COLOR16;
}

pub fn endTerm() void {
    _ = c.endwin();
}

pub fn wantsAscii() bool {
    const loc = locale_str orelse return false;
    return std.mem.indexOf(u8, loc, "UTF") == null;
}

pub fn getKey() types.Key {
    const ch = c.getch();
    return switch (ch) {
        -1 => .none,
        c.KEY_UP => .up,
        c.KEY_DOWN => .down,
        c.KEY_LEFT => .left,
        c.KEY_RIGHT => .right,
        c.KEY_RESIZE => .resize,
        else => if (ch >= 0 and ch < 256) .{ .char = @intCast(ch) } else .none,
    };
}

pub fn refresh() void {
    _ = c.refresh();
}

pub fn clearLine(y: u16) void {
    _ = c.move(@intCast(y), 0);
    _ = c.clrtoeol();
}

pub fn printOverlay(y: u16, x: u16, text: []const u8) void {
    _ = c.attr_set(c.A_BOLD | c.A_REVERSE, 0, null);
    _ = c.mvaddnstr(@intCast(y), @intCast(x), text.ptr, @intCast(text.len));
}

pub fn lines() u16 {
    return @intCast(c.LINES);
}

pub fn cols() u16 {
    return @intCast(c.COLS);
}

pub fn clearScreen() void {
    _ = c.clear();
}

pub fn attrSet(bold: bool, pair: i16) void {
    _ = c.attr_set(if (bold) c.A_BOLD else 0, pair, null);
}

pub fn attrBoldOn() void {
    _ = c.attron(c.A_BOLD);
}

pub fn attrReset() void {
    _ = c.attr_set(0, 0, null);
}

pub fn putEntry(y: u16, x: u16, entry: *const types.CharEntry) void {
    _ = c.mvaddstr(@intCast(y), @intCast(x), &entry.utf8);
}

pub fn putAscii(y: u16, x: u16, ch: u8) void {
    _ = c.mvaddch(@intCast(y), @intCast(x), ch);
}

pub fn isCellEmpty(y: u16, x: u16) bool {
    const ch = c.mvinch(@intCast(y), @intCast(x));
    return ch == c.ERR or ch == 0 or ch == ' ';
}

pub fn useDefaultColors() void {
    _ = c.use_default_colors();
}

pub fn initPair(pair: i16, fg: i16, bg: i16) void {
    _ = c.init_pair(pair, fg, bg);
}

pub fn initColor(idx: i16, r: i16, g: i16, b: i16) void {
    _ = c.init_color(idx, r, g, b);
}

pub fn setBackgroundPair(pair: i16) void {
    _ = c.bkgdset(@intCast(c.COLOR_PAIR(pair)));
}
