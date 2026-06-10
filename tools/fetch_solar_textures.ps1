# Downloads Solar System Scope (CC BY 4.0) planet maps + the NASA SVS Deep Star Maps
# 2020 EXR. The 2k set is tracked in git; pass -EightK for the local hi-res upgrade
# (git-ignored). After this, run convert_starmap.py and bake_saturn_rings.py.
#
# Uses curl.exe: solarsystemscope.com 403s requests without a browser User-Agent AND
# a same-site Referer (Invoke-WebRequest gets blocked even with a UA).
param([switch]$EightK)

$ErrorActionPreference = "Stop"
$texDir = Join-Path $PSScriptRoot "..\Assets\Textures\Solar"
New-Item -ItemType Directory -Force $texDir | Out-Null

$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
$referer = "https://www.solarsystemscope.com/textures/"
$base = "https://www.solarsystemscope.com/textures/download"

$maps = @(
    "2k_sun.jpg", "2k_mercury.jpg", "2k_venus_atmosphere.jpg",
    "2k_earth_daymap.jpg", "2k_earth_nightmap.jpg", "2k_earth_clouds.jpg",
    "2k_moon.jpg", "2k_mars.jpg", "2k_jupiter.jpg", "2k_saturn.jpg",
    "2k_uranus.jpg", "2k_neptune.jpg", "2k_saturn_ring_alpha.png"
)
if ($EightK) {
    $maps += @("8k_sun.jpg", "8k_mercury.jpg", "8k_venus_atmosphere.jpg", "8k_earth_daymap.jpg",
        "8k_earth_nightmap.jpg", "8k_earth_clouds.jpg", "8k_moon.jpg", "8k_mars.jpg",
        "8k_jupiter.jpg", "8k_saturn.jpg", "8k_uranus.jpg", "8k_neptune.jpg")
}

foreach ($f in $maps) {
    $out = Join-Path $texDir $f
    if (-not (Test-Path $out)) {
        Write-Host "fetching $f"
        $code = & curl.exe -sL -o $out -A $ua -e $referer "$base/$f" -w "%{http_code}"
        if ($code -ne "200") { Remove-Item $out -ErrorAction SilentlyContinue; throw "HTTP $code for $f" }
    }
}

# NASA SVS Deep Star Maps 2020 (https://svs.gsfc.nasa.gov/4851), public domain.
$starmap = Join-Path $texDir "starmap_2020_4k.exr"
if (-not (Test-Path $starmap)) {
    Write-Host "fetching starmap_2020_4k.exr"
    $code = & curl.exe -sL -o $starmap -A $ua "https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_4k.exr" -w "%{http_code}"
    if ($code -ne "200") { Remove-Item $starmap -ErrorAction SilentlyContinue; throw "HTTP $code for starmap" }
}

Write-Host "Done. Next: python tools/convert_starmap.py; python tools/bake_saturn_rings.py"
