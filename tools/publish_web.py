"""Builds the GitHub Pages site of every game's browser export and can publish it to this repo's gh-pages branch.

GitHub Pages limits a site to 1 GB and Git refuses files over 100 MB, so the site is not a copy of the exports:
the wasm player (identical across games built from one engine) is stored once per distinct build under player/,
and each game's asset pack is gzip-compressed and cut into parts that the game's page downloads and unpacks
before it starts the player.

Usage: python tools/publish_web.py [--exports <dir>] [--site <dir>] [--export-missing] [--push]
  --exports         folder holding <Game>/site from the engine's tools/export_web.py and an optional <Game>/shot.png
                    (default ../PhasmaEngine/build-wasm-export/games)
  --site            where the site is written (default ../phasma-games-site, outside the repo)
  --export-missing  export tracked games that have no <Game>/site yet (needs the engine's desktop and wasm builds)
  --push            replace origin's gh-pages branch with the site as one commit (the branch keeps no history)
A game is every tracked phasma_project.json. Serve the site locally with
python -m http.server --directory <site> 8080 and open http://localhost:8080/ (WebGPU needs localhost or https).
"""
import argparse
import gzip
import hashlib
import html
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ENGINE = REPO.parent / "PhasmaEngine"
PART_BYTES = 90 * 1024 * 1024  # under Git's 100 MB file limit
SITE_LIMIT = 1024 ** 3
PLAYER_SCRIPT = "<script async src=PhasmaPlayer.js></script>"

# Replaces the export's player script: downloads and unpacks the asset pack, then starts the player with the pack
# in memory and the shared wasm.
LOADER = """<script>(async()=>{try{const parts=__PARTS__,total=__BYTES__;let got=0;
const packed=new ReadableStream({async start(out){for(let i=0;i<parts;i++){
const response=await fetch("data."+String(i).padStart(3,"0"));
if(!response.ok)throw new Error("part "+i+" answered "+response.status);
const reader=response.body.getReader();
for(;;){const{done,value}=await reader.read();if(done)break;got+=value.length;out.enqueue(value);
Module.setStatus("Loading... "+Math.floor(100*got/total)+"%")}}out.close()}});
const pack=await new Response(packed.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
Module.getPreloadedPackage=()=>pack;
Module.locateFile=path=>path.endsWith(".wasm")?"../player/__WASM__":path;
const script=document.createElement("script");script.src="PhasmaPlayer.js";document.body.appendChild(script)
}catch(error){Module.setStatus("The game could not be loaded: "+error.message)}})()</script>"""

