#!/bin/sh
# Fallback installer for people without a tap:  curl -fsSL <raw url>/install.sh | sh
set -eu
REPO="https://raw.githubusercontent.com/igorsigalovs/tailscale-multi/main"
DEST="${TSM_PREFIX:-/usr/local/bin}"

[ "$(uname)" = "Darwin" ] || { echo "tsm is macOS only" >&2; exit 1; }
command -v tailscaled >/dev/null 2>&1 || [ -x /opt/homebrew/bin/tailscaled ] || [ -x /usr/local/bin/tailscaled ] \
  || { echo "tailscaled not found; run: brew install tailscale" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

tmp=$(mktemp)
curl -fsSL "$REPO/bin/tsm" -o "$tmp"
chmod 755 "$tmp"
if [ -w "$DEST" ]; then mv "$tmp" "$DEST/tsm"; else sudo mv "$tmp" "$DEST/tsm"; fi
echo "installed $DEST/tsm ($("$DEST/tsm" version))"
echo "next: tsm add <name> [--login-server URL]"
