# Tasks: niri-omarchy

Boundaries: never modify `~/.local/share/omarchy/**`; `~/.config/hypr/**` frozen; noctalia installed; backup precedes niri rewrites; `— verify` = checkbox.

## Review Workload Forecast

|Field|Value|
|---|---|
|Estimated changed lines|~650–750 (cfg, wrappers, tpls, waybar, checklists); repo-side ≈100|
|400-line budget risk|High|
|Chained PRs recommended|Yes — as chained apply slices|
|Chain strategy|pending (user decision)|

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

**Non-repo reality:** system-config files aren't PR-able: "changed lines" = authored config lines; slices = apply batches with start/finish/verification/rollback; repo gets only the checklist mirror. Proposed (undecided): `git -C ~/.config/niri init` post-backup for diffs.

### Units

|Unit|Goal|Focused test|Runtime harness|Rollback|
|---|---|---|---|---|
|1|installs+backups|`pacman -Q`|N/A|`pacman -R`|
|2|cfg+waybar+swayidle|`niri validate`|N/A|untar backup|
|3|wrappers+toggle|`shellcheck`|`sudo -k` probe|rm 8 binaries|
|4|theming|rendered files|`theme set aether`|rm tpls; hook|
|5|gate+switch|pre-switch validate|reboot|3 rollback tiers|
|6|checklist+proofs|24/24 green|live probes|N/A|

## Phase 1: Installs, backups

> Slice-1 note (2026-08-18): sudo is password-gated (`sudo -n` fails). DONE without sudo: niri tar backup, user-side autologin copy, frozen-tree checksums, git init + baseline `b7da1b4`. PENDING sudo: package installs (1.1) and the `/etc/sddm.conf.d/autologin.conf.bak.<ts>` copy (1.2). Details: Engram `sdd/niri-omarchy/apply-progress`.
> Slice-2 note (2026-08-19): the two sudo commands were run by the user between slices — packages verified (`pacman -Q`: swayidle 1.9.0-1.1, swaylock-effects 1.8.1-1, wlsunset 0.4.0-1.1) and `/etc/sddm.conf.d/autologin.conf.bak.20260818-173326` exists; 1.1/1.2 closed. Phase 2 committed `d525d65` in `~/.config/niri`.

- [x] 1.1 `sudo pacman -S swayidle swaylock-effects wlsunset` — verify `pacman -Q`.
- [x] 1.2 Tar `~/.config/niri`; `sudo cp -a` autologin.conf → `.bak.<ts>`; checksum `~/.config/hypr/**`+`~/.local/share/omarchy/**` — verify exist (R12-S2).
- [x] 1.3 DECISION-GATED: `git -C ~/.config/niri init` post-backup; skip if declined.

## Phase 2: Config writes (D1–D6, D11)

- [x] 2.1 `config.kdl`: include `cfg/*.kdl` + `../../omarchy/current/theme/niri.kdl`; keep animation.kdl. *(niri has no glob include — explicit list; themed path is `../omarchy/...` from config.kdl, one level up — probed.)*
- [x] 2.2 `cfg/display.kdl`: 3 outputs by make/model/serial; design position/scale; ASUS VRR; named workspaces per output (R9-S1, R11-S2). *(VRR = bare `variable-refresh-rate`; `true` arg rejected — probed.)*
- [x] 2.3 `cfg/input.kdl`: latam; `compose:caps`; repeat 40/250; numlock on; accel 0.35 (R11-S1). *(effective Hyprland: adaptive profile — hyprland-gui wins over user `flat`.)*
- [x] 2.4 `cfg/misc.kdl` + `cfg/layout.kdl`: `GDK_SCALE=2`; blur; xdg-activation; gaps+border 4; radius 0; clip; presets 0.49/0.98 (R4-S1).
- [x] 2.5 `cfg/rules.kdl`: ALL windows.conf rules; `opacity 0.97 0.9`; 7 class lists → workspaces; ghostty float (R4-S2, R5-S2). *(26.04 rejects two-arg opacity — single-value 0.97 fallback, pre-sanctioned.)*
- [x] 2.6 `cfg/binds.kdl`: nav core + user binds (launcher/menus/terminal/rdp-connect); Mod+M/A/J/G/Z/S focus, Shift move (R5-S1). *(replaces noctalia keybinds.kdl; parity wins over 5 conflicting core binds.)*
- [x] 2.7 `cfg/autostart.kdl`: D4 spawn list; NO noctalia spawn (R3-S1).
- [x] 2.8 `waybar/config.niri.jsonc`: `niri/workspaces` swap; drop hyprcaffeine; rest verbatim.
- [x] 2.9 `swayidle/config`: 152s `niri-lock`/wake; before-sleep `--no-display-off` (R6-S1/S2). *(swayidle 1.9: `resume` is an inline timeout suffix, not a standalone line — probed.)*

