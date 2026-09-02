# Exploration: niri-omarchy — Run Niri as the session compositor while preserving the Omarchy/Hyprland look & feel

Change id: `niri-omarchy` | Phase: explore | Date: 2026-08-18
Intent (user): complete exploration + step-by-step plan to use Niri with the current Hyprland-Omarchy aspect and functionality, autologin landing in Niri, trivial rollback to Hyprland.

> Scope note: this change TARGETS SYSTEM CONFIG (`~/.config/**`, `/etc/sddm.conf.d/**`, installed packages). The rdp-connect repo is only the artifact anchor. Repo bats tests (`make test`) are NOT a verification path for Niri configs — verification is manual (`niri validate` + live session checklist).

## Current State

### Session mechanics (how Omarchy boots today)
- SDDM 0.21.0 autologin: `/etc/sddm.conf.d/autologin.conf` → `User=hbuddenberg`, `Session=omarchy` (stale name; no `omarchy.desktop` exists → SDDM falls back to `hyprland.desktop` → `Exec=/usr/bin/start-hyprland`). Greeter `CompositorCommand=start-hyprland` (login screen only, independent of session choice).
- `/usr/bin/start-hyprland` is an **ELF watchdog binary shipped by the `hyprland 0.56.2-1` package** (verified via `pacman -Qo` + `strings`). It only starts/restarts Hyprland. It does NO dbus/uwsm/env setup.
- The actual session hygiene comes from Omarchy's autostart lines: `systemctl --user import-environment $(env | cut -d= -f1)` + `dbus-update-activation-environment --systemd --all` (`~/.local/share/omarchy/default/hypr/autostart.conf`). The running session is NOT uwsm-managed (the `uwsm-app --` prefixes in autostart degrade gracefully to plain exec).
- `/usr/bin/niri-session` (niri 26.04-1.1) already does the equivalent hygiene natively: guards against double sessions, `systemctl --user import-environment`, `dbus-update-activation-environment --all`, starts `niri.service` via `systemctl --user --wait`, tears down `graphical-session.target` via `niri-shutdown.target`, unsets session env on exit.
- Wayland session files: `hyprland.desktop` (start-hyprland), `hyprland-uwsm.desktop` (`uwsm start -e -D Hyprland hyprland.desktop`), `niri.desktop` (`Exec=niri-session`, `DesktopNames=niri`). **No niri-uwsm .desktop exists.**
- Conclusion: switching = one line, `Session=omarchy` → `Session=niri` (niri.desktop exists, so the key resolves). Rollback = restore the previous line (recommend keeping a timestamped copy of `autologin.conf`; also note `Session=hyprland` is the *correct* non-stale Hyprland value if the user wants to fix the staleness during rollback). Greeter needs no change.

### Omarchy 3.8.3 integration surface
- `grep -ri niri ~/.local/share/omarchy/` → only a comment in `config/hypr/looknfeel.conf` ("Change to niri-like side-scrolling layout") and a false-positive match inside a wallpaper JPEG. **No native niri support in Omarchy 3.8.3.**
- `omarchy update` never touches `~/.config/niri/` (clean separation confirmed).
- `omarchy-niri-config-gen` does NOT exist anywhere (`which` empty, nothing niri-ish in `~/.local/bin` or omarchy `bin/`).
- Theming: `omarchy theme set <name>` (`omarchy-theme-set`) copies stock theme dir + user overlay dir (`~/.config/omarchy/themes/<name>/`) verbatim into `~/.config/omarchy/current/theme/`, writes `theme.name`, then regenerates themed files via `omarchy-theme-set-templates` (renders `*.tpl` from `colors.toml`; **user templates in `~/.config/omarchy/themed/*.tpl` override built-ins — a safe, non-omarchy-owned extension point for a `niri.kdl` theme variant**). Current theme: `aether`, a USER theme (not in stock list) at `~/.config/omarchy/themes/aether/`.
- Theme dir contains per-app theming: `hyprland.conf`, `hyprlock.conf`, `waybar.css`, `mako.ini`, `walker.css`, `swayosd.css`, `gtk.css`, terminal confs, `colors.toml`, backgrounds. Most are compositor-agnostic; `hyprland.conf`/`hyprlock.conf` are Hyprland-only.
- User hook `~/.config/omarchy/hooks/theme-set` exists (calls `omazed set`) — another safe ride-along point for niri re-theming.
- Omarchy default autostart (`~/.local/share/omarchy/default/hypr/autostart.conf`), classified:
  - **Compositor-agnostic**: `mako`, `waybar` (gated by `waybar-off` toggle), `fcitx5`, `swaybg -i ~/.config/omarchy/current/background -m fill` (wallpaper is already swaybg — hyprpaper is NOT installed), `polkit-gnome`, `omarchy-first-run`, `omarchy-powerprofiles-init`, post-boot hook.
  - **Hyprland-specific**: `hypridle`, `omarchy-hyprland-monitor-watch` (listens on Hyprland socket2).
  - **Redundant under niri**: `systemctl --user import-environment` + `dbus-update-activation-environment` (niri-session does both).
  - User autostart (`~/.config/hypr/autostart.conf`): `input-remapper-control stop-all && autoload` (agnostic), `omarchy-launch-webapp gmail` (agnostic).

