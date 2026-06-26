# PR-0 — `docs/project-foundation`
# Project Foundation: Patent, Summary, Architecture, Roadmaps

**Branch:** `docs/project-foundation`  
**Base:** `main` (this is the first commit in the repo)  
**Repo:** `github.com/{org}/onboarded` — new repository, does not yet exist  
**msi-nav:** UNTOUCHED — lives in its ADO repo, zero changes there  
**Test gate:** None — this PR contains documentation only. No code, no generators, no builds.  
**Review gate:** Patent counsel confirms `docs/patent/` contents are the correct pre-filing draft before merge.

---

## What This PR Is

This is the knowledge capture commit. It creates the Onboarded GitHub repository and immediately commits every artefact produced in the June 24, 2026 design session as a versioned, citable baseline. No code is written here. The entire value is provenance: when each document existed, what it said, and what decisions it locked in before any implementation began.

After this PR merges, PRs 1–6 implement the technical system. The `docs/` tree established here does not change during those PRs — it is the stable reference point all technical PRs link back to.

---

## Why This PR Comes Before PR-1

Three reasons:

1. **Patent filing sequence.** The patent application is a pre-filing draft. Its first git commit establishes a date-stamped record of the invention's state before public disclosure. This matters for prior art and priority date arguments.

2. **Roadmap as a contract.** The 6 PR documents and the reconciliation notes are engineering commitments. Committing them before writing code means the implementation can be audited against the plan. Any deviation from a PR document is a conscious decision, not drift.

3. **R&D scope boundary.** The self-improvement roadmap defines what the tool does NOT do today (auto-write to `domain.json`, transmit tenant data). Committing it now makes that boundary explicit and versioned.

---

## Complete File Inventory

### Root files — new

| File | Content |
|---|---|
| `README.md` | Onboarded project entry point — what it is, repo structure, where to start |
| `CHANGELOG.md` | Version history starting with this foundation entry |
| `.gitignore` | Standard ignores: `node_modules/`, `dist/`, `.env`, `*.pyc`, `.nx/cache`, `packages/shared/src/lib/tenants/` |

### `docs/` — project documentation

| File | Source |
|---|---|
| `docs/Onboarded_Project_Summary.docx` | Produced this session — 4-part summary (non-technical, technical, patent, playbook) |
| `docs/Onboarded_SelfImprovement_RD_Roadmap.md` | Produced this session — 5-phase, 12-spike R&D roadmap |

### `docs/patent/` — patent artefacts

| File | Source |
|---|---|
| `docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx` | Pre-filing draft — docket OB-2026-001, applicant Lowenstein, assignee SoftwareLabs.ca |

### `docs/automation-playbook/` — companion artefact

| File | Source |
|---|---|
| `docs/automation-playbook/senior_eng_automation_playbook.html` | 10-method senior engineer automation playbook; methods 2, 8, 10 align with Onboarded features |

### `docs/figures/` — architecture diagrams

| File | Source |
|---|---|
| `docs/figures/fig1_system_architecture.svg` | FIG. 1 — domain.json → synthesis engine → 4 runtime targets |
| `docs/figures/fig2_tenant_isolation.svg` | FIG. 2 — multiple tenant specs → shared schema + engines |
| `docs/figures/fig3_adapter_synthesis_flow.svg` | FIG. 3 — domain.json → validate → b64 encode → 5 output files |
| `docs/figures/figure_4_web_portal_architecture.svg` | FIG. 4 — Angular shell → lazy routes → React islands |
| `docs/figures/figure_5_static_analysis_engine.svg` | FIG. 5 — ScanRequest → decode → compile → traverse → ScanResult |

### `docs/pr-roadmap/` — implementation roadmap

