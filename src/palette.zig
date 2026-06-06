//! xterm-256 palette as packed 0xRRGGBB values, shared by the non-curses
//! backends (wasm canvas and Windows console) which emit RGB directly.

pub const xterm: [256]u32 = blk: {
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

/// Convert a curses 0-1000 color component to 0-255.
pub fn scaleComponent(v: i16) u32 {
    const clamped: u32 = @intCast(@max(0, @min(v, 1000)));
    return clamped * 255 / 1000;
}
