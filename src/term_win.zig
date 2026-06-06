//! Windows console backend: VT escape sequences over the Win32 console API.
//! No ncurses dependency; requires Windows 10+ virtual terminal support.
const std = @import("std");
const types = @import("types.zig");
const palette = @import("palette.zig");

const HANDLE = ?*anyopaque;
const DWORD = u32;
const WORD = u16;
const BOOL = i32;
const UINT = u32;

const STD_INPUT_HANDLE: DWORD = 0xFFFF_FFF6;
const STD_OUTPUT_HANDLE: DWORD = 0xFFFF_FFF5;
const CP_UTF8: UINT = 65001;

const ENABLE_PROCESSED_OUTPUT: DWORD = 0x0001;
const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
const ENABLE_WINDOW_INPUT: DWORD = 0x0008;
const ENABLE_EXTENDED_FLAGS: DWORD = 0x0080;

const KEY_EVENT: WORD = 0x0001;
const WINDOW_BUFFER_SIZE_EVENT: WORD = 0x0004;

const VK_LEFT: WORD = 0x25;
const VK_UP: WORD = 0x26;
const VK_RIGHT: WORD = 0x27;
const VK_DOWN: WORD = 0x28;

const COORD = extern struct { X: i16, Y: i16 };
const SMALL_RECT = extern struct { Left: i16, Top: i16, Right: i16, Bottom: i16 };

const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: WORD,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

const KEY_EVENT_RECORD = extern struct {
    bKeyDown: BOOL,
    wRepeatCount: WORD,
    wVirtualKeyCode: WORD,
    wVirtualScanCode: WORD,
    uChar: extern union { UnicodeChar: u16, AsciiChar: u8 },
    dwControlKeyState: DWORD,
};

const INPUT_RECORD = extern struct {
    EventType: WORD,
    Event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        WindowBufferSizeEvent: COORD,
    },
};

extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.winapi) HANDLE;
extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: *DWORD) callconv(.winapi) BOOL;
extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(.winapi) BOOL;
extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) UINT;
extern "kernel32" fn SetConsoleOutputCP(wCodePageID: UINT) callconv(.winapi) BOOL;
extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpInfo: *CONSOLE_SCREEN_BUFFER_INFO) callconv(.winapi) BOOL;
extern "kernel32" fn WriteFile(hFile: HANDLE, lpBuffer: [*]const u8, nBytes: DWORD, lpWritten: ?*DWORD, lpOverlapped: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn ReadConsoleInputW(hConsoleInput: HANDLE, lpBuffer: [*]INPUT_RECORD, nLength: DWORD, lpRead: *DWORD) callconv(.winapi) BOOL;
extern "kernel32" fn GetNumberOfConsoleInputEvents(hConsoleInput: HANDLE, lpcNumberOfEvents: *DWORD) callconv(.winapi) BOOL;

const gpa = std.heap.page_allocator;
const default_fg: u32 = 0xCCCCCC;
const csi = "\x1b[";

var h_in: HANDLE = null;
var h_out: HANDLE = null;
var saved_in_mode: DWORD = 0;
var saved_out_mode: DWORD = 0;
var saved_cp: UINT = 0;
var term_active = false;

var grid_lines: u16 = 24;
var grid_cols: u16 = 80;
var cells: []u21 = &.{};

var buf: std.ArrayList(u8) = .empty;

var color_overrides: [256]?u32 = @splat(null);
var pair_rgb: [256]u32 = @splat(default_fg);

fn out(s: []const u8) void {
    buf.appendSlice(gpa, s) catch {};
}

fn outFmt(comptime fmt: []const u8, args: anytype) void {
    var tmp: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, fmt, args) catch return;
    out(s);
}

fn moveTo(y: u16, x: u16) void {
    outFmt(csi ++ "{d};{d}H", .{ @as(u32, y) + 1, @as(u32, x) + 1 });
}

fn flushBuf() void {
    if (buf.items.len == 0) return;
    var written: DWORD = 0;
    _ = WriteFile(h_out, buf.items.ptr, @intCast(buf.items.len), &written, null);
    buf.clearRetainingCapacity();
}

fn refreshSize() void {
    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (h_out == null or GetConsoleScreenBufferInfo(h_out, &info) == 0) return;
    const new_cols: u16 = @intCast(@max(1, info.srWindow.Right - info.srWindow.Left + 1));
    const new_lines: u16 = @intCast(@max(1, info.srWindow.Bottom - info.srWindow.Top + 1));
    if (new_lines == grid_lines and new_cols == grid_cols and cells.len > 0) return;
    grid_lines = new_lines;
    grid_cols = new_cols;
    const size = @as(usize, grid_lines) * @as(usize, grid_cols);
    if (cells.len != size) {
        gpa.free(cells);
        cells = gpa.alloc(u21, size) catch @panic("OOM");
    }
    @memset(cells, ' ');
}

