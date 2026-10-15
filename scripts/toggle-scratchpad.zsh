#!/usr/bin/env zsh

# Toggle one named Yabai scratchpad and repair the two intermittent states that
# a plain `window --toggle` cannot recover from: a hidden owning application or
# a lost Accessibility reference/rule assignment.

set -u

if (( $# != 3 )); then
    print -u2 "Usage: $0 <scratchpad-label> <application-name> <rule-label>"
    exit 2
fi

scratchpad_label=$1
application_name=$2
rule_label=$3
log_file=${YABAI_SCRATCHPAD_LOG:-${HOME:?HOME is not set}/Library/Logs/yabai-scratchpad.log}
toggle_lock_dir="/tmp/yabai-scratchpad-toggle-${UID}-${scratchpad_label}"
toggle_cooldown_file="/tmp/yabai-scratchpad-toggle-${UID}-${scratchpad_label}.last"
readonly toggle_cooldown_seconds=0.30

if ! command -v yabai >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    print -u2 "The scratchpad toggle requires yabai and jq."
    exit 1
fi

# skhd repeats held keys after roughly 0.25 seconds and then about every 0.08
# seconds with the current keyboard settings. Each ignored repeat refreshes the
# timestamp, while the short quiet period still permits a deliberate quick
# second press.
zmodload zsh/datetime
toggle_now=$EPOCHREALTIME

if [[ -d $toggle_lock_dir ]]; then
    lock_modified=$(stat -f '%m' "$toggle_lock_dir" 2>/dev/null || print 0)
    if [[ $lock_modified == <-> ]] && (( EPOCHSECONDS - lock_modified > 15 )); then
        rmdir "$toggle_lock_dir" 2>/dev/null || true
    fi
fi

if ! mkdir "$toggle_lock_dir" 2>/dev/null; then
    print -r -- "$toggle_now" >| "$toggle_cooldown_file" 2>/dev/null || true
    exit 0
fi
trap 'rmdir "$toggle_lock_dir" 2>/dev/null' EXIT INT TERM

previous_toggle=0
if [[ -r $toggle_cooldown_file ]]; then
    read -r previous_toggle < "$toggle_cooldown_file" || previous_toggle=0
fi
print -r -- "$toggle_now" >| "$toggle_cooldown_file" 2>/dev/null || true

if [[ $previous_toggle == <-> || $previous_toggle == <->.<-> ]] \
    && (( toggle_now - previous_toggle < toggle_cooldown_seconds )); then
    exit 0
fi

mkdir -p "${log_file:h}" 2>/dev/null || true
if [[ -f $log_file ]] && (( $(stat -f '%z' "$log_file" 2>/dev/null || print 0) > 1048576 )); then
    mv -f "$log_file" "$log_file.1" 2>/dev/null || true
fi

query_windows() {
    local windows
    windows=$(yabai -m query --windows 2>/dev/null) || windows='[]'
    print -r -- "$windows"
}

find_scratchpad() {
    jq -c --arg label "$scratchpad_label" \
        'first(.[] | select(.scratchpad == $label)) // empty'
}

describe_state() {
    local window_json=$1
    if [[ -z $window_json ]]; then
        print -r -- 'window=missing'
        return
    fi

    print -r -- "$window_json" | jq -r \
        '["window=" + (.id | tostring),
          "visible=" + (."is-visible" | tostring),
          "hidden=" + (."is-hidden" | tostring),
          "minimized=" + (."is-minimized" | tostring),
          "ax=" + (."has-ax-reference" | tostring),
          "role=" + .role,
          "subrole=" + .subrole] | join(" ")'
}

log_state() {
    local event=$1
    local window_json=$2
    local timestamp state
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    state=$(describe_state "$window_json")
    print -r -- "$timestamp label=$scratchpad_label event=$event $state" >> "$log_file" 2>/dev/null || true
}

activate_application() {
    /usr/bin/open -a "$application_name" >/dev/null 2>&1
}

wait_for_scratchpad() {
    local attempt windows window_json
    # A Yabai service restart returns before window discovery and rule loading
    # are necessarily complete. Allow that asynchronous startup to settle.
    for attempt in {1..50}; do
        windows=$(query_windows)
        window_json=$(print -r -- "$windows" | find_scratchpad)
        if [[ -n $window_json ]]; then
            sleep 0.2
            windows=$(query_windows)
            window_json=$(print -r -- "$windows" | find_scratchpad)
            if [[ -n $window_json ]]; then
                print -r -- "$window_json"
                return 0
            fi
        fi
        sleep 0.1
    done
    return 1
}

windows=$(query_windows)
window_json=$(print -r -- "$windows" | find_scratchpad)
log_state before "$window_json"

# A visible scratchpad only needs Yabai's normal order-out path. No application
# hide command is used, so auxiliary windows such as the Codex pet stay visible.
if [[ -n $window_json ]] && [[ $(print -r -- "$window_json" | jq -r '."is-visible"') == true ]]; then
    window_id=$(print -r -- "$window_json" | jq -r '.id')
    if yabai -m window --toggle "$scratchpad_label" >/dev/null 2>&1; then
        for attempt in {1..20}; do
            sleep 0.05
            window_json=$(query_windows | find_scratchpad)
            if [[ -z $window_json ]] || [[ $(print -r -- "$window_json" | jq -r '."is-visible"') != true ]]; then
                log_state hidden "$window_json"
                exit 0
            fi
        done

        # ChatGPT occasionally acknowledges the scratchpad order-out request
        # without actually hiding its standard window. Minimize only that
        # window as a final fallback, leaving the rest of the app untouched.
        if [[ $application_name == ChatGPT ]] \
            && yabai -m window "$window_id" --minimize >/dev/null 2>&1; then
            for attempt in {1..20}; do
                sleep 0.05
                window_json=$(query_windows | find_scratchpad)
                if [[ -z $window_json ]] \
                    || [[ $(print -r -- "$window_json" | jq -r '."is-visible"') != true ]] \
                    || [[ $(print -r -- "$window_json" | jq -r '."is-minimized"') == true ]]; then
                    log_state hidden-minimized "$window_json"
                    exit 0
                fi
            done
        fi

        window_json=$(query_windows | find_scratchpad)
        log_state hide-unverified "$window_json"
        exit 1
    fi

    log_state hide-failed "$window_json"
    exit 1
fi

# If Yabai lost the scratchpad assignment, activate/open the application and
# reapply only its existing named rule. Newly launched windows normally receive
# the rule automatically; --apply handles already-open recovered windows.
if [[ -z $window_json ]]; then
    log_state recovering-missing-window "$window_json"
    activate_application || true
    sleep 0.2
    yabai -m rule --apply "$rule_label" >/dev/null 2>&1 || true
    window_json=$(wait_for_scratchpad) || window_json=''

    if [[ -z $window_json ]]; then
        log_state recovery-failed "$window_json"
        exit 1
    fi

    # Activation may already have made the newly recovered window visible.
    if [[ $(print -r -- "$window_json" | jq -r '."is-visible"') == true ]]; then
        window_id=$(print -r -- "$window_json" | jq -r '.id')
        yabai -m window "$window_id" --focus >/dev/null 2>&1 || true
        log_state recovered-visible "$window_json"
        exit 0
    fi
fi

# A ChatGPT hide fallback may have minimized the scratchpad window. Focusing a
# minimized Yabai window restores it directly, without toggling it hidden again.
if [[ -n $window_json ]] && [[ $(print -r -- "$window_json" | jq -r '."is-minimized"') == true ]]; then
    window_id=$(print -r -- "$window_json" | jq -r '.id')
    yabai -m window "$window_id" --focus >/dev/null 2>&1 || true

    for attempt in {1..20}; do
        sleep 0.05
        window_json=$(query_windows | find_scratchpad)
        [[ -n $window_json ]] || continue
        if [[ $(print -r -- "$window_json" | jq -r '."is-visible"') == true ]] \
            && [[ $(print -r -- "$window_json" | jq -r '."is-minimized"') != true ]]; then
            log_state shown-from-minimized "$window_json"
            exit 0
        fi
    done
fi

# Yabai orders the window onto the active space first. Native application
# activation then supplies the same unhide/frontmost transition as a Dock click
# and refreshes a stale Accessibility reference when macOS permits it.
if ! yabai -m window --toggle "$scratchpad_label" >/dev/null 2>&1; then
    log_state show-toggle-failed "$window_json"
    activate_application || true
    sleep 0.2
    yabai -m rule --apply "$rule_label" >/dev/null 2>&1 || true
    yabai -m window --toggle "$scratchpad_label" >/dev/null 2>&1 || true
fi

activate_application || true

for attempt in {1..20}; do
    sleep 0.05
    window_json=$(query_windows | find_scratchpad)
    [[ -n $window_json ]] || continue

    if [[ $(print -r -- "$window_json" | jq -r '."is-visible"') == true ]]; then
        window_id=$(print -r -- "$window_json" | jq -r '.id')
        yabai -m window "$window_id" --focus >/dev/null 2>&1 || true
        window_json=$(query_windows | find_scratchpad)
        log_state shown "$window_json"
        exit 0
    fi
done

log_state show-failed "$window_json"
exit 1
