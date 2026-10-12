#!/usr/bin/env bash
# caffeine.sh — a mac-`caffeinate` equivalent for Hyprland.
#
# A transient systemd user unit holds a systemd-inhibit lock. The unit IS the
# state: ActiveState for liveness, Description encodes "<mode>|<end>|<label>".
#
# Design + rationale: docs/superpowers/specs/2026-07-30-caffeine-design.md

set -euo pipefail

UNIT=caffeine
SELF=$(readlink -f "${BASH_SOURCE[0]}") # repo path in dev, store path once installed
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
WAYBAR_SIG=8

# ponytail: ephemeral flag, not state — suppresses the "Decaffeinated" toast
# when a start is only replacing a running unit.
REPLACING="$RUNTIME/caffeine.replacing"

# Codepoints read from the font's cmap, not guessed; the names are the guard.
ICON_OFF=$'\U000F06CA' # nf-md-coffee_outline — hollow cup, no steam
ICON_ON=$'\U0000EF59'  # nf-fa-mug_hot        — filled mug, steam (no MDI cup has any)

ROFI_CFG="$HOME/.config/rofi/config-compact.rasi"

NOTIFY_ICON_ON=budgie-caffeine-cup-full # both shipped by Tela-circle-dracula
NOTIFY_ICON_OFF=budgie-caffeine-cup-empty

# ponytail: random draw, not a true rotation — a no-repeat cycle needs a
# persisted index, and the unit Description is meant to be the only state.
FLAVOR_ON=(
  "You shall not sleep." "Ride on, Shadowfax." "The board is set."
  "Fly, you fools." "The way to sleep is shut."
  "Espresso pulled." "Another round, then." "Beans committed."
  "Double shot, no room." "Fresh pot on."
  "WIRED." "Sleep is a construct." "I can see sound."
  "No thoughts. Only up." "Vibrating slightly."
  "Sleep deferred." "The machine persists." "Idle is cancelled."
  "Staying up. On purpose." "hypridle has opinions."
)
FLAVOR_OFF=(
  "Rest now." "The long defeat is over." "Homeward, then."
  "The watch is ended." "Sleep, and dream of the Shire."
  "Cup's empty." "Closing time." "Last call."
  "Machine's off." "Tab closed."
  "Crashing." "The jitters subside." "Powering down."
  "Sweet, sweet sleep." "Back to baseline."
  "Sleep restored." "Standing down." "Idle re-enabled."
  "Going back to bed." "Normal service resumed."
)

flavor() {
  case $1 in
  on) printf '%s\n' "${FLAVOR_ON[RANDOM % ${#FLAVOR_ON[@]}]}" ;;
  off) printf '%s\n' "${FLAVOR_OFF[RANDOM % ${#FLAVOR_OFF[@]}]}" ;;
  esac
}

active() { systemctl --user -q is-active "$UNIT.service" 2>/dev/null; }

# Sets $mode $end $label; returns 1 when not caffeinated.
read_state() {
  # Load-bearing: systemd reports a synthetic Description equal to the unit
  # name for units it has never seen, which would parse as garbage.
  active || return 1
  local d
  d=$(systemctl --user show -P Description "$UNIT.service" 2>/dev/null)
  IFS='|' read -r mode end label <<<"$d"
  [ -n "${mode:-}" ] && [ -n "${end:-}" ]
}

notify() { # notify <summary> [body] [icon-name]
  local icon=()
  if [ -n "${3:-}" ]; then icon=(-i "$3"); fi
  notify-send -a Caffeine \
    -h string:x-canonical-private-synchronous:caffeine \
    "${icon[@]}" "$1" "${2:-}" 2>/dev/null || true
}

signal_waybar() { pkill "-RTMIN+$WAYBAR_SIG" waybar 2>/dev/null || true; }

