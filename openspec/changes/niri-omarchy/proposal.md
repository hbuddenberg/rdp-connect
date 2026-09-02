# Proposal: niri-omarchy — Niri session, Omarchy parity

`niri-omarchy` | propose rev 2 | 2026-08-18 | Input: `exploration.md` (recommends Approach 1). Encodes all 21 user-ratified assumptions (A1–A21); none re-opened.

## Intent

Niri as session compositor on Omarchy 3.8.3 with full look & functional parity to current Hyprland; autologin lands in Niri, rollback trivial. System-config change — the rdp-connect repo is artifact anchor only.

## Scope

### In Scope
- Switch `Session=omarchy`→`Session=niri` (`/etc/sddm.conf.d/autologin.conf`), timestamped backup first (A1).
- `~/.local/bin/session-toggle` (A21): sudo; reads current `Session=`, flips niri↔hyprland atomically (temp+`mv`), prints result, fails loudly. File-level only; no detection/logout/reboot/runtime switch.
- Rewrite `~/.config/niri/**` (backup first, A4): Omarchy autostart — waybar/walker/mako/swayosd/swaybg (A5); noctalia spawn/binds removed, kept installed (A6).
- Omarchy gaps/borders/radii/opacities (A7); idiomatic scrollable tiling (A11); ALL windows.conf rules→rules.kdl (A14).
- Niri navigation core + user app/scratchpad binds (A12); 7 specials → output-pinned named workspaces + class routing (A10).
- swayidle, exact hypridle timings + lock-before-suspend (A18); swaylock-effects themed aether (A8); tte screensaver dropped. Install swayidle/swaylock-effects/wlsunset — sudo.
- `niri.kdl` from colors.toml via `themed/*.tpl` + theme-set hook (A9); `theme set` functional, menu best-effort (A19).
- Niri equivalents, ALL hyprctl helpers: monitor toggles, capture, zoom, hyprcaffeine, monitor-watch (A15).
- VRR/tearing ported; `cm srgb` documented NOT ported (A16); monitors/env (latam, GDK_SCALE).
- Screencast verified: portal-gnome + pipewire (A17); separate niri-module waybar config, explicit path (A13).

### Out of Scope
- `~/.config/hypr/**` frozen — fallback only, zero dual maintenance (A2).
- rdp-connect code/tests/specs (follow-up below).
- `~/.local/share/omarchy/**` (read-only); noctalia uninstall (A6); SDDM greeter; uwsm desktop (stock niri-session suffices).

## Capabilities

### New Capabilities
- `niri-session`: Niri session on Omarchy — switch/rollback/toggle-script, autostart, look&feel, bindings/scratchpads, idle/lock, theming, helpers, screencast.

### Modified Capabilities
- None — existing specs are rdp-connect engine capabilities, untouched.

## Approach

Incremental: switch proof → autostart → bindings/scratchpads → idle/lock after installs → theme ride-along → live checklist. `niri validate` gates every switch; user-space wrappers + rebinds, never PATH-shadowing omarchy binaries.

## Affected Areas

|Area|Impact|
|---|---|
|`/etc/sddm.conf.d/autologin.conf`|modified — one line + backup|
|`~/.config/niri/**`|rewritten — noctalia → Omarchy parity|
|`~/.config/waybar/` niri variant|new|
|`~/.config/omarchy/themed/*.tpl`, `hooks/theme-set`|new/modified|
|`~/.local/bin/` wrappers + `session-toggle`|new|
|swayidle, swaylock-effects, wlsunset (+portal?)|installed|

## Risks

|Risk|Sev|Mitigation|
|---|---|---|
|Autologin lockout into broken session|High|validate pre-switch; greeter fallback; TTY rollback; backups|
|Unknowns: niri zoom (A15), portal presence (A17)|Med|probe at apply; document shortfall|
|Scratchpad emulation partial (no overlay)|Med|accepted (A10); pinned workspaces + routing|
|Noctalia double-spawn conflicts|Med|atomic rewrite drops spawn/binds|
|Tasks likely exceed 400-line budget|High|forecast only; slicing at sdd-tasks (ask-on-risk)|

## Rollback Plan

Restore timestamped backup → `Session=hyprland` (A1), reboot; optionally restore niri backup. Routine flips: `session-toggle` (A21). Emergency TTY: Ctrl+Alt+F2 + `sudo sed`. Hyprland tree untouched → one-line rollback. No password-path/stdin/`parse_env_safe` exposure — repo untouched.

## Dependencies

sudo (installs + autologin edit); `themed/*.tpl` extension point (verified); niri 26.04 + waybar 0.15 niri modules (present).

## Success Criteria

- [ ] Live-session checklist green (A3) — manual; bats proves nothing
- [ ] `niri validate` pre-switch; autologin lands in Niri
- [ ] Stack + 7 scratchpads work; `theme set` re-renders `niri.kdl`
- [ ] Idle timings exact; lock-before-suspend proven; screencast live
- [ ] Rollback tested, trivial
- [ ] `session-toggle` flips niri↔hyprland correctly from both states

## Follow-up (A20)

Chained next SDD change (this repo): compositor-aware rdp-connect — `hyprctl` on Hyprland / `niri msg` on Niri, FULL parity (preferred workspace, monitors, DPI) + fallback when neither present. Not started here.
