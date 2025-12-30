const std = @import("std");

pub const Charset = enum(u32) {
    NONE = 0x0,
    ENGLISH_LETTERS = 0x1,
    ENGLISH_DIGITS = 0x2,
    ENGLISH_PUNCTUATION = 0x4,
    KATAKANA = 0x8,
    GREEK = 0x10,
    CYRILLIC = 0x20,
    ARABIC = 0x40,
    HEBREW = 0x80,
    BINARY = 0x100,
    HEX = 0x200,
    DEVANAGARI = 0x400,
    BRAILLE = 0x800,
    RUNIC = 0x1000,
    DEFAULT = 0x7,
    EXTENDED_DEFAULT = 0xE,
    // Mixed mode: Japanese 80%, Cyrillic 10%, Braille 6%, ASCII 4%
    MIX = 0x2000,
};

pub fn bitAnd(lhs: Charset, rhs: Charset) Charset {
    return @enumFromInt(@intFromEnum(lhs) & @intFromEnum(rhs));
}

pub fn isNone(input: Charset) bool {
    return @intFromEnum(input) == 0;
}

pub const Color = enum(u32) {
    USER,
    GREEN,
    GREEN2,
    GREEN3,
    YELLOW,
    ORANGE,
    RED,
    BLUE,
    CYAN,
    GOLD,
    RAINBOW,
    PURPLE,
    PINK,
    PINK2,
    VAPORWAVE,
    GRAY,
};

pub const ColorMode = enum(u32) {
    MONO,
    COLOR16,
    COLOR256,
    TRUECOLOR,
    INVALID,
};

pub const ColorContent = struct {
    color: c_short = 0,
    r: c_short = 0x7FFF,
    g: c_short = 0x7FFF,
    b: c_short = 0x7FFF,
};

pub const ShadingMode = enum(u32) {
    RANDOM,
    DISTANCE_FROM_HEAD,
    INVALID,
};

pub const BoldMode = enum(u32) {
    OFF,
    RANDOM,
    ALL,
    INVALID,
};

pub const CharAttr = struct {
    color_pair: c_int,
    is_bold: bool,
};

pub const CharLoc = enum {
    MIDDLE,
    TAIL,
    HEAD,
};

pub const ColumnStatus = struct {
    max_speed_pct: f32 = 1.0,
    num_droplets: u8 = 0,
    can_spawn: bool = true,
};

pub const MsgChr = struct {
    line: u16 = 0,
    col: u16 = 0,
    val: u8 = 0,
    draw: bool = false,

    pub fn init(val: u8) MsgChr {
        return .{
            .val = val,
            .draw = false,
        };
    }
};

pub const CHAR_POOL_SIZE: usize = 2048;
pub const GLITCH_POOL_SIZE: usize = 1024;
pub const MAX_DROPLETS_PER_COL: u8 = 3;
