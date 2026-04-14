# fish completion for neo-zig
# Place in ~/.config/fish/completions/ or /usr/share/fish/vendor_completions.d/

set -l colors green green2 green3 gold red blue cyan yellow orange purple pink pink2 rainbow gray vaporwave
set -l charsets mix katakana ascii extended english digits punc binary hex cyrillic greek arabic hebrew devanagari braille runic
set -l colormodes mono 0 16 256 32

complete -c neo-zig -s h -l help        -d 'Show help message'
complete -c neo-zig -s V -l version     -d 'Print version'
complete -c neo-zig -s a -l async       -d 'Asynchronous scroll speed'
complete -c neo-zig      -l no-glitch   -d 'Disable glitch animation'

complete -c neo-zig -s S -l speed       -d 'Set scroll speed in FPS (default: 20)' -r
complete -c neo-zig -s m -l message     -d 'Display a message' -r
complete -c neo-zig      -l seed        -d 'Random seed for reproducible output' -r
complete -c neo-zig      -l droplets    -d 'Maximum number of droplets' -r
complete -c neo-zig      -l benchmark   -d 'Run benchmark for N seconds' -r

complete -c neo-zig -s c -l color       -d 'Set color' -r -a "$colors"
complete -c neo-zig      -l colormode   -d 'Set color mode' -r -a "$colormodes"
complete -c neo-zig      -l charset     -d 'Set character set' -r -a "$charsets"

# Per-value descriptions for --color
complete -c neo-zig -s c -l color -n '__fish_seen_argument -s c -l color' -a "green"     -d 'Classic Matrix green'
complete -c neo-zig -s c -l color -n '__fish_seen_argument -s c -l color' -a "gold"      -d 'Gold / amber'
complete -c neo-zig -s c -l color -n '__fish_seen_argument -s c -l color' -a "red"       -d 'Red'
complete -c neo-zig -s c -l color -n '__fish_seen_argument -s c -l color' -a "rainbow"   -d 'Cycling rainbow'
complete -c neo-zig -s c -l color -n '__fish_seen_argument -s c -l color' -a "vaporwave" -d 'Vaporwave palette'

# Per-value descriptions for --charset
complete -c neo-zig -l charset -n '__fish_seen_argument -l charset' -a "arabic"   -d 'Arabic (flows left-to-right)'
complete -c neo-zig -l charset -n '__fish_seen_argument -l charset' -a "mix"      -d 'Mixed (80% katakana default)'
complete -c neo-zig -l charset -n '__fish_seen_argument -l charset' -a "katakana" -d 'Japanese katakana'
complete -c neo-zig -l charset -n '__fish_seen_argument -l charset' -a "braille"  -d 'Braille patterns'
complete -c neo-zig -l charset -n '__fish_seen_argument -l charset' -a "runic"    -d 'Runic alphabet'
