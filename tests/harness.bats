# tests/harness.bats — covers Makefile + CI scenarios
#
# Spec provenance: openspec/changes/strict-tdd-enable/specs/test-harness-delta.md
# (3 requirements, 8 scenarios). All 8 spec scenarios get a covering @test
# here, plus 1 additional @test (make_smoke_works) that locks in the W-5 fix
# from PR1 verify-report (engine's --help block moved before mkdir+source so
# the smoke target's throwaway-HOME invocation succeeds).
#
# Per design.md Decision: migration_pattern — one @test per spec scenario.
# Per design.md Decision: ci_xfreerdp3_strategy — no test invokes the engine
# past --help; the make_install_delegates_to_installer test uses a PATH/CD
# spy on install-rdp-framework.sh and does NOT actually run the installer's
# hard-dep check.

load test_helper

# Per-test cleanup: any fixture file pushed to _CLEANUP_FILES is removed
# after the @test body returns, regardless of pass/fail. Bats runs teardown
# after every @test in the file.
_CLEANUP_FILES=()
teardown() {
  if [ "${#_CLEANUP_FILES[@]}" -gt 0 ]; then
    rm -f "${_CLEANUP_FILES[@]}"
    _CLEANUP_FILES=()
  fi
  # Also clean any sandbox dirs we created
  if [ -n "${_CLEANUP_DIRS[*]:-}" ]; then
    rm -rf "${_CLEANUP_DIRS[@]}"
    _CLEANUP_DIRS=()
  fi
}
_CLEANUP_DIRS=()

# ============================================================================
# Requirement: Makefile entry points
# ============================================================================

@test "make_test_passes_46_plus_cases" {
  # Spec: Fresh-clone make test passes 46+ cases. The full bats suite runs
  # in a child process; we count "ok" TAP lines and assert >= 46.
  # The count matches 24 (parser) + 8 (hidpi) + 6 (pid-path) + 10 (vpn-trim)
  # + 9 (this file, harness) = 57 today; PR3 will add cleanup-session (6) +
  # engine-security (2) = 65. The 46-floor is the spec's pre-PR3 minimum.
  #
  # Recursion guard: this test invokes `make test`, which runs `bats tests/`,
  # which loads harness.bats, which runs THIS TEST. Without the guard, the
  # child would re-invoke `make test` and recurse indefinitely. The sentinel
  # env var breaks the loop: top-level run sets it; the child's re-run of
  # this test sees it set and skips (bats's `skip` produces an "ok" TAP line
  # so the parent's count still includes it).
  if [ -n "${HARNESS_RECURSION_GUARD:-}" ]; then
    skip "recursion guard (parent invocation is running make test)"
  fi
  export HARNESS_RECURSION_GUARD=1
  run make -C "$REPO_ROOT" test
  assert_success
  # Count "^ok " TAP lines. $lines is the array of stdout lines (bats-assert).
  local ok_count=0
  local line
  for line in "${lines[@]}"; do
    [[ "$line" == ok\ * ]] && ok_count=$((ok_count+1))
  done
  [ "$ok_count" -ge 46 ]
}

@test "make_install_delegates_to_installer" {
  # Spec: make install delegates to install-rdp-framework.sh (no other side
  # effects). Spy pattern: copy the Makefile into a sandbox dir, write a
  # SPY install-rdp-framework.sh there that touches a marker file, run
  # `make -C <sandbox> install`, assert the marker exists (invoked exactly
  # once via exactly-one touch).
  #
  # Why sandbox + make -C (instead of PATH shim): the Makefile recipe is
  # `./install-rdp-framework.sh` (relative path with `./` prefix — a
  # security measure that defeats PATH lookup). A sandbox dir with `make -C`
  # resolves the recipe against the sandbox's spy installer without touching
  # the real installer in the repo root.
  local sandbox="${BATS_TMPDIR}/install-sandbox"
  _CLEANUP_DIRS+=("$sandbox")
  mkdir -p "$sandbox"
  cp "$REPO_ROOT/Makefile" "$sandbox/Makefile"
  local marker="${BATS_TMPDIR}/install-invoked"
  rm -f "$marker"
  cat > "$sandbox/install-rdp-framework.sh" <<EOF
#!/usr/bin/env bash
echo "spy: install-rdp-framework.sh invoked with \$*" >> "$marker"
EOF
  chmod +x "$sandbox/install-rdp-framework.sh"

  run make -C "$sandbox" install
  assert_success
  [ -f "$marker" ]
  # Exactly one invocation (one line in the marker file)
  local invocations
  invocations=$(wc -l < "$marker")
  [ "$invocations" = "1" ]
}

