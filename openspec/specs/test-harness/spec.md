# test-harness Capability Spec

> **Capability**: `test-harness` · **Origin**: promoted from `strict-tdd-enable`
> delta (`test-harness-delta.md`) at archive.
> **Purpose**: contract surface for `make test`, `make lint`, and CI. Exists so
> `strict_tdd: true` enforces something real — without it the flag is a no-op.

## Requirements

### Requirement: Makefile entry points

The Makefile MUST define exactly five targets: `test` MUST run `bats tests/`
and exit non-zero on ANY failure; `lint` MUST run `shellcheck` over every
`*.bash`/`*.sh` file (excluding `tests/fixtures/`) and exit non-zero on any
warning; `install` MUST delegate to `install-rdp-framework.sh` with no other
side effect; `smoke` MUST run the post-install smoke sequence (throwaway
`HOME`, then an engine invocation proving the binary is on `PATH` and parses);
`verify-manifest` MUST run `sha256sum -c` on
`~/.local/state/rdp/manifest.sha256` and exit non-zero on any mismatch.

The `ci` alias target MUST run `lint` THEN `test` in that order (lint first).
GitHub Actions invokes `make ci` on every push to `main` and on every
`pull_request`.

#### Scenario: Fresh-clone `make test` passes 46+ cases

- GIVEN a fresh clone with `bats-core` installed via the README distro matrix
- WHEN a developer runs `make test`
- THEN `bats tests/` runs ≥46 cases and exits `0`
- AND (@test `harness.bats::make_test_passes_46_plus_cases`: shell out in a clean checkout; assert exit `0`, `cases` ≥ 46)

#### Scenario: `make install` delegates to the installer

- GIVEN the repo root with `Makefile` and `install-rdp-framework.sh`
- WHEN a developer runs `make install`
- THEN `install-rdp-framework.sh` executes (no other side effects)
- AND the engine lands at `~/.local/bin/rdp-connect`
- AND (@test `harness.bats::make_install_delegates_to_installer`: spy via `PATH` shim; assert invoked once)

#### Scenario: `make verify-manifest` catches a tampered deployment

- GIVEN a deployed `~/.local/state/rdp/manifest.sha256`
- WHEN one deployed file is modified and `make verify-manifest` runs
- THEN the target exits non-zero naming the tampered file
- AND (@test `harness.bats::make_verify_manifest_detects_tamper`: deploy to `setup_test_home`, mutate one file, assert non-zero exit)

#### Scenario: shellcheck warnings fail `make lint`

- GIVEN a `*.bash`/`*.sh` file with an injected `SC2086` warning
- WHEN `make lint` runs
- THEN the target exits non-zero and the offending file is named
- AND (@test `harness.bats::make_lint_fails_on_shellcheck_warning`: drop a fixture with an unquoted expansion; run `make lint`; assert non-zero exit)

### Requirement: Shared test helper (`tests/test_helper.bash`)

The repo MUST ship `tests/test_helper.bash`, sourced by every `*.bats` file.
The helper MUST: call `bats_require_minimum_version 1.5.0` at the top (R1
mitigation for bats skew); load the external `bats-support` and `bats-assert`
libraries (they are NOT part of bats-core — `assert_success`,
`assert_output`, `assert_equal`, `assert_failure`, `assert_empty` ship as
separate repos); source `lib/rdp-common.bash` from the repo root; provide
`setup_test_home()` that creates `$BATS_TMPDIR/home`, exports `HOME` to it,
and returns the path (no test MUST touch the real `HOME`); provide
`assert_probes_pass()` for the shared fail-on-nonzero assertion.

The bats-assert loader MUST search, first match wins, `$BATS_LIB_PATH` →
`/usr/lib/bats` → `~/.local/lib/bats` for `bats-support/load.bash` +
`bats-assert/load.bash`. If either library is missing, the helper MUST bail
with a clear install hint (exit code `2`) naming the searched roots and the
distro install commands, so a missing dep surfaces at load time instead of
cascading into a `command not found` inside the first `@test` body.

> **Codification note (carry-forward Q5, resolved at archive):** the loader
> clause above was implemented in task T1.3 but omitted from the original
> delta's helper skeleton (see the amendment block under the `test_helper.bash`
> skeleton in `strict-tdd-enable/design.md`). Promoted into the canonical spec
> here so the source-of-truth matches the deployed helper
> (`tests/test_helper.bash:42-77`).

#### Scenario: bats < 1.5.0 fails with a clear message

- GIVEN an environment with bats `1.1.0`
- WHEN `make test` runs
- THEN every `.bats` aborts at load with a message naming `1.5.0`
- AND (@test `harness.bats::bats_minimum_version_enforced`: stub `bats` reporting `1.1.0`; invoke `make test`; assert non-zero exit and the `1.5.0` token)

#### Scenario: `setup_test_home` isolates `HOME`

- GIVEN a `*.bats` test that calls `setup_test_home`
- WHEN the test writes a profile under `$HOME/.config/rdp/profiles/`
- THEN writes land under `$BATS_TMPDIR/home`, NOT the real `HOME`
- AND (@test `harness.bats::setup_test_home_isolates_HOME`: snapshot real `HOME`, call helper, write marker, assert it resolves under `$BATS_TMPDIR/home`)

### Requirement: CI workflow (`.github/workflows/test.yml`)

The CI workflow MUST trigger on `push` AND `pull_request` against `main`, run
on `ubuntu-latest`, install `bats-core` via `apt-get install -y bats`, run
`make lint` then `make test` in that order (matching `make ci`), and upload the `tests/` log
artifact on failure via `actions/upload-artifact`.

#### Scenario: CI green on a healthy PR

- GIVEN a PR against `main` with all bats cases green and `shellcheck` clean
- WHEN CI runs
- THEN both `make test` and `make lint` exit `0` and the workflow passes
- AND (@test `harness.bats::ci_workflow_well_formed`: assert workflow declares both triggers, `ubuntu-latest`, the `bats` apt install, both make targets, upload-artifact step)

#### Scenario: CI fails on a red test and uploads logs

- GIVEN a PR that introduces a failing bats case
- WHEN CI runs
- THEN `make test` fails, the workflow exits non-zero, and the `tests/` log
  artifact is uploaded for download
- AND (@test `harness.bats::ci_workflow_uploads_logs_on_failure`: static assert that `if: failure()` on `actions/upload-artifact` references `tests/`)
