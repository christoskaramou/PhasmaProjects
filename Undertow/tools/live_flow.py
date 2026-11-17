"""Walk Undertow's whole flow in the throwaway Player with REAL input posted to its window (tools/live.py: WM_KEYDOWN /
WM_MOUSE* to the copy's HWND only; never SendInput, never focus). Start the copy first: python tools/live.py start.

    python tools/live.py start && python tools/live_flow.py <out_dir> [w h]

Title -> M mute -> SETTINGS -> BACK -> PLAY -> play with Space -> Esc pause -> SETTINGS -> BACK -> RESUME -> death ->
game-over -> RETRY -> death -> BACK TO MENU -> (one autoplay run through the game's own input path for the glass
unlock) -> GLASS -> QUIT. Buttons are found by their label from the quads the game draws (runtime_ui.set_quad is
wrapped from the console; the scripts are not edited). Sound calls are logged by wrapping audio.play / play_music.
Every screenshot is copied out of %TEMP% at once and checked with is_undertow (live.Mcp.shot)."""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import live  # noqa: E402

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
LOG = []
m = live.Mcp(live.PORT).init()


def log(*a):
    s = " ".join(str(x) for x in a)
    LOG.append("%.2f %s" % (time.time() - T0, s))
    print(LOG[-1], flush=True)


T0 = time.time()
HOOKS = r'''
_G.__labels, _G.__sounds, _G.__vol = _G.__labels or {}, _G.__sounds or {}, _G.__vol or {}
if not _G.__uw_sq then
  _G.__uw_sq = runtime_ui.set_quad
  local ap, am, mv = audio.play, audio.play_music, audio.set_master_volume
  audio.play = function(n, ...) __sounds[#__sounds + 1] = "play:" .. tostring(n); return ap(n, ...) end
  audio.play_music = function(n, ...) __sounds[#__sounds + 1] = "music:" .. tostring(n); return am(n, ...) end
  audio.set_master_volume = function(v, ...) __vol[#__vol + 1] = v; return mv(v, ...) end
end
local inner = _G.__uw_sq
runtime_ui.set_quad = function(scr, id, o)
  local r = inner(scr, id, o)
  if o and o.label and o.label ~= "" and o.visible ~= false then
    local lab = o.label:gsub("^> ", "")
    __labels[lab] = { o.x, o.y, o.width or o.w, o.height or o.h, scr, id }
  elseif o then
    for k, v in pairs(__labels) do if v[5] == scr and v[6] == id then __labels[k] = nil end end
  end
  return r
end
return "hooked"
'''


def lua(code):
    return m.lua(code)


def info():
    return lua("return undertow.G.info()")


def find(label):
    r = lua('local v = __labels[%s]; if not v then return "" end; return string.format("%%.1f,%%.1f,%%.1f,%%.1f", v[1], v[2], v[3], v[4])'
            % json.dumps(label))
    if not r or r.count(",") != 3:
        return None
    x, y, w, h = map(float, r.split(","))
    return x + w / 2, y + h / 2


def click(label, wait=0.6):
    p = None
    for _ in range(20):
        p = find(label)
        if p:
            break
        time.sleep(0.15)
    if not p:
        raise RuntimeError("no button labelled %r on screen" % label)
    live.click(p[0], p[1])
    log("click", label, "at %.0f,%.0f" % p)
    time.sleep(wait)


def key(name, wait=0.4):
    live.post_key(name, True)
    time.sleep(0.12)
    live.post_key(name, False)
    log("key", name)
    time.sleep(wait)


def shot(name, scene=True):
    """scene=False: a full-screen card hides the scene, so only the copy's own marker guards it (no is_undertow)."""
    p = m.shot(OUT / name, check=scene)
    log("shot", p.name, "(marker + is_undertow)" if scene else "(marker)")
    return p


def wait_for(pred, timeout, what):
    t = time.time()
    while time.time() - t < timeout:
        i = info()
        if pred(i):
            return i
        time.sleep(0.2)
    raise RuntimeError("timeout waiting for %s: %s" % (what, info()))


# The decision a careful player makes, read from the game each poll: is the float hooked, and would letting go now
# carry it to the next hook alive (the rules' own look-ahead, uw_bot rollout)? The key itself is posted to the window.
STATE = '''local rs = undertow.S.rs; if not rs then return "none" end
local ok = "0"
if rs.hook and not rs.slack and rs.om > 0 and rs.mode ~= "dead" then
  local R = undertow.Bot._rollout     -- robust to the post latency: releasing 2, 5 or 8 steps from now all land
  if R(rs, rs.steps + 2, 7.5) and R(rs, rs.steps + 5, 7.5) and R(rs, rs.steps + 8, 7.5) then ok = "1" end
end
return string.format("%s,%s,%s,%.2f,%s", rs.hook and "1" or "0", ok, rs.mode, rs.x, tostring(rs.score))'''


