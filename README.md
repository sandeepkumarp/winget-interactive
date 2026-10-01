# winget-interactive

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)
[![Shell](https://img.shields.io/badge/Shell-PowerShell%207%20%7C%205.1-blueviolet.svg)](https://github.com/PowerShell/PowerShell)

An interactive, automated upgrade manager for Windows Package Manager (`winget`) with persistent memory.

---

## Why winget-interactive?

Native Windows Package Manager (`winget`) is great, but it has two major gaps:
1. **No Interactive Selection**: You can only run `winget upgrade --all` (upgrades everything blindly) or manually type out individual package IDs one by one.
2. **No "Always Yes" Auto-Approve List**: WinGet only supports blacklisting (`winget pin`), with no way to maintain an allowlist of tools you always want updated while prompting for everything else.

`winget-interactive` wraps `winget` into an interactive CLI that remembers your choices:
- **Upfront Decision Batching**: Review pending updates upfront in seconds, then let the sequential installer run unattended.
- **Persistent Preferences**:
  - `[Y] Yes (Once)`: Upgrade this time (Default — just press <kbd>Enter</kbd>).
  - `[N] No (Skip Once)`: Skip this update for now.
  - `[A] Always Yes`: Auto-upgrade this app on future runs without asking again.
  - `[S] Always Skip`: Never prompt or upgrade this app again.
  - `[Q] Quit`: Stop reviewing and proceed with approved packages.
- **Sequential Execution**: Installs approved packages one by one with live progress bars to eliminate Windows Installer (`msiexec.exe` error `1618`) concurrency locks.
- **UAC Auto-Elevation**: Requests Administrator rights upfront so you only confirm UAC once at launch, preventing interrupted background installations.
- **Zero Privacy Leakage**: Your personal preferences are stored privately in `%LOCALAPPDATA%\winget-interactive\preferences.json`, completely separate from the repository.

---

## Quick Installation

Open PowerShell as Administrator (or standard user) and run:

```powershell
irm https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main/install.ps1 | iex
```

### What the installer does:
- Installs to `%LOCALAPPDATA%\Programs\winget-interactive`
- Adds the directory to your User `PATH`
- Creates an auto-start shortcut in Windows Startup (`shell:startup`) so your system checks for updates upon logon

---

## Manual Installation (from Git)

```powershell
git clone https://github.com/sandeepkumarp/winget-interactive.git
cd winget-interactive
.\install.ps1
```

---

## Usage

Once installed, you can run the tool from any terminal (PowerShell, Command Prompt, or Windows Terminal) using either the full name or the short 3-letter alias:

```powershell
# Using the primary command
winget-interactive

# Using the quick alias
wgi
```

### Command-Line Options

```text
USAGE:
    winget-interactive [OPTIONS]
    wgi [OPTIONS]

GENERAL OPTIONS:
    -h, --help, -?            Show help message and exit
    -v, --version             Show version information and exit
    -u, --update              Update winget-interactive to the latest release
    --dry-run, -DryRun        Simulate scan and review without installing or saving rules
    --silent, -Silent         Pass --silent to winget for unattended installations
    --no-elevate, -NoElevate  Run in current user context without requesting UAC elevation
    --portable, -Portable     Store preferences locally next to the script instead of AppData

UPDATE CHECK OPTIONS:
    -EnableUpdateCheck        Enable daily automatic check for winget-interactive updates (default)
    -DisableUpdateCheck       Disable daily automatic check for winget-interactive updates

PREFERENCE MANAGEMENT:
    -ListPreferences          Show current 'Always Yes' and 'Always Skip' package rules
    -ResetPreferences         Clear all saved preference rules
    -RemoveRule <PackageID>   Remove a specific package ID from rules
    -AddAlwaysYes <PackageID> Add a package ID directly to Always Yes
    -AddAlwaysSkip <PackageID> Add a package ID directly to Always Skip (Don't ask again)
```

### Examples

**Simulate a run without modifying anything:**
```powershell
wgi --dry-run
```

**List your saved rules:**
```powershell
wgi -ListPreferences
```

**Update winget-interactive to the latest version:**
```powershell
wgi --update
```

**Remove a rule for a package:**
```powershell
wgi -RemoveRule "Microsoft.Edge"
```

---

## Managing Preferences

Your preferences are saved in `%LOCALAPPDATA%\winget-interactive\preferences.json`:

```json
{
  "AlwaysYes": [
    "astral-sh.uv",
    "Microsoft.VisualStudioCode"
  ],
  "AlwaysSkip": [
    "EpicGames.EpicGamesLauncher"
  ]
}
```

You can view and modify rules directly through the CLI switches (`-ListPreferences`, `-RemoveRule`, `-AddAlwaysYes`, `-AddAlwaysSkip`) or edit the JSON file directly.

---

## Windows Startup Behavior

If installed with the startup shortcut (enabled by default):
1. Upon logon, `winget-interactive` launches and requests UAC elevation once.
2. WinGet scans for available updates.
3. If no updates are available, it displays a status message and automatically exits after 5 seconds.
4. If updates are available, it auto-approves your `Always Yes` apps, auto-skips `Always Skip` apps, and prompts you for any unclassified packages.

---

## Uninstallation

To remove `winget-interactive` cleanly from your system:

```powershell
irm https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main/uninstall.ps1 | iex
```

Or from a local clone:
```powershell
.\uninstall.ps1
```

*(Pass `-PurgePreferences` if you also want to delete your saved application rules).*

---

## License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for details.

Copyright (c) 2026 Sandeep
