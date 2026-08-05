# macOS window-manager dotfiles

My keyboard-first setup for [Yabai](https://github.com/asmvik/yabai), [skhd](https://github.com/asmvik/skhd), and [JankyBorders](https://github.com/FelixKratz/JankyBorders).

The idea is simple: the right hand stays on an inverted-T **I/J/K/L** cluster, like a right-handed WASD. The direction never changes; modifiers change the verb.

![Keyboard shortcut map](assets/shortcut-map.svg)

## The spatial language

| Layer | I / J / K / L does |
| --- | --- |
| `Option` | Focus north / west / south / east |
| `Shift + Option` | Move the window in that direction |
| `Control + Option` | Resize that edge by 75 px |
| `Meh` | Stack with the neighbor in that direction |
| `Hyper` | Choose where the next window is inserted |

`Meh` means `Control + Option + Shift`. `Hyper` adds `Command`.

## Spaces

The number row uses physical keycodes, so it keeps working when I change keyboard layouts.

| Shortcut | Action |
| --- | --- |
| `Option + 1…9` | Focus space 1…9 |
| `Option + 0` | Focus the last space |
| `Fn + 1…9` | Alternate way to focus space 1…9 |
| `Fn + Option + 1…0` | Focus space 10…19 |
| `Shift + Option + 1…9` | Send the focused window to space 1…9 |
| `Shift + Option + 0` | Send the window to the last space |
| `Meh + 1…0` | Move the current space to position 1…10 |
| `Option + N / M` | Focus the previous / next space |
| `Shift + Option + N / M` | Send the window to the previous / next space |
| `Shift + Option + = / -` | Create / destroy a space |

There are a few deliberate aliases in [.skhdrc](.skhdrc) for whichever keys are easiest to reach at the time.

## Other useful bindings

| Shortcut | Action |
| --- | --- |
| `Option + U / O` | Next / previous window in a stack |
| `Shift + Option + Space` | Toggle floating |
| `Option + F` | Toggle Yabai zoom |
| `Shift + Option + F` | Toggle native full screen |
| `Hyper + B / U` | Set the space to BSP / floating layout |
| `Command + Option + S` | Toggle the Spotify scratchpad |
| `Control + Z / X / C / V` | Previous tab / next tab / close tab / new tab in supported browsers |
| `Option + D` | Open [Homerow](https://www.homerow.app/) |

The Yabai file also defines floating rules for utility windows and scratchpads for Spotify, Telegram, Gemini, and MacTube. Delete or adapt those app-specific rules freely.

## Install

1. Read Yabai's [installation](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29) and [scripting-addition](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection) instructions first. Several bindings here need the scripting addition and a compatible SIP configuration.
2. Review the four third-party Homebrew projects linked in this README, then explicitly trust their formulae. This is intentionally not automated:

   ```sh
   brew trust --formula asmvik/formulae/yabai
   brew trust --formula asmvik/formulae/skhd
   brew trust --formula felixkratz/formulae/borders
   brew trust --formula laishulu/macism/macism
   ```

3. Install the command-line dependencies:

   ```sh
   brew bundle
   ```

4. Preview what the installer will change:

   ```sh
   ./scripts/install.sh --dry-run
   ```

5. Install the files and reload the services:

   ```sh
   ./scripts/install.sh
   ```

The installer saves the previous files under `~/.dotfiles-backups/` before replacing them. It does not install or change Yabai's scripting-addition/SIP setup.

## Optional integrations

- [`jq`](https://jqlang.github.io/jq/) is used to look up space numbers.
- [`macism`](https://github.com/laishulu/macism) gates two phonetic keyboard-layout helpers.
- [Homerow](https://www.homerow.app/) provides keyboard-driven clicking.
- My [Barik fork](https://github.com/jerechinsky/barik) shows space/window feedback. The `notifyutil` messages are harmless when Barik is not installed; remove them if you prefer.

## Validation

Run:

```sh
./scripts/validate.sh
```

It checks the shell syntax, duplicate skhd bindings, the core I/J/K/L layers, the SVG, accidental home-directory paths, and whitespace errors.

Tested on macOS 15.7.7 (Apple Silicon) with Yabai 7.1.24, skhd 0.3.9, and JankyBorders 1.8.4. App names and security requirements can change between macOS versions.

## What is deliberately not here

This repository contains active window-management configuration only. Old disabled experiments, machine-specific paths, and personal application data are excluded. Machine-specific Barik configuration is not duplicated here; Barik documents its own settings.

## License

[MIT](LICENSE). Yabai, skhd, JankyBorders, macism, Homerow, and Barik are separate projects with their own authors and licenses.