| File | Source | Notes |
|---|---|---|
| `docs/pr-roadmap/PR-1_feat-monorepo-scaffold.md` | Produced this session | Branch corrected from original: `feat/monorepo-scaffold` |
| `docs/pr-roadmap/PR-2_feat-core-data.md` | Produced this session | Branch corrected from original: `feat/core-data` |
| `docs/pr-roadmap/PR-3_feat-cli-engines.md` | Produced this session | Branch name unchanged |
| `docs/pr-roadmap/PR-4_feat-api.md` | Produced this session | All-new component, no msi-nav predecessor |
| `docs/pr-roadmap/PR-5_feat-portal-shared.md` | Produced this session | All-new component, no msi-nav predecessor |
| `docs/pr-roadmap/PR-6_feat-devops.md` | Produced this session | Includes CI pipeline, Docker, K8s, admin CLI |
| `docs/pr-roadmap/PR-1-3_Reconciliation_Notes.md` | Produced this session | Deltas from msi-nav migration context |

---

## File Contents — New Files Authored in This PR

### `README.md`

```markdown
# Onboarded

Multi-tenant platform intelligence system.

Captures institutional codebase knowledge as a schema-validated JSON domain
specification and synthesises executable adapters for multiple runtimes from
that single source of truth.

**Docket:** OB-2026-001  
**Applicant:** Michael Lowenstein  
**Assignee:** SoftwareLabs.ca  
**Status:** Pre-filing draft — not for public disclosure

---

## What It Does

One file (`domain.json`) drives everything:

```
domain.json
  → validate_domain.py          (schema gate)
  → generate_adapters.py        (one-pass synthesis)
      → nav_maps.zsh            (Zsh shell CLI)
      → scan_rules.zsh          (Zsh compliance scanner)
      → nav_maps.ps1            (PowerShell module)
      → scan_rules.ps1          (PowerShell scanner)
      → packages/shared/src/lib/tenants/{slug}.ts  (Angular portal)
```

Developers get `{tenant} where {operation}`, `{tenant} status {code}`,
`{tenant} audit`, and `{tenant} secrets` at the terminal.
The Angular portal serves the same data with no runtime HTTP fetch.
The FastAPI microservice exposes everything via REST.

---

## Repository Structure

```
docs/                          ← Project documentation (this PR)
  patent/                      ← Patent application (pre-filing draft)
  figures/                     ← Architecture diagrams (FIG. 1–5)
  pr-roadmap/                  ← Implementation PRs 1–6
  Onboarded_Project_Summary.docx
  Onboarded_SelfImprovement_RD_Roadmap.md

packages/                      ← Monorepo packages (PRs 1–6)
  core/                        ← domain.json, generator, validator (PR-2)
  shared/                      ← TypeScript interfaces + tenant snapshots (PR-5)
  cli/                         ← Zsh + PowerShell engines (PR-3)
  api/                         ← FastAPI microservice (PR-4)
  portal/                      ← Angular 19 SPA + React islands (PR-5)
  admin-cli/                   ← TypeScript + Python admin CLIs (PR-6)
```

---

## Implementation Sequence

| PR | Branch | Delivers |
|---|---|---|
| 0 | `docs/project-foundation` | This commit — all documentation |
| 1 | `feat/monorepo-scaffold` | Nx workspace, root configs, docker-compose |
| 2 | `feat/core-data` | domain.json × 2, generator, schema, validator |
| 3 | `feat/cli-engines` | Zsh engines, PowerShell module, bats + Pester tests |
| 4 | `feat/api` | FastAPI microservice, 85 pytest assertions |
| 5 | `feat/portal-shared` | Angular portal, React islands, shared TS types |
| 6 | `feat/devops` | CI pipeline, Docker, K8s, admin CLI, docs |

See `docs/pr-roadmap/` for the full specification of each PR.

---

## The Update Cycle

Every domain change follows the same four steps:

```bash
# 1. Edit
$EDITOR packages/core/tenants/msi/domain/domain.json

# 2. Validate
python3 packages/core/scripts/validate_domain.py --strict

# 3. Generate
python3 packages/core/scripts/generate_adapters.py --all

# 4. Reload
source ~/.zshrc   # or . $PROFILE on Windows
```

---

## Self-Improvement R&D

See `docs/Onboarded_SelfImprovement_RD_Roadmap.md` for the 5-phase,
12-spike research roadmap covering telemetry, gap detection, LLM-assisted
domain enrichment, and cross-tenant rule sharing — all without auto-writing
to `domain.json` or transmitting tenant data outside the local machine.

---

## Confidentiality

This repository is pre-filing. Contents are confidential to Michael Lowenstein
and SoftwareLabs.ca. Do not disclose publicly before patent filing.
```

