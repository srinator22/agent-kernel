# check.ps1 - Windows-native entry point to the canonical gauntlet.
# The gauntlet is scripts/check.sh and CI runs that exact script; this
# wrapper only locates Git Bash and forwards to it, so PowerShell and cmd
# sessions run the same single source of truth instead of a second one.
# Usage: ./scripts/check.ps1 [--full-mutation]
$ErrorActionPreference = "Stop"

$candidates = @()
$onPath = Get-Command bash -ErrorAction SilentlyContinue
if ($onPath) { $candidates += $onPath.Source }
$candidates += "$env:ProgramFiles\Git\bin\bash.exe"
$candidates += "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
$candidates += "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"

$bash = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { $bash = $c; break }
}
if (-not $bash) {
    [Console]::Error.WriteLine("check.ps1: Git Bash not found (PATH, Program Files, LocalAppData).")
    [Console]::Error.WriteLine("Install Git for Windows; scripts/check.sh is the canonical gauntlet and needs bash.")
    exit 1
}

$checkSh = Join-Path $PSScriptRoot "check.sh"
& $bash $checkSh @args
exit $LASTEXITCODE
