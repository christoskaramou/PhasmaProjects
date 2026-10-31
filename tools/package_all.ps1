<#
.SYNOPSIS
    Exports every Phasma game in this repo as a standalone Windows build and
    bundles them into one zip: <Out>\PhasmaGames-<Version>.zip

.DESCRIPTION
    Used by .github/workflows/build-games.yml and runnable locally.

    For each game (any git-tracked phasma_project.json, outside dot-folders):
      1. PhasmaExport --project <dir> --output <bundle>\<Game> --force
      2. PhasmaPlayer.exe -> <Game>.exe
      3. phasma_settings.json: graphics_api / live_profiler=false
      4. Copy the MSVC C++ runtime DLLs next to the exe
      5. Check that the required files are there
    One game failing does not stop the others. The exit code is 1 if any game
    failed (the zip still contains the games that worked).

    The output layout:
      <Out>\PhasmaGames-<Version>\README.txt
      <Out>\PhasmaGames-<Version>\<Game>\<Game>.exe ...
      <Out>\PhasmaGames-<Version>.zip
      <Out>\logs\<Game>.log
      <Out>\summary.json

.PARAMETER Engine
    Engine root (C:\...\PhasmaEngine) or the build output folder that holds
    PhasmaExport.exe (C:\...\PhasmaEngine\build\Release). Defaults to
    $env:PHASMA_ENGINE, then a PhasmaEngine checkout next to this repo.

.PARAMETER Out
    Output folder. Default: <repo>\dist (gitignored).

.PARAMETER Version
    Version label used in the bundle/zip name. Default: yyyyMMdd-<short sha>.

.PARAMETER Games
    Only export these games (folder names, wildcards allowed).

.PARAMETER Exclude
    Skip these games (folder names, wildcards allowed).

.PARAMETER GraphicsApi
    Value written to phasma_settings.json "graphics_api". Default: vulkan.

.PARAMETER NoZip
    Stage the folders but do not create the zip.

.EXAMPLE
    pwsh tools/package_all.ps1 -Engine ..\PhasmaEngine\build-ninja-physics\Release
#>
[CmdletBinding()]
param(
    [string]$Engine = $env:PHASMA_ENGINE,
    [string]$Out,
    [string]$Version,
    [string[]]$Games,
    [string[]]$Exclude,
    [ValidateSet('vulkan', 'dx12')]
    [string]$GraphicsApi = 'vulkan',
    [switch]$NoZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Out) { $Out = Join-Path $RepoRoot 'dist' }
$Out = [IO.Path]::GetFullPath($Out)

# GitHub release assets must be smaller than 2 GiB.
$ReleaseAssetLimit = 2GB

# DLLs PhasmaCore/PhasmaPlayer need from the MSVC redistributable.
$CrtDlls = @(
    'msvcp140.dll',
    'msvcp140_1.dll',
    'msvcp140_2.dll',
    'msvcp140_atomic_wait.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll'
)
# msvcp140_2 is optional (nothing imports it today); the rest are required.
$OptionalCrtDlls = @('msvcp140_2.dll')

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    return '{0:N1} MB' -f ($Bytes / 1MB)
}

function Get-DirSize([string]$Path) {
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [long]0 }
    return [long]$sum
}

function Resolve-Exporter([string]$EnginePath) {
    $candidates = @()
    if ($EnginePath) {
        $EnginePath = [IO.Path]::GetFullPath($EnginePath)
        $candidates += Join-Path $EnginePath 'PhasmaExport.exe'
        foreach ($b in @('build-ninja-physics', 'build', 'build-ninja')) {
            $candidates += Join-Path $EnginePath "$b\Release\PhasmaExport.exe"
        }
        $candidates += @(Get-ChildItem -LiteralPath $EnginePath -Directory -Filter 'build*' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'Release\PhasmaExport.exe' })
    } else {
        $sibling = Join-Path (Split-Path $RepoRoot -Parent) 'PhasmaEngine'
        if (Test-Path -LiteralPath $sibling) { return Resolve-Exporter $sibling }
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
    }
    throw "PhasmaExport.exe not found. Pass -Engine <engine root or build\Release folder> or set PHASMA_ENGINE."
}

