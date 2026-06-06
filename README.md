# neo-zig

![neo is AWESOME](assets/neo_is_awesome.gif)

**WARNING: neo may cause discomfort and seizures in people with photosensitive epilepsy. User discretion is advised.**

**neo-zig** is a Zig port of [neo](https://github.com/st3w/neo), recreating the digital rain effect from "The Matrix". Streams of random characters will endlessly scroll down your terminal screen.

## Features

- Simulates the Matrix digital rain effect
- Multiple color themes (green, gold, red, blue, cyan, purple, pink, rainbow, etc.)
- Multiple character sets:
  - Mix (default: 60% Katakana, 20% Cyrillic, 12% Braille, 8% ASCII)
  - Katakana (Japanese)
  - ASCII, Extended ASCII
  - English (letters, digits, punctuation)
  - Cyrillic (Russian)
  - Greek
  - Hebrew
  - Arabic
  - Devanagari (Hindi)
  - Braille
  - Runic
  - Binary (0s and 1s)
  - Hexadecimal
- Supports 16/256 colors and truecolor
- Handles terminal resizing
- Async mode for varying column speeds
- Display custom messages
- Benchmark mode for performance testing

## Quick Start

No Zig required — download and run with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/igor-borovoi/neo/main/install.sh | bash
```

Or run without installing:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/igor-borovoi/neo/main/run.sh)
```

Supports macOS (ARM) and Linux (x86\_64 & aarch64).

On Windows, download `neo-zig-windows-x86_64.exe` (or `-aarch64`) from the [latest release](https://github.com/igor-borovoi/neo/releases/latest) and run it from Windows Terminal.

## Prerequisites

**neo-zig** works on Linux and other UNIX-like operating systems (macOS, FreeBSD) via ncurses, and natively on Windows 10+ via the built-in console VT support (Windows Terminal recommended).

Required (only if building from source):
- [Zig](https://ziglang.org/download/) 0.16.0
- ncurses development library (`libncurses-dev` on Debian/Ubuntu, `ncurses` on Arch); not needed on Windows

For Unicode characters, use a font that supports the character set you want to display and ensure your locale is set to UTF-8.

## Building

```bash
git clone https://github.com/YOUR_USERNAME/neo-zig.git
cd neo-zig
zig build
```

The binary will be at `./zig-out/bin/neo-zig`.

### Task Runner

If you have [Task](https://taskfile.dev) installed, every build command has a shortcut:

```bash
task            # Build the wasm bundle and serve it in the browser
task web        # Same as above
task serve      # Serve an already-built wasm bundle (no rebuild)
task wasm       # Build the WebAssembly bundle into zig-out/web
task build      # Build the native executable
task run        # Build and run; pass args after --, e.g. task run -- -c gold
task test       # Run the test suite
task bench      # Run the performance benchmark
```

For development there are two watch modes:

```bash
task dev        # Native: rebuilds and restarts the app when src/ changes
task web:dev    # Browser: serves the wasm build, rebuilds on src/ or web/
                # changes, and the open page reloads itself automatically
```

While `task web:dev` is running it accepts hotkeys: `o` or `Space` opens the page in the browser, `r` forces a rebuild, `h` shows the hotkey list, and `q`, `Esc`, or `Ctrl+C` stops the server.

For `task dev`, quitting the app (`q` or `Esc`) also stops the watcher, and `Ctrl+C` works at any time.

The web server port defaults to 8000; override with `task web:dev PORT=9000` (works for `web` and `serve` too).

## Running in the Browser (WebAssembly)

The same Zig simulation compiles to `wasm32-freestanding` and runs in any modern browser, rendered onto a canvas. One command builds and serves it:

```bash
task            # then open http://localhost:8000
```

Or without Task:

```bash
zig build wasm
python3 -m http.server -d zig-out/web 8000
# open http://localhost:8000
```

No ncurses needed for this target; a small JS host (`web/neo.js`) drives the frame loop, draws the cell updates emitted by the wasm module, and forwards keyboard input. All interactive controls work in the browser (pause, reset, speed, charset and color cycling).

Options are passed via URL query parameters:

```
http://localhost:8000/?color=gold&charset=katakana&speed=30&seed=42
```

- `color` - green, green2, green3, gold, red, blue, cyan, yellow, orange, purple, pink, pink2, rainbow, vaporwave, gray
- `charset` - mix, katakana, ascii, extended, english, digits, punc, cyrillic, greek, arabic, hebrew, devanagari, braille, runic, binary, hex
- `speed` - target FPS (1-100)
- `seed` - random seed for reproducible rain

## Running

```bash
./zig-out/bin/neo-zig
```

### Options

```bash
# Colors
./zig-out/bin/neo-zig --color=green     # Default
./zig-out/bin/neo-zig --color=green2
./zig-out/bin/neo-zig --color=green3
./zig-out/bin/neo-zig --color=gold
./zig-out/bin/neo-zig --color=red
./zig-out/bin/neo-zig --color=blue
./zig-out/bin/neo-zig --color=cyan
./zig-out/bin/neo-zig --color=yellow
./zig-out/bin/neo-zig --color=orange
./zig-out/bin/neo-zig --color=purple
./zig-out/bin/neo-zig --color=pink
./zig-out/bin/neo-zig --color=pink2
./zig-out/bin/neo-zig --color=gray
./zig-out/bin/neo-zig --color=rainbow
./zig-out/bin/neo-zig --color=vaporwave

# Character sets
./zig-out/bin/neo-zig --charset=mix        # Default: Japanese 60%, Cyrillic 20%, Braille 12%, ASCII 8%
./zig-out/bin/neo-zig --charset=katakana
./zig-out/bin/neo-zig --charset=ascii
./zig-out/bin/neo-zig --charset=extended
./zig-out/bin/neo-zig --charset=english
./zig-out/bin/neo-zig --charset=digits
./zig-out/bin/neo-zig --charset=punc
./zig-out/bin/neo-zig --charset=cyrillic
./zig-out/bin/neo-zig --charset=greek
./zig-out/bin/neo-zig --charset=arabic
./zig-out/bin/neo-zig --charset=hebrew
./zig-out/bin/neo-zig --charset=devanagari
./zig-out/bin/neo-zig --charset=binary
./zig-out/bin/neo-zig --charset=hex
./zig-out/bin/neo-zig --charset=braille
./zig-out/bin/neo-zig --charset=runic

# Speed (characters per second)
./zig-out/bin/neo-zig -S=2.0    # Slower
./zig-out/bin/neo-zig -S=8.0    # Faster

# Async mode (varying speeds per column)
./zig-out/bin/neo-zig --async

# Display a message
./zig-out/bin/neo-zig --message="WAKE UP NEO"

# Benchmark mode (run for N seconds and show performance stats)
./zig-out/bin/neo-zig --benchmark=5
./zig-out/bin/neo-zig --benchmark=10 --seed=42

# Disable glitch animation
./zig-out/bin/neo-zig --no-glitch

# Limit droplets per column
./zig-out/bin/neo-zig --droplets=2

# Combine options
./zig-out/bin/neo-zig --color=gold --charset=katakana --async -S=3.0
```

### Controls

- `q` or `ESC` - Quit
- `p` - Pause/Resume
- `Space` - Reset
- `↑` / `↓` - Increase/decrease speed
- `←` / `→` - Cycle through charsets
- `c` - Cycle through colors

### All Options

```
-h, --help             Show help message
-V, --version          Print version
-S, --speed=NUM        Set scroll speed (default: 8.0)
-c, --color=COLOR      Set color theme
    --colormode=MODE   Set color mode (0=mono, 16, 256, 32=truecolor)
-m, --message=STR      Display a message
-a, --async            Asynchronous scroll speed per column
    --charset=STR      Set character set
    --benchmark=SECS   Run in benchmark mode for N seconds
    --seed=NUM         Set random seed for reproducible runs
    --no-glitch        Disable glitch animation
    --droplets=NUM     Set max droplets per column (default: 3)
```

## Shell Completions

Tab completion is available for bash, zsh, and fish.

**bash** — add to `~/.bashrc`:
```bash
source /path/to/neo-zig/completions/neo-zig.bash
```

**zsh** — copy to a directory on your `$fpath`:
```bash
cp completions/neo-zig.zsh /usr/local/share/zsh/site-functions/_neo-zig
```

**fish** — copy to completions directory:
```bash
cp completions/neo-zig.fish ~/.config/fish/completions/
```

## Screenshots

![In Soviet Russia](assets/in_soviet_russia.png)

![Green Hexadecimal](assets/green_hex.png)

![Golden Greek](assets/golden_greek.png)

## Troubleshooting

**Q:** Characters display as garbage or boxes.
**A:** Your terminal font may not support the selected charset. Try `--charset=ascii` or install a font with broader Unicode support.

**Q:** Colors aren't working.
**A:** Make sure your terminal supports colors. Try `--colormode=16` or `--colormode=0` for monochrome.

**Q:** How do I change the speed?
**A:** Use `-S=<speed>` where lower values are slower (e.g., `-S=2.0`).

## License

This project is a Zig port of [neo](https://github.com/st3w/neo) by Stewart Reive.

**neo-zig** is provided under the GNU GPL v3. See [doc/COPYING](doc/COPYING) for more details.

## Acknowledgments

- [Stewart Reive](https://github.com/st3w) - Original author of neo
- Chris Allegretta and Abishek V Ashok - CMatrix authors
- Thomas E. Dickey - ncurses maintainer
- Everyone involved in "The Matrix" franchise

## Disclaimer

This project is not affiliated with "The Matrix", Warner Bros. Entertainment Inc., Village Roadshow Pictures, Silver Pictures, nor any of their parent companies, subsidiaries, partners, or affiliates.
