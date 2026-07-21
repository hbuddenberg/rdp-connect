# Verification Report — strict-tdd-enable (PR2 bats-migration slice)

> **Change**: `strict-tdd-enable` · **Project**: `rdp-connect`
> **Slice**: PR2 — Bats migration + trim extraction (`pr2/bats-migration`)
> **Branch**: `pr2/bats-migration` (8 commits, not pushed)
> **Base**: `main` (post-PR1-merge, tip `2b07024`)
> **Mode**: Standard (Strict TDD `false` — flag stays `false` until T3.4 in PR3)
> **Date**: 2026-07-21
> **Verifier**: sdd-verify executor (glm-5.2)

## Section A — Status

**status**: **pass**

**executive_summary**:
PR2 lands 7/7 tasks (T2.1–T2.7) with all 57 bats @test blocks passing on the dev box and `make ci` exiting 0. All 8 test-harness-delta spec scenarios move from TOOLING-READY (PR1) to COMPLIANT via covering @test in `tests/harness.bats`. The 3 preflight-trim scenarios in engine-robustness-delta gain @test parity via `tests/vpn-trim.bats` (8 fixture-driven + 2 meta-tests). The engine-security-delta "trim allowlist" scenario is COMPLIANT via `vpn-trim.bats::F8`; the "Parser consumers call trim_profile_fields, not inline" scenario is correctly DEFERRED to PR3 T3.3 (out of scope for this slice). Three carry-forward items (Q1 spec MANIFEST path, Q4 make ci order, Q5 bats-loader design gap) remain open and must be amended before archive. **PR2 is ready to merge** with `size:exception` (reviewer scans per-file, not per-line — the migration is mechanical 1:1 probe→bats translation).

**artifacts**:
- File: `openspec/changes/strict-tdd-enable/verify-report-pr2.md` (this file)
- Engram mirror: topic_key `sdd/strict-tdd-enable/verify-report-pr2`

## Section B — Build & Tests Execution

**Build / lint**: ✅ Passed
```text
$ make lint
shellcheck --severity=warning engine/rdp-connect lib/*.bash install-rdp-framework.sh bootstrap.sh \
           tests/test_helper.bash
$ echo $?
0
```

**Tests**: ✅ 57 passed / 0 failed / 0 skipped
```text
$ make ci
... (shellcheck output) ...
bats tests/
1..57
ok 1  make_test_passes_46_plus_cases          (harness.bats)
ok 2  make_install_delegates_to_installer     (harness.bats)
ok 3  make_verify_manifest_detects_tamper     (harness.bats)
ok 4  make_lint_fails_on_shellcheck_warning   (harness.bats)
ok 5  bats_minimum_version_enforced           (harness.bats)
ok 6  setup_test_home_isolates_HOME           (harness.bats)
ok 7  ci_workflow_well_formed                 (harness.bats)
ok 8  ci_workflow_uploads_logs_on_failure     (harness.bats)
ok 9  make_smoke_works                        (harness.bats — W-5 regression backstop)
ok 10-17  S1..S8 compute_dpi_flags cases      (hidpi.bats, 8 tests)
ok 18-41  F1..F23 parse_env_safe cases        (parser.bats, 24 tests)
ok 42-47  S1..S6 compute_pid_path cases       (pid-path.bats, 6 tests)
ok 48-55  F1..F8 trim_profile_fields cases    (vpn-trim.bats, 8 fixture-driven)
ok 56     trim_profile_fields_byte_identical_on_fixtures  (vpn-trim.bats)
ok 57     trim_profile_fields_has_unit_coverage            (vpn-trim.bats)

$ echo $?
0
```

**Coverage**: ➖ Not available (bats has no line-coverage collector; scenario-coverage is the proxy — see Section C).

### Per-file breakdown

| File | @test count | Status |
|------|-------------|--------|
| `tests/parser.bats` | 24 | ✅ 24/24 PASS |
| `tests/hidpi.bats` | 8 | ✅ 8/8 PASS |
| `tests/pid-path.bats` | 6 | ✅ 6/6 PASS |
| `tests/vpn-trim.bats` | 10 | ✅ 10/10 PASS |
| `tests/harness.bats` | 9 | ✅ 9/9 PASS (8 spec + 1 W-5 backstop) |
| **PR2 total** | **57** | ✅ 57/57 PASS |

## Section C — Spec Compliance Matrix

### test-harness-delta (8 scenarios — all COMPLIANT)

