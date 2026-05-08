#!/usr/bin/env bash
# Wallpaper picker + cache generator.
#
# Modes:
#   No args  → rofi picker over $WALLPAPER_DIR.
#   1 arg    → apply that path directly (used by autostart on default).
#
# Side effects (in addition to applying via awww):
#   ~/.cache/wallpaper/blurred_wallpaper.png  — hyprlock background
#   ~/.cache/wallpaper/square_wallpaper.png   — hyprlock avatar

set -euo pipefail

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
ROFI_CFG="$HOME/.config/rofi/config-compact.rasi"
CACHE_DIR="$HOME/.cache/wallpaper"

mkdir -p "$CACHE_DIR"

if [[ $# -gt 0 ]]; then
    target="$1"
else
    if [[ ! -d "$WALLPAPER_DIR" ]]; then
        notify-send "Wallpaper picker" "Directory not found: $WALLPAPER_DIR"
        exit 1
    fi
    selected=$(
        find "$WALLPAPER_DIR" -type f \
            \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) \
            -printf '%f\n' \
        | sort \
        | rofi -dmenu -i -p "Wallpaper" -config "$ROFI_CFG"
    )
    [[ -z "$selected" ]] && exit 0
    target="$WALLPAPER_DIR/$selected"
fi

[[ -f "$target" ]] || { notify-send "Wallpaper picker" "Not a file: $target"; exit 1; }

# Apply (awww is idempotent with same path).
awww img --transition-type wipe --transition-duration 1 "$target" || true

# Generate hyprlock cache images in parallel.
magick "$target" \
    -resize 1920x1080^ -gravity center -extent 1920x1080 \
    -blur 0x20 \
    "$CACHE_DIR/blurred_wallpaper.png" &

magick "$target" \
    -resize 280x280^ -gravity center -extent 280x280 \
    "$CACHE_DIR/square_wallpaper.png" &

wait

# Rofi @import — exposes `@current-image` to widget configs that want
# the wallpaper as a background-image.
cat > "$CACHE_DIR/current.rasi" <<EOF
* {
    current-image: url("$target", height);
}
EOF

# matugen — regenerate templated configs (rofi colors etc.) from the
# new wallpaper's palette. Skips silently if matugen isn't installed.
if command -v matugen >/dev/null 2>&1; then
    matugen image "$target" >/dev/null 2>&1 || true
fi