pub fn initTerm(usr_color_mode: types.ColorMode) types.ColorMode {
    h_in = GetStdHandle(STD_INPUT_HANDLE);
    h_out = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h_out == null) {
        std.debug.print("Error: no console output handle\n", .{});
        std.process.exit(1);
    }

    _ = GetConsoleMode(h_out, &saved_out_mode);
    if (SetConsoleMode(h_out, ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING) == 0) {
        std.debug.print("Error: this console does not support VT sequences (Windows 10+ required)\n", .{});
        std.process.exit(1);
    }
    saved_cp = GetConsoleOutputCP();
    _ = SetConsoleOutputCP(CP_UTF8);

    if (h_in != null) {
        _ = GetConsoleMode(h_in, &saved_in_mode);
        _ = SetConsoleMode(h_in, ENABLE_WINDOW_INPUT | ENABLE_EXTENDED_FLAGS);
    }

    refreshSize();
    term_active = true;
    // Alternate screen buffer, hidden cursor, cleared screen
    out(csi ++ "?1049h" ++ csi ++ "?25l" ++ csi ++ "2J" ++ csi ++ "H");
    flushBuf();

    return if (usr_color_mode == .INVALID) .TRUECOLOR else usr_color_mode;
}

pub fn endTerm() void {
    if (!term_active) return;
    term_active = false;
    out(csi ++ "0m" ++ csi ++ "?25h" ++ csi ++ "?1049l");
    flushBuf();
    _ = SetConsoleOutputCP(saved_cp);
    if (h_out != null) _ = SetConsoleMode(h_out, saved_out_mode);
    if (h_in != null) _ = SetConsoleMode(h_in, saved_in_mode);
}

pub fn wantsAscii() bool {
    return false;
}

pub fn getKey() types.Key {
    const hin = h_in orelse return .none;
    while (true) {
        var avail: DWORD = 0;
        if (GetNumberOfConsoleInputEvents(hin, &avail) == 0 or avail == 0) return .none;
        var rec: INPUT_RECORD = undefined;
        var nread: DWORD = 0;
        if (ReadConsoleInputW(hin, @ptrCast(&rec), 1, &nread) == 0 or nread == 0) return .none;
        switch (rec.EventType) {
            KEY_EVENT => {
                const ke = rec.Event.KeyEvent;
                if (ke.bKeyDown == 0) continue;
                switch (ke.wVirtualKeyCode) {
                    VK_UP => return .up,
                    VK_DOWN => return .down,
                    VK_LEFT => return .left,
                    VK_RIGHT => return .right,
                    else => {
                        const ch = ke.uChar.UnicodeChar;
                        if (ch != 0 and ch < 0x80) return .{ .char = @intCast(ch) };
                    },
                }
            },
            WINDOW_BUFFER_SIZE_EVENT => return .resize,
            else => {},
        }
    }
}

pub fn refresh() void {
    flushBuf();
}

pub fn lines() u16 {
    refreshSize();
    return grid_lines;
}

pub fn cols() u16 {
    refreshSize();
    return grid_cols;
}

pub fn clearScreen() void {
    if (cells.len > 0) @memset(cells, ' ');
    out(csi ++ "2J");
}

pub fn clearLine(y: u16) void {
    moveTo(y, 0);
    out(csi ++ "2K");
    if (y < grid_lines and cells.len > 0) {
        @memset(cells[@as(usize, y) * grid_cols ..][0..grid_cols], ' ');
    }
}

pub fn printOverlay(y: u16, x: u16, text: []const u8) void {
    moveTo(y, x);
    out(csi ++ "0;1;7m");
    out(text);
    out(csi ++ "0m");
}

pub fn attrSet(bold: bool, pair: i16) void {
    const rgb = if (pair >= 0) pair_rgb[@intCast(pair)] else default_fg;
    outFmt(csi ++ "0{s};38;2;{d};{d};{d}m", .{
        if (bold) ";1" else "",
        (rgb >> 16) & 0xFF,
        (rgb >> 8) & 0xFF,
        rgb & 0xFF,
    });
}

pub fn attrBoldOn() void {
    out(csi ++ "1m");
}

pub fn attrReset() void {
    out(csi ++ "0m");
}

pub fn putEntry(y: u16, x: u16, entry: *const types.CharEntry) void {
    if (y >= grid_lines or x >= grid_cols) return;
    cells[@as(usize, y) * grid_cols + x] = entry.codepoint;
    moveTo(y, x);
    out(entry.utf8[0..entry.utf8_len]);
}

pub fn putAscii(y: u16, x: u16, ch: u8) void {
    if (y >= grid_lines or x >= grid_cols) return;
    cells[@as(usize, y) * grid_cols + x] = ch;
    moveTo(y, x);
    buf.append(gpa, ch) catch {};
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