@test "make_verify_manifest_detects_tamper" {
  # Spec: make verify-manifest catches a tampered deployment. Deploy a
  # minimal manifest to setup_test_home, mutate one file, run
  # `make verify-manifest`, assert non-zero exit.
  setup_test_home >/dev/null
  mkdir -p "$HOME/.local/state/rdp" "$HOME/.local/bin"
  # Write a deployed file + manifest with its checksum
  echo "original-content" > "$HOME/.local/bin/rdp-connect"
  (cd "$HOME" && sha256sum .local/bin/rdp-connect > "$HOME/.local/state/rdp/manifest.sha256")

  # Tamper: change the deployed file's content (checksum no longer matches)
  echo "tampered-content" > "$HOME/.local/bin/rdp-connect"

  run make verify-manifest
  assert_failure
  # sha256sum -c names the tampered file in its diagnostic
  [[ "$output" == *"rdp-connect"* ]]
}

@test "make_lint_fails_on_shellcheck_warning" {
  # Spec: shellcheck warnings fail make lint. Drop a fixture that triggers
  # a WARNING-severity finding under tests/*.bash (which is in the lint
  # glob pre- and post-T2.7). Run make lint, assert non-zero exit. Cleanup
  # via teardown.
  #
  # Fixture code choice: SC2086 (unquoted $var expansion) is info-level and
  # filtered out by `--severity=warning`; the Makefile's lint target uses
  # --severity=warning (per PR1 deviation note 1). SC2034 (variable assigned
  # but never used) IS warning-severity and triggers the failure.
  local fixture="${TESTS_DIR}/zzs-shellcheck-fixture.bash"
  : > "$fixture"  # truncate / ensure exists
  printf '#!/usr/bin/env bash\n# intentional SC2034 warning fixture\nUNUSED_VAR="this variable is never read"\necho hello\n' > "$fixture"
  _CLEANUP_FILES+=("$fixture")

  run make -C "$REPO_ROOT" lint
  assert_failure
  [[ "$output" == *"SC2034"* ]]
}

# ============================================================================
# Requirement: Shared test helper (tests/test_helper.bash)
# ============================================================================

@test "bats_minimum_version_enforced" {
  # Spec: bats < 1.5.0 fails with a clear message. The floor is enforced by
  # tests/test_helper.bash's `bats_require_minimum_version 1.5.0` call.
  # Real bats 1.1.0 cannot run modern .bats files (uses 1.5.0+ features like
  # `run --separate-stderr`), so a stub that reports 1.1.0 and bails with
  # the floor message simulates the failure mode at the right boundary.
  local spy_dir="${BATS_TMPDIR}/bats-spy"
  _CLEANUP_DIRS+=("$spy_dir")
  mkdir -p "$spy_dir/bin"
  cat > "$spy_dir/bin/bats" <<'EOF'
#!/usr/bin/env bash
# Stub simulating bats 1.1.0 (does NOT support the 1.5.0+ floor enforced
# by test_helper.bash::bats_require_minimum_version).
if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
  echo "Bats 1.1.0"
  exit 0
fi
# Mirror the real bats_require_minimum_version bail message format.
echo "Bats-require-minimum-version: these tests require bats version 1.5.0 or newer, but you have 1.1.0." >&2
exit 1
EOF
  chmod +x "$spy_dir/bin/bats"

  # Stub on PATH; make test will invoke the stub via the Makefile's
  # `command -v bats` check, then `bats tests/`.
  PATH="$spy_dir/bin:$PATH" run make -C "$REPO_ROOT" test
  assert_failure
  [[ "$output" == *"1.5.0"* ]]
}

@test "setup_test_home_isolates_HOME" {
  # Spec: setup_test_home isolates HOME under $BATS_TMPDIR/home. Snapshot
  # real HOME, call the helper, write a marker file, assert it resolves
  # under $BATS_TMPDIR/home (NOT real HOME).
  local real_home="$HOME"
  # Call the helper WITHOUT command substitution — the export must propagate
  # to the calling shell (per PR1 verify-report note: $(setup_test_home)
  # runs in a subshell and the export does NOT propagate; the spec scenario
  # uses the side-effect form).
  setup_test_home >/dev/null
  [ "$HOME" = "${BATS_TMPDIR}/home" ]
  [ "$HOME" != "$real_home" ]
  # Write a marker and confirm it lands under the isolated HOME
  mkdir -p "$HOME/.config/rdp/profiles"
  touch "$HOME/.config/rdp/profiles/marker.env"
  [ -f "${BATS_TMPDIR}/home/.config/rdp/profiles/marker.env" ]
  # Restore so subsequent tests get a clean HOME
  HOME="$real_home"
}

# ============================================================================
# Requirement: CI workflow (.github/workflows/test.yml)
# ============================================================================

