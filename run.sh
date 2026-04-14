#!/bin/bash
case "$(uname -s),$(uname -m)" in
  Darwin,arm64)   B=macos-aarch64 ;;
  Linux,x86_64)   B=linux-x86_64 ;;
  Linux,aarch64)  B=linux-aarch64 ;;
  *) echo "Unsupported platform"; exit 1 ;;
esac
curl -fsSL "https://github.com/igor-borovoi/neo/releases/latest/download/neo-zig-$B" -o /tmp/neo-zig
chmod +x /tmp/neo-zig
/tmp/neo-zig
