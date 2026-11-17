"""Live runs at every difficulty step in the throwaway Player (start it first: python tools/live.py start; it runs on its
own hidden desktop, muted, port 8912). Each run starts from the title with a posted click on PLAY.

    python tools/live_levels.py <out_dir> <run> [<run> ...]
      run = real / realN  the hold posted as real Space key events (look-ahead release policy); realN starts at step N
            prog          no start level: the real progression (difficulty steps every 300 units)
            0..5          G.start_level = n (the run starts at and holds that step)
    Non-"real" runs play through the game's own input function with the bot deciding (G.auto).

Per run: the in-game time series every 0.25 s (t, x, z, hook, score, level, game, rules, dist, lamps, frame_ms), 10
guarded screenshots 1.0 s apart (8x8 copy marker + is_undertow) in the first ~12 s, then a shot-free window for the
frame time (undertow.timing), node measurements at ~4 Hz (__uw_measure: drawn float vs rules, chain ends, hooked
piece's node vs the rules' origin, hazard clearance, water), pool use / starvation, and the log's warnings / errors."""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import live  # noqa: E402
import live_flow as lf  # noqa: E402  (HOOKS, click helpers)

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
m = lf.m

MEASURE = r'''
function __uw_measure()
  local U = undertow; local rs, W, D = U.S.rs, U.W, U.D
  if not rs or rs.mode == "dead" or U.G.mode ~= "run" then return "-" end
  local fl = W.float
  local g = fl.glass:get_position()                       -- engine (x, up, -y)
  local out = { string.format("%.2f", rs.x), string.format("%.4f", g.x - U.S.F.x), string.format("%.4f", g.y - U.S.F.z),
                string.format("%.4f", g.x - rs.x), string.format("%.4f", g.y - rs.z) }
  if W.chain and W.links_used > 0 and rs.hook then
    local l1, ln, r = W.links[1]:get_position(), W.links[W.links_used]:get_position(), fl.ring:get_position()
    local function d(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2) end
    out[#out + 1] = string.format("%.3f", d(l1, r))                  -- first link to the hook ring
    out[#out + 1] = string.format("%.3f", d(ln, g) - D.FLOAT_R)      -- last link to the glass surface
    out[#out + 1] = string.format("%.4f", r.x - rs.hx)                -- ring vs the rules' hook
    out[#out + 1] = string.format("%.4f", r.y - 0.04 - rs.hz)
    local cur = W.ITEM and W.ITEM[rs.hook.id]
    if cur and cur.node then
      local p = cur.node:get_position(); local ox, oy, oz = U.Course.origin(rs.hook, U.S.t)
      out[#out + 1] = string.format("%.4f", math.sqrt((p.x - ox)^2 + (p.y - oz)^2 + (p.z + oy)^2))  -- drawn piece vs rules origin
    else out[#out + 1] = "nan" end
  else
    for _ = 1, 5 do out[#out + 1] = "nan" end
  end
  local clear = 9
  for r = D.FLOAT_R, D.FLOAT_R + 1.5, 0.02 do
    if U.Rules.hit_at(rs.course, rs.x, rs.z, rs.t, r) then clear = r - D.FLOAT_R; break end
  end
  out[#out + 1] = string.format("%.2f", clear)                     -- clearance of the glass to the nearest hazard mesh
  out[#out + 1] = string.format("%.3f", rs.z - D.FLOAT_R - U.Sea.height(rs.x, 0, rs.t))   -- glass bottom above the water
  return table.concat(out, ",")
end
return "measure on"
'''
MCOLS = "x,float_vs_view_x,float_vs_view_z,float_vs_rules_x,float_vs_rules_z,link1_to_ring,lastlink_to_glass,ring_vs_hook_x,ring_vs_hook_z,piece_vs_origin,hazard_clearance,bottom_above_water"


def to_title():
    i = lf.info()
    if "mode=over" in i:
        lf.click("BACK TO MENU")
    elif "mode=run" in i:
        lf.key("Escape", 0.6)
        lf.click("BACK TO MENU")
    lf.wait_for(lambda s: "mode=title" in s, 8, "title")


