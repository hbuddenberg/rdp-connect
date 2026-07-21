# Proposal: strict-tdd-enable

> **Change**: `strict-tdd-enable` · **Project**: `rdp-connect` (Bash, v0.1.0, public) · **Mode**: openspec (engram mirror) · **Date**: 2026-07-21
> **Dependency**: `openspec/changes/strict-tdd-enable/explore.md` · Engram `sdd/strict-tdd-enable/explore` (obs #245)

## Intent

Flip `openspec/config.yaml` `strict_tdd: false → true` so every future SDD change to rdp-connect MUST follow `strict-tdd.md` (red-green-refactor). To give the flag teeth: install bats-core as a dev dependency, migrate the existing 46 probe cases (4 files, ~530 LOC) to bats, extract two pure functions from the engine into `lib/rdp-common.bash` for unit coverage, and add CI + a Makefile entry point.

## Scope

### In Scope
- bats-core dev dependency (distro matrix in README; **not** a runtime/installer dep)
- `tests/*.probe.sh` → `tests/*.bats` (4 files, 46 cases, 1:1 mechanical) + shared `tests/test_helper.bash`
- Extract `trim_profile_fields()` (engine L174–181) and `extract_session_error()` (cleanup L248–254) into lib
- Flip **both** config keys: top-level `strict_tdd` AND `rules.apply.tdd` (L56)
- Update `testing.*` block (runner/framework/unit → `bats` / `bats-core`)
- `.github/workflows/test.yml` (ubuntu-latest, `make test` + shellcheck)
- `Makefile` — 5 targets: `test`, `lint`, `install`, `smoke`, `verify-manifest`

### Out of Scope
- New product features; selector / wofi / xfreerdp3 behavior unchanged
- Engine-wide refactor — only the two minimum extractions above
- Changing probe assertions or logic (migration is 1:1)
- Mocking `/dev/tcp`, `flock`, `xfreerdp3` (stay manual / integration)
- Adding bats to `install-rdp-framework.sh` F10 runtime deps (dev-only)
- `load_language_or_return()` extraction (defer until a change targets i18n)
- Installer scenario automation (needs a `--dry-run` flag — separate change)

## Capabilities

> Verified against `openspec/specs/`: `engine-robustness`, `engine-security`, `hidpi-scaling`, `installer`, `instance-locking`. **No `sdd-config` spec exists; no `test-harness` spec exists.**

### New Capabilities
- `test-harness`: bats-core suite + `test_helper.bash` + `Makefile` + CI workflow. The contract surface for `make test` / `bats tests/` referenced post-flip by `rules.apply.test_command`.

### Modified Capabilities
- `engine-robustness`: the 3 preflight-trim + 4 cleanup-session-isolation scenarios (today manual-verify or tested-by-copy) become real bats unit tests via `trim_profile_fields()` and `extract_session_error()`.
- `engine-security`: parser consumers of the trim step now call the extracted `trim_profile_fields()` (behavior identical; spec delta documents the lib move, not new behavior).

> The `strict_tdd` flip is a `config.yaml` change, **not** a spec-level capability. No `sdd-config` spec exists, so it is tracked under **Affected Areas** rather than as a capability delta. (If the project later adds an `sdd-config` spec, the flip should migrate there.)

## Approach

**Approach A (recommended) — 3-PR stacked-to-main chain.** Each slice is independently mergeable and revertable. PR1 lands tooling with the flag still `false`; PR2 fills the harness with migrated cases; PR3 flips both keys so strict-tdd enforces something real.

**Approach B (fallback only) — single PR with `size:exception`.** Used only if a later phase reveals the split is artificial. Carries reviewer-fatigue risk on the ~1080-line migration slice.

F3 extraction ships in PR3 (after migration) specifically to kill the `vpn-trim-probe.sh` test smell — strict-tdd verify would otherwise flag "approval test exercises copy, not production code."

## Delivery Strategy

`chained-PRs` · `stacked-to-main` · `size:exception` on PR2.

| PR | Scope | Findings | Surface | Risk |
|---|---|---|---|---|
| PR1 `tooling` | Makefile + CI + README distro matrix | F1 + F5 + F6 | ~115 LOC | Low |
| PR2 `bats-migration` | `test_helper.bash` + 4 probe→bats; delete old `*.probe.sh` | F2 | ~1080 LOC | Medium |
| PR3 `extraction-flip` | 2 lib extractions + new bats cases + **both-key flip** + `testing.*` block + README badge | F3 + F4 | ~200 LOC | Medium |

**PR2 `size:exception` rationale:** mechanical 1:1 translation, no logic change; reviewer scans per-probe-file (4 files), not per-line. PR3 carries the only behavior change (small refactor) plus the canary flip.

## Affected Areas

| Area | Impact | Change |
|---|---|---|
| `openspec/config.yaml` | Modified | `strict_tdd`, `rules.apply.tdd` flip; `testing.*` block updated |
| `tests/*.bats` + `test_helper.bash` | New | 4 migrated files + helper |
| `tests/*.probe.sh` | Removed | deleted post-migration |
| `lib/rdp-common.bash` | Modified | +`trim_profile_fields`, +`extract_session_error` |
| `engine/rdp-connect` | Modified | trim loop + `cleanup()` now delegate to lib (behavior preserved) |
| `.github/workflows/test.yml` | New | ubuntu-latest, `make test` + shellcheck |
| `Makefile` | New | 5 targets |
| `README.md` | Modified | bats distro matrix + badge count |

## Risks

| ID | Risk | L | Mitigation |
|---|---|---|---|
| R1 | bats version skew (Arch 1.13.0 vs Ubuntu 20.04 1.1.0) | Med | `bats_require_minimum_version 1.5.0` atop each `.bats`; CI on ubuntu-latest clears the bar |
| R2 | strict_tdd over-ceremonies small fixes | Med | Use strict-tdd.md escape valve `"Triangulation skipped: {reason}"`; record in `rules.apply.escape_valves_used` |
| R3 | hyprctl / xfreerdp3 mocks drift from real behavior | Med | Extract-Before-Mock rule — mock PURE LOGIC only; engine integration paths stay manual-verify |
| R4 | F3 extraction subtly changes engine behavior | Low | Probe parity check — same 46 cases pass before AND after extraction (approval-test current output first) |
| R5 | PR2 size:exception (~1080 LOC) = 2.7× the 400-line budget | Med | Mechanical 1:1; reviewer scans per-file (4 files), not per-line |
| R6 | Two-key flip (L20 + L56) — silent no-op if only one flips | **High** | PR3 task includes grep assertion that BOTH keys are `true` post-flip; rollback restores both |

## High-Risk Callouts

- **F4 (two-key flip)** — silent no-op if only one key flips; hardest to catch in review. Mitigated by R6.
- **F3 (engine extraction)** — the only slice that changes engine behavior. Approval-test current trim/cleanup output before refactoring; assert parity. Mitigated by R4.
- **F2 (size:exception)** — ~1080 LOC migration slice; review-burden risk. Mitigated by mechanical per-file scan (R5).

## Rollback Plan

`git revert` the merge commits in **reverse order**: PR3 → PR2 → PR1. The canary is `strict_tdd` returning to `false`. If a future change fails strict-tdd verify catastrophically, reverting PR3 alone restores the pre-strict regime while leaving the bats harness in place (PR1 + PR2 are harmless without the flip). The installer is idempotent and never touched — deployed users are unaffected at every step.

## Dependencies

- bats-core installed on dev host (distro matrix lands in README via F1) — prerequisite for local `make test`
- `openspec/changes/strict-tdd-enable/explore.md` (obs #245) — source of all verified claims

## Success Criteria

- [ ] `make test` runs 46+ bats cases green on a clean clone with bats installed
- [ ] `.github/workflows/test.yml` is green on a PR against `main`
- [ ] `grep -c '^strict_tdd: true' openspec/config.yaml` = 1 **AND** `grep -c 'tdd: true' openspec/config.yaml` ≥ 1 (both keys flipped)
- [ ] All 46 migrated cases pass before AND after F3 extraction (parity)
- [ ] No change to deployed `engine/rdp-connect` behavior for end users (installer smoke-test unchanged)
- [ ] The next SDD change's strict-tdd verify finds a populated TDD Evidence table — not "no test runner found"
