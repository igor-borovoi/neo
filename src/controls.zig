const types = @import("types.zig");

pub const CHARSET_CYCLE = [_]types.Charset{
    .MIX,
    .KATAKANA,
    .DEFAULT,
    .EXTENDED_DEFAULT,
    .ENGLISH_LETTERS,
    .ENGLISH_DIGITS,
    .ENGLISH_PUNCTUATION,
    .CYRILLIC,
    .GREEK,
    .ARABIC,
    .HEBREW,
    .DEVANAGARI,
    .BRAILLE,
    .RUNIC,
    .BINARY,
    .HEX,
};

pub fn charsetName(charset: types.Charset) []const u8 {
    return switch (charset) {
        .MIX => "mix",
        .KATAKANA => "katakana",
        .DEFAULT => "ascii",
        .EXTENDED_DEFAULT => "extended",
        .ENGLISH_LETTERS => "english",
        .ENGLISH_DIGITS => "digits",
        .ENGLISH_PUNCTUATION => "punc",
        .CYRILLIC => "cyrillic",
        .GREEK => "greek",
        .ARABIC => "arabic",
        .HEBREW => "hebrew",
        .DEVANAGARI => "devanagari",
        .BRAILLE => "braille",
        .RUNIC => "runic",
        .BINARY => "binary",
        .HEX => "hex",
        else => "unknown",
    };
}

pub const COLOR_CYCLE = [_]types.Color{
    .GREEN,
    .GREEN2,
    .GREEN3,
    .YELLOW,
    .ORANGE,
    .RED,
    .BLUE,
    .CYAN,
    .GOLD,
    .RAINBOW,
    .PURPLE,
    .PINK,
    .PINK2,
    .VAPORWAVE,
    .GRAY,
};

pub fn colorName(color: types.Color) []const u8 {
    return switch (color) {
        .GREEN => "green",
        .GREEN2 => "green2",
        .GREEN3 => "green3",
        .YELLOW => "yellow",
        .ORANGE => "orange",
        .RED => "red",
        .BLUE => "blue",
        .CYAN => "cyan",
        .GOLD => "gold",
        .RAINBOW => "rainbow",
        .PURPLE => "purple",
        .PINK => "pink",
        .PINK2 => "pink2",
        .VAPORWAVE => "vaporwave",
        .GRAY => "gray",
        else => "unknown",
    };
}

pub fn findColorIndex(color: types.Color) ?usize {
    for (COLOR_CYCLE, 0..) |col, i| {
        if (col == color) return i;
    }
    return null;
}

pub fn cycleColorForward(color: types.Color) types.Color {
    if (findColorIndex(color)) |idx| {
        return COLOR_CYCLE[(idx + 1) % COLOR_CYCLE.len];
    }
    return .GREEN;
}

pub fn findCharsetIndex(charset: types.Charset) ?usize {
    for (CHARSET_CYCLE, 0..) |cs, i| {
        if (cs == charset) return i;
    }
    return null;
}

pub fn cycleCharsetForward(charset: types.Charset) types.Charset {
    if (findCharsetIndex(charset)) |idx| {
        return CHARSET_CYCLE[(idx + 1) % CHARSET_CYCLE.len];
    }
    return .MIX;
}

pub fn cycleCharsetBackward(charset: types.Charset) types.Charset {
    if (findCharsetIndex(charset)) |idx| {
        return CHARSET_CYCLE[(idx + CHARSET_CYCLE.len - 1) % CHARSET_CYCLE.len];
    }
    return .MIX;
}