| # | Scenario (delta spec) | Covering @test | Result |
|---|-----------------------|----------------|--------|
| 1 | Fresh-clone `make test` passes 46+ cases | `harness.bats::make_test_passes_46_plus_cases` | ✅ COMPLIANT |
| 2 | `make install` delegates to the installer | `harness.bats::make_install_delegates_to_installer` | ✅ COMPLIANT |
| 3 | `make verify-manifest` catches a tampered deployment | `harness.bats::make_verify_manifest_detects_tamper` | ✅ COMPLIANT |
| 4 | shellcheck warnings fail `make lint` | `harness.bats::make_lint_fails_on_shellcheck_warning` | ✅ COMPLIANT |
| 5 | bats < 1.5.0 fails with a clear message | `harness.bats::bats_minimum_version_enforced` | ✅ COMPLIANT |
| 6 | `setup_test_home` isolates `HOME` | `harness.bats::setup_test_home_isolates_HOME` | ✅ COMPLIANT |
| 7 | CI green on a healthy PR | `harness.bats::ci_workflow_well_formed` | ✅ COMPLIANT |
| 8 | CI fails on a red test and uploads logs | `harness.bats::ci_workflow_uploads_logs_on_failure` | ✅ COMPLIANT |

**Note (deviation 4 & 5 in apply-progress)**: scenarios 4 and 2 deviate from the literal spec text (SC2034 fixture instead of SC2086 because `make lint` uses `--severity=warning`; sandbox+`make -C` instead of PATH shim because the Makefile recipe uses `./install-rdp-framework.sh`). Both deviations preserve scenario INTENT and are documented in apply-progress §"Deviations from Design (PR2 batch)" items 4–5. Recommend amending the spec scenarios at archive to reflect the implemented mechanism.

### engine-robustness-delta — 3 preflight-trim scenarios (all COMPLIANT)

The robustness delta spec scenario "All 7 robustness scenarios have @test parity" is split across PR2 (3 trim scenarios) and PR3 (4 cleanup-session scenarios). PR2 covers the trim half:

| Preflight-trim sub-scenario | Covering @test(s) | Result |
|-----------------------------|-------------------|--------|
| whitespace-only `VPN_CHECK` is trimmed | `vpn-trim.bats::F1` (empty), `F2` (single-space), `F3` (multi-space), `F4` (tab-only) | ✅ COMPLIANT |
| surrounding-whitespace `HOST` is trimmed | `vpn-trim.bats::F5`, `F7` | ✅ COMPLIANT |
| padded `PASS_RDP` / `USER_RDP` are NOT trimmed (exclusion invariant) | `vpn-trim.bats::F5`, `F7`, `F8` | ✅ COMPLIANT |

Plus the two meta-scenarios from the same delta:

| Meta-scenario | Covering @test | Result |
|---------------|----------------|--------|
| 8 vpn-trim fixtures pass byte-identical pre/post extraction | `vpn-trim.bats::trim_profile_fields_byte_identical_on_fixtures` | ✅ COMPLIANT |
| @test coverage for `trim_profile_fields()` | `vpn-trim.bats::trim_profile_fields_has_unit_coverage` | ✅ COMPLIANT |

**Note**: the "All 7 robustness scenarios have @test parity" scenario itself remains PARTIAL until PR3 T3.2 ships `cleanup-session.bats` (the 4 cleanup-isolation cases). This is expected and in-scope for PR3, not a PR2 defect.

### engine-security-delta (1 of 2 scenarios COMPLIANT; 1 DEFERRED)

| Scenario | Covering @test | Result |
|----------|----------------|--------|
| `trim_profile_fields()` allowlist is the documented 5 trimmed + 2 excluded | `vpn-trim.bats::F8: all 7 fields padded — 5 trimmed, 2 excluded (comprehensive allowlist)` | ✅ COMPLIANT (covers both halves of the invariant) |
| Parser consumers call `trim_profile_fields()`, not inline trim | _(none — `tests/engine-security.bats` does not exist in PR2)_ | ⏸️ DEFERRED to PR3 T3.3 (`engine_calls_trim_profile_fields_not_inline`) |

**Rationale for the DEFER**: the PR2 scope is bats migration + trim extraction only. The canonical @test for the call-site boundary lands in PR3 T3.3. However, T2.1 already did the structural extraction (engine invokes `trim_profile_fields` as a one-line call at `engine/rdp-connect:182`; no inline `${VAR#"${VAR%%...` idiom remains — see Section D). The @test backstop is what's missing, not the behavior.

### Compliance summary

