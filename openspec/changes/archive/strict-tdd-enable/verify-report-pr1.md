# Verify Report — strict-tdd-enable PR1 (tooling slice)

> **Change**: `strict-tdd-enable` · **Project**: `rdp-connect` · **Slice**: PR1 — Tooling (`pr1/tooling`)
> **Branch**: `pr1/tooling` (6 commits, not pushed) · **Base**: `main`
> **Mode**: Standard (strict_tdd: false — the flip is T3.4 in PR3)
> **Persistence**: openspec (file below) + Engram mirror (topic_key `sdd/strict-tdd-enable/verify-report-pr1`)
> **Date**: 2026-07-21
> **Verifier scope**: T1.1–T1.4 ONLY. PR2 (T2.x) and PR3 (T3.x) are OUT OF SCOPE.

## Status

**partial** — PASS WITH WARNINGS. Ready to merge as PR1; the 4 tooling tasks are contract-complete and structurally clean. PR2 owns the spec-scenario `@test` coverage (T2.6 `harness.bats`); per the launch contract, PR1 only needs to land the tooling that T2.6 will exercise. One new functional bug found (`make smoke` cannot succeed as written — see WARNING W-5); 4 carried-forward open questions remain.

## Executive Summary

All 7 structural checks pass: the Makefile ships the 6 required targets (`test lint install smoke verify-manifest ci`) plus a `help` default goal with correct `.PHONY` and `SHELL := /usr/bin/env bash`; `make lint` exits 0 on the full repo; `make test` exits 127 with a distro install matrix when bats is absent and reports "Found no tests" gracefully when bats is present but `tests/*.bats` is empty (expected transitional state); the GitHub Actions workflow parses as valid YAML and matches every structural assertion the future `harness.bats::ci_workflow_well_formed` will check (push + pull_request to main, ubuntu-latest, 7 apt packages including bats-assert/bats-support, `make ci`, `actions/upload-artifact@v4` with `if: failure()` and `path: tests/`); `tests/test_helper.bash` is `bash -n` clean and `shellcheck --severity=warning` clean; the README "Testing" section covers Arch/Ubuntu-Debian/Fedora with the bats-support/bats-assert source-install pattern and an explicit "dev dependencies only — NOT runtime" note. The 8 spec scenarios in `test-harness-delta.md` are all **TOOLING-READY** (underlying contract met) but **UNTESTED** at runtime — by design, because T2.6 (`harness.bats`) ships in PR2. Per the launch contract this is the expected state for PR1; flagged as "warned" rather than "failed".

The makefile `--help L40 < require_cmd L47` finding is **confirmed by code inspection** of `engine/rdp-connect` — the `--help` short-circuit (L25–41, `exit 0` at L40) fires before `require_cmd xfreerdp3` at L47. **However, a NEW prior-source dependency was found**: the engine's `source "$LIB_FILE"` at **L19** runs before `--help` at L25, and `LIB_FILE` is computed from `$HOME`. This means `make smoke`'s `HOME=$(mktemp -d)` override breaks the engine's lib source before `--help` is reached. See WARNING W-5.

## Artifacts

- `openspec/changes/strict-tdd-enable/verify-report-pr1.md` (this file)
- Engram mirror: topic_key `sdd/strict-tdd-enable/verify-report-pr1`

## Scenarios Verified

Spec: `openspec/changes/strict-tdd-enable/specs/test-harness-delta.md` (3 requirements, 8 scenarios).

| Metric | Value |
|--------|-------|
| passed | 0 |
| warned | 8 (TOOLING-READY — covering `@test` ships in PR2 T2.6) |
| failed | 0 |
| total | 8 |

Per the verify skill: "A spec scenario is compliant only when a covering test passed at runtime." The 8 scenarios have **no covering `@test` yet** because `harness.bats` is T2.6 (PR2). The launch contract explicitly scoped PR1 to "verify the tooling EXISTS and MEETS CONTRACT, even though the bats tests themselves haven't been written yet." Each scenario's underlying tooling was inspected and where possible manually executed; results below.

### Scenario Results

