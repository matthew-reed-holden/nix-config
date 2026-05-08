#!/usr/bin/env bash
# Catppuccin flavor switcher — overwrites ~/.config/rofi/colors.rasi
# with the picked variant's palette. Affects rofi only (live-reload).
# Bound to Super+Shift+T.

set -euo pipefail

THEMES_DIR="$HOME/.config/rofi/themes"
ACTIVE_FILE="$HOME/.config/rofi/colors.rasi"
ROFI_CFG="$HOME/.config/rofi/config-compact.rasi"

choice=$(printf 'Latte\nFrappe\nMacchiato\nMocha\nDynamic\n' \
    | rofi -dmenu -i -p "Flavor" -config "$ROFI_CFG")

[[ -z "$choice" ]] && exit 0

flavor=$(echo "$choice" | tr '[:upper:]' '[:lower:]')
src="$THEMES_DIR/$flavor.rasi"

[[ -f "$src" ]] || { notify-send "Flavor switcher" "Missing $src"; exit 1; }

# install -m 644 forces writable mode, overrides any read-only carry-
# over from the previous Nix-managed symlink era.
install -m 644 "$src" "$ACTIVE_FILE"
notify-send "Flavor: $choice"
