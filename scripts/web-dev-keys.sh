#!/usr/bin/env bash
# Hotkey listener for `task web:dev`. Runs in the background next to the
# foreground file watcher, so it reads the controlling terminal directly.
url="$1"

open_url() { open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null; }

show_help() {
  echo ""
  echo "  Hotkeys:"
  echo "    o / Space      open $url in the browser"
  echo "    r              rebuild the wasm bundle now"
  echo "    h              show hotkeys"
  echo "    q / Esc / ^C   stop the dev server"
  echo ""
}

# INT the whole process group (server, watcher, this script), same as Ctrl+C
quit() { kill -INT 0; exit 0; }

show_help
while IFS= read -rsn1 key; do
  case "$key" in
    o | " ") open_url ;;
    r)
      echo "rebuilding..."
      zig build wasm 2>&1 && echo "rebuilt - the page reloads if anything changed"
      ;;
    h) show_help ;;
    q) quit ;;
    $'\e')
      # Lone Esc quits; Esc followed by more bytes is an escape sequence (arrows etc.)
      # Integer timeout: macOS ships bash 3.2, which rejects fractional -t values.
      read -rsn2 -t 1 _ || quit
      ;;
  esac
done < /dev/tty
