const std = @import("std");

pub fn main() !void {
    std.debug.print("\x1b[2J\x1b[H", .{});

    var seed: u64 = 0x1234567;
    var frame: usize = 0;
    while (frame < 5) : (frame += 1) {
        std.debug.print("\x1b[H", .{});

        // Generate and print some random characters
        var i: usize = 0;
        while (i < 20) : (i += 1) {
            seed = seed *% 1103515245 +% 12345;
            const char_code = 33 + (seed % 94); // ASCII 33-126
            std.debug.print("{c} ", .{@as(u8, @intCast(char_code))});
        }

        std.debug.print("\n", .{});
        std.Thread.sleep(500 * 1000 * 1000); // 500ms
    }

    std.debug.print("\nTest complete - if you see random characters above, basic output works!\n", .{});
}
