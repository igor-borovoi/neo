# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

neo-zig is a Zig port of the original neo C++ program that recreates the digital rain effect from "The Matrix". It renders random characters streaming down the terminal using ncurses, and also compiles to WebAssembly for browser rendering onto a canvas.

## Build Commands

```bash
zig build              # Build the executable (output: ./zig-out/bin/neo-zig)
zig build run          # Build and run with default settings
zig build run -- -c gold --charset katakana  # Run with arguments
zig build test         # Run the test suite
zig build bench        # Run performance benchmark
zig build wasm         # Build the browser bundle (output: ./zig-out/web/)
```

A `Taskfile.yml` wraps these for the [Task](https://taskfile.dev) runner: `task build|run|test|bench|wasm|serve|web`. Plain `task` (default) builds the wasm bundle and serves it at http://localhost:8000 (`PORT=...` to override). `task dev` (native) and `task web:dev` (browser) are watch modes that rebuild on source changes; the web page auto-reloads via a localhost-only HEAD poll in `web/neo.js`.

**Dependencies**: Zig 0.16.0, ncurses development library (`libncurses-dev` on Debian/Ubuntu, `ncurses` on Arch, built-in on macOS). The wasm target needs no ncurses; serve `zig-out/web/` over HTTP (e.g. `python3 -m http.server -d zig-out/web`).

On Linux, `build.zig` compiles to an object via Zig and links via the system `cc`. This sidesteps an incompatibility where Zig 0.16's bundled linkers (LLD and self-hosted) cannot relocate `.sframe` sections in GCC 16+ CRT files. macOS/other targets link normally via Zig.

Time and I/O go through `std.Io` in Zig 0.16. `src/time.zig` is a thin compat shim wrapping `std.Io.Clock` with a `std.time.Instant`-shaped surface (`now(io)`, `since()`, `order()`, plus `sleep(io, ns)` and `nanoTimestamp(io)` helpers). `Cloud` carries an `io` field typed `time.Io`; on native that is `std.Io` (passed down from `std.process.Init`), on wasm it collapses to an empty struct and the JS host feeds wall-clock time via `time.setWasmClock` each frame.

## Architecture

### Core Components

- **main.zig** - Native entry point, ncurses setup, argument parsing, main event loop
- **cloud.zig** - `Cloud` struct that orchestrates all droplets and manages the rain effect; the `Droplet` struct (individual falling streams) is nested inside it. Renders only through `term.zig`, never ncurses directly
- **term.zig** - Rendering backend dispatcher, comptime-selected by target: `term_curses.zig` (native, owns the ncurses `@cImport`) or `term_web.zig` (wasm: cell grid + draw-op buffer + xterm-256 palette with `init_color` overrides)
- **wasm_main.zig** - WebAssembly exports (`neoInit`/`neoReset`/`neoFrame`/`neoOnKey`/...); the JS host owns the requestAnimationFrame loop and reads draw ops as (pos, codepoint, rgb|bold) u32 triples from wasm memory
- **controls.zig** - Charset and color cycle order and names, shared by main.zig and wasm_main.zig
- **types.zig** - Enums and type definitions (Charset, Color, ColorMode, etc.)
- **benchmark.zig** - Performance benchmarking utilities
- **test.zig** - Test suite
- **web/** - Static browser host (`index.html`, `neo.js`): canvas rendering, keyboard forwarding, URL-param options (`?color=...&charset=...&speed=...&seed=...`)
- **droplet.zig, test_simple.zig, matrix_simple.zig** - Legacy files, not imported by any build target

### Object Pool Pattern

The codebase uses pre-allocated pools for performance (avoids dynamic allocation during animation):
- **Droplet pool**: ~2x the number of terminal columns
- **Character pool**: 2048 pre-generated random characters
- **Glitch pool**: 1024 positions for glitch effects

### Rendering Optimization

Each Droplet tracks `head_cur_line` vs `head_put_line` and `tail_cur_line` vs `tail_put_line` to minimize redraws - only changed positions are redrawn each frame.

### Main Loop Flow

```
main() → initCurses() → Cloud.init() → Cloud.reset()
       ↓
  Event loop: Cloud.rain() → advance droplets → draw changes → handle input
```

## Key Functions

- `Cloud.rain()` - Main simulation step: advances and draws all active droplets
- `Cloud.spawnDroplets()` - Creates new droplets based on spawn rate
- `Droplet.advance()` - Updates droplet position with fractional tracking
- `Droplet.draw()` - Renders droplet characters via the `term` backend
- `pickColorMode()` - Detects terminal color capabilities

## Visual Effects

The default configuration mimics the movie aesthetic:
- **Mix charset** - 80% Katakana, 10% Cyrillic, 6% Braille, 4% ASCII (default)
- **Distance-from-head shading** - Characters gradually fade from bright (near head) to dim (at tail)
- **Glow effect** - Leading 3-6 characters near the head get extra brightness with bold
- **Linear brightness falloff** - Smooth, gradual fade across the entire trail

### Truecolor Support (Kitty, iTerm2, etc.)
In truecolor terminals, the effect uses a 16-step RGB gradient:
- Dark green at the tail → bright green → white-green glow at the head
- Custom RGB colors defined in `setColor()` at cloud.zig:875

The `getAttr()` function in cloud.zig:1442 controls all brightness/color calculations based on `ShadingMode`.

## Interactive Controls

- `q` or `ESC` - Quit
- `p` - Pause/Resume
- `Space` - Reset the rain effect
- `↑` / `↓` - Increase/decrease speed (FPS, 1-100)
- `←` / `→` - Cycle through charsets
- `c` - Cycle through colors
