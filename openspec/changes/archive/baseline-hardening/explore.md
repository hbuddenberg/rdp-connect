# Exploration: baseline-hardening

> Scope: track (a) — parser hardening + `bc` removal + security/robustness fixes that address live bugs.
> NOT in scope: bats-core scaffolding (track b), new features, splitting the single-file installer.

## Current State

`rdp-connect` is a Bash installer (`install-rdp-framework.sh`, 296 lines) that deploys a
~210-line engine script to `~/.local/bin/rdp-connect`. The engine reads per-profile `.env`
files under `~/.config/rdp/profiles/`, parses them through a custom `parse_env_safe`, then
launches `xfreerdp3` with the password piped via stdin (`/from-stdin:force`) so it does not
appear in `ps aux`. Single-instance enforcement uses `flock` on a PID file in `/tmp`.

The engine advertises a "safe parser" contract (no `source` on profiles), but several real
holes exist: arbitrary key injection via `printf -v "$key"`, no inline-comment handling,
`source` on i18n files (contradicts the contract), silent no-op when `bc` is missing,
predictable world-writable PID path, missing tool guards, and word-splitting on flag strings.

Environment probe on the dev box (`/home/hbuddenberg`):
- `bc` is NOT installed (confirmed: `command -v bc` → not found).
- `wofi`, `rofi` are NOT installed.
- `xfreerdp3 /from-stdin:force` IS supported by the installed build (`xfreerdp3 /help` shows
  `/from-stdin[: force]`).
- `hyprctl`, `jq`, `notify-send`, `python3`, `mktemp`, `flock` are present.
- `XDG_RUNTIME_DIR=/run/user/1000` (usable for a safer PID path).
- Reproduced: writing `PATH=/usr/bin/evil` into a profile overwrote the live `PATH` via the
  current `parse_env_safe`.
- Reproduced: `DOMAIN="MicrosoftAccount" # comment` parses to
  `MicrosoftAccount" # comment` (extra quote + comment retained).

## Affected Areas

- `install-rdp-framework.sh:74–286` — the embedded `~/.local/bin/rdp-connect` engine. All
  fixes target this region (the inner heredoc), not the outer installer logic.
- `~/.config/rdp/profiles/*.env` — consumers of `parse_env_safe`; fixes must remain
  backward-compatible with the existing template (`HOST`, `USER_RDP`, `PASS_RDP`, `DOMAIN`,
  `VPN_CHECK`, `PREFERRED_WS`, `LANG_OVERRIDE`).
- `~/.config/rdp/i18n/{es,en}.env` — touched if we route i18n through `parse_env_safe`.

---

## Findings

### F1. `bc` missing → HiDPI silently disabled (HIGH)

- **Evidence**: `install-rdp-framework.sh:230`
  ```bash
  if (( $(echo "$SCALE > 1.0" | bc -l 2>/dev/null || echo "0") )); then
  ```
- **Current behavior**: on a box without `bc` (this dev box, confirmed), the fallback
  `|| echo "0"` always wins. `(( 0 ))` is falsy, so HiDPI scaling is never applied even on a
  4K panel. `python3` is then also dragged in on line 231 just to do `int($SCALE * 100)`.
- **Severity**: HIGH — the feature is dead on minimal Arch/Omarchy installs that don't pull
  `bc`; user gets blurry RDP at 200% with no warning.

**Proposed fixes**

1. **Pure-bash integer math (RECOMMENDED)**
   - `hyprctl monitors -j` returns scale like `1.5` or `2`. Bash can't do floats, but we can
     multiply by 10 and compare as int: `SCALE_X10=$(jq -r '.[0].scale // 1.0' | tr -d .)`
     then `if (( SCALE_X10 > 10 ))` and `SCALE_PCT=$(( SCALE_X10 * 10 ))`.
   - Pros: removes BOTH `bc` AND `python3` dependencies; aligns with config.yaml rule
     "Prefer removing fragile deps (bc, python3) over adding them"; trivial diff.
   - Cons: integer-only (scales like `1.25` become `125` × 10 = `1250` → 125%, fine; `1.5`
     → `15` × 10 = 150%, fine; `2` → `20` × 10 = 200%, fine). Edge: scale `1.0` → `10` →
     not > 10, correct.
   - Effort: Low (~8 lines).