### Existing niri config audit (`~/.config/niri/`, okimarchy-derived, `niri validate` PASSES)
- Modular: `config.kdl` includes `cfg/{animation,autostart,keybinds,input,display,layout,rules,misc}.kdl`.
- **It is a noctalia-shell desktop, not an Omarchy port.** `autostart.kdl` spawns only `noctalia` (installed: noctalia 5.0.0_beta.8 from cachyos-extra). Noctalia is an all-in-one shell (bar, launcher, notifications, lock, wallpaper, OSD, control center) — a *different* stack from Omarchy's waybar/walker/mako/swayosd/swaybg.
- `layout.kdl`: gaps 16, `background-color "transparent"` specifically so noctalia's wallpaper layer shows; preset column widths 1/3–2/3.
- `display.kdl`: **entirely commented out** (`/-` prefix) — none of the 3 monitors are configured.
- `input.kdl`: layout commented (user needs `latam` + `compose:caps`), numlock on, natural-scroll ON (user's Hyprland has natural_scroll commented OFF), focus-follows-mouse ON (not in Hyprland config), `workspace-auto-back-and-forth`.
- `misc.kdl`: env block (needs `GDK_SCALE=2` port from monitors.conf), capitaine-cursors, blur, `honor-xdg-activation-with-invalid-serial` for noctalia, `screenshot-path null` (noctalia handles screenshots).
- `rules.kdl`: global radius 20 + blur, noctalia float/layer rules, steam rules. No port of Omarchy's `windows.conf` semantics (default opacity 0.97/0.9, suppress maximize).
- `keybinds.kdl`: noctalia-centric bindings (Mod+S control center, Mod+Ctrl+Return noctalia launcher, media keys via `noctalia msg`, lock via noctalia). Layout keys are stock niri defaults-ish (Mod+H/J/K/L focus, Mod+Q close, Mod+F maximize, workspaces 1–9).

### Hyprland→niri binding/config gap map (what "functionality parity" requires)
The user's Hyprland setup is extensive. Major groups with NO niri equivalent today:
1. **Special workspaces / scratchpad system** (`~/.config/hypr/workspaces.conf`): 7 named specials (mensajeria, ai, musica, correo, terminal, silencio, scratchpad), each with SUPER+<key> toggle pinned to a specific monitor via focusmonitor chains, plus windowrules routing webapp classes (WhatsApp/Discord/Telegram/Claude/ChatGPT/Gemini/AppleMusic/Gmail) into them. Niri has NO special workspaces; nearest emulation = per-output named workspaces + `open-on-workspace` window rules + focus toggles. Partial fidelity; this is the biggest UX migration item. NOTE: existing niri binds collide with these keys (Mod+S, Mod+A, Mod+M, Mod+J, Mod+G, Mod+Z are all used by noctalia binds).
2. **Omarchy launcher layer**: SUPER+SPACE walker, SUPER+ALT+SPACE omarchy-menu, system/hardware/toggle/capture/theme/background menus, clipboard manager (SUPER+Ctrl+V), emoji picker, reminders, capture menu — all `omarchy-*` CLIs are compositor-agnostic and bindable in niri, but none are bound.
3. **User app layer** (bindings.conf): scratchpad terminal (SUPER+Return → `launch-scratchpad-terminal.sh`, which is **hyprctl-dependent**), tmux, browser/editor/webapp launchers (agnostic CLIs, portable), rdp-connect on SUPER+SHIFT+R.
4. **Media/brightness with OSD**: Hyprland routes through `omarchy-swayosd-client` (agnostic — talks to swayosd) + `omarchy-brightness-display`; niri config routes through `noctalia msg` (noctalia OSD). Stack decision needed (swayosd vs noctalia OSD) — do NOT run both.
5. **Screenshots**: Omarchy `omarchy-capture-screenshot` uses slurp/satty BUT reads monitor/window geometry via `hyprctl monitors -j`/`hyprctl clients -j` (4 hyprctl calls) → **breaks under niri**. Same for screenrecording (6 hyprctl calls). Text extraction is clean. Niri has built-in `screenshot` actions (bound to Ctrl+Shift+1/2/3) — acceptable substitute, different UX (no satty edit flow).
6. **Lock/idle/screensaver**: `omarchy-system-lock` = hyprlock + hyprctl switchxkblayout + 1Password lock + display off. `omarchy-launch-screensaver` is hyprctl-dispatch heavy (spawns tte terminal screensaver per monitor). `hypridle.conf`: screensaver at 150 s, lock at 152 s, lock-before-suspend, inhibit_sleep=3. All Hyprland-only.
7. **Misc**: cursor zoom (hyprctl zoom_factor — niri has no equivalent), hyprcaffeine (idle inhibitor; waybar module + keybinds; likely Hyprland-specific — verify), monitor toggles/scaling-cycle/close-all/pop/gaps/transparency/workspace-layout-toggle omarchy helpers (hyprctl-bound), lid switch handling, touchpad toggle keys.
8. **Monitors** (effective config from `hyprland-gui.conf`, which loads after and overrides `monitors.conf`): Dell U2417H #1 1920x1080@60 @0x0, ASUS XG27ACS 2560x1440@60 @1920x0, Dell U2417H #2 1920x1080@60 @4480x0, all scale 1, `cm, srgb` colormanager on Dells, VRR on, tearing allowed, GDK_SCALE=2 env, gaps 4/border 4, scrolling layout `column_width 0.49` (user already runs Hyprland's niri-like scrolling layout — the migration motive). Niri `display.kdl` must port positions/modes/VRR; `cm, srgb` (colord CMS) has no confirmed niri equivalent (verify at apply).
9. **XWayland**: niri ≥ 25.05 auto-spawns `xwayland-satellite` when installed — 0.8.2 is installed; confirm at apply time (X11 apps incl. some RDP flows may depend on it).

### Replacement components — installed status
| Component | Hyprland | Candidate | Installed? |
|---|---|---|---|
| Idle daemon | hypridle 0.1.8 | swayidle | **NO** (must install) |
| Lock screen | hyprlock 0.9.6 (theme-rendered `hyprlock.conf`) | swaylock / swaylock-effects | **NO** (must install; PAM file ships with pkg; only `hyprlock` PAM exists today) |
| Night light | hyprsunset 0.4.0 (currently identity/off) | wlsunset | **NO** (must install) |
| Wallpaper | swaybg 1.2.2 (already agnostic) | swaybg | **YES** |
| XWayland | built-in | xwayland-satellite 0.8.2 | **YES** |
| Screenshots | grim 1.5.0 + slurp 1.5.0 (hyprctl-wrapped in omarchy scripts) / niri built-in | both present | **YES** |
| Bar | waybar 0.15.0 (`hyprland/workspaces` + `custom/hyprcaffeine` modules) | `niri/workspaces` + `niri/window` modules | **YES** — man pages `waybar-niri-*.5` confirm module support |
| Notifications/launcher/OSD | mako 1.11, walker 2.17, swayosd 0.3.1 | same (agnostic) | **YES** |

### rdp-connect adjacency (documented, not fixed here)
`rdp-connect` (this repo) hard-requires `hyprctl` (require_cmd preflight + monitor/workspace detection for DPI/monitor flags). Under a Niri session it fails at preflight. Remediation (niri `msg` port vs documented limitation) is a proposal-scope decision.

## Affected Areas
- `/etc/sddm.conf.d/autologin.conf` — the one-line session switch + rollback anchor.
- `~/.config/niri/**` — full rework of autostart/keybinds/display/input/layout/rules/misc (current content is noctalia-oriented, omarchy-hostile in places).
- `~/.config/waybar/config.jsonc` — swap `hyprland/workspaces` → `niri/workspaces`; handle `custom/hyprcaffeine`.
- `~/.config/omarchy/themed/*.tpl` (+ optionally `~/.config/omarchy/hooks/theme-set`) — niri theming ride-along.
- Installed packages — add swayidle, swaylock(-effects), wlsunset.
- NOT affected (verified): `~/.local/share/omarchy/**` (read-only per skill), `~/.config/hypr/**` (left intact for rollback), SDDM greeter.

## Approaches

### 1. Port the Omarchy stack into Niri (drop noctalia from the session)
Rewrite `~/.config/niri/` to spawn the Omarchy stack (waybar w/ niri module, mako, walker, swayosd, swaybg, fcitx5, polkit-gnome, input-remapper, powerprofiles), port bindings to Omarchy semantics, install swayidle/swaylock-effects/wlsunset, emulate special workspaces with per-output named workspaces, add a niri theme template riding `omarchy theme set`.
- Pros: matches the user's stated intent exactly (same bar, launcher, notifications, OSD, theming pipeline, menus); reuses all agnostic theme files (waybar.css/mako.ini/walker.css/swayosd.css) as-is; maximal parity; noctalia binary simply not spawned.
- Cons: largest effort; idle/lock/screensaver flows need nidi replacements (omarchy-system-lock is immutable in omarchy-owned PATH — keybinds must call a user wrapper instead); special-workspace emulation is partial; several hyprctl-bound omarchy helpers remain broken (documented).
- Effort: **High** (but incremental, parallel-safe with Hyprland kept intact).

### 2. Keep the current noctalia-on-niri config
Adopt the existing valid niri config as-is (noctalia shell provides everything).
- Pros: near-zero work; already validates.
- Cons: NOT the Omarchy look & feel (different bar/launcher/notifications/lock/theming); abandons the omarchy theme pipeline and menus; contradicts the change intent.
- Effort: **Low**.

### 3. Hybrid (noctalia for lock/OSD/wallpaper + omarchy bar/launcher/notifications)
- Pros: fewer missing pieces initially.
- Cons: duplicate OSD/notifications/wallpaper conflict sources; two theming systems fighting; worst maintainability.
- Effort: **Medium**, not recommended.

## Recommendation
**Approach 1.** It is the only one that satisfies "aspecto y funcionalidad actual". Land it in this order: (1) session switch mechanics + rollback proof, (2) core autostart port (bar/notifications/launcher/wallpaper/OSD), (3) bindings port incl. special-workspace emulation, (4) idle/lock/night-light replacements (after package install), (5) theme ride-along template, (6) parity checklist pass. Keep `~/.config/hypr/` untouched so rollback is purely the autologin line. Do not create a uwsm niri desktop — stock `niri-session` already matches Omarchy's session hygiene.

## Risks
1. **Autologin lockout into a broken session** — Severity: High impact / low probability. Mitigation: `niri validate` before every switch; SDDM falls back to greeter on session exit (greeter runs start-hyprland, independent); TTY Ctrl+Alt+F2 + `sudo sed` rollback; keep rollback command in the artifact.
2. **rdp-connect breaks under Niri** (hyprctl preflight) — Severity: High for daily workflow. Out of exploration scope; proposal must decide (niri msg port vs documented Hyprland-only limitation). SUPER+SHIFT+R binding is portable either way.
3. **Special-workspace system cannot be fully replicated** (7 scratchpads, monitor-pinned toggles, class-based routing) — Severity: High (core daily UX). Mitigation: niri per-output named workspaces + `open-on-workspace` rules + focus-toggle binds; expect partial fidelity (e.g., no "toggle hides windows but keeps them" semantics — actually niri workspaces do persist windows; main loss is the special-vs-visual workspace distinction and per-monitor summon-on-any-monitor behavior).
4. **Lock/idle/screensaver chain needs rebuilding with uninstalled packages** (swayidle, swaylock-effects, wlsunset missing) — Severity: Medium-High (security-relevant: lock-before-suspend must not regress). `omarchy-system-lock`/`omarchy-launch-screensaver` are hyprctl/hyprlock-bound and live in the read-only omarchy tree; niri keybinds must call user-space wrappers (~/.local/bin does NOT precede omarchy/bin in PATH — do not shadow, rebind instead).
5. **Omarchy menu/helper surface partially broken under niri** (monitor toggles/scaling cycle/gaps/transparency/workspace-layout toggles, monitor-watch, cursor zoom, hyprcaffeine, capture scripts' hyprctl geometry calls) — Severity: Medium. Mitigation: bind niri-native equivalents where trivial (`niri msg action ...`), document the rest as Hyprland-only.
6. **Theme set writes hyprland-only + restarts** — Severity: Low. Agnostic components (waybar/mako/terminal) still theme correctly; niri colors need the user-template ride-along; `omarchy-restart-hyprctl` fails silently under niri (cosmetic).
7. **Waybar module swap + hyprcaffeine module** — Severity: Low-Medium. `niri/workspaces` exists in waybar 0.15; `custom/hyprcaffeine` likely dead under niri (verify; remove or condition).
8. **Noctalia stack conflicts if both spawned** — Severity: Medium (duplicate bars/OSD/notifications/wallpaper). Mitigation: remove `spawn-at-startup "noctalia"` + noctalia binds + transparent background + `screenshot-path null` when porting; binary may stay installed.
9. **Monitor/colormanagement gaps** — `cm, srgb` (colord) on the Dells has no confirmed niri equivalent; VRR/tearing need explicit output config; conflicting monitor definitions exist in Hyprland config (effective = hyprland-gui.conf values). Severity: Medium (visual fidelity), verify at apply.
10. **Verification path is manual, not bats** — repo `make test` proves nothing here; verification = `niri validate` + a live-session parity checklist + one reboot test. Severity: Low process risk, but MUST be stated in spec/verify phases.

## Ready for Proposal
Yes. The proposal should decide: (a) confirm Approach 1; (b) rdp-connect remediation scope (port vs document); (c) swaylock vs swaylock-effects vs noctalia-lock; (d) how faithful the special-workspace emulation must be (full 7-workspace port vs reduced set); (e) whether GDK_SCALE=2 and other env vars carry over as-is; (f) package install list approval (sudo required).