- **test-harness-delta**: 8/8 scenarios COMPLIANT (was 8/8 TOOLING-READY after PR1)
- **engine-robustness-delta** (trim half): 3/3 preflight-trim sub-scenarios COMPLIANT + 2/2 meta-scenarios COMPLIANT. (The aggregate "All 7 robustness scenarios" scenario is PARTIAL pending PR3.)
- **engine-security-delta**: 1/2 COMPLIANT, 1/2 DEFERRED to PR3 (in scope for that slice)
- **PR2 total**: 14 covering @tests map to spec scenarios; all PASS at runtime.

## Section D — Correctness (Static Evidence)

| Requirement | Status | Notes |
|------------|--------|-------|
| T2.1 `trim_profile_fields` extraction call site | ✅ Implemented | `engine/rdp-connect:182` is a bare `trim_profile_fields` invocation. The `for _field in HOST VPN_CHECK DOMAIN PREFERRED_WS LANG_OVERRIDE` loop lives ONLY in `lib/rdp-common.bash:177-184`. `grep -n "for _field in HOST" engine/rdp-connect` returns no matches. |
| T2.1 inline trim idiom removed from engine | ✅ Implemented | `grep -n '\${VAR#"${VAR%%' engine/rdp-connect` returns no matches. The idiom appears ONLY in `lib/rdp-common.bash:180-181` (the extracted fn). Reinforces engine-security-delta R1. |
| T2.5 `declare -gA` fix in lib | ✅ Implemented | `lib/rdp-common.bash:33` uses `declare -gA _PROFILE_KEYS=(...)` (global associative array). Required because bats's `load test_helper` chain sources the lib inside a function frame; plain `declare -A` would scope locally and the allowlist would be empty by @test time. No-op for the engine (top-level scope). |
| T2.7 Makefile lint glob narrowed | ✅ Implemented | `Makefile:53-55` lint recipe globs `$(wildcard tests/*.bash)` only — `tests/*.sh` is gone (probes deleted). `tests/*.bats` is intentionally excluded (bats DSL is not shellcheck-parseable). Comment block at L48-52 explains why. |
| T2.7 size-exception footer present | ⚠️ SPELLING DEVIATION | T2.7 commit body uses `size-exception:` (hyphen) at the top of the message. The chained-pr skill convention is `size:exception` (colon separator). Flag for awareness; does not block merge — the intent is unambiguous and the apply-progress forecast table uses the canonical `size:exception` form. Recommend the orchestrator amend the commit body before push if reviewer-facing canonical spelling matters. |
| T2.6 `make_smoke_works` regression backstop | ✅ Implemented | `tests/harness.bats:243` exercises the W-5 fix from PR1 (`a5ec6fb`, in `main` via PR1 merge `2b07024`). The @test invokes `make smoke` against a `setup_test_home` throwaway HOME and asserts the engine's `--help` block fires before the mkdir+source dependency chain. |
| Probe scripts deleted (T2.7) | ✅ Implemented | `tests/{parser,hidpi,pid-path,vpn-trim}-probe.sh` are absent. Their content was migrated 1:1 into `tests/{parser,hidpi,pid-path,vpn-trim}.bats` in T2.2-T2.5. |
| PR3 files correctly absent | ✅ Scope honored | `tests/engine-security.bats` and `tests/cleanup-session.bats` do NOT exist on this branch — confirms the slice boundary is respected. |

## Section E — Coherence (Design Decisions)

| Decision (from design.md / tasks.md) | Followed? | Notes |
|--------------------------------------|-----------|-------|
| T2.1 BEFORE T2.5 (extraction-before-migration) | ✅ Yes | Commit `6689502` (T2.1) is the FIRST commit on the branch; `f39f563` (T2.5) is fifth. `vpn-trim.bats` calls the REAL extracted `trim_profile_fields`, not a copy. |
| T2.2-T2.5 BEFORE T2.7 (probes deleted only after .bats supersede them) | ✅ Yes | Commits in dependency order: `46b9231` → `fdfad55` → `39431a1` → `f39f563` → `33066c6` (T2.7). |
| T2.1/T2.2/T2.3/T2.4 BEFORE T2.6 (`make_test_passes_46_plus_cases` needs suite populated) | ✅ Yes | `6812d83` (T2.6) is the 6th commit; suite was already populated by T2.2-T2.5. |
| Migration pattern: mechanical 1:1 probe→bats translation | ✅ Yes | Each .bats case maps to a probe case with the same Given/When/Then. Three documented deviations in apply-progress (declare -gA, assert_success+rc-column instead of assert_failure, `$stderr` match instead of `assert_output --partial` for F20/F21) — all preserve intent. |
| Delivery strategy: stacked-to-main, PR2 = size:exception | ✅ Yes | Branch `pr2/bats-migration` branches from `main` (post-PR1 merge). Target for PR2 is `main`. `size:exception` declared in T2.7 commit body (spelling: hyphen). |

