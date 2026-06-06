//! WebAssembly entry point. The JS host (web/neo.js) drives the simulation:
//! it owns the requestAnimationFrame loop, feeds wall-clock time into
//! `neoFrame`, reads back the draw-op buffer, and forwards keyboard input.
const std = @import("std");
const types = @import("types.zig");
const cloud_mod = @import("cloud.zig");
const controls = @import("controls.zig");
const term = @import("term_web.zig");
const time = @import("time.zig");

pub const KEY_UP: u32 = 0x101;
pub const KEY_DOWN: u32 = 0x102;
pub const KEY_RIGHT: u32 = 0x103;
pub const KEY_LEFT: u32 = 0x104;

const KeyResult = enum(u32) { none, pause, reset, speed, charset, quit, color };

var cloud: cloud_mod.Cloud = undefined;
var color: types.Color = .GREEN;
var target_fps: f32 = 20.0;
var charset_name: []const u8 = "mix";
var color_name: []const u8 = "green";

export fn neoInit(seed_lo: u32, seed_hi: u32, color_id: u32, charset_id: u32, fps: f32) void {
    cloud = cloud_mod.Cloud.init(std.heap.wasm_allocator, .{}, .TRUECOLOR, false);
    const seed = (@as(u64, seed_hi) << 32) | seed_lo;
    cloud.setSeed(if (seed == 0) 0x1234567 else seed);
    cloud.charset = std.enums.fromInt(types.Charset, charset_id) orelse .MIX;
    charset_name = controls.charsetName(cloud.charset);
    color = std.enums.fromInt(types.Color, color_id) orelse .GREEN;
    color_name = controls.colorName(color);
    if (fps > 0) target_fps = std.math.clamp(fps, 1.0, 100.0);
}

export fn neoReset(lines: u32, cols: u32, now_ms: f64) void {
    setClock(now_ms);
    term.setSize(@intCast(@min(lines, 0xFFFF)), @intCast(@min(cols, 0xFFFF)));
    cloud.reset() catch return;
    cloud.setColor(color) catch return;
    cloud.raining = true;
}

export fn neoFrame(now_ms: f64) u32 {
    setClock(now_ms);
    term.beginFrame();
    if (cloud.raining) {
        cloud.rain();
    }
    return @intCast(term.opsLen());
}

export fn neoOnKey(code: u32, now_ms: f64) u32 {
    setClock(now_ms);
    const result: KeyResult = switch (code) {
        ' ' => blk: {
            cloud.reset() catch break :blk .none;
            cloud.force_draw_everything = true;
            cloud.raining = true;
            break :blk .reset;
        },
        'p' => blk: {
            cloud.togglePause();
            break :blk .pause;
        },
        'c' => blk: {
            color = controls.cycleColorForward(color);
            cloud.setColor(color) catch break :blk .none;
            color_name = controls.colorName(color);
            cloud.force_draw_everything = true;
            break :blk .color;
        },
        'q', 27 => blk: {
            cloud.raining = false;
            break :blk .quit;
        },
        KEY_UP => blk: {
            target_fps = @min(target_fps + 1.0, 100.0);
            break :blk .speed;
        },
        KEY_DOWN => blk: {
            target_fps = @max(target_fps - 1.0, 1.0);
            break :blk .speed;
        },
        KEY_RIGHT => blk: {
            cloud.setCharset(controls.cycleCharsetForward(cloud.charset));
            charset_name = controls.charsetName(cloud.charset);
            break :blk .charset;
        },
        KEY_LEFT => blk: {
            cloud.setCharset(controls.cycleCharsetBackward(cloud.charset));
            charset_name = controls.charsetName(cloud.charset);
            break :blk .charset;
        },
        else => .none,
    };
    return @intFromEnum(result);
}

export fn neoOpsPtr() [*]const u32 {
    return term.opsPtr();
}

export fn neoClearRequested() u32 {
    return @intFromBool(term.clearRequested());
}

export fn neoTargetFps() f32 {
    return target_fps;
}

export fn neoPaused() u32 {
    return @intFromBool(cloud.pause);
}

export fn neoCharsetNamePtr() [*]const u8 {
    return charset_name.ptr;
}

export fn neoCharsetNameLen() u32 {
    return @intCast(charset_name.len);
}

export fn neoColorNamePtr() [*]const u8 {
    return color_name.ptr;
}

export fn neoColorNameLen() u32 {
    return @intCast(color_name.len);
}

fn setClock(now_ms: f64) void {
    time.setWasmClock(@intFromFloat(now_ms * std.time.ns_per_ms));
}