2. **`awk` one-liner**
   - `hyprctl monitors -j | jq -r '.[0].scale // 1.0' | awk '{exit !($1 > 1.0)}'`
   - Pros: handles float natively; awk is in POSIX base.
   - Cons: still spawns two subprocesses; doesn't kill the `python3` dep on line 231.
   - Effort: Low.
3. **Fail loudly if `bc` missing**
   - `command -v bc >/dev/null || { log_event "ERROR" "bc no está instalado..."; exit 1; }`
   - Pros: surfaces the gap.
   - Cons: user-hostile — refuses to connect over a cosmetic flag. Not recommended.
   - Effort: Low.

**Size estimate**: ~8–12 lines net.
**Dependencies**: none.

---

### F2. `load_language` uses `source` on i18n files (HIGH)

- **Evidence**: `install-rdp-framework.sh:88–92`
  ```bash
  load_language() {
      local target_lang="${1:-${LANG:0:2}}"
      local lang_file="$I18N_DIR/${target_lang}.env"
      [ -f "$lang_file" ] && source "$lang_file" || source "$I18N_DIR/es.env"
  }
  ```
- **Current behavior**: contradicts the "safe parser" contract documented in the README and
  `openspec/config.yaml`. Anyone who can write `~/.config/rdp/i18n/{es,en}.env` (which the
  installer creates with mode 600 — but a copy-pasted file, an editor swap, or a malicious
  theme installer could place arbitrary Bash there) gets code execution as the user every
  time `rdp-connect` starts.
- **Severity**: HIGH — code-execution vector that violates the project's stated security
  invariant.

**Proposed fixes**

1. **Route i18n through `parse_env_safe` (RECOMMENDED)**
   - Treat `MSG_*` keys the same as profile keys. Requires the key allowlist (see F3) to
     include `MSG_*` (or a `MSG_` prefix match).
   - Pros: one parser, one contract, defense in depth.
   - Cons: forces F3 to land first (or in the same change).
   - Effort: Low (~4 lines).
2. **Document why i18n is trusted and profiles aren't**
   - Add a comment + README note that i18n files ship from the installer and are 600; users
     who edit them accept the risk.
   - Pros: zero code change.
   - Cons: leaves the contradiction in the security contract; weak defense.
   - Effort: Trivial (docs only).

**Size estimate**: ~4 lines if fix #1.
**Dependencies**: F3 (allowlist must accept `MSG_*`).

---

### F3. `parse_env_safe` weaknesses (CRITICAL)

- **Evidence**: `install-rdp-framework.sh:96–104`
  ```bash
  parse_env_safe() {
      local file="$1"
      while IFS='=' read -r key value || [ -n "$key" ]; do
          [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
          value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
          printf -v "$key" "%s" "$value"
      done < "$file"
  }
  ```
- **Current behavior** (confirmed by reproduction):
  - **Arbitrary key injection**: `printf -v "$key"` accepts anything as a variable name.
    `PATH=`, `BASH_ENV=`, `HOME=`, `LD_PRELOAD=` all get overwritten from profile content.
    (Reproduced: `PATH=/usr/bin/evil` overwrote the live PATH.)
  - **No inline-comment handling**: `DOMAIN="MicrosoftAccount" # comment` parses to
    `MicrosoftAccount" # comment` (extra quote + comment retained).
  - **No multiline values** (acceptable for the current data, but undocumented).
  - **Quote stripping is naive**: only strips first/last char if it's a quote; can't handle
    `KEY="value with # inside"` correctly.
- **Severity**: CRITICAL — the parser is the stated security boundary and it is the weakest
  link. A user who copy-pastes a profile from a chat or a theme installer that drops a
  profile gets arbitrary variable clobbering.

