#compdef neo-zig
# zsh completion for neo-zig
# Place in a directory on your $fpath, e.g. /usr/local/share/zsh/site-functions/

_neo-zig() {
    local -a colors charsets colormodes

    colors=(
        'green:classic Matrix green'
        'green2:alternate green'
        'green3:alternate green'
        'gold:gold / amber'
        'red:red'
        'blue:blue'
        'cyan:cyan'
        'yellow:yellow'
        'orange:orange'
        'purple:purple'
        'pink:pink'
        'pink2:alternate pink'
        'rainbow:cycling rainbow'
        'gray:grayscale'
        'vaporwave:vaporwave palette'
    )

    charsets=(
        'mix:80% katakana / 10% cyrillic / 6% braille / 4% ASCII (default)'
        'katakana:Japanese katakana'
        'ascii:ASCII printable characters'
        'extended:extended ASCII'
        'english:English letters only'
        'digits:decimal digits 0-9'
        'punc:punctuation'
        'binary:binary 0s and 1s'
        'hex:hexadecimal'
        'cyrillic:Cyrillic script'
        'greek:Greek alphabet'
        'arabic:Arabic script (flows left-to-right)'
        'hebrew:Hebrew script'
        'devanagari:Devanagari script'
        'braille:Braille patterns'
        'runic:Runic alphabet'
    )

    colormodes=(
        'mono:monochrome (no color)'
        '16:16-color mode'
        '256:256-color mode'
        '32:truecolor mode'
    )

    _arguments -s \
        '(-h --help)'{-h,--help}'[show help message]' \
        '(-V --version)'{-V,--version}'[print version]' \
        '(-S --speed)'{-S,--speed}'=[set scroll speed (default: 20)]:speed (fps)' \
        '(-c --color)'{-c,--color}'=[set color]:color:->color' \
        '--colormode=[set color mode]:mode:->colormode' \
        '(-m --message)'{-m,--message}'=[display a message]:message text' \
        '(-a --async)'{-a,--async}'[asynchronous scroll speed]' \
        '--charset=[character set]:charset:->charset' \
        '--no-glitch[disable glitch animation]' \
        '--seed=[random seed for reproducible output]:seed (integer)' \
        '--droplets=[maximum number of droplets]:count (integer)' \
        '--benchmark=[run benchmark for N seconds]:seconds'

    case $state in
        color)
            _describe 'color' colors ;;
        colormode)
            _describe 'color mode' colormodes ;;
        charset)
            _describe 'charset' charsets ;;
    esac
}

_neo-zig "$@"
