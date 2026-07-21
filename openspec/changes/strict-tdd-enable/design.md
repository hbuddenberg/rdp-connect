# Design: strict-tdd-enable

> **Change**: `strict-tdd-enable` · **Project**: `rdp-connect` · **Mode**: openspec (engram mirror) · **Date**: 2026-07-21
> **Dependencies**: `proposal.md` (obs #249), `specs/test-harness-delta.md`, `specs/engine-robustness-delta.md`, `specs/engine-security-delta.md`, `explore.md` (obs #245)

## Technical Approach

Land the change as a **3-PR stacked-to-main chain** (per `delivery_strategy: chained-PRs`):
PR1 ships the tooling (Makefile + CI + helper) with the flag still `false`; PR2 migrates the 46 probe cases 1:1 to bats and deletes the legacy probe scripts; PR3 extracts two pure functions from the engine into `lib/rdp-common.bash`, adds the new bats coverage those extractions unlock, and flips **both** `strict_tdd` keys so the flag finally enforces something real.

The architectural spine is the **Extract-Before-Mock rule** (R3): the only engine logic that gains unit coverage is logic that can be lifted to `lib/rdp-common.bash` as a pure function with NO external commands. Everything that touches `xfreerdp3`, `hyprctl`, `flock`, `notify-send`, `/dev/tcp`, or `exit` stays in the engine and stays manual-verify (per `engine-robustness/spec.md` footers). Two functions clear that bar: the post-parse trim loop (engine L174–181) and the `cleanup()` awk extractor (engine L248–254). They become `trim_profile_fields()` and `extract_session_error()` in lib.

CI runs `make ci` (= `lint test`) on `ubuntu-latest`. **No mocking of `xfreerdp3`/`hyprctl` is needed** — every bats test is lib-boundary, and `rdp-connect --help` exits at engine L40 BEFORE `require_cmd` runs (L47), so the engine help path works on a bare CI runner. See Architecture Decision: ci_xfreerdp3_strategy.

## Architecture Decisions

### Decision: file_layout

**Choice**: Create the 11 new files below; **DELETE** the four `tests/*-probe.sh` scripts in PR2 in the same commit-train as the `.bats` files that supersede them.

```
rdp-connect/
├── Makefile                                   (new, PR1)
├── .github/workflows/test.yml                 (new, PR1)
├── tests/
│   ├── test_helper.bash                       (new, PR1)
│   ├── parser.bats                            (new, PR2 — replaces parser-probe.sh)
│   ├── hidpi.bats                             (new, PR2 — replaces hidpi-probe.sh)
│   ├── pid-path.bats                          (new, PR2 — replaces pid-path-probe.sh)
│   ├── vpn-trim.bats                          (new, PR2 — replaces vpn-trim-probe.sh)
│   ├── harness.bats                           (new, PR2 — covers Makefile + CI scenarios)
│   ├── engine-security.bats                   (new, PR3)
│   ├── cleanup-session.bats                   (new, PR3)
│   ├── fixtures/
│   │   ├── vpn-trim/        (8 fixtures + __snapshots__/)
│   │   └── cleanup-session/ (4 multi-session log fixtures)
│   ├── parser-probe.sh                        (DELETE in PR2)
│   ├── hidpi-probe.sh                         (DELETE in PR2)
│   ├── pid-path-probe.sh                     (DELETE in PR2)
│   └── vpn-trim-probe.sh                     (DELETE in PR2)
├── lib/rdp-common.bash                        (modify in PR3: +2 functions)
└── engine/rdp-connect                         (modify in PR3: trim loop + cleanup() delegate)
```

**Alternatives considered**:
- *Keep `tests/*-probe.sh` as thin wrappers that exec `bats tests/<name>.bats`.* Rejected — adds maintenance surface for a migration that completes inside one PR, and creates a drift vector (someone runs the probe, misses a bats-only fix). `make test` is the single entry point; the probe scripts were never invoked by the installer or CI (the installer has its own inline parser-probe at `install-rdp-framework.sh:207`).
- *Keep fixtures inline in `.bats` files (no `tests/fixtures/` dir).* Rejected for `vpn-trim` and `cleanup-session` only — R4 parity needs golden files so the pre-extraction snapshot and post-extraction assertion share bytes. The other 6 `.bats` files keep fixtures inline (parser F1–F23 patterns, hidpi JSON, pid-path uids).

**Rationale**: One entry point (`make test`), no drift vector, golden files only where parity demands them.

### Decision: migration_pattern

**Choice**: Per-case `@test` blocks (one probe case → one `@test`), no loop-style probes. Each `.bats` file sources `test_helper.bash` once at the top; the body is a flat list of `@test` functions.

Canonical translation — `parser-probe.sh` F15 (empty quoted value) → `tests/parser.bats`:

```bash
# tests/parser.bash — probe form (parser-probe.sh:181-183)
expect_val "F15 empty quoted value" \
           'VPN_CHECK=""\n' \
           profile VPN_CHECK ''

# tests/parser.bats — migrated form
@test "F15: empty quoted value parses to empty string" {
  parse_env_safe_under_setu 'VPN_CHECK=""\n' profile
  assert_success
  assert_output --regexp $'^\t$'   # rc=0<TAB><empty value>
  assert_equal "${VPN_CHECK:-}" ""
}
```

Helper mapping table:

| Probe idiom | bats replacement | Notes |
|---|---|---|
| `ok`/`fail` with `color()` | `assert_success` / `assert_failure` + `assert_output` | Drop `color()` entirely. bats formats TAP output. |
| `expect_rc <label> <fixture> <mode> <rc>` | `parse_env_safe_under_setu "$fixture" "$mode"; assert_failure` (or `assert_success`) | The helper writes fixture, spawns child bash, captures `<rc>\t<val>`. |
| `expect_val` | … + `assert_equal` on indirect var | |
| `expect_rc_msg` | … + `assert_output --partial "unexpected content after closing quote"` | `stderr` is captured into `$output` by the helper. |
| `expect_skip` (vpn-trim-probe) | `run trim_profile_fields VPN_CHECK; assert_empty "$VPN_CHECK"` | **Must call the extracted lib function, NOT a reimplementation.** This kills the "approval test exercises copy, not production code" smell flagged in explore F2. |
| `expect_enter_with` | `trim_profile_fields VPN_CHECK; assert_equal "$VPN_CHECK" "$expected"` | Same — production function. |
| `set -euo pipefail` atop probe | **DROP at .bats top level** (bats wraps each `@test` in its own function; top-level `set -e` breaks bats). Inside a `@test` body, `set -u` is fine; `set -e` is unnecessary because `run` + `assert_*` are the failure model. |
| Loop `for case in F1 F2 F3; do expect_skip …; done` | One `@test` per case | Required for per-case TAP reporting and `--filter` selectivity. |

**F14 special case** (set -u safety re-verification): the existing `parser-probe.sh` deliberately spawns a CHILD bash with `set -u` to re-verify that a non-allowlisted key returns `1` cleanly (no "unbound variable" abort). bats `@test` blocks run in-process; the child-bash idiom MUST be preserved inside the `@test` body. `test_helper.bash::parse_env_safe_under_setu` provides this.

### Decision: trim_extraction

**Choice**: Extract the engine's L174–181 post-parse trim loop verbatim into `lib/rdp-common.bash::trim_profile_fields()` (zero behavior change; the engine call site becomes a one-liner).

**Signature and pseudocode** (`lib/rdp-common.bash`):

```bash
# trim_profile_fields
#
# Mutates the 5 network-identifier fields IN PLACE via printf -v: HOST,
# VPN_CHECK, DOMAIN, PREFERRED_WS, LANG_OVERRIDE. Uses the parameter-expansion
# trim idiom (no subshell, no set -e trap). NEVER touches PASS_RDP or
# USER_RDP — credentials MAY legally contain surrounding whitespace; the
# allowlist (5 trimmed, 2 excluded) is enforced by the loop list, NOT by
# conditional logic, so an accidental widening is impossible without editing
# this function (security-critical invariant — see engine-security spec).
#
# Caller contract: the 5 globals MUST already be set (by parse_env_safe or
# pre-init). The function does NOT take arguments and returns nothing.
trim_profile_fields() {
  local _field _val
  for _field in HOST VPN_CHECK DOMAIN PREFERRED_WS LANG_OVERRIDE; do
    # shellcheck disable=SC2229  # dynamic var name; values come from parse_env_safe allowlist
    _val="${!_field}"
    _val="${_val#"${_val%%[![:space:]]*}"}"   # strip leading whitespace
    _val="${_val%"${_val##*[![:space:]]}"}"   # strip trailing whitespace
    # shellcheck disable=SC2229  # see above
    printf -v "$_field" '%s' "$_val"          # indirect write to global
  done
}
```

**Engine call site** (replaces L174–181):

```bash
# T2.6: trim network-identifier fields post-parse (extracted to lib so the
# bats suite tests the REAL trim, not a reimplementation).
trim_profile_fields
```

**Why `local _field _val` is safe**: `printf -v "$_field"` writes to the GLOBAL named by `_field` (e.g. `HOST`); only `_field` and `_val` are scoped locally. The globals (`HOST`, `VPN_CHECK`, …) were already assigned to global scope by `parse_env_safe`'s `printf -v "$key" '%s' "$value"` (lib L143).

**Unit-test pattern** (`tests/vpn-trim.bats`):

```bash
@test "trim_profile_fields: 8 fixtures produce byte-identical output" {
  for f in "$TESTS_DIR/fixtures/vpn-trim"/*.env; do
    name=$(basename "$f" .env)
    snapshot="$TESTS_DIR/fixtures/vpn-trim/__snapshots__/${name}.txt"

    # Load fixture values into the 7 globals (parse_env_safe is the prod path).
    parse_env_safe "$f" profile || fail "fixture $name failed to parse"
    trim_profile_fields

    # Snapshot format: 7 lines, "<KEY>=<value>" for HOST/USER_RDP/PASS_RDP/
    # DOMAIN/VPN_CHECK/PREFERRED_WS/LANG_OVERRIDE (the 2 excluded keys are
    # asserted verbatim; the 5 trimmed keys are asserted against their snapshot).
    actual=$(printf 'HOST=%s\nUSER_RDP=%s\nPASS_RDP=%s\nDOMAIN=%s\nVPN_CHECK=%s\nPREFERRED_WS=%s\nLANG_OVERRIDE=%s\n' \
      "$HOST" "$USER_RDP" "$PASS_RDP" "$DOMAIN" "$VPN_CHECK" "$PREFERRED_WS" "$LANG_OVERRIDE")
    assert_equal "$actual" "$(cat "$snapshot")"
  done
}
```

### Decision: session_error_extraction

**Choice**: Extract the `cleanup()` awk extractor (engine L248–254) into `lib/rdp-common.bash::extract_session_error()`. File-existence guard moves INTO the function; the engine's `[ -n "${START_TIME:-}" ]` defensive guard is dropped (the trap registers AFTER `START_TIME` is set at engine L192, so the guard is statically true).

**Signature and pseudocode** (`lib/rdp-common.bash`):

```bash
# extract_session_error <log_file> <pid>
#
# Outputs the LAST line written by <pid>'s session that matches
# /error|failed|status|connect/ (case-insensitive), scanning FORWARD from
# <pid>'s SESSION_START marker. Empty output if no marker exists for <pid>
# (legacy log), no matching line exists in this session, or <log_file> is
# missing/unreadable. PID matching is prefix-safe: pid=2222 does NOT match a
# marker for pid=22222.
#
# Pure text transformation over a file — NO external state, NO side effects,
# NO notify-send, NO exit. Safe to unit-test directly.
extract_session_error() {
  local log_file="$1" pid="$2"
  [[ -f "$log_file" ]] || return 0
  awk -v pid="$pid" '
    $0 ~ /\[SESSION_START\]/ && $0 ~ "pid="pid"([^0-9]|$)" { found=1; next }
    found && tolower($0) ~ /error|failed|status|connect/ { last=$0 }
    END { if (last) print last }
  ' "$log_file" 2>/dev/null || true
}
```

**Engine `cleanup()` call site** (replaces L247–254):

```bash
if [ $EXIT_CODE -ne 0 ]; then
    LAST_ERROR="$(extract_session_error "$LOG_FILE" "$$")"
    log_event "ERROR" "Sesión finalizada con error (Código $EXIT_CODE). Duración: ${DURATION}s."
    log_event "ERROR" "Causa reportada: ${LAST_ERROR:-Error no especificado}"
    notify-send -u critical -i network-error "RDP $PROFILE Error" "${LAST_ERROR:-Ver log en $LOG_FILE}" || true
else
    log_event "INFO" "Sesión finalizada correctamente. Duración total: ${DURATION}s."
    notify-send -i display-off "RDP $PROFILE" "$MSG_SESSION_ENDED" || true
fi
```

**Parity note (R4)**: the `[ -n "${START_TIME:-}" ]` drop is the ONLY behavioral difference between the inline and extracted forms. It is statically true at every cleanup invocation (START_TIME assigned L192, trap registered L272). The 4 cleanup-session fixtures cover the 4 spec scenarios; none exercise the START_TIME-unset edge because it cannot occur at runtime.

### Decision: makefile

**Choice**: 5 targets + `ci` alias, `SHELL := /usr/bin/env bash`, all phony.

```makefile
# Makefile — rdp-connect entry points
# Spec: openspec/changes/strict-tdd-enable/specs/test-harness-delta.md

SHELL := /usr/bin/env bash
TESTS_DIR := tests

.PHONY: test lint install smoke verify-manifest ci

# Primary entry point. Runs every *.bats under tests/. Exits non-zero on any
# case failure (bats's own exit code).
test:
	bats $(TESTS_DIR)/

# Static analysis. shellcheck exits non-zero on any warning. tests/fixtures/
# is excluded (golden files are data, not source).
lint:
	shellcheck engine/rdp-connect lib/*.bash install-rdp-framework.sh bootstrap.sh \
	           tests/test_helper.bash tests/*.bash

# Idempotent install. No other side effect (per spec).
install:
	./install-rdp-framework.sh

# Post-install smoke. Throwaway HOME proves the engine binary is on PATH and
# parses (--help exits 0 before require_cmd, so this works without xfreerdp3).
smoke: install
	HOME=$$(mktemp -d) ~/.local/bin/rdp-connect --help >/dev/null

# Tamper detection. NOTE: the installer writes ~/.local/state/rdp/manifest.sha256
# (lowercase). The spec test-harness-delta.md says ~/.local/share/rdp/MANIFEST.sha256
# (uppercase) — that is a SPEC BUG. This target matches the installer (source of
# truth: install-rdp-framework.sh:219). Open question Q1 tracks fixing the spec.
verify-manifest:
	sha256sum -c ~/.local/state/rdp/manifest.sha256

# CI alias. GitHub Actions invokes this on every PR.
ci: lint test
```

### Decision: ci_workflow

**Choice**: `.github/workflows/test.yml` on `ubuntu-latest`, triggers on `push` + `pull_request` against `main`, installs `bats` + `shellcheck` + `jq` via apt, runs `make ci`, uploads `tests/` log on failure.

```yaml
# .github/workflows/test.yml
name: test
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: |
          sudo apt-get update
          sudo apt-get install -y bats shellcheck jq libnotify-bin util-linux
      - name: make ci
        run: make ci
      - name: Upload test logs on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: test-logs
          path: tests/
```

**Dep notes**:
- `bats` — ubuntu-latest ships bats 1.5.0+ via apt (R1 floor met)
- `shellcheck` — linter
- `jq` — required by `compute_dpi_flags` (lib) and assert path if a test exercises it
- `libnotify-bin` (provides `notify-send`) and `util-linux` (provides `flock`) — needed if any test shells out to the engine; harmless to install
- `xfreerdp3` and `hyprctl` are NOT installed and NOT needed (see next decision)

### Decision: ci_xfreerdp3_strategy

**Choice**: Option **(c) — only test lib functions in CI; engine integration tests stay manual.** No mocks, no escape hatches.

**Rationale** (correcting the premise in the launch prompt):

1. **The premise "require_cmd exits 127 in `rdp-connect --help`" is factually wrong.** Engine L25–41 (`--help` mode, `exit 0`) executes BEFORE L47 (`require_cmd xfreerdp3`). `--help` runs cleanly on a bare CI runner with zero `xfreerdp3`/`hyprctl` installed. This was verified by reading the engine in this design phase.

2. **Every bats test is already lib-boundary.** They source `lib/rdp-common.bash` and exercise pure functions (`parse_env_safe`, `compute_pid_path`, `compute_dpi_flags` with a mocked `hyprctl`, `trim_profile_fields`, `extract_session_error`). No test invokes the engine past `--help`.

3. **The harness.bats `make_install_delegates_to_installer` test uses a PATH-shim SPY** (per `test-harness-delta.md` L33) — it intercepts `install-rdp-framework.sh` and asserts the invocation count; it does NOT actually run the installer. So the installer's hard-dep check at `install-rdp-framework.sh:96` (`for binary in xfreerdp3 jq flock notify-send`) never fires in CI.

4. **Option (a) shims drift** — fakes of `xfreerdp3`/`hyprctl` would be the highest-risk vector in the change (R3). **Option (b) `--no-require` escape hatch** adds a security liability: someone sets `RDP_NO_REQUIRE=1` in production to "fix" a misconfigured host and bypasses the preflight on the credential path. **Option (c) is free** and aligns with the Extract-Before-Mock rule.

5. **Engine integration tests** (real `xfreerdp3` exit codes, real `flock` contention, real `hyprctl` IPC, real `/dev/tcp` host probe) stay manual-verify per the existing `engine-robustness/spec.md` footers. This is unchanged.

## Data Flow

```
make ci ──▶ lint ──▶ shellcheck (engine + lib + installer + bootstrap + tests/*.{bash})
       └─▶ test ──▶ bats tests/
                    │
                    ├─ test_helper.bash ─source─▶ lib/rdp-common.bash
                    │                              ├─ parse_env_safe
                    │                              ├─ compute_pid_path
                    │                              ├─ compute_dpi_flags
                    │                              ├─ trim_profile_fields       (PR3)
                    │                              └─ extract_session_error     (PR3)
                    │
                    ├─ parser.bats        ─uses─▶ parse_env_safe_under_setu (child bash)
                    ├─ hidpi.bats         ─mocks─▶ hyprctl, log_event
                    ├─ pid-path.bats      ─mocks─▶ id
                    ├─ vpn-trim.bats      ─uses─▶ trim_profile_fields + fixtures/
                    ├─ cleanup-session.bats ─uses─▶ extract_session_error + fixtures/
                    ├─ engine-security.bats ─spies─▶ trim_profile_fields
                    └─ harness.bats       ─shells─▶ make {test,lint,install,verify-manifest}

PR3 flip ──▶ openspec/config.yaml: strict_tdd (L20) + rules.apply.tdd (L56)
                  │
                  └─▶ next SDD change now MUST follow strict-tdd.md (red-green-refactor)
```

## File Changes

| File | Action | PR | LOC |
|------|--------|----|----|
| `Makefile` | Create | PR1 | ~30 |
| `.github/workflows/test.yml` | Create | PR1 | ~30 |
| `tests/test_helper.bash` | Create | PR1 | ~55 |
| `tests/parser.bats` | Create | PR2 | ~290 |
| `tests/hidpi.bats` | Create | PR2 | ~140 |
| `tests/pid-path.bats` | Create | PR2 | ~95 |
| `tests/vpn-trim.bats` | Create | PR2 | ~95 (pre-extraction form) |
| `tests/harness.bats` | Create | PR2 | ~110 |
| `tests/parser-probe.sh` | **Delete** | PR2 | −248 |
| `tests/hidpi-probe.sh` | **Delete** | PR2 | −119 |
| `tests/pid-path-probe.sh` | **Delete** | PR2 | −85 |
| `tests/vpn-trim-probe.sh` | **Delete** | PR2 | −78 |
| `lib/rdp-common.bash` | Modify (+2 functions) | PR3 | +~35 |
| `engine/rdp-connect` | Modify (trim + cleanup delegate) | PR3 | −~20 / +~6 |
| `tests/vpn-trim.bats` | Modify (rewrite to use lib fn) | PR3 | ~+25 net |
| `tests/engine-security.bats` | Create | PR3 | ~80 |
| `tests/cleanup-session.bats` | Create | PR3 | ~90 |
| `tests/fixtures/vpn-trim/*` + `__snapshots__/` | Create | PR3 | ~60 |
| `tests/fixtures/cleanup-session/*` | Create | PR3 | ~40 |
| `openspec/config.yaml` | Modify (L20 + L56 + `testing.*` block) | PR3 | ~+10 / −10 |
| `README.md` | Modify (distro matrix + badge) | PR1 | ~+30 |

## Interfaces / Contracts

### `tests/test_helper.bash` (PR1)

```bash
# tests/test_helper.bash — sourced by every tests/*.bats
bats_require_minimum_version 1.5.0   # R1 mitigation: clear abort on bats < 1.5.0

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/lib/rdp-common.bash"

# shellcheck source=../lib/rdp-common.bash
source "$LIB_FILE"

# setup_test_home — R1 mitigation: no test touches real $HOME.
# Creates and exports a per-test throwaway HOME, returns its path.
setup_test_home() {
  HOME="$BATS_TMPDIR/home"
  mkdir -p "$HOME"
  printf '%s' "$HOME"
}

# parse_env_safe_under_setu <fixture_content> <mode>
# Writes fixture to a tmp file, spawns a CHILD bash under `set -u`, sources
# lib, runs parse_env_safe, prints "<rc>\t<value-of-_unused_>" and (via
# stderr) any _reject diagnostic. Required so F14 can re-verify that a
# non-allowlisted key returns 1 cleanly under set -u (in-process bats run
# can't catch the unbound-variable case the way a child bash can).
# Sets $status, $output, $stderr for the standard bats assertions.
parse_env_safe_under_setu() {
  local fixture="$1" mode="${2:-profile}"
  local f; f=$(mktemp)
  printf '%b' "$fixture" > "$f"
  run bash -c '
    set -u
    source "$1"
    parse_env_safe "$2" "$3"
    printf "%d\t%s\n" "$?" "<ok>"
  ' _ "$LIB_FILE" "$f" "$mode"
  rm -f "$f"
}

# assert_probes_pass — shared fail-on-nonzero assertion (referenced by spec
# test-harness-delta Requirement: Shared test helper). Kept as a thin alias
# so the spec's naming is honored; delegates to the standard bats idiom.
assert_probes_pass() {
  assert_success
}
```

### `lib/rdp-common.bash` (PR3 additions — signatures)

```bash
trim_profile_fields()           # no args, no return; mutates 5 globals in place
extract_session_error() { }     # <log_file> <pid>; prints LAST_ERROR or empty
```

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Unit (lib) | `parse_env_safe` (24 cases), `compute_pid_path` (6), `compute_dpi_flags` (8), `trim_profile_fields` (8), `extract_session_error` (4) | bats table-driven; mocks for `hyprctl`/`id`; child bash for set-u parity. **Total: 50 @test blocks.** |
| Boundary (engine→lib) | Post-parse trim call site uses extracted fn (not inline); cleanup trap uses extracted fn | bats spy on `trim_profile_fields`/`extract_session_error`; assert exactly-once invocation. |
| Harness (Makefile + CI) | `make {test,lint,install,verify-manifest}` exit codes; CI workflow YAML well-formedness | bats shelling out to `make`, asserting `$status`; YAML structural assertion via `grep`/`yq` if available, else `grep`. |
| Integration (engine) | Real xfreerdp3 exit, real flock, real hyprctl, real `/dev/tcp` | **Manual-verify** (unchanged per `engine-robustness/spec.md` footers). NOT in bats, NOT in CI. |

## Migration / Rollout

3-PR stacked-to-main chain. Each PR is independently mergeable and revertable.

- **PR1 (tooling, ~115 LOC, Low risk)**: Makefile + CI + `test_helper.bash` + README distro matrix. Flag stays `false`. Lands the entry points the next two PRs plug into.
- **PR2 (bats migration, ~1080 changed LOC, Medium risk, `size:exception`)**: 5 new `.bats` files (the 4 migrations + `harness.bats`), delete the 4 probe scripts. Pure mechanical translation; no logic change. `size:exception` rationale: 4-file scan, not per-line scan (per `chained-pr` rule + explore F7).
- **PR3 (extraction + flip, ~200 LOC, Medium risk)**: 2 lib extractions, engine delegates to them, 2 new `.bats` files + fixtures, rewrite `vpn-trim.bats` to call `trim_profile_fields` (kills the test smell), flip both `strict_tdd` keys (L20 + L56), update `testing.*` block. Carries the canary flip.

Rollback (per proposal): `git revert` in reverse order PR3 → PR2 → PR1. The canary is `strict_tdd` returning to `false`. Reverting PR3 alone restores the pre-strict regime while keeping the harness in place (PR1 + PR2 are inert without the flip).

## Open Questions

- [ ] **Q1 — spec bug in `test-harness-delta.md`**: the spec says `verify-manifest` reads `~/.local/share/rdp/MANIFEST.sha256`, but the installer (`install-rdp-framework.sh:219`) writes `~/.local/state/rdp/manifest.sha256`. Design follows the **installer** (source of truth). The spec should be amended before sdd-verify runs, OR the installer should be renamed. Recommend: amend the spec.
- [ ] **Q2 — `assert_probes_pass` naming**: the spec `test-harness-delta.md` L56 names this helper explicitly, but its semantics are identical to bats's built-in `assert_success`. PR1 ships it as a thin alias to honor the spec contract; can be removed if the spec is amended.
- [ ] **Q3 — README badge count**: proposal mentions a "badge count" but does not specify the badge URL (Code Climate? custom? static?). Recommend: static SVG counting the 50 bats cases, generated by a tiny post-test script. Defer exact URL to PR3.
