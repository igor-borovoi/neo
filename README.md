# neo-zig

![neo is AWESOME](assets/neo_is_awesome.gif)

**WARNING: neo may cause discomfort and seizures in people with photosensitive epilepsy. User discretion is advised.**

**neo-zig** is a Zig port of [neo](https://github.com/st3w/neo), recreating the digital rain effect from "The Matrix". Streams of random characters will endlessly scroll down your terminal screen.

## Features

- Simulates the Matrix digital rain effect
- Multiple color themes (green, gold, red, blue, cyan, purple, pink, rainbow, etc.)
- Multiple character sets:
  - ASCII (default)
  - Katakana (Japanese)
  - Cyrillic (Russian)
  - Greek
  - Hebrew
  - Arabic
  - Braille
  - Runic
  - Binary (0s and 1s)
  - Hexadecimal
- Supports 16/256 colors and truecolor
- Handles terminal resizing
- Async mode for varying column speeds
- Display custom messages

## Prerequisites

**neo-zig** works on Linux and other UNIX-like operating systems (macOS, FreeBSD). Windows is not supported natively but may work via WSL.

Required:
- [Zig](https://ziglang.org/download/) (0.11.0 or later)
- ncurses development library (`libncurses-dev` on Debian/Ubuntu, `ncurses` on Arch)

For Unicode characters, use a font that supports the character set you want to display and ensure your locale is set to UTF-8.

## Building

```bash
git clone https://github.com/YOUR_USERNAME/neo-zig.git
cd neo-zig
zig build
```

The binary will be at `./zig-out/bin/neo-zig`.

## Running

```bash
./zig-out/bin/neo-zig
```

### Options

```bash
# Colors
./zig-out/bin/neo-zig --color=green    # Default
./zig-out/bin/neo-zig --color=gold
./zig-out/bin/neo-zig --color=red
./zig-out/bin/neo-zig --color=blue
./zig-out/bin/neo-zig --color=cyan
./zig-out/bin/neo-zig --color=purple
./zig-out/bin/neo-zig --color=rainbow

# Character sets
./zig-out/bin/neo-zig --charset=katakana
./zig-out/bin/neo-zig --charset=cyrillic
./zig-out/bin/neo-zig --charset=greek
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

# Combine options
./zig-out/bin/neo-zig --color=gold --charset=katakana --async -S=3.0
```

### Controls

- `q` or `ESC` - Quit
- `p` - Pause/Resume
- `Space` - Reset

### All Options

```
-h, --help             Show help message
-V, --version          Print version
-S, --speed=NUM        Set scroll speed (default: 4.0)
-c, --color=COLOR      Set color theme
    --colormode=MODE   Set color mode (0=mono, 16, 256, 32=truecolor)
-m, --message=STR      Display a message
-a, --async            Asynchronous scroll speed per column
    --charset=STR      Set character set
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