---

### `CHANGELOG.md`

```markdown
# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.1.0-foundation] — 2026-06-24

### Added — Documentation foundation (PR-0)

This entry captures the design session of June 24, 2026. No code was written.
All entries below describe documents committed, not features shipped.

**Patent artefacts**
- `docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx`
  Pre-filing draft, docket OB-2026-001. 15 claims across 3 independent claims
  covering: multi-tenant platform knowledge management system (Claim 1),
  method for synthesising executable adapters from structured data (Claim 8),
  and system for delivering domain knowledge without runtime fetch (Claim 11).

**Project summary**
- `docs/Onboarded_Project_Summary.docx`
  4-part briefing: non-technical summary, technical system architecture
  (7-component reference, 5-figure diagram reference, data flow, Nx monorepo
  structure), patent claims overview, 10-method automation playbook.

**Architecture diagrams**
- `docs/figures/` — 5 SVG diagrams (FIG. 1–5) covering system architecture,
  tenant isolation model, adapter synthesis flow, web portal architecture,
  and static analysis engine flow.

**Self-improvement R&D roadmap**
- `docs/Onboarded_SelfImprovement_RD_Roadmap.md`
  5-phase, 12-spike R&D roadmap. Phase 0: telemetry foundation. Phase 1: gap
  detection. Phase 2: suggestion engine (ob learn, ob suggest, scan-git).
  Phase 3: LLM enrichment (local model first, cloud opt-in). Phase 4:
  cross-tenant rule sharing via anonymised pattern library. Design invariant
  throughout: the tool proposes, the engineer approves — domain.json is never
  auto-written.

**Implementation roadmap**
- `docs/pr-roadmap/PR-{1–6}_*.md` — 6 PR specifications covering the full
  msi-nav v2.0.0 → Onboarded v1.2.0 transformation.
- `docs/pr-roadmap/PR-1-3_Reconciliation_Notes.md` — branch name corrections
  and msi-nav migration context addendum for PRs 1–3.

**Companion artefact**
- `docs/automation-playbook/senior_eng_automation_playbook.html`
  10-method senior engineer automation playbook. Methods 2 (git hooks), 8
  (secrets audit), and 10 (auto-generated ADR) align directly with Onboarded
  features.

### Context — Predecessor

Onboarded is derived from msi-nav v2.0.0, a single-tenant Zsh navigation tool
maintained in a separate ADO repository. msi-nav is not modified by this
project. The transition plan (see `docs/pr-roadmap/`) migrates its domain
data and generalises its shell engines without changing the developer-facing
command interface.

---

## [msi-nav 2.0.0] — 2025-05-12

See msi-nav ADO repository for complete v2.0.0 changelog. Key changes:
JSON as single source of truth, generate_adapters.py, cross-platform
(Zsh + PowerShell), doctor and config commands, CI pipeline.

---

## [msi-nav 1.x] — Historical

See msi-nav ADO git log. Original single-platform Zsh implementation.
```

---

### `.gitignore`

```gitignore
# Node
node_modules/
dist/
.npm/

# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
.env

# Nx
.nx/cache
.nx/workspace-data

# Generated artefacts — regenerated by generate_adapters.py on every build
packages/shared/src/lib/tenants/

# Local environment
.env
.env.local
*.local

# OS
.DS_Store
Thumbs.db

# Editor
.vscode/settings.json
.idea/
*.swp
```

---

## Terminal Commands — Exact Sequence

