# tests/TestHelpers.ps1
# Snapshot/restore of real per-user state (preferences file and Startup shortcut) that some
# end-to-end tests have to touch, so running the suite never alters the developer's own setup.

function Get-WgiUserStatePaths {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = Join-Path $HOME "AppData\Local" }
    $startupFolder = [Environment]::GetFolderPath('Startup')
    return @(
        (Join-Path (Join-Path $localAppData "winget-interactive") "preferences.json"),
        (Join-Path $startupFolder "Winget Interactive.lnk")
    )
}

function Backup-WgiUserState {
    $backupDir = Join-Path $env:TEMP "wgi_test_state_$PID"
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
    $entries = @()
    $index = 0
    foreach ($path in (Get-WgiUserStatePaths)) {
        $backupFile = Join-Path $backupDir "state_$index.bak"
        $existed = Test-Path $path
        if ($existed) { Copy-Item -Path $path -Destination $backupFile -Force }
        $entries += [PSCustomObject]@{ Path = $path; Backup = $backupFile; Existed = $existed }
        $index++
    }
    return [PSCustomObject]@{ Directory = $backupDir; Entries = $entries }
}

function Restore-WgiUserState {
    param(
        [Parameter(Mandatory = $true)]
        $State
    )
    foreach ($entry in $State.Entries) {
        if ($entry.Existed) {
            Copy-Item -Path $entry.Backup -Destination $entry.Path -Force
        } elseif (Test-Path $entry.Path) {
            Remove-Item -Path $entry.Path -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -Path $State.Directory -Recurse -Force -ErrorAction SilentlyContinue
}
