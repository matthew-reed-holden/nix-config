#!/bin/sh
# Toggle-or-start waybar.
#
# Used by the Plasma global shortcut (Meta+Shift+B). If waybar isn't running,
# start it (respects config's start_hidden so first key press reveals
# it). If it is running, send SIGUSR1 to toggle visibility.

if pgrep -x waybar >/dev/null; then
  pkill -SIGUSR1 waybar
else
  waybar &
fi