**Proposed fixes**

1. **Allowlist + bash-native quote handling (RECOMMENDED)**
   - Define `readonly ALLOWED_KEYS=(HOST USER_RDP PASS_RDP DOMAIN VPN_CHECK PREFERRED_WS LANG_OVERRIDE)` plus a `MSG_*` glob for i18n.
   - In the loop: skip if `$key` not in allowlist (and not matching `^MSG_[A-Z_]+$`).
   - Replace the `sed` strip with a `case`-based parser that:
     1. Detects leading `"` or `'`, finds the matching closing quote, takes the substring
        between them (this naturally drops trailing `# comment`).
     2. For unquoted values, strips a trailing ` #…` comment (space + hash) but keeps `#`
        inside the value (since `HOST=#not_a_value` is almost certainly a misconfig — see
        sizing note below).
   - Reject `$key` containing anything other than `[A-Za-z_][A-Za-z0-9_]*`.
   - Pros: closes the injection hole; matches the documented contract; no `sed` subprocess.
   - Cons: bigger diff; needs careful testing of every existing template/profile combination
     to avoid breaking existing values.
   - Effort: Medium (~35–45 lines including a small helper).
2. **Allowlist only (no quote refactor)**
   - Same allowlist, keep the existing sed strip. Fixes the worst hole (arbitrary keys) but
     leaves the inline-comment bug.
   - Pros: minimal change.
   - Cons: F3 sub-bugs around comments remain; users still get a broken `DOMAIN` if they add
     an inline comment.
   - Effort: Low (~12 lines).
3. **Replace with `set -a; . "$file"; set +a` after pre-validation**
   - Use bash's own parser, but only after grep-validating that every non-comment line
     matches `^[A-Z_]+=(.*)$` and the key is in the allowlist.
   - Pros: leverages the battle-tested bash parser; supports quotes/comments/multiline
     correctly for free.
   - Cons: brings back `source`-equivalent semantics (relies on the pre-validation being
     bulletproof — circular, since the whole point was to avoid `source`). NOT recommended.
   - Effort: Low, but rejected.

**Size estimate**: ~35–45 lines for fix #1 (recommended); ~12 for fix #2.
**Dependencies**: BLOCKING for F2 (i18n routing) and recommended pairing with F4 (so the
parser is robust before `set -e` is enabled, otherwise parser edge cases abort the engine).

---

### F4. Engine missing `set -euo pipefail` (MEDIUM)

- **Evidence**: `install-rdp-framework.sh:78` — engine has only `set -o pipefail`. (Note: the
  OUTER installer on line 2 has `set -e`, but that does NOT propagate into the heredoc body
  that becomes `~/.local/bin/rdp-connect`.)
- **Current behavior**: silent failure cascade. Examples:
  - `hyprctl monitors -j | jq ...` — if `hyprctl` errors (no Hyprland session, transient IPC
    hiccup), `jq` gets empty stdin, `MONITORS=""`, `MON_COUNT=""`, and `[ "" -gt 1 ]` is a
    bash integer-parse error that gets silently swallowed.
  - Any single command failure mid-session does NOT abort; the script limps on.
- **Severity**: MEDIUM — the absence hides bugs (compounds every other finding) but adding
  it naively can break the live session.

**Blast-radius analysis for `set -e`**

Risky spots if `-e` is added naively:
- Line 181: `hyprctl dispatch focuswindow "class:^($WM_CLASS)$"` — transient IPC errors are
  common; under `-e` this aborts the "focus existing window" path.
- Line 192: `tail -n 15 "$LOG_FILE" | grep -iE ...` — `grep` returns 1 when nothing matches;
  under `-e` this kills the cleanup trap's error-branch with a misleading exit code.
- Line 210/219: `timeout 2 bash -c "</dev/tcp/..."` already has explicit `if ! ...` guards,
  so `-e` is fine there.
- Line 244: `hyprctl keyword ...` — same IPC flakiness as 181.

**Proposed fixes**

