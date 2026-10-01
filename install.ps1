<#
.SYNOPSIS
    Installer for winget-interactive.

.DESCRIPTION
    Installs winget-interactive to %LOCALAPPDATA%\Programs\winget-interactive,
    registers the directory in the User PATH environment variable,
    and sets up an auto-start shortcut in Windows Startup (shell:startup).
    Works both locally and as a one-liner web installer via:
    irm https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main/install.ps1 | iex
#>

[CmdletBinding()]
param (
    [string]$InstallPath,
    [switch]$NoStartupShortcut,
    [switch]$NoPath
)

$ErrorActionPreference = 'Stop'
$RepoRawBase = "https://raw.githubusercontent.com/sandeepkumarp/winget-interactive/main"

# Target installation directory
if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = Join-Path $HOME "AppData\Local"
    }
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
    $pathParts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
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

# Create / Update Startup Shortcut
if (-not $NoStartupShortcut) {
    $startupFolder = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startupFolder "Winget Interactive.lnk"
    
    # Remove any legacy old shortcut from previous test if present
    $legacyShortcut = Join-Path $startupFolder "Winget Updater.lnk"
    if (Test-Path $legacyShortcut) {
        Remove-Item -Path $legacyShortcut -Force -ErrorAction SilentlyContinue
    }
    
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $InstallDir "winget-interactive.cmd"
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.Description = "Interactive Windows Package Manager Upgrade Tool"
        $shortcut.Save()
        Write-Host "[i] Created Windows Startup shortcut: $shortcutPath" -ForegroundColor Green
    } catch {
        Write-Warning "Could not register startup shortcut: $_"
    }
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "   winget-interactive has been successfully installed!  " -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "You can now run it from any terminal by typing:"
Write-Host "    winget-interactive" -ForegroundColor Cyan
Write-Host "    wgi" -ForegroundColor Cyan
Write-Host "Options: winget-interactive -h" -ForegroundColor DarkGray
Write-Host ""
