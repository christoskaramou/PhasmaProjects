# Drives PRISM Tetris with the engine's PhasmaGameDriver from outside the game (agent play / benchmarks).
# run.ps1 starts (or reuses) the PRISM Player with MCP on -Port; the driver then attaches over MCP.
# PhasmaGameDriver has no project argument: it only needs the Player's MCP URL.
param(
    [Parameter(Mandatory)][ValidateSet('local', 'jev')][string]$Policy,
    [int]$Steps = 20,
    [int]$Seed = 42,
    [int]$Port = 8876,
    [int]$PaceMs = 0,
    [switch]$UseVault,
    [string]$Trace
)
$ErrorActionPreference = 'Stop'

$engineRoot = $env:PHASMA_ENGINE
if (-not $engineRoot) {
    $dir = Get-Item -LiteralPath $PSScriptRoot
    while ($dir) {
        $cand = Join-Path $dir.FullName 'PhasmaEngine'
        if (Test-Path -LiteralPath (Join-Path $cand 'build-game-driver/Release/PhasmaGameDriver.exe')) { $engineRoot = $cand; break }
        $dir = $dir.Parent
    }
}
$driver = if ($engineRoot) { Join-Path $engineRoot 'build-game-driver/Release/PhasmaGameDriver.exe' }
if (-not $driver -or -not (Test-Path -LiteralPath $driver)) {
    throw "Missing PhasmaGameDriver.exe. Run Phasma/GameDriver/build.ps1 in PhasmaEngine (or set PHASMA_ENGINE)."
}

& (Join-Path $PSScriptRoot 'run.ps1') -Port $Port
if (-not $Trace) { $Trace = Join-Path $engineRoot "build-prism-tetris/trace-$Policy-$(Get-Date -Format yyyyMMdd-HHmmss).jsonl" }
$driverArgs = @('--policy', $Policy, '--url', "http://127.0.0.1:$Port/mcp", '--steps', $Steps, '--seed', $Seed,
    '--trace', $Trace, '--pace-ms', $PaceMs)
if ($UseVault) { $driverArgs += @('--key-source', 'vault') }
& $driver @driverArgs
exit $LASTEXITCODE
