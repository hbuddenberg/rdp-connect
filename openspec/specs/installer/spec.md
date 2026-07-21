# installer Capability Spec

> The installer (`install-rdp-framework.sh`) is the deterministic cross-distro
> deployment vehicle for the rdp-connect engine and its supporting files. It
> detects the host distro, installs missing dependencies via the detected
> package manager, deploys the engine/lib/i18n/template files via idempotent
> `install -D`, runs a post-install smoke test, and emits a SHA-256 checksum
> manifest for reproducibility. This capability exists because the original
> installer generated the engine at runtime via a `cat << 'ENGINE'` heredoc —
> making the deployed byte stream unauditable and the smoke test impossible.

## Requirements

### Requirement: Distro detection via /etc/os-release

The installer MUST detect the host distro by parsing `ID` and `ID_LIKE` from
`/etc/os-release`. It MUST support exactly three package managers: `pacman`
(Arch and derivatives), `apt` (Debian and derivatives), and `dnf` (Fedora and
derivatives). Detection order MUST prefer `pacman`, then `dnf`, then `apt` when
`ID_LIKE` is ambiguous. A host matching none of these MUST be treated as
unsupported (see separate requirement).

Detection MUST be robust under `set -euo pipefail`: the installer MUST NOT
`. /etc/os-release` (which can fail on files with unset variables); it MUST
parse via `grep`/`cut` (or equivalent) so namespace pollution and `set -u`
edge cases cannot break detection.

#### Scenario: Arch host detected as pacman

- GIVEN `/etc/os-release` with `ID=arch` (or an `ID_LIKE` containing `arch`)
- WHEN the installer runs detection
- THEN it selects `pacman` as the package manager for the rest of the run
- AND (manual-verify: `grep ^ID= /etc/os-release`; run installer with `--dry-run` if supported; observe selected manager)

#### Scenario: Debian host detected as apt

- GIVEN `/etc/os-release` with `ID=debian` or `ID_LIKE=debian`
- WHEN the installer runs detection
- THEN it selects `apt`

#### Scenario: Fedora host detected as dnf

- GIVEN `/etc/os-release` with `ID=fedora`
- WHEN the installer runs detection
- THEN it selects `dnf`

### Requirement: Declared dependency list with missing-dep install

The installer MUST declare a single dependency list mapping each package to its
name on each supported manager (e.g. `freerdp3` on Arch → `freerdp3-x11` on
Debian → `freerdp` on Fedora). Before deploying engine files, the installer MUST
check each dependency and install any missing one via the detected package
manager. The declared set is: FreeRDP3 (with `/from-stdin:force`), `jq`,
`util-linux` (provides `flock`), `libnotify` (provides `notify-send`),
`wofi` OR `rofi`, `hyprland`, `shellcheck`. `bc` and `python3` MUST NOT be in
the dependency list (the hidpi-scaling capability removed them).

On Debian-family hosts where the `hyprland` package is not in the main archive,
the installer MUST warn loudly but MUST NOT fail the install — the engine's
`require_cmd hyprctl` preflight (see engine-robustness) catches the missing
binary at startup with exit 127 and an actionable message.

#### Scenario: Missing jq is installed before engine deploy

- GIVEN a clean host where `jq` is not installed
- WHEN the installer runs
- THEN it installs `jq` via the detected package manager BEFORE writing `~/.local/bin/rdp-connect`
- AND (manual-verify: `command -v jq` succeeds after a clean run on a throwaway container)

#### Scenario: wofi or rofi satisfies the launcher dependency

- GIVEN a host with `rofi` installed but not `wofi`
- WHEN the installer runs
- THEN it does NOT attempt to install `wofi` (the OR is satisfied) and proceeds

### Requirement: Unsupported distro fails loudly

On a host whose `/etc/os-release` matches none of `pacman`/`apt`/`dnf` (e.g.
Alpine, NixOS), the installer MUST exit non-zero with a clear message that
lists every required package and prints the manual install commands for each
of the three supported managers as a reference. The installer MUST NOT silently
skip dependency installation and MUST NOT proceed to deploy engine files.

#### Scenario: Alpine host is rejected with manual install instructions

- GIVEN `/etc/os-release` with `ID=alpine`
- WHEN the installer runs
- THEN it exits non-zero with a message listing all required packages AND printing suggested `pacman`, `apt`, and `dnf` commands
- AND no file under `~/.local/bin/` or `~/.config/rdp/` is written
- AND (manual-verify: run inside an Alpine container; `ls ~/.local/bin/rdp-connect` returns no such file)

### Requirement: Idempotent deployment

