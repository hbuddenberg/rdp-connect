# Apply Progress — strict-tdd-enable (PR1 tooling slice + PR2 bats-migration slice)
> **Change**: `strict-tdd-enable` · **Project**: `rdp-connect` · **Mode**: openspec (engram mirror)
> **Slice**: PR1 — Tooling (`pr1/tooling`, stacked-to-main from `main`)
> **Batch**: 1 (no previous apply-progress — started fresh per launch)
> **Date**: 2026-07-21
> **Strict TDD**: false (flag stays `false`; the flip is T3.4 in PR3 — Standard Mode for this batch)
> **Delivery**: `chained-PRs` · `stacked-to-main` · `size:exception` on PR2 only

## Status

**success** — 4/4 PR1 tasks complete, verified, committed. Ready for `/sdd-verify`.

## Executive Summary

Landed the PR1 tooling slice for `strict-tdd-enable`: a `Makefile` with 6 canonical targets (`help test lint install smoke verify-manifest ci`), a GitHub Actions workflow that runs `make ci` on every push and pull_request against `main`, the shared `tests/test_helper.bash` sourced by every future `*.bats`, and a README "Testing" section with the bats distro install matrix. All four manual verifications pass on the dev box. Total diff vs `main`: **351 lines across 4 files** (under the 400-line review budget).

The largest deviation from the design is in T1.3: the design's helper pseudocode omitted loading of **bats-support** and **bats-assert** (which provide `assert_success` / `assert_output` / `assert_equal` — NOT built-in to bats-core). Without them, the helper's own `assert_probes_pass` cannot work, and PR2's `.bats` files have no assertions. This batch adds a robust loader (searches `$BATS_LIB_PATH` → `/usr/lib/bats` → `~/.local/lib/bats`) and amends the T1.2 workflow's apt install to include `bats-assert bats-support`.

## Commits Made (PR1, `pr1/tooling`)

| sha | task | title | files | Δ lines | manual-verify |
|---|---|---|---|---|---|
| `a0a597d` | T1.1 | `feat(build): add Makefile with test/lint/install/smoke/verify-manifest targets` | `Makefile` | +86 | ✅ `make` shows help, `make lint` exits 0, `make test` (bats missing) exits 127 with install matrix, `make test` (bats present) invokes bats correctly |
| `747cfad` | T1.2 | `ci: add GitHub Actions workflow running make ci on ubuntu-latest` | `.github/workflows/test.yml` | +48 (later +7 via T1.3 amend → net 54) | ✅ YAML parses; structural assertions match the future T2.6 `ci_workflow_well_formed` contract (triggers, runner, 7 apt pkgs, `make ci`, upload-artifact on failure) |
| `e9e71f7` | T1.3 | `test: add tests/test_helper.bash (lib source, setup_test_home, parse_env_safe_under_setu)` | `tests/test_helper.bash` (+171), `.github/workflows/test.yml` (+7) | +178 / -1 | ✅ `bash -n` clean, `shellcheck --severity=warning` clean, 5/5 functional bats smoke tests pass |
| `8ffd7fd` | T1.4 | `docs(readme): add bats-core distro install matrix` | `README.md` | +40 | ✅ "Testing" section rendered, openspec link target exists, no broken section headers |
| `e2b711a` | — | `chore(openspec): mark strict-tdd-enable PR1 tasks T1.1-T1.4 complete` | `openspec/changes/strict-tdd-enable/tasks.md` | +8 / -8 | n/a (bookkeeping) |

## Tasks Completed

- [x] **T1.1** Makefile (6 targets incl. `help` + `ci` alias)
- [x] **T1.2** `.github/workflows/test.yml`
- [x] **T1.3** `tests/test_helper.bash`
- [x] **T1.4** README "Testing" section

## Tasks Remaining (out of scope for this batch)

**PR2 — Bats migration + trim extraction** (`pr2/bats-migration`, ~1080 LOC, `size:exception`):

- [ ] T2.1 `refactor(engine): extract trim_profile_fields into lib/rdp-common.bash` ← FIRST
- [ ] T2.2 `test(parser): migrate parser-probe.sh F1–F24 to tests/parser.bats`
- [ ] T2.3 `test(hidpi): migrate hidpi-probe.sh to tests/hidpi.bats`
- [ ] T2.4 `test(pid-path): migrate pid-path-probe.sh to tests/pid-path.bats`
- [ ] T2.5 `test(vpn-trim): migrate vpn-trim-probe.sh to tests/vpn-trim.bats using extracted trim_profile_fields`
- [ ] T2.6 `test(harness): add tests/harness.bats covering Makefile + CI scenarios`
- [ ] T2.7 `chore(tests): delete legacy *.probe.sh scripts superseded by *.bats`

