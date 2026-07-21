# Delta for engine-security

> **HIGH-RISK (F3 — `parse_env_safe` security boundary):** the deployed engine runs
> as the user and gates the RDP credential session. Arbitrary-key injection is live
> today (`PATH=`, `BASH_ENV=`, `LD_PRELOAD=` are all clobber-able). Every requirement
> in this delta MUST be manually verified in a throwaway `HOME` before archive.

## ADDED Requirements

### Requirement: parse_env_safe key allowlist

The engine MUST only accept profile keys from this allowlist:
`HOST`, `USER_RDP`, `PASS_RDP`, `DOMAIN`, `VPN_CHECK`, `PREFERRED_WS`, `LANG_OVERRIDE`.
Any key outside the allowlist MUST be rejected. On rejection the engine MUST exit
non-zero and print a message naming the offending key and file. Allowlist enforcement
MUST occur BEFORE any value is assigned into the environment (no `printf -v` on
unknown keys). The parser MUST NOT `source`, `eval`, or exec profile content;
values MUST be assigned via bash parameter expansion only.

#### Scenario: Dangerous key in profile is rejected

- GIVEN a profile containing `PATH=/usr/bin/attacker`
- WHEN the engine parses the profile via `parse_env_safe`
- THEN the engine exits non-zero and prints a message naming `PATH` as rejected
- AND the ambient `$PATH` is unchanged from the parent shell
- AND (manual-verify: `HOME=$(mktemp -d) ./install-rdp-framework.sh`; write `PATH=/x` into a profile; run `rdp-connect <profile>`; confirm rejection and `echo $PATH`)

#### Scenario: Unknown non-allowlisted key is rejected

- GIVEN a profile containing `KEY=unknown`
- WHEN the engine parses the profile
- THEN the engine exits non-zero naming `KEY` and the source file
- AND (manual-verify: same harness with `KEY=foo`)

#### Scenario: All allowlisted keys accepted

- GIVEN a profile populated only with the seven allowlisted keys
- WHEN the engine parses the profile
- THEN the engine proceeds past the parser without error
- AND (manual-verify: shipped `partner.env` reaches the host-reachability log line)

### Requirement: Quote and comment handling

The parser MUST support three value forms: double-quoted, single-quoted, and
unquoted. Inline `#` characters inside a quoted value MUST be preserved verbatim.
An unquoted value followed by whitespace and `#` MUST have the comment and
everything after it stripped. Surrounding quote characters MUST be removed before
assignment. A line with no `=` delimiter MUST be rejected with a non-zero exit
and a message naming the file and line.

#### Scenario: Inline comment inside double-quoted value is preserved

- GIVEN a profile line `HOST="server # production"`
- WHEN the engine parses the profile
- THEN `$HOST` equals the literal string `server # production` (comment preserved)
- AND (manual-verify: `bash -x` on `parse_env_safe` shows `$HOST` literal)

#### Scenario: Trailing comment after unquoted value is stripped

- GIVEN a profile line `PREFERRED_WS=3  # target workspace`
- WHEN the engine parses the profile
- THEN `$PREFERRED_WS` equals `3` (no trailing whitespace or comment)
- AND (manual-verify: same `bash -x` harness)

#### Scenario: Single-quoted value is unquoted

- GIVEN a profile line `DOMAIN='MicrosoftAccount'`
- WHEN the engine parses the profile
- THEN `$DOMAIN` equals `MicrosoftAccount`

#### Scenario: Malformed line aborts parsing

- GIVEN a profile containing a line with no `=` delimiter (other than blank/comment)
- WHEN the engine parses the profile
- THEN the engine exits non-zero with a message naming the file and line number

### Requirement: i18n loaded through the hardened parser (no `source`)

The engine MUST load `~/.config/rdp/i18n/*.env` through `parse_env_safe`, not via
`source`. The literal token `source` MUST NOT appear on any path matching
`~/.config/rdp/**` inside the deployed engine. The i18n parser MUST restrict
accepted keys to the `MSG_*` prefix; any non-`MSG_*` key in an i18n file MUST be
rejected with the same error semantics as profile allowlist violations.

#### Scenario: i18n file with injected key is rejected

- GIVEN `~/.config/rdp/i18n/es.env` containing `PATH=/x`
- WHEN the engine starts and loads the i18n dictionary
- THEN the engine exits non-zero naming `PATH` as rejected
- AND (manual-verify: `grep -nE 'source[[:space:]]+.*\.env' ~/.local/bin/rdp-connect` returns no matches after install)

#### Scenario: Legitimate MSG_* keys load

- GIVEN the shipped `es.env` and `en.env` files
- WHEN the engine starts under either locale
- THEN every shipped `MSG_*` key is populated and `$MSG_CONNECTING` renders with the profile name substituted
- AND (manual-verify: run `rdp-connect <profile>` and read the connecting notification + log line)
