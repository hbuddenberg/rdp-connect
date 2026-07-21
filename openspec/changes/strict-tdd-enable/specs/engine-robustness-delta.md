# Delta for engine-robustness

> **Capability**: `engine-robustness` (Modified) · **Change**: `strict-tdd-enable`
> **Existing behavior**: see `openspec/specs/engine-robustness/spec.md`. The 7
> scenarios under "Preflight input normalization" (3) and "Cleanup error
> diagnostic scoped to the current session" (4) keep their existing text and
> manual-verify footers. This delta layers on a testability contract and the
> lib-extraction invariants. Uses `## ADDED Requirements` exclusively — no
> existing requirement text changes (sdd-spec rule: additive → ADDED).

## ADDED Requirements

### Requirement: Scenario-to-test parity for robustness scenarios

Every scenario under "Preflight input normalization" and "Cleanup error
diagnostic scoped to the current session" in `engine-robustness/spec.md` MUST
have a corresponding `@test` block in `tests/vpn-trim.bats` (trim cases) or
`tests/cleanup-session.bats` (session-isolation cases) that exercises the SAME
Given/When/Then. Manual-verify footers stay (integration-level); the `@test`
covers the unit-level contract via extracted lib functions. This is what
`strict_tdd: true` enforces on this capability.

#### Scenario: All 7 robustness scenarios have @test parity

- GIVEN the 3 preflight-trim scenarios (whitespace-only `VPN_CHECK`,
  surrounding-whitespace `HOST`, padded `PASS_RDP`/`USER_RDP`) and the 4
  cleanup-session-isolation scenarios (stale prior-session ERROR, PID prefix
  collision `2222` vs `22222`, current-session no-ERROR, legacy
  no-SESSION_START)
- WHEN `bats tests/` runs
- THEN each of the 7 scenarios has a corresponding `@test` block
- AND every `@test` passes on a fresh clone (post-F3 extraction)

### Requirement: `trim_profile_fields()` extraction preserves byte-identical behavior

`trim_profile_fields()` MUST live in `lib/rdp-common.bash` (not inlined in
`engine/rdp-connect`). For any profile fixture, the extracted function MUST
produce byte-identical output to the current inline parameter-expansion idiom
for: `HOST`, `VPN_CHECK`, `DOMAIN`, `PREFERRED_WS`, `LANG_OVERRIDE`. The
function MUST NOT trim `PASS_RDP` or `USER_RDP` (reinforces the existing
"Preflight input normalization" requirement; security-side framing in
`engine-security-delta.md`).

#### Scenario: 8 vpn-trim fixtures pass byte-identical pre/post extraction

- GIVEN the 8 fixtures under `tests/fixtures/vpn-trim/` (whitespace-only,
  surrounding-whitespace, quoted-with-inline-comment, padded
  `PASS_RDP`/`USER_RDP` — R4 mitigation)
- WHEN `trim_profile_fields()` runs on each fixture
- THEN output matches the approval-test snapshot taken before extraction
- AND `PASS_RDP`/`USER_RDP` retain literal surrounding whitespace on every fixture
- AND (@test `vpn-trim.bats::trim_profile_fields_byte_identical_on_fixtures`: assert each fixture equals its snapshot under `tests/fixtures/vpn-trim/__snapshots__/`)

#### Scenario: @test coverage for `trim_profile_fields()`

- GIVEN `tests/vpn-trim.bats` sources `test_helper.bash` and exercises
  `trim_profile_fields` on the 8 fixtures
- WHEN `bats tests/vpn-trim.bats` runs
- THEN every `@test` passes (the "approval test exercises a copy, not
  production code" smell is killed because the function now lives in lib)
- AND (@test `vpn-trim.bats::trim_profile_fields_has_unit_coverage`: meta-assertion of ≥ 8 cases targeting the function)

### Requirement: `extract_session_error()` extraction preserves behavior

`extract_session_error()` MUST live in `lib/rdp-common.bash`. For any
`LOG_FILE` fixture, it MUST produce the SAME `LAST_ERROR` string as the
current inline `awk` extractor in the engine's cleanup trap. PID-scoping
semantics (prefix safety, empty fallback on no marker, generic "see log" on
legacy logs) MUST be preserved exactly — see the existing "Cleanup error
diagnostic scoped to the current session" requirement.

#### Scenario: Multi-session `LOG_FILE` fixtures match pre-extraction output

- GIVEN fixtures under `tests/fixtures/cleanup-session/` (prior-session-stale-
  ERROR, PID prefix collision, current-session-no-ERROR, legacy-no-
  SESSION_START)
- WHEN `extract_session_error()` runs on each fixture with the current PID injected
- THEN the returned `LAST_ERROR` matches the pre-extraction snapshot
- AND the empty-string fallback is preserved verbatim
- AND (@test `cleanup-session.bats::extract_session_error_byte_identical_on_fixtures`: assert each fixture's `LAST_ERROR` equals its snapshot)

#### Scenario: @test coverage for `extract_session_error()`

- GIVEN `tests/cleanup-session.bats` sources `test_helper.bash` and exercises
  `extract_session_error` on the 4 multi-session fixtures
- WHEN `bats tests/cleanup-session.bats` runs
- THEN all 4 session-isolation scenarios from `engine-robustness/spec.md` are
  covered by `@test` blocks and pass
- AND (@test `cleanup-session.bats::extract_session_error_has_unit_coverage`: meta-assertion of ≥ 4 cases targeting the function)
