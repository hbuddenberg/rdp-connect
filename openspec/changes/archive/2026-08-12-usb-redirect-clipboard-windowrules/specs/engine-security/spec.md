# Delta for engine-security

> Two changes: (1) MODIFIED `parse_env_safe key allowlist` extends the accepted
> key set to the five peripheral toggle keys (still parsed by `parse_env_safe`,
> never sourced/evaled); (2) a new ADDED requirement documents the drive/USB
> blast-radius posture (R1). No change to the parser's `source`/`eval`
> prohibition, the i18n loader, or the post-parse trim helper.

## MODIFIED Requirements

### Requirement: parse_env_safe key allowlist

The engine MUST only accept profile keys from this allowlist:
`HOST`, `USER_RDP`, `PASS_RDP`, `DOMAIN`, `VPN_CHECK`, `PREFERRED_WS`,
`LANG_OVERRIDE`, `USB_REDIRECT`, `USB_DEVICE_IDS`, `DRIVE_REDIRECT`, `SHARE_DIR`,
`CLIPBOARD_SYNC`.
Any key outside the allowlist MUST be rejected. On rejection the engine MUST exit
non-zero and print a message naming the offending key and file. Allowlist enforcement
MUST occur BEFORE any value is assigned into the environment (no `printf -v` on
unknown keys). The parser MUST NOT `source`, `eval`, or exec profile content;
values MUST be assigned via bash parameter expansion only. The five peripheral
keys carry NO parser privilege — they are value-only string keys whose semantic
validation happens downstream in the lib flag-build functions (see
`peripheral-redirect` spec: `USB_DEVICE_IDS` is regex-validated; `DRIVE_REDIRECT`
is treated as a boolean; `SHARE_DIR` is treated as a path string).

> **Spec-interpretation note (carried from design, resolved at archive):** no
> dynamic write-side mechanism in bash (`printf -v`, `declare -g`, nameref) is
> literally parameter expansion. `printf -v` is retained because it does NOT
> execute profile content (the security intent) and is the codebase's existing
> pattern. The format string is the literal `%s`; the value is supplied as a
> printf argument, never as a format string. The allowlist + charset check on
> the key happens BEFORE the `printf -v` call.

(Previously: allowlist was 7 keys (`HOST`, `USER_RDP`, `PASS_RDP`, `DOMAIN`,
`VPN_CHECK`, `PREFERRED_WS`, `LANG_OVERRIDE`); the five peripheral toggle keys
were not accepted. This delta adds them as value-only string keys with no
parser privilege.)

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

- GIVEN a profile populated only with the seven original allowlisted keys
- WHEN the engine parses the profile
- THEN the engine proceeds past the parser without error
- AND (manual-verify: shipped `partner.env` reaches the host-reachability log line)

#### Scenario: Peripheral keys accepted; non-peripheral key still rejected

- GIVEN a profile containing all five peripheral keys set to valid values PLUS an injected `PATH=/x`
- WHEN the engine parses the profile via `parse_env_safe`
- THEN the five peripheral keys are accepted (parsed as value-only strings)
- AND `PATH` is rejected with a non-zero exit naming `PATH` (allowlist still enforced — peripheral keys gain no privilege)
- AND (@test `engine-security.bats::peripheral_keys_accepted_path_still_rejected`)

## ADDED Requirements

### Requirement: Peripheral redirect blast-radius posture

Drive and USB redirect let the remote host touch local files on the user's
machine. Therefore the following posture MUST hold: (1) USB redirect MUST be
opt-in per profile and MUST default to OFF — the `/usb:auto` form MUST NOT be
emitted as a default or as a shipped opt-in in this change (arbitrary-device
redirect is too broad an attack surface for a default configuration). (2) Drive
redirect MUST default to ON (preserve current behavior) and MUST be togglable
OFF per profile. (3) The forms `/usb:auto` and `/drive:hotplug,*` MUST NOT
appear as defaults in any shipped profile, template, or default configuration
— `/drive:hotplug,*` auto-shares all hotplugged drives and is prohibited as a
shipped configuration. This requirement codifies R1 from the proposal. It does
NOT change the credential path (`/from-stdin:force`), the PID lockfile, or
`setsid --wait` re-exec semantics.

#### Scenario: Default profile ships no USB redirect

- GIVEN the shipped profile template and a profile with no `USB_REDIRECT` key
- WHEN the engine builds the xfreerdp3 argv
- THEN no `/usb:` token is present and no `/usb:auto` appears anywhere
- AND (@test `peripheral-flags.bats::usb_default_off_emits_no_flag`)

#### Scenario: /usb:auto and /drive:hotplug,* are not shipped defaults

- GIVEN the shipped `template/template.env` and any default profile
- WHEN the template is inspected
- THEN it does not set `USB_REDIRECT=auto` and does not reference `/drive:hotplug`
- AND (@test `engine-security.bats::no_hotplug_or_auto_defaults_in_template`)

#### Scenario: Drive default-on is preserved (not silently regressed)

- GIVEN a profile with no `DRIVE_REDIRECT` key
- WHEN the engine builds the xfreerdp3 argv
- THEN `/drive:compartido,<SHARE_DIR>` IS present (drive default-on preserved)
- AND (@test `peripheral-flags.bats::drive_default_on_preserved`)
