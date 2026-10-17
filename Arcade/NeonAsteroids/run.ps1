# run.ps1 - launch this game in PhasmaPlayer on Windows.
# Uses a private runtime copy under %LOCALAPPDATA%\PhasmaGames\<game> so the shared
# engine build's phasma_settings.json (used by the editor) is never touched.
param([string]$Api = 'vulkan', [int]$Display = 1)
$ErrorActionPreference = 'Stop'
$game = Split-Path $PSScriptRoot -Leaf
# Find the PhasmaEngine checkout: walk up from this folder and use the first sibling 'PhasmaEngine'
# (works for PhasmaProjects\<Game> and PhasmaProjects\Arcade\<Game>). Override with $env:PHASMA_ENGINE.
$engineRoot = $env:PHASMA_ENGINE
if (-not $engineRoot) {
    $dir = Get-Item $PSScriptRoot
    while ($dir) {
        $cand = Join-Path $dir.FullName 'PhasmaEngine'
        if ((Test-Path $cand) -and (Get-ChildItem "$cand\build*\Release\PhasmaPlayer.exe" -EA SilentlyContinue)) { $engineRoot = $cand; break }
        $dir = $dir.Parent
    }
}
if (-not $engineRoot) { throw "PhasmaEngine checkout with a Release PhasmaPlayer.exe build not found above $PSScriptRoot (set PHASMA_ENGINE)" }
$source = Get-ChildItem "$engineRoot\build*\Release\PhasmaPlayer.exe" -EA SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.DirectoryName 'RuntimeAssets') } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $source) { throw "No PhasmaPlayer.exe build found under $engineRoot\build*\Release" }
$src = $source.DirectoryName
$runtime = Join-Path $env:LOCALAPPDATA "PhasmaGames\$game"
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
Copy-Item (Join-Path $src 'PhasmaPlayer.exe') $runtime -Force
Get-ChildItem $src -Filter '*.dll' -File | Where-Object { $_.Name -notmatch '_live_' } | Copy-Item -Destination $runtime -Force
foreach ($f in 'RuntimeAssets','MaterialX') { if (Test-Path (Join-Path $src $f)) { Copy-Item (Join-Path $src $f) $runtime -Recurse -Force } }
@{ project_path = (Join-Path $PSScriptRoot 'Assets'); project_manifest = ''; startup_scene = 'Scenes/main.pescene'; graphics_api = $Api; live_profiler = $false } |
    ConvertTo-Json | Set-Content (Join-Path $runtime 'phasma_settings.json') -Encoding utf8
Start-Process (Join-Path $runtime 'PhasmaPlayer.exe') -ArgumentList '--api', $Api, '--display', $Display -WorkingDirectory $runtime
Write-Host "$game launched from $runtime (player: $src). Log: $runtime\PhasmaEngine.log"
