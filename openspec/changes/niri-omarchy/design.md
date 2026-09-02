# Design: niri-omarchy — Niri session, Omarchy parity

## Technical Approach

Rewrite `~/.config/niri/` from noctalia-shell to Omarchy parity; Hyprland tree stays frozen as rollback. Verified facts: effective Hyprland = omarchy defaults → user files → `hyprland-gui.conf` (loads last, wins); `~/.config/omarchy/themed/*.tpl` renders into `current/theme/` on every `omarchy theme set`; portal-gnome 50.0 + `niri-portals.conf` already installed; niri 26.04 has `variable-refresh-rate` but **no tearing** (binary-audited). Assumes niri 26.04-1.1, waybar 0.15.0-2.1, omarchy 3.8.3.

## Architecture Decisions

| # | Decision | Choice (rejected → why) |
|---|---|---|
| D1 | Layout | Keep modular `config.kdl` + `cfg/*.kdl` (flat rejected: mirrors omarchy sourced-conf structure). `config.kdl` also includes `../../omarchy/current/theme/niri.kdl` — themed values live ONLY there; static ports in cfg/*. |
| D2 | display.kdl | Outputs matched by `make model serial` (stable vs DP-x). Dell#1 XVNNT6BTAPBL 1920x1080@60 @0x0; ASUS T6LMTF111342 2560x1440@60 @1920x0 `variable-refresh-rate true`; Dell#2 J75VK884B7ZL 1920x1080@60 @4480x0; scale 1. Named workspaces per-output (D6). `GDK_SCALE=2` in misc.kdl environment. `cm, srgb` documented NOT ported (A16). |
| D3 | input.kdl | `xkb { layout "latam"; options "compose:caps" }`, repeat 40/250, `numlock` on, mouse accel adaptive + 0.35 (effective Hyprland). DROP focus-follows-mouse, workspace-auto-back-and-forth, touchpad block (noctalia-template artifacts / no hardware). |
| D4 | Autostart | spawn-at-startup: mako; waybar gated by waybar-off, `-c ~/.config/waybar/config.niri.jsonc`; fcitx5; swaybg on current/background; polkit-gnome; swayosd-server (verified: no unit, no omarchy spawn); `swayidle -w`; input-remapper stop-all+autoload; gmail webapp; first-run/powerprofiles/post-boot hook. NOT ported: hypridle (→swayidle), hyprland-monitor-watch (→`niri-monitor-watch`), import-environment/dbus-update (niri-session does both), noctalia spawn (A6), wlsunset (on demand via `niri-nightlight`; hyprsunset currently off). |
| D5 | Look & feel | gaps 4 (in=out=4 → niri single `gaps` exact); border width 4, colors from tpl; `geometry-corner-radius 0` (omarchy rounding 0; noctalia's 20 dropped); `clip-to-geometry`; window-rule `opacity 0.97 0.9` (two-arg form checked by validate, single-value fallback); maximize-suppression ≈ `open-maximized false` (runtime-maximize residue → checklist); keep misc blur + `honor-xdg-activation-with-invalid-serial` (launcher focus ≈ focus_on_activate). `preset-column-widths 0.49 + 0.98`; Mod+Ctrl+F → `switch-preset-column-width` (replaces scroll-column-toggle.sh). |
| D6 | Scratchpads | 7 specials → per-output named workspaces + `open-on-workspace` routing (class lists = workspaces.conf verbatim): mensajeria→Dell#2, ai→Dell#1, musica→ASUS (+float), correo→ASUS, terminal→ASUS (ghostty float 1400x800), silencio+scratchpad unpinned. Mod+M/A/J/G/Z/S → `focus-workspace "<name>"` (niri focuses owning output ≡ focusmonitor chain); +Shift → `move-column-to-workspace`. Accepted loss (A10): no toggle-hide. |
| D7 | session-toggle | Parse `Session=` under `[Autologin]` (exactly one, else fail). Flip niri→hyprland, else (hyprland\|omarchy)→niri; other lines byte-preserved. mktemp → `sudo cp /etc/sddm.conf.d/.autologin.tmp.$$ && sudo mv` (same-fs atomic rename). Sudo denial → non-zero, stderr, untouched. Prints old→new. (LIVE-AMENDED 2026-08-19: SDDM 0.21 resolves suffixed basenames only; flip targets are niri.desktop ↔ omarchy.desktop; omarchy.desktop = uwsm Hyprland session discovered in /usr/local/share/wayland-sessions/ — exploration's 'stale session' finding was wrong) (AMENDED #2 same day post-first-boot: read side also normalizes full paths; write side ALWAYS emits /usr/local/share/wayland-sessions/{niri,omarchy}.desktop — the empirically proven form; sed delimiter `|` since values contain slashes; suite now 13/13) |
| D8 | Idle/lock | `~/.config/swayidle/config`: `timeout 152 'niri-lock'` / `resume 'niri-wake'`; `before-sleep 'niri-lock --no-display-off'`; `after-resume 'niri-wake'`. 150s tte listener dropped (A8). Lock-before-suspend = before-sleep blocks sleep until lock completes (≡ inhibit_sleep=3). `niri-lock` = swaylock-effects `--config current/theme/swaylock` + `1password --lock` + power-off-monitors (unless --no-display-off); `niri-wake` = power-on-monitors. |
| D9 | Theming | `themed/niri.kdl.tpl` renders layout background-color + border/focus-ring colors from `{{ background }}`/`{{ accent }}`/`{{ muted }}`; `themed/swaylock.tpl` renders swaylock-effects config (aether). `hooks/theme-set`: APPEND after omazed markers (never inside): `niri msg action load-config-file \|\| true`. Waybar variant reuses themed style.css. Bootstrap: `omarchy theme set aether` before first validate. Menu/refresh best-effort (A19). |
| D10 | Helpers | `~/.local/bin/`: `niri-{lock,wake,nightlight,monitor-toggle,capture,caffeine,monitor-watch}` + `session-toggle`. NEVER `omarchy-*` names — PATH order vs omarchy/bin is environment-dependent (observed both) → no-shadow absolute. `niri-capture` → `niri msg action screenshot-screen\|screenshot-window`; `niri-caffeine` = stop/start swayidle + state file; `niri-monitor-watch` tails `niri msg event` for OutputConnected. **P1 zoom:** expected absent → shortfall documented, Mod+Ctrl+Z unbound; if found → `niri-zoom`. **P2 portal:** expect zero-config (niri-portals.conf); fallback portals.conf pinning screencast=gnome. |
| D11 | Waybar | `config.niri.jsonc`: `hyprland/workspaces`→`niri/workspaces`; drop `custom/hyprcaffeine` (hyprland-bound); rest agnostic, verbatim. |
| D12 | Tearing | **Spec conflict:** no niri tearing node/action. VRR ports; tearing = documented shortfall; spec scenario needs amendment at tasks. |

## Data Flow

    SDDM(Session=niri) → niri-session → cfg/*.kdl ⊕ theme/niri.kdl → stack
    theme set → tpl + colors.toml → current/theme/{niri.kdl,swaylock} → hook → load-config-file

## File Changes

| File | Action |
|---|---|
| `/etc/sddm.conf.d/autologin.conf` | Modify via session-toggle; timestamped backup first |
| `~/.config/niri/**` | Rewrite after timestamped backup (A4); animation.kdl kept |
| `~/.config/waybar/config.niri.jsonc`, `~/.config/swayidle/config` | Create |
| `~/.config/omarchy/themed/{niri.kdl,swaylock}.tpl` | Create |
| `~/.config/omarchy/hooks/theme-set` | Modify (append reload) |
| `~/.local/bin/session-toggle` + 7 `niri-*` wrappers | Create |
| `~/.config/niri/CHECKLIST.md` (+ mirror `openspec/changes/niri-omarchy/checklist.md`) | Create |

## Interfaces / Contracts

`session-toggle`: stdout `Session: <old> → <new>`; exit 0 ok, 1 sudo-denied/parse-fail, 2 ambiguous Session=. Checklist: checkbox per spec scenario ID (`R<req>-S<n>`) with command/probe; SHORTFALLS section (zoom, tearing, colord, runtime-maximize, toggle-hide).

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Static | cfg/*.kdl + rendered niri.kdl | `niri validate` gate before any switch |
| E2E | 23 spec scenarios | live-session CHECKLIST.md, manual (bats proves nothing) |
| Rollback | 3 tiers | backup restore / session-toggle / TTY sudo sed — each reboot-tested |

## Threat Matrix

| Boundary | Applicability |
|---|---|
| Doc-like paths / git / commit / push / PR | N/A — no VCS/doc automation in this change |
| Shell wrapper + sudo + atomic write (adapted) | Applicable: sudo denial, kill mid-write, concurrent toggle, malformed Session= → spec toggle scenarios; manual RED = checklist items |

## Migration / Rollout

(1) sudo install swayidle swaylock-effects wlsunset → (2) backups (niri tar + autologin copy) → (3) write configs/wrappers/tpls → (4) `omarchy theme set aether` → (5) `niri validate` gate → (6) session-toggle → niri → (7) reboot → live checklist → (8) prove rollback tiers. Lockout prevention: no flip before validate; greeter + TTY Ctrl+Alt+F2 `sudo sed` preserved.

## Open Questions

- [ ] D12 tearing: amend spec scenario wording at tasks, or accept failed scenario?
- [ ] D3 numlock ON (user input.conf) vs effective Hyprland OFF (HyprMod artifact) — confirm ON.