**PR3 — session_error extraction + security boundary + flip** (`pr3/extraction-flip`, ~200 LOC):

- [ ] T3.1 `refactor(engine): extract extract_session_error into lib/rdp-common.bash`
- [ ] T3.2 `test(cleanup-session): add tests/cleanup-session.bats + fixtures`
- [ ] T3.3 `test(engine-security): add tests/engine-security.bats for trim allowlist + call-site boundary`
- [ ] T3.4 `chore(openspec): flip strict_tdd true and wire testing.* block to bats` ← CANARY
- [ ] T3.5 `docs(readme): add bats test-count badge`

## Verification Evidence (Standard Mode — no TDD cycle table)

### T1.1 — Makefile
- `make` (no args) → prints help table, rc=0
- `make lint` → `shellcheck --severity=warning` over engine + lib + installer + bootstrap + 4 probe scripts + test_helper.bash, rc=0
- `make test` with bats installed → invokes `bats tests/` (transitional "Found no tests" — expected until PR2 populates the suite), rc=1
- `make test` with bats hidden (`env -i PATH=/usr/bin:/bin`) → prints the distro install matrix and exits 127
- `make -n test|lint|ci` → recipes resolve cleanly

### T1.2 — Workflow
- `python -c 'import yaml; yaml.safe_load(...)'` → parses (note PyYAML 1.1 quirk: `on:` is parsed as boolean `True`; the workflow uses GitHub Actions YAML 1.2 semantics where `on:` is a string)
- Structural assertions (mirror the future T2.6 `ci_workflow_well_formed`): name=test, both triggers to main, ubuntu-latest, checkout@v4, apt installs all 7 packages, `make ci` step, upload-artifact with `if: failure()` and `path: tests/` — all PASS

### T1.3 — Helper
- `bash -n tests/test_helper.bash` → clean
- `shellcheck --severity=warning tests/test_helper.bash` → rc=0 (the `# shellcheck disable=` directives cover SC2154 for bats-injected vars, SC1090/SC1091 for runtime-resolved sources)
- `make lint` → still clean (helper is now in the wildcard glob)
- Functional smoke (`BATS_LIB_PATH=~/.local/lib/bats bats tests/_smoke.bats`) → 5/5 pass:
  1. lib sourced (parse_env_safe is a function)
  2. assert_probes_pass works (proves bats-assert loaded)
  3. setup_test_home isolates HOME under `$BATS_TMPDIR/home`
  4. F14 idiom preserved — HOSTILE key returns rc=1 cleanly under set-u, `_reject` diagnostic on `$stderr`
  5. F14 negative — valid input survives set-u with status=0

### T1.4 — README
- 10 top-level sections, "Testing" sits between "Distro support matrix" and "Specifications"
- Source-install commands for bats-support + bats-assert included (Arch has no bats-assert in pacman)
- Link target `openspec/changes/strict-tdd-enable/` exists
- Existing `tests` badge left untouched (T3.5 owns the badge update)

## Deviations from Design

1. **T1.1 — `--severity=warning` on `lint`** (design L217 had no severity flag).
   Default-severity shellcheck reports info-level codes (SC1091/SC2012/SC2015) that exist in the current clean codebase, so `make lint` would never exit 0. The installer's own smoke step uses `--severity=warning` (README L46); matching it makes lint meaningful. Aligned with the launch prompt's T1.1 verification ("make lint runs shellcheck and exits 0").

2. **T1.1 — `$(wildcard ...)` instead of literal `tests/*.sh tests/*.bash` globs.**
   PR1's transitional state has `tests/*.sh` populated (probe scripts) but no `tests/*.bash` until T1.3. A literal unmatched glob hands the unexpanded string to shellcheck → "file not found". `$(wildcard ...)` expands at make-parse-time and tolerates either glob being empty. **PR2 T2.7 MUST narrow this** to `tests/*.bash` once the probe scripts are deleted.

3. **T1.1 — added `help` target + `.DEFAULT_GOAL := help`** (design had no default goal).
   Without it, `make` with no args runs the first non-`.PHONY` target (`test`), which fails the launch prompt's "make (no args) shows targets" verification.

4. **T1.1 — added bats-missing guard inside `test`** (design had bare `bats tests/`).
   The guard prints the distro install matrix and exits 127, satisfying the launch prompt's "make test fails gracefully if bats not installed (with a clear message)".

5. **T1.1 — `verify-manifest` includes a manifest-existence guard** (design had bare `sha256sum -c`).
   `sha256sum -c` on a missing manifest produces a confusing error; the guard prints "run `make install` first" and exits 1.

