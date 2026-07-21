# rdp-connect

RDP connection framework for Hyprland/Wayland built on `xfreerdp3`.

## What it does

- **Profile-based connections**: each server is an `.env` file under `~/.config/rdp/profiles/`
- **Graphical selector**: `wofi`/`rofi` menu when invoked without args
- **Hyprland integration**: auto workspaces, window rules, multi-monitor, HiDPI scaling
- **Security**: safe env parser (no `source`), password piped via stdin (hidden from `ps aux`), `flock` single-instance guard
- **Pre-flight checks**: TCP socket probe on port 3389 before launching
- **i18n**: Spanish/English message dictionaries, auto-detected from `$LANG`
- **Auditing**: per-profile logs under `~/.local/state/rdp/`

## Install

```bash
./install-rdp-framework.sh
```

Then edit `~/.config/rdp/profiles/<name>.env` to set real credentials.

## Usage

| Command | Function |
|---|---|
| `rdp-connect` | Open graphical selector (wofi/rofi) |
| `rdp-connect <profile>` | Direct connection to a profile |
| `rdp-connect --new <name>` | Create a new profile from template |
| `rdp-connect --log <profile>` | Tail the profile's audit log |

## Status

Baseline. Hardening, testing, and refactoring pending — see SDD planning artifacts.
