#!/usr/bin/env python3
"""Small structural checks for this repository's skhd configuration."""

from __future__ import annotations

import re
import sys
from pathlib import Path


def logical_lines(text: str) -> list[str]:
    lines: list[str] = []
    pending = ""
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if pending:
            pending += " " + stripped
        else:
            pending = stripped
        if pending.endswith("\\"):
            pending = pending[:-1].rstrip()
            continue
        lines.append(pending)
        pending = ""
    if pending:
        lines.append(pending)
    return lines


def normalize_hotkey(value: str) -> str:
    value = re.sub(r"\s+", " ", value.strip().lower())
    if "-" not in value:
        return value
    modifiers, key = value.rsplit("-", 1)
    parts = sorted(part.strip() for part in modifiers.split("+") if part.strip())
    return "+".join(parts) + "-" + key.strip()


def parse_bindings(text: str, *, reject_duplicates: bool = True) -> dict[str, str]:
    bindings: dict[str, str] = {}
    app_block = False
    duplicates: list[str] = []

    for line in logical_lines(text):
        if app_block:
            if line == "]":
                app_block = False
            continue

        if line.endswith("["):
            hotkey = normalize_hotkey(line[:-1])
            command = "application map"
            app_block = True
        elif ":" in line:
            raw_hotkey, command = line.split(":", 1)
            hotkey = normalize_hotkey(raw_hotkey)
            command = command.strip()
        else:
            continue

        if hotkey in bindings:
            duplicates.append(hotkey)
        else:
            bindings[hotkey] = command

    if duplicates and reject_duplicates:
        raise ValueError("duplicate hotkey(s): " + ", ".join(sorted(set(duplicates))))
    if app_block:
        raise ValueError("unterminated application map")
    return bindings


def require_core_layers(bindings: dict[str, str]) -> None:
    directions = {
        "i": "north",
        "j": "west",
        "k": "south",
        "l": "east",
    }
    layers = {
        "alt": "--focus",
        "alt+shift": "--warp",
        "alt+lctrl": "--resize",
        "meh": "--stack",
        "hyper": "--insert",
    }
    resize_edges = {
        "i": "top",
        "j": "left",
        "k": "bottom",
        "l": "right",
    }
    errors: list[str] = []

    for modifiers, action in layers.items():
        for key, direction in directions.items():
            hotkey = normalize_hotkey(f"{modifiers} - {key}")
            command = bindings.get(hotkey)
            if command is None:
                errors.append(f"missing {hotkey}")
                continue
            target = resize_edges[key] if action == "--resize" else direction
            if action not in command or target not in command:
                errors.append(f"unexpected command for {hotkey}: {command}")

    if errors:
        raise ValueError("core layer check failed:\n  " + "\n  ".join(errors))


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else ".skhdrc")
    try:
        bindings = parse_bindings(path.read_text(encoding="utf-8"))
        require_core_layers(bindings)
    except (OSError, ValueError) as error:
        print(f"skhd check failed: {error}", file=sys.stderr)
        return 1

    print(f"skhd check passed: {len(bindings)} unique hotkeys; all I/J/K/L layers present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
