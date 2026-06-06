const std = @import("std");
const types = @import("types.zig");
const palette = @import("palette.zig");

const allocator = std.heap.wasm_allocator;

const default_fg: u32 = 0xCCCCCC;

var grid_lines: u16 = 24;
var grid_cols: u16 = 80;
var cells: []u21 = &.{};
var ops: std.ArrayList(u32) = .empty;
var clear_requested: bool = false;

var cur_rgb: u32 = default_fg;
var cur_bold: bool = false;

var color_overrides: [256]?u32 = @splat(null);
var pair_rgb: [256]u32 = @splat(default_fg);

pub fn setSize(new_lines: u16, new_cols: u16) void {
    const size = @as(usize, new_lines) * @as(usize, new_cols);
    if (cells.len != size) {
        allocator.free(cells);
        cells = allocator.alloc(u21, size) catch @panic("OOM");
    }
    grid_lines = new_lines;
    grid_cols = new_cols;
    @memset(cells, ' ');
    clear_requested = true;
}

pub fn beginFrame() void {
    ops.clearRetainingCapacity();
    clear_requested = false;
}

pub fn opsPtr() [*]const u32 {
    return ops.items.ptr;
}

pub fn opsLen() usize {
    return ops.items.len;
}

pub fn clearRequested() bool {
    return clear_requested;
}

pub fn lines() u16 {
    return grid_lines;
}

pub fn cols() u16 {
    return grid_cols;
}

pub fn clearScreen() void {
    @memset(cells, ' ');
    ops.clearRetainingCapacity();
    clear_requested = true;
}

pub fn attrSet(bold: bool, pair: i16) void {
    cur_bold = bold;
    cur_rgb = if (pair >= 0) pair_rgb[@intCast(pair)] else default_fg;
}

pub fn attrBoldOn() void {
    cur_bold = true;
}

pub fn attrReset() void {
    cur_bold = false;
    cur_rgb = default_fg;
}

fn putCp(y: u16, x: u16, cp: u21) void {
    if (y >= grid_lines or x >= grid_cols) return;
    cells[@as(usize, y) * grid_cols + x] = cp;
    const pos = (@as(u32, y) << 16) | x;
    const style = (cur_rgb << 8) | @intFromBool(cur_bold);
    ops.appendSlice(allocator, &.{ pos, cp, style }) catch {};
}

pub fn putEntry(y: u16, x: u16, entry: *const types.CharEntry) void {
    putCp(y, x, entry.codepoint);
}

pub fn putAscii(y: u16, x: u16, ch: u8) void {
    putCp(y, x, ch);
}

pub fn isCellEmpty(y: u16, x: u16) bool {
    if (y >= grid_lines or x >= grid_cols) return true;
    const cp = cells[@as(usize, y) * grid_cols + x];
    return cp == 0 or cp == ' ';
}

pub fn useDefaultColors() void {}

pub fn initPair(pair: i16, fg: i16, bg: i16) void {
    _ = bg;
    if (pair < 0) return;
    pair_rgb[@intCast(pair)] = if (fg >= 0 and fg < 256)
        color_overrides[@intCast(fg)] orelse palette.xterm[@intCast(fg)]
    else
        default_fg;
}

pub fn initColor(idx: i16, r: i16, g: i16, b: i16) void {
    if (idx < 0 or idx >= 256) return;
    const scale = palette.scaleComponent;
    color_overrides[@intCast(idx)] = (scale(r) << 16) | (scale(g) << 8) | scale(b);
}

pub fn setBackgroundPair(pair: i16) void {
    _ = pair;
}
