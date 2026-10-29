# package.ps1 - build a single self-extracting Windows exe of this game.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\package.ps1 [-Api vulkan|dx12] [-Verify]
#
# Steps: PhasmaExport -> dist\BannersBorders (player exe renamed to BannersBorders.exe, game.pepak,
# runtime DLLs + the MSVC runtime) -> dist\BannersBorders.zip -> tools\launcher.cs compiled with the
# .NET Framework csc.exe into dist\BannersBorders.exe with the zip embedded.
# -Verify runs the built launcher with --extract-only (never starts the game) into dist\_verify.
# Engine: $env:PHASMA_ENGINE / -Engine, else the first sibling 'PhasmaEngine' (with a Release PhasmaExport.exe)
# found walking up from the game folder (default ..\..\PhasmaEngine); prefers build-ninja-physics\Release.
param(
    [ValidateSet('vulkan', 'dx12')][string]$Api = 'vulkan',
    [string]$Engine = $env:PHASMA_ENGINE,
    [switch]$SkipExport,
    [switch]$Verify
)
$ErrorActionPreference = 'Stop'
$name = 'BannersBorders'
$game = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $game 'dist'
$out = Join-Path $dist $name
$zip = Join-Path $dist "$name.zip"
$final = Join-Path $dist "$name.exe"
$obj = Join-Path $dist 'obj'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }

# ---- 1. export --------------------------------------------------------------------------------
if (-not $SkipExport) {
    if (-not $Engine) {
        $dir = Get-Item $game
        while ($dir) {
            $cand = Join-Path $dir.FullName 'PhasmaEngine'
            if (Get-ChildItem "$cand\build*\Release\PhasmaExport.exe" -EA SilentlyContinue) { $Engine = $cand; break }
            $dir = $dir.Parent
        }
        if (-not $Engine) { $Engine = [IO.Path]::GetFullPath((Join-Path $game '..\..\PhasmaEngine')) }
    }
    $exporters = @(Get-ChildItem "$Engine\build*\Release\PhasmaExport.exe" -EA SilentlyContinue |
        Where-Object { (Test-Path (Join-Path $_.DirectoryName 'PhasmaPlayer.exe')) -and (Test-Path (Join-Path $_.DirectoryName 'RuntimeAssets')) })
    if (-not $exporters) { throw "No Release PhasmaExport.exe (with PhasmaPlayer.exe + RuntimeAssets beside it) under $Engine\build*\Release. Set PHASMA_ENGINE or -Engine." }
    $exporter = ($exporters | Where-Object { $_.FullName -like '*\build-ninja-physics\*' } | Select-Object -First 1)
    if (-not $exporter) { $exporter = $exporters | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
    Step "Export with $($exporter.FullName)"
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    & $exporter.FullName --project (Join-Path $game 'project') --output $out --force
    if ($LASTEXITCODE -ne 0) { throw "PhasmaExport failed (exit $LASTEXITCODE)" }

    Step 'Rename player'
    Move-Item -Force (Join-Path $out 'PhasmaPlayer.exe') (Join-Path $out "$name.exe")

    Step "Settings (graphics_api=$Api)"
    $settingsPath = Join-Path $out 'phasma_settings.json'
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName graphics_api -NotePropertyValue $Api -Force
    $settings | Add-Member -NotePropertyName live_profiler -NotePropertyValue $false -Force
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))

    Step 'MSVC runtime DLLs'
    $crt = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_atomic_wait.dll')
    $crtDir = $null
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        foreach ($vs in @(& $vswhere -all -products * -property installationPath)) {
            $cand = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory -EA SilentlyContinue |
                Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending |
                ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64') -Directory -Filter 'Microsoft.VC14*.CRT' -EA SilentlyContinue } |
                Where-Object { Test-Path (Join-Path $_.FullName 'msvcp140.dll') } | Select-Object -First 1
            if ($cand) { $crtDir = $cand.FullName; break }
        }
    }
    foreach ($dll in $crt) {
        $src = if ($crtDir -and (Test-Path (Join-Path $crtDir $dll))) { Join-Path $crtDir $dll } else { Join-Path $env:WINDIR "System32\$dll" }
        if (-not (Test-Path $src)) { throw "MSVC runtime $dll not found (VS redist or System32)" }
        Copy-Item $src $out -Force
        Write-Host "   $dll <- $src"
    }

    foreach ($f in "$name.exe", 'PhasmaCore.dll', 'game.pepak', 'phasma_project.json', 'phasma_settings.json', 'Assets\anchor.txt', 'RuntimeAssets\anchor.txt') {
        if (-not (Test-Path (Join-Path $out $f))) { throw "Export is missing $f" }
    }
}
if (-not (Test-Path (Join-Path $out "$name.exe"))) { throw "No export at $out (run without -SkipExport)" }