1. **Add `set -euo pipefail` + tactical `|| true` on hyprctl calls (RECOMMENDED)**
   - Enable `-euo` at the top.
   - Wrap the two `hyprctl` cosmetic calls with `|| true` (focuswindow on already-active
     session, keyword windowrulev2 application).
   - Fix the cleanup-trap grep: `LAST_ERROR=$(tail -n 15 ... | grep -iE ... | tail -n 1 || true)`.
   - Pros: catches real bugs while not aborting on cosmetic IPC noise.
   - Cons: requires careful audit of every command; needs the manual verification step from
     config.yaml (re-run installer in throwaway HOME).
   - Effort: Medium (~6 line changes + audit).
2. **Add `set -uo pipefail` only (leave `-e` off)**
   - Catches unset-variable bugs and pipeline failures without aborting on any non-zero.
   - Pros: much smaller blast radius; still surfaces real bugs (like the empty `MON_COUNT`).
   - Cons: doesn't force aborts on hard errors; less discipline.
   - Effort: Low (~1 line).
3. **Defer to a follow-up change**
   - Argue that `-e` is risky enough to ship after the parser (F3) and tool guards (F6) are
     in place.
   - Pros: smaller blast radius per change.
   - Cons: leaves the engine permissive for longer.
   - Effort: n/a.

**Size estimate**: ~6–10 lines for fix #1; ~1 line for fix #2.
**Dependencies**: SHOULD land after F3 (parser robustness) and F6 (tool guards) so the
abort-on-failure surface is well-understood.

---

### F5. Predictable PID file in world-writable `/tmp` (HIGH)

- **Evidence**: `install-rdp-framework.sh:169`
  ```bash
  PID_FILE="/tmp/rdp-${PROFILE}.pid"
  ```
- **Current behavior**: `/tmp` is `drwxrwxrwt` (sticky-bit world-writable, confirmed). Path
  is fully predictable from the profile name. An attacker who can race the user can
  pre-create `/tmp/rdp-partner.pid` as a symlink to `/home/user/.bashrc`, and the installer
  will `exec 200>"$PID_FILE"` (truncate it). Even without a race, a non-privileged user on
  the box can pre-create the file and lock out the profile (DoS).
- **Severity**: HIGH — symlink attack + DoS. The script handles real credentials.

**Proposed fixes**

1. **`${XDG_RUNTIME_DIR}/rdp-<profile>-<uid>.pid` (RECOMMENDED)**
   - `XDG_RUNTIME_DIR` is `700` and per-user (systemd sets it to `/run/user/<uid>`). Fall
     back to `mktemp -d` if unset.
   - Code:
     ```bash
     RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(mktemp -d)}"
     PID_FILE="$RUNTIME_DIR/rdp-${PROFILE}-$(id -u).pid"
     ```
   - Pros: closes symlink attack; per-user; honors XDG; aligns with config.yaml's XDG style.
   - Cons: needs a fallback path for non-systemd boxes (handled by `mktemp -d`).
   - Effort: Low (~3 lines).
2. **`mktemp -d` per invocation**
   - `PID_DIR=$(mktemp -d); PID_FILE="$PID_DIR/${PROFILE}.pid"`; `rmdir` in cleanup.
   - Pros: no predictability at all.
   - Cons: breaks the "is another instance already running?" check (each invocation makes a
     fresh dir, so flock on a different file every time). Reject.
   - Effort: Low but broken.
3. **`~/.local/state/rdp/<profile>.pid` (alongside logs)**
   - Co-locate with `LOG_DIR`.
   - Pros: simple; mode 700 by existing mkdir.
   - Cons: PID files are runtime state, not application state — semantics mismatch; some
     users symlink `~/.local/state` to network storage.
   - Effort: Low.

**Size estimate**: ~3–5 lines.
**Dependencies**: none, but update cleanup (F9) in the same change so the new PID path is
cleaned.

---

### F6. No `command -v` guards on required tools (MEDIUM)

