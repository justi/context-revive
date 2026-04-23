#!/usr/bin/env bash
# revive installer — copies bin/revive into $PREFIX/bin
# Usage: curl -sSL https://raw.githubusercontent.com/justi/context-revive/main/install.sh | bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
REPO="${REPO:-justi/context-revive}"
REF="${REF:-main}"
URL="https://raw.githubusercontent.com/${REPO}/${REF}/bin/revive"
DEST="${PREFIX}/bin/revive"

mkdir -p "${PREFIX}/bin"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$DEST"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$DEST" "$URL"
else
  echo "error: need curl or wget" >&2
  exit 1
fi

chmod +x "$DEST"
echo "installed: $DEST"

case ":$PATH:" in
  *":${PREFIX}/bin:"*) ;;
  *) echo "note: add ${PREFIX}/bin to PATH (not currently in \$PATH)" >&2 ;;
esac
