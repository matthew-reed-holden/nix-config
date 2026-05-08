#!/usr/bin/env bash
# Screenshot menu — rofi picker for Full / Region / Window / Edit.
# Output saved to ~/Pictures/Screenshots/<timestamp>.png AND copied to
# clipboard. "Edit" pipes through swappy for annotation before save.
# Bound to Print key.

set -euo pipefail

ROFI_CFG="$HOME/.config/rofi/config-screenshot.rasi"
DEST_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DEST_DIR"
ts=$(date +'%Y-%m-%d_%H-%M-%S')
out="$DEST_DIR/screenshot_${ts}.png"

choice=$(printf 'Full\nRegion\nWindow\nEdit (region → swappy)\n' \
    | rofi -dmenu -i -p "Screenshot" -config "$ROFI_CFG")

case "$choice" in
    Full)
        grim "$out"
        ;;
    Region)
        region=$(slurp) || exit 0
        grim -g "$region" "$out"
        ;;
    Window)
        # window pixel via slurp -p (point click)
        region=$(slurp -p) || exit 0
        grim -g "$region" "$out"
        ;;
    "Edit (region → swappy)")
        region=$(slurp) || exit 0
        grim -g "$region" - | swappy -f - -o "$out"
        ;;
    *) exit 0 ;;
esac

[[ -f "$out" ]] || exit 1

wl-copy < "$out"
notify-send "Screenshot" "Saved $out — also on clipboard"