## Phase 3: Wrappers + session-toggle (D7, D10)

- [x] 3.1 RED (sudo+atomic-write): probes R2-S1/S2/S3 + ambiguous `Session=` — flip = one line; mid-write kill → complete old-or-new; denial/parse-fail → exit 1+stderr, untouched. *(RED 0/8 @ rc=127 → GREEN 8/8; probes in `~/.local/state/niri-omarchy/tests/run-toggle-tests.sh` — location not pinned by tasks.md, orchestrator-sanctioned; sudo stubbed in PATH, kill-after-cp stub proves atomicity.)*
- [x] 3.2 `~/.local/bin/session-toggle`: parse `Session=`; flip; mktemp+`sudo cp`+`sudo mv`; print old→new — verify `sudo -k`; `bash -n`. *(`--conf PATH` test override; real-sudo denial probed under `setsid`: rc=1+stderr+untouched, no hang; exit 2 = ambiguous per design interfaces; shellcheck warning-clean.)*
- [x] 3.3 Wrappers `niri-{lock,wake,nightlight,monitor-toggle,capture,caffeine,monitor-watch}` — verify `type -a` shadows nothing (R8-S1). *(7 in `~/.local/bin`, mode 700, shellcheck warning-clean; `type -a` = single path each, 0 collisions vs omarchy/bin listing; binds.kdl/swayidle reference names matched by grep first.)*
- [x] 3.4 PROBE P1 zoom: exists → `niri-zoom` + Mod+Ctrl+Z bind; absent → SHORTFALLS, unbound (R8-S2). *(ABSENT: `niri msg action --help` = 0 zoom actions; recorded in `~/.local/state/niri-omarchy/SHORTFALLS.md`; no niri-zoom, no binds edit — binds.kdl:255 documents it as comment only.)*

## Phase 4: Theming (D9)

- [x] 4.1 `themed/{niri.kdl,swaylock}.tpl` (aether vars); append hook reload after omazed markers; run `omarchy theme set aether` — verify rendered files (R7-S1).

## Phase 5: Gate + switch

> Slice-5 note (2026-08-19): gate + rehearsal done by agent — validate exit 0, 12/12 invariants PASS, toggle suite 8/8, GO-NOGO.md written (`~/.local/state/niri-omarchy/GO-NOGO.md`). The flip+reboot+land-check are USER-executed per GO-NOGO.md (sudo password interactive by design); slice 6 confirms R1-S1/R2-S1 live. Checkbox reflects gate-slice success per orchestrator contract.
> Remediation (2026-08-19, slice-5r): post-reboot defect — bare `Session=niri` matched no session file and SDDM fell back to state.conf `Last.Session` (omarchy.desktop, uwsm Hyprland in /usr/local/share/wayland-sessions/) → booted Hyprland; session-toggle + suite remediated to suffixed basenames `niri.desktop` ↔ `omarchy.desktop` with read-side legacy normalization (RED 6-fail → GREEN 11/11 ×2); see GO-NOGO.md ADDENDUM + design.md D7 amendment.

- [x] 5.1 `niri validate` until clean — gate (R1-S2); `session-toggle` → niri; reboot — verify diff + autologin lands niri (R2-S1, R1-S1).

## Phase 6: Live verification

- [ ] 6.1 Regenerate CHECKLIST.md + openspec mirror from v2 24 IDs `R1-S1…R12-S2` (supersedes stale 23); SHORTFALLS: zoom/tearing/colord/runtime-maximize/toggle-hide (R8-S2, R9-S2/S3).
- [ ] 6.2 Execute 24 live; PROBE P2 portal: zero-config screencast, else `portals.conf` screencast=gnome, retest (R10-S1).
- [ ] 6.3 Prove 3 rollback tiers (backup/`session-toggle`/TTY `sudo sed`), reboot each (R1-S3).
- [ ] 6.4 Verify frozen-tree checksums unchanged (R12-S1); `pacman -Q noctalia` (R3-S1).
