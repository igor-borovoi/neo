const std = @import("std");

pub fn main() !void {
    // Clear screen and hide cursor
    std.debug.print("\x1b[2J\x1b[H\x1b[?25l", .{});

    var seed: u64 = 0x1234567;
    var frame: usize = 0;

    // Matrix characters - mix of ASCII and some Unicode
    const chars = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '-', '_', '+', '=', '[', ']', '{', '}', '|', '\\', ':', ';', '"', '\'', '<', '>', ',', '.', '?', '/', '~', '`' };

    while (frame < 200) { // Run for about 10 seconds
        // Move cursor to top
        std.debug.print("\x1b[H", .{});

        // Generate Matrix rain effect
        var row: usize = 0;
        while (row < 24) : (row += 1) {
            var col: usize = 0;
            while (col < 80) : (col += 1) {
                // Create trailing effect - some positions fade
                seed = seed *% 1103515245 +% 12345;
                const should_draw = (seed % 100) < 80; // 80% chance to draw

                if (should_draw) {
                    seed = seed *% 1103515245 +% 12345;
                    const char_idx = seed % chars.len;
                    std.debug.print("{c}", .{chars[char_idx]});
                } else {
                    std.debug.print(" ", .{});
                }
            }
            std.debug.print("\n", .{});
        }

        // Frame timing
        std.Thread.sleep(50 * 1000 * 1000); // 50ms - faster animation

        frame += 1;
    }

    // Show cursor again
    std.debug.print("\x1b[?25h\nMatrix rain complete! The Matrix effect is working in your terminal.\n", .{});
}
