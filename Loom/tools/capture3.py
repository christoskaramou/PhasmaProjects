"""Round-3 proof in the muted throwaway copy (port 8913), driven by REAL input posted to the copy's own window
(tools/input.py: PostMessage to its HWND; no SendInput, no focus). The console is used only to read state (and to
pose the look states A / B). The copy is closed at the end by its own QUIT button.

    python tools/capture3.py <out_dir>
"""
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import live  # noqa: E402
import input as inp  # noqa: E402

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
rep = {"steps": [], "series": [], "focus_taken": 0}
CONTACT = (Path(__file__).resolve().parent / "capture.py").read_text(encoding="utf-8").split('CONTACT = r"""')[1].split('"""')[0]
REF = OUT.parent / "partA"


def note(k, v):
    rep["steps"].append([k, v])
    print(k, v, flush=True)


live.start()
pid = int((live.WORK / "pid.txt").read_text())
m = live.Mcp(live.PORT).init()


def lua(code):
    return m.lua(code)


w = None


def guard(dst):
    """Loom's look (targets, backdrop) or, for play frames with no staged target, the run's own HUD chip bar."""
    if live.is_loom(dst):
        return True
    hud = OUT / "hud_2560.png"
    return hud.exists() and live.similar(dst, hud, (0.0, 0.86, 1.0, 1.0))


class FrameKeys:
    """Keys held until the game has drawn two frames (its own frame counter), then released and one more frame
    awaited: a fixed hold shorter than a frame lost keys when the GPU was busy (another agent's Player running)."""
    def __init__(self, win):
        self.w = win

    def frames(self):
        return int(float(lua("return loom.S.frames")))

    def key(self, name, hold=None):
        f0 = self.frames()
        self.w.down(name)
        t0 = time.time()
        while self.frames() < f0 + 2 and time.time() - t0 < 2.0:
            time.sleep(0.01)
        self.w.up(name)
        f1 = self.frames()
        while self.frames() < f1 + 1 and time.time() - t0 < 3.0:
            time.sleep(0.01)

    def click(self, x, y):
        self.w.click(x, y)

    def foreground_is_mine(self):
        return self.w.foreground_is_mine()

    @property
    def sent(self):
        return self.w.sent


def shot(name, ref=None):
    ref = ref or guard
    p = OUT / (name + ".png")
    m.shot(p, ref=ref)
    if w.foreground_is_mine():
        rep["focus_taken"] += 1
    return p


def info():
    return lua("return loom.G.info()")


def rect_click(rid):
    r = json.loads(lua("local r = loom.G.rects['%s']; if not r then return 'null' end; "
                       "return string.format('{\"x\":%%f,\"y\":%%f,\"w\":%%f,\"h\":%%f}', r.x, r.y, r.w, r.h)" % rid))
    if not r:
        raise RuntimeError("no rect " + rid)
    w.click(r["x"] + r["w"] / 2, r["y"] + r["h"] / 2)


def wait_mode(mode, t=4.0):
    t0 = time.time()
    while time.time() - t0 < t:
        if lua("return loom.G.mode") == mode:
            return True
        time.sleep(0.2)
    return False


def poll(code, want, t=0.8):
    t0 = time.time()
    v = None
    while time.time() - t0 < t:
        v = lua(code)
        if want(v):
            return v
        time.sleep(0.03)
    return v


def weave_row_by_keys(careless=False):
    """Plan the row with the rules' weaver (read only: its RNG is restored), then lay it with real keys: Left/Right to
    the cell, then its number. Each key's effect is awaited before the next (a posted key is handled on a later frame)."""
    plan = [] if careless else json.loads(lua(
        "local st = loom.S.st; local g0 = st.g.s; local plan = loom.R.bot_row(st); st.g.s = g0; "
        "local t = {} for _, p in ipairs(plan) do t[#t+1] = string.format('[%d,%d]', p.c, p.i) end return '[' .. table.concat(t, ',') .. ']'"))
    for c, i in plan:
        for _ in range(9):
            cur = int(float(lua("return loom.S.st.cursor")))
            if cur == c:
                break
            w.key("Right" if c > cur else "Left", hold=0.04)
            poll("return loom.S.st.cursor", lambda v, cur=cur: int(float(v)) != cur)
        before = lua("return tostring(loom.S.st.cur[%d])" % c)
        w.key(str(i), hold=0.04)
        poll("return tostring(loom.S.st.cur[%d]) .. ' ' .. tostring(loom.G.msg)" % c, lambda v, b=before: v.split(" ")[0] != b, 0.6)
    k0 = lua("return loom.S.st.K")
    w.key("Space", hold=0.05)
    got = poll("return loom.S.st.K", lambda v: v != k0, 1.5)
    if got == k0:
        rep["steps"].append(["beat refused", lua("return tostring(loom.G.msg)")])
        lua("return 1")
        # the clock's own beat (auto) is the rules' way out of an illegal row: wait for it would take 45 s; press Space
        # again after clearing the last pick with Backspace
        w.key("Backspace", hold=0.05)
        w.key("Space", hold=0.05)
        poll("return loom.S.st.K", lambda v: v != k0, 1.5)


