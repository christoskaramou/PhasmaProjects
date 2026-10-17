param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8876
)

$ErrorActionPreference = 'Stop'

# Find the PhasmaEngine checkout: walk up from this folder and use the first sibling 'PhasmaEngine'
# with a build-ninja-physics Release Player (works from PhasmaProjects\Arcade\PrismTetris).
# Override with $env:PHASMA_ENGINE.
$engineRoot = $env:PHASMA_ENGINE
if (-not $engineRoot) {
    $dir = Get-Item -LiteralPath $PSScriptRoot
    while ($dir) {
        $cand = Join-Path $dir.FullName 'PhasmaEngine'
        if (Test-Path -LiteralPath (Join-Path $cand 'build-ninja-physics/Release/PhasmaPlayer.exe')) { $engineRoot = $cand; break }
        $dir = $dir.Parent
    }
}
if (-not $engineRoot -or -not (Test-Path -LiteralPath $engineRoot)) {
    throw "Missing PhasmaEngine checkout with build-ninja-physics/Release above $PSScriptRoot (set PHASMA_ENGINE)"
}

$source = Join-Path $engineRoot 'build-ninja-physics/Release'
$runtime = Join-Path $engineRoot 'build-prism-tetris/player'
$assets = Join-Path $runtime 'Assets'
$player = Join-Path $runtime 'PhasmaPlayer.exe'
$driver = Join-Path $engineRoot 'build-game-driver/Release/PhasmaGameDriver.exe'
$instancePath = Join-Path $runtime 'instance.json'

foreach ($required in @('PhasmaPlayer.exe', 'PhasmaCore.dll', 'RuntimeAssets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $required))) {
        throw "Missing Player build file: $source/$required"
    }
}

# One PRISM Player per runtime folder: reuse it while it runs on the requested port.
if (Test-Path -LiteralPath $instancePath) {
    $previous = Get-Content -LiteralPath $instancePath -Raw | ConvertFrom-Json
    $running = Get-Process -Id $previous.pid -ErrorAction SilentlyContinue
    if ($running -and $running.Path -eq $player) {
        if ($previous.port -ne $Port) {
            throw "PRISM is already running on port $($previous.port). Close it before changing ports."
        }

        Write-Host "PRISM is already running (PID $($running.Id), MCP port $Port)."
        exit 0
    }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
} catch {
    throw "Port $Port is occupied. Choose a different -Port."
} finally {
    $listener.Stop()
}

New-Item -ItemType Directory -Path $assets -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $source 'PhasmaPlayer.exe') -Destination $runtime -Force
Get-ChildItem -LiteralPath $source -Filter '*.dll' -File |
    Where-Object { $_.Name -notmatch '_live_' } |
    Copy-Item -Destination $runtime -Force
foreach ($folder in @('RuntimeAssets', 'MaterialX')) {
    $sourceFolder = Join-Path $source $folder
    if (Test-Path -LiteralPath $sourceFolder) {
        Copy-Item -LiteralPath $sourceFolder -Destination $runtime -Recurse -Force
    }
}

# Game files are replaced on every launch; Save/ (best score) stays between launches.
foreach ($folder in @('Audio', 'Scenes', 'Scripts', 'Textures')) {
    $target = Join-Path $assets $folder
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }

    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Assets/$folder") -Destination $assets -Recurse
}

# Races start the driver from inside the game, which may only run programs under its Assets folder (proc.start
# refuses anything else). Copy it into the runtime copy and into this source folder's Assets/Bots (gitignored),
# so the game also finds it when opened in place from PhasmaLauncher or the editor.
if (Test-Path -LiteralPath $driver) {
    foreach ($bots in @((Join-Path $assets 'Bots'), (Join-Path $PSScriptRoot 'Assets/Bots'))) {
        New-Item -ItemType Directory -Path $bots -Force | Out-Null
        # A driver still running from an in-place session holds its copy; keep that one rather than fail.
        try { Copy-Item -LiteralPath $driver -Destination $bots -Force } catch { Write-Warning "Could not refresh $bots/PhasmaGameDriver.exe: $_" }
    }
} else {
    Write-Warning "Missing $driver. Run Phasma/GameDriver/build.ps1 in $engineRoot to race Jev."
}

# Opening PRISM in place (PhasmaLauncher points the Player at this folder) reads this folder's own
# Assets/Agent/agent_config.json, so enable the same MCP port there; other keys the editor keeps are preserved.
$sourceAgent = Join-Path $PSScriptRoot 'Assets/Agent'
$sourceConfig = Join-Path $sourceAgent 'agent_config.json'
try {
    $config = if (Test-Path -LiteralPath $sourceConfig) {
        Get-Content -LiteralPath $sourceConfig -Raw | ConvertFrom-Json
    } else { [pscustomobject]@{} }
    if ($config.mcp -ne $true -or $config.mcp_port -ne $Port) {
        $config | Add-Member -NotePropertyName mcp -NotePropertyValue $true -Force
        $config | Add-Member -NotePropertyName mcp_port -NotePropertyValue $Port -Force
        New-Item -ItemType Directory -Path $sourceAgent -Force | Out-Null
        $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $sourceConfig -Encoding utf8
    }
} catch {
    Write-Warning "Could not enable MCP in $sourceConfig (in-place races need it): $_"
}
$agent = Join-Path $assets 'Agent'
New-Item -ItemType Directory -Path $agent -Force | Out-Null
@{ mcp = $true; mcp_port = $Port } | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $agent 'agent_config.json') -Encoding utf8
@{
    project_path = $assets
    project_manifest = ''
    startup_scene = 'Scenes/prism_tetris.pescene'
    graphics_api = 'vulkan'
    live_profiler = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtime 'phasma_settings.json') -Encoding utf8

# The Player never needs a model key: the race driver reads the saved key itself.
$keys = @{}
foreach ($name in @('JEV_API_KEY', 'TYPESAFE_API_KEY')) {
    $keys[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    foreach ($name in $keys.Keys) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    $process = Start-Process -FilePath $player -ArgumentList '--api', 'vulkan', '--display', '1' `
        -WorkingDirectory $runtime -PassThru
} finally {
    foreach ($name in $keys.Keys) {
        [Environment]::SetEnvironmentVariable($name, $keys[$name], 'Process')
    }
    $keys.Clear()
}
@{ pid = $process.Id; executable = $player; port = $Port } | ConvertTo-Json |
    Set-Content -LiteralPath $instancePath -Encoding utf8

$deadline = [DateTime]::UtcNow.AddSeconds(90)
while ([DateTime]::UtcNow -lt $deadline) {
    $process.Refresh()
    if ($process.HasExited) {
        throw "PRISM exited ($($process.ExitCode)). See $runtime/PhasmaEngine.log"
    }

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.Connect([Net.IPAddress]::Loopback, $Port)
        Write-Host "PRISM is running (PID $($process.Id), MCP port $Port). Enter plays solo; V races Jev."
        exit 0
    } catch {
        Start-Sleep -Milliseconds 250
    } finally {
        $client.Dispose()
    }
}

throw "PRISM started, but its MCP port $Port did not open within 90 seconds. See $runtime/PhasmaEngine.log"
