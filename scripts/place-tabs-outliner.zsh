#!/usr/bin/env zsh
# Keep Outliners stacked in the narrow left column of the main display's first desktop.
set -eu
readonly Y=/opt/homebrew/bin/yabai
readonly J=/opt/homebrew/bin/jq
# Coalesce bursts into one worker and one trailing refresh. No waiting
# shell processes and no stale directory locks after a killed worker.
if [[ "${1:-}" != --reconcile ]]; then
    zmodload zsh/system
    readonly lock=/tmp/tabs-outliner-placement-${UID}.lock
    readonly pending=/tmp/tabs-outliner-placement-${UID}.pending
    : > "$pending"
    : >> "$lock"
    zsystem flock -t 0 -f lock_fd "$lock" 2>/dev/null || exit 0
    for attempt in {1..4}; do
        rm -f "$pending"
        "$0" --reconcile || true
        [[ -e "$pending" ]] || break
    done
    zsystem flock -u "$lock_fd"
    # Close the final-event race after releasing the lock. Another signal
    # can acquire it directly; otherwise this process drains the pending work.
    [[ ! -e "$pending" ]] || exec "$0"
    exit 0
fi
main=$($Y -m query --displays | $J -r '.[] | select(.frame.x == 0 and .frame.y == 0) | .index')
[[ -n "$main" ]] || exit 0
home_space=$($Y -m query --spaces | $J -r --argjson d "$main" '[.[] | select(.display == $d and ."is-native-fullscreen" == false)] | sort_by([.label != "tabs-outliner-home", .index]) | .[0].index // empty')
[[ -n "$home_space" ]] || exit 0
# macOS may expose stale AX frames on an inactive desktop. Reconcile when
# the user returns, rather than rearranging an invisible desktop on each switch.
$Y -m query --spaces --space "$home_space" | $J -e '."is-visible"' >/dev/null || exit 0
$Y -m space "$home_space" --label tabs-outliner-home
snapshot=$($Y -m query --windows)
# A disconnected TV can leave its player on the main desktop. Do not reshape
# that desktop until the player is moved away by the user.
if print -r -- "$snapshot" | $J -e --argjson s "$home_space" 'any(.[]; .space == $s and (.title | startswith("TV Player")))' >/dev/null; then
    exit 0
fi
ids=(${(f)"$(print -r -- "$snapshot" | $J -r --argjson s "$home_space" --argjson d "$main" '[.[] | select(.app == "Brave Browser Beta" and (.title | test("^Tabs Outliner( · (Work|Personal))?( - (Work|Personal))?$")) and .display == $d and ."is-minimized" == false and ."is-hidden" == false and ."is-native-fullscreen" == false and ."is-sticky" == false)] | sort_by([.space != $s, .frame.x]) | .[].id')"})
(( ${#ids} )) || exit 0
base=${ids[1]}
for wid in $ids; do
    state=$($Y -m query --windows --window "$wid")
    if [[ $(print -r -- "$state" | $J -r '.space') != "$home_space" ]]; then
        $Y -m window "$wid" --space "$home_space"
    fi
    if [[ $(print -r -- "$state" | $J -r '."is-floating"') == true ]]; then
        $Y -m window "$wid" --toggle float
    fi
done
# Only ordinary, already-managed Brave windows on this desktop participate.
# Floating utilities, other apps, other Spaces, and TV windows stay untouched.
snapshot=$($Y -m query --windows)
right_ids=(${(f)"$(print -r -- "$snapshot" | $J -r --argjson s "$home_space" '[.[] | select(.space == $s and .app == "Brave Browser Beta" and .role == "AXWindow" and .subrole == "AXStandardWindow" and (.title | test("^Tabs Outliner( · (Work|Personal))?( - (Work|Personal))?$") | not) and (.title | startswith("TV Player") | not) and ."is-floating" == false and ."is-minimized" == false and ."is-hidden" == false and ."is-sticky" == false and ."is-native-fullscreen" == false)] | sort_by(.id) | .[].id')"})

same_stack() {
    $Y -m query --windows | $J -e --argjson b "$1" --argjson w "$2" '
        (.[] | select(.id == $b)) as $b | (.[] | select(.id == $w)) as $w |
        ($b.frame == $w.frame and $b."stack-index" > 0 and $w."stack-index" > 0)' >/dev/null
}

anchor=${right_ids[1]:-}
if [[ -n "$anchor" ]]; then
    # yabai refuses warp between members of the same stack. Temporarily
    # detach this managed browser, then re-tile it beside the Outliner.
    if same_stack "$base" "$anchor"; then
        $Y -m window "$anchor" --toggle float
        $Y -m window "$base" --insert west
        if ! $Y -m window "$base" --insert east; then
            $Y -m window "$anchor" --toggle float
            exit 1
        fi
        $Y -m window "$anchor" --toggle float
    fi
    for wid in ${right_ids:1}; do
        same_stack "$anchor" "$wid" || $Y -m window "$anchor" --stack "$wid"
    done
    snapshot=$($Y -m query --windows)
    correct=$(print -r -- "$snapshot" | $J -r --argjson b "$base" --argjson a "$anchor" '
        (.[] | select(.id == $b)) as $b | (.[] | select(.id == $a)) as $a |
        ($b.frame.x < $a.frame.x and $b.frame.y == $a.frame.y and $b.frame.h == $a.frame.h)')
    if [[ "$correct" != true ]]; then
        $Y -m window "$anchor" --insert east
        $Y -m window "$anchor" --insert west
        if ! warp_error=$($Y -m window "$base" --warp "$anchor" 2>&1); then
            # AX geometry may still be stale during a large browser restore.
            # The manager's error is authoritative about stack membership.
            if [[ "$warp_error" != *"same stack"* ]]; then
                print -u2 -- "$warp_error"
                exit 1
            fi
            $Y -m window "$base" --toggle float
            $Y -m window "$anchor" --insert east
            $Y -m window "$anchor" --insert west
            $Y -m window "$base" --toggle float
        fi
    fi
fi
for wid in ${ids:1}; do
    same_stack "$base" "$wid" || $Y -m window "$base" --stack "$wid"
done
if [[ -n "$anchor" ]]; then
    # Avoid repeated resize commands when focus/title signals arrive.
    correct=$($Y -m query --windows | $J -r --argjson b "$base" --argjson a "$anchor" '
        (.[] | select(.id == $b)).frame as $b | (.[] | select(.id == $a)).frame as $a |
        (($b.w / ($a.x + $a.w - $b.x) - 0.23) | fabs) < 0.005')
    [[ "$correct" == true ]] || $Y -m window "$base" --ratio abs:0.23
fi

# Stacking can raise a different Outliner after the independent focus signal.
# Recheck the actual focused browser and restore its profile without focus theft.
focused=$($Y -m query --windows | $J -r '.[] | select(."has-focus" and .app == "Brave Browser Beta") | .id')
if [[ -n "$focused" && -x "$HOME/.config/yabai/sync-tabs-outliner-profile.zsh" ]]; then
    "$HOME/.config/yabai/sync-tabs-outliner-profile.zsh" "$focused"
fi
