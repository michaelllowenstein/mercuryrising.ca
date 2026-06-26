# MSI Nav — Windows / PowerShell Setup

## Requirements

| Dependency | Required | Notes |
|---|---|---|
| PowerShell 5.1+ | Yes | Pre-installed on Windows 10/11; PowerShell 7 recommended |
| python3 | Recommended | For `generate_adapters.py`, `validate_domain.py`; `winget install Python.Python.3` |
| ripgrep (`rg`) | Optional | `winget install BurntSushi.ripgrep.MSVC`; `Select-String` fallback used if absent |
| Pester v5 | Dev only | `Install-Module Pester -Force` |

---

## Quick Install

```powershell
git clone <repo-url> "$HOME\msi-nav"
cd "$HOME\msi-nav"
.\install\install-windows.ps1 -MSIRoot "C:\msi\MSIMGA"
. $PROFILE
msi doctor
```

The installer:
1. Creates `$HOME\bin\msi-nav.ps1` launcher
2. Adds `$HOME\bin` to user `PATH`
3. Runs `generate_adapters.py --ps1` to build `msi_domain.ps1` from JSON
4. Appends a dot-source line to `$PROFILE`

---

## Manual Setup

Add this block to your `$PROFILE` (`notepad $PROFILE`):

```powershell
$env:MSI_ROOT       = "C:\msi\MSIMGA"      # ← your checkout location
$env:MSI_EDITOR     = "code"                # ← or "rider", "notepad"
$env:MSI_NAV_HOME   = "$HOME\msi-nav"

# Optional overrides
# $env:MSI_REPO_PAS    = "MSI-PAS"
# $env:MSI_REPO_CORE   = "MSI-PAS-CORE"
# $env:MSI_REPO_WIDGET = "MSI-Widget"
# $env:MSI_REPO_QE     = "MSI-QE"

. "$env:MSI_NAV_HOME\src\powershell\msi_nav.ps1"
```

Then generate the domain adapters once:
```powershell
python3 "$HOME\msi-nav\src\python\generate_adapters.py" --ps1
. $PROFILE
```

---

## Execution Policy

If you see an execution policy error:

```powershell
# User-scoped — does not require admin
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Tab Completion

Tab completion is registered automatically when `msi_nav.ps1` is dot-sourced. It completes the first argument to `msi`:

```powershell
msi w<Tab>   # completes to: where
msi p<Tab>   # completes to: product, portal, prod
```

---

## Uninstall

```powershell
cd "$HOME\msi-nav"
.\install\uninstall-windows.ps1
. $PROFILE
# Optional: remove the repo
Remove-Item -Recurse -Force "$HOME\msi-nav"
```

---

## Running Tests

```powershell
# Install Pester once
Install-Module Pester -Force

# Run the test suite
Invoke-Pester tests\powershell\MsiNav.Tests.ps1 -Output Detailed
```

---

## Troubleshooting

**`msi: The term 'msi' is not recognized`**
Ensure `msi_nav.ps1` is dot-sourced (`. $PROFILE` or restart terminal).

**`Cannot load msi_domain.ps1`**

```powershell
python3 "$HOME\msi-nav\src\python\generate_adapters.py" --ps1
. $PROFILE
```

**`Cannot be loaded because running scripts is disabled`**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**`msi doctor` shows repos not cloned**
Clone the repos under `$env:MSI_ROOT`:

```powershell
cd $env:MSI_ROOT
git clone <MSI-PAS-url>
git clone <MSI-PAS-CORE-url>
```