## Section F — Structural Checks

| Check | Result |
|-------|--------|
| `make ci` exits 0 | ✅ rc=0 |
| `make lint` exits 0 | ✅ rc=0 |
| Total bats @test blocks at runtime | ✅ 57 (24+8+6+10+9) |
| `declare -gA` fix present in `lib/rdp-common.bash` | ✅ L33 |
| T2.7 size-exception footer present | ⚠️ Yes, but spelled `size-exception:` (hyphen) instead of canonical `size:exception:` |
| T2.1 extraction call site in engine | ✅ `engine/rdp-connect:182` is a one-line `trim_profile_fields` call; no inline idiom |
| T2.7 Makefile lint glob narrowed to `tests/*.bash` | ✅ `Makefile:55` |

## Section G — Diff Sanity / Review Surface

```text
$ git diff main..HEAD --shortstat
30 files changed, 1292 insertions(+), 577 deletions(-)
```

**Total review surface**: 1869 changed lines (ins + del). **Excluding openspec bookkeeping** (apply-progress.md +179 / tasks.md +38): 28 files, 1099 ins / 553 del = **1652 changed lines of code/tests**. The tasks.md forecast of "~1080 LOC" was insertions-only and an underestimate (apply-progress §"Workload / PR Boundary" reconciles).

**Size budget verdict**: clearly exceeds the 400-line default. `size:exception` is correctly declared in the T2.7 commit body. Reviewer can scan per-file (4 of the 5 `.bats` files are mechanical 1:1 translations of deleted probes — net new logic is the ~25-line `trim_profile_fields` extraction + the `declare -gA` one-character fix + the W-5 backstop test).

### Commit order (8 commits, dependency-honoring)

```
09628f9 docs(sdd): PR2 apply-progress update                          [bookkeeping]
33066c6 chore(tests): delete legacy *.probe.sh scripts superseded by *.bats  [T2.7]
6812d83 test(harness): add tests/harness.bats covering Makefile + CI scenarios  [T2.6]
f39f563 test(vpn-trim): migrate vpn-trim-probe.sh to tests/vpn-trim.bats using extracted trim_profile_fields  [T2.5]
39431a1 test(pid-path): migrate pid-path-probe.sh to tests/pid-path.bats  [T2.4]
fdfad55 test(hidpi): migrate hidpi-probe.sh to tests/hidpi.bats  [T2.3]
46b9231 test(parser): migrate parser-probe.sh F1-F24 to tests/parser.bats  [T2.2]
6689502 refactor(engine): extract trim_profile_fields into lib/rdp-common.bash  [T2.1, FIRST]
```

Order matches the `## Ordering Constraints (verified)` section of tasks.md exactly.

## Section H — Issues Found

### CRITICAL
None.

### WARNING
1. **T2.7 `size-exception:` spelling** — commit footer uses hyphen (`size-exception:`) instead of the chained-pr skill's canonical colon form (`size:exception:`). Intent is unambiguous; does not block merge. Recommend the orchestrator amend the commit message before push if reviewer-facing canonical spelling matters, OR amend the chained-pr skill to accept both forms.
2. **Q1 (carry-forward from PR1)** — spec test-harness-delta.md L18/L37 says `verify-manifest` reads `~/.local/share/rdp/MANIFEST.sha256` (uppercase). Makefile + installer + `harness.bats::make_verify_manifest_detects_tamper` all use `~/.local/state/rdp/manifest.sha256` (lowercase). The @test follows reality (installer is source of truth). **Action**: amend the spec scenario text before `/sdd-archive`.
3. **Q4 (carry-forward from PR1)** — spec test-harness-delta.md L77 says CI runs "`make test` then `make lint` in that order". Makefile + workflow + `harness.bats::ci_workflow_well_formed` use `make ci` (= `lint test`, opposite order). The @test is correct (asserts reality). **Action**: amend the spec scenario text before `/sdd-archive`.
4. **Q5 (carry-forward from PR1)** — design.md L348-395 omitted the bats-assert / bats-support loaders from `test_helper.bash`. PR1 added them (the helper is non-functional without — `assert_success` is NOT built-in to bats-core). **Action**: amend design.md before `/sdd-archive` to reflect the loader, OR document the deviation in the archive summary.