function ConvertTo-ExeName([string]$Name) {
    # "Banners Borders" / "banners-borders" / "BannersBorders" -> "BannersBorders"
    $parts = [regex]::Split($Name, '[^A-Za-z0-9]+') | Where-Object { $_ }
    $title = ($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
    if (-not $title) { throw "Cannot derive an exe name from '$Name'." }
    return $title
}

function Split-Camel([string]$Name) {
    # "NeonCombat" -> "Neon Combat", "1942Remix" -> "1942 Remix"
    $s = [regex]::Replace($Name, '(?<=[a-z])(?=[A-Z0-9])|(?<=[0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])', ' ')
    return $s.Trim()
}

function Find-Games {
    # Prefer git-tracked manifests so untracked export output (ChessExport\...)
    # and local scratch folders are never picked up. Fall back to a filesystem
    # scan when this is not a git checkout.
    $manifests = @()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
        $manifests = @(& git -C $RepoRoot ls-files -- '*phasma_project.json' 'phasma_project.json')
        if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    } else {
        $manifests = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter 'phasma_project.json' |
            ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1) })
    }

    $found = @()
    foreach ($rel in $manifests) {
        $rel = $rel -replace '\\', '/'
        $segments = $rel.Split('/')
        if ($segments.Count -lt 2) { continue }                      # manifest at repo root
        if ($segments | Where-Object { $_.StartsWith('.') }) { continue }  # .testpool, .superpowers, ...
        if ($segments[0] -in @('dist', 'tools', 'docs')) { continue }
        if ($segments[0] -like '*Export') { continue }               # ChessExport etc.

        $projectDir = Join-Path $RepoRoot (($segments[0..($segments.Count - 2)]) -join '\')
        # Layout <Game>\project\phasma_project.json -> name comes from <Game>.
        $folder = $segments[$segments.Count - 2]
        if ($folder -ieq 'project' -and $segments.Count -ge 3) { $folder = $segments[$segments.Count - 3] }

        $manifest = Get-Content -LiteralPath (Join-Path $projectDir 'phasma_project.json') -Raw | ConvertFrom-Json
        $display = if ($manifest.PSObject.Properties['name'] -and $manifest.name) { [string]$manifest.name } else { $folder }

        $found += [pscustomobject]@{
            Name       = ConvertTo-ExeName $folder
            Display    = Split-Camel $display
            Group      = if ($segments.Count -ge 3 -and $segments[0] -ne $folder) { $segments[0] } else { '' }
            ProjectDir = $projectDir
            Relative   = ($segments[0..($segments.Count - 2)]) -join '/'
        }
    }

    $dupes = $found | Group-Object Name | Where-Object Count -gt 1
    if ($dupes) { throw "Two games map to the same exe name: $(($dupes | ForEach-Object Name) -join ', ')" }
    return @($found | Sort-Object Group, Name)
}

function Find-CrtFolder {
    # 1. VCToolsRedistDir (set by vcvars / ilammy/msvc-dev-cmd)
    # 2. vswhere -> VC\Redist\MSVC\<newest>\x64\Microsoft.VC*.CRT
    # 3. System32 (whatever is installed on this machine)
    $roots = @()
    if ($env:VCToolsRedistDir) { $roots += $env:VCToolsRedistDir }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vs) {
            $redist = Join-Path $vs 'VC\Redist\MSVC'
            if (Test-Path -LiteralPath $redist) {
                $roots += @(Get-ChildItem -LiteralPath $redist -Directory |
                    Where-Object { $_.Name -match '^\d+\.\d+' } |
                    Sort-Object { [version]($_.Name -replace '^(\d+\.\d+\.\d+).*', '$1') } -Descending |
                    ForEach-Object FullName)
            }
        }
    }
    foreach ($root in $roots) {
        $crt = Get-ChildItem -LiteralPath (Join-Path $root 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($crt -and (Test-Path -LiteralPath (Join-Path $crt.FullName 'vcruntime140.dll'))) { return $crt.FullName }
    }
    Write-Warning 'MSVC redist folder not found; copying the C++ runtime from System32.'
    return (Join-Path $env:WINDIR 'System32')
}