def run(name):
    d = OUT / ("run_" + name)
    d.mkdir(exist_ok=True)
    to_title()
    is_real = name.startswith("real")
    lv = (int(name[4:]) if len(name) > 4 else None) if is_real else (None if name == "prog" else int(name))
    lf.lua("undertow.G.start_level = %s" % ("nil" if lv is None else lv))
    lf.lua("undertow.G.auto = %s" % ("nil" if is_real else "true"))
    lf.lua("undertow.series_start(0.25)")
    lf.click("PLAY")
    lf.wait_for(lambda s: "mode=run" in s, 5, "run")
    t0 = time.time()
    meas, shots, real = [], [], None
    min_t = 300.0 if name == "real" else (120.0 if name == "prog" or is_real else 62.0)
    if is_real:
        real = {"held": False, "catches": 0, "releases": 0, "last": False, "t_rel": 0}
        live.post_key("Space", True); real["held"] = True
    timing_started = False
    next_shot, next_meas, n_shot = t0 + 1.5, t0, 0
    while True:
        now = time.time()
        st = lf.lua('local rs = undertow.S.rs; return rs and (rs.mode .. "," .. string.format("%.1f", rs.dist)) or "none"')
        if st.startswith("dead") or "mode=run" not in lf.info():
            break
        if now - t0 > min_t and (name != "prog" or float(st.split(",")[1]) >= 650):
            break
        if name == "prog" and now - t0 > 240:
            break
        if real is not None:
            s = lf.lua(lf.STATE).split(",")
            hooked = s[0] == "1"
            if hooked and not real["last"]:
                real["catches"] += 1
            real["last"] = hooked
            if hooked and real["held"] and s[1] == "1":
                live.post_key("Space", False); real["held"] = False; real["releases"] += 1; real["t_rel"] = time.time()
            elif not real["held"] and time.time() - real["t_rel"] > 0.012:
                live.post_key("Space", True); real["held"] = True
        if n_shot < (0 if is_real else 10) and now >= next_shot:     # (real-input runs: no shots, they stall the driver)
            p = m.shot(d / ("f%02d.png" % n_shot))
            shots.append((round(now - t0, 2), p.name))
            n_shot += 1
            next_shot = now + 1.0
        elif n_shot >= 10 and not timing_started:
            lf.lua("undertow.timing_reset()")
            timing_started, t_timing = True, now
        if now >= next_meas:
            r = lf.lua("return __uw_measure()")
            if r and r != "-":
                meas.append(r)
            next_meas = now + 0.25
        time.sleep(0.004 if real is not None else 0.05)
    if real is not None:
        live.post_key("Space", False)
    res = {"run": name, "seconds": round(time.time() - t0, 1), "end": lf.lua("return undertow.run_info()"),
           "info": lf.lua("return undertow.info()"), "game": lf.info(),
           "timing": lf.lua("return undertow.timing()") if timing_started else "no shot-free window",
           "timing_window_s": round(time.time() - t_timing, 1) if timing_started else 0, "shots": shots, "real": real}
    rows = lf.lua("return undertow.series_read(1)").split("|")
    (d / "series.csv").write_text("t,x,z,hook,score,level,game,rules,dist,lamps,frame_ms\n" + "\n".join(rows[1:]) + "\n")
    (d / "measure.csv").write_text(MCOLS + "\n" + "\n".join(meas) + "\n")
    (d / "result.json").write_text(json.dumps(res, indent=1))
    print(json.dumps({k: res[k] for k in ("run", "seconds", "end", "timing", "real")}), flush=True)
    return res


def main():
    print(lf.lua(lf.HOOKS), lf.lua(MEASURE))
    for name in sys.argv[2:]:
        try:
            run(name)
        except Exception as e:      # noqa: BLE001
            print("run", name, "failed:", e, flush=True)
            (OUT / ("run_%s_error.txt" % name)).write_text(str(e))
    to_title()


if __name__ == "__main__":
    main()