# start <mode> <end_epoch> <label> <holder...>
start() {
  local mode=$1 end=$2 label=$3
  shift 3
  if active; then
    : >"$REPLACING"
    systemctl --user stop "$UNIT.service"
  fi
  # Explicit bash: the source file is 644, so a bare ExecStopPost path fails
  # the whole job. No ExecStartPost — the unit is still `activating` during
  # it, so a hook gated on active() would do nothing; the toast below runs
  # client-side instead. Status must be systemd-run's, not signal_waybar's
  # always-0, or a failed start still announces "Caffeinated".
  if ! systemd-run --user --unit="$UNIT" \
    --description="$mode|$end|$label" \
    --property=CollectMode=inactive-or-failed \
    --property=ExecStopPost="/usr/bin/bash $SELF _stopped" \
    systemd-inhibit --what=idle:sleep --who=caffeine --why="$label" \
    "$@" >/dev/null; then
    return 1
  fi
  notify "$(flavor on)" "Caffeinated · $label" "$NOTIFY_ICON_ON"
  signal_waybar
}

cmd_on() { start on 0 indefinite sleep infinity; }

cmd_off() {
  if active; then systemctl --user stop "$UNIT.service"; fi
}

cmd_toggle() {
  if active; then cmd_off; else cmd_on; fi
}

parse_timespan() {
  local out us
  if ! out=$(systemd-analyze timespan "$1" 2>&1); then
    printf '%s\n' "$out" >&2
    return 1
  fi
  us=$(awk '/μs:/{print $2}' <<<"$out")
  if [ -z "$us" ]; then
    echo "could not parse timespan '$1'" >&2
    return 1
  fi
  echo $((us / 1000000))
}

cmd_for() {
  local secs
  if ! secs=$(parse_timespan "${1:-}"); then
    notify "Caffeine" "Bad duration: ${1:-}"
    return 1
  fi
  if [ "$secs" -le 0 ]; then
    notify "Caffeine" "Duration must be greater than zero"
    return 1
  fi
  start for "$(($(date +%s) + secs))" "for $1" sleep "$secs"
}

cmd_until() {
  local out target now
  if ! out=$(date -d "${1:-}" +%s 2>&1); then # 2>&1, so date's own error reaches stderr
    printf '%s\n' "$out" >&2
    notify "Caffeine" "Bad time: ${1:-}"
    return 1
  fi
  target=$out
  now=$(date +%s)
  # ponytail: naive +1 day rollover, ignores DST. Use `date -d "tomorrow $1"`
  # if an hour of drift ever matters.
  if [ "$target" -le "$now" ]; then target=$((target + 86400)); fi
  start until "$target" "until $(date -d "@$target" '+%a %H:%M')" \
    sleep $((target - now))
}

# Both variants share one holder: tail exits when the watched pid does.
# The command runs in the caller's shell, not the unit, so it keeps its
# terminal and exit code. CAFFEINE_LABEL overrides the derived label —
# the menu sets it, since `bash -c` would otherwise label everything "bash".
cmd_while() {
  local pid rc=0
  if [ "${1:-}" = --pid ]; then
    pid=${2:-}
    if ! kill -0 "$pid" 2>/dev/null; then
      notify "Caffeine" "No such process: $pid"
      return 1
    fi
    # Untested call is fine here — no forked child to abandon, unlike below.
    start while 0 \
      "${CAFFEINE_LABEL:-$(ps -p "$pid" -o comm= 2>/dev/null || echo "pid $pid")}" \
      tail --pid="$pid" -f /dev/null
    return 0
  fi

  if [ $# -eq 0 ]; then
    echo "usage: caffeine.sh while <cmd...>" >&2
    return 1
  fi

  "$@" <&0 & # <&0 or bash gives a background job /dev/null for stdin
  pid=$!
  # Testing start keeps set -e from killing us here and orphaning that child.
  # The command matters more than the lock, so a failed lock only warns.
  if ! start while 0 "${CAFFEINE_LABEL:-$(basename "$1")}" \
    tail --pid="$pid" -f /dev/null; then
    echo "caffeine: lock failed, running uncaffeinated" >&2
  fi
  wait "$pid" || rc=$?
  return "$rc"
}

fmt_remaining() {
  local s=$1 h m
  if [ "$s" -lt 60 ]; then
    echo "<1m"
    return
  fi
  h=$((s / 3600))
  m=$(((s % 3600) / 60))
  if [ "$h" -gt 0 ]; then echo "${h}h${m}m"; else echo "${m}m"; fi
}

cmd_waybar() {
  local text tip class left
  if read_state; then
    class=active
    case "$mode" in
    for | until)
      left=$((end - $(date +%s)))
      if [ "$left" -lt 0 ]; then left=0; fi
      text="$ICON_ON $(fmt_remaining "$left")"
      tip="Caffeinated $label — $(fmt_remaining "$left") left"
      ;;
    while)
      text="$ICON_ON $label"
      tip="Caffeinated while $label is running"
      ;;
    *)
      text="$ICON_ON"
      tip="Caffeinated — indefinite"
      ;;
    esac
  else
    class=idle
    text="$ICON_OFF"
    tip="Not caffeinated"
  fi
  # jq, not printf: labels can contain quotes and would break waybar's parser.
  jq -nc --arg t "$text" --arg c "$class" \
    --arg tip "$tip"$'\n'"Left: menu  Right: toggle" \
    '{text: $t, alt: $c, class: $c, tooltip: $tip}'
}

