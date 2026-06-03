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
