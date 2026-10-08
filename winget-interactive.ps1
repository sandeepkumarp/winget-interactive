<#
.SYNOPSIS
    Interactive Windows Package Manager (winget) Upgrade Tool with Persistent Memory.

.DESCRIPTION
    Scans for available software updates via Windows Package Manager (winget).
    Allows interactive per-package review with persistent preferences:
      - [Y] Yes (Once) - Default
      - [N] No (Skip Once)
      - [A] Always Yes (Saved to AlwaysYes list)
      - [S] Always Skip (Saved to AlwaysSkip list / Don't ask again)
      - [Q] Quit review loop
    Batches user decisions upfront and executes approved upgrades sequentially
    with live progress bars and zero installer lock collisions.

.PARAMETER Help
    Displays command-line help and usage information. Aliases: -h, --help, -?

.PARAMETER Version
    Displays application version information. Aliases: -v, --version

.PARAMETER Update
    Updates winget-interactive to the latest release from GitHub. Aliases: -u, --update

.PARAMETER EnableUpdateCheck
    Enables automatic daily check for new winget-interactive releases.

.PARAMETER DisableUpdateCheck
    Disables automatic daily check for new winget-interactive releases.

.PARAMETER EnableStartup
    Enables launching winget-interactive automatically upon Windows logon.

.PARAMETER DisableStartup
    Disables launching winget-interactive automatically upon Windows logon.

.PARAMETER NoElevate
    Skips the automatic Administrator elevation check and runs in the current context.

.PARAMETER Silent
    Passes the '--silent' switch to winget for unattended background installations.

.PARAMETER DryRun
    Simulates the scan, prompt, and execution flow without modifying software or saving rules.

.PARAMETER Portable
    Stores and reads preferences from a local preferences.json file in the script directory
    instead of the default %LOCALAPPDATA%\winget-interactive\ folder.

.PARAMETER ListPreferences
    Displays all saved 'Always Yes', 'Always Skip', Startup, and Update preferences and exits.

.PARAMETER ResetPreferences
    Clears all saved rules in preferences.json and exits.

.PARAMETER RemoveRule
    Removes a specific Package ID from saved preferences and exits.

.PARAMETER AddAlwaysYes
    Manually adds a package ID to the AlwaysYes list and exits.

.PARAMETER AddAlwaysSkip
    Manually adds a package ID to the AlwaysSkip list and exits.

.PARAMETER NoExecute
    Internal switch used by test suites to load functions without executing the main loop.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Alias('h', '?')]
    [switch]$Help,

    [Alias('v', 'ver')]
    [switch]$Version,

    [Alias('u', 'upgrade')]
    [switch]$Update,

    [switch]$EnableUpdateCheck,
    [switch]$DisableUpdateCheck,
    [switch]$EnableStartup,
    [switch]$DisableStartup,
    [switch]$NoElevate,
    [switch]$Silent,
    [switch]$DryRun,
    [switch]$Portable,
    [switch]$ListPreferences,
    [switch]$ResetPreferences,
    [string]$RemoveRule,
    [string]$AddAlwaysYes,
    [string]$AddAlwaysSkip,
    [switch]$NoExecute
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "1.1.0"
$RepoRawBase   = "https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main"

# --- Display Help ---
if ($Help) {
    Write-Host @"

winget-interactive v$ScriptVersion
Interactive Windows Package Manager Upgrade Tool with Persistent Memory
https://github.com/sandeepkumarp/winget-interactive

USAGE:
    winget-interactive [OPTIONS]
    wgi [OPTIONS]

GENERAL OPTIONS:
    -h, --help, -?            Show this help message and exit
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

INTERACTIVE KEYS:
    [Y] Yes (Once - Default)  Upgrade package this time
    [N] No (Skip Once)        Skip package this time
    [A] Always Yes            Upgrade now and remember preference for future runs
    [S] Always Skip           Skip now and never prompt or upgrade again
    [Q] Quit                  Stop reviewing and proceed with approved upgrades

"@ -ForegroundColor Cyan
    exit 0
}

# --- Display Version ---
if ($Version) {
    Write-Host "winget-interactive v$ScriptVersion" -ForegroundColor Green
    exit 0
}

# --- Determine Preferences Storage Path ---
if ($Portable) {
    $ConfigDir = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
        $ConfigDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($ConfigDir)) {
        $ConfigDir = (Get-Location).Path
    }
} else {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = Join-Path $HOME "AppData\Local"
    }
    $ConfigDir = Join-Path $localAppData "winget-interactive"
}

if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
$ConfigFile = Join-Path $ConfigDir "preferences.json"

# ==============================================================================
# Helper Functions (Modular & Unit-Testable)
# ==============================================================================

