"""Live runs of the rules in a throwaway, MUTED Player copy on port 8914 (tools/look_capture_lib.py):

    python tools/play_capture.py OUT_DIR

The scripted win and the do-nothing loss, six 2560x1369 screenshots each with the puppet's state at every shot
(runs.json); then frame times while the puppet walks and the lantern is dragged every frame through the game's own
picking, with the unfocused-window cap off. The Player is killed at the end; the log's warnings/errors are counted.
"""
import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import look_capture_lib as lib  # noqa: E402

OUT = Path(sys.argv[1]).resolve()
# times from scratch/trace_runs.lua (2026-11-13 rules): win: flat walk, walk, mid-climb, the 75 deg slope off the
# ledge, mid-fall, end; nothing: flat walk, the 75 deg rise, cup top, past the cup, the 74 deg descent, end
# 2026-11-13 19:00 (slide rules): every slope over 55 deg in the runs (scratch/trace_runs.lua): win: walk, climb x2
# (alternating hands), the ladder-top lip (stepped), the ledge's chamfer tip (stepped, then the drop), end;
# nothing: the 75 deg lip rise (stepped), the cup's 5 cm step down (stepped), slide down the cup's side x2, end
SHOTS = {"win": [1.0, 18.4, 18.65, 21.1, 24.36, None], "nothing": [6.1, 7.92, 8.66, 8.82, None]}


def main():
    proc = lib.launch(OUT)
    rt = OUT / "work" / "rt"
    mcp = lib.Mcp(lib.PORT)
    report = {"runs": {}}
    try:
        lib.connect(mcp, proc)
        report["mute"] = mcp.lua("audio.set_master_volume(0); return 'master volume 0'")
        hwnd = lib.window_of(proc.pid)
        if hwnd:
            lib.size_client(hwnd, 2560, 1369)
        time.sleep(2.5)
        report["size"] = mcp.lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height")
        mcp.lua("pcall(engine.set_background_fps_cap, false) return 1")
        for run, times in SHOTS.items():
            mcp.lua("puppet.pause_at(%s) return puppet.run('%s')" % (times[0] if times[0] is not None else "nil", run))
            shots = []
            for i, t in enumerate(times):
                deadline = time.time() + 60
                while time.time() < deadline:
                    st = mcp.lua("local g = puppet.S.game; return string.format('%.4f %d %d %s', g.t, g.won and 1 or 0, g.dead and 1 or 0, puppet.is_paused())")
                    gt, won, dead, paused = st.split()
                    if (t is not None and paused == "1") or (t is None and (won == "1" or dead == "1")):
                        break
                    time.sleep(0.05)
                if t is None:
                    time.sleep(1.2)                     # let the end pose (death tip / win wave) play
                mcp.lua("return puppet.pause(true)")
                status = mcp.lua("return puppet.status()")
                name = "%s_%d" % (run, i + 1)
                time.sleep(0.3)
                mcp.shot(name)
                mcp.lua("return puppet.show_puppet(false)")       # the same frame without the puppet: the ground
                time.sleep(0.6)
                mcp.shot(name + "_ground")
                nxt = times[i + 1] if i + 1 < len(times) else None
                mcp.lua("puppet.show_puppet(true) puppet.pause_at(%s) return puppet.pause(false)" % (nxt if nxt is not None else "nil"))
                shots.append({"shot": name + ".png", "status": status})
                print(run, i + 1, status, flush=True)
            report["runs"][run] = shots
        # frame time while the puppet walks and the lantern is dragged every frame through the game's own picking
        mcp.lua("""
puppet.play()
local W = puppet.W
_G.__ft, _G.__k = {}, 0
script.on_update('ft', function()
    local m = engine.get_metrics(); _G.__ft[#_G.__ft + 1] = m.delta_ms
    _G.__k = _G.__k + 1
    local st = W.state
    local sx, sy = W.project(st.lantern[1], st.lantern[2], 0.02)
    local g = W.drag_begin('lantern', sx, sy)
    local tx = W.project(math.sin(_G.__k * 0.05) * 1.2, st.lantern[2], 0.02)
    if g then W.drag_move(g, tx, sy) end
end, 'play')
return 'rec'""")
        time.sleep(6.0)
        report["frame_time"] = mcp.lua("""
script.on_update('ft', function() end, 'play')
local t = _G.__ft
local s, n, mx = 0, 0, 0
for i = 30, #t do s = s + t[i]; n = n + 1; if t[i] > mx then mx = t[i] end end
table.sort(t)
return string.format('frames %d mean %.2f ms p95 %.2f ms max %.2f ms, lantern dragged every frame, puppet %s', n,
  s / math.max(1, n), t[math.floor(#t * 0.95)] or 0, mx, puppet.status())""")
        print("frame time:", report["frame_time"], flush=True)
    finally:
        time.sleep(0.5)
        proc.kill()
        log = rt / "PhasmaEngine.log"
        if log.exists():
            shutil.copy2(log, OUT / "PhasmaEngine.log")
            lines = log.read_text(errors="replace").splitlines()
            report["log_warnings"] = sum(1 for l in lines if "[WARN" in l)
            report["log_errors"] = sum(1 for l in lines if "[ERROR" in l)
            print("log: %d warning lines, %d error lines" % (report["log_warnings"], report["log_errors"]))
            for l in [l for l in lines if "[WARN" in l or "[ERROR" in l][:20]:
                print("   ", l[:220])
        (OUT / "runs.json").write_text(json.dumps(report, indent=1))


main()