- **Evidence**: missing across the engine. Concretely:
  - `notify-send` is used at lines 161, 180, 195, 198, 213, 222, 251 — failure mode is
    silent (the script continues, user gets no notification).
  - `xfreerdp3` is invoked at line 256 with no check; if missing, the user sees a generic
    "command not found" mid-flow.
  - `hyprctl` at lines 181, 228, 237, 238, 244 — if Hyprland isn't running, every call
    errors silently and `MON_COUNT` ends up empty.
  - `jq` at 228, 237, 238 — if missing, all `jq` filters fail.
  - `wofi`/`rofi` are guarded with `command -v` at 152/154, but only for the selector path.
- **Severity**: MEDIUM — degrades the failure UX; user gets confusing errors mid-session
  instead of a clear "install these packages first" message at startup.

**Proposed fixes**

1. **`require_cmd` helper with clear error UX (RECOMMENDED)**
   ```bash
   require_cmd() {
       local cmd="$1" why="$2"
       command -v "$cmd" >/dev/null 2>&1 || {
           printf 'rdp-connect: falta dependencia "%s". %s\n' "$cmd" "$why" >&2
           notify-send -u critical "RDP Error" "Falta: $cmd ($why)" 2>/dev/null || true
           exit 127
       }
   }
   require_cmd xfreerdp3 "Instala freerdp3 (pacman -S freerdp3)"
   require_cmd hyprctl  "Requiere Hyprland en ejecución"
   require_cmd jq       "Instala jq"
   require_cmd notify-send "Instala libnotify"
   ```
   - Pros: one pattern, consistent UX, translatable.
   - Cons: more lines; need to decide `hyprctl` is hard-required (it is, for HiDPI + monitor
     detection + workspace routing).
   - Effort: Low (~15 lines).
2. **Per-call inline guards**
   - Add `command -v X || { echo "..."; exit 1; }` before each first use.
   - Pros: local context.
   - Cons: duplicated messages, drift between calls.
   - Effort: Low but messy.

**Size estimate**: ~15 lines.
**Dependencies**: pairs naturally with F4 (once guards exist, `-e` is safer to enable).

---

### F7. `/from-stdin:force` runtime support — VERIFIED OK (LOW / informational)

- **Evidence**: `install-rdp-framework.sh:260` uses `/from-stdin:force`.
- **Verification**: `xfreerdp3 /help 2>&1 | grep -i from-stdin` on the dev box returns:
  ```
      /from-stdin[: force]              Read credentials from stdin. With <force>
  ```
- **Conclusion**: the installed build supports the flag. No code change needed.
- **Recommendation**: add a one-line runtime feature-gate so a build without the flag fails
  loudly instead of silently connecting with a blank password:
  ```bash
  xfreerdp3 /help 2>&1 | grep -q from-stdin || {
      echo "rdp-connect: este build de xfreerdp3 no soporta /from-stdin:force" >&2
      exit 1
  }
  ```
- **Severity**: LOW (gating only; the flag already works today).
- **Size estimate**: ~4 lines.

---

### F8. Unquoted `$MON_FLAGS` / `$DPI_FLAGS` word-split (MEDIUM)

- **Evidence**: `install-rdp-framework.sh:239, 256–285`
  ```bash
  MON_FLAGS=$([ "$MON_COUNT" -gt 1 ] && echo "/multimon /monitors:$MONITORS" || echo "/f")
  ...
  $MON_FLAGS \
  $DPI_FLAGS \
  ```
