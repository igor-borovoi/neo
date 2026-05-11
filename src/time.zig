const std = @import("std");

/// Thin compat shim wrapping the 0.16 `std.Io` clock API in a
/// `std.time.Instant`-shaped surface (0.15-era API). Keeps source diffs minimal.
pub const Instant = struct {
    nanoseconds: i96 = 0,

    pub fn now(io: std.Io) Instant {
        return .{ .nanoseconds = std.Io.Clock.now(.awake, io).nanoseconds };
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

pub fn sleep(io: std.Io, duration_ns: u64) void {
    std.Io.sleep(io, .fromNanoseconds(@intCast(duration_ns)), .awake) catch {};
}

pub fn nanoTimestamp(io: std.Io) i128 {
    return std.Io.Clock.now(.real, io).nanoseconds;
}