```bash
# ── Step 1: Create the GitHub repository ──────────────────────────────────────
# On GitHub:
#   New repository → name: "onboarded" → Private → No auto-init → Create
# Copy the SSH URL.

# ── Step 2: Create local directory and initialise git ────────────────────────
mkdir onboarded
cd onboarded
git init
git remote add origin git@github.com:YOUR_ORG/onboarded.git
git branch -M main

# ── Step 3: Create directory structure ────────────────────────────────────────
mkdir -p docs/patent
mkdir -p docs/figures
mkdir -p docs/pr-roadmap
mkdir -p docs/automation-playbook

# ── Step 4: Write root files ──────────────────────────────────────────────────
# Write README.md      (content from "File Contents" above)
# Write CHANGELOG.md   (content from "File Contents" above)
# Write .gitignore     (content from "File Contents" above)

# ── Step 5: Copy patent application ──────────────────────────────────────────
cp /path/to/Onboarded_Patent_Application_v0_Lowenstein.docx \
   docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx

# ── Step 6: Copy project summary ─────────────────────────────────────────────
cp /path/to/outputs/Onboarded_Project_Summary.docx \
   docs/Onboarded_Project_Summary.docx

# ── Step 7: Copy architecture figures ────────────────────────────────────────
cp /path/to/fig1_system_architecture.svg         docs/figures/fig1_system_architecture.svg
cp /path/to/fig2_tenant_isolation.svg             docs/figures/fig2_tenant_isolation.svg
cp /path/to/fig3_adapter_synthesis_flow.svg       docs/figures/fig3_adapter_synthesis_flow.svg
cp /path/to/figure_4_web_portal_architecture.svg  docs/figures/figure_4_web_portal_architecture.svg
cp /path/to/figure_5_static_analysis_engine.svg   docs/figures/figure_5_static_analysis_engine.svg

# ── Step 8: Copy R&D roadmap ──────────────────────────────────────────────────
cp /path/to/outputs/Onboarded_SelfImprovement_RD_Roadmap.md \
   docs/Onboarded_SelfImprovement_RD_Roadmap.md

# ── Step 9: Copy automation playbook ─────────────────────────────────────────
cp /path/to/senior_eng_automation_playbook.html \
   docs/automation-playbook/senior_eng_automation_playbook.html

# ── Step 10: Copy PR roadmap documents ───────────────────────────────────────
# IMPORTANT: rename PR-1 and PR-2 to their corrected branch names per
# the reconciliation notes

cp /path/to/outputs/PR-1_feat-nx-bootstrap.md \
   docs/pr-roadmap/PR-1_feat-monorepo-scaffold.md

cp /path/to/outputs/PR-2_feat-core-domain.md \
   docs/pr-roadmap/PR-2_feat-core-data.md

cp /path/to/outputs/PR-3_feat-cli-engines.md \
   docs/pr-roadmap/PR-3_feat-cli-engines.md

cp /path/to/outputs/PR-4_feat-api.md \
   docs/pr-roadmap/PR-4_feat-api.md

cp /path/to/outputs/PR-5_feat-portal-shared.md \
   docs/pr-roadmap/PR-5_feat-portal-shared.md

cp /path/to/outputs/PR-6_feat-devops.md \
   docs/pr-roadmap/PR-6_feat-devops.md

cp /path/to/outputs/PR-1-3_Reconciliation_Notes.md \
   docs/pr-roadmap/PR-1-3_Reconciliation_Notes.md

# ── Step 11: Verify directory tree ───────────────────────────────────────────
find . -not -path './.git/*' | sort
# Expected output:
# .
# ./.gitignore
# ./CHANGELOG.md
# ./README.md
# ./docs
# ./docs/Onboarded_Project_Summary.docx
# ./docs/Onboarded_SelfImprovement_RD_Roadmap.md
# ./docs/automation-playbook
# ./docs/automation-playbook/senior_eng_automation_playbook.html
# ./docs/figures
# ./docs/figures/fig1_system_architecture.svg
# ./docs/figures/fig2_tenant_isolation.svg
# ./docs/figures/fig3_adapter_synthesis_flow.svg
# ./docs/figures/figure_4_web_portal_architecture.svg
# ./docs/figures/figure_5_static_analysis_engine.svg
# ./docs/patent
# ./docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx
# ./docs/pr-roadmap
# ./docs/pr-roadmap/PR-1-3_Reconciliation_Notes.md
# ./docs/pr-roadmap/PR-1_feat-monorepo-scaffold.md
# ./docs/pr-roadmap/PR-2_feat-core-data.md
# ./docs/pr-roadmap/PR-3_feat-cli-engines.md
# ./docs/pr-roadmap/PR-4_feat-api.md
# ./docs/pr-roadmap/PR-5_feat-portal-shared.md
# ./docs/pr-roadmap/PR-6_feat-devops.md

# ── Step 12: Stage and commit ─────────────────────────────────────────────────
git checkout -b docs/project-foundation
git add .
git status
# Verify: 19 files to be committed, nothing unexpected

git commit -m "docs: project foundation — patent, summary, figures, PR roadmap, R&D roadmap

Captures the complete design session of 2026-06-24. No application code.

Patent artefacts:
  docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx
  Pre-filing draft, docket OB-2026-001. 15 claims: multi-tenant platform
  knowledge management (Cl.1), adapter synthesis method (Cl.8), build-time
  domain delivery (Cl.11). Applicant: Lowenstein. Assignee: SoftwareLabs.ca.

Project summary:
  docs/Onboarded_Project_Summary.docx
  4-part technical + non-technical briefing. 7-component architecture table,
  5-figure reference, end-to-end data flow, Nx monorepo package map,
  patent claims summary, 10-method automation playbook.

Architecture diagrams (5 SVGs):
  docs/figures/ — FIG.1 system architecture, FIG.2 tenant isolation,
  FIG.3 adapter synthesis flow, FIG.4 web portal architecture,
  FIG.5 static analysis engine flow.

Self-improvement R&D roadmap:
  docs/Onboarded_SelfImprovement_RD_Roadmap.md
  5 phases, 12 spikes. Telemetry → gap detection → suggestion engine →
  LLM enrichment → cross-tenant rule sharing. Design invariant: tool
  proposes, engineer approves. domain.json never auto-written.

PR implementation roadmap:
  docs/pr-roadmap/PR-{1-6}_*.md — full spec for msi-nav→Onboarded transform
  docs/pr-roadmap/PR-1-3_Reconciliation_Notes.md — branch name corrections
  and msi-nav migration context (glossary format reversal risk documented)

Companion artefact:
  docs/automation-playbook/senior_eng_automation_playbook.html

msi-nav ADO repo: UNTOUCHED."

# ── Step 13: Push and open PR ─────────────────────────────────────────────────
git push -u origin docs/project-foundation
# On GitHub: Open PR → docs/project-foundation → main
# PR title: "docs: Project foundation — patent, summary, architecture, roadmaps"
# PR description: paste the "What This PR Is" section above
```

