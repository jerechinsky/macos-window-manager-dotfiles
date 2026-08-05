#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h}
user_home=${HOME:?HOME is not set}
dry_run=0

if [[ ${1:-} == "--dry-run" ]]; then
    dry_run=1
elif [[ $# -gt 0 ]]; then
    print -u2 "Usage: $0 [--dry-run]"
    exit 2
fi

sources=(
    "$repo_root/.yabairc"
    "$repo_root/.skhdrc"
    "$repo_root/.config/borders/bordersrc"
)
destinations=(
    "$user_home/.yabairc"
    "$user_home/.skhdrc"
    "$user_home/.config/borders/bordersrc"
)
modes=(0755 0644 0755)

print "Files to install:"
for index in {1..3}; do
    print "  ${sources[$index]} -> ${destinations[$index]}"
done

if (( dry_run )); then
    print "Dry run only; no files changed."
    exit 0
fi

"$repo_root/scripts/validate.sh"

timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$user_home/.dotfiles-backups/macos-window-manager-$timestamp"
mkdir -p "$backup_dir"

had_original=(0 0 0)
for index in {1..3}; do
    destination=${destinations[$index]}
    if [[ -e "$destination" ]]; then
        had_original[$index]=1
        cp -p "$destination" "$backup_dir/original-$index"
    fi
done

rollback() {
    print -u2 "Reload failed; restoring the previous configuration."
    for index in {1..3}; do
        destination=${destinations[$index]}
        if (( had_original[$index] )); then
            cp -p "$backup_dir/original-$index" "$destination"
        else
            rm -f "$destination"
        fi
    done
    command -v skhd >/dev/null && skhd --reload >/dev/null 2>&1 || true
    command -v yabai >/dev/null && yabai --restart-service >/dev/null 2>&1 || true
    command -v borders >/dev/null && zsh "$user_home/.config/borders/bordersrc" >/dev/null 2>&1 || true
}

trap rollback ZERR

for index in {1..3}; do
    destination=${destinations[$index]}
    mkdir -p "${destination:h}"
    temporary="${destination}.dotfiles-new.$$"
    install -m "${modes[$index]}" "${sources[$index]}" "$temporary"
    mv -f "$temporary" "$destination"
done

if command -v skhd >/dev/null; then
    skhd --reload
fi
if command -v yabai >/dev/null; then
    yabai --restart-service
fi
if command -v borders >/dev/null; then
    zsh "$user_home/.config/borders/bordersrc"
fi

trap - ZERR
print "Installed successfully. Backup: $backup_dir"