| # | Requirement | Scenario | Tooling Status | Evidence |
|---|---|---|---|---|
| 1 | Makefile entry points | Fresh-clone `make test` passes 46+ cases | ⚠️ TOOLING-READY | `make test` invokes `bats tests/` correctly; verified rc=1 "Found no tests" (expected — no `*.bats` until PR2). `@test` ships in T2.6. |
| 2 | Makefile entry points | `make install` delegates to the installer | ⚠️ TOOLING-READY | `make -n install` → `./install-rdp-framework.sh` only. No other side effect. `@test` ships in T2.6. |
| 3 | Makefile entry points | `make verify-manifest` catches a tampered deployment | ⚠️ TOOLING-READY | Target uses `~/.local/state/rdp/manifest.sha256` (installer path, Q1 spec bug acknowledged). Manifest-existence guard prints "run `make install` first" + exits 1 when manifest absent. `@test` ships in T2.6. |
| 4 | Makefile entry points | shellcheck warnings fail `make lint` | ⚠️ TOOLING-READY | `make lint` runs `shellcheck --severity=warning` over engine + lib + installer + bootstrap + tests/*.{sh,bash}; rc=0 on current clean repo. `@test` ships in T2.6. |
| 5 | Shared test helper | bats < 1.5.0 fails with a clear message | ⚠️ TOOLING-READY | `tests/test_helper.bash:24` calls `bats_require_minimum_version 1.5.0`. Confirmed by direct inspection. `@test` ships in T2.6. |
| 6 | Shared test helper | `setup_test_home` isolates `HOME` | ⚠️ TOOLING-READY | Helper sets `HOME="${BATS_TMPDIR}/home"` + exports + mkdirs. Manually verified via 1-test bats smoke probe: `[ "${HOME}" = "${BATS_TMPDIR}/home" ]` passes when helper is called without command substitution (the spec's T2.6 contract form). NOTE: calling via `$(setup_test_home)` runs in a subshell and the export does not propagate — this is correct bash semantics, not a helper bug. The spec's scenario uses the side-effect form. `@test` ships in T2.6. |
| 7 | CI workflow | CI green on a healthy PR | ⚠️ TOOLING-READY | Workflow parses (PyYAML 1.1 `on:`→bool quirk aside — GitHub Actions uses YAML 1.2 semantics). Triggers: push + pull_request to main ✅. Runner: ubuntu-latest ✅. Steps: checkout@v4, apt installs all 7 packages, `make ci`, upload-artifact on failure ✅. `@test` ships in T2.6. |
| 8 | CI workflow | CI fails on a red test and uploads logs | ⚠️ TOOLING-READY | `actions/upload-artifact@v4` step with `if: failure()`, `path: tests/`, `if-no-files-found: warn` ✅. `@test` ships in T2.6. |

## Structural Checks

| Check | Result | Evidence |
|---|---|---|
| `makefile_targets` | ✅ PASS | All 6 required targets (`test lint install smoke verify-manifest ci`) + `help` default. `.PHONY: help test lint install smoke verify-manifest ci`. `SHELL := /usr/bin/env bash` at L9. `make` (no args) prints help table, rc=0. |
| `make_lint` | ✅ PASS | `make lint` → `shellcheck --severity=warning` over engine + lib + installer + bootstrap + tests/*.{sh,bash}, rc=0. |
| `make_test_graceful_failure` | ✅ PASS | With bats installed (`/home/hbuddenberg/.local/bin/bats` 1.13.0): "Found no tests" rc=1 (expected — no `*.bats` until PR2). With bats hidden (`env -i PATH=/usr/bin:/bin`): prints distro install matrix (Arch/Debian/Fedora/Source) + exits 127. |
| `ci_yaml_valid` | ✅ PASS | PyYAML parses. `name: test`. Triggers `push`+`pull_request` to `main`. `runs-on: ubuntu-latest`. `concurrency` block. Apt installs all 7 packages: `bats bats-assert bats-support shellcheck jq libnotify-bin util-linux`. `make ci` step. `actions/upload-artifact@v4` with `if: failure()`, `path: tests/`, `if-no-files-found: warn`. |
| `test_helper_bash_n` | ✅ PASS | `bash -n tests/test_helper.bash` → rc=0, clean. |
| `test_helper_shellcheck` | ✅ PASS | `shellcheck --severity=warning tests/test_helper.bash` → rc=0. SC2154/SC1090/SC1091/SC2206 disables are scoped and accurate. |
| `readme_section` | ✅ PASS | "Testing" section at L130. Distro matrix: Arch (pacman), Ubuntu/Debian (apt), Fedora (dnf), source. Explicit "**dev dependencies only** — the installer does NOT install them" callout. `make test`/`make lint`/`make ci`/`make smoke` documented. Pointer to `openspec/changes/strict-tdd-enable/` exists (relative link target resolves). |

## Build & Tests Execution

**Build**: ➖ N/A (bash project — no compile step; `bash -n` covered per file under `make_lint`).

**Tests**: ⚠️ 0 passed / 0 failed / 8 awaiting PR2 T2.6 `harness.bats`.

```
$ make test
bats tests/
ERROR: Found no tests. (Try `--allow-empty-suite`?)1..0
make: *** [Makefile:35: test] Error 1
```

This is the **expected transitional state**. PR2's first `.bats` file (T2.2 `parser.bats`) populates the suite. PR1 was never going to have passing `@test`s — that's PR2's job per the chained-PR plan.

**Coverage**: ➖ Not applicable (no `@test`s exist yet).

## Spec Compliance Matrix

Per the verify skill's contract ("A spec scenario is compliant only when a covering test passed at runtime"), all 8 scenarios are technically `UNTESTED`. They are marked `TOOLING-READY` here because the launch contract explicitly scoped PR1 to landing the underlying tooling. See scenario results above.

**Compliance summary**: 0/8 scenarios COMPLIANT (covering `@test` ships in PR2 T2.6) · 8/8 scenarios TOOLING-READY (underlying contract met) · 0/8 FAILING.

## Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| Makefile: 5 targets + ci alias | ✅ Implemented | All present + `help` default + bats-missing guard + manifest guard |
| Makefile: `test` exits non-zero on any failure | ✅ Implemented | Delegates to `bats tests/`; bats exit code propagates |
| Makefile: `lint` excludes `tests/fixtures/` | ✅ Implemented | No `tests/fixtures/` exists yet; glob doesn't include it. PR2 T2.7 narrows `tests/*.sh` glob to `tests/*.bash` |
| Makefile: `install` no other side effect | ✅ Implemented | `./install-rdp-framework.sh` — single recipe line |
| Makefile: `smoke` throwaway HOME + engine parse | ⚠️ Implemented but BROKEN | See W-5 — engine `source "$LIB_FILE"` at L19 runs before `--help` at L25; throwaway HOME breaks the source |
| Makefile: `verify-manifest` sha256sum -c | ✅ Implemented | Uses installer path `~/.local/state/rdp/manifest.sha256` (Q1 spec path mismatch acknowledged) |
| Helper: sources `lib/rdp-common.bash` | ✅ Implemented | `LIB_FILE="${REPO_ROOT}/lib/rdp-common.bash"` via `BATS_TEST_FILENAME` resolution |
| Helper: `bats_require_minimum_version 1.5.0` | ✅ Implemented | L24 |
| Helper: `setup_test_home()` | ✅ Implemented | Sets `HOME="${BATS_TMPDIR}/home"`, exports, mkdirs, prints path |
| Helper: `assert_probes_pass()` | ✅ Implemented | Thin alias to `assert_success` (Q2 redundancy acknowledged) |
| CI: triggers on push + pull_request to main | ✅ Implemented | L17–21 |
| CI: ubuntu-latest | ✅ Implemented | L30 |
| CI: apt install bats + bats-support/bats-assert + etc | ✅ Implemented | L41–43 (PR1 extended the spec's bare `bats` apt install — Q5) |
| CI: runs `make ci` | ✅ Implemented | L46 (NB: spec L77 says "`make test` then `make lint` in that order"; Makefile's `ci: lint test` is opposite order — Q4) |
| CI: upload `tests/` artifact on failure | ✅ Implemented | L48–54, `if: failure()`, `path: tests/` |

## Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| `--severity=warning` on lint | ✅ Yes + deviation noted | Design had no severity; PR1 added `--severity=warning` to match installer's own smoke (README L46) and avoid SC1091/SC2012 info-level noise. |
| `$(wildcard ...)` for tests/*.{sh,bash} | ✅ Yes + deviation noted | Tolerates PR1's transitional state (only one glob populated). PR2 T2.7 MUST narrow this. |
| `help` target + `.DEFAULT_GOAL := help` | ✅ Yes + deviation noted | Without it, `make` no-args runs `test` and fails the launch contract's "make (no args) shows targets". |
| bats-missing guard inside `test` | ✅ Yes + deviation noted | Prints distro matrix, exits 127. |
| Manifest-existence guard in `verify-manifest` | ✅ Yes + deviation noted | "run `make install` first" instead of confusing sha256sum error. |
| Load bats-support + bats-assert | ✅ Yes + deviation noted (Q5) | **Largest design gap.** Design L348–395 omitted these entirely; without them `assert_success` is undefined. Loader searches `$BATS_LIB_PATH` → `/usr/lib/bats` → `~/.local/lib/bats`. |
| `run --separate-stderr` in `parse_env_safe_under_setu` | ✅ Yes + deviation noted | Requires bats 1.5.0+ (the floor set by `bats_require_minimum_version`). |
| `assert_probes_pass` as thin alias | ✅ Yes | Per spec + design, NOT per launch prompt's "takes a bats file name and asserts rc=0" (which would re-invoke bats — nonsensical recursion). Q2 carried forward. |
| apt extended in T1.3 commit (not T1.2 amend) | ✅ Yes | Per work-unit-commits "tell a story" — the dep is introduced by T1.3, so the apt amendment lives in T1.3. |
| `concurrency` block | ✅ Yes + deviation noted | Design had none; PR1 added to cancel in-flight runs. |

## Issues Found

### CRITICAL: None.

No blocking issues for PR1 merge. The 8 UNTESTED scenarios are by design (T2.6 is PR2's job per the chained-PR plan).

### WARNING

- **W-1 (Q1, design L425)** — Spec `test-harness-delta.md` L18/L37 says `verify-manifest` reads `~/.local/share/rdp/MANIFEST.sha256` (uppercase, share/). Installer (`install-rdp-framework.sh:219`) writes `~/.local/state/rdp/manifest.sha256` (lowercase, state/). Makefile follows installer (source of truth). **Recommendation**: amend the spec before T2.6 lands so `harness.bats::make_verify_manifest_detects_tamper` doesn't assert against a path the installer never writes.

- **W-2 (Q2, design L426)** — `assert_probes_pass` is a semantically-redundant alias to bats's built-in `assert_success`. PR1 ships the alias to honor the spec verbatim. **Recommendation**: either amend the spec to drop the name (and remove the alias in PR2), or keep it as documentation sugar. Low priority.

- **W-3 (Q4, new)** — Spec L77 says CI runs "`make test` then `make lint` in that order". Design L13 + Makefile L86 + workflow L46 use `make ci` (= `lint test`, OPPOSITE order). PR1 follows the design + launch prompt. **Recommendation**: reconcile in T2.6 — either amend the spec to match `make ci` (cheap, recommended — lint-first catches syntax errors before spending time on bats), or change `ci: lint test` to `ci: test lint` and update the design.

- **W-4 (Q5, new)** — Design L348–395 omitted bats-support/bats-assert from the helper entirely. PR1 added them (loader + workflow apt extension). Without them, every PR2 `@test` cascades into "command not found" on `assert_success`. **Recommendation**: amend `design.md` post-archive to reflect the loader, or note this in the archive summary.

- **W-5 (NEW — `make smoke` is functionally broken)** — The Makefile's smoke target does `HOME=$$(mktemp -d) ~/.local/bin/rdp-connect --help >/dev/null`. The engine computes `LIB_FILE="$HOME/.local/lib/rdp/rdp-common.bash"` (engine L13) and runs `source "$LIB_FILE"` (engine L19) **BEFORE** the `--help` short-circuit at L25. With a throwaway HOME the lib does not exist, so `source` fails under `set -euo pipefail` and the engine exits non-zero before `--help` is reached. Verified empirically: `HOME=$(mktemp -d) ~/.local/bin/rdp-connect --help` → rc=1 (failure). The design (L224–226, L284) and the Makefile/README comments all repeat the incorrect claim that "`--help` exits 0 at L40 BEFORE require_cmd at L47" — true in isolation, but the engine has an EVEN-EARLIER `source` at L19 that depends on `$HOME`. **Impact**: `make smoke` will always fail; no spec scenario covers smoke directly (T2.6's `@test` list does not include a smoke test), so this slips through silently. **Recommendation**: either (a) drop the `HOME=$(mktemp -d)` override from smoke and match the installer's own smoke at `install-rdp-framework.sh:201–203` (which runs `--help` against the just-installed HOME), (b) symlink/copy the lib into the throwaway HOME before invoking the engine, or (c) refactor the engine to resolve `LIB_FILE` relative to the binary (`${BASH_SOURCE[0]}`) rather than to `$HOME`. Option (a) is the lowest-risk fix and aligns with the installer's existing pattern; the "throwaway HOME" language in the spec was probably copied from the parser-probe idiom and doesn't fit the engine's lib-source requirement.

### SUGGESTION

- **S-1** — Forward note from apply-progress (still valid): PR2 T2.7 MUST narrow the Makefile lint glob from `$(wildcard tests/*.sh) $(wildcard tests/*.bash)` to `$(wildcard tests/*.bash)` once the four probe scripts are deleted. Otherwise the literal unmatched `tests/*.sh` is passed to shellcheck (harmless under `$(wildcard)` returning empty, but the comment in the Makefile will reference files that no longer exist).
- **S-2** — `harness.bats::ci_workflow_well_formed` (T2.6) should assert the workflow installs `bats-assert` + `bats-support` too, not just `bats`. Otherwise the test is weaker than reality and a future PR that drops the assertion libraries would pass CI structural checks while breaking every `@test`.

## Open Questions

| Q | Status | Concrete Recommendation |
|---|---|---|
| Q1 — spec MANIFEST path mismatch | OPEN | Amend `test-harness-delta.md` L18/L37 to `~/.local/state/rdp/manifest.sha256` (lowercase, state/) BEFORE T2.6 lands. Otherwise `harness.bats::make_verify_manifest_detects_tamper` will assert against a path the installer never writes and fail. Cheap spec fix; no code change needed (Makefile already correct). |
| Q2 — `assert_probes_pass` redundancy | OPEN (low) | Either amend the spec to drop the name and remove the alias in PR2, or keep it as syntactic sugar. Either way, T2.6 doesn't need to test the alias itself — `assert_success` parity is enough. |
| Q4 — `make ci` order vs spec | OPEN | Amend spec L77 to "`make ci` (= lint test)" — lint-first is the better convention (catches shellcheck issues before spending CI time on bats). No code change needed. |
| Q5 — bats-assert/bats-support design gap | OPEN | Amend `design.md` post-archive (section "tests/test_helper.bash") to document the loader + search order. OR note this in the archive summary as a known deviation. No code change needed (PR1 already correct). |
| **Q-smoke (NEW, W-5)** — `make smoke` broken | **OPEN — recommend fix in PR2 or PR3** | Drop `HOME=$(mktemp -d)` from `smoke` target; rely on the installer having just put the lib in the real HOME (matches installer's own smoke at `install-rdp-framework.sh:201–203`). Alternatively, add a `make_smoke_works` `@test` to T2.6 so the bug can't recur. This is a real functional bug, not just a doc issue. |

## PR1 Merge Readiness

| Field | Value |
|---|---|
| `pr1_ready_to_merge` | ✅ **true** (with the 5 WARNINGs carried forward to PR2/PR3) |
| `pr1_size_lines` | **351** (Makefile 86 + workflow 54 + README 40 + test_helper 171 = code review surface only; total diff stat 564 includes SDD bookkeeping: apply-progress 197 + tasks delta 16) |
| Within 400-line review budget | ✅ Yes (351 < 400) |
| Rollback | `git revert` PR1's 5 commits (T1.1 → T1.4 + bookkeeping). Chain stays clean — PR2/PR3 not started. |
| CI green forecast | ✅ Yes — `make ci` runs `lint test`; lint is clean; test will report "Found no tests" rc=1 (bats exit), making CI RED until PR2 populates `tests/*.bats`. **This is expected for a tooling-only PR1.** Either (a) merge PR1 with red CI (allowed because the spec scenario `Fresh-clone make test passes 46+ cases` is explicitly a PR2 deliverable), or (b) cherry-pick T2.2 parser.bats (24 tests) into PR1 to make CI green. Recommendation: (a) — the chained-PR plan owns this. |
| Strict TDD | ✅ Off (correct for PR1 — flip is T3.4 in PR3) |
| Branch hygiene | ✅ Branch `pr1/tooling` off `main`, not pushed. 6 commits in dependency order T1.1 → T1.2 → T1.3 → T1.4 → docs × 2. Working tree clean. |

## Commits (dependency order)

```
cead424 docs(sdd): strict-tdd-enable PR1 apply-progress
e2b711a chore(openspec): mark strict-tdd-enable PR1 tasks T1.1-T1.4 complete
8ffd7fd docs(readme): add bats-core distro install matrix + Testing section
e9e71f7 test: add tests/test_helper.bash (lib source, setup_test_home, parse_env_safe_under_setu)
747cfad ci: add GitHub Actions workflow running make ci on ubuntu-latest
a0a597d feat(build): add Makefile with test/lint/install/smoke/verify-manifest targets
```

Dependency order is correct: T1.1 (Makefile) before T1.2 (workflow uses `make ci`); T1.2 before T1.3 (T1.3 amends T1.2's apt install to add `bats-assert bats-support`); T1.3 before T1.4 (README references the helper's loader); bookkeeping last.

## Verdict

**PASS WITH WARNINGS.**

PR1 lands exactly what the chained-PR plan promised: tooling scaffolding that PR2/PR3 plug into. All 7 structural checks pass; the 8 spec scenarios are TOOLING-READY (underlying contract met) with covering `@test`s scheduled for T2.6 in PR2. The launch contract explicitly authorized this state. Five WARNINGs carry forward — four are open questions (Q1/Q2/Q4/Q5) with concrete cheap resolutions documented above, and one is a new functional bug in `make smoke` (W-5/Q-smoke) that should be fixed in PR2 or PR3 but does not block PR1 merge because no spec scenario covers smoke directly.

## Next Recommended

1. Push `pr1/tooling`: `git push -u origin pr1/tooling`
2. Open PR1 targeting `main` (NOT a feature/tracker branch — stacked-to-main plan per tasks.md L35). Suggested body: "PR1/3 — tooling scaffolding for strict-tdd-enable. Lands Makefile + CI + tests/test_helper.bash + README Testing section. The 8 spec scenarios in test-harness-delta.md will be covered by `harness.bats` in PR2 (T2.6); until then `make test` reports 'Found no tests' (expected). CI will be RED on this PR — that's by design; merge anyway per the chained-PR plan, OR cherry-pick T2.2 if a green-CI merge gate is required. Review surface: 351 lines (under the 400-line budget)."
3. After PR1 merges, start PR2 from a fresh branch off updated `main`: `git checkout main && git pull && git checkout -b pr2/bats-migration`. First commit MUST be T2.1 (trim extraction) so T2.5 `vpn-trim.bats` calls the REAL `trim_profile_fields`, not a copy.
4. Resolve Q1 (spec MANIFEST path) BEFORE T2.6 starts writing `harness.bats::make_verify_manifest_detects_tamper`.
5. Resolve Q-smoke (W-5) in PR2 T2.6 OR PR3 — either drop the `HOME=$(mktemp -d)` override or add a `make_smoke_works` `@test`.

## Skill Resolution

`paths-injected` — both skills from the launch prompt's `## Skills to load before work` block were read before any task work:
- `~/.config/opencode/skills/sdd-verify/SKILL.md`
- `~/.config/opencode/skills/_shared/SKILL.md`

Plus shared references read proactively: `_shared/sdd-phase-common.md`, `_shared/persistence-contract.md`, `sdd-verify/references/report-format.md`. No fallback-registry or SKILL: Load path needed.

## Tooling Versions (verifier box)

- shellcheck: `/usr/bin/shellcheck`
- bats-core: `/home/hbuddenberg/.local/bin/bats` 1.13.0 (≥ R1 floor of 1.5.0)
- bats-support + bats-assert: `/home/hbuddenberg/.local/lib/bats/{bats-support,bats-assert}`
- PyYAML: used for workflow structural assertions (1.1 `on:`→bool quirk noted; GitHub Actions uses YAML 1.2 semantics)