---

## PR Description (paste into GitHub)

```
## What this PR is

Knowledge capture commit for the June 24, 2026 design session.

Creates the Onboarded repository and commits every artefact produced today
as a versioned, citable baseline before any implementation begins. No code
is written here. The value is provenance: when each document existed and
what decisions it locked in.

## Contents

| Path | What it is |
|---|---|
| `docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx` | Pre-filing draft, docket OB-2026-001 |
| `docs/Onboarded_Project_Summary.docx` | 4-part technical + non-technical briefing |
| `docs/figures/` | Architecture diagrams FIG. 1–5 (SVG) |
| `docs/Onboarded_SelfImprovement_RD_Roadmap.md` | 5-phase, 12-spike R&D roadmap |
| `docs/pr-roadmap/PR-{1–6}_*.md` | Full implementation PR specifications |
| `docs/pr-roadmap/PR-1-3_Reconciliation_Notes.md` | Migration context + branch name corrections |
| `docs/automation-playbook/` | 10-method senior engineer playbook |
| `README.md` | Project entry point |
| `CHANGELOG.md` | Version history (starts here) |

## What comes next

PR-1 (`feat/monorepo-scaffold`) — Nx workspace, root configs, docker-compose.
See `docs/pr-roadmap/PR-1_feat-monorepo-scaffold.md` for the full spec.

## Review note for patent counsel

`docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx` is the
pre-review draft prepared for counsel. Please confirm this is the correct
version before this PR merges to main, as the git commit timestamp will
serve as a reference point for the filing timeline.

## msi-nav

Untouched. Lives in ADO. This repo is independent.
```

---

## Verification Checklist Before Merging

