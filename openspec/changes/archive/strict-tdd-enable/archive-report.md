# Archive Report — strict-tdd-enable

> **Change**: `strict-tdd-enable`
> **Project**: `rdp-connect`
> **Archived**: 2026-07-21
> **Archive path**: `openspec/changes/archive/strict-tdd-enable/`
> **Canonical capability specs**: `openspec/specs/{engine-security,engine-robustness,hidpi-scaling,instance-locking,installer,test-harness}/spec.md`
> **Merged PRs**: [#3 (tooling — Makefile + CI + helper + README)](https://github.com/hbuddenberg/rdp-connect/pull/3), [#4 (bats migration — 5 .bats files)](https://github.com/hbuddenberg/rdp-connect/pull/4), [#5 (extraction + strict_tdd flip)](https://github.com/hbuddenberg/rdp-connect/pull/5)
> **Delivery strategy**: chained-PRs (stacked-to-main, all merged)
> **Engram mirror**: topic_key `sdd/strict-tdd-enable/archive-report`

## Executive Summary

The `strict-tdd-enable` change is fully landed on `main` and archived. All three chained PRs (stacked-to-main) merged cleanly; every task (T1.1–T1.4 PR1 + T2.1–T2.7 PR2 + T3.1–T3.5 PR3) is implementation-complete and verified at runtime with **66/66 bats `@test` blocks passing** and `make ci` exiting 0. The change delivered three things in a review-safe order: (1) the tooling surface (Makefile + GitHub Actions CI + `tests/test_helper.bash` + README distro matrix), (2) the migration of all 46 legacy probe scenarios to `*.bats`, and (3) the extraction of two pure functions (`trim_profile_fields`, `extract_session_error`) out of the engine into `lib/rdp-common.bash` plus the `strict_tdd: true` flip — enforced by a two-key canary `@test` so the flag can never silently no-op. 6 canonical capability specs now live under `openspec/specs/` (the `test-harness` capability is NEW; `engine-robustness` and `engine-security` gained additive requirements). The change folder has been moved to `openspec/changes/archive/strict-tdd-enable/` as an immutable audit trail. **Strict TDD is now ACTIVE** for every future SDD change in `rdp-connect`.

## Carry-forward Items Resolved (at archive)

All four carry-forward items deferred by the verify reports (PR1/PR2/PR3) were amended on the spec/design/config files in place BEFORE the folder moved to archive, in commit `de3dad8`. The archive never modifies the canonical deltas silently — it amends first, then promotes.

| ID | Item | Resolution | Where |
|---|---|---|---|
| **Q1** | `test-harness-delta.md` said `verify-manifest` reads `~/.local/share/rdp/MANIFEST.sha256`; the installer (`install-rdp-framework.sh:219`), `bootstrap.sh:85`, Makefile, and `harness.bats` all use `~/.local/state/rdp/manifest.sha256` (XDG `state/`, lowercase) | Both occurrences amended to `~/.local/state/rdp/manifest.sha256` (implementation wins). Design Open Questions Q1 marked `[x] RESOLVED`. | `test-harness-delta.md` (L18 requirement + L37 scenario); `design.md` Open Questions Q1 |
| **Q4** | `test-harness-delta.md` CI workflow requirement said "`make test` then `make lint`"; Makefile `ci: lint test` runs lint first | Amended to "`make lint` then `make test` in that order (matching `make ci`)" | `test-harness-delta.md` CI workflow requirement (L76) |
| **Q5** | `design.md` `test_helper.bash` skeleton (L348–395) omitted the `bats-support`/`bats-assert` external loader that task T1.3 added | Added an amendment block under the skeleton documenting `_load_bats_assert()` (search order, bail behavior, run timing). The loader clause was also codified into the canonical `test-harness/spec.md` Shared-test-helper requirement so the source-of-truth matches the deployed helper. | `design.md` (after the skeleton); `openspec/specs/test-harness/spec.md` |
| **NEW** | `openspec/config.yaml` `testing.unit` count said "65 @test blocks"; the canary `@test` added in T3.4 bumped the real count to 66 | Count bumped 65 → 66 (with a note naming the canary as the cause). README badge (T3.5) already said 66; the config is now consistent with it. | `openspec/config.yaml:27` |

## Canonical Specs Synced

The `openspec/specs/` directory gained a 6th capability (`test-harness`) and two existing capabilities gained additive requirements (no existing requirement text was modified — both deltas used `## ADDED Requirements` framing per the sdd-spec additive rule).

| Capability | Source delta | Canonical spec | Action |
|---|---|---|---|
| `test-harness` | `test-harness-delta.md` | `openspec/specs/test-harness/spec.md` | **NEW (promoted + codified)** — delta was a full spec (no `## ADDED` framing). Promoted 3 requirements / 8 scenarios verbatim with a canonical header. Codified the `bats-support`/`bats-assert` loader clause into the Shared-test-helper requirement (carry-forward Q5) and added a `make ci` order clause to the Makefile-entry-points requirement (carry-forward Q4) so the canonical spec matches the deployed Makefile. |
| `engine-robustness` | `engine-robustness-delta.md` | `openspec/specs/engine-robustness/spec.md` | **MODIFIED (additive merge)** — appended 3 ADDED requirements (5 scenarios) after the existing "Preflight input normalization" requirement. All 7 pre-existing requirements preserved untouched. New: `Scenario-to-test parity for robustness scenarios`, `trim_profile_fields() extraction preserves byte-identical behavior` (2 scenarios), `extract_session_error() extraction preserves behavior` (2 scenarios). |
| `engine-security` | `engine-security-delta.md` | `openspec/specs/engine-security/spec.md` | **MODIFIED (additive merge)** — appended 1 ADDED requirement (2 scenarios) after the existing "i18n loaded through the hardened parser" requirement. All 3 pre-existing requirements preserved untouched. New: `Post-parse trim consumers use the extracted helper` (reinforces — does not replace — the robustness-side trim spec; defines WHERE the trim logic must live so the credential-exclusion invariant cannot drift). |

**Capability count**: 5 → 6. **Normative scenario count across canonical specs**: `test-harness` 8 (new) + `engine-robustness` 23 (18 + 5) + `engine-security` 14 (12 + 2) = **45 scenarios in the three touched capabilities**; `hidpi-scaling`, `instance-locking`, `installer` unchanged from the baseline-hardening archive.

## Scenarios Amended / Synced

Carry-forward text amendments (in-place on the delta before promotion):

| ID | Capability | Scenario / Requirement | Amendment |
|---|---|---|---|
| Q1 | `test-harness` | `verify-manifest` requirement + `make verify-manifest catches a tampered deployment` scenario | `~/.local/share/rdp/MANIFEST.sha256` → `~/.local/state/rdp/manifest.sha256` |
| Q4 | `test-harness` | `CI workflow` requirement | `make test` then `make lint` → `make lint` then `make test` (matching `make ci`) |
| Q5 | `test-harness` | `Shared test helper` requirement | Codified the `bats-support`/`bats-assert` loader clause (search order + exit-2 bail) |
| NEW | (config) | `openspec/config.yaml` `testing.unit` | 65 → 66 `@test` blocks |

New scenarios synced into canonical specs (15 total):

| Capability | Scenarios added |
|---|---|
| `test-harness` (NEW) | Fresh-clone `make test` passes 46+ cases · `make install` delegates to the installer · `make verify-manifest` catches a tampered deployment · shellcheck warnings fail `make lint` · bats < 1.5.0 fails with a clear message · `setup_test_home` isolates `HOME` · CI green on a healthy PR · CI fails on a red test and uploads logs |
| `engine-robustness` (+5) | All 7 robustness scenarios have @test parity · 8 vpn-trim fixtures pass byte-identical pre/post extraction · @test coverage for `trim_profile_fields()` · Multi-session `LOG_FILE` fixtures match pre-extraction output · @test coverage for `extract_session_error()` |
| `engine-security` (+2) | Parser consumers call `trim_profile_fields()`, not inline trim · `trim_profile_fields()` allowlist is the documented 5 trimmed + 2 excluded |

## Source-of-Truth Pointer Updates

In-code spec pointers were repointed from the (now-archived) deltas to the canonical specs, so nothing references the archive as if it were current. Comment-only, zero behavioral change.

| File | Change |
|---|---|
| `Makefile` L1-2 | `Spec:` pointer → `openspec/specs/test-harness/spec.md`; `verify-manifest` NOTE rewritten to record Q1 as RESOLVED (was an open spec-bug note) |
| `tests/test_helper.bash` L4-5 | `Spec:` pointer → `openspec/specs/test-harness/spec.md` |
| `README.md` | Badges: status → `strict-tdd-active`; added `strict_tdd:true` + CI workflow badges; capabilities 5 → 6. Capabilities table: added `test-harness` row. SDD-context section: active-change pointer → archive path; added canonical-spec link. |

## Archive Contents

The change folder moved verbatim — no deletion, no rewrite. The archive contains the complete SDD cycle artifacts:

- `proposal.md` ✅
- `specs/` ✅ (3 deltas: `test-harness-delta.md` [amended], `engine-robustness-delta.md`, `engine-security-delta.md`)
- `design.md` ✅ (Q1 marked resolved; Q5 loader amendment added)
- `tasks.md` ✅ (all tasks complete across the 3 PRs)
- `apply-progress.md` ✅
- `explore.md` ✅
- `verify-report-pr1.md` / `verify-report-pr2.md` / `verify-report-pr3.md` ✅ (per-slice verification; these were untracked on `main` and are committed as part of the archive)

## Verification (final state on `main`)

| Check | Result |
|---|---|
| `strict_tdd:` in `openspec/config.yaml` | ✅ `true` (L20) |
| `rules.apply.tdd:` in `openspec/config.yaml` | ✅ `true` (L68) — flipped in lockstep with L20 |
| Canary `harness.bats::both_strict_tdd_keys_flipped` | ✅ PASS (greps both anchored patterns; R6 silent no-op risk closed) |
| Total bats `@test` blocks (`grep -c '^@test' tests/*.bats`) | ✅ **66** (parser 24 + hidpi 8 + pid-path 6 + vpn-trim 10 + harness 10 + cleanup-session 6 + engine-security 2) |
| `make ci` | ✅ rc=0 (lint + 66 bats pass) |
| Active changes directory | ✅ Empty — `strict-tdd-enable` no longer present |

## Commits Made

1. `de3dad8` — `docs(sdd): amend strict-tdd-enable spec/design post-verify (Q1/Q4/Q5 + count bump)` — resolves all four carry-forward items on the delta/design/config in place (before the folder moved).
2. *(commit 2, this report)* — `docs(sdd): archive strict-tdd-enable — sync delta specs to canonical capabilities` — promotes `test-harness` (NEW), merges additive requirements into `engine-robustness` + `engine-security`, moves the change folder to `archive/`, repoints in-code spec pointers to canonical, refreshes README badges + capabilities matrix, and records this archive report.

Both pushed to `main` at `origin`.

## SDD Cycle Complete

The `strict-tdd-enable` change has been fully planned, implemented, verified, and archived. The source-of-truth specs now reflect the deployed behavior, and `strict_tdd: true` is enforced on every future SDD change in `rdp-connect`.

## Next Recommended

1. **Tag release `v0.2.0`.** `v0.1.0` was the baseline-hardened state; `v0.2.0` is the strict-TDD-active state (66 bats cases, CI workflow, lib-extracted pure functions). A tag now gives every future `git bisect` a clean anchor.
2. **CI badge will go live** on the first PR/push after this commit lands the `.github/workflows/test.yml` reference in the README badge URL. The workflow file itself shipped in PR1; the badge URL just needs a run to exist.
3. **Next SDD change candidate** — the multi-peer EXIT-trap race (the other candidate surfaced during the baseline-hardening explore). With strict TDD now active, that change MUST follow the red-green-refactor cycle at the unit level; the harness is ready.
4. **Optional follow-up (deferred, non-blocking)** — strengthen the two-key-flip canary to also assert `grep -c '^strict_tdd: false$'` returns 0 (catches a stale `false` lingering if both keys were somehow duplicated). Cheap to add; noted in verify-report-pr3 Section K.
