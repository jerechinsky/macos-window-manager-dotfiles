#!/usr/bin/env zsh

set -u

if (( $# != 1 )) || [[ "$1" != "prev" && "$1" != "next" ]]; then
    print -u2 "Usage: $0 <prev|next>"
    exit 2
fi

readonly direction=$1
readonly yabai_bin="/opt/homebrew/bin/yabai"
readonly notify_bin="/usr/bin/notifyutil"
readonly lock_dir="/tmp/yabai-stack-cycle-${UID}"
readonly cooldown_file="/tmp/yabai-stack-cycle-${UID}.last"
readonly cooldown_seconds=0.20

[[ -x "$yabai_bin" ]] || exit 1

# Bound rapid repeats without turning the guard into a sliding lockout. Ignored
# events leave the last accepted timestamp unchanged, so quick deliberate
# presses continue cycling once the short guard interval has elapsed.
zmodload zsh/datetime
cycle_now=$EPOCHREALTIME

if [[ -d "$lock_dir" ]]; then
    lock_modified="$(stat -f '%m' "$lock_dir" 2>/dev/null || print 0)"
    if [[ "$lock_modified" == <-> ]] && (( EPOCHSECONDS - lock_modified > 5 )); then
        rmdir "$lock_dir" 2>/dev/null || true
    fi
fi

if ! mkdir "$lock_dir" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$lock_dir" 2>/dev/null' EXIT INT TERM

previous_cycle=0
if [[ -r "$cooldown_file" ]]; then
    read -r previous_cycle < "$cooldown_file" || previous_cycle=0
fi
if [[ "$previous_cycle" == <-> || "$previous_cycle" == <->.<-> ]] \
    && (( cycle_now - previous_cycle < cooldown_seconds )); then
    exit 0
fi
print -r -- "$cycle_now" >| "$cooldown_file" 2>/dev/null || true

if [[ "$direction" == "prev" ]]; then
    "$yabai_bin" -m window --focus stack.prev 2>/dev/null \
        || "$yabai_bin" -m window --focus stack.last 2>/dev/null \
        || exit 0
else
    "$yabai_bin" -m window --focus stack.next 2>/dev/null \
        || "$yabai_bin" -m window --focus stack.first 2>/dev/null \
        || exit 0
fi

"$yabai_bin" -m window --opacity 1.0 2>/dev/null || true
"$notify_bin" -p com.barik.window_changed 2>/dev/null || true