function Set-ExportSettings([string]$Path) {
    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName graphics_api -NotePropertyValue $GraphicsApi -Force
    $settings | Add-Member -NotePropertyName live_profiler -NotePropertyValue $false -Force
    $json = $settings | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($Path, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function New-Zip([string]$SourceDir, [string]$ZipPath) {
    # Manual entries: forward slashes on every PowerShell/.NET version, and
    # empty files (Assets\anchor.txt) are kept.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    $base = Split-Path $SourceDir -Parent
    $zip = [IO.Compression.ZipFile]::Open($ZipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force) {
            $entry = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $f.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $zip.Dispose()
    }
}

# --------------------------------------------------------------------------

$Exporter = Resolve-Exporter $Engine
$EngineBin = Split-Path $Exporter -Parent
foreach ($need in @('PhasmaPlayer.exe', 'PhasmaCore.dll', 'RuntimeAssets')) {
    if (-not (Test-Path -LiteralPath (Join-Path $EngineBin $need))) {
        throw "$need is missing next to $Exporter (build the PhasmaPlayer target)."
    }
}

if (-not $Version) {
    $sha = (& git -C $RepoRoot rev-parse --short=8 HEAD 2>$null)
    if (-not $sha) { $sha = 'local' }
    $Version = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd'), $sha
}
$Version = $Version -replace '[^A-Za-z0-9._-]', '-'
$BundleName = "PhasmaGames-$Version"
$Bundle = Join-Path $Out $BundleName
$ZipPath = Join-Path $Out "$BundleName.zip"
$LogDir = Join-Path $Out 'logs'

$all = Find-Games
$selected = @($all | Where-Object {
    $n = $_.Name
    $inc = (-not $Games) -or ($Games | Where-Object { $n -like $_ })
    $exc = $Exclude -and ($Exclude | Where-Object { $n -like $_ })
    $inc -and -not $exc
})
if (-not $selected) { throw 'No games selected.' }

$CrtDir = Find-CrtFolder

Write-Step "Exporter : $Exporter"
Write-Step "C++ CRT  : $CrtDir"
Write-Step "Version  : $Version"
Write-Step "Output   : $Bundle"
Write-Step "Games    : $($selected.Count) of $($all.Count)"

if (Test-Path -LiteralPath $Bundle) { Remove-Item -LiteralPath $Bundle -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Bundle, $LogDir | Out-Null

$results = @()
foreach ($g in $selected) {
    $dest = Join-Path $Bundle $g.Name
    $log = Join-Path $LogDir "$($g.Name).log"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $err = $null
    Write-Step "[$($results.Count + 1)/$($selected.Count)] $($g.Relative) -> $($g.Name)"
    try {
        # Native stderr must not turn into terminating errors (Windows PowerShell 5.1).
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $Exporter --project $g.ProjectDir --output $dest --force 2>&1
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prevEap
        }
        $output | ForEach-Object { "$_" } | Set-Content -LiteralPath $log -Encoding utf8
        if ($code -ne 0) {
            $tail = ($output | Select-Object -Last 5 | ForEach-Object { "$_" }) -join ' | '
            throw "PhasmaExport exited with $code. $tail"
        }

        $player = Join-Path $dest 'PhasmaPlayer.exe'
        $exe = Join-Path $dest "$($g.Name).exe"
        if (-not (Test-Path -LiteralPath $player)) { throw 'PhasmaPlayer.exe missing from export.' }
        if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe -Force }
        Rename-Item -LiteralPath $player -NewName "$($g.Name).exe"

        Set-ExportSettings (Join-Path $dest 'phasma_settings.json')

        foreach ($dll in $CrtDlls) {
            $src = Join-Path $CrtDir $dll
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $dest -Force }
            elseif ($dll -notin $OptionalCrtDlls) { throw "C++ runtime DLL not found: $src" }
        }

        $required = @("$($g.Name).exe", 'PhasmaCore.dll', 'game.pepak', 'phasma_project.json',
            'phasma_settings.json', 'Assets\anchor.txt', 'RuntimeAssets\anchor.txt', 'vcruntime140.dll')
        $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dest $_)) })
        if ($missing) { throw "Missing after export: $($missing -join ', ')" }
    } catch {
        $err = $_.Exception.Message
        Write-Host "    FAILED: $err" -ForegroundColor Red
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        Remove-Item -LiteralPath "$dest.exporting" -Recurse -Force -ErrorAction SilentlyContinue
    }
    $sw.Stop()

    $size = if (-not $err -and (Test-Path -LiteralPath $dest)) { Get-DirSize $dest } else { [long]0 }
    $pepak = Join-Path $dest 'game.pepak'
    $pepakSize = if (-not $err -and (Test-Path -LiteralPath $pepak)) { (Get-Item -LiteralPath $pepak).Length } else { [long]0 }
    $results += [pscustomobject]@{
        Game      = $g.Name
        Display   = $g.Display
        Group     = $g.Group
        Source    = $g.Relative
        Ok        = (-not $err)
        Bytes     = $size
        PepakBytes = $pepakSize
        Seconds   = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Error     = $err
    }
    if (-not $err) { Write-Host ("    ok  {0}  (game.pepak {1})  {2}s" -f (Format-Size $size), (Format-Size $pepakSize), $results[-1].Seconds) }
}

