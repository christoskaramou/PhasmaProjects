"""Proof captures in the muted throwaway copy (port 8913), then the copy is closed.

    python tools/capture.py <out_dir> [series_seconds]

Cards (title, pause, settings, HUD, game over) at 2560x1369 (maximised) and 1280x720; state A and B; a play time series
(a row woven every ~3 s by the rules' weaver through the console, a screenshot every 2.5 s, rules state logged), a game
over and a retry; frame time in focus; prop / traveller contact with the drawn cloth; the log's warnings and errors.
"""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import live  # noqa: E402

OUT = Path(sys.argv[1])
SERIES = float(sys.argv[2]) if len(sys.argv) > 2 else 66.0
OUT.mkdir(parents=True, exist_ok=True)
rep = {"series": []}

CONTACT = r"""
local W, S, D, R = loom.W, loom.S, loom.D, loom.R
local st = S.st
local out, worst = {}, 0
local function gy(n) local ok, p = pcall(function() return n:get_position() end); if ok and p then return p.y end end
-- traveller: engine height of its node vs the measured cloth under its footprint
local tp = W.trav_pos
if tp and tp.name then
  local y = gy(W.trav)
  local tw = S.walk
  local want = D.Z0 + W.ground(tp.name, tw.u, tw.v, 0.23) - 0.0006 + (tw.bob or 0)
  if y then worst = math.max(worst, math.abs(y - want)); out[#out+1] = string.format('trav dz=%.5f', y - want) end
end
local n = 0
for r = 0, D.ROWS_FLAT - 1 do for c = 0, D.COLS - 1 do
  local p = W.props[r][c]
  if p.on then
    local kind = R.grid_fn(st)(r, c)
    local name = W.cells[r][c].mesh
    local want
    if kind == 'H' then want = D.Z0 + W.ground(name, 0, 0, 0.36) - 0.0005
    elseif kind == 'b' then want = D.Z0 + math.min(W.ground(name, 0, 0.47), W.ground(name, 0, -0.47)) - 0.0008
    elseif kind == 'B' then want = D.Z0 + math.min(W.ground(name, 0.47, 0), W.ground(name, -0.47, 0)) - 0.0008 end
    local y = gy(p.n)
    if want and y then worst = math.max(worst, math.abs(y - want)); n = n + 1 end
  end
end end
return string.format('props=%d worst_dz=%.6f %s', n, worst, table.concat(out, ' '))
"""


REF = OUT.parent / "partA"


def shot(m, name):
    p = OUT / (name + ".png")
    ref = REF / (name + ".png") if name.startswith("settings_") and (REF / (name + ".png")).exists() else None
    m.shot(p, ref=ref)
    return str(p)


live.start()
try:
    m = live.Mcp(live.PORT).init()
    m.lua("engine.set_background_fps_cap(false); return 'cap off'")
    for size, tag in (((0, 0), "2560"), ((1280, 720), "1280")):
        live.size(*size)
        time.sleep(2.0)
        rep["surface_" + tag] = m.lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height")
        m.lua("loom.game_mode(); return 1")
        time.sleep(2.5)
        shot(m, "title_" + tag)
        m.lua("loom.G.keys({'Escape'}); return 1"); time.sleep(1.0)
        shot(m, "pause_title_" + tag)
        m.lua("loom.G.close_pause(); loom.G.settings:open(function() end); return 1"); time.sleep(1.0)
        shot(m, "settings_" + tag)
        m.lua("loom.G.settings:close(); return 1"); time.sleep(0.6)
        m.lua("loom.G.start_run(41); return 1"); time.sleep(1.5)
        m.lua("local st = loom.S.st; loom.R.lay(st, st.cursor, 2); st.cursor = 3; return 1"); time.sleep(0.8)
        shot(m, "hud_" + tag)
        m.lua("loom.G.keys({'Escape'}); return 1"); time.sleep(1.0)
        shot(m, "pause_run_" + tag)
        m.lua("loom.G.close_pause(); return 1"); time.sleep(0.3)
        # a careless row: the path breaks -> game over card
        m.lua("local st = loom.S.st; for c = 0, 8 do st.cur[c] = st.forced[c] end; st.order = {}; loom.G.keys({'Space'}); return 1")
        time.sleep(3.5)
        rep["over_" + tag] = m.lua("return loom.G.info()")
        shot(m, "over_" + tag)
    live.size(0, 0)
    time.sleep(2.0)
    for st in ("A", "B"):
        m.lua("return loom.state('%s')" % st)
        time.sleep(3.0)
        shot(m, "state_" + st)
    # the play series: a run, a row every ~3 s woven by the rules' weaver, a shot every 2.5 s
    m.lua("loom.game_mode(); loom.G.start_run(77); return 1")
    time.sleep(1.0)
    m.lua("loom.timing_reset(); return 1")
    t0 = time.time()
    k = 0
    next_row = t0 + 1.0
    while time.time() - t0 < SERIES:
        if time.time() >= next_row:
            m.lua("local st = loom.S.st; if not st.over then for _, p in ipairs(loom.R.bot_row(st)) do loom.R.lay(st, p.c, p.i) end; st.cursor = 0; loom.G.keys({'Space'}) end; return 1")
            next_row += 3.0
        name = "series_%02d" % k
        shot(m, name)
        info = m.lua("local st = loom.S.st; return string.format('t=%.1f K=%d trav=%d,%d phase=%s walked=%d score=%d timer=%.1f over=%s wool=%d/%d/%d/%d/%d/%d/%d', "
                     "loom.S.t, st.K, st.trav.c, st.trav.k, loom.S.phase, st.walked, st.score, st.timer, tostring(st.over), st.wool.sage, st.wool.indigo, "
                     "st.wool.tan, st.wool.brown, st.wool.ochre, st.wool.grey, st.wool.cream)")
        contact = m.lua(CONTACT)
        rep["series"].append({"shot": name, "wall": round(time.time() - t0, 2), "info": info, "contact": contact})
        print(name, info, contact, flush=True)
        k += 1
        time.sleep(max(0.0, t0 + k * 2.5 - time.time()))
    rep["timing_series"] = m.lua("return loom.timing()")
    # frame time, nothing polled meanwhile
    m.lua("loom.timing_reset(); return 1")
    time.sleep(10.0)
    rep["timing_quiet"] = m.lua("return loom.timing()")
    # end this run: game over, then RETRY
    m.lua("local st = loom.S.st; for c = 0, 8 do st.cur[c] = st.forced[c] end; st.order = {}; loom.G.keys({'Space'}); return 1")
    time.sleep(3.5)
    rep["series_over"] = m.lua("return loom.G.info()")
    shot(m, "series_over")
    m.lua("loom.G.keys({'Return'}); return 1")
    time.sleep(1.5)
    rep["retry"] = m.lua("return loom.G.info()")
    shot(m, "retry")
    rep["info"] = m.lua("return loom.info()")
finally:
    live.stop()
log = live.WORK / "rt" / "PhasmaEngine.log"
lines = [ln.rstrip() for ln in open(log, encoding="utf-8", errors="replace") if "WARN" in ln or "ERROR" in ln or "rror" in ln]
rep["log_warnings_errors"] = sorted(set(lines))[:60]
(OUT / "capture.json").write_text(json.dumps(rep, indent=1))
print(json.dumps({k: v for k, v in rep.items() if k != "series"}, indent=1))
