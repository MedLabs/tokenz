#!/usr/bin/env bash
#
# Install (or upgrade) the Tokenz plasmoid and its panel icon.
#
#   ./install.sh
#
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID="org.tokenz.plasma"

if command -v kpackagetool6 >/dev/null 2>&1; then
    KPT=kpackagetool6
elif command -v kpackagetool5 >/dev/null 2>&1; then
    KPT=kpackagetool5
else
    echo "kpackagetool6/kpackagetool5 not found" >&2
    exit 1
fi

if "$KPT" --type Plasma/Applet --list 2>/dev/null | grep -qx "$ID"; then
    "$KPT" --type Plasma/Applet --upgrade "$PKG_DIR"
else
    "$KPT" --type Plasma/Applet --install "$PKG_DIR"
fi

ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$ICON_DIR"
cp "$PKG_DIR/contents/icons/tokenz.svg" "$ICON_DIR/tokenz.svg"
chmod 644 "$ICON_DIR/tokenz.svg" || true

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "Installed $ID. Add \"Tokenz\" from the panel's Add Widgets dialog."
