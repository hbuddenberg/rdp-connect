# Archive Report — baseline-hardening

> **Change**: `baseline-hardening`
> **Project**: `rdp-connect`
> **Archived**: 2026-07-21
> **Archive path**: `openspec/changes/archive/baseline-hardening/`
> **Canonical capability specs**: `openspec/specs/{engine-security,engine-robustness,hidpi-scaling,instance-locking,installer}/spec.md`
> **Merged PRs**: [#1 (security-core)](https://github.com/hbuddenberg/rdp-connect/pull/1), [#2 (robustness-installer + bugfix slice)](https://github.com/hbuddenberg/rdp-connect/pull/2)
> **Engram mirror**: topic_key `sdd/baseline-hardening/archive-report`

## Executive Summary

The `baseline-hardening` change is fully landed on `main` and archived. Both chained PRs (stacked-to-main) merged; all 9 tasks (T1.1–T1.4 PR1 + T2.1–T2.3 PR2 + T2.4–T2.6 PR2 bugfix slice) are implementation-complete and verified at runtime. 5 canonical capability specs now live under `openspec/specs/`; the 5 delta specs from the change folder were promoted to canonical and **amended** with three sets of bugfix-slice scenarios that were implemented during the PR2 bugfix slice but were not codified in the original deltas. The change folder has been moved to `openspec/changes/archive/baseline-hardening/` as an immutable audit trail. README has been refreshed with final-state badges, a capabilities matrix, an install one-liner, a smoke-test command, a manifest-verification command, a distro support matrix, and a pointer to `openspec/specs/`.

## Canonical Specs Synced

The `openspec/specs/` directory started empty (per proposal: "every entry below is **New**"). All five delta specs were promoted to canonical (no merge into pre-existing content needed). The deltas' `## ADDED Requirements` framing was rewritten as plain capability spec framing; the requirement and scenario content is otherwise verbatim from the deltas, with the explicit additions below.

| Capability | Source delta | Canonical spec | Action |
|---|---|---|---|
| `engine-security` | `engine-security-delta.md` | `openspec/specs/engine-security/spec.md` | **Promoted + amended** — added 3 new scenarios under `Quote and comment handling` for CRLF tolerance, trailing-whitespace-after-quote tolerance, and garbage-after-closing-quote rejection with raw preview. Also reconciled the `printf -v` interpretation note (resolved). |
| `engine-robustness` | `engine-robustness-delta.md` | `openspec/specs/engine-robustness/spec.md` | **Promoted + amended** — added 1 new requirement `Cleanup error diagnostic scoped to the current session` (4 scenarios) and 1 new requirement `Preflight input normalization` (3 scenarios). |
| `hidpi-scaling` | `hidpi-scaling-delta.md` | `openspec/specs/hidpi-scaling/spec.md` | **Promoted verbatim** — no amendment. |
| `instance-locking` | `instance-locking-delta.md` | `openspec/specs/instance-locking/spec.md` | **Promoted verbatim** — no amendment. |
| `installer` | `installer-delta.md` | `openspec/specs/installer/spec.md` | **Promoted + reconciled** — `Post-install smoke test` requirement updated to enumerate all 4 actual smoke steps (bash -n, shellcheck --severity=warning, --help, parser-probe); `Checksum manifest` requirement updated to canonical name `manifest.sha256` (was `install-manifest.sha256` in design pseudocode); `Distro detection` requirement updated to mandate grep-based parsing (not `. /etc/os-release`) for `set -euo pipefail` safety. |

## Scenarios Amended (bugfix slice that wasn't in original deltas)

| Capability | Scenario | Source task |
|---|---|---|
| `engine-security` | CRLF terminated line is tolerated | T2.4 |
| `engine-security` | Trailing whitespace after closing quote is tolerated | T2.4 |
| `engine-security` | Garbage after closing quote is rejected with raw preview | T2.4 |
| `engine-robustness` | Cleanup diagnostic scoped to current session by PID | T2.5 |
| `engine-robustness` | PID prefix safety | T2.5 |
| `engine-robustness` | Current session with no ERROR line returns empty | T2.5 |
| `engine-robustness` | Legacy log file without SESSION_START marker degrades gracefully | T2.5 |
| `engine-robustness` | VPN_CHECK with whitespace trimmed before preflight | T2.6 |
| `engine-robustness` | HOST with surrounding whitespace is trimmed before TCP probe | T2.6 |
| `engine-robustness` | PASS_RDP and USER_RDP are NOT trimmed | T2.6 |

**Total scenarios in canonical specs**: 9 (engine-security) + 18 (engine-robustness) + 5 (hidpi-scaling) + 7 (instance-locking) + 12 (installer) = **51 normative scenarios**.

## Documentation Gaps Closed (per verify-report-pr2)

| Gap | Resolution |
|---|---|
| `tasks.md` lacked T2.4, T2.5, T2.6 entries | Added full "PR2 — bugfix slice" section with per-scenario manual-verification evidence mirroring `apply-progress.md`. Updated forecast table to "final, post-archive" with actual line counts. Renamed "Suggested Work Units" → "Work Units Delivered" with merged-PR status per task. |
| `apply-progress.md` lacked a T2.6 section | Extended "PR2 — bugfix slice" section from T2.4+T2.5 to T2.4+T2.5+T2.6: updated header, goal, discoveries, accomplished, deviations, issues, workload, and status. T2.6 now has its own `✅` entry with placement rationale and the PASS_RDP/USER_RDP exclusion note. |
| `verify-report-pr2.md` was untracked (not committed) | Staged for inclusion in the archive commit. |
| Engine-security `Quote and comment handling` didn't codify the implemented CRLF/whitespace/tail-validation behavior | Synced 3 new scenarios into canonical `engine-security/spec.md`. |
| Engine-robustness didn't codify the implemented cleanup session-isolation or VPN trim | Synced 2 new requirements (7 scenarios) into canonical `engine-robustness/spec.md`. |
| Installer spec said `install-manifest.sha256`; code uses `manifest.sha256` | Canonical installer spec now uses `manifest.sha256` (matches deployed engine). |
| Installer spec smoke test omitted bash -n + shellcheck steps | Canonical installer spec now enumerates all 4 smoke steps. |
| Installer spec didn't mandate grep-based os-release parsing | Canonical installer spec now mandates grep-based parsing for `set -u` safety. |

## Archive Contents

The change folder moved verbatim — no deletion, no rewrite. The archive contains the complete SDD cycle artifacts:

- `proposal.md` ✅
- `specs/` ✅ (5 delta specs — the source material for the canonical sync)
- `design.md` ✅
- `tasks.md` ✅ (9/9 tasks complete, forecast updated to final)
- `apply-progress.md` ✅ (T1.1–T2.6 all documented)
- `verify-report-pr1.md` ✅ (16/16 PR1 scenarios compliant, PASS WITH WARNINGS)
- `verify-report-pr2.md` ✅ (28/28 PR2 scenarios compliant, PASS WITH WARNINGS)
- `explore.md` ✅ (F1–F9 finding triage)
- `archive-report.md` ✅ (this file)

## Verification Snapshot

| Phase | Scenarios | Result |
|---|---|---|
| PR1 verify (security-core: engine-security + instance-locking) | 16/16 ✅ | PASS WITH WARNINGS (3 non-blocking hygiene WARNs) |
| PR2 verify (hidpi-scaling + engine-robustness + installer) | 28/28 ✅ | PASS WITH WARNINGS (size + doc-gap WARNs, both closed at archive) |
| **Total** | **44/44 spec scenarios** | **All COMPLIANT** |
| Executable probes | parser 24/24, hidpi 8/8, pid-path 6/6, vpn-trim 8/8 | 46/46 ✅ |
| Structural | shellcheck --severity=warning clean (engine + lib + installer + tests); bash -n clean | ✅ |

## Commits Made (this archive)

1. `docs(sdd): archive baseline-hardening — sync delta specs to canonical capabilities` — the archive commit on `main`. Includes:
   - 5 new canonical capability spec files under `openspec/specs/`
   - Updated `openspec/changes/baseline-hardening/tasks.md` (T2.4/T2.5/T2.6 + forecast)
   - Updated `openspec/changes/baseline-hardening/apply-progress.md` (T2.6 section + status)
   - `openspec/changes/baseline-hardening/` moved to `openspec/changes/archive/baseline-hardening/`
   - `openspec/changes/archive/baseline-hardening/archive-report.md` (this file)
   - `openspec/changes/archive/baseline-hardening/verify-report-pr2.md` (was untracked)
   - Updated `README.md` (badges, capabilities matrix, install one-liner, smoke test, manifest verification, openspec/specs/ pointer)

## Open Items Resolved at Archive

- [x] **Spec wording "parameter expansion only" vs `printf -v`** (design open question) — resolved in canonical `engine-security/spec.md` with an interpretation note: `printf -v` retained because it does NOT execute profile content (the security intent), the format string is the literal `%s`, the value is a printf argument, and the key is charset+allowlist validated before the call.
- [x] **Manifest path** (`install-manifest.sha256` vs `manifest.sha256`) — canonical installer spec uses `manifest.sha256` (matches deployed engine and installer).
- [x] **`detect_pkgr` parsing approach** — canonical installer spec mandates grep-based parsing, functionally equivalent to `. /etc/os-release` but safer under `set -euo pipefail`.
- [x] **Smoke test severity** — canonical installer spec documents `--severity=warning` as the canonical severity (engine has known info-level findings).
- [x] **PR2 size overage** — accepted via orchestrator delivery decision (bugfix slice inherently coupled to parser/cleanup code in same PR); documented in `tasks.md` forecast.
- [x] **`tasks.md` T2.4/T2.5/T2.6 missing** — full entries added.
- [x] **`apply-progress.md` T2.6 section missing** — full entry added.

## Open Items Deferred (recommendations for next change)

- **Tag release `v0.1.0`** — both PRs merged, capabilities synced; cut the first semver tag.
- **bats-core scaffolding** — config.yaml still has `strict_tdd: false` because no bash test runner is installed. The 4 executable probes (`tests/parser-probe.sh`, `tests/hidpi-probe.sh`, `tests/pid-path-probe.sh`, `tests/vpn-trim-probe.sh`) are reusable as bats test cases; installing bats-core and wiring a `make test` target would unlock TDD on the next change.
- **Multi-peer EXIT-trap race** (carry from T1.4 discovery) — if a third `rdp-connect` instance starts after the second one's EXIT trap unlinks the PID file the first instance still holds open via fd 200, the third can `exec 200>` a new inode at the same path and bypass the first's lock. Spec scenario "Live lock from a running peer is honored" tests only a single second peer (which works correctly), so this is NOT a spec violation. Real fix: gate the trap `rm` on a `_LOCK_ACQUIRED` flag set only after `flock -n` succeeds. The engine already ships `_LOCK_ACQUIRED` (T2.2) but the trap doesn't currently consult it.
- **Engine info-level shellcheck findings** (SC2059 printf-as-format, SC2012 ls, SC1091 source) — 10 remaining, all info-level, all pre-existing (surfaced by T1.1 extraction). Cosmetic pass recommended for a future cleanup change.

## SDD Cycle Complete

The `baseline-hardening` change has been fully **explored → proposed → specified → designed → tasked → applied (2 chained PRs) → verified (both PRs) → archived**. The canonical capability specs at `openspec/specs/` are now the source of truth for every behavior the deployed engine + installer MUST exhibit.

Ready for the next change.
