# niri-session Specification

## Purpose

Niri as the autologin session compositor on Omarchy 3.8.3 with Hyprland-equivalent look, function, and one-line rollback. Verification is manual — `niri validate` plus a live-session checklist; repo bats tests prove nothing here.

## Requirements

### Requirement: Session Switch and Rollback

The autologin Session line SHALL switch to niri only after `niri validate` passes and a timestamped backup of autologin.conf exists. Rollback MUST work via three tiers: backup restore, `session-toggle`, TTY `sudo sed`.

#### Scenario: Switch lands in Niri
- GIVEN validate passes and a backup exists
- WHEN Session switches to niri, then reboot
- THEN autologin starts the niri session

#### Scenario: Validation gate
- WHEN the staged config fails `niri validate`
- THEN no switch happens and the failure is reported

#### Scenario: Rollback tiers
- GIVEN Session=niri
- WHEN the backup is restored, `session-toggle` runs, or TTY `sudo sed` sets hyprland, then reboot
- THEN autologin starts Hyprland

### Requirement: Session Toggle Script

`session-toggle` MUST read the current `Session=`, flip niri↔hyprland atomically (temp file + `mv`), print the result, fail loudly on sudo denial, and change nothing else.

#### Scenario: Flip both directions
- GIVEN Session=niri (or hyprland)
- WHEN `session-toggle` runs
- THEN the value flips, the result is printed, and no other line differs

#### Scenario: No partial writes
- GIVEN a toggle write in progress
- WHEN the process dies mid-write (kill, power loss)
- THEN autologin.conf holds complete old or new content, never partial

#### Scenario: Loud sudo failure
- GIVEN sudo is denied
- WHEN `session-toggle` runs
- THEN non-zero exit, clear error, file unchanged

### Requirement: Autostart Stack

The niri session MUST spawn the Omarchy stack (waybar, walker, mako, swayosd, swaybg) and MUST NOT spawn noctalia; the package stays installed, inert.

#### Scenario: Stack spawns, noctalia inert
- WHEN a niri session starts
- THEN waybar, walker, mako, swayosd, swaybg run AND no noctalia process exists AND `pacman -Q noctalia` still reports installed

### Requirement: Look and Feel Parity

Niri MUST match Omarchy gaps, borders, radii, and opacities, use idiomatic scrollable tiling, and port every windows.conf rule to rules.kdl.

#### Scenario: Visual parity
- WHEN niri is compared to the Hyprland reference
- THEN gaps, borders, radii, opacities match AND tiling follows niri's scrollable column idiom

#### Scenario: Window rules ported
- WHEN windows.conf rules are enumerated against rules.kdl
- THEN every rule has a niri equivalent — none dropped

### Requirement: Bindings and Scratchpads

Keybinds MUST pair niri's navigation core with the user's app/scratchpad binds; the 7 special workspaces MUST become output-pinned named workspaces with window-class routing.

#### Scenario: Hybrid binds
- WHEN navigation keys and user binds (launcher, menus, terminal, rdp-connect) fire
- THEN each performs its Hyprland-equivalent action

#### Scenario: Pinned scratchpads
- WHEN a routed class (WhatsApp, Claude, …) opens or a toggle bind fires
- THEN it lands on / focuses its named workspace on the pinned output

### Requirement: Idle and Lock

swayidle MUST match the exact hypridle timings, including lock-before-suspend; swaylock-effects MUST be aether-themed; the tte screensaver is dropped.

#### Scenario: Idle timeline
- GIVEN an idle session
- WHEN the hypridle-equivalent thresholds pass
- THEN the aether-themed swaylock engages at the same moments

#### Scenario: Lock before suspend
- WHEN the system suspends
- THEN the screen locks before sleep begins

### Requirement: Theming Integration

niri.kdl colors MUST render from the active theme's colors.toml via `~/.config/omarchy/themed/*.tpl`; `omarchy theme set` MUST re-render niri.kdl; menu/refresh integration is documented best-effort.

#### Scenario: Theme set re-renders
- WHEN `omarchy theme set <name>` runs
- THEN niri.kdl regenerates with that theme's colors AND menu/refresh limits are documented, not assumed

### Requirement: Helper Parity

Niri equivalents for monitor toggles, capture, zoom, hyprcaffeine, and monitor-watch MUST be user-space wrappers in `~/.local/bin/`, never shadowing omarchy binaries; known unknowns get documented shortfalls, never silent assumptions.

#### Scenario: Wrappers without shadowing
- WHEN a wrapper (e.g. capture) runs under niri
- THEN it works via niri-native facilities AND omarchy binaries still resolve first for their own names

#### Scenario: Shortfall documented
- WHEN no niri equivalent exists (e.g. cursor zoom)
- THEN the shortfall is recorded with status in docs

### Requirement: Hardware

VRR MUST be ported; tearing and colord (`cm, srgb`) MUST be documented as NOT ported (A16, tearing amended 2026-08-18: niri 26.04 lacks tearing support — user-ratified shortfall; re-evaluate on niri upgrade).

#### Scenario: VRR live
- WHEN output state is queried in session
- THEN VRR is active on the ASUS display, matching Hyprland

#### Scenario: Tearing not ported
- WHEN hardware docs are reviewed
- THEN tearing is listed as not ported with a re-evaluate-on-niri-upgrade note

#### Scenario: Colord not ported
- WHEN hardware docs are reviewed
- THEN colord CMS is listed as not ported

### Requirement: Screencast

Screen sharing MUST work under niri via xdg-desktop-portal-gnome and PipeWire.

#### Scenario: Live screen share
- WHEN a share is started from an app in the niri session
- THEN the portal picker appears and the stream is live

### Requirement: Input, Environment, and Displays

latam layout with compose:caps, GDK_SCALE=2, and all 3 monitors (2× Dell U2417H 1920x1080@60, ASUS XG27ACS 2560x1440@60, Hyprland positions, scale 1) MUST be configured.

#### Scenario: Keyboard and scale
- WHEN a niri session starts
- THEN layout is latam, Compose on Caps Lock, GDK_SCALE=2 set

#### Scenario: Monitors match inventory
- WHEN display.kdl is compared to the Hyprland inventory
- THEN all 3 outputs match mode, position, and scale

### Requirement: Safety Invariants

`niri validate` MUST gate every config change before any session switch; `~/.local/share/omarchy/` MUST NOT be modified; `~/.config/hypr/` MUST stay frozen; `~/.config/niri/` rewrites MUST be backup-first.

#### Scenario: Frozen trees
- WHEN the change completes
- THEN `~/.local/share/omarchy/` and `~/.config/hypr/` are byte-identical to pre-change state

#### Scenario: Backup before rewrite
- WHEN `~/.config/niri/**` is rewritten
- THEN a timestamped backup of the prior tree exists first
