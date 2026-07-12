# run_smoke.ps1 — launch AgainstTheHero in PhasmaPlayer and assert it loads cleanly.
# Modeled on Ylem/run_smoke.ps1: writes phasma_settings.json next to the newest
# player exe, launches the scene-driven game (game.pescene boots the arena),
# waits, then checks the engine log for Lua errors and arena progress lines.
#
#   .\run_smoke.ps1                 # wave 1, auto-draft, killed after 30s
#   .\run_smoke.ps1 -Wave 5 -Seconds 60   # jump to wave 5 (boss coverage)
#   .\run_smoke.ps1 -HeroClass brawler   # exercise the melee class
param(
    [int]$Wave = 1,
    [int]$Map = 0,
    [int]$Seconds = 30,
    [ValidateSet("ranger", "brawler", "sower", "mage", "rogue")]
    [string]$HeroClass = "ranger",
    [ValidateSet("", "fire", "ice", "earth", "air", "poison", "hemorrhage", "shadow", "execute")]
    [string]$HeroSpec = "",
    [ValidateSet("", "mid", "top")]
    [string]$GearSet = "",
    [switch]$KeepAlive
)
$ErrorActionPreference = "Stop"

$project = "C:\Users\Christos\repos\PhasmaProjects\AgainstTheHero"
$api     = "dx12"
$startup = "Assets/Scenes/game.pescene"

# Pick the newest PhasmaPlayer across build trees — a stale player
# 0xC0000005-crashes loading any current scene.
$engine = "c:\Users\Christos\repos\PhasmaEngine"
$exe = Get-ChildItem "$engine\build*\Release\PhasmaPlayer.exe" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $exe) { Write-Host "SMOKE FAIL: no PhasmaPlayer.exe found under $engine\build*\Release"; exit 3 }
$exeDir = Split-Path $exe
$settings = Join-Path $exeDir "phasma_settings.json"
$log = Join-Path $exeDir "PhasmaEngine.log"

@{ project_path = $project; startup_scene = $startup } | ConvertTo-Json | Set-Content -Encoding UTF8 $settings

# Headless knobs: auto-pick the first draft boon, optionally start at a later
# wave / on a specific map / with a fixed balance loadout.
$env:ATH_DUEL_AUTOPLAY = "1"
$env:ATH_DUEL_WAVE = "$Wave"
$env:ATH_HERO_CLASS = $HeroClass
if ($HeroSpec) { $env:ATH_HERO_SPEC = $HeroSpec } else { Remove-Item Env:ATH_HERO_SPEC -ErrorAction SilentlyContinue }
if ($Map -gt 0) { $env:ATH_DUEL_MAP = "$Map" } else { Remove-Item Env:ATH_DUEL_MAP -ErrorAction SilentlyContinue }
if ($GearSet) { $env:ATH_DUEL_GEARSET = $GearSet } else { Remove-Item Env:ATH_DUEL_GEARSET -ErrorAction SilentlyContinue }

Get-Process PhasmaPlayer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
if (Test-Path $log) { Remove-Item -Force $log -ErrorAction SilentlyContinue }

Write-Host "Launching $exe --api $api ($HeroClass, wave $Wave, ${Seconds}s) ..."
$proc = Start-Process $exe -ArgumentList '--api', $api, '--display', '1' -WorkingDirectory $exeDir -PassThru
Start-Sleep -Seconds $Seconds

$alive = -not $proc.HasExited
if (-not $alive) { Write-Host ("SMOKE: player EXITED early code=0x{0:X8}" -f $proc.ExitCode) }
else { Write-Host "SMOKE: player ALIVE after ${Seconds}s (pid=$($proc.Id))" }

$logText = ""
if (Test-Path $log) { $logText = Get-Content $log -Raw }

$sceneLoaded = $logText -match "Scene loaded from:"
$booted      = $logText -match "\[ATH\] game boot"
$waveStart   = $logText -match "wave start wave="
$draftPick   = $logText -match "draft pick wave="
$bossLine    = $logText -match "boss telegraphed"
$luaErr      = ($logText -split "`n" | Where-Object { $_ -match "(?i)\[lua\].*error|script error|PE_ERROR|\[error\]" })

Write-Host "scene loaded:  $sceneLoaded"
Write-Host "game booted:   $booted"
Write-Host "wave started:  $waveStart"
Write-Host "draft picked:  $draftPick"
Write-Host "boss reached:  $bossLine"
if ($luaErr) { Write-Host "LUA/SCRIPT ERRORS:"; $luaErr | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" } }

Write-Host "----- ATH lines -----"
($logText -split "`n" | Where-Object { $_ -match "\[ATH" } | Select-Object -Last 20) | ForEach-Object { Write-Host $_ }
Write-Host "----- tail of PhasmaEngine.log -----"
if ($logText) { ($logText -split "`n" | Select-Object -Last 12) | ForEach-Object { Write-Host $_ } }

if (-not $KeepAlive -and $alive) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }

if ($alive -and $sceneLoaded -and $booted -and $waveStart -and -not $luaErr) { Write-Host "SMOKE PASS"; exit 0 }
Write-Host "SMOKE FAIL"; exit 1
