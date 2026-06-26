# MSI Nav — Architecture

## Core Principle

One domain, two platform frontends.

```text
data/msi_domain.json          ← Single source of truth (human edits here)
        │
        ├── src/python/generate_adapters.py
        │        │
        │        ├─→  src/zsh/msi_domain.zsh        (generated — do not edit)
        │        └─→  src/powershell/msi_domain.ps1  (generated — do not edit)
        │
        ├── src/zsh/msi_nav.zsh        ← Linux/macOS adapter (query logic)
        ├── src/powershell/msi_nav.ps1 ← Windows adapter (query logic)
        └── src/sh/msi_nav.sh          ← POSIX sh adapter (fallback, subset)
```

---

## Why JSON as source of truth?

The original tool stored all domain knowledge in two parallel places:

- `MSI_OPS[bind]="..."` in `msi_domain.zsh`
- `$global:MSI_OPS['bind'] = "..."` in `msi_domain.ps1`

These drift. Every time a new operation, product, or portal is added, it must be added in both files. JSON eliminates that by being platform-neutral. The adapter files are **outputs**, not inputs.

---

## Domain Loading Priority

Both adapters use the same fallback order at source time:

```text
1. data/msi_domain.json (ConvertFrom-Json / python3)  ← preferred
        ↓ fails (JSON absent or parse error)
2. src/{platform}/msi_domain.{ext} (native fast load)  ← fallback
        ↓ fails (not generated yet)
3. Error — run install script or generate_adapters.py
```

This means on a fresh clone, the first `source msi_nav.zsh` triggers an automatic one-time `generate_adapters.py --zsh` call (~1s), which writes the generated file and caches it. Subsequent shell startups are fast (native array assignment, no subprocess).

---

## Pipe-Delimited Value Format

Domain values use a shared DSL across both adapters:

```text
operations: "label|ctrl1,ctrl2|svc1,svc2|queue1,queue2|js1,js2"
products:   "code|label|ctrl1,ctrl2|js1,js2|gen3path|webjob1,webjob2"
portals:    "name|REPO:path|product1,product2"
queues:     "consumer description|WebJob1,WebJob2"
```

This is intentional. It keeps the generated files human-readable and directly comparable across platforms. Both `msi_domain.zsh` and `msi_domain.ps1` use the same field order, so parity fixtures can test both adapters against the same expected strings.

---

## PowerShell Lib Decomposition

`msi_nav.ps1` dot-sources three lib files rather than being a monolith:

| File | Responsibility |
|---|---|
| `lib/Output.ps1` | `Write-Cyan`, `Write-MsiGreen`, `Write-PathList`, `Write-BulletList` — all colour + formatting |
| `lib/Paths.ps1` | `Resolve-MsiPath`, `Get-MsiRepoDir`, `$script:MSI_CD_TARGETS` ordered hashtable |
| `lib/Search.ps1` | `Invoke-MsiSearch` — rg with `Select-String` fallback, cached `$script:MSI_SEARCH_HAS_RG` |

This decomposition:

- makes each concern independently testable via Pester
- keeps `msi_nav.ps1` focused on command logic, not I/O plumbing
- mirrors how Angular services separate concerns (each lib = a focused `@Injectable`)

The `script:` scope (not `global:`) means lib symbols stay private to the loaded module. Only `$global:MSI_OPS` etc. are intentionally global (loaded domain data is shared state by design).

---

## POSIX sh Adapter (`src/sh/`)

The sh adapter is a **structural subset** of the zsh adapter. It covers the commands most useful without a full interactive shell: `where`, `product`, `status`, `grep`, `list`, `doctor`, `config`.

It intentionally omits:

- `msi explain` (glossary needs associative arrays or python3 — falls to zsh or ps1)
- `msi cd` (shell-builtins interact poorly with exec'd scripts)
- `msi open` (editor launch is environment-dependent)
- Tab completions (shell-specific)

The sh adapter uses POSIX-compatible case statements instead of associative arrays. `msi_domain.sh` exports `_msi_op_lookup()`, `_msi_product_lookup()`, etc. as functions — the equivalent of hash lookups, but compatible with any POSIX shell.

---

## Parity Testing

Cross-platform parity is enforced by fixture files in `tests/parity/`. Both the Zsh bats suite and the Pester suite read from the same fixture file and assert identical strings appear in the output of `msi where bind`, `msi status 13`, etc.

Formatting differences (ANSI escape codes, checkmark glyphs vs `[+]` prefixes, Windows path separators) are acceptable and expected. Semantic content — operation name, controller paths, queue names, product codes — must match.

---

## Extension Pattern

To add a new operation, product, status, or portal:

1. Edit `data/msi_domain.json`
2. Run `python3 src/python/validate_domain.py --strict`
3. Run `python3 src/python/generate_adapters.py`
4. The zsh, ps1, and sh adapters all pick up the change automatically on next shell load

No other files need to change. The nav logic in `msi_nav.zsh` and `msi_nav.ps1` is data-driven — it reads from the domain maps at runtime.