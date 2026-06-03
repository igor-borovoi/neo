const std = @import("std");
const types = @import("types.zig");

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

const xterm_palette: [256]u32 = blk: {
    var p: [256]u32 = undefined;
    const basic = [16]u32{
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
    };
    for (basic, 0..) |v, i| p[i] = v;
    const steps = [6]u32{ 0, 95, 135, 175, 215, 255 };
    for (0..216) |i| {
        p[16 + i] = (steps[i / 36] << 16) | (steps[(i / 6) % 6] << 8) | steps[i % 6];
    }
    for (0..24) |i| {
        const v: u32 = 8 + 10 * i;
        p[232 + i] = (v << 16) | (v << 8) | v;
    }
    break :blk p;
};

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
        color_overrides[@intCast(fg)] orelse xterm_palette[@intCast(fg)]
    else
        default_fg;
}

pub fn initColor(idx: i16, r: i16, g: i16, b: i16) void {
    if (idx < 0 or idx >= 256) return;
    const scale = struct {
        fn f(v: i16) u32 {
            const clamped: u32 = @intCast(std.math.clamp(v, 0, 1000));
            return clamped * 255 / 1000;
        }
    }.f;
    color_overrides[@intCast(idx)] = (scale(r) << 16) | (scale(g) << 8) | scale(b);
}

pub fn setBackgroundPair(pair: i16) void {
    _ = pair;
}