# Phones (a coarse pointer, or ?touch=1 to preview on a desktop), the same for every game: the page is laid out in
# device pixels so the canvas, which the player sizes in CSS pixels, renders sharp (capped at 2x for the GPU's sake);
# a tap enters full screen in landscape; and Module.peUiZoom asks the player to enlarge the game's UI on a
# phone-sized screen (RuntimeUiZoom.h in the engine; ?zoom=1.8 tries another value). The player itself pulses the
# phone's vibration when a UI element is pressed. A two-finger pinch on the canvas becomes mouse-wheel steps with a
# vibration pulse each, so every game that zooms or scrolls with the wheel does so by pinching.
UI_ZOOM = 2.2
MOBILE = """<style>
html,body{overscroll-behavior:none;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
#canvas{touch-action:none}
.pe-ui{position:fixed;z-index:5;display:none;align-items:center;justify-content:center;color:#fff;
font:calc(20px*var(--pe-u,1)) system-ui,sans-serif}
#pe-start{inset:0;z-index:6;background:rgba(0,0,0,.55)}
#pe-full{top:calc(8px*var(--pe-u,1));right:calc(8px*var(--pe-u,1));width:calc(40px*var(--pe-u,1));
height:calc(40px*var(--pe-u,1));box-sizing:border-box;border-radius:50%;background:rgba(20,24,32,.4);
border:calc(1.5px*var(--pe-u,1)) solid rgba(255,255,255,.45);touch-action:none}
</style>
<div id=pe-start class=pe-ui>Tap to play full screen</div>
<div id=pe-full class=pe-ui>&#x26F6;</div>
<script>(()=>{
const preview=/[?&]touch=1/.test(location.search),coarse=matchMedia("(pointer: coarse)").matches;
if(!coarse&&!preview)return;
const show=(id,on)=>document.getElementById(id).style.display=on?"flex":"none";
const asked=/[?&]zoom=([0-9.]+)/.exec(location.search);
if(preview||Math.min(screen.width,screen.height)<=600)Module.peUiZoom=asked?+asked[1]:__ZOOM__;
const scale=Math.min(devicePixelRatio||1,2);
if(scale>1&&coarse){
const meta=document.querySelector("meta[name=viewport]");
meta.content="width=device-width,initial-scale="+1/scale+",minimum-scale="+1/scale+",maximum-scale="+1/scale+",user-scalable=no";
document.documentElement.style.setProperty("--pe-u",scale)}
const fullScreen=()=>{const root=document.documentElement;
if(document.fullscreenElement||!root.requestFullscreen)return;
root.requestFullscreen({navigationUI:"hide"}).then(()=>screen.orientation&&screen.orientation.lock&&
screen.orientation.lock("landscape")).catch(()=>{})};
document.getElementById("pe-full").addEventListener("pointerup",event=>{event.preventDefault();
document.fullscreenElement?document.exitFullscreen():fullScreen()});
document.getElementById("pe-start").addEventListener("pointerup",()=>{show("pe-start",false);fullScreen()});
const fingers=new Map();let span=0;
const spread=()=>{const[a,b]=[...fingers.values()];return Math.hypot(a.clientX-b.clientX,a.clientY-b.clientY)};
addEventListener("pointerdown",event=>{
if(event.pointerType!="touch"||event.target.id!="canvas")return;
fingers.set(event.pointerId,event);
if(fingers.size==2)span=spread()},true);
addEventListener("pointermove",event=>{
if(!fingers.has(event.pointerId))return;
fingers.set(event.pointerId,event);
if(fingers.size!=2)return;
const step=24*scale,[a,b]=[...fingers.values()];
while(Math.abs(spread()-span)>=step){
const way=Math.sign(spread()-span);span+=way*step;
event.target.dispatchEvent(new WheelEvent("wheel",{deltaY:-100*way,clientX:(a.clientX+b.clientX)/2,
clientY:(a.clientY+b.clientY)/2,bubbles:true,cancelable:true}));
navigator.vibrate&&navigator.vibrate(8)}},true);
for(const type of["pointerup","pointercancel"])addEventListener(type,event=>fingers.delete(event.pointerId),true);
show("pe-start",true);show("pe-full",true)})()</script>""".replace("__ZOOM__", str(UI_ZOOM))

INDEX = """<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Phasma games</title>
<style>
  body {{ margin: 0; padding: 24px; background: #101216; color: #e6e6e6; font: 15px/1.4 system-ui, sans-serif; }}
  h1 {{ font-size: 20px; margin: 0 0 4px; }}
  p {{ margin: 0 0 16px; color: #9aa4b2; }}
  main {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 16px; }}
  a {{ display: block; color: inherit; text-decoration: none; background: #1a1d24; border-radius: 8px; overflow: hidden; }}
  a:focus-visible {{ outline: 3px solid #7fb4ff; }}
  img {{ display: block; width: 100%; aspect-ratio: 16 / 9; object-fit: cover; background: #000; }}
  span {{ display: block; padding: 10px 12px; }}
  small {{ color: #9aa4b2; }}
</style>
<h1>Phasma games</h1>
<p>{count} games that run in the browser. They need WebGPU: a recent Chrome or Edge on a desktop computer.</p>
<main>
{tiles}
</main>
</html>
"""


def games():
    """Tracked games as (name, project folder)."""
    listed = subprocess.run(["git", "ls-files", "*phasma_project.json"], cwd=REPO, capture_output=True, text=True,
                            check=True)
    found = []
    for line in listed.stdout.splitlines():
        project = (REPO / line.strip()).parent
        name = project.name if project.name != "project" else project.parent.name
        found.append((name, project))

    return sorted(found)


def export_game(project, site):
    command = [sys.executable, ENGINE / "tools" / "export_web.py", "--project", project, "--output", site]
    return subprocess.run([str(part) for part in command], cwd=ENGINE).returncode == 0


def pack_parts(pack, folder):
    """Writes the gzip of `pack` as data.000, data.001, ... and returns (parts, compressed bytes)."""
    packed = gzip.compress(pack.read_bytes(), compresslevel=9, mtime=0)
    parts = 0
    for start in range(0, len(packed), PART_BYTES):
        (folder / f"data.{parts:03d}").write_bytes(packed[start:start + PART_BYTES])
        parts += 1

    return parts, len(packed)


