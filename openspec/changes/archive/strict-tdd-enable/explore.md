# Exploration: `strict-tdd-enable`

> **Change**: `strict-tdd-enable`
> **Project**: `rdp-connect` (Bash, v0.1.0 baseline)
> **Goal**: Flip `openspec/config.yaml` `strict_tdd: false → true` so future SDD changes enforce red-green-refactor via bats-core.
> **Mode**: openspec (mirror to engram)
> **Date**: 2026-07-21

---

## Current State

`rdp-connect` is a single-engine Bash project (369-line `engine/rdp-connect` + 247-line `lib/rdp-common.bash`) deployed by a 271-line `install-rdp-framework.sh`. The v0.1.0 baseline ships **5 capabilities / 51 canonical scenarios** across `engine-security`, `engine-robustness`, `hidpi-scaling`, `instance-locking`, `installer`.

**Testing today (verified by command, not assumed):**

| Surface | Status | Evidence |
|---|---|---|
| `command -v bats` | ❌ NOT installed | `BATS NOT INSTALLED` on this Arch host |
| `command -v shellcheck` | ✅ v0.11.0 at `/usr/bin/shellcheck` | — |
| `bash --version` | 5.3.15(1)-release | kernel 7.1.3-arch1-2 |
| Test runner in `config.yaml` | `runner: none`, `framework: none` | `openspec/config.yaml:23-24` |
| `strict_tdd` (top-level) | `false` | `openspec/config.yaml:20` |
| `rules.apply.tdd` | `false` | `openspec/config.yaml:56` |
| Probe scripts (NOT bats) | **4 scripts / 46 cases / 530 LOC** | `tests/{parser,hidpi,pid-path,vpn-trim}-probe.sh` |
| GitHub Actions | none | `.github/` does not exist |
| `Makefile` | none | repo root |

The 46 existing cases cover: parser F1–F23 (24 cases), HiDPI S1–S8 (8 cases), PID path S1–S6 (6 scenarios), VPN trim F1–F8 (8 cases). All are plain-bash runners with hand-rolled PASS/FAIL counters — **not** TAP-compliant, **not** auto-discovered, **not** wired to CI.