- **Current behavior**: relies on shell word-splitting to turn the string into multiple
  args. This is intentional but fragile:
  - `set -u` (recommended in F4) will not affect this, but `set -o pipefail` already in
    effect means a future `IFS` change elsewhere silently breaks the call.
  - If `MONITORS` ever contains a space (it won't, but defensive), splitting breaks.
  - `shellcheck` flags SC2086 on both lines.
- **Severity**: MEDIUM — fragile, but currently works because the values are well-formed.

**Proposed fixes**

1. **Arrays (RECOMMENDED)**
   ```bash
   MON_FLAGS=()
   if (( MON_COUNT > 1 )); then
       MON_FLAGS=(/multimon "/monitors:$MONITORS")
   else
       MON_FLAGS=(/f)
   fi
   ...
   xfreerdp3 ... "${MON_FLAGS[@]}" "${DPI_FLAGS[@]}" ...
   ```
   - Pros: SC2086-clean; survives `IFS` changes; idiomatic bash.
   - Cons: minor refactor across the `xfreerdp3` invocation; need empty-array guards for
     `set -u` ("${DPI_FLAGS[@]-}" or initialize `DPI_FLAGS=()` always).
   - Effort: Low–Medium (~15 lines, but touches the big invocation).
2. **Keep strings, document the choice**
   - Add `# shellcheck disable=SC2086` with a comment explaining intentional splitting.
   - Pros: zero behavior change.
   - Cons: leaves the fragility; doesn't fix the underlying issue.
   - Effort: Trivial.

**Size estimate**: ~15 lines.
**Dependencies**: should land together with F4 if `-u` is enabled (else empty-array expansion
errors).

---

### F9. `cleanup()` reads `$LOG_FILE` before first `log_event` (LOW)

- **Evidence**: `install-rdp-framework.sh:185–202`
  ```bash
  cleanup() {
      ...
      if [ $EXIT_CODE -ne 0 ]; then
          LAST_ERROR=$(tail -n 15 "$LOG_FILE" | grep -iE ... | tail -n 1)
  ```
  `LOG_FILE` is defined at line 168 (always before the trap is registered at 202), but the
  file itself is only created by the first `log_event` at line 204. If the engine exits
  between lines 168 and 204 (e.g., `set -e` triggers an early abort, or `flock` fails), the
  `tail` call errors and `LAST_ERROR` gets a noisy stderr message instead of an empty
  string.
- **Severity**: LOW — cosmetic, but confusing in logs.

**Proposed fixes**

1. **Guard with `[ -f "$LOG_FILE" ]` (RECOMMENDED)**
   ```bash
   if [ $EXIT_CODE -ne 0 ] && [ -f "$LOG_FILE" ]; then
       LAST_ERROR=$(tail -n 15 "$LOG_FILE" | grep -iE ... | tail -n 1 || true)
   ```
   - Pros: clean; no stderr noise on early-exit.
   - Cons: none.
   - Effort: Low (~2 lines).
2. **Touch the log file at startup**
   - `: > "$LOG_FILE"` after defining it.
   - Pros: guarantees the file exists.
   - Cons: truncates an existing log from a prior session (data loss); reject.
   - Effort: Low but wrong.

**Size estimate**: ~2 lines.
**Dependencies**: none; trivially pairable with F4 and F5.

---

## Cross-cutting Dependencies

```
F3 (parser allowlist)  ──blocks──▶  F2 (route i18n through parser)
F3 + F6 (tool guards)  ──should-precede──▶  F4 (enable -e)
F4 (-u)                ──requires──▶  F8 (arrays, to avoid empty-var errors)
F5 (PID path change)   ──pair-with──▶  F9 (cleanup uses new PID path)
F1, F7                 ──independent
```

## Size Triage

| Finding | Recommended fix | Net lines | Class |
|---|---|---|---|
| F1 | Pure-bash int math | ~10 | Small |
| F2 | Route i18n via parser | ~4 | Small |
| F3 | Allowlist + bash-native quotes | ~40 | **Medium** |
| F4 | `set -euo` + tactical `\|\| true` | ~8 | Small |
| F5 | XDG_RUNTIME_DIR PID | ~4 | Small |
| F6 | `require_cmd` helper | ~15 | Small |
| F7 | Runtime feature-gate | ~4 | Small |
| F8 | Arrays for flag strings | ~15 | Small-Med |
| F9 | `[ -f ]` guard in cleanup | ~2 | Tiny |
| **Total** | | **~100** | Fits the **400-line** review budget with headroom for tests + comments |

Everything fits in one PR under the 400-line review budget. No chained-PR split needed for
review-load reasons alone — but see splitting note below for risk isolation.

## Approaches

### Approach A — Single bundled "baseline-hardening" change (RECOMMENDED)

Bundle F1, F2, F3, F4, F5, F6, F7, F8, F9 in one proposal.

- Pros:
  - One verification pass, one rollback (re-run installer).
  - Parser (F3), i18n routing (F2), `-e` (F4), and tool guards (F6) all interlock — landing
    them piecemeal leaves half-hardened intermediate states that are harder to reason about.
  - Total ~100 LOC net is well inside the 400-line review budget.
- Cons:
  - Single PR mixes a CRITICAL security fix (F3) with cosmetic fixes (F9). A reviewer who
    skims the diff could miss the parser change inside a wall of refactors.
  - Mitigation: tasks.md groups the change into phases so reviewers can read by phase.
- Effort: Medium overall.

### Approach B — Split: "security-critical" vs "robustness"

- Change 1 (`hardening-security`): F2, F3, F5, F6, F7. The contract-violating + credential-
  touching fixes. ~65 lines.
- Change 2 (`hardening-robustness`): F1, F4, F8, F9. The "make it work on minimal installs"
  fixes. ~35 lines.
- Pros:
  - Security reviewers can focus on Change 1; robustness reviewers on Change 2.
  - Each change is well under the 400-line budget with comfortable headroom.
- Cons:
  - F4 depends on F3 + F6 landing first to be safe — strictly enforces ordering.
  - Two verification passes, two archives.
- Effort: Medium overall, but split.

### Approach C — Minimal: F3 alone

- Ship only the parser allowlist. Defer everything else.
- Pros: smallest possible blast radius; closes the worst hole fast.
- Cons: leaves F2 (source-on-i18n) as a live contradiction of the security contract; leaves
  F1 (HiDPI) dead on this dev box.
- Effort: Low.

## Recommendation

**Approach A** (single bundled change), because:

1. The findings are tightly coupled — F2 requires F3, F4 is safe only with F3+F6, F8 needs
   F4 — and shipping them together avoids three rounds of "depends-on" PRs.
2. Total size (~100 LOC net + comments + manual verification checklist) stays inside the
   400-line budget with headroom for the test/verification doc.
3. The installer is idempotent (per `openspec/config.yaml`), so rollback is trivial.
4. Reviewers get one coherent "baseline hardening" story instead of three partial ones.

If the proposal-phase forecast reveals the change ballooning past 400 lines, **fall back to
Approach B** with the security change first.

## Risks

- **Behavior change in `parse_env_safe`** may break existing user profiles that relied on
  permissive parsing (e.g., someone using inline comments today). Mitigation: scan
  `~/.config/rdp/profiles/*.env` on the dev box before applying; document the accepted
  syntax in the proposal.
- **Adding `set -e`** may abort a live RDP session on a transient `hyprctl` error.
  Mitigation: tactical `|| true` on cosmetic IPC calls; manual verification per config.yaml.
- **PID file relocation** changes where users look for stale locks. Mitigation: cleanup runs
  on EXIT trap; document the new path in the README.
- **Array refactor (F8)** requires care for `set -u` empty-array expansion
  (`"${arr[@]}"` errors on unset under `-u`; must initialize or use `"${arr[@]-}"`).
- **`require_cmd hyprctl`** makes Hyprland a hard requirement — correct for this project's
  scope, but worth noting for anyone trying to run under Sway.

## Ready for Proposal

**Yes.** Scope is well-bounded, evidence is reproducible, dependencies are mapped, and the
total size fits the budget. The next phase (`/sdd-propose`) should:

1. Confirm Approach A vs B with the user (delivery strategy is `ask-always`).
2. Draft a proposal with explicit rollback plan (re-run installer).
3. Flag F3 and F5 as the high-risk/high-impact items per `openspec/config.yaml` rule
   "Flag ANY change to the password path, stdin handling, or parse_env_safe as high-risk".
