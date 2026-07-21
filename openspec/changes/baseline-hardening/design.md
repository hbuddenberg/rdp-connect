# Design: baseline-hardening

## Technical Approach

Single bundled change (Approach A per proposal): land F1–F10 together because the findings interlock — F2 needs F3; F4+F8 pair (arrays only matter under `set -u`); F5+F9 pair (EXIT trap cleans the new PID path); F10 is the verification vehicle for every engine fix. The 296-line single-file installer is split into real repo files (`engine/`, `lib/`, `i18n/`, `template/`) plus a restructured installer. The engine sources a testable pure-function library so the installer smoke test can probe `parse_env_safe` in isolation. `bc` and `python3` are removed entirely; `jq` (already a hard dep) absorbs the float math.

## Architecture Decisions

### Decision: Repo file layout (F10 + testability)

**Choice**:
```
install-rdp-framework.sh   # installer entry (restructured: detect+deps+copy+smoke+manifest)
engine/rdp-connect         # deployed to ~/.local/bin/rdp-connect
lib/rdp-common.bash        # sourced by engine + smoke test (pure functions)
i18n/{es,en}.env           # deployed to ~/.config/rdp/i18n/
template/template.env      # deployed to ~/.config/rdp/template.env
```

**Deviations from the orchestrator's proposed names (spec is the contract)**:

| Proposed | Chosen | Why |
|---|---|---|
| `bin/rdp-connect`, `config/{template,i18n}` | `engine/`, `i18n/`, `template/` | `installer-delta` scenario asserts exact paths `engine/rdp-connect`, `i18n/{es,en}.env`, `template/template.env`; verify will run `diff -q engine/rdp-connect ~/.local/bin/rdp-connect`. |
| `install.sh` (rename) | `install-rdp-framework.sh` (kept) | `config.yaml` `verify.test_command` = `shellcheck install-rdp-framework.sh`; renaming breaks the verify gate. |
| `distro/{arch,debian,fedora}.sh` | inline `case` in installer | 3 distros → 3 tiny hooks; separate files add navigation without benefit. |
| `lib/` only if needed | **Included** | installer-delta smoke test MUST feed a bad profile to `parse_env_safe` in isolation; the engine body can't be sourced cleanly (it runs `require_cmd`/from-stdin gate at top level). Extraction is mandated by the smoke-test requirement and by `config.yaml`'s testing recommendation. |

