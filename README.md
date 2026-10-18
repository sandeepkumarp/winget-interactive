# winget-interactive

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)
[![Shell](https://img.shields.io/badge/Shell-PowerShell%207%20%7C%205.1-blueviolet.svg)](https://github.com/PowerShell/PowerShell)
[![Tests: Pester](https://img.shields.io/badge/Tests-Pester%2027%20Passed-brightgreen.svg)](tests/)

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
- **Single-Instance Protection**: Enforces single-instance execution via a named system mutex, preventing multiple concurrent runs and package manager database locks.
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
- **Optional Windows Startup**: Prompts whether you want `winget-interactive` to start on Windows logon (`[y/N]`, default: No) or via `-Startup` switch.
- **Daily Update Checks**: Prompts whether to enable daily checks for `winget-interactive` releases (`[Y/n]`, default: Yes).

---

## Manual Installation (from Git)

```powershell
git clone https://github.com/sandeepkumarp/winget-interactive.git
cd winget-interactive
.\install.ps1
```

For silent/automated installs:
```powershell
# Install without Windows Startup shortcut and enable daily checks
.\install.ps1 -NoStartupShortcut -CheckForUpdates

# Install with Windows Startup enabled
.\install.ps1 -Startup
```

---

## Portable / Zero-Install Mode

If you prefer not to install files to AppData or modify your system `PATH`, clone the repo and run it directly in portable mode:

```powershell
git clone https://github.com/sandeepkumarp/winget-interactive.git
cd winget-interactive
.\winget-interactive.ps1 -Portable
```

*(In portable mode, preferences are saved locally to `preferences.json` inside the script directory instead of `%LOCALAPPDATA%`.)*

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

WINDOWS STARTUP OPTIONS:
    -EnableStartup            Enable launching winget-interactive on Windows logon
    -DisableStartup           Disable launching winget-interactive on Windows logon

UPDATE CHECK OPTIONS:
    -EnableUpdateCheck        Enable daily automatic check for winget-interactive updates
    -DisableUpdateCheck       Disable daily automatic check for winget-interactive updates

PREFERENCE MANAGEMENT:
    -ListPreferences          Show current preferences (Startup, Updates, Always Yes/Skip)
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

**List your saved rules and startup status:**
```powershell
wgi -ListPreferences
```

**Enable or disable Windows startup:**
```powershell
wgi -EnableStartup
wgi -DisableStartup
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
  ],
  "CheckForUpdates": true,
  "StartupConfigured": true
}
```

You can view and modify rules directly through the CLI switches (`-ListPreferences`, `-RemoveRule`, `-AddAlwaysYes`, `-AddAlwaysSkip`, `-EnableStartup`, `-DisableStartup`, `-EnableUpdateCheck`, `-DisableUpdateCheck`) or edit the JSON file directly.

---

## Testing & Quality Assurance

The project includes an automated test suite powered by **Pester**:

```powershell
pwsh -File .\tests\run-tests.ps1
```

Tests cover:
- Single-instance mutex acquisition, collision rejection, and clean release
- Windows Startup shortcut creation, deletion, and detection
- Preferences persistence, case-insensitive ID matching, and unreadable file backup
- First-run onboarding migration for existing users
- Installer configuration and parameters (`-Startup`, `-NoStartupShortcut`, `-CheckForUpdates`, `-NoUpdateCheck`)
- CLI command switches (`-EnableStartup`, `-DisableStartup`, `-EnableUpdateCheck`, `-DisableUpdateCheck`)
- Relaunch argument quoting and switch forwarding across restarts
- Elevation failure and declined UAC prompt detection

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
