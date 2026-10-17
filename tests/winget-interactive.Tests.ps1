# tests/winget-interactive.Tests.ps1
# Pester test suite for winget-interactive core functions

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $here
$scriptPath = Join-Path $projectRoot "winget-interactive.ps1"

# Dot-source the script with -NoExecute to import functions without running the main loop
. $scriptPath -NoExecute
. (Join-Path $here "TestHelpers.ps1")

Describe "Single-Instance Mutex Enforcement" {
    $testMutexName = "Local\WingetInteractive_TestMutex_$PID"

    It "Acquires mutex successfully when not held by any other process" {
        $acquired = Test-AcquireSingleInstanceMutex -MutexName $testMutexName
        $acquired | Should Be $true
        Release-SingleInstanceMutex -MutexName $testMutexName
    }

    It "Fails to acquire mutex and detects collision when already held" {
        $first = Test-AcquireSingleInstanceMutex -MutexName $testMutexName
        $first | Should Be $true

        # Attempt to acquire the same mutex again in another mutex object
        $second = Test-AcquireSingleInstanceMutex -MutexName $testMutexName -CheckOnly
        $second | Should Be $false

        Release-SingleInstanceMutex -MutexName $testMutexName
    }

    It "Re-acquires mutex successfully after being released" {
        $first = Test-AcquireSingleInstanceMutex -MutexName $testMutexName
        $first | Should Be $true
        Release-SingleInstanceMutex -MutexName $testMutexName

        $second = Test-AcquireSingleInstanceMutex -MutexName $testMutexName
        $second | Should Be $true
        Release-SingleInstanceMutex -MutexName $testMutexName
    }
}

