# Tasks: strict-tdd-enable

> **Change**: `strict-tdd-enable` · **Project**: `rdp-connect` · **Mode**: openspec (engram mirror)
> **Dependencies**: `proposal.md` (obs #249), `design.md` (obs #252), 3 spec deltas (7 reqs / 15 scenarios)
> **Delivery**: `chained-PRs` · `stacked-to-main` · `size:exception` on PR2

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR1 ~115 · PR2 ~1080 · PR3 ~200 |
| 400-line budget risk | High (PR2 only) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 tooling → PR2 bats migration → PR3 extraction + flip |
| Delivery strategy | chained-PRs (auto) |
| Chain strategy | stacked-to-main (PR2 = size:exception) |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | PR | Base |
|------|------|----|------|
| 1 | Tooling scaffolding (Makefile + CI + helper + README matrix) | PR1 | main |
| 2 | trim extraction + 5 `.bats` migrations + probe cleanup | PR2 | main (after PR1) |
| 3 | session_error extraction + security boundary + canary flip | PR3 | main (after PR2) |

## Branch Plan (stacked-to-main)

- `pr1/tooling` ← from `main` → merges to `main`
- `pr2/bats-migration` ← from `main` (after PR1 merges) → merges to `main`
- `pr3/extraction-flip` ← from `main` (after PR2 merges) → merges to `main`

Each PR is independently mergeable + revertable. Rollback = `git revert` PR3 → PR2 → PR1.

---

## PR1 — Tooling (`pr1/tooling`, ~115 LOC, Low risk)

Flag stays `false`. Lands entry points PR2/PR3 plug into.

- [x] **T1.1** `feat(build): add Makefile with test/lint/install/smoke/verify-manifest targets`
  - Files: `Makefile` (new)
  - Deps: — · Size: ~30 · PR1
  - `@test` added: none (exercised by T2.6 `harness.bats`)
  - [x] manual-verification: Makefile defines 5 targets + `ci` alias; `test` runs `bats tests/`; `lint` shellchecks all `*.bash`/`*.sh` excl. `tests/fixtures/`

- [x] **T1.2** `ci: add GitHub Actions workflow running make ci on ubuntu-latest`
  - Files: `.github/workflows/test.yml` (new)
  - Deps: T1.1 · Size: ~30 · PR1
  - `@test` added: none (exercised by T2.6)
  - [x] manual-verification: triggers on `push`+`pull_request` to `main`; `ubuntu-latest`; apt installs `bats shellcheck jq libnotify-bin util-linux`; runs `make ci`; uploads `tests/` on failure

- [x] **T1.3** `test: add tests/test_helper.bash (lib source, setup_test_home, parse_env_safe_under_setu)`
  - Files: `tests/test_helper.bash` (new)
  - Deps: — (lib exists) · Size: ~55 · PR1
  - `@test` added: none (enables T2.6 scenarios 5–6: `bats_require_minimum_version 1.5.0`, `setup_test_home`)
  - [x] manual-verification: helper sources `lib/rdp-common.bash`; calls `bats_require_minimum_version 1.5.0`; `setup_test_home` exports `HOME=$BATS_TMPDIR/home`; provides `parse_env_safe_under_setu` (child bash) + `assert_probes_pass` alias

- [x] **T1.4** `docs(readme): add bats-core distro install matrix`
  - Files: `README.md`
  - Deps: — · Size: ~30 · PR1
  - `@test` added: none
  - [x] manual-verification: README documents bats-core install for Arch/Ubuntu/Fedora (dev-only, NOT a runtime dep)

## PR2 — Bats migration + trim extraction (`pr2/bats-migration`, ~1080 LOC, size:exception, Medium risk)

**Ordering invariant**: T2.1 (trim extraction) is FIRST so T2.5 `vpn-trim.bats` calls the REAL `trim_profile_fields` — not a reimplementation. Kills the "approval test exercises copy, not production code" smell at migration time.

- [ ] **T2.1** `refactor(engine): extract trim_profile_fields into lib/rdp-common.bash`
  - Files: `lib/rdp-common.bash` (+`trim_profile_fields`), `engine/rdp-connect` (L174–181 loop → one-line `trim_profile_fields` call)
  - Deps: — · Size: ~25 · PR2 (FIRST commit)
  - `@test` added: none (pure behavior-preserving refactor; parity proven by still-passing probes + T2.5)
  - [ ] manual-verification: byte-identical engine behavior; existing `vpn-trim-probe.sh` still passes against extracted fn

- [ ] **T2.2** `test(parser): migrate parser-probe.sh F1–F24 to tests/parser.bats`
  - Files: `tests/parser.bats` (new)
  - Deps: T1.3 · Size: ~290 · PR2
  - `@test` added (24): F1–F24 `parse_env_safe` cases; F14 preserves child-bash `set -u` via `parse_env_safe_under_setu`
  - [ ] manual-verification: mechanical 1:1 translation; `bats tests/parser.bats` mirrors probe rc/output

- [ ] **T2.3** `test(hidpi): migrate hidpi-probe.sh to tests/hidpi.bats`
  - Files: `tests/hidpi.bats` (new)
  - Deps: T1.3 · Size: ~140 · PR2
  - `@test` added (8): `compute_dpi_flags` cases (mocks `hyprctl`/`id`; lib-boundary only)

- [ ] **T2.4** `test(pid-path): migrate pid-path-probe.sh to tests/pid-path.bats`
  - Files: `tests/pid-path.bats` (new)
  - Deps: T1.3 · Size: ~95 · PR2
  - `@test` added (6): `compute_pid_path` cases (mocks `id`)

- [ ] **T2.5** `test(vpn-trim): migrate vpn-trim-probe.sh to tests/vpn-trim.bats using extracted trim_profile_fields`
  - Files: `tests/vpn-trim.bats` (new), `tests/fixtures/vpn-trim/*.env` (8), `tests/fixtures/vpn-trim/__snapshots__/*.txt` (8)
  - Deps: **T2.1** (extracted fn), T1.3 · Size: ~155 · PR2
  - `@test` added (10): 8 fixture-driven `@test` + `trim_profile_fields_byte_identical_on_fixtures` + `trim_profile_fields_has_unit_coverage`
  - [ ] manual-verification: "All 7 robustness scenarios have @test parity" (3 preflight-trim scenarios)
  - [ ] manual-verification: "8 vpn-trim fixtures pass byte-identical pre/post extraction"
  - [ ] manual-verification: "@test coverage for trim_profile_fields()"

- [ ] **T2.6** `test(harness): add tests/harness.bats covering Makefile + CI scenarios`
  - Files: `tests/harness.bats` (new)
  - Deps: T1.1, T1.2, T1.3 · Size: ~110 · PR2
  - `@test` added (8): `make_test_passes_46_plus_cases`, `make_install_delegates_to_installer`, `make_verify_manifest_detects_tamper`, `make_lint_fails_on_shellcheck_warning`, `bats_minimum_version_enforced`, `setup_test_home_isolates_HOME`, `ci_workflow_well_formed`, `ci_workflow_uploads_logs_on_failure`
  - [ ] manual-verification: "Fresh-clone `make test` passes 46+ cases"
  - [ ] manual-verification: "`make install` delegates to the installer"
  - [ ] manual-verification: "`make verify-manifest` catches a tampered deployment"
  - [ ] manual-verification: "shellcheck warnings fail `make lint`"
  - [ ] manual-verification: "bats < 1.5.0 fails with a clear message"
  - [ ] manual-verification: "`setup_test_home` isolates `HOME`"
  - [ ] manual-verification: "CI green on a healthy PR"
  - [ ] manual-verification: "CI fails on a red test and uploads logs"

- [ ] **T2.7** `chore(tests): delete legacy *.probe.sh scripts superseded by *.bats`
  - Files: DELETE `tests/{parser,hidpi,pid-path,vpn-trim}-probe.sh`
  - Deps: T2.2, T2.3, T2.4, T2.5 · Size: −530 · PR2
  - `@test` added: none (cleanup; `make test` is sole entry point)

## PR3 — session_error extraction + security boundary + flip (`pr3/extraction-flip`, ~200 LOC, Medium risk)

**Ordering invariant**: extractions (T3.1) BEFORE flip (T3.4), so strict_tdd activates against extracted code. Flip is LAST = canary.

- [ ] **T3.1** `refactor(engine): extract extract_session_error into lib/rdp-common.bash`
  - Files: `lib/rdp-common.bash` (+`extract_session_error`), `engine/rdp-connect` (cleanup() L247–254 → delegate; drop statically-true `[ -n START_TIME ]` guard)
  - Deps: — · Size: ~30 · PR3
  - `@test` added: none (parity in T3.2)
  - [ ] manual-verification: `cleanup()` produces identical `LAST_ERROR` on the 4 multi-session fixtures

- [ ] **T3.2** `test(cleanup-session): add tests/cleanup-session.bats + fixtures for extract_session_error`
  - Files: `tests/cleanup-session.bats` (new), `tests/fixtures/cleanup-session/*.log` (4) + snapshots
  - Deps: T3.1 · Size: ~130 · PR3
  - `@test` added (6): 4 fixture-driven `@test` (stale ERROR, PID prefix collision 2222 vs 22222, no-ERROR, legacy no-SESSION_START) + `extract_session_error_byte_identical_on_fixtures` + `extract_session_error_has_unit_coverage`
  - [ ] manual-verification: "All 7 robustness scenarios have @test parity" (4 cleanup-session scenarios)
  - [ ] manual-verification: "Multi-session `LOG_FILE` fixtures match pre-extraction output"
  - [ ] manual-verification: "@test coverage for `extract_session_error()`"

- [ ] **T3.3** `test(engine-security): add tests/engine-security.bats for trim allowlist + call-site boundary`
  - Files: `tests/engine-security.bats` (new)
  - Deps: T2.1 (satisfied via PR2 merge) · Size: ~80 · PR3
  - `@test` added (2): `engine_calls_trim_profile_fields_not_inline`, `trim_allowlist_is_five_trimmed_two_excluded`
  - [ ] manual-verification: "Parser consumers call `trim_profile_fields()`, not inline trim"
  - [ ] manual-verification: "`trim_profile_fields()` allowlist is the documented 5 trimmed + 2 excluded"

- [ ] **T3.4** `chore(openspec): flip strict_tdd true and wire testing.* block to bats`  ← CANARY
  - Files: `openspec/config.yaml` (L20 `strict_tdd: true`, L56 `rules.apply.tdd: true`, `testing.runner/framework/unit` → `bats`/`bats-core`)
  - Deps: T2.6, T3.2, T3.3 (all bats green before flip) · Size: ~20 · PR3
  - `@test` added: none (config change)
  - [ ] manual-verification: `grep -c '^strict_tdd: true' openspec/config.yaml` = 1 **AND** `grep -c 'tdd: true' openspec/config.yaml` ≥ 1 (R6 two-key flip canary — silent no-op if only one flips)

- [ ] **T3.5** `docs(readme): add bats test-count badge`
  - Files: `README.md`
  - Deps: T3.4 (count final post-flip) · Size: ~10 · PR3
  - `@test` added: none

---

## Ordering Constraints (verified)

- T2.1 BEFORE T2.5 — `vpn-trim.bats` calls the extracted `trim_profile_fields` (not a copy) → **resolved per launch rule #6** (extraction moved to PR2-first)
- T2.2–T2.5 BEFORE T2.7 — probes deleted only after `.bats` supersede them
- T2.1/T2.2/T2.3/T2.4 BEFORE T2.6 — `harness.bats::make_test_passes_46_plus_cases` needs the suite populated
- T3.1 BEFORE T3.2 — session_error fn exists before its tests
- T3.2/T3.3 BEFORE T3.4 — flip LAST, after all bats cases green
- T3.3 deps on T2.1 satisfied by stacked-to-main branch order (PR3 branches from main post-PR2-merge)

## `@test` Block Tally

| PR | File | `@test` count |
|----|------|---------------|
| PR2 | parser.bats | 24 |
| PR2 | hidpi.bats | 8 |
| PR2 | pid-path.bats | 6 |
| PR2 | vpn-trim.bats | 10 |
| PR2 | harness.bats | 8 |
| PR3 | cleanup-session.bats | 6 |
| PR3 | engine-security.bats | 2 |
| **Total** | | **64** |