- [ ] `docs/patent/Onboarded_Patent_Application_v0_Lowenstein.docx` opens correctly in Word — correct version, correct docket, correct claims count (15)
- [ ] `docs/Onboarded_Project_Summary.docx` opens correctly — 4 parts visible, figures referenced correctly
- [ ] All 5 SVGs render in the GitHub file browser
- [ ] `docs/Onboarded_SelfImprovement_RD_Roadmap.md` renders cleanly in GitHub markdown — all 12 spike entries present
- [ ] `docs/pr-roadmap/` contains exactly 7 files (6 PR docs + 1 reconciliation note)
- [ ] PR-1 file is named `PR-1_feat-monorepo-scaffold.md` (not `nx-bootstrap`)
- [ ] PR-2 file is named `PR-2_feat-core-data.md` (not `core-domain`)
- [ ] `CHANGELOG.md` entry date reads `2026-06-24`
- [ ] `.gitignore` includes `packages/shared/src/lib/tenants/` (the gitignored TS snapshots)
- [ ] `git log --oneline` shows exactly 1 commit

---

## What This PR Does NOT Contain

These are explicitly deferred to later PRs and should not be added here:

| Not in this PR | Where it lands |
|---|---|
| `packages/` directory | PR-1 (scaffold), PR-2 (core), PR-3–6 (everything else) |
| `nx.json`, root `package.json` | PR-1 |
| Any `.zsh`, `.ps1`, `.py`, `.ts` source files | PR-2 through PR-6 |
| `domain.json` files | PR-2 |
| Docker, CI, K8s configs | PR-6 |
| The self-improvement implementation | Post-PR-6 spikes |

---

## Benchmark Recap

**What was just done:** The Onboarded GitHub repository is created and the full knowledge base from the June 24 design session is committed as a single atomic foundation PR. Everything produced today has a version-controlled home with a date stamp.

**Repository state after merge:**

```
onboarded/
├── .gitignore
├── CHANGELOG.md                                  ← v0.1.0-foundation entry
├── README.md                                     ← project entry point
└── docs/
    ├── Onboarded_Project_Summary.docx            ← 4-part briefing
    ├── Onboarded_SelfImprovement_RD_Roadmap.md   ← 5-phase, 12-spike R&D
    ├── automation-playbook/
    │   └── senior_eng_automation_playbook.html
    ├── figures/
    │   ├── fig1_system_architecture.svg
    │   ├── fig2_tenant_isolation.svg
    │   ├── fig3_adapter_synthesis_flow.svg
    │   ├── figure_4_web_portal_architecture.svg
    │   └── figure_5_static_analysis_engine.svg
    ├── patent/
    │   └── Onboarded_Patent_Application_v0_Lowenstein.docx
    └── pr-roadmap/
        ├── PR-1-3_Reconciliation_Notes.md
        ├── PR-1_feat-monorepo-scaffold.md
        ├── PR-2_feat-core-data.md
        ├── PR-3_feat-cli-engines.md
        ├── PR-4_feat-api.md
        ├── PR-5_feat-portal-shared.md
        └── PR-6_feat-devops.md
```

**Total files committed:** 19  
**Total lines of code:** 0  
**msi-nav ADO repo:** Untouched

**What changed from baseline:** The repository exists. Every decision made today is recorded and citable. The patent application has a git timestamp. The implementation sequence is locked in `docs/pr-roadmap/`. The R&D boundary (what the tool will and will not do automatically) is committed before a single line of implementation code is written.

**Key takeaways:**
1. The PR-1 and PR-2 filenames in `docs/pr-roadmap/` use the corrected branch names from the reconciliation notes (`feat/monorepo-scaffold`, `feat/core-data`). The original files produced during the session used different names. The copies made in Step 10 apply the corrections.
2. The `.gitignore` entry for `packages/shared/src/lib/tenants/` is committed here even though that directory doesn't exist yet. This prevents the generated TypeScript snapshots from ever being accidentally staged when the directory is created in PR-5.
3. Patent counsel should review before merge, not after. The commit timestamp on this PR is a potential prior art reference point.
4. The `CHANGELOG.md` `[0.1.0-foundation]` entry deliberately records document commitments, not feature deliveries. The versioning scheme will shift to `[1.0.0]`, `[1.1.0]`, `[1.2.0]` once PRs 1–6 deliver working software.