# --- Single-Instance Mutex Enforcement ---
$script:activeMutexes = @{}

function Test-AcquireSingleInstanceMutex {
    [CmdletBinding()]
    param(
        [string]$MutexName = "Local\WingetInteractive_SingleInstance_Mutex",
        [switch]$CheckOnly
    )
    if ($script:activeMutexes.ContainsKey($MutexName)) {
        return $false
    }
    try {
        $mutex = New-Object System.Threading.Mutex($false, $MutexName)
        $hasHandle = $mutex.WaitOne(0, $false)
        if (-not $hasHandle) {
            $mutex.Close()
            return $false
        }
        if ($CheckOnly) {
            $mutex.ReleaseMutex()
            $mutex.Close()
            return $false
        }
        $script:activeMutexes[$MutexName] = $mutex
        return $true
    } catch {
        return $false
    }
}

function Release-SingleInstanceMutex {
    [CmdletBinding()]
    param(
        [string]$MutexName = "Local\WingetInteractive_SingleInstance_Mutex"
    )
    if ($script:activeMutexes.ContainsKey($MutexName)) {
        $m = $script:activeMutexes[$MutexName]
        try {
            $m.ReleaseMutex()
            $m.Dispose()
        } catch {}
        $script:activeMutexes.Remove($MutexName)
    }
}

# --- Windows Startup Management ---
function Get-StartupShortcutPath {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    return (Join-Path $startupFolder "Winget Interactive.lnk")
}

function Test-IsStartupEnabled {
    [CmdletBinding()]
    param(
        [string]$ShortcutPath = (Get-StartupShortcutPath)
    )
    return (Test-Path $ShortcutPath)
}

function Set-StartupShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enable,
        [string]$TargetPath,
        [string]$ShortcutPath = (Get-StartupShortcutPath)
    )

    if ($Enable) {
        if ([string]::IsNullOrWhiteSpace($TargetPath)) {
            $scriptDir = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($scriptDir)) {
                $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
            }
            $TargetPath = Join-Path $scriptDir "winget-interactive.cmd"
        }
        $targetDir = Split-Path -Parent $TargetPath

        $parentFolder = Split-Path -Parent $ShortcutPath
        if (-not (Test-Path $parentFolder)) {
            New-Item -ItemType Directory -Path $parentFolder -Force | Out-Null
        }

        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = $targetDir
        $shortcut.Description = "Interactive Windows Package Manager Upgrade Tool"
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
    } else {
        if (Test-Path $ShortcutPath) {
            Remove-Item -Path $ShortcutPath -Force -ErrorAction SilentlyContinue
        }
        $legacy = Join-Path (Split-Path -Parent $ShortcutPath) "Winget Updater.lnk"
        if (Test-Path $legacy) {
            Remove-Item -Path $legacy -Force -ErrorAction SilentlyContinue
        }
    }
}