6. **T1.3 — loads bats-support + bats-assert** (design L348-395 omitted this entirely).
   This is the largest deviation. The design's helper assumes `assert_success` is built-in to bats — it is NOT. Without the load, `assert_probes_pass` is undefined and every PR2 `.bats` file cascades into "command not found". Loader searches `$BATS_LIB_PATH` → `/usr/lib/bats` → `~/.local/lib/bats` and bails with a clear install hint if not found.

7. **T1.3 — `run --separate-stderr` in `parse_env_safe_under_setu`** (design used bare `run`).
   Without this, `parse_env_safe`'s `_reject` diagnostic (stderr) leaks into `$output` ahead of the `<rc>\t<ok>` line and breaks rc-column parsing. `run --separate-stderr` is a bats 1.5.0+ feature — the floor set by `bats_require_minimum_version 1.5.0` is precisely what makes this flag available.

8. **T1.3 — assert_probes_pass is a thin alias to `assert_success`** (per design + spec, NOT per launch prompt).
   The launch prompt T1.3 described it as "takes a bats file name and asserts rc=0". That would re-invoke bats inside a `@test` (recursion) — nonsensical. Q2 in design.md explicitly raises this for spec amendment; PR1 ships the design+spec form (thin alias).

9. **T1.2 amended in T1.3** — apt install extended to `bats bats-assert bats-support ...`
   The bats-assert dependency is introduced by the T1.3 helper, not by T1.2's workflow. Per work-unit-commits "tell a story", the apt amendment lives in T1.3 (the commit that introduces the dep), not as an amend of T1.2.

10. **T1.2 — added `concurrency` block** (design had none).
    Cancel in-flight runs when a new commit lands on the same ref. Keeps the Actions bill down during active iteration.

## Issues Found

### Open questions raised by this batch (carry forward)

- **Q1 (existing, design L425)** — spec test-harness-delta.md L17-18 says `verify-manifest` reads `~/.local/share/rdp/MANIFEST.sha256` (uppercase). Installer (`install-rdp-framework.sh:219`) and README L65/L101 write `~/.local/state/rdp/manifest.sha256` (lowercase). Makefile follows installer (source of truth). **Action**: amend the spec before `/sdd-verify`.

- **Q2 (existing, design L426)** — `assert_probes_pass` is a redundant alias to `assert_success`. PR1 ships the alias to honor the spec contract verbatim. **Action**: amend the spec or remove the alias in a future change.

- **Q4 (new — workflow spec/design tension)** — spec test-harness-delta.md L74-77 says CI runs "`make test` then `make lint` in that order". Design + launch prompt + this PR1 use `make ci` (= `lint test`, opposite order). PR1 follows the launch prompt + design. **Action**: reconcile in T2.6 — either amend the spec to match `make ci`, or change `ci: lint test` to `ci: test lint` and update the design.

- **Q5 (new — bats-assert / bats-support)** — design L348-395 omitted these entirely from the helper. PR1 added them. **Action**: amend design.md (post-archive edit or in a follow-up) to reflect the loader, OR note this deviation in the archive summary.

### Forward notes for PR2

