<#
.SYNOPSIS
    Installer for winget-interactive.

.DESCRIPTION
    Installs winget-interactive to %LOCALAPPDATA%\Programs\winget-interactive,
    registers the directory in the User PATH environment variable,
    and optionally sets up an auto-start shortcut in Windows Startup (shell:startup).
    Works both locally and as a one-liner web installer via:
    irm https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main/install.ps1 | iex

.PARAMETER InstallPath
    Custom target directory to install winget-interactive.

.PARAMETER Startup
    Enables creating a Windows Startup shortcut on logon.

.PARAMETER NoStartupShortcut
    Disables creating a Windows Startup shortcut (backward compatibility).

.PARAMETER CheckForUpdates
    Enables automatic daily check for new winget-interactive releases (default).

.PARAMETER NoUpdateCheck
    Disables automatic daily check for new winget-interactive releases.

.PARAMETER NoPath
    Skips adding the install directory to the User PATH environment variable.
#>

[CmdletBinding()]
param (
    [string]$InstallPath,
    [switch]$Startup,
    [switch]$NoStartupShortcut,
    [switch]$CheckForUpdates,
    [switch]$NoUpdateCheck,
    [switch]$NoPath
)

$ErrorActionPreference = 'Stop'
$RepoRawBase = "https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main"

# Target installation directory
$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = Join-Path $HOME "AppData\Local"
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallDir = Join-Path $localAppData "Programs\winget-interactive"
} else {
    $InstallDir = $InstallPath
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "         Installing winget-interactive...               " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "[i] Target Directory: $InstallDir" -ForegroundColor Gray

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$filesToInstall = @(
    "winget-interactive.ps1",
    "winget-interactive.cmd",
    "wgi.cmd",
    "version.json"
)

# Determine if we have local source files or need to fetch from web
$sourceDir = $PSScriptRoot
$isLocal = (-not [string]::IsNullOrWhiteSpace($sourceDir)) -and (Test-Path (Join-Path $sourceDir "winget-interactive.ps1"))

if ($isLocal) {
    Write-Host "[i] Installing from local source..." -ForegroundColor Gray
    foreach ($file in $filesToInstall) {
        $src = Join-Path $sourceDir $file
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination (Join-Path $InstallDir $file) -Force
            Write-Host "  -> Installed $file" -ForegroundColor Green
        }
    }
} else {
    Write-Host "[i] Downloading files from GitHub repository..." -ForegroundColor Gray
    foreach ($file in $filesToInstall) {
        $url = "$RepoRawBase/$file"
        $dest = Join-Path $InstallDir $file
        try {
            Invoke-RestMethod -Uri $url -OutFile $dest
            Write-Host "  -> Downloaded $file" -ForegroundColor Green
        } catch {
            Write-Error "Failed to download $file from $($url): $_"
            exit 1
        }
    }
}

# Add to User PATH
if (-not $NoPath) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    # @() keeps a single-entry PATH an array, so '+' appends instead of concatenating strings
    $pathParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathParts -notcontains $InstallDir) {
        Write-Host "[i] Adding $InstallDir to User PATH..." -ForegroundColor Cyan
        $newPath = ($pathParts + $InstallDir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$InstallDir"
        Write-Host "  -> User PATH updated successfully." -ForegroundColor Green
    } else {
        Write-Host "  -> User PATH already contains install directory." -ForegroundColor DarkGray
    }
}

# Determine Interactive Console
$isInteractive = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected)

# Handle Windows Startup Shortcut Preference (Default: Disabled)
$createStartup = $false
if ($Startup) {
    $createStartup = $true
} elseif ($NoStartupShortcut) {
    $createStartup = $false
} elseif ($isInteractive) {
    Write-Host ""
    Write-Host -NoNewline "Do you want winget-interactive to launch automatically on Windows startup? [y/N] (Default: N): " -ForegroundColor White
    $ans = Read-Host
    if ($ans -and $ans.Trim().ToLowerInvariant() -in @('y', 'yes')) {
        $createStartup = $true
    } else {
        $createStartup = $false
    }
} else {
    $createStartup = $false
}

$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupFolder "Winget Interactive.lnk"
$legacyShortcut = Join-Path $startupFolder "Winget Updater.lnk"
if (Test-Path $legacyShortcut) {
    Remove-Item -Path $legacyShortcut -Force -ErrorAction SilentlyContinue
}

if ($createStartup) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $InstallDir "winget-interactive.cmd"
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.Description = "Interactive Windows Package Manager Upgrade Tool"
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        Write-Host "[i] Created Windows Startup shortcut: $shortcutPath" -ForegroundColor Green
    } catch {
        Write-Warning "Could not register startup shortcut: $_"
    }
} else {
    if (Test-Path $shortcutPath) {
        Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[i] Windows Startup shortcut: Disabled." -ForegroundColor Gray
}

# Handle Daily Update Check Preference (Default: Enabled)
$enableUpdateCheck = $true
if ($NoUpdateCheck) {
    $enableUpdateCheck = $false
} elseif ($CheckForUpdates) {
    $enableUpdateCheck = $true
} elseif ($isInteractive) {
    Write-Host -NoNewline "Enable daily automatic check for winget-interactive updates? [Y/n] (Default: Y): " -ForegroundColor White
    $upAns = Read-Host
    if ([string]::IsNullOrWhiteSpace($upAns) -or $upAns.Trim().ToLowerInvariant() -in @('y', 'yes')) {
        $enableUpdateCheck = $true
    } else {
        $enableUpdateCheck = $false
    }
} else {
    $enableUpdateCheck = $true
}

# Save initial preferences
$configDir = Join-Path $localAppData "winget-interactive"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
$configFile = Join-Path $configDir "preferences.json"

$initialPrefs = [PSCustomObject]@{
    AlwaysYes         = @()
    AlwaysSkip        = @()
    CheckForUpdates   = [bool]$enableUpdateCheck
    LastUpdateCheck   = ""
    StartupConfigured = $true
}
if (Test-Path $configFile) {
    try {
        $existing = Get-Content -Path $configFile -Raw -Encoding utf8 | ConvertFrom-Json
        if ($null -ne $existing.AlwaysYes) { $initialPrefs.AlwaysYes = $existing.AlwaysYes }
        if ($null -ne $existing.AlwaysSkip) { $initialPrefs.AlwaysSkip = $existing.AlwaysSkip }
        if ($null -ne $existing.LastUpdateCheck) { $initialPrefs.LastUpdateCheck = $existing.LastUpdateCheck }
    } catch {}
}
$initialPrefs | ConvertTo-Json -Depth 5 | Set-Content -Path $configFile -Encoding utf8
Write-Host "[i] Preferences configured (Daily Updates: $(if ($enableUpdateCheck) { 'Enabled' } else { 'Disabled' }))." -ForegroundColor Gray

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "   winget-interactive has been successfully installed!  " -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "You can now run it from any terminal by typing:"
Write-Host "    winget-interactive" -ForegroundColor Cyan
Write-Host "    wgi" -ForegroundColor Cyan
Write-Host "Options: winget-interactive -h" -ForegroundColor DarkGray
Write-Host ""
