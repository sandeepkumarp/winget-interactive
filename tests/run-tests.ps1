# tests/run-tests.ps1
# Test runner for winget-interactive

[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
$testDir = $PSScriptRoot

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "         Running winget-interactive Test Suite          " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# The suite uses Pester 3/4 syntax ('Should Be'); Pester 5 changed discovery and assertion syntax
Import-Module Pester -MaximumVersion 4.99 -ErrorAction Stop

$result = Invoke-Pester -Path $testDir -PassThru
if ($result.FailedCount -gt 0) {
    Write-Host "`n[-] $($result.FailedCount) test(s) FAILED." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n[+] All $($result.PassedCount) test(s) PASSED!" -ForegroundColor Green
    exit 0
}
