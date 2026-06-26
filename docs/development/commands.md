# MSI Nav — Command Reference

All commands are dispatched through the `msi` function. Aliases (single-letter and standalone) are noted.

---

## Bug Triage

### `msi bug` / `msi b`

Guided 7-step triage wizard. Walks through operation → product → status → queue → grep → open → QE. Start here when you don't know where a bug lives.

### `msi where <key>` / `msi w <key>`

Look up the full implementation stack for a given operation or product:

- Controllers (entry points)
- Services / Business Logic
- Azure Storage Queues (async)
- Client-side JS files

```
msi where bind        # bind flow
msi where payment     # payment flow
msi where fnol        # claims / FNOL
msi where renters     # renters product
msi where pay         # fuzzy: returns payment, paynow matches
```

### `msi product <key>` / `msi p <key>`

Full product profile: product type code, controllers, Gen3 API path, JS files, WebJobs.

```shell
msi product renters
msi product flood
msi product ho_admitted_h03
msi product           # list all products
```

### `msi status <code>` / `msi s <code>`

Explain a PolicyStatusCode integer. Includes trigger description for key codes.

```
msi status 13    # EndorsementScenario
msi status 36    # Suspense
msi status 30    # RenewalOffer
msi status       # list all codes
```

### `msi explain <term>` / `msi e <term>`

Insurance domain glossary. Plain-English definitions plus code-path cross-references for key flows.

```shell
msi explain bind
msi explain fnol
msi explain master_policy
msi explain          # full glossary list
```

---

## Navigation

### `msi cd <target>` / `mcd <target>`

Change directory into a well-known repo or subdirectory.

| Target | Destination |
|---|---|
| `pas` / `gen1` | MSI-PAS root |
| `core` / `gen2` / `gen3` | MSI-PAS-CORE root |
| `widget` | MSI-Widget root |
| `qe` | MSI-QE root |
| `config` | PAS-APP-CONFIG root |
| `root` | `$MSI_ROOT` |
| `admin` | Portal.Admin |
| `customer` | Portal.Customer |
| `apis` / `api` | MSI.Core.Apis |
| `flood_api` | Integration/Flood |
| `renters_api` | Integration/GroupRenters |
| `ho_api` | Integration/Homeowners |
| `webjobs` | MSI.Core.WebJobs |
| `services` | MSI.Core.BusinessService |
| `framework` | MSI.Core.Framework |
| `tests` | MSI.Core.Tests |

### `msi open <key>` / `msi o <key>`

Open all relevant files for an operation or product in `$MSI_EDITOR` (async).

```shell
msi open bind
msi open renters
```

### `msi grep <pattern> [repos]` / `msi g <pattern> [repos]`

Search the codebase for a pattern. Uses `rg` if installed, falls back to `grep -r`.

```shell
msi grep 'PolicyService.Bind'          # searches all repos
msi grep 'BindPolicy' CORE             # search only MSI-PAS-CORE
msi grep 'RenewalOffer' CORE PAS       # search two repos
```

Repos: `PAS` `CORE` `WIDGET` `QE` (default: all four)

### Quick repo-jump aliases

```shell
cdpas cdcore cdwidget cdqe cdconfig
cdadmin cdapis cdservices cdwebjobs cdtests
cdfloodapi cdrentersapi cdhoapi cdmrf
```

---

## Discovery

### `msi list [filter]` / `msi l [filter]`

List all operations, products, and portals in the domain map. Optional filter keyword.

```shell
msi list
msi list flood
msi list payment
```

### `msi queue [partial]` / `msi qu [partial]`

Describe Azure Storage Queues — consumer WebJob, trigger context.

```shell
msi queue bind        # all queues matching 'bind'
msi queue renewal     # renewal queues
msi queue            # all queues
```

### `msi portal [key]`

White-label customer portal directory.

```shell
msi portal avalon
msi portal msi
msi portal           # all portals
```

### `msi qe [filter]` / `msi q [filter]`

Find QE (end-to-end) test class paths by domain keyword.

```shell
msi qe renters
msi qe flood
msi qe claims
msi qe              # all test suites
```

---

## Tooling

### `msi doctor` / `mdoctor`

Checks: `MSI_ROOT`, editor, `MSI_NAV_HOME`, `msi_domain.json`, `rg`, `python3`, `jq`. Also verifies all repos are cloned.

### `msi config` / `mconfig`

Prints all resolved environment variables.

---

## Command Aliases Reference

| Full command | Short alias | Standalone alias |
|---|---|---|
| `msi where` | `msi w` | `mwhere` |
| `msi product` | `msi p` | `mprod` |
| `msi status` | `msi s` | `mstatus` |
| `msi grep` | `msi g` | `mgrep` |
| `msi open` | `msi o` | `mopen` |
| `msi qe` | `msi q` | `mqe` |
| `msi queue` | `msi qu` | `mqueue` |
| `msi list` | `msi l` | `mlist` |
| `msi explain` | `msi e` | `mexplain` |
| `msi bug` | `msi b` | `mbug` |
| `msi cd` | — | `mcd` |
| `msi doctor` | — | `mdoctor` |
| `msi config` | — | `mconfig` |
