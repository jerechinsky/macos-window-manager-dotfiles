#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h}
cd "$repo_root"

zsh -n .yabairc
zsh -n .config/borders/bordersrc
python3 scripts/check_skhd.py .skhdrc
xmllint --noout assets/shortcut-map.svg

if rg -n '/Users/|100\.[0-9]+\.[0-9]+\.[0-9]+' \
    --glob '!scripts/validate.sh' \
    .yabairc .skhdrc .config README.md Brewfile scripts assets; then
    print -u2 "Validation failed: a machine-specific home path or private IP was found."
    exit 1
fi

if rg -n '[[:blank:]]+$' \
    .yabairc .skhdrc .config README.md Brewfile scripts assets; then
    print -u2 "Validation failed: trailing whitespace was found."
    exit 1
fi

print "Validation passed."