cmd_status() {
  local line left icon
  if read_state; then
    icon=$NOTIFY_ICON_ON
    line="Caffeinated — $label"
    if [ "$end" != 0 ]; then
      left=$((end - $(date +%s)))
      if [ "$left" -lt 0 ]; then left=0; fi
      line="$line ($(fmt_remaining "$left") left)"
    fi
  else
    icon=$NOTIFY_ICON_OFF
    line="Not caffeinated"
  fi
  notify "Caffeine" "$line" "$icon"
  echo "$line"
}

# ExecStopPost hook — expiry, manual stop and menu stop all converge here.
cmd_stopped() {
  if [ -e "$REPLACING" ]; then
    rm -f "$REPLACING"
  else
    notify "$(flavor off)" "Decaffeinated" "$NOTIFY_ICON_OFF"
  fi
  signal_waybar
}

rofi_menu() {
  local prompt=$1
  shift # extra args forwarded so menu_while can add -format i
  rofi -dmenu -i -p "$prompt" -config "$ROFI_CFG" "$@"
}

# Empty stdin gives rofi no list to match, so it returns whatever was typed.
rofi_input() { rofi -dmenu -p "$1" -config "$ROFI_CFG" </dev/null; }

# Every rofi capture below needs `|| true` — rofi exits 1 when dismissed, and
# set -e would kill the script before the empty-selection guard ran.
menu_for() {
  local c
  c=$(printf '15m\n30m\n1h\n2h\n4h\n8h\nCustom…\n' | rofi_menu "Caffeinate for") || true
  if [ -z "$c" ]; then return 0; fi
  if [ "$c" = "Custom…" ]; then c=$(rofi_input "Timespan (e.g. 90min)") || true; fi
  if [ -z "$c" ]; then return 0; fi
  cmd_for "$c"
}

menu_until() {
  local c
  c=$(printf '12:00\n17:00\n23:59\nCustom…\n' | rofi_menu "Caffeinate until") || true
  if [ -z "$c" ]; then return 0; fi
  if [ "$c" = "Custom…" ]; then c=$(rofi_input "Time (e.g. 17:00)") || true; fi
  if [ -z "$c" ]; then return 0; fi
  cmd_until "$c"
}

menu_while() {
  local rows=() idx cmd
  # No -u: single-process apps share a pid across windows, so deduping hides
  # real windows and buys nothing.
  mapfile -t rows < <(
    hyprctl clients -j |
      jq -r '.[] | select(.pid > 0) | "\(.pid)\t\(.class) — \(.title)"' |
      sort -t$'\t' -k2
  )
  rows+=($'0\tCustom command…')

  # -format i returns the row index, so the pid needn't survive rofi's output.
  idx=$(printf '%s\n' "${rows[@]}" | cut -f2- | rofi_menu "Caffeinate while" -format i) || return 0
  if [ -z "$idx" ] || [ "$idx" -lt 0 ]; then return 0; fi

  local pid=${rows[$idx]%%$'\t'*}
  if [ "$pid" = 0 ]; then
    cmd=$(rofi_input "Command") || true
    if [ -z "$cmd" ]; then return 0; fi
    CAFFEINE_LABEL="${cmd%% *}" cmd_while bash -c "$cmd"
  else
    cmd_while --pid "$pid"
  fi
}

