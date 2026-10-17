# tests/install.Tests.ps1
# Pester test suite for install.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $here
$installScript = Join-Path $projectRoot "install.ps1"
. (Join-Path $here "TestHelpers.ps1")

Describe "Installer Configuration and Switches" {
    $tempInstallDir = Join-Path $env:TEMP "wgi_test_install_$PID"
    if (-not (Test-Path $tempInstallDir)) { New-Item -ItemType Directory -Path $tempInstallDir | Out-Null }

    $configFile = (Get-WgiUserStatePaths)[0]

    # The installer writes the real preferences file and Startup shortcut; snapshot them first
    $userState = Backup-WgiUserState

    try {
        It "Installs cleanly with -NoStartupShortcut and -NoUpdateCheck" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript `
                -InstallPath $tempInstallDir `
                -NoStartupShortcut `
                -NoUpdateCheck `
                -NoPath

            # Verify files installed
            (Test-Path (Join-Path $tempInstallDir "winget-interactive.ps1")) | Should Be $true
            (Test-Path (Join-Path $tempInstallDir "wgi.cmd")) | Should Be $true

            # Verify preferences created with CheckForUpdates = false
            (Test-Path $configFile) | Should Be $true
            $prefs = Get-Content $configFile -Raw | ConvertFrom-Json
            $prefs.CheckForUpdates | Should Be $false
            $prefs.StartupConfigured | Should Be $true
        }

        It "Configures CheckForUpdates = true when -CheckForUpdates is passed" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript `
                -InstallPath $tempInstallDir `
                -NoStartupShortcut `
                -CheckForUpdates `
                -NoPath

            $prefs = Get-Content $configFile -Raw | ConvertFrom-Json
            $prefs.CheckForUpdates | Should Be $true
        }

        It "Creates startup shortcut when -Startup switch is provided" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $installScript `
                -InstallPath $tempInstallDir `
                -Startup `
                -NoPath

            $startupFolder = [Environment]::GetFolderPath('Startup')
            $shortcut = Join-Path $startupFolder "Winget Interactive.lnk"
            (Test-Path $shortcut) | Should Be $true
        }
    } finally {
        Restore-WgiUserState -State $userState
        Remove-Item -Path $tempInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
