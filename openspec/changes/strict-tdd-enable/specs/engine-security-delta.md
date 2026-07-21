# Delta for engine-security

> **Capability**: `engine-security` (Modified)
> **Change**: `strict-tdd-enable`
> **Existing behavior**: see `openspec/specs/engine-security/spec.md`. The
> baseline `parse_env_safe` key allowlist, quote/comment handling, and i18n
> loader requirements are unchanged. This delta documents that the post-parse
> trim step — downstream of `parse_env_safe` and security-relevant because it
> touches credential fields — MUST consume the extracted
> `trim_profile_fields()` helper rather than an inline idiom, and that the
> credential-exclusion invariant (`PASS_RDP`, `USER_RDP` MUST NOT be trimmed)
> has explicit `@test` coverage at the lib boundary.

## ADDED Requirements

### Requirement: Post-parse trim consumers use the extracted helper

The post-parse trim step in `engine/rdp-connect` MUST call
`trim_profile_fields()` from `lib/rdp-common.bash`. The engine MUST NOT inline
the `${VAR#"${VAR%%[![:space:]]*}"}` parameter-expansion idiom at the post-
parse call site — the trim allowlist MUST live in exactly one place (the lib
function) so drift between consumers is impossible.

The trim step MUST run AFTER `parse_env_safe` returns successfully and BEFORE
the VPN preflight guard. The allowlist consumed by `trim_profile_fields()`
MUST be exactly `{HOST, VPN_CHECK, DOMAIN, PREFERRED_WS, LANG_OVERRIDE}` —
5 fields trimmed, with `PASS_RDP` and `USER_RDP` explicitly excluded.

This requirement reinforces (does NOT replace) the existing "Preflight input
normalization" requirement in `openspec/specs/engine-robustness/spec.md`. The
robustness spec defines WHAT is trimmed; this spec defines WHERE the trim
logic MUST live so the security-critical exclusion list cannot drift between
consumers. The `@test` coverage at this boundary is the regression backstop:
an extraction that accidentally widens the allowlist is the highest-risk
vector in this change (silent credential corruption).

#### Scenario: Parser consumers call `trim_profile_fields()`, not inline trim

- GIVEN the deployed `~/.local/bin/rdp-connect` and `~/.local/share/rdp/lib/rdp-common.bash`
- WHEN the engine reaches the post-parse trim step on a parsed profile
- THEN `trim_profile_fields` is invoked from `lib/rdp-common.bash`
- AND the inline `${VAR#"${VAR%%...` idiom does NOT appear at the post-parse call site in the deployed engine
- AND (@test `engine-security.bats::engine_calls_trim_profile_fields_not_inline`: source both files in a bats fixture; intercept `trim_profile_fields` with a bats spy; invoke the engine's post-parse step on a fixture; assert the spy was called exactly once with the parsed profile)

#### Scenario: `trim_profile_fields()` allowlist is the documented 5 trimmed + 2 excluded

- GIVEN `lib/rdp-common.bash` defining `trim_profile_fields()` and a fixture
  `tests/fixtures/vpn-trim/all-fields.env` containing padded values for all
  7 profile fields
- WHEN `trim_profile_fields()` runs on the fixture
- THEN `HOST`, `VPN_CHECK`, `DOMAIN`, `PREFERRED_WS`, `LANG_OVERRIDE` have
  their surrounding whitespace removed
- AND `PASS_RDP` and `USER_RDP` retain their literal surrounding whitespace
  verbatim
- AND (@test `engine-security.bats::trim_allowlist_is_five_trimmed_two_excluded`: source `lib/rdp-common.bash`, call `trim_profile_fields` on the all-fields fixture, assert the 5 are trimmed AND the 2 are verbatim — both halves of the invariant in one test)
