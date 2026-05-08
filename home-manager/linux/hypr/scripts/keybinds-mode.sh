#!/usr/bin/env bash
# Rofi script-mode adapter — outputs formatted bind rows on stdout.
# Used as: rofi -modi "keybinds:keybinds-mode.sh"
# Picking a row is a no-op (informational). exit 0 keeps rofi closed.

set -euo pipefail

# When rofi calls a script-mode with an argument (the picked row), we
# do nothing — list is read-only.
[[ $# -gt 0 ]] && exit 0

hyprctl binds -j \
    | jq -r '.[] | "\(.modmask)|\(.key)|\(.dispatcher)|\(.arg)"' \
    | awk -F'|' '
        {
            m = ""
            if ($1 % 2)             m = m "Shift+"
            if (int($1/4) % 2)      m = m "Ctrl+"
            if (int($1/8) % 2)      m = m "Alt+"
            if (int($1/64) % 2)     m = m "Super+"
            arg = ($4 == "null" || $4 == "") ? "" : $4
            printf "%-22s  %s %s\n", m $2, $3, arg
        }
    ' \
    | sort