**Rejected**: keep heredoc (spec forbids runtime heredoc generation); inline all functions in engine (smoke test can't isolate `parse_env_safe`).

### Decision: Parser implementation (F3) — highest-risk area

**Allowlist representation**: associative array (Bash 5.3 confirmed in `config.yaml` context). O(1) lookup, no `eval`, no `case` ladder.

```bash
# lib/rdp-common.bash
declare -A _PROFILE_KEYS=(
  [HOST]=1 [USER_RDP]=1 [PASS_RDP]=1 [DOMAIN]=1
  [VPN_CHECK]=1 [PREFERRED_WS]=1 [LANG_OVERRIDE]=1
)
_reject() { printf 'parse_env_safe: %s:%d: %s\n' "$1" "$2" "$3" >&2; }

parse_env_safe() {                      # parse_env_safe <file> [profile|i18n]
  local file="$1" mode="${2:-profile}" line key raw value lineno=0 q
  # shellcheck disable=SC2094  # _reject writes stderr only; $file is read-only input
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    line="${line#"${line%%[![:space:]]*}"}"           # trim leading whitespace
    [[ -z "$line" || "$line" == \#* ]] && continue    # blank / full-line comment
    [[ "$line" != *=* ]] && { _reject "$file" "$lineno" "no '=' delimiter"; return 1; }
    key="${line%%=*}"; raw="${line#*=}"                # split on FIRST '=' → preserves '=' in passwords
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { _reject "$file" "$lineno" "invalid key '$key'"; return 1; }
    # allowlist BEFORE any assignment (spec: "no printf -v on unknown keys")
    # NOTE: `-v` (is-set) test, NOT `${arr[$k]}` — under `set -u` a missing assoc key
    # raises "unbound variable" before `[[ -n ]]` can return false. Verified in design.
    case "$mode" in
      profile) [[ -v _PROFILE_KEYS[$key] ]] || { _reject "$file" "$lineno" "rejected key '$key'"; return 1; } ;;
      i18n)    [[ "$key" == MSG_* ]]           || { _reject "$file" "$lineno" "rejected i18n key '$key'"; return 1; } ;;
    esac
    # value normalization by leading char
    if   [[ "$raw" == \"* ]]; then q=\"                  # double-quoted
    elif [[ "$raw" == \'* ]]; then q=\'                  # single-quoted
    else q=                                              # unquoted
    fi
    if [[ -n "$q" ]]; then
      [[ "$raw" != *"$q" ]] && { _reject "$file" "$lineno" "unterminated quote"; return 1; }
      value="${raw:1:${#raw}-2}"                         # strip outer quotes; interior '#' preserved verbatim
    else
      value="${raw%%[[:space:]]#*}"                      # strip unquoted inline comment (ws + '#')
      value="${value%"${value##*[![:space:]]}"}"         # trim trailing whitespace
    fi
    printf -v "$key" '%s' "$value"                       # key is charset+allowlist validated; format is literal %s → no execution of profile content
  done < "$file"
}
```

| Concern | Decision |
|---|---|
| Allowlist | assoc array for profile; `MSG_*` glob for i18n |
| Tokenization | `${line%%=*}` / `${line#*=}` (first `=` only — keeps `=` in passwords) |
| `KEY="v # c"` | leading `"` → strip outer quotes, interior `#` preserved |
| `KEY=v # c` | no leading quote → strip `<ws>#...` suffix, trim trailing ws |
| `KEY='v'` | leading `'` → strip outer quotes |
| No `=` line | reject, name file + line |
| Assignment | `printf -v "$key" '%s' "$value"` (existing pattern, line 102) — safe because key is validated+allowlisted and value is a printf **argument**, not a format string |
| Multiline | **REJECTED** — one `KEY=value` per line; an embedded newline parses as a new line and is rejected if it has no `=`. Matches current profile format. |
| Error UX | non-zero return + `parse_env_safe: <file>:<lineno>: <reason>` to stderr; caller logs `ERROR` + `notify-send` then `exit 1` |

> **Spec-interpretation note**: the spec says "values MUST be assigned via bash parameter expansion only." No dynamic write-side mechanism in bash (`printf -v`, `declare -g`, nameref) is literally parameter expansion; `printf -v` is retained because it does **not** execute profile content (the security intent) and is the codebase's existing pattern. Flagged for spec author review at archive.

### Decision: HiDPI math (F1)

**Choice**: **jq-native** (sanctioned by `hidpi-scaling-delta`: "via jq integer math").

```bash
# lib/rdp-common.bash
compute_dpi_flags() {                   # sets DPI_FLAGS[], IS_HIDPI, SCALE_PCT
  local raw
  read -r IS_HIDPI SCALE_PCT SCALE_VALID raw < <(hyprctl monitors -j | jq -r '
      .[0].scale as $raw
    | (try ($raw|tonumber) catch null) as $n
    | if $n == null then "0 100 invalid \($raw)"                    # null / missing / non-numeric → WARN fallback
      else (if $n > 1 then "1" else "0" end) + " " + (($n*100)|round|tostring) + " valid \($raw)" end')
  DPI_FLAGS=()
  if [[ "$SCALE_VALID" != valid ]]; then
    log_event "WARN" "unparsable monitor scale '${raw:-<missing>}'; defaulting to 100%"
  elif [[ "$IS_HIDPI" == 1 ]]; then
    DPI_FLAGS=("/scale-desktop:$SCALE_PCT" "/smart-sizing")
    log_event "INFO" "HiDPI scale ${raw} → /scale-desktop:${SCALE_PCT}."
  fi
}
```

| Option | Tradeoff | Verdict |
|---|---|---|
| `awk 'BEGIN{exit !(ARGV[1]>ARGV[2])}'` | portable but spawns another external proc | rejected — spec sanctions jq, not awk |
| bash strip-dot (`1.5`→`15`) then pad/compare | zero deps but fiddly alignment (`1` vs `1.5` vs `2.0`) | rejected — fragile |
| **jq-native** | jq already required; clean float compare + `round`; null/non-numeric → WARN + 100% | **chosen** |

Removes both `bc` (line 230) and `python3` (line 231). Satisfies the safe-fallback requirement (`null`/`"auto"` → `0 100 invalid` + WARN log, session proceeds).

### Decision: Array refactor (F8)

**Before** (strings + unquoted interpolation — breaks under `set -u`):
```bash
DPI_FLAGS="/scale-desktop:$SCALE_PCT /smart-sizing"           # line 232 — string
MON_FLAGS=$(… echo "/multimon /monitors:$MONITORS" …)         # line 239 — string
$MON_FLAGS \        # line 264 — unquoted, relies on word-splitting
$DPI_FLAGS \        # line 265 — unquoted, empty under set -u → abort
```
**After** (arrays + quoted-safe expansion):
```bash
DPI_FLAGS=()                                                  # always initialize
MON_FLAGS=()
(( IS_HIDPI )) && DPI_FLAGS=("/scale-desktop:$SCALE_PCT" "/smart-sizing")
(( MON_COUNT > 1 )) && MON_FLAGS=("/multimon" "/monitors:$MONITORS") || MON_FLAGS=("/f")
…
echo "$PASS_RDP" | xfreerdp3 \
  /v:"$HOST" ${DOMAIN:+/d:"$DOMAIN"} /u:"$USER_RDP" /from-stdin:force \
  /wm-class:"$WM_CLASS" /sec:nla /cert:tofu \
  "${MON_FLAGS[@]-}" "${DPI_FLAGS[@]-}" \                     # empty-safe under set -u
  +grab-keyboard /async-input …
```
`${arr[@]-}` supplies an empty default when the array is unset (spec-mandated; belt-and-suspenders even though we always `arr=()`-init).

### Decision: PID path + stale-lock reclamation (F5)

```bash
# lib/rdp-common.bash
compute_pid_path() { printf '%s/rdp-%s-%s.pid' "${XDG_RUNTIME_DIR:-/tmp}" "$1" "$(id -u)"; }

# engine
PID_FILE="$(compute_pid_path "$PROFILE")"          # /run/user/1000/rdp-partner-1000.pid
exec 200>"$PID_FILE"
if ! flock -n 200; then                            # a peer holds the fd → that peer is alive
  _peer=$(<"$PID_FILE" 2>/dev/null || true)
  log_event "WARN" "active instance pid=$_peer holds lock; focusing window"
  notify-send -i display "RDP $PROFILE" "$MSG_ALREADY_ACTIVE"
  hyprctl dispatch focuswindow "class:^($WM_CLASS)$" || true
  exit 0
fi
echo "$$" >&200                                    # always overwrite → reclaims stale content automatically
```

- **Path**: `${XDG_RUNTIME_DIR:-/tmp}/rdp-<profile>-$(id -u).pid` — uid-private, lives under `/run/user/<uid>/` on systemd hosts; uid suffix present even in the `/tmp` fallback.
- **Stale reclamation is automatic**: `flock` is process-bound — a crashed peer's lock is released by the kernel, so our `flock -n` succeeds and we overwrite the stale PID content with `$$`.
- **Live peer honored**: `flock -n` fails → focus + `exit 0` (spec scenario). The decision is authoritative on `flock`, not on file content.

### Decision: Installer architecture (F10)

**Distro detection** (`/etc/os-release` `ID` + `ID_LIKE`, order pacman→dnf→apt per spec):
```bash
detect_pkgr() {
  local id id_like tok
  . /etc/os-release
  for tok in $ID $ID_LIKE; do case "$tok" in arch|cachyos|garuda|endeavouros) echo pacman; return 0;; esac; done
  for tok in $ID $ID_LIKE; do case "$tok" in fedora|rhel|centos|rocky|alma)   echo dnf;    return 0;; esac; done
  for tok in $ID $ID_LIKE; do case "$tok" in debian|ubuntu|linuxmint|pop)     echo apt;    return 0;; esac; done
  return 1   # unsupported → caller fails loudly
}
```

**Dependency manifest** (spec mapping; OR-handling for launcher):

| Logical | pacman | apt | dnf | binary probe |
|---|---|---|---|---|
| FreeRDP3 (+ `/from-stdin:force`) | `freerdp3` | `freerdp3-x11` | `freerdp` | `xfreerdp3` |
| jq | `jq` | `jq` | `jq` | `jq` |
| flock | `util-linux` | `util-linux` | `util-linux` | `flock` |
| notify-send | `libnotify` | `libnotify-bin` | `libnotify` | `notify-send` |
| launcher | `wofi`\|`rofi` | `wofi`\|`rofi` | `wofi`\|`rofi` | `command -v wofi \|\| command -v rofi` |
| hyprland | `hyprland` | `hyprland`* | `hyprland` | `hyprctl` |
| linter | `shellcheck` | `shellcheck` | `shellcheck` | `shellcheck` |

\* `hyprland` is not in Debian main — see Open Questions. `bc`/`python3` deliberately absent (F1).

**Idempotency**: deploy files always (`install -D -m 700` engine, `-m 600` secrets/template/i18n, `-m 644` lib); install deps only when `command -v` fails; launcher OR satisfied if either binary present; user-edited profiles preserved (`[ -f ]` guard, existing `partner.env` pattern).

**Unsupported distro** (Alpine, NixOS): exit non-zero, list every required package, print pacman/apt/dnf install equivalents as reference, write **no** file under `~/.local/bin/` or `~/.config/rdp/`.

**Smoke test** (after deploy, fails loud on any step):
1. `bash -n ~/.local/bin/rdp-connect` + `shellcheck ~/.local/bin/rdp-connect`
2. `~/.local/bin/rdp-connect --help` → exit `0` (engine gains a `--help` no-op flag)
3. parser probe: `bash -c 'source ~/.local/lib/rdp/rdp-common.bash; parse_env_safe <(printf "PATH=/x\n") profile'` → expect non-zero

**Checksum manifest** (reproducible):
```bash
{ cd "$HOME" && sha256sum \
    .local/bin/rdp-connect .local/lib/rdp/rdp-common.bash \
    .config/rdp/i18n/es.env .config/rdp/i18n/en.env .config/rdp/template.env; } \
  | LC_ALL=C sort > "$HOME/.local/state/rdp/install-manifest.sha256"
```

## Data Flow

```
install-rdp-framework.sh
  ├─ detect_pkgr ──► {pacman|dnf|apt} | FAIL (loud: list pkgs + 3-manager reference)
  ├─ install missing deps (command -v gate; OR for wofi|rofi)
  ├─ install -D  engine/ lib/ i18n/ template/ ──► ~/.local/{bin,lib}, ~/.config/rdp/
  ├─ smoke: bash -n + shellcheck + rdp-connect --help + parser-probe(rejects PATH=/x)
  └─ sha256sum ──► ~/.local/state/rdp/install-manifest.sha256

~/.local/bin/rdp-connect (engine)
  ├─ source ~/.local/lib/rdp/rdp-common.bash
  ├─ require_cmd {xfreerdp3,hyprctl,jq,notify-send,flock,wofi|rofi}   (F6)
  ├─ /from-stdin:force gate via `xfreerdp3 /help`                      (F7)
  ├─ parse_env_safe <profile> profile                                  (F3)
  ├─ parse_env_safe <i18n>    i18n        ← NO `source`               (F2)
  ├─ compute_dpi_flags  (jq, no bc/python3)                            (F1)
  ├─ build_mon_flags    (arrays)                                       (F8)
  ├─ compute_pid_path + flock (uid-private, stale-reclaiming)          (F5)
  └─ xfreerdp3 "${MON_FLAGS[@]-}" "${DPI_FLAGS[@]-}" /from-stdin:force
```

## File Changes

| File | Action | Description |
|---|---|---|
| `engine/rdp-connect` | Create | engine extracted from heredoc; gains `--help`, `set -euo pipefail`, arrays, new PID path, `require_cmd`, from-stdin gate, `cleanup` log guard |
| `lib/rdp-common.bash` | Create | `parse_env_safe`, `require_cmd`, `compute_dpi_flags`, `build_mon_flags`, `compute_pid_path`, `_reject` |
| `i18n/es.env`, `i18n/en.env` | Create | extracted verbatim from heredoc |
| `template/template.env` | Create | extracted verbatim |
| `install-rdp-framework.sh` | Rewrite | distro detect + dep install + copy + smoke + manifest (all heredocs removed) |
| `README.md` | Modify | new layout, Hyprland hard-req note, PID path doc, accepted profile syntax |

## Interfaces / Contracts

- `parse_env_safe <file> [profile|i18n]` → `0` ok / `1` + stderr on rejection.
- `require_cmd <name> [pkg_hint]` → returns `0`; on missing, prints message + exits `127`.
- `compute_pid_path <profile>` → path string on stdout.
- `compute_dpi_flags` → sets `DPI_FLAGS[]`, `IS_HIDPI`, `SCALE_PCT`.
- `build_mon_flags <count> <ids>` → sets `MON_FLAGS[]`.
- Engine CLI: `--help` | `--log <p>` | `--new <p>` | `<p>` | (no arg → wofi/rofi selector).

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Static | all `.sh` + `engine/rdp-connect` | `shellcheck … && bash -n …` (config verify command) |
| Unit (manual) | `parse_env_safe` edge cases | `source lib/rdp-common.bash` in throwaway shell; feed fixtures: quoted-`#`, unquoted-comment, single-quote, no-`=`, `PATH=`, allowlisted set |
| Install smoke | parser probe + `--help` | installer runs both post-deploy, fails loud |
| E2E (manual) | full session + dep removal | `HOME=$(mktemp -d) ./install-rdp-framework.sh`; real RDP host; `strace -f -e execve` proves no `bc`/`python3` |

## Migration / Rollout

- **R1 migration scan**: installer runs `parse_env_safe` in `--dry-run` mode over `~/.config/rdp/profiles/*.env` **before** deploy; reports any line that would be rejected (unknown keys, inline comments on unquoted values). Warns the user with offending file:line; never auto-edits. Shipped `partner.env`/`template.env` verified clean against the allowlist.
- **Rollback**: `git checkout` prior tag, re-run installer (idempotent — overwrites all deployed non-profile files; no destructive migration).

## Risks Addressed

- **R1 (parser breaks existing profiles)** → migration scan above; shipped profiles pre-verified; accepted syntax documented in README + `template.env` comments.
- **R2 (`set -e` aborts live session)** → tactical `|| true` ONLY on:
  - `hyprctl keyword windowrulev2 …` (window-placement hint, line 244)
  - `hyprctl dispatch focuswindow …` (focus existing, line 181)
  - every `notify-send …` (cosmetic UX)
  - cleanup `grep` (no-match exits 1): wrapped as `[ -f "$LOG_FILE" ] && LAST_ERROR=$(tail -n 15 "$LOG_FILE" | grep -iE '…' | tail -n 1 || true)`
  - **NEVER** on `xfreerdp3`, `flock`, `jq`, file tests, or any security-relevant call (per `engine-robustness-delta`).
- **R5 (empty array under `set -u`)** → `"${MON_FLAGS[@]-}"` / `"${DPI_FLAGS[@]-}"` at every expansion site; every array initialized with `arr=()` at declaration (pseudocode above).

## Commit Plan (work-unit sequence for sdd-apply)

| # | Commit | Findings | Why it is one work unit |
|---|---|---|---|
| 1 | `refactor: extract engine, lib, i18n, template into real repo files` | F10 prep | no behavior change; foundation enabling shipping + smoke test; repo is fully functional after this commit alone |
| 2 | `fix(security): harden parse_env_safe with allowlist and quote/comment handling` | F3 | the security anchor; standalone-testable via `lib/`; ship probe fixtures in same commit |
| 3 | `fix(security): route i18n through hardened parser (no source)` | F2 | single call-site change in `load_language`; depends on 2; verifiable via `grep -nE 'source[[:space:]]+.*\.env'` = empty |
| 4 | `fix(hidpi): replace bc/python3 with jq-native scale math` | F1 | independent; `strace -f -e execve` proves no bc/python3 |
| 5 | `fix(lock): relocate PID to XDG_RUNTIME_DIR with uid suffix; guard cleanup` | F5+F9 | spec pairs them — EXIT trap must clean the new path; `[ -f ]` guard covers early-exit |
| 6 | `feat(robustness): strict mode, require_cmd, from-stdin gate, array flags` | F4+F6+F7+F8 | interlocked — F8 only meaningful under F4's `set -u`; F6/F7 are startup guards on the same preflight |
| 7 | `feat(installer): cross-distro deterministic installer with smoke test` | F10 | depends on 1 (real files) + 2 (parser probe); top-level verification vehicle |

**Chained-PR recommendation** (work-unit-commits skill — High risk → `delivery_strategy: ask-always`): the forecast total diff (~700–950 lines, see below) exceeds the **400-line** review budget for a single PR. Recommend **2 chained PRs**:
- **PR1 — security core**: commits 1, 2, 3, 5 (extract + parser + i18n + lock).
- **PR2 — robustness + installer**: commits 4, 6, 7 (hidpi + strict-mode preflight + installer).

Final slice decision deferred to `sdd-tasks` / user per `ask-always`.

## Open Questions

- [ ] Debian package name `freerdp3-x11` vs `freerdp3` across bookworm/trixie — confirm at apply; installer falls back to `freerdp3` if `freerdp3-x11` is unfound, then the from-stdin gate (F7) catches a wrong build.
- [ ] `hyprland` is not in Debian main archive — should the installer fail, or print a note + defer to the F6 `require_cmd hyprctl` gate? Recommend: **note + defer** (don't fail the whole install on Debian).
- [ ] Spec wording "parameter expansion only" vs `printf -v` (see parser decision note) — confirm intent with spec author at archive.
