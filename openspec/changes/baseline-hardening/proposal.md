# Proposal: baseline-hardening

## Intent

Harden engine security and robustness (close the `parse_env_safe` injection hole, kill `source` on i18n, relocate the credential-adjacent PID path, add strict mode + tool guards) and ship a deterministic, idempotent, cross-distro installer so the framework deploys identically on any machine.

## Blast Radius — HIGH-RISK

The deployed `~/.local/bin/rdp-connect` runs as the user and handles real RDP credentials (password piped via stdin `/from-stdin:force`). Per `config.yaml` rule "Flag ANY change to the password path, stdin handling, or parse_env_safe as high-risk", the following are flagged:

- **F3** `parse_env_safe` — the stated security boundary; arbitrary-key injection is live today (`PATH=`, `BASH_ENV=`, `LD_PRELOAD=` all clobber-able).
- **F5** PID file in world-writable `/tmp` — symlink/DoS vector on the per-profile lock that gates the credential session.
- **F7** `/from-stdin:force` runtime gate — defensive check directly on the password path.

## Scope

### In Scope

- **F1** Remove `bc` + `python3` HiDPI math → pure-bash integer comparison.
- **F2** Route i18n `MSG_*` keys through the hardened parser (eliminate `source`).
- **F3** `parse_env_safe` allowlist + bash-native quote/comment handling. **Anchor of the change.**
- **F4** Add `set -euo pipefail` with tactical `|| true` on cosmetic `hyprctl` IPC.
- **F5** PID file → `${XDG_RUNTIME_DIR:-fallback}/rdp-<profile>-<uid>.pid`.
- **F6** `require_cmd` helper (xfreerdp3, hyprctl, jq, notify-send, flock, wofi|rofi).
- **F7** Runtime feature-gate on `/from-stdin:force`.
- **F8** Convert `$MON_FLAGS` / `$DPI_FLAGS` strings to arrays.
- **F9** Guard `cleanup()` with `[ -f "$LOG_FILE" ]`.
- **F10** Deterministic cross-distro installer wrapper (Arch/Debian/Fedora detection, declared dep list, idempotent, post-install smoke test, ship engine/i18n/template as real repo files — no runtime heredoc generation).

### Out of Scope

- bats-core / strict_tdd scaffolding (deferred to track b).
- New end-user features; new profiles.
- Engine → sourced-library refactor (only the extraction F10 strictly requires).
- Niche-distro support (Alpine, NixOS) — installer MUST fail loudly, not silently skip.

## Capabilities

> `openspec/specs/` is empty — this change introduces the project's capability structure. Every entry below is **New**.

### New Capabilities

- `engine-security`: the `parse_env_safe` boundary — key allowlist, quote/comment parsing, no `source` on user-controlled files (covers F2, F3).
- `engine-robustness`: strict mode, `require_cmd` guards, array flag-building, cleanup guards, runtime feature-gates (covers F4, F6, F7, F8, F9).
- `hidpi-scaling`: monitor scale detection + DPI flag emission without `bc` / `python3` (covers F1).
- `instance-locking`: per-profile flock + uid-private PID file under `XDG_RUNTIME_DIR` (covers F5).
- `installer`: deterministic cross-distro deployment, distro detection, idempotency, post-install smoke test (covers F10).

### Modified Capabilities

- None (no existing specs to modify).

## Approach

**Approach A — single bundled change, all F1–F10.** Rationale (echoing explore): the findings interlock — F2 requires F3, F4 is only safe after F3 + F6, F8 requires F4, F5 pairs with F9. Landing them piecemeal leaves half-hardened intermediate states that are harder to reason about. F10 bundles naturally because the installer is the verification vehicle for every engine fix.

**Forecast:** ~100 LOC (F1–F9 per explore triage) + ~150 LOC (F10) = **~250 LOC net**, well under the **400-line** review budget with headroom for comments and the manual-verification checklist.

**Fallback:** Approach B (security slice F2/F3/F5/F6/F7 first; robustness+installer slice F1/F4/F8/F9/F10 second) only if the spec or design phase reveals the forecast exceeding 400 lines.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `install-rdp-framework.sh:74–286` (engine heredoc) | Modified | F1–F9 land inside the embedded engine. |
| `install-rdp-framework.sh:1–73` (installer head) | Modified | F10 distro detection + dep install + smoke test. |
| `~/.config/rdp/profiles/*.env` | Compat risk | F3 may reject previously-permissive values (inline comments). |
| `~/.config/rdp/i18n/{es,en}.env` | Consumer | F2 parses instead of `source`. |
| Repo layout (new) | New | F10 ships `engine/`, `i18n/`, `template/` as real files. |

## Risks

| Risk | L | Mitigation |
|------|---|------------|
| **F3** parser change breaks existing profiles with inline comments | Med | Scan `~/.config/rdp/profiles/*.env` pre-apply; document accepted syntax in spec; manual verify in throwaway HOME. |
| **F4** `set -e` aborts a live RDP session on transient `hyprctl` IPC error | Med | Tactical `\|\| true` on cosmetic IPC (focuswindow, keyword); cleanup `grep` guarded with `\|\| true`. |
| **F6** `require_cmd hyprctl` makes Hyprland a hard requirement | High (intended) | Correct for scope; README note + installer preflight message for Sway users. |
| **F10** distro detection misses niche distros (Alpine, NixOS) | Low | Fail loudly with explicit error + suggested manual install path; never silently skip. |
| **F8** empty-array expansion under `set -u` | Med | Always initialize arrays; use `"${arr[@]-}"` where unsure. |
| **F5** PID relocation surprises users looking for stale locks in `/tmp` | Low | EXIT trap cleans the new path; README documents `${XDG_RUNTIME_DIR}/rdp-*`. |

## Rollback Plan

Installer is idempotent (per `config.yaml`). Rollback = `git checkout` the previous tag and re-run `install-rdp-framework.sh`; deployed files (`~/.local/bin/rdp-connect`, `~/.config/rdp/`) are overwritten to prior state. For F10 specifically: the previous installer version re-deploys the prior engine; no destructive migration is performed.

## Dependencies

- Hyprland running (`hyprctl`) — hard requirement after F6.
- `xfreerdp3` build with `/from-stdin:force` support — runtime-gated by F7.
- F10 declared package set: `freerdp3`, `jq`, `util-linux` (flock), `libnotify`, `wofi`|`rofi`, `hyprland`, `shellcheck`. `bc` and `python3` are **removed** by F1.

## Success Criteria

- [ ] A malicious `PATH=...` (or `BASH_ENV=`, `LD_PRELOAD=`) line in a profile is rejected; only allowlisted keys are set.
- [ ] `DOMAIN="MicrosoftAccount" # comment` parses to `MicrosoftAccount` (no trailing quote/comment).
- [ ] `source` no longer appears on any `~/.config/rdp/**` path inside the engine.
- [ ] On a `bc`-less box, a 2× scale monitor still receives `/scale:200`.
- [ ] `set -euo pipefail` is in effect and a live session survives a transient `hyprctl` blip.
- [ ] PID file lives under `/run/user/<uid>/` (or documented fallback), never `/tmp`.
- [ ] Running `install-rdp-framework.sh` twice produces byte-identical deployed state.
- [ ] On a clean Debian/Fedora box, the installer detects the package manager, installs missing deps, and `rdp-connect --help` succeeds post-install.
- [ ] On an unsupported distro, the installer exits non-zero with a clear, actionable message.
- [ ] `shellcheck install-rdp-framework.sh && bash -n install-rdp-framework.sh` both clean.
