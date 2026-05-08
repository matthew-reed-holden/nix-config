#!/usr/bin/env bash
# Power menu — rofi-driven dialog for lock/logout/suspend/reboot/poweroff.

set -euo pipefail

ROFI_CFG="$HOME/.config/rofi/config-compact.rasi"

choice=$(printf 'Lock\nLogout\nSuspend\nReboot\nShutdown\n' \
    | rofi -dmenu -i -p "Power" -config "$ROFI_CFG")

case "$choice" in
    Lock)     exec hyprlock ;;
    Logout)   exec uwsm stop ;;
    Suspend)  exec systemctl suspend ;;
    Reboot)   exec systemctl reboot ;;
    Shutdown) exec systemctl poweroff ;;
    *)        exit 0 ;;
esac