### SUGGESTION
1. **T3.1 carry-forward** — when PR3 extracts `extract_session_error`, any new associative array declared in `lib/rdp-common.bash` MUST use `declare -gA` (same fix as T2.5). The T2.5 fix only covered `_PROFILE_KEYS`. Document this in the PR3 launch prompt.
2. **T3.3 carry-forward** — `tests/engine-security.bats::engine_calls_trim_profile_fields_not_inline` should `grep` engine/rdp-connect for the inline `${VAR#"${VAR%%...` idiom and assert it's gone. T2.1 already did the structural extraction; T3.3 is the @test backstop. Easy to write now that T2.1 is on this branch.
3. **Spec scenario text amendments** — scenarios `make_install_delegates_to_installer` (PATH shim → sandbox+`make -C`) and `make_lint_fails_on_shellcheck_warning` (SC2086 → SC2034) describe mechanisms that differ from the implemented @tests. Both preserve intent. Consider amending the spec scenario text at archive to match the implemented mechanism, OR document the deviations in the archive summary.

## Section I — Carry-Forward for PR3

- **T3.1**: extract `extract_session_error` into `lib/rdp-common.bash`. Apply `declare -gA` to ANY new associative array (the T2.5 pattern). Engine cleanup trap delegates.
- **T3.2**: add `tests/cleanup-session.bats` + 4 fixtures + snapshots. Completes the 4 cleanup-isolation half of the "All 7 robustness scenarios" aggregate scenario.
- **T3.3**: add `tests/engine-security.bats` with 2 @test: `engine_calls_trim_profile_fields_not_inline` (grep-based structural assertion — T2.1 made it pass-by-construction) and `trim_allowlist_is_five_trimmed_two_excluded` (canonical version of F8 — already passing via F8 in PR2).
- **T3.4** (CANARY): flip `strict_tdd: true` in `openspec/config.yaml` + wire `testing.*` block to bats. LAST commit, only after all bats green.
- **T3.5**: README bats test-count badge.
- **Spec amendments before archive**: Q1 (MANIFEST path), Q4 (make ci order), Q5 (bats-loader in design). All non-blocking for PR2 merge.

## Section J — Verdict

**PASS WITH WARNINGS**

PR2 is structurally sound, behaviorally verified (57/57 bats pass, `make ci` rc=0), spec-compliant for its declared scope (8/8 test-harness-delta COMPLIANT, 3/3 trim scenarios COMPLIANT, 1/2 engine-security COMPLIANT with the 1 DEFERRED correctly scoped to PR3 T3.3). Three carry-forward spec amendments (Q1/Q4/Q5) and one commit-footer spelling nit (`size-exception:` vs `size:exception:`) are non-blocking warnings — none prevent merge.

**pr2_ready_to_merge**: **true**

**pr2_size_lines**: **1869** (1292 ins + 577 del, all files) · **1652** excluding openspec bookkeeping · forecast was ~1080 (insertions-only, underestimate).

## Section K — Scenario Tally

- **scenarios_verified.total**: 11 (8 test-harness + 2 robustness meta + 1 engine-security allowlist)
- **scenarios_verified.passed**: 11
- **scenarios_verified.warned**: 0
- **scenarios_verified.failed**: 0
- **scenarios_deferred_to_pr3**: 2 (engine-security "Parser consumers…" + robustness aggregate "All 7 scenarios" pending the 4 cleanup-session cases)

## Section L — Skill Resolution

`paths-injected` — both skill paths from the launch prompt's `## Skills to load before work` block were read before any verification work:
- `~/.config/opencode/skills/sdd-verify/SKILL.md`
- `~/.config/opencode/skills/_shared/SKILL.md`

Plus shared references read proactively: `_shared/sdd-phase-common.md`, `sdd-verify/references/report-format.md`. No fallback-registry or SKILL: Load path needed. Strict TDD module NOT loaded (`strict_tdd: false`).

## Section M — Next Recommended

1. **Push the branch**: `git push -u origin pr2/bats-migration`
2. **Open PR2** targeting `main` with the `size:exception` rationale in the PR body (mechanical 1:1 probe→bats migration; reviewer scans per-file).
3. **After PR2 merges**, start PR3 (`pr3/extraction-flip` from main) with T3.1 first (extract_session_error extraction before its tests). The flip (T3.4) is LAST — canary.
4. **Before archive**: amend the 3 carry-forward spec/design items (Q1 MANIFEST path, Q4 make ci order, Q5 bats-loader in design).