- **T2.7 MUST narrow the Makefile lint glob** from `$(wildcard tests/*.sh) $(wildcard tests/*.bash)` to just `$(wildcard tests/*.bash)` once the 4 probe scripts are deleted. Otherwise the literal `tests/*.sh` is passed to shellcheck (or $(wildcard) returns empty, harmless — but the comment in the Makefile references the probe scripts which won't exist).

- **T2.6 `harness.bats::ci_workflow_well_formed`** should assert the workflow installs `bats-assert` + `bats-support` too, not just `bats` — otherwise the test is weaker than reality.

- **`make test` in PR1's current state fails with "Found no tests"** (no `*.bats` files exist). This is the expected transitional state. PR2's first `.bats` file (T2.2 parser.bats) populates the suite.

- **bats version on dev box: 1.13.0** (via source install to `~/.local/bin/bats`). ubuntu-latest's `apt install bats` ships bats 1.5.0+ (CI floor met). Local source install of bats-support + bats-assert to `~/.local/lib/bats/`.

## Workload / PR Boundary

- Mode: **chained PR slice** (PR1 of 3)
- Branch: `pr1/tooling` (from `main`)
- Boundary: T1.1 → T1.4 (4 tasks, 5 commits including bookkeeping)
- Actual diff: **351 changed lines** (vs design estimate ~115)
  - Makefile: 86 (est 30) — help target + bats-missing guard + extensive comments
  - Workflow: 54 (est 30) — bats-apt extension + concurrency + comments
  - Helper: 171 (est 55) — bats-assert loader (~50 lines) + extensive comments
  - README: 40 (est 30) — bats-assert + bats-support matrix
- Review budget impact: **within 400-line budget**. No `size:exception` triggered.
- Rollback: `git revert` PR1 (5 commits). PR2 + PR3 are not yet started; the chain stays clean.

## Bats Installation Record (dev box)

`sudo pacman -S bats` per the launch prompt could NOT be executed non-interactively (`sudo: a password is required`). Fell back to a user-local source install — same effect, no privileges needed:

```bash
# bats-core 1.13.0 → ~/.local/bin/bats
cd /tmp/opencode && rm -rf bats-core && \
  git clone --depth 1 https://github.com/bats-core/bats-core && \
  cd bats-core && ./install.sh ~/.local

# bats-support + bats-assert → ~/.local/lib/bats/{bats-support,bats-assert}
cd /tmp/opencode && \
  git clone --depth 1 https://github.com/bats-core/bats-support && \
  git clone --depth 1 https://github.com/bats-core/bats-assert && \
  mkdir -p ~/.local/lib/bats && mv bats-support bats-assert ~/.local/lib/bats/
```

For future sessions: `export BATS_LIB_PATH=/home/hbuddenberg/.local/lib/bats` when running bats locally.

**`bats_installed_on_dev`: true** (via source install to `~/.local`, not pacman). bats 1.13.0 ≥ R1 floor of 1.5.0. bats-support + bats-assert also installed locally.

## Skill Resolution

`paths-injected` — all 4 skill paths from the launch prompt's `## Skills to load before work` block were read before any task work:
- `~/.config/opencode/skills/sdd-apply/SKILL.md`
- `~/.config/opencode/skills/_shared/SKILL.md`
- `~/.config/opencode/skills/work-unit-commits/SKILL.md`
- `~/.config/opencode/skills/chained-pr/SKILL.md`

Plus shared references read proactively: `_shared/sdd-phase-common.md`, `_shared/openspec-convention.md`. No fallback-registry or SKILL: Load path needed.

## Artifacts

- `Makefile` (new) — T1.1
- `.github/workflows/test.yml` (new) — T1.2 (apt amended in T1.3)
- `tests/test_helper.bash` (new) — T1.3
- `README.md` (modified, +40 lines) — T1.4
- `openspec/changes/strict-tdd-enable/tasks.md` (modified, T1.1-T1.4 marked `[x]`)
- `openspec/changes/strict-tdd-enable/apply-progress.md` (this file)
- Engram mirror: topic_key `sdd/strict-tdd-enable/apply-progress`

## Next Recommended

`/sdd-verify` for PR1 — confirm the 4 tasks meet specs/design/tasks, then push `pr1/tooling` and open PR1 against `main`. After PR1 merges, start PR2 (`pr2/bats-migration` from main) with T2.1 first (trim extraction before the bats migrations that depend on it).

---

## PR2 — bats-migration slice

> **Slice**: PR2 — Bats migration + trim extraction (`pr2/bats-migration`, stacked-to-main from `main` after PR1 merge)
> **Batch**: 2 (APPENDED to PR1 section above — merge protocol: prior PR1 tasks preserved, PR2 tasks added below)
> **Date**: 2026-07-21
> **Strict TDD**: false (flag STILL stays `false`; the flip is T3.4 in PR3 — Standard Mode for this batch)
> **Size**: `size:exception` APPROVED (mechanical 1:1 probe→bats translation; reviewer scans per-file, not per-line)

### Status

**success** — 7/7 PR2 tasks complete, verified, committed. Ready for `/sdd-verify`. **57/57 bats tests pass** (24 parser + 8 hidpi + 6 pid-path + 10 vpn-trim + 9 harness). `make ci` exits 0.

### Executive Summary

Landed the PR2 bats-migration slice for `strict-tdd-enable`: extracted `trim_profile_fields()` into `lib/rdp-common.bash` (T2.1, FIRST per the extraction-before-migration rule), migrated all 4 legacy probe scripts 1:1 into 4 `.bats` files (T2.2-T2.5), added `tests/harness.bats` covering all 8 spec scenarios plus a new `make_smoke_works` regression backstop for the W-5 fix from PR1 (T2.6), then deleted the 4 probe scripts and narrowed the Makefile lint glob (T2.7). 7 task commits + 1 docs commit.

The migration was mechanical per design.md `Decision: migration_pattern`. Three discoveries during the migration drove three documented deviations from the design pseudocode (all below). The most significant: a classic bash gotcha where `declare -A` at file scope of a sourced file creates a LOCAL array when the source happens inside a function — the engine sources the lib at top level (no issue), but bats's `load test_helper` chain sources it inside a bats-injected function frame, so the `_PROFILE_KEYS` allowlist was empty by the time @test bodies ran. Fixed by changing `declare -A` to `declare -gA` in `lib/rdp-common.bash` (a no-op for the engine; the standard fix for libs sourced from both top-level and function contexts).

Total diff vs `main`: **+913 / −562 across 33 files touched** (24 parser.bats + 145 hidpi.bats + 109 pid-path.bats + 159 vpn-trim.bats + 257 harness.bats + 8 fixtures × ~10 LOC + 8 snapshots × 7 LOC + lib change + engine trim refactor + Makefile lint glob narrowing + 4 probe deletions + tasks.md marks). Above the 400-line budget; `size:exception` per launch prompt (mechanical migration, reviewer scans per-file).

### Commits Made (PR2, `pr2/bats-migration`)

| sha | task | title | files | Δ lines | manual-verify |
|---|---|---|---|---|---|
| `6689502` | T2.1 | `refactor(engine): extract trim_profile_fields into lib/rdp-common.bash` | `lib/rdp-common.bash`, `engine/rdp-connect`, `tests/vpn-trim-probe.sh` | +79 / −29 | ✅ vpn-trim-probe 8/8 PASS using extracted fn; parser/hidpi/pid-path probes unchanged; `make lint` rc=0 |
| `46b9231` | T2.2 | `test(parser): migrate parser-probe.sh F1-F24 to tests/parser.bats` | `tests/parser.bats` | +236 | ✅ bats tests/parser.bats → 24/24 PASS |
| `fdfad55` | T2.3 | `test(hidpi): migrate hidpi-probe.sh to tests/hidpi.bats` | `tests/hidpi.bats` | +145 | ✅ bats tests/hidpi.bats → 8/8 PASS |
| `39431a1` | T2.4 | `test(pid-path): migrate pid-path-probe.sh to tests/pid-path.bats` | `tests/pid-path.bats` | +109 | ✅ bats tests/pid-path.bats → 6/6 PASS |
| `f39f563` | T2.5 | `test(vpn-trim): migrate vpn-trim-probe.sh to tests/vpn-trim.bats using extracted trim_profile_fields` | `lib/rdp-common.bash` (declare -gA fix), `tests/vpn-trim.bats`, 8× `tests/fixtures/vpn-trim/*.env`, 8× `tests/fixtures/vpn-trim/__snapshots__/*.txt` | +305 / −1 | ✅ bats tests/vpn-trim.bats → 10/10 PASS; 4 probes still pass (lib change preserves engine behavior) |
| `6812d83` | T2.6 | `test(harness): add tests/harness.bats covering Makefile + CI scenarios` | `tests/harness.bats` | +257 | ✅ bats tests/harness.bats → 9/9 PASS; `bats tests/` → 57/57 PASS |
| `33066c6` | T2.7 | `chore(tests): delete legacy *.probe.sh scripts superseded by *.bats` | `Makefile`, DELETE `tests/{parser,hidpi,pid-path,vpn-trim}-probe.sh` | +7 / −562 | ✅ `make ci` rc=0; 57 bats cases pass |
| (this commit) | — | `docs(sdd): PR2 apply-progress update` | `openspec/changes/strict-tdd-enable/{apply-progress.md,tasks.md}` | +this | n/a (bookkeeping) |

### Tasks Completed (cumulative — includes PR1)

PR1 (already complete from prior batch):
- [x] **T1.1** Makefile (6 targets incl. `help` + `ci` alias)
- [x] **T1.2** `.github/workflows/test.yml`
- [x] **T1.3** `tests/test_helper.bash`
- [x] **T1.4** README "Testing" section

PR2 (this batch):
- [x] **T2.1** Extract `trim_profile_fields` into `lib/rdp-common.bash` (FIRST)
- [x] **T2.2** `tests/parser.bats` (24 @test)
- [x] **T2.3** `tests/hidpi.bats` (8 @test)
- [x] **T2.4** `tests/pid-path.bats` (6 @test)
- [x] **T2.5** `tests/vpn-trim.bats` (10 @test) + 8 fixtures + 8 snapshots + lib `declare -gA` fix
- [x] **T2.6** `tests/harness.bats` (9 @test — 8 spec + make_smoke_works)
- [x] **T2.7** Delete 4 probe scripts + narrow Makefile lint glob

### Verification Evidence (Standard Mode — no TDD cycle table)

#### T2.1 — trim extraction (FIRST commit)
- `bash tests/vpn-trim-probe.sh` → 8/8 PASS via the EXTRACTED `trim_profile_fields` (probe now sources lib and calls production fn; pre-inits the 5 globals to satisfy the caller contract under `set -euo pipefail`)
- `bash tests/{parser,hidpi,pid-path}-probe.sh` → 24/8/6 PASS (lib change preserves engine behavior)
- `make lint` → rc=0 (SC2034 disable scoped to the 2 pre-init lines in vpn-trim-probe.sh; indirect access via `${!_field}` is invisible to shellcheck by design)
- `bash -n engine/rdp-connect` → clean
- Engine call site is a one-line `trim_profile_fields` invocation; the inline parameter-expansion idiom no longer appears at the post-parse call site (reinforces engine-security-delta R1; tested directly in PR3 T3.3).

#### T2.2 — parser.bats
- `bats tests/parser.bats` → 24/24 PASS (matches the 24/24 probe baseline)
- Pattern: every case uses `assert_success` (child bash inside `parse_env_safe_under_setu` ALWAYS exits 0 — it catches parse_env_safe's rc internally and prints `<rc>\t<ok>`; the <ok> sentinel proves set -u survived). Rejection is signaled by the rc column being "1", NOT by `$status`. F14 (load-bearing set-u test) asserts all 4 clauses: child OK + parse rc=1 + <ok> present + $stderr does NOT contain "unbound variable".

#### T2.3 — hidpi.bats
- `bats tests/hidpi.bats` → 8/8 PASS (5 spec + 3 robustness, matches probe baseline)
- Mock strategy: function-shadow `hyprctl` (printf JSON) + function-shadow `log_event` (capture WARN lines into per-test `warn_lines` array via dynamic scoping).

#### T2.4 — pid-path.bats
- `bats tests/pid-path.bats` → 6/6 PASS (matches probe baseline)
- Mock strategy: function-shadow `id` (echoes $FAKE_UID); S3/S4 re-mock id with a second uid inside the @test body to assert two-user non-collision.

#### T2.5 — vpn-trim.bats + fixtures + snapshots + lib fix
- `bats tests/vpn-trim.bats` → 10/10 PASS (8 fixture-driven + byte-identical approval test + has_unit_coverage meta-test)
- Snapshots generated by running the REAL `parse_env_safe` + `trim_profile_fields` against each fixture — byte-identical to production BY CONSTRUCTION.
- 3 spec scenarios from `engine-robustness-delta.md` "trim_profile_fields() extraction preserves byte-identical behavior" all covered: whitespace-only `VPN_CHECK` (F2/F3/F4), surrounding-whitespace `HOST` (F5/F7), padded `PASS_RDP`/`USER_RDP` exclusion (F5/F7/F8).

#### T2.6 — harness.bats
- `bats tests/harness.bats` → 9/9 PASS (8 spec scenarios + `make_smoke_works`)
- All 8 spec scenarios in `test-harness-delta.md` now COMPLIANT (covering @test passed at runtime). Promotes PR1's 8 TOOLING-READY scenarios to COMPLIANT.
- `make_smoke_works` exercises the W-5 fix from PR1 verify-report (engine's --help block moved before mkdir+source so the throwaway-HOME invocation succeeds). Fix is in main via `a5ec6fb`; this test is the regression backstop.

#### T2.7 — probe cleanup + Makefile glob narrowing
- `make lint` → rc=0 (lint glob now correctly picks up only `tests/test_helper.bash` in the tests/ tree)
- `make test` → 57/57 PASS (24 parser + 8 hidpi + 6 pid-path + 10 vpn-trim + 9 harness)
- `make ci` → rc=0
- Installer's own inline parser-probe (`install-rdp-framework.sh:206`) unchanged — does NOT reference the deleted tests/*-probe.sh files.

### Deviations from Design (PR2 batch)

1. **T2.5 — `declare -gA` instead of `declare -A` in lib/rdp-common.bash** (design pseudocode implied plain `declare -A`).
   This is the most consequential deviation. Classic bash gotcha: `declare -A` at file scope of a sourced file creates a LOCAL array when the source happens inside a function. The engine sources the lib at top level (no issue), but bats's `load test_helper` → `test_helper.bash` → `source "$LIB_FILE"` chain runs inside a bats-injected function frame; plain `declare -A` would scope `_PROFILE_KEYS` locally to that frame, the allowlist would be empty by the time @test bodies run, and `parse_env_safe` would reject every key. `-g` forces global scope regardless of source depth. The change is a no-op for the engine (top-level `declare -A` and `declare -gA` are equivalent) and is the standard fix for libs sourced from both top-level and function contexts. Discovered while writing the FIRST .bats file that calls `parse_env_safe` in-process (`vpn-trim.bats`); `parser.bats` uses the child-bash helper so didn't expose the issue.

2. **T2.2 — `assert_success` + rc-column check, not `assert_failure`** (design migration-pattern table implied assert_failure for reject cases).
   Design L75–83's mapping table suggests `assert_failure` for reject cases. But the child bash inside `parse_env_safe_under_setu` ALWAYS exits 0 — it catches `parse_env_safe`'s rc internally and prints `<rc>\t<ok>` to stdout (the <ok> sentinel proves set -u survived past the parser). Rejection is signaled by the rc column (`${lines[0]%$'\t'*}`) being "1", not by `$status`. Every case uses `assert_success` + explicit rc check; F14 (the load-bearing set-u test) follows the same pattern with 4 assertion clauses. The design's table is correct in spirit (asserting rejection); the mechanics differ because the helper wraps the call in a child bash that itself succeeds.

3. **T2.2 — `[[ "$stderr" == ... ]]` instead of `assert_output --partial`** for stderr diagnostics (F20, F21).
   Design L75–83's mapping table suggested `assert_output --partial "unexpected content after closing quote"` for `expect_rc_msg` cases. But the helper uses `run --separate-stderr` (bats 1.5.0+), so the `_reject` diagnostic lands in `$stderr` (string), NOT `$output` (which holds `<rc>\t<ok>` on stdout). `assert_output` asserts on `$output` and would always fail. Used `[[ "$stderr" == *"<diagnostic>"* ]]` instead — same intent, correct mechanism.

4. **T2.6 — `make_install_delegates_to_installer` uses sandbox+`make -C`, not a PATH shim** (spec L33 said "spy via PATH shim").
   The Makefile's recipe is `./install-rdp-framework.sh` (relative path with `./` prefix — a security measure that defeats PATH lookup). A PATH shim cannot intercept this. Sandbox pattern: copy Makefile to `$BATS_TMPDIR/install-sandbox`, write a spy `install-rdp-framework.sh` there, run `make -C <sandbox> install`. The `-C` makes the recipe's `./` resolve against the sandbox's spy without touching the real installer in the repo root. Equivalent semantics to the spec's PATH-shim intent (assert the installer is invoked exactly once with no other side effect).

5. **T2.6 — `make_lint_fails_on_shellcheck_warning` uses SC2034, not SC2086** (spec L46 said "injected SC2086 warning").
   SC2086 (unquoted `$var` expansion) is **info-level** under shellcheck's severity model. The Makefile's `lint` target uses `--severity=warning` (per PR1 deviation note 1), which filters out SC2086. The fixture wouldn't trigger a failure. SC2034 (variable assigned but never used) IS warning-severity and triggers the failure the spec scenario expects. Same intent (warning-severity finding fails lint); correct code for the actual lint configuration.

6. **T2.6 — `make_test_passes_46_plus_cases` needs a recursion guard** (not in design).
   This @test invokes `make test`, which runs `bats tests/`, which loads `harness.bats`, which runs THIS TEST — infinite recursion without intervention. Added `HARNESS_RECURSION_GUARD` env var: top-level run sets it; the child's re-run sees it set and `skip`s (bats's `skip` emits "ok" TAP lines, so the parent's count still includes them).

7. **T2.6 — `make_smoke_works` is an ADDITIONAL @test** (not in spec; launch prompt requested it).
   W-5 fix from PR1 verify-report needed a regression backstop. The smoke scenario is not in the test-harness-delta spec; the launch prompt explicitly asked for it as a NEW @test. Documented in commit body as covering W-5.

### Issues Found

#### Open questions resolved by this batch (from PR1 carry-forward)

- **Q1 — spec MANIFEST path mismatch**: W-1 still OPEN. The Makefile follows the installer (`~/.local/state/rdp/manifest.sha256`, lowercase); the spec says `~/.local/share/rdp/MANIFEST.sha256` (uppercase). T2.6 `make_verify_manifest_detects_tamper` deploys to `setup_test_home` and writes the manifest at the INSTALLER's path (lowercase) — the @test passes because it matches reality. The spec bug is unresolved but does NOT block PR2 because the @test follows the installer. **Action remains**: amend `test-harness-delta.md` L18/L37 before `/sdd-verify` final sign-off, OR update the spec scenario text to match.

- **Q4 — `make ci` order vs spec**: W-3 still OPEN. T2.6 `ci_workflow_well_formed` asserts the workflow runs `make ci` (= `lint test`), matching the workflow file and design. Spec L77 says "`make test` then `make lint` in that order" — opposite order. The @test is correct (asserts reality); the spec is wrong. **Action remains**: amend `test-harness-delta.md` L77 to "`make ci` (= lint test)" before `/sdd-verify`.

- **Q-smoke — `make smoke` broken (W-5)**: **RESOLVED in PR1** via `a5ec6fb` (engine --help block moved before mkdir+source, committed to `pr1/tooling` and merged to main as part of PR1). T2.6 `make_smoke_works` is the regression backstop. The smoke target now succeeds on a fresh install. Marking Q-smoke RESOLVED.

#### New open notes for PR3

- **T3.3 `engine-security.bats::engine_calls_trim_profile_fields_not_inline`** should `grep` engine/rdp-connect for the inline `${VAR#"${VAR%%...` idiom and assert it's GONE from the post-parse call site. T2.1 already did the extraction; T3.3 is the @test backstop. Easy to write now that T2.1 is in `main`.

- **PR3's `cleanup-session.bats` and `engine-security.bats` will need their own `declare -gA` audit** if they declare any new associative arrays. The lib fix in T2.5 only covered `_PROFILE_KEYS`; if T3.1 adds new arrays, they need the same `-g` flag.

### Workload / PR Boundary

- Mode: **chained PR slice (size:exception)** — PR2 of 3
- Branch: `pr2/bats-migration` (from `main` after PR1 merged)
- Boundary: T2.1 → T2.7 (7 task commits + 1 docs commit)
- Actual diff: **+913 / −562 across 33 files touched** (vs design estimate ~1080 changed LOC)
  - parser.bats: +236 (est ~290) — 24 compact @test blocks, no loop-style tests
  - hidpi.bats: +145 (est ~140)
  - pid-path.bats: +109 (est ~95)
  - vpn-trim.bats: +159 (est ~155) — slightly larger due to thorough comments per case
  - harness.bats: +257 (est ~110) — significantly larger due to sandbox+spy patterns and per-test cleanup
  - 8 fixtures × ~10 LOC + 8 snapshots × 7 LOC = ~135
  - lib change (declare -gA): ~+10 net
  - engine trim refactor: ~+11 / −12 net (comment block expanded)
  - vpn-trim-probe.sh source-lib update: ~+30 net (was thrown away in T2.7)
  - Makefile lint glob narrowing: ~+7 / −10 net
  - 4 probe deletions in T2.7: −552
- Review budget impact: **ABOVE 400-line budget** — `size:exception` per launch prompt (mechanical 1:1 probe→bats translation; reviewer scans per-file, not per-line). The deletion in T2.7 alone is −552 LOC; the migrations are net +913 of NEW test surface. The "real" review load is the 5 .bats files (~810 LOC of mechanical translation) plus the 25-LOC lib extraction.
- Rollback: `git revert` PR2's 8 commits (T2.1 → T2.7 + docs). The chain stays clean — PR3 has not started. Reverting PR2 alone restores the pre-migration state (PR1 tooling + 4 legacy probes).

### Total Bats Count

**57 bats @test blocks passing on a fresh clone:**

| File | @test count |
|------|-------------|
| `tests/parser.bats` | 24 |
| `tests/hidpi.bats` | 8 |
| `tests/pid-path.bats` | 6 |
| `tests/vpn-trim.bats` | 10 |
| `tests/harness.bats` | 9 |
| **PR2 total** | **57** |

PR3 will add `cleanup-session.bats` (6) + `engine-security.bats` (2) = 65 total post-PR3.

### Skill Resolution

`paths-injected` — all 5 skill paths from the launch prompt's `## Skills to load before work` block were read before any task work:
- `~/.config/opencode/skills/sdd-apply/SKILL.md`
- `~/.config/opencode/skills/_shared/SKILL.md`
- `~/.config/opencode/skills/work-unit-commits/SKILL.md`
- `~/.config/opencode/skills/chained-pr/SKILL.md`
- `~/.config/opencode/skills/go-testing/SKILL.md` (REVIEW ONLY — table-driven test pattern reference; mapped to bats fixture-driven cases)

### Next Recommended

`/sdd-verify` for PR2 — confirm the 7 tasks meet specs/design/tasks (especially the 8 spec scenarios in test-harness-delta.md moving from TOOLING-READY to COMPLIANT, and the 3 trim scenarios in engine-robustness-delta.md gaining @test parity). Then push `pr2/bats-migration` and open PR2 against `main`. After PR2 merges, start PR3 (`pr3/extraction-flip` from main) with T3.1 first (extract_session_error extraction before its tests). The flip (T3.4) is LAST — canary.
