"""Phase-1 proof captures in the muted throwaway copy (port 8912), then the copy is closed.

    python tools/capture.py <out_dir>

States A and B (+ a second shot 0.6 s later for shimmer), 8 sea-motion frames 0.25 s apart (sea time set exactly),
a 20 s scroll with the pendulum running (frame times, screenshots), 1280x720 framing, node / light counts.
"""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import live  # noqa: E402

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
rep = {}
live.start()
try:
    m = live.Mcp(live.PORT).init()
    m.lua("engine.set_background_fps_cap(false); return 'cap off'")
    rep["fps_cap"] = m.lua("return tostring(engine.get_background_fps_cap())")
    live.size(0, 0)
    time.sleep(1.5)
    rep["surface"] = m.lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height")
    for st in ("A", "B"):
        rep["state_" + st] = m.lua("return undertow.state('%s')" % st)
        time.sleep(3.0)
        m.shot(OUT / ("state_%s.png" % st))
        time.sleep(0.6)
        m.shot(OUT / ("state_%s_2.png" % st))
        rep["info_" + st] = m.lua("return undertow.info()")
    rep["counts"] = m.lua("""local n = 0; for _ in pairs(scene.get_nodes and scene.get_nodes() or {}) do n = n + 1 end
        local pl = #lights.get_point_lights(); local c = lights.get_counts and lights.get_counts() or {}
        return 'scene nodes ' .. n .. ' point lights ' .. pl .. ' counts ' .. (type(c) == 'table' and table.concat((function() local t = {} for k, v in pairs(c) do t[#t+1] = k .. '=' .. tostring(v) end return t end)(), ' ') or tostring(c))""")
    # sea motion: the float held in state A, the sea at t0 + k * 0.25 s
    m.lua("undertow.state('A'); return 'x'")
    t0 = float(m.lua("return tostring(undertow.S.t)"))
    for k in range(8):
        m.lua("undertow.S.t = %f; return 'x'" % (t0 + 0.25 * k))
        time.sleep(1.2)
        m.shot(OUT / ("motion_%d.png" % k))
    # scrolling with the pendulum
    m.lua("undertow.state('A'); return undertow.run(12)")
    samples, shots = [], 0
    t_end = time.time() + 20
    while time.time() < t_end:
        s = m.lua("local d = engine.get_metrics().delta_ms; return string.format('%.3f %.2f', d, undertow.S.cx)")
        samples.append([float(v) for v in s.split()])
        if shots < 3 and len(samples) in (12, 24, 36):
            m.shot(OUT / ("scroll_%d.png" % shots))
            shots += 1
        time.sleep(0.4)
    rep["scroll_info"] = m.lua("return undertow.info()")
    rep["state_fps"] = m.call("get_state").get("structuredContent")
    ms = [s[0] for s in samples]
    rep["scroll_ms"] = {"n": len(ms), "mean": sum(ms) / len(ms), "max": max(ms), "min": min(ms),
                        "cx_start": samples[0][1], "cx_end": samples[-1][1]}
    # 1280x720
    m.lua("undertow.stop(); return undertow.state('A')")
    live.size(1280, 720)
    time.sleep(2.5)
    rep["surface_720"] = m.lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height")
    m.shot(OUT / "state_A_720.png")
    m.lua("return undertow.state('B')")
    time.sleep(2.5)
    m.shot(OUT / "state_B_720.png")
finally:
    live.stop()
log = (live.WORK / "rt" / "PhasmaEngine.log").read_text(errors="replace").splitlines()
rep["log_warnings"] = sum(1 for l in log if "[WARN" in l)
rep["log_errors"] = sum(1 for l in log if "[ERROR" in l)
rep["log_problem_lines"] = sorted({l.split("]", 2)[-1].strip()[:140] for l in log if "[WARN" in l or "[ERROR" in l})[:20]
(OUT / "capture.json").write_text(json.dumps(rep, indent=1))
print(json.dumps(rep, indent=1))
