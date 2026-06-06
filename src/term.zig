//! Rendering backend, selected at compile time: ncurses on Unix-like targets,
//! the Win32 console with VT sequences on Windows, a cell grid consumed by
//! the JS canvas host on wasm.
const builtin = @import("builtin");

const backend = if (builtin.target.cpu.arch.isWasm())
    @import("term_web.zig")
else if (builtin.target.os.tag == .windows)
    @import("term_win.zig")
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

// Native-host surface, used by main.zig only (the wasm backend does not
// provide these; the JS host owns init, input, and frame pacing there).
pub const initTerm = backend.initTerm;
pub const endTerm = backend.endTerm;
pub const wantsAscii = backend.wantsAscii;
pub const getKey = backend.getKey;
pub const refresh = backend.refresh;
pub const clearLine = backend.clearLine;
pub const printOverlay = backend.printOverlay;
