<#
.SYNOPSIS
    Uninstaller for winget-interactive.

.DESCRIPTION
    Removes winget-interactive from %LOCALAPPDATA%\Programs\winget-interactive,
    cleans up the User PATH environment variable, and removes the Windows Startup shortcut.
    Optionally removes saved preferences if -PurgePreferences is specified.
#>

[CmdletBinding()]
param (
    [switch]$PurgePreferences,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
if ([string]::IsNullOrWhiteSpace($localAppData)) {
    $localAppData = Join-Path $HOME "AppData\Local"
}
$InstallDir = Join-Path $localAppData "Programs\winget-interactive"
$ConfigDir  = Join-Path $localAppData "winget-interactive"

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "        Uninstalling winget-interactive...              " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Remove Startup Shortcut
$startupFolder = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupFolder "Winget Interactive.lnk"
$legacyShortcut = Join-Path $startupFolder "Winget Updater.lnk"

foreach ($lnk in @($shortcutPath, $legacyShortcut)) {
    if (Test-Path $lnk) {
        Remove-Item -Path $lnk -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Removed Startup shortcut: $lnk" -ForegroundColor Green
    }
}

# 2. Clean User PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($pathParts -contains $InstallDir) {
    $newParts = $pathParts | Where-Object { $_ -ne $InstallDir }
    $newPath = $newParts -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "[+] Removed $InstallDir from User PATH." -ForegroundColor Green
}

# 3. Remove Installed Files
if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Removed installation directory: $InstallDir" -ForegroundColor Green
}

# 4. Handle Preferences Purge
if ($PurgePreferences) {
    if (Test-Path $ConfigDir) {
        Remove-Item -Path $ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Purged saved user preferences directory: $ConfigDir" -ForegroundColor Green
    }
} else {
    if (Test-Path $ConfigDir) {
        Write-Host "[i] Saved preferences kept in $ConfigDir. (Use -PurgePreferences to delete)." -ForegroundColor DarkGray
    }
}

Write-Host "`nwinget-interactive has been successfully uninstalled.`n" -ForegroundColor Green