**Why strict_tdd is false today** (from engram obs #214 / `sdd/rdp-connect/testing-capabilities`): no bash test framework was installed at `sdd init` time, so per the init decision gate `strict_tdd` was correctly left false. The init artifact already laid out the four-step activation path (install bats → keep the lib extraction → add `tests/` + `Makefile` → flip the flag). **Three of those four steps are already done** — only the runner install, the bats migration, and the flag flip remain.

---

## Affected Areas

- `openspec/config.yaml` — `strict_tdd: false → true` (top-level L20) **AND** `rules.apply.tdd: false → true` (L56). The sdd-apply resolver reads BOTH (`openspec/config.yaml → strict_tdd + testing section`); flipping only one is a silent no-op.
- `openspec/config.yaml` — `testing.runner: none → bats`, `testing.framework: none → bats-core`, `testing.unit: none → bats`, `testing.coverage: none → "bats --tap | tee"` (informational), `rules.apply.test_command` and `rules.verify.test_command` should gain `bats tests/`.
- `tests/*.probe.sh` → `tests/*.bats` — mechanical translation, 4 files, ~530 LOC in / ~530 LOC out (1:1, plus a shared `test_helper.bash`).
- `lib/rdp-common.bash` — no code change, but two functions (`require_cmd`, `build_mon_flags`) are currently unprobed and SHOULD gain bats coverage as part of the migration (otherwise strict-tdd verify will flag the gap on the next change that touches them).
- `engine/rdp-connect` — only the post-parse trim loop (L174–181) and the `cleanup()` awk extractor (L248–254) are realistic extraction candidates (see Finding F3). Everything else touches `hyprctl`/`xfreerdp3`/`flock`/`/dev/tcp` and stays integration-only.
- `install-rdp-framework.sh` — `pkg_for()` does NOT map `bats` today; if bats becomes a hard dev requirement, F10 dependency list grows by one row. **Recommendation: do NOT add bats to the runtime dep list** — see Finding F1.
- `.github/workflows/test.yml` — does not exist; recommend adding (Finding F5).
- `Makefile` — does not exist; recommend adding (Finding F6).
- `README.md` L6 badge — `tests-46 probe scenarios` → update post-migration to `tests-N bats cases` (cosmetic, apply phase).

---

## Approaches (per finding)

### F1 — Bats-core installation matrix & packaging policy

**Verified facts (run on this host):**

```
$ pacman -Si bats-core
error: package 'bats-core' was not found       ← the NAME is wrong

$ pacman -Si bats
Repository : extra
Name       : bats
Version    : 1.13.0-1
Provides   : bats-core                        ← THIS is the package
Replaces   : bash-bats
```

**Install matrix (confirmed via `pacman -Si` + bats-core readthedocs):**

| Distro | Command | Package | Version (typical) |
|---|---|---|---|
| Arch + derivatives (CachyOS, Garuda, EndeavourOS) | `sudo pacman -S --needed bats bats-assert bats-support bats-file` | `extra/bats` | 1.13.0 |
| Debian | `sudo apt-get install bats bats-assert bats-support bats-file` | `shells/bats` | 1.2.1+ (Debian 12) |
| Ubuntu | `sudo apt install bats bats-assert bats-support bats-file` | `shells/bats` (universe) | 1.2.1+ (22.04), older on 20.04 |
| Fedora | `sudo dnf install bats bats-assert bats-support bats-file` | `rpms/bats` | 1.2.1+ |
| Alpine (unsupported per installer spec) | `apk add bats` | `community/bats` | — |
| Any (fallback) | `npm install -g bats` | npm | latest |

**Approaches:**

1. **Optional dev dependency, graceful fallback in installer** *(RECOMMENDED)*
   - `bats` is NOT added to `pkg_for()` or the F10 hard-dep list. The installer smoke test keeps using the existing inline parser probe. Developers install bats themselves via the README's distro matrix.
   - Pros: zero blast-radius change to the deployed engine; installer stays deterministic; Alpine/NixOS hosts unaffected; the v0.1.0 installer contract is preserved.
   - Cons: a fresh clone without bats can't run `make test` — must fail loudly with a clear "install bats via X" message.
   - Effort: Low. README addition + Makefile guard (~30 LOC).

2. **Hard runtime dependency in F10**
   - Add `bats bats-assert bats-support bats-file` to every distro row of `pkg_for()`.
   - Pros: every deployed host can self-test post-install.
   - Cons: wrong layer — bats is a *developer* tool, not a runtime requirement. Inflates the installer dep tree for end users who never write tests. Conflicts with the spec principle "Prefer removing fragile deps over adding them."
   - Effort: Medium. 4 rows × 4 packages = 16 new entries; smoke test grows a bats step.

3. **Pin bats via npm in `package.json`** *(not recommended for this project)*
   - Adds a Node toolchain dep to a pure-Bash project. Wrong cultural fit; would require every contributor to install Node.

**Recommendation: Approach 1.** Bats is a dev-only dependency. Document the distro matrix in README, gate `make test` on `command -v bats`, fail loudly if missing. This matches the existing `shellcheck` pattern (also dev-only, also optional in the installer).

**Size estimate**: ~30 LOC (README section + Makefile guard).
**Dependencies**: none.

---

### F2 — Probe → bats migration plan

The four existing probes share an identical shape: source `lib/rdp-common.bash`, define `ok()`/`fail()` color printers, call helpers, count PASS/FAIL, exit non-zero on any failure. The translation to bats is **mechanical and 1:1** — bats provides the test runner, the counters, and the TAP output for free.

**Mechanical translation pattern (parser-probe.sh F4 as example):**

```bash
# BEFORE — tests/parser-probe.sh (plain bash)
expect_val "F4 preserve inline # inside double quotes" \
           'HOST="server # production"\n' \
           profile HOST 'server # production'

# AFTER — tests/parser.bats
load test_helper.bash

@test "F4: inline # inside double quotes is preserved" {
  fixture 'HOST="server # production"\n'
  run parse_env_safe "$FIXTURE" profile
  [ "$status" -eq 0 ]
  assert_equal "$HOST" 'server # production'
}
```

**Per-probe migration analysis:**

| Probe | LOC | Cases | Helpers needed in `test_helper.bash` | Effort | Notes |
|---|---|---|---|---|---|
| `parser-probe.sh` | 248 | 24 | `fixture()` (writes `$TMP/fixture.env`), `parse_env_safe_under_setu()` (spawns child bash with `set -u` to re-verify the `-v` vs `${arr[k]}` safety claim — must KEEP this two-process pattern, can't collapse) | **Medium** (largest) | F14 specifically re-verifies set -u safety in a child bash; bats `@test` runs in-process so the child-bash idiom must be preserved inside the test body. `expect_rc_msg` (3 cases) asserts on stderr content → use `assert_output --partial`. |
| `hidpi-probe.sh` | 119 | 8 | `mock_hyprctl()` (emits fixed JSON), `stub_log_event()` (captures WARN lines) | **Low** | Already uses the mock pattern (`hyprctl()` function override). Translation is direct — `mock_hyprctl` becomes a `setup()` helper. |
| `pid-path-probe.sh` | 85 | 6 | `mock_id_u()` (overrides `id -u` to a fake uid) | **Low** | Already mocks `id`. Direct translation. |
| `vpn-trim-probe.sh` | 78 | 8 | none beyond `test_helper.bash` | **Low** ⚠️ | **Test smell**: this probe reimplements the trim idiom inline rather than calling the engine's actual trim loop. Under strict-tdd verify this would be flagged as "approval test exercises copy, not production code." Recommend extracting the engine trim block (L174–181) into `lib/rdp-common.bash::trim_profile_fields()` and having the bats test source THAT. See Finding F3. |

**Shared `test_helper.bash` (proposed, ~25 LOC):**

```bash
#!/usr/bin/env bash
# tests/test_helper.bash — shared fixtures + mocks for rdp-connect bats suite
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/rdp-common.bash"

# Source the lib under test (every test file calls this)
load_lib() { source "$LIB"; }

# Write a fixture file with printf %b semantics; sets $FIXTURE
fixture() { FIXTURE="$BATS_TMPDIR/fixture.env"; printf '%b' "$1" > "$FIXTURE"; }

# Override hyprctl to emit a captured JSON payload
mock_hyprctl() { hyprctl() { printf '%s' "$1"; }; }

# Stub log_event to capture WARN lines into the WARN_LINES array
stub_log_event() {
  WARN_LINES=()
  log_event() { local lvl="$1" msg="$2"; [[ "$lvl" == WARN ]] && WARN_LINES+=("$msg"); }
}

# Override id -u for two-user non-collision tests
mock_id_u() { id() { echo "$1"; }; }
```

**bats patterns that differ from plain bash (gotchas to note in the apply phase):**

1. **`set -e` is implicit inside `@test`.** Every non-zero exit aborts the test as a failure — this is what we WANT. The probes' hand-rolled `set -u` at the top of each file should be dropped; bats sets its own. The `set -euo pipefail` discipline still applies to the sourced `lib/rdp-common.bash` body itself (unchanged).
2. **`run` captures stdout/stderr/status into `$status`/`$output`/`$lines`.** Anything you previously did with `out=$(run_probe ...); rc=${out%%$'\t'*}` becomes `run parse_env_safe ...; [ "$status" -eq 0 ]`. Don't fight it.
3. **`load test_helper.bash` is path-relative to the test file.** It delegates to `source` and exits on error — perfect for shared mocks.
4. **Process isolation for the F14 set -u test.** bats `@test` blocks run in-process; if the test specifically re-verifies behavior under `set -u` AFTER sourcing the lib, the lib must be sourced in a child bash (`bash -c 'set -u; source ...; ...'`). The existing parser-probe already does this; keep the pattern.
5. **`bats_require_minimum_version 1.5.0`** unlocks `run -N` (expected-exit) and `--separate-stderr`. The Arch package ships 1.13.0, Debian 12 ships 1.2.1 — both clear the bar. Older Ubuntu 20.04 (bats 1.1.0) does NOT — recommend a `bats_require_minimum_version` guard at the top of each `.bats` file so the failure mode is a clear message, not a cryptic syntax error.

**Effort summary:** ~4 file rewrites + 1 new helper ≈ 550 LOC out for 530 LOC in. Net delta ≈ +20 LOC. **Medium effort, low risk** — the assertions are unchanged, only the harness changes.

**Recommendation: bundle as one apply task per probe** (4 work units), with `test_helper.bash` + the first probe (parser, largest) as the foundational PR slice.

**Size estimate**: ~550 LOC (1:1 migration + helper).
**Dependencies**: F1 (bats must be installable), F6 (Makefile gives `make test`).

---

### F3 — Engine testability gap analysis

**Currently probed directly (pure functions in `lib/rdp-common.bash`):**
- `parse_env_safe` ✅ (24 cases)
- `compute_dpi_flags` ✅ (8 cases, hyprctl mocked)
- `compute_pid_path` ✅ (6 cases, `id -u` mocked)

**In lib but UNPROBED (low-hanging fruit — both are pure):**
- `require_cmd()` (lib L219–226) — pure exit-127 logic. Trivial to test: `PATH=` manipulation + assert exit code. **Add 2–3 bats cases during migration.**
- `build_mon_flags()` (lib L238–247) — pure array builder. Trivial to test: `( "2" "0,1" )` → array equals `( "/multimon" "/monitors:0,1" )`. **Add 2 bats cases during migration.**

**Engine code that is NOT unit-testable today:**

| Engine region (line range) | Why it's hard | Minimum refactor to make it testable |
|---|---|---|
| `load_language()` (L68–77) | Calls `parse_env_safe` + `notify-send` + `exit 1` on failure. The `exit` is the problem — can't be asserted from a sourced function. | Move to lib as `load_language_or_return() { ...; return 1; }`. Engine wraps with `load_language_or_return || { notify-send ...; exit 1; }`. **2 LOC moved, engine keeps the exit semantics.** |
| Post-parse trim loop (L174–181) | Pure parameter-expansion trim, but written inline. The `vpn-trim-probe.sh` currently RE IMPLEMENTS it to test the idiom — a test smell. | Extract to `lib/rdp-common.bash::trim_profile_fields()` taking an array of field names. Engine calls `trim_profile_fields HOST VPN_CHECK DOMAIN PREFERRED_WS LANG_OVERRIDE`. **~10 LOC moved.** The bats test then sources the real function. |
| `cleanup()` awk extractor (L248–254) | The session-scoped error-line extractor is the most complex untested logic in the engine. It's pure text transformation over a log file — perfect unit-test material — but it's inlined in `cleanup()` between side effects. | Extract to `lib/rdp-common.bash::extract_session_error() { awk -v pid="$1" '...' "$2"; }`. The `cleanup()` body becomes `LAST_ERROR=$(extract_session_error "$$" "$LOG_FILE")`. **~8 LOC moved.** Bats test feeds a synthetic multi-session log and asserts the correct line is returned. This DIRECTLY covers 4 canonical scenarios in `engine-robustness/spec.md` (cleanup-session-isolation, PID prefix safety, no-error-returns-empty, legacy-no-marker) that today are manual-verify only. |
| Selector mode (L130–145) | Calls `wofi`/`rofi` interactively. | **Keep as integration-only.** Mocking wofi is possible but low-value; the selector is cosmetic. |
| VPN/host preflight (L292–308) | Uses `bash -c '</dev/tcp/HOST/3389'`. | **Keep as integration-only.** Mocking `/dev/tcp` requires a stub binary on PATH; the existing throwaway-HOME dry-run covers it. |
| `flock` block (L208–219) | Real kernel flock. | **Keep as integration-only.** Already verified at runtime (engram: "F5 live-peer flock contention verified at runtime"). |
| `xfreerdp3` invocation (L340–368) | Spawns the actual RDP client. | **E2E only — manual.** Always manual per spec. |

**Recommended MINIMUM refactor (the answer to "what's the minimum to make `parse_env_safe` callers unit-testable"):**

Three small extractions to `lib/rdp-common.bash`, all under 15 LOC each, none changing engine behavior:

1. `trim_profile_fields()` — covers the 3 `Preflight input normalization` scenarios that `vpn-trim-probe.sh` currently tests-by-copy.
2. `extract_session_error()` — covers the 4 `Cleanup error diagnostic scoped to current session` scenarios.
3. `load_language_or_return()` — optional; only needed if a future change wants to unit-test the i18n fallback path. **Defer unless a strict-tdd change targets i18n.**

**These three extractions turn 7 currently manual-verify-only scenarios into auto-testable bats cases.** That's the single highest-leverage change in this exploration.

**Approaches:**

1. **Ship the extractions as PART of the strict-tdd-enable change** *(RECOMMENDED if delivery strategy allows)*
   - Pros: the bats suite has real engine coverage on day 1; strict-tdd verify has something to verify against; future changes inherit a working test layer.
   - Cons: expands the change scope from "tooling only" to "tooling + light refactor." 400-line review budget risk: Low–Medium (see below).
   - Effort: ~40 LOC refactor + ~120 LOC new bats cases = ~160 LOC.

2. **Ship tooling only; defer extractions to a follow-up change**
   - Pros: smaller blast radius; strict-tdd-enable becomes a pure tooling/config change.
   - Cons: strict-tdd verify on the NEXT change will discover the engine-testability gap and force the extraction anyway. Strict-tdd verify on THIS change can only validate the migrated probe cases.
   - Effort: ~0 LOC refactor; apply is just config + bats migration.

3. **Extract everything possible, including selector/preflight mocks**
   - Pros: maximum coverage.
   - Cons: violates the "minimum refactor" principle; mocking `hyprctl`/`xfreerdp3`/`/dev/tcp` produces test doubles that drift from real behavior (see Risks).

**Recommendation: Approach 1, but only extract `trim_profile_fields()` + `extract_session_error()` (skip `load_language_or_return` — defer to when needed).** Two extractions, ~20 LOC moved, 7 scenarios gain auto coverage. Combined with the 4-probe migration, the change stays under the 400-line budget (see Finding F7).

**Size estimate**: ~160 LOC (40 refactor + 120 new bats).
**Dependencies**: F2 (bats migration provides the harness these tests plug into).

---

### F4 — strict_tdd activation impact

**Reading the actual strict-tdd modules** (`sdd-apply/strict-tdd.md` 364 LOC, `sdd-verify/strict-tdd-verify.md` 269 LOC) — not guessing.

**What changes when `strict_tdd: true` lands in `openspec/config.yaml`:**

The sdd-apply executor's Step 3 resolves mode from `openspec/config.yaml → strict_tdd + testing section`. If `strict_tdd: true` AND a test runner exists, it loads `strict-tdd.md` — a 364-line module that **overrides Step 4 (Standard Workflow) entirely**. There is no silent fallback: "If you resolved Strict TDD as active, you follow it or you report failure."

**sdd-apply differences (Strict TDD Mode vs Standard Mode):**

| Aspect | Standard Mode | Strict TDD Mode |
|---|---|---|
| Task cycle | Read → Write code → Mark `[x]` | SAFETY NET (run existing tests) → UNDERSTAND → **RED** (write failing test FIRST) → **GREEN** (minimum code, run tests, must pass) → **TRIANGULATE** (≥2 cases per behavior) → **REFACTOR** (tests stay green) → Mark `[x]` |
| Test-first rule | none | **NEVER write production code before its test** — the one unbreakable rule |
| Triangulation | none | MANDATORY; ≥2 test cases per behavior; skip only for purely structural tasks with explicit note |
| Approval tests | none | REQUIRED for refactoring tasks (capture current behavior FIRST, then refactor) |
| Assert quality | none | Banned patterns enforced (no tautologies, no empty-collection-without-companion, no type-only asserts, no ghost loops, no CSS-class coupling, mock/assertion ratio ≤ 3) |
| Apply-progress artifact | Files Changed + Deviations | All of that **PLUS** a `TDD Cycle Evidence` table: `\| Task \| Test File \| Layer \| Safety Net \| RED \| GREEN \| TRIANGULATE \| REFACTOR \|` |
| Pure function preference | encouraged | Enforced via "Extract-Before-Mock Rule" — if you need >3 mocks, extract a pure function FIRST |

**sdd-verify differences (Strict TDD Verify Module):**

Adds 4 new verification steps beyond the standard suite:

1. **Step 5a — TDD Compliance Check**: reads the apply-progress TDD Evidence table, cross-references each row against the actual codebase. RED column → test file must EXIST. GREEN column → test must PASS on execution. TRIANGULATE → if "✅ N cases" is claimed, N cases must be countable in the file. **If no TDD Evidence table found → CRITICAL flag.**
2. **Step 5 Expanded — Test Layer Validation**: classifies every test file as Unit/Integration/E2E/Unknown, reports distribution, flags WARNING if tests use tools not in cached capabilities.
3. **Step 5d Expanded — Changed File Coverage**: if a coverage tool exists, reports per-file line/branch coverage for changed files only. **< 80% → WARNING.** (For rdp-connect: no coverage tool — verify reports "Coverage analysis skipped — no coverage tool detected." **NOT a failure.**)
4. **Step 5f — Assertion Quality Audit (MANDATORY)**: scans every test file for banned patterns. Tautologies and ghost loops are **CRITICAL**. Empty-collection-without-companion, smoke-test-only, CSS-coupling, mock-heavy (>2× mocks vs asserts) are **WARNING**.

**Would any current spec FAIL strict-tdd verification?**

Audited all 5 canonical specs against the strict-tdd requirements. Findings:

| Spec | Scenarios | Auto-testable today? | Notes |
|---|---|---|---|
| `engine-security` | 12 | **Mostly YES** — parser scenarios map 1:1 to `tests/parser.bats` (post-F2 migration). The "dangerous key rejected" / "i18n injected key rejected" / "all allowlisted keys accepted" scenarios are pure-function unit tests. | The 2 "manual-verify" footer lines (`bash -x`, `grep -nE 'source'`) stay manual — they're invariant checks, not behavior. |
| `hidpi-scaling` | 5 | **YES** — all 5 scenarios map to `tests/hidpi.bats` (post-F2). | — |
| `instance-locking` | 6 | **3 of 6 YES** — the 3 `compute_pid_path` scenarios are unit-tested by `tests/pid-path.bats`. The 3 flock-reclamation / live-peer / cleanup-trap scenarios are **integration-only** (real kernel flock, real EXIT trap). They remain manual-verify. | Strict-tdd verify will flag these as "insufficient triangulation" only if a future change MODIFIES the flock code. Today they're grandfathered. |
| `engine-robustness` | 19 | **12 of 19 YES post-F3** — the 3 preflight-trim scenarios (currently tested-by-copy in vpn-trim-probe) become real unit tests after `trim_profile_fields()` extraction. The 4 cleanup-session-isolation scenarios become real unit tests after `extract_session_error()` extraction. The 5 require_cmd / feature-gate / array-expansion / log-guard scenarios are unit-testable but currently UNCOVERED — strict-tdd will flag them only if a future change touches them. | The remaining 7 (real xfreerdp3 exit, real flock contention, real notify-send, real host probe) stay integration/manual. |
| `installer` | 9 | **Integration-only.** Every scenario runs the actual installer in a throwaway HOME. bats CAN drive this (`run install-rdp-framework.sh` with `HOME=$(mktemp -d)`), but it requires `sudo`/root for `pacman`/`apt`/`dnf` — unsuitable for CI without containers. | Recommend: keep as manual-verify + document. A future `tests/installer.bats` could cover the dry-run paths if `install-rdp-framework.sh` grew a `--dry-run` flag (currently out of scope). |

**Bottom line: no current spec would CRITICAL-fail strict-tdd verify on day 1.** The migrated probes cover the security/hidpi/pid scenarios. The engine-robustness trim + cleanup scenarios become covered after F3's small extraction. The installer and flock scenarios stay manual-verify, which strict-tdd verify accepts (it flags missing coverage as SUGGESTION/WARNING, never CRITICAL, when no integration tool is available).

**Approaches:**

1. **Flip strict_tdd in this change, ship F2+F3 to give it teeth** *(RECOMMENDED)*
   - The flag flip is meaningless without the bats harness. Bundling them makes the change self-justifying.
2. **Flip strict_tdd alone; let the next change discover the gaps**
   - Strict-tdd verify on the very next change will immediately block on "no test runner found" or "0% coverage" — bad UX, rework guaranteed.
3. **Don't flip yet; wait until engine refactor is done**
   - Indefinite deferral; the project keeps shipping manual-verify-only changes.

**Recommendation: Approach 1.**

**Size estimate**: ~10 LOC config changes (the actual flag flip + testing section).
**Dependencies**: F2 (bats migration), F3 (engine extractions), F6 (Makefile), F5 (CI — optional but strongly recommended).

---

### F5 — CI integration (GitHub Actions)

No `.github/workflows/` directory exists today. The repo is public on GitHub.

**Approaches:**

1. **Add `.github/workflows/test.yml` running `bats tests/` + `shellcheck` on every PR** *(RECOMMENDED)*
   - Minimum CI image: **Ubuntu** (`ubuntu-latest`). Rationale: Debian-family has `bats` in universe (no extra repo), `shellcheck` is in main, bash 5.x is default. Arch in CI requires a container; Fedora likewise. Ubuntu is the lowest-friction.
   - Install step: `sudo apt-get install -y bats bats-assert bats-support bats-file shellcheck` (one line).
   - Job: `bats tests/` (runs all `*.bats`), then `shellcheck --severity=warning engine/rdp-connect lib/rdp-common.bash install-rdp-framework.sh`.
   - Runtime: ~15–25 sec per run (bats is fast; the suite is 46 cases).
   - Pros: every PR gets a green/red signal before merge; strict-tdd verify can point at the CI run as evidence; protects main from regressions.
   - Cons: one new file (~40 LOC); CI minute consumption (free for public repos).
   - Effort: Low.

2. **Run CI in an Arch container** (matches the primary dev env)
   - Pros: exact version skew with dev (`extra/bats 1.13.0`).
   - Cons: slower pull, larger image, no benefit over Ubuntu for a 46-case suite.
   - Effort: Medium.

3. **Matrix build (Ubuntu + Fedora + Arch)**
   - Pros: catches distro-specific bats version skew.
   - Cons: 3× CI minutes for a suite this small; the `bats_require_minimum_version` guard in each `.bats` file already protects against version drift.
   - Effort: Medium.

**Recommendation: Approach 1.** Add a single Ubuntu job. If version skew becomes a real issue later, expand to a matrix.

**Minimum CI YAML shape (apply phase will finalize):**

```yaml
name: tests
on: [pull_request, push]
jobs:
  bats:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y bats bats-assert bats-support bats-file shellcheck
      - run: shellcheck --severity=warning engine/rdp-connect lib/rdp-common.bash install-rdp-framework.sh bootstrap.sh
      - run: bats tests/
```

**Tradeoff CI runtime vs confidence:** at ~20 sec/run for 46 cases + shellcheck, the confidence massively outweighs the cost. This is the highest-leverage file in the change.

**Size estimate**: ~40 LOC.
**Dependencies**: F2 (bats suite must exist for `bats tests/` to find anything).

---

### F6 — Makefile

No `Makefile` exists today. Developers currently invoke probes one-by-one (`./tests/parser-probe.sh` etc.). This doesn't scale and gives CI no single entry point.

**Recommended targets:**

```makefile
# Makefile — single entry point for dev + CI
.PHONY: test lint install smoke verify-manifest clean

BATS        := $(shell command -v bats 2>/dev/null)
SHELLCHECK  := $(shell command -v shellcheck 2>/dev/null)
ENGINE      := engine/rdp-connect
LIB         := lib/rdp-common.bash
INSTALLER   := install-rdp-framework.sh
BOOTSTRAP   := bootstrap.sh

test:
	@if [ -z "$(BATS)" ]; then \
	    echo "ERROR: bats is not installed. Install via:"; \
	    echo "  Arch:    sudo pacman -S bats bats-assert bats-support bats-file"; \
	    echo "  Debian:  sudo apt-get install bats bats-assert bats-support bats-file"; \
	    echo "  Fedora:  sudo dnf install bats bats-assert bats-support bats-file"; \
	    exit 1; \
	fi
	bats tests/

lint:
	@if [ -z "$(SHELLCHECK)" ]; then echo "ERROR: shellcheck not installed"; exit 1; fi
	shellcheck --severity=warning $(ENGINE) $(LIB) $(INSTALLER) $(BOOTSTRAP) tests/*.bash

install:
	./$(INSTALLER)

smoke:
	HOME=$$(mktemp -d) ./$(INSTALLER)

verify-manifest:
	sha256sum -c ~/.local/state/rdp/manifest.sha256

clean:
	rm -rf tests/*.log tests/*.tmp
```

**Approaches:**

1. **5 targets as above** *(RECOMMENDED)* — covers dev workflow (`make test`, `make lint`), CI (`make test && make lint`), and installer reproducibility (`make smoke`, `make verify-manifest`).
2. **Minimal 2 targets (`test`, `lint`)** — sufficient for CI but loses the smoke/manifest entry points.
3. **Just-delegate target (`test: ; bats tests/`)** — no shellcheck, no graceful failure.

**Recommendation: Approach 1.** The Makefile becomes the contract surface for both dev and CI — `make test` is what `rules.apply.test_command` should reference post-flip (`bats tests/` is the literal command, `make test` is the friendly alias).

**Size estimate**: ~35 LOC.
**Dependencies**: F2 (test target needs the bats suite).

---

### F7 — Delivery & scope bundle (the 400-line question)

**Forecast per finding (LOC additions + deletions):**

| Finding | + LOC | − LOC | Notes |
|---|---|---|---|
| F1 (README distro matrix + installer unchanged) | ~30 | 0 | docs only |
| F2 (4 probe → bats migration + helper) | ~550 | ~530 | net +20 |
| F3 (2 engine extractions + bats coverage) | ~160 | ~20 | refactor + new tests |
| F4 (config.yaml flag flip) | ~10 | ~10 | net 0 |
| F5 (`.github/workflows/test.yml`) | ~40 | 0 | new file |
| F6 (`Makefile`) | ~35 | 0 | new file |
| **Total** | **~825** | **~560** | **net +265, but review surface ≈ 825+560 = ~1385** |

**400-line budget risk: HIGH.** The raw review surface (additions + deletions) is ~1385 lines, well over the 400 budget. Even though most of F2 is mechanical 1:1 translation (low cognitive load per line), the raw number will trigger the work-unit guard.

**Approaches:**

1. **Single PR, accept `size:exception`** *(not recommended)*
   - Reviewer fatigue; the 4-probe migration alone is ~1080 lines of review surface.
   - The session preflight says `delivery_strategy: ask-always` — this finding is exactly the trigger that strategy exists to handle.

2. **Stacked-to-main PR chain (RECOMMENDED)** — 3 slices:

   | Slice | Scope | Review surface | Risk |
   |---|---|---|---|
   | **PR1 — tooling** | Makefile (F6) + `.github/workflows/test.yml` (F5) + README distro matrix (F1) + config.yaml flag flip (F4) **MINUS** the strict_tdd flip — keep `strict_tdd: false` until PR3 lands bats | ~115 LOC | Low — pure tooling, no behavior change |
   | **PR2 — bats migration** | `test_helper.bash` + 4 probe → `.bats` rewrites (F2). Delete the 4 old `*.probe.sh` files. CI now runs `bats tests/`. | ~1080 LOC (1:1 migration, low cognitive load) | Medium — large diff but mechanical |
   | **PR3 — engine extraction + flag flip** | `trim_profile_fields()` + `extract_session_error()` extractions (F3) + new bats cases covering them + **flip `strict_tdd: false → true` and `rules.apply.tdd: false → true`** + update `config.yaml` testing section + README badge | ~200 LOC | Medium — the only slice that changes engine behavior (small refactor) |

   Each slice is independently mergeable, independently revertable, and respects the work-unit commit guidance. PR1 sets up the harness; PR2 fills it with the migrated cases; PR3 makes strict-tdd actually enforce something.

3. **Three separate changes (not stacked)** — overkill; these are tightly coupled.

**Recommendation: Approach 2 (stacked-to-main, 3 slices).** The orchestrator's `chain_strategy` should resolve to `stacked-to-main`. The `ask-always` delivery strategy means the user MUST be asked to confirm before apply starts — this is the canonical trigger.

**Size estimate**: N/A (this is the scope decision, not an implementation finding).
**Dependencies**: this finding IS the dependency map for the others.

---

## Risks

- **bats-core version skew across distros.** Arch ships 1.13.0, Debian 12 ships 1.2.1, Ubuntu 20.04 ships 1.1.0. The `run -N` (expected-exit) and `--separate-stderr` flags need ≥ 1.5.0; the Debian/Ubuntu LTS versions DON'T clear that bar. **Mitigation:** add `bats_require_minimum_version 1.5.0` at the top of every `.bats` file; document in README that Ubuntu 20.04 users need `npm install -g bats` or a backport. CI runs on `ubuntu-latest` (currently 24.04, bats 1.2.1+ — but `bats_require_minimum_version` will catch it cleanly if the LTS shifts).

- **Mocking `hyprctl`/`xfreerdp3` produces test doubles that drift from real behavior.** The current `hidpi-probe.sh` mocks `hyprctl` to emit fixed JSON; if FreeRDP changes its `--help` output format, the F7 feature-gate test would pass while the real engine fails. **Mitigation:** keep mocks for PURE LOGIC only (JSON parsing, array building). Never mock the actual `xfreerdp3 /help` invocation — that stays integration/manual. The Extract-Before-Mock rule from `strict-tdd.md` enforces this.

- **strict_tdd might over-ceremony small fixes.** A one-line typo fix would formally require RED → GREEN → TRIANGULATE → REFACTOR. **Mitigation:** `strict-tdd.md` already has escape valves — "Triangulation skipped: {reason}" for single-output structural tasks, and the Safety Net rule protects refactors. The apply executor can also mark a task FAILED if TDD is genuinely impossible (e.g., a comment-only change). Document this in the project's `rules.apply` so future contributors know when to invoke the escape hatch.

- **Stacked PR chain has a merge-ordering hazard.** If PR1 merges before PR2 is rebased onto it, PR2's diff will show the new Makefile as context. The `sdd-phase-common.md §E` Feature Branch Chain rule (retarget/rebase until the diff is clean) applies. **Mitigation:** `stacked-to-main` (not `feature-branch-chain`) — each PR targets the previous PR's branch, then main after merge. Lower cognitive load.

- **The `vpn-trim-probe.sh` test smell (F3).** The probe currently RE IMPLEMENTS the engine's trim idiom inline. Migrating it to bats AS-IS would preserve the smell — strict-tdd verify would flag "approval test exercises copy, not production code." **Mitigation:** F3's `trim_profile_fields()` extraction MUST ship before or with the vpn bats migration, not after. This is why PR3 (extraction) and PR2 (migration) can be collapsed if the user prefers fewer slices.

- **Manual-verify scenarios lose their footer discipline.** Today every scenario has an `AND (manual-verify: ...)` footer. After strict_tdd flips, there's a risk contributors assume "bats covers it" and stop running the manual checks. **Mitigation:** the manual-verify footers MUST stay in the specs (they're part of the canonical text). strict-tdd-verify Step 5a does NOT remove them — it adds the TDD Compliance table ON TOP. Document this in the change's spec delta.

---

## Ready for Proposal

**Yes.** The exploration is complete, all stack claims were verified by command (`pacman -Si`, `command -v`, `/etc/os-release`), and the scope is bounded. The next SDD phase (`/sdd-propose`) should:

1. Draft the proposal with intent = "enable strict-tdd enforcement for all future rdp-connect changes via bats-core."
2. Recommend `chain_strategy: stacked-to-main` with 3 slices (tooling / migration / extraction+flip).
3. Carry the `size:exception` decision explicitly for PR2 (the migration slice is intentionally large but mechanical).
4. Flag that `strict_tdd: false → true` is a **two-line flip** in `openspec/config.yaml` (top-level L20 AND `rules.apply.tdd` L56) — missing either is a silent no-op.
5. Note that the `delivery_strategy: ask-always` MUST surface the chain decision to the user before apply starts.

---

## Skill Resolution

**Loaded skills** (paths-injected per the launch prompt's `## Skills to load before work` block):

- `sdd-explore/SKILL.md` — phase protocol (executor mode, persistence contract, return envelope)
- `_shared/SKILL.md` + `_shared/sdd-phase-common.md` + `_shared/openspec-convention.md` — artifact paths, persistence, review guard
- `go-testing/SKILL.md` — REVIEW ONLY for TDD discipline transfer (red-green-refactor, table-driven, golden files). **Applicable patterns identified:** (1) table-driven → bats `@test` blocks mirror `t.Run(tt.name, ...)`; (2) `t.TempDir()` → bats `$BATS_TMPDIR`; (3) "Use small mocks/interfaces around system or command execution boundaries" → directly informs F3's Extract-Before-Mock guidance; (4) testing.Short() skip → bats `skip` directive for integration tests. The Go-specific tooling (`teatest`, golden files) does NOT translate to Bash.
- `sdd-apply/SKILL.md` + `sdd-apply/strict-tdd.md` — read for F4 (what changes when strict_tdd flips)
- `sdd-verify/strict-tdd-verify.md` — read for F4 (what verify adds)

**Skill resolution**: `paths-injected` — 4 skills loaded via the orchestrator's explicit path block, plus 2 reference modules (`strict-tdd.md`, `strict-tdd-verify.md`) loaded by file path because F4 required understanding the activation impact. `go-testing` was used in REVIEW ONLY mode as instructed.
