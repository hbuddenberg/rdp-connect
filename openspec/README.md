# OpenSpec — rdp-connect

This directory is the SDD source of truth for the `rdp-connect` project.

## Layout

```
openspec/
├── config.yaml              # Project SDD config (stack, testing, phase rules)
├── specs/                   # Main specs (source of truth, updated by sdd-archive)
└── changes/                 # Active and archived changes
    └── archive/             # Completed changes (YYYY-MM-DD-{name}/)
```

## Status

- **Initialized**: SDD init completed against baseline commit `ef04f56`.
- **Strict TDD**: `false` (no bash test runner installed; only `shellcheck`).
- **Next phase**: `/sdd-explore` or `/sdd-new` to scope baseline hardening
  (parser edge cases, missing `bc` fallback, `source` on i18n, lack of validation,
  untested `/from-stdin:force` assumption, predictable `/tmp` pid path, no `set -e`).

See `config.yaml` for the full rules each phase must follow.