try:
    w = FrameKeys(inp.Win(pid))
    lua("engine.set_background_fps_cap(false); return 1")
    live.size(2560, 1369)
    time.sleep(2.0)
    note("surface", lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height"))
    note("foreground is the copy at start", w.foreground_is_mine())
    # ---- (b) the flow with real input
    time.sleep(1.0)
    shot("title_2560")
    w.key("Escape"); time.sleep(0.8)
    note("Esc on title -> pause", info())
    shot("pause_title_2560")
    w.key("Escape"); time.sleep(0.6)
    rect_click("t_settings"); time.sleep(1.0)
    note("click SETTINGS", lua("return tostring(loom.G.settings:is_open())"))
    shot("settings_2560", ref=REF / "settings_2560.png")
    w.key("Escape"); time.sleep(0.8)
    note("Esc in settings -> back to title", lua("return tostring(loom.G.settings:is_open()) .. ' ' .. loom.G.mode"))
    mute0 = lua("return tostring(loom.G.settings:get('mute'))")
    w.key("M"); time.sleep(0.4)
    mute1 = lua("return tostring(loom.G.settings:get('mute'))")
    w.key("M"); time.sleep(0.4)
    note("M toggles mute (master volume stays 0)", "%s -> %s -> %s" % (mute0, mute1, lua("return tostring(loom.G.settings:get('mute'))")))
    rect_click("t_play"); time.sleep(1.2)
    note("click PLAY", info())
    weave_row_by_keys(); time.sleep(1.5)
    shot("hud_2560")
    w.key("Escape"); time.sleep(0.8)
    note("Esc in run -> pause", info())
    shot("pause_run_2560")
    rect_click("pz_settings"); time.sleep(1.0)
    note("pause SETTINGS", lua("return tostring(loom.G.settings:is_open())"))
    w.key("Escape"); time.sleep(0.8)
    note("settings BACK -> pause", info())
    rect_click("pz_resume"); time.sleep(0.8)
    note("RESUME", info())
    # ---- (c) one long run through the levels: real keys, a shot every ~2.5 s, state logged
    lua("loom.timing_reset(); return 1")
    t0 = time.time()
    k = 0
    next_shot = t0
    levels = set()
    while True:
        st = lua("local st = loom.S.st; return string.format('%d %d %d %d %d %s', st.K, st.level, st.walked, st.score, st.trav.c, tostring(st.over))").split()
        levels.add(int(st[1]))
        if st[5] != "nil" or int(st[1]) >= 5 and time.time() - t0 > 70:
            break
        if time.time() - t0 > 400:
            break
        weave_row_by_keys()
        if time.time() >= next_shot:
            name = "series_%02d" % k
            shot(name, ref=(OUT / "hud_2560.png", (0.0, 0.86, 1.0, 1.0)))     # play frames: the run's own chip bar
            row = lua("local st = loom.S.st; local m = engine.get_metrics(); return string.format('t=%.1f K=%d level=%d trav=%d,%d walked=%d score=%d timer=%.1f over=%s dt_ms=%.2f', "
                      "loom.S.t, st.K, st.level, st.trav.c, st.trav.k, st.walked, st.score, st.timer, tostring(st.over), m.delta_ms)")
            contact = lua(CONTACT)
            rep["series"].append({"shot": name, "wall": round(time.time() - t0, 1), "state": row, "contact": contact})
            print(name, row, contact, flush=True)
            k += 1
            next_shot += 2.5
    rep["levels_reached"] = sorted(levels)
    rep["timing_run"] = lua("return loom.timing()")
    note("run ended at", lua("local st = loom.S.st; return string.format('K=%d level=%d walked=%d score=%d over=%s', st.K, st.level, st.walked, st.score, tostring(st.over))") + " wall=%.0fs" % (time.time() - t0))
    # the beat frame pair: just before and during a beat, the bottom of the frame (the beam is below it)
    HUDREF = (OUT / "hud_2560.png", (0.0, 0.86, 1.0, 1.0))
    shot("beat_before", ref=HUDREF)
    weave_row_by_keys(); time.sleep(0.12)
    shot("beat_during", ref=HUDREF)
    time.sleep(1.5)
    shot("beat_after", ref=HUDREF)
    import subprocess as _sp

    def contention():
        others = [l for l in _sp.run(["tasklist", "/FI", "IMAGENAME eq PhasmaPlayer.exe", "/FO", "CSV"], capture_output=True, text=True).stdout.splitlines()[1:]
                  if '"%d"' % pid not in l]
        smi = _sp.run(["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader"], capture_output=True, text=True).stdout.strip()
        apps = _sp.run(["nvidia-smi", "--query-compute-apps=process_name", "--format=csv,noheader"], capture_output=True, text=True).stdout.split()
        return {"other_players": others, "gpu_util_before": smi, "gpu_apps": [a.split("\\")[-1] for a in apps if a.strip()]}
    rep["contention_before_quiet_timing"] = contention()
    lua("loom.timing_reset(); return 1")
    time.sleep(10.0)
    rep["timing_quiet"] = lua("return loom.timing()")
    # game over by a careless row (Space on an empty row), RETRY by click, BACK TO MENU, then the unlock and QUIT
    weave_row_by_keys(careless=True)
    wait_mode("over", 6.0)
    note("careless row -> game over", info())
    shot("over_2560")
    time.sleep(0.5)
    rect_click("o_retry"); time.sleep(1.2)
    note("click RETRY", info())
    w.key("9"); time.sleep(0.4)
    note("house unlock: key 9 in the new run", lua("local st = loom.S.st; local h = 0 for c = 0, 8 do if st.cur[c] == 'H' then h = h + 1 end end return 'village=' .. tostring(st.village) .. ' houses laid=' .. h"))
    w.key("Escape"); time.sleep(0.8)
    rect_click("pz_menu"); time.sleep(1.2)
    note("BACK TO MENU", info())
    shot("title_unlocked_2560")
    # the look states (console: poses only)
    for s_ in ("A", "B"):
        lua("return loom.state('%s')" % s_)
        time.sleep(3.0)
        shot("state_" + s_)
    lua("loom.game_mode(); return 1")
    time.sleep(1.0)
    # every card at 1280x720
    live.size(1280, 720)
    time.sleep(2.0)
    note("surface", lua("local s = runtime_ui.get_surface_size(); return s.width .. 'x' .. s.height"))
    shot("title_1280")
    w.key("Escape"); time.sleep(0.8); shot("pause_title_1280"); w.key("Escape"); time.sleep(0.6)
    rect_click("t_settings"); time.sleep(1.0); shot("settings_1280", ref=REF / "settings_1280.png"); w.key("Escape"); time.sleep(0.8)
    rect_click("t_play"); time.sleep(1.2); weave_row_by_keys(); time.sleep(1.5); shot("hud_1280")
    w.key("Escape"); time.sleep(0.8); shot("pause_run_1280"); rect_click("pz_resume"); time.sleep(0.6)
    weave_row_by_keys(careless=True); wait_mode("over", 6.0); time.sleep(0.6); shot("over_1280")
    w.key("Escape"); time.sleep(1.2)
    note("Esc on game over -> menu", info())
    live.size(2560, 1369)
    time.sleep(1.5)
    rep["info"] = lua("return loom.info()")
    note("foreground is the copy at end", w.foreground_is_mine())
    rect_click("t_quit")
    time.sleep(3.0)
finally:
    import subprocess
    alive = str(pid) in subprocess.run(["tasklist", "/FI", "PID eq %d" % pid], capture_output=True, text=True).stdout
    rep["quit_closed_the_copy"] = not alive
    if alive:
        live.stop()
log = live.WORK / "rt" / "PhasmaEngine.log"
lines = [ln.rstrip() for ln in open(log, encoding="utf-8", errors="replace") if "WARN" in ln or "ERROR" in ln or "rror" in ln]
rep["log_warnings_errors"] = sorted(set(lines))[:60]
rep["posted_messages"] = w.sent if w else 0
(OUT / "capture.json").write_text(json.dumps(rep, indent=1))
print(json.dumps({k: v for k, v in rep.items() if k not in ("series", "steps")}, indent=1))
