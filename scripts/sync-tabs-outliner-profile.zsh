#!/usr/bin/env zsh

set -u

readonly YABAI_BIN="/opt/homebrew/bin/yabai"
readonly JQ_BIN="/opt/homebrew/bin/jq"
readonly LOCK_DIR="/tmp/tabs-outliner-profile-sync-${UID}"
readonly LOG_FILE="$HOME/Library/Logs/tabs-outliner-profile-sync.log"

source_window_id="${1:-${YABAI_WINDOW_ID:-}}"
mode="${2:-}"

[[ -x "$YABAI_BIN" && -x "$JQ_BIN" && -n "$source_window_id" ]] || exit 0

# Serialize updates, but never drop the final focus event during a busy update.
# Re-read the source after acquiring the lock so queued stale events do nothing.
if [[ "$mode" != "--dry-run" ]]; then
  if [[ -d "$LOCK_DIR" ]]; then
    lock_modified="$(stat -f %m "$LOCK_DIR" 2>/dev/null || printf '0')"
    current_epoch="$(date +%s)"
    if [[ "$lock_modified" == <-> ]] && (( current_epoch - lock_modified > 5 )); then
      rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
  acquired=false
  for _ in {1..200}; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      acquired=true
      break
    fi
    sleep 0.01
  done
  [[ "$acquired" == true ]] || exit 0
  trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM
fi

source_window_json="$($YABAI_BIN -m query --windows --window "$source_window_id" 2>/dev/null)" || exit 0
source_app="$(printf '%s' "$source_window_json" | "$JQ_BIN" -r '.app // ""')"
source_title="$(printf '%s' "$source_window_json" | "$JQ_BIN" -r '.title // ""')"
source_space="$(printf '%s' "$source_window_json" | "$JQ_BIN" -r '.space // 0')"
source_display="$(printf '%s' "$source_window_json" | "$JQ_BIN" -r '.display // 0')"

# Focus signals may arrive after the user has already selected another window.
if [[ -z "$mode" ]]; then
  [[ "$(printf '%s' "$source_window_json" | "$JQ_BIN" -r '.["has-focus"]')" == true ]] || exit 0
fi

[[ "$source_app" == "Brave Browser Beta" ]] || exit 0
[[ "$source_title" == *" - Brave Beta - "* ]] || exit 0

# Outliners belong to their home desktop, never to transient browser Spaces.
home_space="$($YABAI_BIN -m query --spaces | "$JQ_BIN" -r '.[] | select(.label == "tabs-outliner-home") | .index')"
[[ -n "$home_space" && "$source_space" == "$home_space" ]] || exit 0

case "$source_title" in
  *" - Brave Beta - Work") profile_label="Work" ;;
  *" - Brave Beta - Personal") profile_label="Personal" ;;
  *) exit 0 ;;
esac

target_window_match="$($YABAI_BIN -m query --windows 2>/dev/null | "$JQ_BIN" -r \
  --arg profile "$profile_label" \
  --argjson source_space "$source_space" \
  --argjson source_display "$source_display" \
  '[.[] | select(
      .app == "Brave Browser Beta"
      and (.title | test("^Tabs Outliner( · (Work|Personal))?( - (Work|Personal))?$"))
      and (.title | endswith($profile))
    )]
    | sort_by([.display != $source_display, .space != $source_space])
    | .[0]
    | if . then [.id, .space, .display] | @tsv else empty end')"

IFS=$'\t' read -r target_window_id target_space target_display <<< "$target_window_match"
[[ -n "$target_window_id" && -n "$target_space" && -n "$target_display" ]] || exit 0

if [[ "$mode" == "--dry-run" ]]; then
  if [[ "$target_display" != "$source_display" ]]; then
    action="ignore-other-display"
  elif [[ "$target_space" == "$source_space" ]]; then
    action="select"
  else
    action="move-and-select"
  fi
  printf 'profile=%s source=%s source_display=%s source_space=%s target=%s target_display=%s target_space=%s action=%s\n' \
    "$profile_label" "$source_window_id" "$source_display" "$source_space" \
    "$target_window_id" "$target_display" "$target_space" "$action"
  exit 0
fi

[[ "$target_display" != "$source_display" ]] && exit 0


[[ "$target_space" == "$home_space" ]] || exit 0

[[ "$mode" == "--relocate-only" ]] && exit 0

current_source_state="$($YABAI_BIN -m query --windows --window "$source_window_id" 2>/dev/null | "$JQ_BIN" -r '[.space, .["has-focus"]] | @tsv')" || exit 0
IFS=$'\t' read -r current_source_space source_has_focus <<< "$current_source_state"
[[ "$current_source_space" == "$source_space" && "$source_has_focus" == "true" ]] || exit 0

# Raise the matching stack member without stealing keyboard focus. Focusing it
# and restoring the browser both races user input and emits another focus signal.
$YABAI_BIN -m window "$target_window_id" --raise 2>/dev/null || exit 0
printf '%s profile=%s source=%s target=%s space=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$profile_label" "$source_window_id" \
  "$target_window_id" "$source_space" >> "$LOG_FILE" 2>/dev/null || true