def play_with_space(seconds):
    """Real-input play (posted WM_KEYDOWN/UP of Space): hold; let go when the look-ahead says the release lands on the
    next hook; press again at once (the hold catches the nearest lamp hook ahead in reach). Returns catches, releases."""
    held, catches, releases = False, 0, 0
    last_hooked, t_rel = False, 0
    live.post_key("Space", True); held = True
    t_end = time.time() + seconds
    st = None
    while time.time() < t_end:
        st = lua(STATE).split(",")
        if st[0] == "none" or st[2] == "dead":
            break
        hooked = st[0] == "1"
        if hooked and not last_hooked:
            catches += 1
        last_hooked = hooked
        if hooked and held and st[1] == "1":
            live.post_key("Space", False); held = False; releases += 1; t_rel = time.time()
        elif not held and time.time() - t_rel > 0.012:
            live.post_key("Space", True); held = True
        time.sleep(0.004)
    return catches, releases, st


def main():
    w, h = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (1280, 720)
    log("window client", live.size(w, h))
    time.sleep(1.0)
    log(lua(HOOKS))
    cfg = live.WORK / "game" / "Assets" / "Save" / "settings.cfg"
    log("title:", info())
    shot("01_title.png")
    # M mute (the copy is muted already: master=0, so both states are silent)
    before = cfg.read_text()
    key("M")
    log("after M settings.cfg mute line:", [l for l in cfg.read_text().splitlines() if l.startswith("mute")], "was",
        [l for l in before.splitlines() if l.startswith("mute")], "master volume calls", lua('return table.concat(__vol, ",")'))
    key("M")
    log("after 2nd M:", [l for l in cfg.read_text().splitlines() if l.startswith(("mute", "master"))])
    click("SETTINGS")
    log("settings open:", info())
    shot("02_settings_from_title.png", False)
    click("BACK")
    log("settings closed:", info())
    click("PLAY")
    i = wait_for(lambda s: "mode=run" in s, 5, "run")
    log("run started:", i)
    shot("03_hud_waiting.png")
    lua("undertow.series_start(0.25)")
    c, r, st = play_with_space(20)
    log("real-input play 20 s: catches", c, "releases", r, "state", st)
    shot("04_play.png")
    live.post_key("Space", False)
    # pause card, settings from pause, back, resume
    live.post_key("Space", True)
    key("Escape", 0.6)
    i = info()
    log("Esc:", i)
    shot("05_pause.png", False)
    click("SETTINGS")
    log("settings from pause:", info())
    shot("06_settings_from_pause.png", False)
    click("BACK")
    log("back:", info())
    click("RESUME")
    log("resume:", info())
    # death: let go and never press again (the float falls into the sea or a hazard)
    live.post_key("Space", False)
    i = wait_for(lambda s: "mode=over" in s, 30, "game over")
    log("over:", i)
    time.sleep(0.8)
    shot("07_game_over.png", False)
    click("RETRY")
    i = wait_for(lambda s: "mode=run" in s, 5, "retry run")
    log("retry:", i)
    c2, r2, st2 = play_with_space(8)
    log("second run 8 s: catches", c2, "releases", r2)
    live.post_key("Space", False)
    i = wait_for(lambda s: "mode=over" in s, 30, "game over 2")
    log("over 2:", i)
    time.sleep(0.8)
    click("BACK TO MENU")
    i = wait_for(lambda s: "mode=title" in s, 5, "title")
    log("back to menu:", i)
    # glass unlock: one autoplay run (the game's own input function, G.auto) until the best passes 400
    lua("undertow.G.auto = true")
    click("PLAY")
    t = time.time()
    while time.time() - t < 120:
        sc = lua("local rs = undertow.S.rs; return tostring(rs and rs.score or 0)")
        if float(sc) >= 430:
            break
        time.sleep(0.5)
    lua("undertow.G.auto = nil")
    log("autoplay score", sc, info())
    i = wait_for(lambda s: "mode=over" in s, 40, "game over 3")
    log("over 3 (unlock):", i)
    time.sleep(0.8)
    shot("08_game_over_unlock.png", False)
    click("BACK TO MENU")
    wait_for(lambda s: "mode=title" in s, 5, "title 2")
    glass = [k for k in lua('local t = {}; for k in pairs(__labels) do t[#t+1] = k end; return table.concat(t, "|")').split("|") if k.startswith("GLASS")]
    log("glass button:", glass)
    click(glass[0])
    log("after GLASS:", info(), "save:", (live.WORK / "game" / "Assets" / "Save" / "undertow.txt").read_text().replace("\n", " "))
    shot("09_title_glass.png")
    log("sounds logged:", lua('return #__sounds .. " | " .. table.concat(__sounds, ",", math.max(1, #__sounds - 40))'))
    log("series rows:", lua("return undertow.series_read(1)")[:20000])
    # QUIT
    pid = int((live.WORK / "pid.txt").read_text())
    click("QUIT", 2.0)
    import subprocess
    alive = str(pid) in subprocess.run(["tasklist", "/FI", "PID eq %d" % pid], capture_output=True, text=True).stdout
    log("after QUIT, player pid", pid, "alive:", alive)
    (OUT / "flow_log.txt").write_text("\n".join(LOG) + "\n")


if __name__ == "__main__":
    try:
        main()
    finally:
        (OUT / "flow_log.txt").write_text("\n".join(LOG) + "\n")
