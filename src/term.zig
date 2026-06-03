//! Rendering backend, selected at compile time: ncurses on native targets,
//! a cell grid consumed by the JS canvas host on wasm.
const builtin = @import("builtin");

const backend = if (builtin.target.cpu.arch.isWasm())
    @import("term_web.zig")
else
    @import("term_curses.zig");

pub const lines = backend.lines;
pub const cols = backend.cols;
pub const clearScreen = backend.clearScreen;
pub const attrSet = backend.attrSet;
pub const attrBoldOn = backend.attrBoldOn;
pub const attrReset = backend.attrReset;
pub const putEntry = backend.putEntry;
pub const putAscii = backend.putAscii;
pub const isCellEmpty = backend.isCellEmpty;
pub const useDefaultColors = backend.useDefaultColors;
pub const initPair = backend.initPair;
pub const initColor = backend.initColor;
pub const setBackgroundPair = backend.setBackgroundPair;