$ok = @($results | Where-Object Ok)
$failed = @($results | Where-Object { -not $_.Ok })

# README -------------------------------------------------------------------
$engineRef = if ($env:PHASMA_ENGINE_SHA) { $env:PHASMA_ENGINE_SHA } else { (& git -C (Split-Path $EngineBin -Parent) rev-parse HEAD 2>$null) }
$projRef = (& git -C $RepoRoot rev-parse HEAD 2>$null)
$lines = @(
    "Phasma Games $Version",
    ('=' * ("Phasma Games $Version").Length),
    '',
    'Each folder is a standalone game. Open the folder and run <Game>.exe.',
    'Keep every file in the folder together: the exe needs the DLLs, game.pepak,',
    'RuntimeAssets\ and Assets\ next to it.',
    '',
    'Requirements',
    '------------',
    '- Windows 10 or 11, 64-bit',
    '- A GPU with current Vulkan drivers (NVIDIA, AMD or Intel)',
    '- The Microsoft C++ runtime is included in each folder; nothing to install.',
    '',
    "Games ($($ok.Count))",
    '-----'
)
foreach ($grp in ($ok | Group-Object Group)) {
    if ($grp.Name) { $lines += ''; $lines += "$($grp.Name):" }
    foreach ($r in $grp.Group) {
        $lines += ('  {0,-22} {1,-26} {2}' -f "$($r.Game)\", $r.Display, (Format-Size $r.Bytes))
    }
}
$lines += ''
$lines += 'Build info'
$lines += '----------'
$lines += "PhasmaProjects : $projRef"
if ($engineRef) { $lines += "PhasmaEngine   : $engineRef" }
$lines += "Built          : $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC"
[IO.File]::WriteAllText((Join-Path $Bundle 'README.txt'), ($lines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))

# Zip ----------------------------------------------------------------------
$zipBytes = [long]0
if (-not $NoZip -and $ok.Count -gt 0) {
    Write-Step "Zipping $ZipPath"
    New-Zip $Bundle $ZipPath
    $zipBytes = (Get-Item -LiteralPath $ZipPath).Length
}

# Summary ------------------------------------------------------------------
Write-Host ''
$results | Format-Table Game, Group, Ok, @{ n = 'Size'; e = { Format-Size $_.Bytes } },
    @{ n = 'game.pepak'; e = { Format-Size $_.PepakBytes } }, Seconds, Error -AutoSize | Out-String -Width 220 | Write-Host
$total = ($results | Measure-Object Bytes -Sum).Sum
Write-Host ("Exported {0}/{1} games, {2} uncompressed" -f $ok.Count, $results.Count, (Format-Size $total))
if ($zipBytes) {
    Write-Host ("Zip: {0} ({1})" -f $ZipPath, (Format-Size $zipBytes))
    if ($zipBytes -ge $ReleaseAssetLimit) {
        Write-Warning "The zip is $(Format-Size $zipBytes); GitHub release assets must be under 2 GiB."
    }
}

[pscustomobject]@{
    version    = $Version
    zip        = if ($zipBytes) { $ZipPath } else { $null }
    zip_bytes  = $zipBytes
    exporter   = $Exporter
    games      = $results
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Out 'summary.json') -Encoding utf8

if ($env:GITHUB_OUTPUT) {
    "version=$Version" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "zip=$ZipPath" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "zip_name=$BundleName.zip" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "zip_bytes=$zipBytes" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "failed=$($failed.Count)" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}
if ($env:GITHUB_STEP_SUMMARY) {
    $md = @("### Phasma games $Version", '', '| Game | Result | Size |', '|---|---|---|')
    foreach ($r in $results) {
        $md += "| $($r.Source) | $(if ($r.Ok) { 'ok' } else { 'FAILED: ' + ($r.Error -replace '\|', '/') }) | $(Format-Size $r.Bytes) |"
    }
    $md += ''
    if ($zipBytes) { $md += "Zip: ``$BundleName.zip`` - $(Format-Size $zipBytes)" }
    $md -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}

if ($failed.Count -gt 0) {
    Write-Host "Failed: $(($failed | ForEach-Object Game) -join ', ')" -ForegroundColor Red
    exit 1
}
exit 0
