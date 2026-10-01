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
    Displays all saved 'Always Yes' and 'Always Skip' package rules and exits.

.PARAMETER ResetPreferences
    Clears all saved rules in preferences.json and exits.

.PARAMETER RemoveRule
    Removes a specific Package ID from saved preferences and exits.

.PARAMETER AddAlwaysYes
    Manually adds a package ID to the AlwaysYes list and exits.

.PARAMETER AddAlwaysSkip
    Manually adds a package ID to the AlwaysSkip list and exits.

.EXAMPLE
    winget-interactive
    Runs the standard interactive upgrade process with auto-elevation.

.EXAMPLE
    wgi -u
    Updates winget-interactive to the latest version.

.EXAMPLE
    wgi -DryRun
    Previews pending updates and prompts without actually installing software.
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
    [switch]$NoElevate,
    [switch]$Silent,
    [switch]$DryRun,
    [switch]$Portable,
    [switch]$ListPreferences,
    [switch]$ResetPreferences,
    [string]$RemoveRule,
    [string]$AddAlwaysYes,
    [string]$AddAlwaysSkip
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "1.0.0"
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

UPDATE CHECK OPTIONS:
    -EnableUpdateCheck        Enable daily automatic check for winget-interactive updates (default)
    -DisableUpdateCheck       Disable daily automatic check for winget-interactive updates

PREFERENCE MANAGEMENT:
    -ListPreferences          Show current 'Always Yes' and 'Always Skip' package rules
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

# --- Self-Update Handler ---
if ($Update) {
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
    } else {
        Write-Warning "`nSome files could not be updated. Please run the installer again if needed."
    }
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
    
    # Forward parameters if present
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
    
    try {
        Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs
        exit 0
    } catch {
        Write-Warning "Elevation cancelled or failed. Continuing in current user context."
    }
}

# Auto-elevate unless explicitly skipped or running preference checks
if (-not (Test-IsAdmin) -and -not $NoElevate -and -not $ListPreferences -and -not $EnableUpdateCheck -and -not $DisableUpdateCheck) {
    Elevate-Process
}

# --- Preferences Persistence ---
function Get-Preferences {
    if (Test-Path $ConfigFile) {
        try {
            $raw = Get-Content -Path $ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
            $alwaysYes = [System.Collections.Generic.List[string]](@($raw.AlwaysYes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
            $alwaysSkip = [System.Collections.Generic.List[string]](@($raw.AlwaysSkip | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
            $checkUpdates = if ($null -ne $raw.CheckForUpdates) { [bool]$raw.CheckForUpdates } else { $true }
            $lastCheck = if ($null -ne $raw.LastUpdateCheck) { [string]$raw.LastUpdateCheck } else { "" }
            
            return [PSCustomObject]@{
                AlwaysYes       = $alwaysYes
                AlwaysSkip      = $alwaysSkip
                CheckForUpdates = $checkUpdates
                LastUpdateCheck = $lastCheck
            }
        } catch {
            Write-Warning "Failed to parse preferences from $ConfigFile. Initializing default preferences."
        }
    }
    return [PSCustomObject]@{
        AlwaysYes       = [System.Collections.Generic.List[string]]@()
        AlwaysSkip      = [System.Collections.Generic.List[string]]@()
        CheckForUpdates = $true
        LastUpdateCheck = ""
    }
}

function Save-Preferences ($prefs) {
    $data = [PSCustomObject]@{
        AlwaysYes       = @($prefs.AlwaysYes | Select-Object -Unique | Sort-Object)
        AlwaysSkip      = @($prefs.AlwaysSkip | Select-Object -Unique | Sort-Object)
        CheckForUpdates = [bool]$prefs.CheckForUpdates
        LastUpdateCheck = [string]$prefs.LastUpdateCheck
    }
    $json = $data | ConvertTo-Json -Depth 5
    $json | Set-Content -Path $ConfigFile -Encoding utf8
}

function Show-PreferencesSummary ($prefs) {
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "              Saved WinGet Preferences                  " -ForegroundColor Cyan
    Write-Host "Config Path: $ConfigFile" -ForegroundColor DarkGray
    Write-Host "========================================================" -ForegroundColor Cyan
    
    $updateStatus = if ($prefs.CheckForUpdates) { "Enabled" } else { "Disabled" }
    $lastCheckedText = if ([string]::IsNullOrWhiteSpace($prefs.LastUpdateCheck)) { "Never" } else { $prefs.LastUpdateCheck }
    Write-Host "Daily Update Check: $updateStatus (Last Checked: $lastCheckedText)" -ForegroundColor Gray

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

# --- Automatic Daily Update Check ---
function Check-DailyUpdate ($prefs) {
    if (-not $prefs.CheckForUpdates) { return }
    $today = (Get-Date).ToString("yyyy-MM-dd")
    if ($prefs.LastUpdateCheck -eq $today) { return }

    try {
        # Quick non-blocking check with 2s timeout
        $meta = Invoke-RestMethod -Uri "$RepoRawBase/version.json" -TimeoutSec 2 -ErrorAction Stop
        if ($meta.version -and ([version]$meta.version -gt [version]$ScriptVersion)) {
            Write-Host "[i] Update available: winget-interactive v$($meta.version) (current: v$ScriptVersion)" -ForegroundColor Yellow
            Write-Host "    Run 'wgi -u' to update to the latest release.`n" -ForegroundColor DarkGray
        }
        $prefs.LastUpdateCheck = $today
        Save-Preferences $prefs
    } catch {
        # Fail silently if offline or network is unreachable
    }
}

# --- CLI Preference Management Execution ---
$prefs = Get-Preferences

if ($EnableUpdateCheck) {
    $prefs.CheckForUpdates = $true
    Save-Preferences $prefs
    Write-Host "Automatic daily update check has been ENABLED." -ForegroundColor Green
    exit 0
}

if ($DisableUpdateCheck) {
    $prefs.CheckForUpdates = $false
    Save-Preferences $prefs
    Write-Host "Automatic daily update check has been DISABLED." -ForegroundColor Yellow
    exit 0
}

if ($ResetPreferences) {
    $prefs.AlwaysYes.Clear()
    $prefs.AlwaysSkip.Clear()
    Save-Preferences $prefs
    Write-Host "Preferences have been reset successfully." -ForegroundColor Green
    exit 0
}

if ($RemoveRule) {
    $removed = $false
    if ($prefs.AlwaysYes.Remove($RemoveRule)) { $removed = $true }
    if ($prefs.AlwaysSkip.Remove($RemoveRule)) { $removed = $true }
    if ($removed) {
        Save-Preferences $prefs
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
        Save-Preferences $prefs
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
        Save-Preferences $prefs
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

# --- Check For winget-interactive Updates ---
Check-DailyUpdate $prefs

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
                    Save-Preferences $prefs
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
                    Save-Preferences $prefs
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
        # Execute winget directly to preserve native console progress display
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
