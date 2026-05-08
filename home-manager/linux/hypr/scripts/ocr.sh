#!/usr/bin/env bash
# Screen OCR — pick language, region-select, tesseract → clipboard.
# Bound to Super+Alt+O.

set -euo pipefail

ROFI_CFG="$HOME/.config/rofi/config-ocr-lang.rasi"

# Language picker — codes match tesseract data files
# (eng, fra, deu, spa, ita, por, nld, jpn, kor, chi_sim, ...).
# Add languages by installing tesseract-data-<lang>.
choice=$(printf 'English (eng)\nFrench (fra)\nGerman (deu)\nSpanish (spa)\n' \
    | rofi -dmenu -i -p "OCR Language" -config "$ROFI_CFG")
[[ -z "$choice" ]] && exit 0

# Strip everything outside parens
lang=$(echo "$choice" | sed -n 's/.*(\(.*\)).*/\1/p')
[[ -z "$lang" ]] && exit 0

# Confirm tesseract data installed for the picked lang.
if ! tesseract --list-langs 2>/dev/null | grep -qx "$lang"; then
    notify-send "OCR" "Missing tesseract-data-$lang. Install via pacman."
    exit 1
fi

# Region select + OCR pipeline.
region=$(slurp) || exit 0
text=$(grim -g "$region" - | tesseract -l "$lang" - - 2>/dev/null)

if [[ -z "${text//[[:space:]]/}" ]]; then
    notify-send "OCR" "No text detected"
    exit 0
fi

printf '%s' "$text" | wl-copy
notify-send "OCR ($lang)" "$(printf '%s' "$text" | head -c 80)…"
