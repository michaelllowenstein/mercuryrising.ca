# MSI Nav — Linux / macOS Setup

## Requirements

| Dependency | Required | Notes |
|---|---|---|
| zsh ≥ 5.8 | Yes | macOS ships it; `apt install zsh` on Ubuntu |
| python3 ≥ 3.10 | Recommended | For `generate_adapters.py`, `validate_domain.py` |
| ripgrep (`rg`) | Optional | `brew install ripgrep` / `apt install ripgrep`; `grep` fallback used if absent |
| jq | Optional | For raw JSON inspection; not required by the tool |
| bats-core | Dev only | For running the test suite |

---

## Quick Install

```zsh
git clone <repo-url> ~/msi-nav
cd ~/msi-nav
chmod +x install/install-linux.sh
./install/install-linux.sh
source ~/.zshrc
msi doctor
```

The installer:
1. Creates `~/.local/bin/msi` and `~/.local/bin/msi-nav` symlinks
2. Runs `generate_adapters.py` to build `msi_domain.zsh` and `msi_domain.ps1` from JSON
3. Appends a `source` line to `~/.zshrc`
4. Adds `~/.local/bin` to `PATH` if not already present

---

## Manual Setup

If you prefer not to use the installer, add this block to `~/.zshrc`:

```zsh
export MSI_ROOT="$HOME/msi/MSIMGA"   # ← your checkout location
export MSI_EDITOR="code"
export MSI_NAV_HOME="$HOME/msi-nav"

# Optional overrides
# export MSI_REPO_PAS="MSI-PAS"
# export MSI_REPO_CORE="MSI-PAS-CORE"
# export MSI_REPO_WIDGET="MSI-Widget"
# export MSI_REPO_QE="MSI-QE"
# export MSI_REPO_CONFIG="PAS-APP-CONFIG"

source "$MSI_NAV_HOME/src/zsh/msi_nav.zsh"
```

Then generate the domain adapters once:
```zsh
python3 ~/msi-nav/src/python/generate_adapters.py
source ~/.zshrc
```

---

## Tab Completion

The installer copies `_msi` to `~/.zfunc/`. If you want to install it manually:

```zsh
mkdir -p ~/.zfunc
cp ~/msi-nav/src/zsh/completion/_msi ~/.zfunc/

# In ~/.zshrc, before compinit:
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
```

---

## Uninstall

```zsh
cd ~/msi-nav && ./install/uninstall-linux.sh
source ~/.zshrc
rm -rf ~/msi-nav   # optional: removes the repo entirely
```

---

## Running Tests

```zsh
# Install bats-core
brew install bats-core    # macOS
# OR
sudo apt install bats     # Ubuntu

# Run the test suite
bats tests/linux/msi-nav.bats
```

---

## Troubleshooting

**`msi: command not found`**
Ensure `~/.local/bin` is in your `PATH`:
```zsh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**Domain not loaded (`No domain data found`)**
```zsh
python3 ~/msi-nav/src/python/generate_adapters.py
source ~/.zshrc
```

**`msi doctor` shows repos not cloned**
Clone the repos under `$MSI_ROOT`:
```zsh
cd $MSI_ROOT
git clone <MSI-PAS-url>
git clone <MSI-PAS-CORE-url>
```