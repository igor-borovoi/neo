const std = @import("std");
const builtin = @import("builtin");

pub const is_wasm = builtin.target.cpu.arch.isWasm();

/// On native targets this is `std.Io` from `std.process.Init`. On wasm there is
/// no OS clock; the JS host feeds the current time via `setWasmClock` each
/// frame and `Io` collapses to an empty struct so `Cloud` code stays identical.
pub const Io = if (is_wasm) struct {} else std.Io;

var wasm_clock_ns: i96 = 0;

pub fn setWasmClock(ns: i96) void {
    wasm_clock_ns = ns;
}

/// Thin compat shim wrapping the 0.16 `std.Io` clock API in a
/// `std.time.Instant`-shaped surface (0.15-era API). Keeps source diffs minimal.
pub const Instant = struct {
    nanoseconds: i96 = 0,

    pub fn now(io: Io) Instant {
        if (comptime is_wasm) {
            return .{ .nanoseconds = wasm_clock_ns };
        } else {
            return .{ .nanoseconds = std.Io.Clock.now(.awake, io).nanoseconds };
        }
    }

    pub fn since(self: Instant, earlier: Instant) u64 {
        const diff = self.nanoseconds - earlier.nanoseconds;
        if (diff <= 0) return 0;
        return @intCast(diff);
    }

    pub fn order(self: Instant, other: Instant) std.math.Order {
        return std.math.order(self.nanoseconds, other.nanoseconds);
    }
};

pub fn sleep(io: Io, duration_ns: u64) void {
    if (comptime !is_wasm) {
        std.Io.sleep(io, .fromNanoseconds(@intCast(duration_ns)), .awake) catch {};
    }
}

pub fn nanoTimestamp(io: Io) i128 {
    if (comptime is_wasm) {
        return wasm_clock_ns;
    } else {
        return std.Io.Clock.now(.real, io).nanoseconds;
    }
}
