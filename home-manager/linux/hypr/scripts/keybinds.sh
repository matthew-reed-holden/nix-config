#!/usr/bin/env bash
# Open rofi with the keybinds custom-mode pre-selected.
# Tab cycles to drun/run/window/filebrowser if user wants to switch
# context without closing.
# Bound to Super+/.

exec rofi \
    -show keybinds \
    -modi "keybinds:$HOME/.local/bin/keybinds-mode.sh,drun,run,window,filebrowser" \
    -config "$HOME/.config/rofi/config-compact.rasi"
