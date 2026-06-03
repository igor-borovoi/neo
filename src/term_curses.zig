const c = @cImport({
    @cDefine("_XOPEN_SOURCE_EXTENDED", "1");
    @cInclude("ncurses.h");
});

const types = @import("types.zig");

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