def publish_game(name, export, site):
    """Writes site/<name>/ from an export folder; returns megabytes written, or None when the export is unusable."""
    page = (export / "PhasmaPlayer.html").read_text(encoding="utf-8")
    if page.count(PLAYER_SCRIPT) != 1:
        print(f"{name}: skipped, PhasmaPlayer.html has no player script to replace")
        return None

    wasm = export / "PhasmaPlayer.wasm"
    wasm_name = hashlib.sha256(wasm.read_bytes()).hexdigest()[:16] + ".wasm"
    shared = site / "player" / wasm_name
    if not shared.exists():
        shutil.copyfile(wasm, shared)

    folder = site / name
    folder.mkdir()
    parts, packed_bytes = pack_parts(export / "PhasmaPlayer.data", folder)
    loader = LOADER.replace("__PARTS__", str(parts)).replace("__BYTES__", str(packed_bytes))
    loader = loader.replace("__WASM__", wasm_name).replace("\n", "")
    page = page.replace(PLAYER_SCRIPT, MOBILE + loader)
    page = page.replace("<title>Phasma</title>", f"<title>{html.escape(name)}</title>")
    (folder / "index.html").write_text(page, encoding="utf-8")
    shutil.copyfile(export / "PhasmaPlayer.js", folder / "PhasmaPlayer.js")
    shot = export.parent / "shot.png"
    if shot.exists():
        shutil.copyfile(shot, folder / "shot.png")

    return sum(file.stat().st_size for file in folder.iterdir()) / 1e6


def remove_tree(folder):
    """shutil.rmtree that also deletes Git's read-only object files on Windows."""
    def make_writable(function, path, _):
        os.chmod(path, stat.S_IWRITE)
        function(path)

    shutil.rmtree(folder, onerror=make_writable)


def build_site(exports, site, export_missing):
    if site.exists():
        remove_tree(site)

    (site / "player").mkdir(parents=True)
    (site / ".nojekyll").write_text("", encoding="utf-8")  # serve the files as they are
    tiles = []
    for name, project in games():
        export = exports / name / "site"
        if not (export / "PhasmaPlayer.wasm").exists() and export_missing:
            export_game(project, export)

        if not (export / "PhasmaPlayer.wasm").exists():
            print(f"{name}: skipped, no export in {export}")
            continue

        megabytes = publish_game(name, export, site)
        if megabytes is None:
            continue

        shot = f'<img src="{name}/shot.png" alt="" loading="lazy">' if (site / name / "shot.png").exists() else ""
        label = f"{html.escape(name)} <small>{megabytes:.0f} MB</small>"
        tiles.append(f'<a href="{name}/">{shot}<span>{label}</span></a>')
        print(f"{name}: {megabytes:.0f} MB", flush=True)

    (site / "index.html").write_text(INDEX.format(count=len(tiles), tiles="\n".join(tiles)), encoding="utf-8")
    total = sum(file.stat().st_size for file in site.rglob("*") if file.is_file())
    print(f"{len(tiles)} games, {total / 1e6:.0f} MB in {site}")
    return len(tiles), total


def push(site):
    """One commit holding the whole site, forced onto origin's gh-pages: the branch never accumulates old packs."""
    origin = subprocess.run(["git", "remote", "get-url", "origin"], cwd=REPO, capture_output=True, text=True,
                            check=True).stdout.strip()
    if (site / ".git").exists():
        remove_tree(site / ".git")

    for command in (["git", "init", "--quiet", "--initial-branch=gh-pages"],
                    ["git", "add", "--all"],
                    ["git", "commit", "--quiet", "-m", "Publish the browser games"],
                    ["git", "push", "--force", origin, "gh-pages"]):
        subprocess.run(command, cwd=site, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exports", type=Path, default=ENGINE / "build-wasm-export" / "games")
    parser.add_argument("--site", type=Path, default=REPO.parent / "phasma-games-site")
    parser.add_argument("--export-missing", action="store_true")
    parser.add_argument("--push", action="store_true")
    args = parser.parse_args()

    count, total = build_site(args.exports.resolve(), args.site.resolve(), args.export_missing)
    if count == 0:
        print("FAIL: no game was published")
        return 1

    if total > SITE_LIMIT:
        print(f"FAIL: the site is {total / 1e6:.0f} MB, over GitHub Pages' 1 GB limit; nothing was pushed")
        return 1

    if args.push:
        push(args.site.resolve())

    return 0


if __name__ == "__main__":
    sys.exit(main())
