"""Throwaway, MUTED Player copy of Shadow Puppeteer on MCP port 8914: screenshots of the look slice.

    python tools/look_capture.py OUT_DIR

Copies the newest Release PhasmaPlayer and this game's Assets (no Save/Agent) into OUT_DIR/work, writes a muted
settings file and an agent config on port 8914 (refuses if the port is taken), launches it, mutes the master volume
before anything else, and takes: state A twice a second apart, state B, a mid-drag state (driven through the game's
own picking), state A at 1280x720, and frame times with the unfocused-window cap off. The window is sized with
SetWindowPos(SWP_NOACTIVATE): the Player never takes focus from the user.
"""
import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import look_capture_lib as lib  # noqa: E402
from look_capture_lib import Mcp, PORT, size_client, window_of  # noqa: E402

OUT = Path(sys.argv[1]).resolve()
QUICK = len(sys.argv) > 2 and sys.argv[2] == "quick"      # state A at 2560x1369 only (iteration)
LUA = sys.argv[3] if len(sys.argv) > 3 else None             # optional Lua run before the shot (tuning)


def main():
    proc = lib.launch(OUT)
    rt = OUT / "work" / "rt"
    report = {}
    mcp = Mcp(PORT)
    try:
        lib.connect(mcp, proc)
        # mute before anything else
        report["mute"] = mcp.lua("audio.set_master_volume(0); if audio.set_muted then pcall(audio.set_muted, true) end; return 'master volume 0'")
        hwnd = window_of(proc.pid)
        for size, tag in (((2560, 1369), "2560"), ((1280, 720), "1280")):
            if hwnd:
                size_client(hwnd, *size)
            time.sleep(2.5)
            got = mcp.lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height")
            print("window", tag, "->", got, flush=True)
            report["size_" + tag] = got
            mcp.lua("return puppet.state_a()")
            if LUA:
                print("lua:", mcp.lua(LUA), flush=True)
            time.sleep(3.0)
            mcp.shot("A_" + got)
            if QUICK:
                break
            if tag != "2560":
                continue
            time.sleep(1.0)
            mcp.shot("A_" + got + "_1s")
            mcp.lua("return puppet.state_b()")
            time.sleep(3.0)
            mcp.shot("B_" + got)
            # measurement frames without dust or halo (motes over a shadow are not its outline); the motes alive
            # when the emitters go dark live up to 9 s
            mcp.lua("puppet.W.set_particles(false) return puppet.state_a()")
            time.sleep(10.0)
            mcp.shot("A_clean")
            time.sleep(1.0)
            mcp.shot("A_clean_1s")
            mcp.lua("return puppet.state_b()")
            time.sleep(3.0)
            mcp.shot("B_clean")
            mcp.lua("puppet.W.set_particles(true) return puppet.state_a()")
            # mid-drag, through the game's own picking: grab the lantern at its foot, carry it toward the middle
            r = mcp.lua("""
puppet.state_a()
local W = puppet.W
local L = W.state.lantern
local sx, sy = W.project(L[1], L[2], 0.02)
local what = W.pick(sx, sy)
local g = W.drag_begin(what, sx, sy)
local tx, ty = W.project(0.15, -0.98, 0.02)
W.drag_move(g, (sx + tx) / 2, (sy + ty) / 2)
local c = puppet.W.state
local g2 = W.drag_begin('comb', W.project(c.comb + 0.2, puppet.D.PROPS.comb.y, 0.2))
local cx = W.project(c.comb + 0.45, puppet.D.PROPS.comb.y, 0.2)
local _, cy = W.project(c.comb + 0.2, puppet.D.PROPS.comb.y, 0.2)
W.drag_move(g2, cx, cy)
return string.format('%s lantern %.3f %.3f comb %.3f', tostring(what), L[1], L[2], c.comb)""")
            print("mid-drag:", r, flush=True)
            report["mid_drag"] = r
            time.sleep(3.0)
            mcp.shot("drag_" + got)
            # frame time: unfocused window with the background FPS cap off
            mcp.lua("""
pcall(engine.set_background_fps_cap, false)
_G.__ft = {}
script.on_update('ft', function() local m = engine.get_metrics(); _G.__ft[#_G.__ft + 1] = m.delta_ms end, 'play')
puppet.state_a()
return 'rec'""")
            time.sleep(6.0)
            ft = mcp.lua("""
local t = _G.__ft
local s, n, mx = 0, 0, 0
for i = 30, #t do s = s + t[i]; n = n + 1; if t[i] > mx then mx = t[i] end end
table.sort(t)
return string.format('frames %d mean %.2f ms p95 %.2f ms max %.2f ms cap %s', n, s / math.max(1, n), t[math.floor(#t * 0.95)] or 0, mx,
  tostring(engine.get_background_fps_cap and engine.get_background_fps_cap()))""")
            print("frame time (unfocused, cap off):", ft, flush=True)
            report["frame_time"] = ft
            mcp.lua("script.on_update('ft', function() end, 'play'); return 'off'")
    finally:
        time.sleep(0.5)
        proc.kill()
        log = rt / "PhasmaEngine.log"
        if log.exists():
            shutil.copy2(log, OUT / "PhasmaEngine.log")
            lines = log.read_text(errors="replace").splitlines()
            warn = [l for l in lines if "[WARN" in l.upper() or "WARNING" in l.upper()]
            err = [l for l in lines if "[ERROR" in l.upper() or " ERROR" in l.upper()]
            report["log_warnings"], report["log_errors"] = len(warn), len(err)
            print("log: %d warning lines, %d error lines" % (len(warn), len(err)))
            for l in (err + warn)[:30]:
                print("   ", l[:220])
        (OUT / "capture_report.json").write_text(json.dumps(report, indent=1))


main()