# ---- 2. version = content hash of the export folder (identical content -> same version) -------
Step 'Version'
$sha = [Security.Cryptography.SHA256]::Create()
$lines = Get-ChildItem $out -Recurse -File | Sort-Object FullName | ForEach-Object {
    $_.FullName.Substring($out.Length + 1).Replace('\', '/') + ':' + (Get-FileHash $_.FullName -Algorithm SHA256).Hash
}
$hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))) | ForEach-Object { $_.ToString('x2') })
$version = $hash.Substring(0, 12)
Write-Host "   version $version"

# ---- 3. zip -----------------------------------------------------------------------------------
Step "Zip -> $zip"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path $zip) { Remove-Item $zip -Force }
$za = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($f in Get-ChildItem $out -Recurse -File) {
        $rel = $f.FullName.Substring($out.Length + 1).Replace('\', '/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $rel, 'Optimal')
    }
} finally { $za.Dispose() }

# ---- 4. launcher ------------------------------------------------------------------------------
Step "Launcher -> $final"
$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fw 'csc.exe'
if (-not (Test-Path $csc)) { throw ".NET Framework csc.exe not found at $csc" }
New-Item -ItemType Directory -Force -Path $obj | Out-Null
$versionFile = Join-Path $obj 'version.txt'
[IO.File]::WriteAllText($versionFile, $version, (New-Object Text.UTF8Encoding($false)))
$cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/platform:x64', "/out:$final",
    "/r:$fw\System.IO.Compression.dll", "/r:$fw\System.Windows.Forms.dll",
    "/resource:$zip,payload.zip", "/resource:$versionFile,version.txt")
$icon = @((Join-Path $PSScriptRoot 'icon.ico'), (Join-Path $game 'project\icon.ico'), (Join-Path $game 'project\Assets\icon.ico')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($icon) { $cscArgs += "/win32icon:$icon"; Write-Host "   icon $icon" } else { Write-Host '   no icon.ico found (tools\icon.ico) - using default' }
$cscArgs += (Join-Path $PSScriptRoot 'launcher.cs')
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "csc failed (exit $LASTEXITCODE)" }

$mb = '{0:N1} MB' -f ((Get-Item $final).Length / 1MB)
Write-Host "Built $final ($mb, version $version)" -ForegroundColor Green

# ---- 5. optional extract-only check (never starts the game) -------------------------------------
if ($Verify) {
    $vroot = Join-Path $dist '_verify'
    Step "Verify: $name.exe --extract-only --install-root $vroot"
    $p = Start-Process $final -ArgumentList '--extract-only', '--install-root', "`"$vroot`"" -Wait -PassThru
    if ($p.ExitCode -ne 0) { Get-Content (Join-Path $vroot 'launcher.log') -EA SilentlyContinue; throw "extract-only failed (exit $($p.ExitCode))" }
    $vdir = Join-Path $vroot $version
    $bad = Get-ChildItem $out -Recurse -File | Where-Object {
        $twin = Join-Path $vdir $_.FullName.Substring($out.Length + 1)
        -not (Test-Path $twin) -or (Get-FileHash $twin).Hash -ne (Get-FileHash $_.FullName).Hash
    }
    if ($bad) { throw "Extracted copy differs: $($bad.FullName -join ', ')" }
    Write-Host "   extracted copy matches the export ($vdir)" -ForegroundColor Green
}