Describe "Windows Startup Shortcut Management" {
    $tempDir = Join-Path $env:TEMP "wgi_test_startup_$PID"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
    $testShortcutPath = Join-Path $tempDir "Winget Interactive.lnk"
    $dummyTarget = Join-Path $tempDir "dummy.cmd"
    Set-Content -Path $dummyTarget -Value "@echo off"

    It "Returns accurate shortcut path ending in Winget Interactive.lnk" {
        $path = Get-StartupShortcutPath
        $path | Should Match "Winget Interactive\.lnk$"
    }

    It "Detects when startup shortcut does not exist" {
        if (Test-Path $testShortcutPath) { Remove-Item $testShortcutPath -Force }
        $enabled = Test-IsStartupEnabled -ShortcutPath $testShortcutPath
        $enabled | Should Be $false
    }

    It "Creates startup shortcut when enabled" {
        Set-StartupShortcut -Enable $true -TargetPath $dummyTarget -ShortcutPath $testShortcutPath
        (Test-Path $testShortcutPath) | Should Be $true
        $enabled = Test-IsStartupEnabled -ShortcutPath $testShortcutPath
        $enabled | Should Be $true
    }

    It "Removes startup shortcut when disabled" {
        Set-StartupShortcut -Enable $false -ShortcutPath $testShortcutPath
        (Test-Path $testShortcutPath) | Should Be $false
        $enabled = Test-IsStartupEnabled -ShortcutPath $testShortcutPath
        $enabled | Should Be $false
    }

    # Cleanup temp directory
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Preferences Persistence and Migration Fields" {
    $tempDir = Join-Path $env:TEMP "wgi_test_prefs_$PID"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
    $testConfigFile = Join-Path $tempDir "preferences.json"

    It "Reads default preferences when file does not exist" {
        if (Test-Path $testConfigFile) { Remove-Item $testConfigFile -Force }
        $prefs = Get-Preferences -CustomConfigFile $testConfigFile
        $prefs.CheckForUpdates | Should Be $true
        $prefs.StartupConfigured | Should Be $false
    }

    It "Saves and reads preferences with StartupConfigured and CheckForUpdates" {
        $prefs = Get-Preferences -CustomConfigFile $testConfigFile
        $prefs.StartupConfigured = $true
        $prefs.CheckForUpdates = $false
        Save-Preferences -CustomConfigFile $testConfigFile -Prefs $prefs

        $loaded = Get-Preferences -CustomConfigFile $testConfigFile
        $loaded.StartupConfigured | Should Be $true
        $loaded.CheckForUpdates | Should Be $false
    }

    # Cleanup
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Existing User Onboarding Migration" {
    $tempDir = Join-Path $env:TEMP "wgi_test_migration_$PID"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
    $testShortcutPath = Join-Path $tempDir "Winget Interactive.lnk"
    $dummyTarget = Join-Path $tempDir "dummy.cmd"
    Set-Content -Path $dummyTarget -Value "@echo off"

    It "Does not run migration if StartupConfigured is already true" {
        $prefs = [PSCustomObject]@{
            AlwaysYes         = [System.Collections.Generic.List[string]]@()
            AlwaysSkip        = [System.Collections.Generic.List[string]]@()
            CheckForUpdates   = $true
            LastUpdateCheck   = ""
            StartupConfigured = $true
        }

        $migrated = Invoke-FirstRunMigration -Prefs $prefs -IsInteractive $false -ShortcutPath $testShortcutPath
        $migrated | Should Be $false
    }

    It "Runs migration and removes legacy startup shortcut when user declines keeping it" {
        # Create legacy shortcut
        Set-StartupShortcut -Enable $true -TargetPath $dummyTarget -ShortcutPath $testShortcutPath

        $prefs = [PSCustomObject]@{
            AlwaysYes         = [System.Collections.Generic.List[string]]@()
            AlwaysSkip        = [System.Collections.Generic.List[string]]@()
            CheckForUpdates   = $true
            LastUpdateCheck   = ""
            StartupConfigured = $false
        }

        # Mock interactive answers: keepStartup = 'n', checkForUpdates = 'y'
        $migrated = Invoke-FirstRunMigration -Prefs $prefs `
            -IsInteractive $true `
            -ShortcutPath $testShortcutPath `
            -StartupPromptResponse "n" `
            -UpdatePromptResponse "y"

        $migrated | Should Be $true
        $prefs.StartupConfigured | Should Be $true
        $prefs.CheckForUpdates | Should Be $true
        (Test-Path $testShortcutPath) | Should Be $false
    }

    It "Runs migration and preserves startup shortcut when user agrees to keep it" {
        Set-StartupShortcut -Enable $true -TargetPath $dummyTarget -ShortcutPath $testShortcutPath

        $prefs = [PSCustomObject]@{
            AlwaysYes         = [System.Collections.Generic.List[string]]@()
            AlwaysSkip        = [System.Collections.Generic.List[string]]@()
            CheckForUpdates   = $true
            LastUpdateCheck   = ""
            StartupConfigured = $false
        }

        $migrated = Invoke-FirstRunMigration -Prefs $prefs `
            -IsInteractive $true `
            -ShortcutPath $testShortcutPath `
            -StartupPromptResponse "y" `
            -UpdatePromptResponse "y"

        $migrated | Should Be $true
        $prefs.StartupConfigured | Should Be $true
        (Test-Path $testShortcutPath) | Should Be $true
    }

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "CLI Startup and Update Check Command Switches" {
    # These run the real script against the real Startup folder and preferences; snapshot them first
    $userState = Backup-WgiUserState

    try {
        It "Enables startup shortcut via -EnableStartup" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -EnableStartup
            $shortcut = Get-StartupShortcutPath
            (Test-Path $shortcut) | Should Be $true
        }

        It "Disables startup shortcut via -DisableStartup" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DisableStartup
            $shortcut = Get-StartupShortcutPath
            (Test-Path $shortcut) | Should Be $false
        }

        It "Disables update check via -DisableUpdateCheck" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DisableUpdateCheck
            $prefs = Get-Preferences
            $prefs.CheckForUpdates | Should Be $false
        }

        It "Enables update check via -EnableUpdateCheck" {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -EnableUpdateCheck
            $prefs = Get-Preferences
            $prefs.CheckForUpdates | Should Be $true
        }
    } finally {
        Restore-WgiUserState -State $userState
    }
}