menu() {
  local choice
  # Six fixed entries — deliberately not state-dependent, so muscle memory
  # holds. Decaffeinate must stay first, or *Caffeinate shadows its glob.
  # Glyphs: timer_outline, clock_outline, application_outline, information.
  choice=$(printf '%s\n' \
    "$ICON_OFF  Decaffeinate" \
    "$ICON_ON  Caffeinate" \
    $'\U000F051B  Caffeinate for…' \
    $'\U000F0150  Caffeinate until…' \
    $'\U000F0614  Caffeinate while…' \
    $'\U000F02FC  Status' |
    rofi_menu Caffeine) || true
  case "$choice" in
  *Decaffeinate) cmd_off ;;
  *"Caffeinate for…") menu_for ;;
  *"Caffeinate until…") menu_until ;;
  *"Caffeinate while…") menu_while ;;
  *Status) cmd_status ;;
  *Caffeinate) cmd_on ;;
  *) return 0 ;;
  esac
}

selftest() {
  # Ctrl-C mid-suite would otherwise strand the `cmd_for 1h` below.
  trap 'cmd_off || true' EXIT
  fails=0
  pass() { printf '  %-44s ok\n' "$1"; }
  fail() {
    printf '  %-44s FAIL\n' "$1"
    fails=$((fails + 1))
  }

  echo "caffeine selftest"

  cmd_off || true # destructive: stops any caffeination already running
  sleep 0.5
  if active; then fail "starts with no unit"; else pass "starts with no unit"; fi

  cmd_on
  sleep 0.5
  if active; then pass "on: unit active"; else fail "on: unit active"; fi
  if systemd-inhibit --list | grep -q 'caffeine.*sleep:idle'; then
    pass "on: inhibitor holds sleep:idle"
  else
    fail "on: inhibitor holds sleep:idle"
  fi
  if read_state && [ "$mode" = on ] && [ "$end" = 0 ]; then
    pass "on: description parses as on|0"
  else
    fail "on: description parses as on|0"
  fi

  cmd_off
  sleep 0.5
  if active; then fail "off: unit gone"; else pass "off: unit gone"; fi
  if systemd-inhibit --list | grep -q 'caffeine.*sleep:idle'; then
    fail "off: inhibitor released"
  else
    pass "off: inhibitor released"
  fi

  cmd_for 30s
  sleep 0.5
  if read_state && [ "$mode" = for ]; then
    pass "for: mode is for"
  else
    fail "for: mode is for"
  fi
  left=$((end - $(date +%s)))
  if [ "$left" -ge 25 ] && [ "$left" -le 31 ]; then
    pass "for 30s: end epoch lands in 25-31s"
  else
    fail "for 30s: end epoch lands in 25-31s (got $left)"
  fi
  cmd_off
  sleep 0.5

  if cmd_for banana 2>/dev/null; then
    fail "for: rejects unparseable timespan"
  else
    pass "for: rejects unparseable timespan"
  fi
  if active; then
    fail "for: rejected input starts no unit"
  else
    pass "for: rejected input starts no unit"
  fi

  if cmd_until banana 2>/dev/null; then
    fail "until: rejects unparseable time"
  else
    pass "until: rejects unparseable time"
  fi
  if active; then
    fail "until: rejected input starts no unit"
  else
    pass "until: rejected input starts no unit"
  fi

  cmd_until 23:59
  sleep 0.5
  if read_state && [ "$mode" = until ] && [ "$end" -gt "$(date +%s)" ]; then
    pass "until: end epoch is in the future"
  else
    fail "until: end epoch is in the future"
  fi
  cmd_off
  sleep 0.5

  sleep 5 &
  holdpid=$!
  cmd_while --pid "$holdpid"
  sleep 0.5
  if read_state && [ "$mode" = while ] && [ "$end" = 0 ]; then
    pass "while --pid: mode is while|0"
  else
    fail "while --pid: mode is while|0"
  fi
  kill "$holdpid" 2>/dev/null || true
  wait "$holdpid" 2>/dev/null || true
  sleep 1.5
  if active; then
    fail "while --pid: unit dies with the process"
  else
    pass "while --pid: unit dies with the process"
  fi

  # Reaped pid, guaranteed dead — beats guessing a large number.
  true &
  deadpid=$!
  wait "$deadpid" 2>/dev/null || true
  if cmd_while --pid "$deadpid" 2>/dev/null; then
    fail "while --pid: rejects a dead pid"
  else
    pass "while --pid: rejects a dead pid"
  fi

  cmd_while sleep 2
  # Poll: cmd_while no longer calls cmd_off, so the holder's own release
  # (~0.73s measured) is what we wait on. 4s ceiling.
  for _ in $(seq 1 20); do
    active || break
    sleep 0.2
  done
  if active; then
    fail "while <cmd>: releases when the command exits"
  else
    pass "while <cmd>: releases when the command exits"
  fi

  if [ "$(fmt_remaining 30)" = "<1m" ]; then pass "fmt: 30s"; else fail "fmt: 30s"; fi
  if [ "$(fmt_remaining 2520)" = "42m" ]; then pass "fmt: 2520s"; else fail "fmt: 2520s"; fi
  if [ "$(fmt_remaining 6120)" = "1h42m" ]; then pass "fmt: 6120s"; else fail "fmt: 6120s"; fi

  # 60 draws: an off-by-one in the modulo yields an empty summary now and then.
  blank=0
  for _ in $(seq 1 60); do
    [ -n "$(flavor on)" ] || blank=1
    [ -n "$(flavor off)" ] || blank=1
  done
  if [ "$blank" = 0 ]; then
    pass "flavor: 60 draws, never empty"
  else
    fail "flavor: 60 draws, never empty"
  fi

  cmd_off
  sleep 0.5
  if [ "$(cmd_waybar | jq -r .class)" = idle ]; then
    pass "waybar: idle class when off"
  else
    fail "waybar: idle class when off"
  fi
  if [ "$(cmd_waybar | jq -r .text)" = "$ICON_OFF" ]; then
    pass "waybar: hollow cup when off"
  else
    fail "waybar: hollow cup when off"
  fi

  cmd_for 1h
  sleep 0.5
  if [ "$(cmd_waybar | jq -r .class)" = active ]; then
    pass "waybar: active class when on"
  else
    fail "waybar: active class when on"
  fi
  if cmd_waybar | jq -e '.text | test("^\\S+ [0-9]+h?[0-9]*m$")' >/dev/null; then
    pass "waybar: timed text carries a countdown"
  else
    fail "waybar: timed text carries a countdown"
  fi
  if cmd_waybar | jq -e . >/dev/null; then
    pass "waybar: emits valid JSON"
  else
    fail "waybar: emits valid JSON"
  fi
  cmd_off
  sleep 0.5

  start while 0 'weird "quoted" label' sleep 5
  sleep 0.5
  if cmd_waybar | jq -e . >/dev/null; then
    pass "waybar: JSON survives quotes in the label"
  else
    fail "waybar: JSON survives quotes in the label"
  fi
  cmd_off
  sleep 0.5

  echo "$fails failure(s)"
  return $((fails > 0))
}

case "${1:-menu}" in
menu) menu ;;
on) cmd_on ;;
off) cmd_off ;;
toggle) cmd_toggle ;;
for)
  shift
  cmd_for "${1:-}"
  ;;
until)
  shift
  cmd_until "${1:-}"
  ;;
while)
  shift
  cmd_while "$@"
  ;;
status) cmd_status ;;
waybar) cmd_waybar ;;
_stopped) cmd_stopped ;;
selftest) selftest ;;
*)
  echo "usage: caffeine.sh {menu|on|off|toggle|for <span>|until <time>|while <cmd>|status|waybar|selftest}" >&2
  exit 2
  ;;
esac
