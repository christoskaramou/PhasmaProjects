# run_smoke.ps1 — launch Chess in PhasmaPlayer and assert it loads cleanly.
#
# Writes phasma_settings.json next to the player exe (that is where ResolveProjectSelection
# looks), force-exits any stale player, launches, waits, then checks the engine log.
#
# The player exe is picked as the NEWEST of the build trees rather than hard-coded: a stale
# player access-violates while loading any scene, which reads as "the game is broken".
$ErrorActionPreference = "Stop"

$project = "C:\Users\Christos\repos\PhasmaProjects\Chess"
$startup = "Assets/Scenes/chess.pescene"
$api     = "vulkan"

$candidates = @(
    "C:\Users\Christos\repos\PhasmaEngine\build-ninja-physics\Release\PhasmaPlayer.exe",
    "C:\Users\Christos\repos\PhasmaEngine\build-ninja-full\Release\PhasmaPlayer.exe",
    "C:\Users\Christos\repos\PhasmaEngine\build-ninja\Release\PhasmaPlayer.exe"
) | Where-Object { Test-Path $_ } | Sort-Object { (Get-Item $_).LastWriteTime } -Descending

if (-not $candidates) { Write-Host "SMOKE FAIL: no PhasmaPlayer.exe found"; exit 3 }
$exe = $candidates[0]
$exeDir = Split-Path $exe
$settings = Join-Path $exeDir "phasma_settings.json"
$log = Join-Path $exeDir "PhasmaEngine.log"

@{ project_path = $project; startup_scene = $startup } | ConvertTo-Json | Set-Content -Encoding UTF8 $settings

Get-Process PhasmaPlayer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
if (Test-Path $log) { Remove-Item -Force $log -ErrorAction SilentlyContinue }

Write-Host "Launching $exe --api $api ..."
# display 1 keeps the window on the same screen as every other test run here.
$proc = Start-Process $exe -ArgumentList '--api', $api, '--display', '1' -WorkingDirectory $exeDir -PassThru
Start-Sleep -Seconds 18

$alive = -not $proc.HasExited
if (-not $alive) { Write-Host ("SMOKE: player EXITED early code=0x{0:X8}" -f $proc.ExitCode) }
else { Write-Host "SMOKE: player ALIVE after 18s (pid=$($proc.Id))" }

$logText = ""
if (Test-Path $log) { $logText = Get-Content $log -Raw }

$sceneLoaded = $logText -match "Scene loaded from:"
$chessReady  = $logText -match "\[chess\] ready"
$luaErr      = ($logText -split "`n" | Where-Object { $_ -match "\[Lua\].*error" })

Write-Host "scene loaded: $sceneLoaded"
Write-Host "chess ready:  $chessReady"
if ($luaErr) { Write-Host "LUA ERRORS:"; $luaErr | ForEach-Object { Write-Host "  $_" } }

Write-Host "----- tail of PhasmaEngine.log -----"
if ($logText) { ($logText -split "`n" | Select-Object -Last 20) | ForEach-Object { Write-Host $_ } }

# Left running so you can play it; pass -Stop to kill it instead.
if ($args -contains '-Stop' -and $alive) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }

if ($alive -and $sceneLoaded -and $chessReady -and -not $luaErr) { Write-Host "SMOKE PASS"; exit 0 }
Write-Host "SMOKE FAIL"; exit 1