Running the installer twice (N times) on the same host MUST produce byte-identical
deployed state. The installer MUST overwrite (not append) engine, i18n, template,
and profile files on each run. Profile files that the user has edited MAY be
preserved (the existing partner.env guard is allowed), but every shipped
non-profile artifact MUST be overwritten deterministically.

#### Scenario: Two consecutive runs produce identical files

- GIVEN a clean throwaway `HOME`
- WHEN the installer runs twice
- THEN `sha256sum` of `~/.local/bin/rdp-connect`, `~/.config/rdp/i18n/es.env`, `~/.config/rdp/i18n/en.env`, and `~/.config/rdp/template.env` is identical between runs
- AND (manual-verify: `sha256sum ~/.local/bin/rdp-connect` before and after second run; diff is empty)

### Requirement: Real repo files, no runtime heredoc generation

The installer MUST ship `engine/`, `i18n/`, and `template/` as real files in the
repository and copy them into place at install time (`cp` or `install`). The
installer MUST NOT generate any of those artifacts at runtime via `cat << EOF`
heredocs. The deployed `~/.local/bin/rdp-connect` MUST be byte-identical to
`engine/rdp-connect` in the repo (modulo line-ending normalization if documented).

#### Scenario: Engine is copied, not heredoc-generated

- GIVEN the repo layout `engine/rdp-connect`, `i18n/{es,en}.env`, `template/template.env`
- WHEN the installer runs
- THEN `sha256sum engine/rdp-connect` equals `sha256sum ~/.local/bin/rdp-connect`
- AND `grep -nE 'cat[[:space:]]+<<' install-rdp-framework.sh` returns no matches for engine/i18n/template deployment
- AND (manual-verify: run installer; `diff -q engine/rdp-connect ~/.local/bin/rdp-connect` is clean)

### Requirement: Post-install smoke test

After deployment, the installer MUST run a smoke test that includes ALL of:

1. `bash -n ~/.local/bin/rdp-connect` — syntax check on the deployed engine.
2. `shellcheck --severity=warning ~/.local/bin/rdp-connect` — lint check at
   warning severity (info-level findings are accepted in the engine; warning
   severity catches regressions without failing on the known info-level
   `printf`-as-format and `ls` patterns).
3. `~/.local/bin/rdp-connect --help` — the engine's no-op entrypoint MUST exit `0`.
4. A parser unit probe that feeds a known-bad profile (containing a
   non-allowlisted key, e.g. `PATH=/x`) to `parse_env_safe` and confirms it is
   rejected with non-zero exit.

If ANY check fails, the installer MUST exit non-zero with a message identifying
which smoke step failed.

#### Scenario: --help succeeds post-install

- GIVEN a freshly installed engine
- WHEN the installer's smoke test runs `rdp-connect --help`
- THEN the command exits `0` and prints usage
- AND (manual-verify: `rdp-connect --help; echo $?` shows `0` after install)

#### Scenario: Parser probe rejects a known-bad profile

- GIVEN a freshly installed engine
- WHEN the smoke test feeds `parse_env_safe` a profile containing `PATH=/x`
- THEN the parser exits non-zero and the installer reports smoke success
- AND (manual-verify: installer log contains a `smoke: parser rejected bad profile` line)

#### Scenario: Smoke test failure aborts the installer

- GIVEN a deployment where the engine was somehow truncated
- WHEN the smoke test runs `rdp-connect --help` and it exits non-zero
- THEN the installer exits non-zero with a `smoke test failed: <step>` message

### Requirement: Checksum manifest for reproducibility

The installer MUST emit a checksum manifest (`sha256sum` listing) of every
file it deployed, written to `~/.local/state/rdp/manifest.sha256`. The manifest
MUST be reproducible: running the installer twice on the same host produces
identical manifest contents (apart from any user-edited profile that the
installer preserved). The manifest MUST be sorted with `LC_ALL=C` so the
ordering is locale-independent.

> **Design reconciliation (resolved at archive):** the design pseudocode named
> this file `install-manifest.sha256`; the actual implementation (and the
> engine that reads it for diagnostic purposes) uses `manifest.sha256`. The
> canonical name is `manifest.sha256`.

#### Scenario: Manifest is generated and stable

- GIVEN a clean throwaway `HOME`
- WHEN the installer runs
- THEN a manifest file exists at `~/.local/state/rdp/manifest.sha256` listing every deployed file with its SHA-256
- AND a second installer run produces a manifest with identical content for the shipped (non-profile) files
- AND (manual-verify: `diff` the manifest across two runs; only user-edited profile lines may differ)