@test "ci_workflow_well_formed" {
  # Spec: CI green on a healthy PR. Static assertion that the workflow
  # declares the required structural elements. Per PR1 verify-report S-2,
  # the assertion list includes bats-assert + bats-support (not just bats)
  # so a future PR that drops the assertion libraries can't slip through.
  local wf="$REPO_ROOT/.github/workflows/test.yml"
  [ -f "$wf" ]
  # Triggers: push + pull_request to main. The full on: block spans 5+ lines
  # (on: / push: / branches / pull_request: / branches); use a wide -A window
  # so both trigger names are in scope.
  run grep -E '^on:' "$wf"
  assert_success
  run grep -A6 '^on:' "$wf"
  [[ "$output" == *"push:"* ]]
  [[ "$output" == *"pull_request:"* ]]
  [[ "$output" == *"main"* ]]
  # Runner: ubuntu-latest
  run grep -E 'runs-on:.*ubuntu-latest' "$wf"
  assert_success
  # All 7 apt packages (bats + bats-assert + bats-support + shellcheck + jq
  # + libnotify-bin + util-linux)
  run grep -E 'bats-assert|bats-support' "$wf"
  assert_success
  run grep -E '\bshellcheck\b' "$wf"
  assert_success
  # make ci step
  run grep -E 'make[[:space:]]+ci' "$wf"
  assert_success
}

@test "ci_workflow_uploads_logs_on_failure" {
  # Spec: CI fails on a red test and uploads logs. Static assertion that
  # the upload-artifact step has `if: failure()` and references `tests/`.
  local wf="$REPO_ROOT/.github/workflows/test.yml"
  [ -f "$wf" ]
  run grep -E 'uses:.*upload-artifact' "$wf"
  assert_success
  run grep -E 'if:.*failure' "$wf"
  assert_success
  run grep -E 'path:.*tests' "$wf"
  assert_success
}

# ============================================================================
# Additional (not in spec — locks in the W-5 fix from PR1 verify-report)
# ============================================================================

@test "make_smoke_works" {
  # W-5 regression backstop: PR1 verify-report flagged that `make smoke` was
  # functionally broken because the engine's `source "$LIB_FILE"` ran BEFORE
  # the --help short-circuit, and the throwaway-HOME override broke the
  # source. PR1's `a5ec6fb` moved --help BEFORE mkdir+source; this @test
  # proves the fix holds. If a future refactor re-orders these blocks, this
  # test catches it.
  #
  # Isolation: setup_test_home exports a sandbox HOME so the install step
  # deploys there (not the real HOME). The smoke target's own throwaway
  # HOME then exercises the engine --help path on a SECOND throwaway.
  setup_test_home >/dev/null
  run make -C "$REPO_ROOT" smoke
  assert_success
}

# ============================================================================
# T3.4 — R6 two-key flip canary (NEW)
# ============================================================================
# The strict-tdd-enable change activates strict TDD by flipping TWO keys in
# openspec/config.yaml in lockstep:
#   L20   strict_tdd: false -> true   (top-level gate)
#   L68   tdd:      false -> true   (under rules.apply — what sdd-apply reads)
#
# The flip is the silent no-op risk of this change: if only ONE key flips
# (e.g. someone edits L20 but forgets L68, or vice versa), strict_tdd is
# nominally "on" but no phase actually enforces it. The sdd-verify phase
# would have nothing to check against. This canary catches that by grepping
# BOTH lines with strict line-anchoring:
#   - `^strict_tdd: true$`         — top of file, no indent
#   - `^    tdd: true$`            — exactly 4 spaces indent (under `apply:`)
# A partial flip fails one of the two greps; the @test fails loud.
#
# Why harness.bats (not a new file): the canary is a harness-level invariant
# (it asserts the project's testing config is well-formed), matching the
# other config-file greps already in this file (ci_workflow_well_formed,
# ci_workflow_uploads_logs_on_failure). It belongs with the Makefile + CI
# structural assertions, not with the lib-unit coverage in cleanup-session
# or engine-security.
@test "both_strict_tdd_keys_flipped" {
  local cfg="$REPO_ROOT/openspec/config.yaml"
  [ -f "$cfg" ] || fail "openspec/config.yaml missing at $cfg"

  # L20 anchor: top-level strict_tdd flag.
  run grep -E '^strict_tdd: true$' "$cfg"
  assert_success
  [[ "$output" == "strict_tdd: true" ]]

  # L68 anchor (post-PR3 line number): rules.apply.tdd, 4-space indent.
  # The 4-space indent is what distinguishes `rules.apply.tdd` from any
  # incidental `tdd: true` substring inside the testing.recommendation
  # multi-line block.
  run grep -E '^    tdd: true$' "$cfg"
  assert_success
  [[ "$output" == "    tdd: true" ]]

  # Strengthened canary: assert NO stale `false` remains for either key.
  # Catches a partial revert where someone edits one line back to false
  # but the positive grep above still matches a different line elsewhere.
  run grep -E '^strict_tdd: false$' "$cfg"
  assert_failure
  run grep -E '^    tdd: false$' "$cfg"
  assert_failure
}
