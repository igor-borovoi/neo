# bash completion for neo-zig
# Source this file or place it in /etc/bash_completion.d/

_neo_zig() {
    local cur prev words cword
    _init_completion || return

    local colors="green green2 green3 gold red blue cyan yellow orange purple pink pink2 rainbow gray vaporwave"
    local charsets="mix katakana ascii extended english digits punc binary hex cyrillic greek arabic hebrew devanagari braille runic"
    local colormodes="mono 0 16 256 32"

    case "$prev" in
        -c|--color)
            COMPREPLY=( $(compgen -W "$colors" -- "$cur") )
            return ;;
        --charset)
            COMPREPLY=( $(compgen -W "$charsets" -- "$cur") )
            return ;;
        --colormode)
            COMPREPLY=( $(compgen -W "$colormodes" -- "$cur") )
            return ;;
        -S|--speed|--seed|--droplets|--benchmark|-m|--message)
            # Expect a value — no completions
            return ;;
    esac

    case "$cur" in
        --color=*)
            COMPREPLY=( $(compgen -W "$colors" -- "${cur#*=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--color=}" )
            return ;;
        --charset=*)
            COMPREPLY=( $(compgen -W "$charsets" -- "${cur#*=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--charset=}" )
            return ;;
        --colormode=*)
            COMPREPLY=( $(compgen -W "$colormodes" -- "${cur#*=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/--colormode=}" )
            return ;;
        -c=*)
            COMPREPLY=( $(compgen -W "$colors" -- "${cur#*=}") )
            COMPREPLY=( "${COMPREPLY[@]/#/-c=}" )
            return ;;
        -S=*)
            return ;;
        -m=*)
            return ;;
    esac

    local flags="-h --help -V --version -S --speed -c --color --colormode
                 -m --message -a --async --charset --no-glitch
                 --seed --droplets --benchmark"
    COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
}

complete -F _neo_zig neo-zig
