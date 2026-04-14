#!/usr/bin/env bash
set -euo pipefail

REPO="igor-borovoi/neo"
BINARY_NAME="neo-zig"

# --- Platform detection ---
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)  OS_NAME="linux" ;;
  Darwin) OS_NAME="macos" ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64)        ARCH_NAME="x86_64" ;;
  aarch64|arm64) ARCH_NAME="aarch64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

ASSET_NAME="${BINARY_NAME}-${OS_NAME}-${ARCH_NAME}"

# --- Fetch latest release tag ---
TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"

if [ -z "$TAG" ]; then
  # Fallback: follow the redirect from /releases/latest
  TAG="$(curl -fsSL -o /dev/null -w "%{url_effective}" \
    "https://github.com/${REPO}/releases/latest" \
    | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' || true)"
fi

if [ -z "$TAG" ]; then
  echo "Failed to determine latest release tag." >&2
  exit 1
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET_NAME}"

# --- Determine install location ---
if [ "${NEO_NO_INSTALL:-}" = "1" ]; then
  TARGET_DIR="$(mktemp -d)"
  CLEANUP=1
elif [ -n "${INSTALL_DIR:-}" ]; then
  TARGET_DIR="$INSTALL_DIR"
  CLEANUP=0
elif [ -w "/usr/local/bin" ] || [ "$(id -u)" = "0" ]; then
  TARGET_DIR="/usr/local/bin"
  CLEANUP=0
elif [ -d "$HOME/.local/bin" ]; then
  TARGET_DIR="$HOME/.local/bin"
  CLEANUP=0
else
  mkdir -p "$HOME/.local/bin"
  TARGET_DIR="$HOME/.local/bin"
  CLEANUP=0
fi

TARGET_PATH="${TARGET_DIR}/${BINARY_NAME}"

# --- Download ---
echo "Downloading neo-zig ${TAG} for ${OS_NAME}-${ARCH_NAME}..."
curl -fsSL --progress-bar -o "$TARGET_PATH" "$DOWNLOAD_URL"
chmod +x "$TARGET_PATH"

# --- ncurses check (Linux only) ---
if [ "$OS_NAME" = "linux" ]; then
  if ! ldconfig -p 2>/dev/null | grep -qE "libncursesw|libncurses\.so" && \
     ! ls /usr/lib/*/libncurses*.so* /usr/lib/libncurses*.so* 2>/dev/null | grep -q .; then
    echo ""
    echo "WARNING: ncurses runtime library not found. Install it with:"
    if command -v apt-get &>/dev/null; then
      echo "  sudo apt-get install libncursesw6"
    elif command -v dnf &>/dev/null; then
      echo "  sudo dnf install ncurses-libs"
    elif command -v pacman &>/dev/null; then
      echo "  sudo pacman -S ncurses"
    elif command -v apk &>/dev/null; then
      echo "  sudo apk add ncurses"
    else
      echo "  Install ncurses via your package manager"
    fi
    echo ""
  fi
fi

# --- macOS Gatekeeper note ---
if [ "$OS_NAME" = "macos" ]; then
  if xattr "$TARGET_PATH" 2>/dev/null | grep -q "com.apple.quarantine"; then
    echo "Note: if macOS blocks the binary, run: xattr -d com.apple.quarantine $TARGET_PATH"
  fi
fi

# --- Run in-place (no install) ---
if [ "${NEO_NO_INSTALL:-}" = "1" ]; then
  "$TARGET_PATH" "$@"
  rm -rf "$TARGET_DIR"
  exit 0
fi

# --- Installed ---
echo "Installed: $TARGET_PATH"

if ! echo ":$PATH:" | grep -q ":${TARGET_DIR}:"; then
  echo ""
  echo "Note: ${TARGET_DIR} is not in your PATH. Add to your shell config:"
  echo "  export PATH=\"${TARGET_DIR}:\$PATH\""
fi