# --- Preferences Persistence ---
function Get-Preferences {
    [CmdletBinding()]
    param(
        [string]$CustomConfigFile = $ConfigFile
    )
    if (Test-Path $CustomConfigFile) {
        try {
            $raw = Get-Content -Path $CustomConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
            $alwaysYes = [System.Collections.Generic.List[string]](@($raw.AlwaysYes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
            $alwaysSkip = [System.Collections.Generic.List[string]](@($raw.AlwaysSkip | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
            $checkUpdates = if ($null -ne $raw.CheckForUpdates) { [bool]$raw.CheckForUpdates } else { $true }
            $lastCheck = if ($null -ne $raw.LastUpdateCheck) { [string]$raw.LastUpdateCheck } else { "" }
            $startupConfigured = if ($null -ne $raw.StartupConfigured) { [bool]$raw.StartupConfigured } else { $false }
            
            return [PSCustomObject]@{
                AlwaysYes         = $alwaysYes
                AlwaysSkip        = $alwaysSkip
                CheckForUpdates   = $checkUpdates
                LastUpdateCheck   = $lastCheck
                StartupConfigured = $startupConfigured
            }
        } catch {
            Write-Warning "Failed to parse preferences from $CustomConfigFile. Initializing default preferences."
        }
    }
    return [PSCustomObject]@{
        AlwaysYes         = [System.Collections.Generic.List[string]]@()
        AlwaysSkip        = [System.Collections.Generic.List[string]]@()
        CheckForUpdates   = $true
        LastUpdateCheck   = ""
        StartupConfigured = $false
    }
}

function Save-Preferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prefs,
        [string]$CustomConfigFile = $ConfigFile
    )
    $data = [PSCustomObject]@{
        AlwaysYes         = @($Prefs.AlwaysYes | Select-Object -Unique | Sort-Object)
        AlwaysSkip        = @($Prefs.AlwaysSkip | Select-Object -Unique | Sort-Object)
        CheckForUpdates   = [bool]$Prefs.CheckForUpdates
        LastUpdateCheck   = [string]$Prefs.LastUpdateCheck
        StartupConfigured = [bool]$Prefs.StartupConfigured
    }
    $targetDir = Split-Path -Parent $CustomConfigFile
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    $json = $data | ConvertTo-Json -Depth 5
    $json | Set-Content -Path $CustomConfigFile -Encoding utf8
}

function Show-PreferencesSummary ($prefs) {
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "              Saved WinGet Preferences                  " -ForegroundColor Cyan
    Write-Host "Config Path: $ConfigFile" -ForegroundColor DarkGray
    Write-Host "========================================================" -ForegroundColor Cyan
    
    $updateStatus = if ($prefs.CheckForUpdates) { "Enabled" } else { "Disabled" }
    $lastCheckedText = if ([string]::IsNullOrWhiteSpace($prefs.LastUpdateCheck)) { "Never" } else { $prefs.LastUpdateCheck }
    Write-Host "Daily Update Check: $updateStatus (Last Checked: $lastCheckedText)" -ForegroundColor Gray

    $startupEnabled = Test-IsStartupEnabled
    $startupStatus = if ($startupEnabled) { "Enabled" } else { "Disabled" }
    Write-Host "Windows Startup:    $startupStatus" -ForegroundColor Gray

    Write-Host "`n[Always Yes] (Auto-installed without prompting):" -ForegroundColor Green
    if ($prefs.AlwaysYes.Count -eq 0) {
        Write-Host "  (None configured)" -ForegroundColor DarkGray
    } else {
        foreach ($id in $prefs.AlwaysYes) {
            Write-Host "  - $id" -ForegroundColor Green
        }
    }
    
    Write-Host "`n[Always Skip] (Ignored / Don't ask again):" -ForegroundColor Yellow
    if ($prefs.AlwaysSkip.Count -eq 0) {
        Write-Host "  (None configured)" -ForegroundColor DarkGray
    } else {
        foreach ($id in $prefs.AlwaysSkip) {
            Write-Host "  - $id" -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

# --- First-Run Onboarding Migration for Existing Users ---
function Invoke-FirstRunMigration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Prefs,
        [bool]$IsInteractive = $true,
        [string]$ShortcutPath = (Get-StartupShortcutPath),
        [string]$StartupPromptResponse,
        [string]$UpdatePromptResponse
    )

    if ($Prefs.StartupConfigured) {
        return $false
    }

    $shortcutActive = Test-IsStartupEnabled -ShortcutPath $ShortcutPath

    if ($IsInteractive) {
        Write-Host "`n========================================================" -ForegroundColor Cyan
        Write-Host "     First-Run Setup: Startup & Update Preferences      " -ForegroundColor Cyan
        Write-Host "========================================================" -ForegroundColor Cyan
        Write-Host "This version of winget-interactive lets you configure" -ForegroundColor Gray
        Write-Host "Windows Startup and Daily Update preferences.`n" -ForegroundColor Gray

        # 1. Startup Decision
        if ($shortcutActive) {
            Write-Host "[Notice] A Windows Startup shortcut is currently enabled from previous installation." -ForegroundColor Yellow
            $promptMsg = "Keep winget-interactive launching automatically on Windows startup? [Y/n] (Default: Y): "
            $defaultChoice = 'y'
        } else {
            $promptMsg = "Launch winget-interactive automatically on Windows startup? [y/N] (Default: N): "
            $defaultChoice = 'n'
        }

        if ($null -ne $StartupPromptResponse) {
            $ans = $StartupPromptResponse
        } else {
            Write-Host -NoNewline $promptMsg -ForegroundColor White
            $ans = Read-Host
        }

        if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $defaultChoice }
        $ans = $ans.Trim().ToLowerInvariant()

        if ($ans -in @('y', 'yes')) {
            Set-StartupShortcut -Enable $true -ShortcutPath $ShortcutPath
            Write-Host "  -> Windows Startup: Enabled." -ForegroundColor Green
        } else {
            Set-StartupShortcut -Enable $false -ShortcutPath $ShortcutPath
            Write-Host "  -> Windows Startup: Disabled." -ForegroundColor DarkGray
        }

        # 2. Daily Update Check Decision
        $updateMsg = "`nCheck for winget-interactive updates automatically once a day? [Y/n] (Default: Y): "
        if ($null -ne $UpdatePromptResponse) {
            $upAns = $UpdatePromptResponse
        } else {
            Write-Host -NoNewline $updateMsg -ForegroundColor White
            $upAns = Read-Host
        }

        if ([string]::IsNullOrWhiteSpace($upAns)) { $upAns = 'y' }
        $upAns = $upAns.Trim().ToLowerInvariant()

        if ($upAns -in @('y', 'yes')) {
            $Prefs.CheckForUpdates = $true
            Write-Host "  -> Daily Update Checks: Enabled." -ForegroundColor Green
        } else {
            $Prefs.CheckForUpdates = $false
            Write-Host "  -> Daily Update Checks: Disabled." -ForegroundColor DarkGray
        }
    }

    $Prefs.StartupConfigured = $true
    return $true
}

# --- Self-Update Handler ---
function Restart-WgiProcess {
    Write-Host "[i] Restarting winget-interactive with updated version..." -ForegroundColor Cyan
    $exe = (Get-Process -Id $PID).Path
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    if ($args) { $argList += $args }
    Release-SingleInstanceMutex
    Start-Process -FilePath $exe -ArgumentList $argList
    exit 0
}

function Invoke-SelfUpdate {
    [CmdletBinding()]
    param(
        [switch]$RestartAfterUpdate
    )

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "         Updating winget-interactive...                 " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "Current Version: v$ScriptVersion" -ForegroundColor Gray

    # 1. If running inside a git repository, pull latest commits
    $gitDir = Join-Path $PSScriptRoot ".git"
    if (Test-Path $gitDir) {
        Write-Host "[i] Detected local Git repository. Pulling latest commits..." -ForegroundColor Cyan
        try {
            & git -C $PSScriptRoot pull
            Write-Host "`n[+] Git repository updated successfully." -ForegroundColor Green
            if ($RestartAfterUpdate) {
                Restart-WgiProcess
            }
            exit 0
        } catch {
            Write-Error "Failed to update via git pull: $_"
            exit 1
        }
    }

    # 2. If running an installed copy, download latest files from GitHub
    Write-Host "[i] Checking latest version from GitHub..." -ForegroundColor Cyan
    $remoteVersion = "latest"
    try {
        $meta = Invoke-RestMethod -Uri "$RepoRawBase/version.json" -TimeoutSec 5 -ErrorAction Stop
        if ($meta.version) { $remoteVersion = $meta.version }
    } catch {
        Write-Warning "Could not fetch version metadata. Proceeding with file download."
    }

    Write-Host "[i] Upgrading to: v$remoteVersion" -ForegroundColor Cyan

    $filesToUpdate = @(
        "winget-interactive.ps1",
        "winget-interactive.cmd",
        "wgi.cmd",
        "install.ps1",
        "uninstall.ps1",
        "version.json"
    )

    $targetDir = $PSScriptRoot
    $successCount = 0

    foreach ($file in $filesToUpdate) {
        $fileUrl = "$RepoRawBase/$file"
        $tempFile = Join-Path $targetDir "$file.tmp"
        $destFile = Join-Path $targetDir $file
        try {
            Invoke-RestMethod -Uri $fileUrl -OutFile $tempFile -TimeoutSec 10 -ErrorAction Stop
            Move-Item -Path $tempFile -Destination $destFile -Force
            Write-Host "  [+] Updated $file" -ForegroundColor Green
            $successCount++
        } catch {
            Write-Warning "Failed to update $($file): $_"
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }

    if ($successCount -eq $filesToUpdate.Count) {
        Write-Host "`n[+] winget-interactive has been successfully updated to v$remoteVersion!" -ForegroundColor Green
        if ($RestartAfterUpdate) {
            Restart-WgiProcess
        }
    } else {
        Write-Warning "`nSome files could not be updated. Please run the installer again if needed."
    }
    exit 0
}

# --- Automatic Daily Update Check ---
function Check-DailyUpdate ($prefs, [bool]$isInteractive = $true) {
    if (-not $prefs.CheckForUpdates) { return }
    $today = (Get-Date).ToString("yyyy-MM-dd")
    if ($prefs.LastUpdateCheck -eq $today) { return }

    try {
        $meta = Invoke-RestMethod -Uri "$RepoRawBase/version.json" -TimeoutSec 2 -ErrorAction Stop
        if ($meta.version -and ([version]$meta.version -gt [version]$ScriptVersion)) {
            Write-Host "`n========================================================" -ForegroundColor Yellow
            Write-Host "       winget-interactive Update Available!             " -ForegroundColor Yellow
            Write-Host "========================================================" -ForegroundColor Yellow
            Write-Host "A new version of winget-interactive is available:" -ForegroundColor White
            Write-Host "  Installed: v$ScriptVersion  ===>  Latest: v$($meta.version)`n" -ForegroundColor Yellow
            
            if ($isInteractive) {
                Write-Host -NoNewline "Would you like to update winget-interactive now? [Y/n] (Default: Y): " -ForegroundColor White
                $choice = Read-Host
                if ([string]::IsNullOrWhiteSpace($choice)) { $choice = 'y' }
                $choice = $choice.Trim().ToLowerInvariant()
                
                if ($choice -in @('y', 'yes')) {
                    $prefs.LastUpdateCheck = $today
                    Save-Preferences -Prefs $prefs
                    Invoke-SelfUpdate -RestartAfterUpdate
                    return
                } else {
                    Write-Host "-> Update deferred. Will check again tomorrow.`n" -ForegroundColor DarkGray
                }
            } else {
                Write-Host "Run 'wgi -u' to update to the latest release.`n" -ForegroundColor DarkGray
            }
        }
        $prefs.LastUpdateCheck = $today
        Save-Preferences -Prefs $prefs
    } catch {
        # Fail silently if offline or network is unreachable
    }
}

# --- UAC Elevation Helpers ---
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Elevate-Process {
    Write-Host "`n[i] Requesting Administrator privileges for uninterrupted updates..." -ForegroundColor Cyan
    $exe = (Get-Process -Id $PID).Path
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
    
    if ($Silent) { $argList += "-Silent" }
    if ($DryRun) { $argList += "-DryRun" }
    if ($Portable) { $argList += "-Portable" }
    if ($ListPreferences) { $argList += "-ListPreferences" }
    if ($ResetPreferences) { $argList += "-ResetPreferences" }
    if ($RemoveRule) { $argList += @("-RemoveRule", $RemoveRule) }
    if ($AddAlwaysYes) { $argList += @("-AddAlwaysYes", $AddAlwaysYes) }
    if ($AddAlwaysSkip) { $argList += @("-AddAlwaysSkip", $AddAlwaysSkip) }
    if ($EnableUpdateCheck) { $argList += "-EnableUpdateCheck" }
    if ($DisableUpdateCheck) { $argList += "-DisableUpdateCheck" }
    if ($EnableStartup) { $argList += "-EnableStartup" }
    if ($DisableStartup) { $argList += "-DisableStartup" }
    
    try {
        Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs
        exit 0
    } catch {
        Write-Warning "Elevation cancelled or failed. Continuing in current user context."
    }
}

# ==============================================================================
# Execution Entry Point
# ==============================================================================

# If dot-sourced by test runner, stop here so tests can invoke functions freely
if ($NoExecute) {
    return
}

# --- Self-Update CLI Handler ---
if ($Update) {
    Invoke-SelfUpdate
}

# Auto-elevate unless running safe preference/startup checks or explicitly disabled
if (-not (Test-IsAdmin) -and -not $NoElevate -and -not $ListPreferences -and -not $EnableUpdateCheck -and -not $DisableUpdateCheck -and -not $EnableStartup -and -not $DisableStartup) {
    Elevate-Process
}

# --- Load Preferences ---
$prefs = Get-Preferences

# --- Startup CLI Handlers ---
if ($EnableStartup) {
    Set-StartupShortcut -Enable $true
    Write-Host "Windows Startup shortcut has been ENABLED." -ForegroundColor Green
    Write-Host "Location: $(Get-StartupShortcutPath)" -ForegroundColor DarkGray
    exit 0
}

if ($DisableStartup) {
    Set-StartupShortcut -Enable $false
    Write-Host "Windows Startup shortcut has been DISABLED." -ForegroundColor Yellow
    exit 0
}

# --- CLI Preference Management Execution ---
if ($EnableUpdateCheck) {
    $prefs.CheckForUpdates = $true
    Save-Preferences -Prefs $prefs
    Write-Host "Automatic daily update check has been ENABLED." -ForegroundColor Green
    exit 0
}

if ($DisableUpdateCheck) {
    $prefs.CheckForUpdates = $false
    Save-Preferences -Prefs $prefs
    Write-Host "Automatic daily update check has been DISABLED." -ForegroundColor Yellow
    exit 0
}

if ($ResetPreferences) {
    $prefs.AlwaysYes.Clear()
    $prefs.AlwaysSkip.Clear()
    Save-Preferences -Prefs $prefs
    Write-Host "Preferences have been reset successfully." -ForegroundColor Green
    exit 0
}

if ($RemoveRule) {
    $removed = $false
    if ($prefs.AlwaysYes.Remove($RemoveRule)) { $removed = $true }
    if ($prefs.AlwaysSkip.Remove($RemoveRule)) { $removed = $true }
    if ($removed) {
        Save-Preferences -Prefs $prefs
        Write-Host "Removed rule for package '$RemoveRule'." -ForegroundColor Green
    } else {
        Write-Warning "Package ID '$RemoveRule' was not found in preferences."
    }
    exit 0
}

if ($AddAlwaysYes) {
    $prefs.AlwaysSkip.Remove($AddAlwaysYes) | Out-Null
    if (-not $prefs.AlwaysYes.Contains($AddAlwaysYes)) {
        $prefs.AlwaysYes.Add($AddAlwaysYes)
        Save-Preferences -Prefs $prefs
        Write-Host "Added '$AddAlwaysYes' to Always Yes list." -ForegroundColor Green
    } else {
        Write-Host "'$AddAlwaysYes' is already in Always Yes list." -ForegroundColor Yellow
    }
    exit 0
}

if ($AddAlwaysSkip) {
    $prefs.AlwaysYes.Remove($AddAlwaysSkip) | Out-Null
    if (-not $prefs.AlwaysSkip.Contains($AddAlwaysSkip)) {
        $prefs.AlwaysSkip.Add($AddAlwaysSkip)
        Save-Preferences -Prefs $prefs
        Write-Host "Added '$AddAlwaysSkip' to Always Skip list." -ForegroundColor Green
    } else {
        Write-Host "'$AddAlwaysSkip' is already in Always Skip list." -ForegroundColor Yellow
    }
    exit 0
}

if ($ListPreferences) {
    Show-PreferencesSummary $prefs
    exit 0
}

# --- Existing User Onboarding Migration ---
$isConsoleInteractive = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected) -and (-not $Silent) -and (-not $DryRun)
if ($isConsoleInteractive -and (-not $prefs.StartupConfigured)) {
    if (Invoke-FirstRunMigration -Prefs $prefs -IsInteractive $true) {
        Save-Preferences -Prefs $prefs
    }
}

# --- Check For winget-interactive Updates ---
Check-DailyUpdate $prefs -isInteractive $isConsoleInteractive

# --- Enforce Single-Instance Execution ---
if (-not (Test-AcquireSingleInstanceMutex)) {
    Write-Host "`n[!] Another instance of winget-interactive is already running." -ForegroundColor Yellow
    Write-Host "    Only one instance can run at a time to prevent package manager collisions.`n" -ForegroundColor DarkGray
    exit 0
}

try {
    # --- Main Scan & Upgrade Routine ---
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "                  winget-interactive                    " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "[i] Scanning system for available upgrades via winget..." -ForegroundColor Gray

    # Run winget upgrade to check for available updates
    try {
        $rawOutput = & winget upgrade --accept-source-agreements 2>&1 | Out-String -Stream
    } catch {
        Write-Error "Failed to execute 'winget upgrade': $_"
        exit 1
    }

    # Find column header line
    $headerLine = $rawOutput | Where-Object { $_ -match '^Name\s+Id\s+Version\s+Available' } | Select-Object -First 1

    if (-not $headerLine) {
        # Check if winget reported no upgrades
        $noUpgrades = $rawOutput | Where-Object { $_ -match 'No applicable update found|No installed package found' }
        if ($noUpgrades -or ($rawOutput -join ' ') -match '0 upgrades available') {
            Write-Host "`n[+] All applications are up to date! No upgrades found." -ForegroundColor Green
            Write-Host "Closing in 5 seconds..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
            exit 0
        } else {
            Write-Host "`nNo upgradable packages detected in output." -ForegroundColor Yellow
            exit 0
        }
    }

    # Determine dynamic column indices based on header positions
    $idIdx    = $headerLine.IndexOf("Id")
    $verIdx   = $headerLine.IndexOf("Version")
    $availIdx = $headerLine.IndexOf("Available")
    $srcIdx   = $headerLine.IndexOf("Source")

    $packages = @()
    $recording = $false

    foreach ($line in $rawOutput) {
        if ($line -match '^---') {
            $recording = $true
            continue
        }
        if ($recording) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\d+\s+upgrades available') {
                break
            }
            if ($line.Length -gt $availIdx) {
                $name  = $line.Substring(0, [Math]::Min($idIdx, $line.Length)).Trim()
                $id    = if ($line.Length -gt $idIdx) { $line.Substring($idIdx, [Math]::Min($verIdx - $idIdx, $line.Length - $idIdx)).Trim() } else { "" }
                $ver   = if ($line.Length -gt $verIdx) { $line.Substring($verIdx, [Math]::Min($availIdx - $verIdx, $line.Length - $verIdx)).Trim() } else { "" }
                $avail = if ($line.Length -gt $availIdx) {
                    if ($srcIdx -gt 0 -and $line.Length -gt $srcIdx) {
                        $line.Substring($availIdx, $srcIdx - $availIdx).Trim()
                    } else {
                        $line.Substring($availIdx).Trim()
                    }
                } else { "" }
                
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    $packages += [PSCustomObject]@{
                        Name             = $name
                        Id               = $id
                        InstalledVersion = $ver
                        AvailableVersion = $avail
                    }
                }
            }
        }
    }

    if ($packages.Count -eq 0) {
        Write-Host "`n[+] All applications are up to date! No upgrades found." -ForegroundColor Green
        Write-Host "Closing in 5 seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
        exit 0
    }

    Write-Host "`nFound $($packages.Count) package(s) with available updates.`n" -ForegroundColor Green

    # Categorize packages
    $approvedQueue = [System.Collections.Generic.List[PSCustomObject]]@()
    $skippedList   = [System.Collections.Generic.List[PSCustomObject]]@()
    $toReview      = [System.Collections.Generic.List[PSCustomObject]]@()

    foreach ($pkg in $packages) {
        if ($prefs.AlwaysYes.Contains($pkg.Id)) {
            Write-Host "[Auto-Approved] $($pkg.Name) ($($pkg.Id)) [$($pkg.InstalledVersion) -> $($pkg.AvailableVersion)]" -ForegroundColor Green
            $approvedQueue.Add($pkg)
        }
        elseif ($prefs.AlwaysSkip.Contains($pkg.Id)) {
            Write-Host "[Auto-Skipped]  $($pkg.Name) ($($pkg.Id)) (Configured to Always Skip)" -ForegroundColor DarkGray
            $skippedList.Add($pkg)
        }
        else {
            $toReview.Add($pkg)
        }
    }

    # Interactive Prompt for unclassified packages
    if ($toReview.Count -gt 0) {
        Write-Host "`n--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "Reviewing $($toReview.Count) package(s) needing your decision..." -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        
        $reviewIndex = 1
        $quitPrompting = $false
        
        foreach ($pkg in $toReview) {
            if ($quitPrompting) {
                Write-Host "[Skipped]       $($pkg.Name) ($($pkg.Id)) (Review stopped by user)" -ForegroundColor DarkGray
                $skippedList.Add($pkg)
                continue
            }
            
            Write-Host "`n[$reviewIndex of $($toReview.Count)]" -ForegroundColor Magenta -NoNewline
            Write-Host " Package Update Details:" -ForegroundColor White
            Write-Host "  Name:      $($pkg.Name)" -ForegroundColor White
            Write-Host "  ID:        $($pkg.Id)" -ForegroundColor Cyan
            Write-Host "  Installed: $($pkg.InstalledVersion)  ===>  Available: $($pkg.AvailableVersion)" -ForegroundColor Yellow
            Write-Host "  Options:" -ForegroundColor DarkGray
            Write-Host "    [Y] Yes (Once)               - Upgrade this package now [Default]" -ForegroundColor White
            Write-Host "    [N] No (Skip Once)           - Skip this update this time" -ForegroundColor DarkGray
            Write-Host "    [A] Always Yes               - Upgrade now and remember for future" -ForegroundColor Green
            Write-Host "    [S] Always Skip / Don't Ask  - Skip and never ask again" -ForegroundColor Yellow
            Write-Host "    [Q] Quit                     - Stop reviewing; proceed with approved" -ForegroundColor Red
            
            while ($true) {
                Write-Host "Select choice [Y/n/a/s/q] (Default: Y): " -NoNewline -ForegroundColor White
                $choice = Read-Host
                if ([string]::IsNullOrWhiteSpace($choice)) { $choice = 'y' }
                $choice = $choice.Trim().ToLowerInvariant()
                
                if ($choice -eq 'y') {
                    $approvedQueue.Add($pkg)
                    Write-Host "-> Queued for upgrade." -ForegroundColor Green
                    break
                }
                elseif ($choice -eq 'n') {
                    $skippedList.Add($pkg)
                    Write-Host "-> Skipped for this run." -ForegroundColor DarkGray
                    break
                }
                elseif ($choice -eq 'a') {
                    $approvedQueue.Add($pkg)
                    if (-not $DryRun) {
                        $prefs.AlwaysYes.Add($pkg.Id)
                        Save-Preferences -Prefs $prefs
                        Write-Host "-> Queued and saved to 'Always Yes' list." -ForegroundColor Green
                    } else {
                        Write-Host "-> [DRY RUN] Queued (Would save to 'Always Yes' list)." -ForegroundColor Green
                    }
                    break
                }
                elseif ($choice -eq 's') {
                    $skippedList.Add($pkg)
                    if (-not $DryRun) {
                        $prefs.AlwaysSkip.Add($pkg.Id)
                        Save-Preferences -Prefs $prefs
                        Write-Host "-> Skipped and saved to 'Always Skip' (Don't ask again) list." -ForegroundColor Yellow
                    } else {
                        Write-Host "-> [DRY RUN] Skipped (Would save to 'Always Skip' list)." -ForegroundColor Yellow
                    }
                    break
                }
                elseif ($choice -eq 'q') {
                    $quitPrompting = $true
                    Write-Host "-> Stopped reviewing. Remaining unapproved packages will be skipped." -ForegroundColor Yellow
                    $skippedList.Add($pkg)
                    break
                }
                else {
                    Write-Host "Invalid choice. Please enter Y, N, A, S, or Q." -ForegroundColor Red
                }
            }
            $reviewIndex++
        }
    }

    # --- Sequential Installation Execution Phase ---
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "               Installation Phase                       " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    if ($approvedQueue.Count -eq 0) {
        Write-Host "No packages were selected for installation.`n" -ForegroundColor Yellow
    } else {
        Write-Host "Starting sequential installation of $($approvedQueue.Count) package(s)...`n" -ForegroundColor Green
    }

    $summaryReport = [System.Collections.Generic.List[PSCustomObject]]@()

    # Record already skipped items
    foreach ($s in $skippedList) {
        $summaryReport.Add([PSCustomObject]@{
            Name             = $s.Name
            Id               = $s.Id
            InstalledVersion = $s.InstalledVersion
            AvailableVersion = $s.AvailableVersion
            Result           = "Skipped"
        })
    }

    $itemNum = 1
    foreach ($pkg in $approvedQueue) {
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "[$itemNum of $($approvedQueue.Count)] Upgrading: $($pkg.Name) ($($pkg.Id))" -ForegroundColor Cyan
        Write-Host "Version: $($pkg.InstalledVersion) ===> $($pkg.AvailableVersion)" -ForegroundColor Gray
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        
        $wingetArgs = @(
            "upgrade",
            "--id", $pkg.Id,
            "--exact",
            "--accept-source-agreements",
            "--accept-package-agreements"
        )
        if ($Silent) {
            $wingetArgs += "--silent"
        }

        if ($DryRun) {
            Write-Host "[DRY RUN] Would execute: winget $($wingetArgs -join ' ')" -ForegroundColor Yellow
            $resultStatus = "Simulated (DryRun)"
        } else {
            & winget @wingetArgs
            $exitCode = $LASTEXITCODE
            
            if ($exitCode -eq 0) {
                Write-Host "[+] Successfully updated $($pkg.Name)!" -ForegroundColor Green
                $resultStatus = "Success"
            }
            elseif ($exitCode -eq -1978335189) { # 0x8A15002B: Already up to date
                Write-Host "[+] Already up to date or completed." -ForegroundColor Green
                $resultStatus = "Success (NoOp)"
            }
            elseif ($exitCode -eq 3010) { # ERROR_SUCCESS_REBOOT_REQUIRED
                Write-Host "[+] Successfully updated $($pkg.Name) (System restart required)." -ForegroundColor Yellow
                $resultStatus = "Restart Required"
            }
            else {
                Write-Host "[-] Upgrade completed with exit code: $exitCode" -ForegroundColor Red
                $resultStatus = "Failed (ExitCode: $exitCode)"
            }
        }

        $summaryReport.Add([PSCustomObject]@{
            Name             = $pkg.Name
            Id               = $pkg.Id
            InstalledVersion = $pkg.InstalledVersion
            AvailableVersion = $pkg.AvailableVersion
            Result           = $resultStatus
        })
        
        $itemNum++
    }

    # --- Final Summary ---
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "                   Final Summary                        " -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    $successCount = ($summaryReport | Where-Object { $_.Result -like 'Success*' -or $_.Result -like 'Restart*' -or $_.Result -like 'Simulated*' }).Count
    $failedCount  = ($summaryReport | Where-Object { $_.Result -like 'Failed*' }).Count
    $skippedCount = ($summaryReport | Where-Object { $_.Result -eq 'Skipped' }).Count

    $summaryReport | Format-Table -Property @{Label="Package"; Expression={$_.Name}}, @{Label="Package ID"; Expression={$_.Id}}, @{Label="Versions"; Expression={"$($_.InstalledVersion) -> $($_.AvailableVersion)"}}, Result -AutoSize

    Write-Host "Summary: $successCount installed/simulated, $skippedCount skipped, $failedCount failed.`n" -ForegroundColor White

    Write-Host "Press Enter to exit..." -ForegroundColor Gray
    Read-Host | Out-Null
} finally {
    Release-SingleInstanceMutex
}
