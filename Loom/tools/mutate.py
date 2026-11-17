"""Show each test failing with its feature removed: copy Loom's scripts and tests to %TEMP%/loom_mut, break one
feature at a time (a string replacement), run the test that guards it, and report the checks that failed.

    python tools/mutate.py            (needs the engine's luajit.exe)
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LJ = ROOT.parent.parent / "PhasmaEngine" / "build-ninja-physics" / "Release" / "luajit.exe"
WORK = Path(tempfile.gettempdir()) / "loom_mut"
S = "Assets/Scripts/"
# (name, file, old, new, test)
MUT = [
    ("laying spends no wool", S + "loom_rules.lua", "st.wool[d.wool] = st.wool[d.wool] - d.cost\n", "\n", "rules"),
    ("the broken path never ends the run", S + "loom_rules.lua", '        st.over = "break"\n', "\n", "rules"),
    ("cells pay every time", S + "loom_rules.lua", "                st.harvested[id] = true\n", "\n", "rules"),
    ("no auto-beat on the clock", S + "loom_rules.lua", "    if st.timer <= 0 then R.beat(st, true) end", "    if false then R.beat(st, true) end", "rules"),
    ("bridges need no river", S + "loom_rules.lua", '        if not bk then return false, "a bridge needs river beside it (or behind it)" end', "", "rules"),
    ("no forced rivers", S + "loom_rules.lua", '        for c = 0, R.COLS - 1 do st.forced[c] = "~" end\n', "\n", "rules"),
    ("Lua blob key ignores the both-orthogonals rule", S + "loom_rules.lua", "is(1, 1) and n and e", "is(1, 1)", "rules"),
    ("no Scene Settings node", S + "loom_world.lua", 'W.settings_node = scene.add_empty_node("Scene Settings")', 'W.settings_node = {}', "view"),
    ("rolled rows drawn flat", S + "loom_world.lua", "local rolled = r >= ROWS_FLAT and not (r == ROWS_FLAT and s < 1)", "local rolled = false", "view"),
    ("traveller ignores the cloth height", S + "loom_world.lua", "local zg = name and W.ground(name, tw.u, tw.v, 0.23) or 0", "local zg = 0", "view"),
    ("houses at the bilinear height, not the footprint's top", S + "loom_world.lua", "local zg = W.ground(name, 0, 0, 0.36)", "local zg = W.ground(name, 0, 0)", "view"),
    ("rules let the traveller cross an E-W bridge sideways", S + "loom_rules.lua", "b = { n = true, s = true }, B = { e = true, w = true },",
     "b = { n = true, s = true, e = true, w = true }, B = { e = true, w = true },", "view"),
    ("the traveller cuts corners (straight to the cell centre)", S + "loom_world.lua", "    if pl then\n        local n = #pl", "    if false then\n        local n = #pl", "view"),
    ("Esc does not pause", "Assets/Scripts/loom_game.lua", "        if G.mode == \"over\" then to_title() else open_pause() end", "        if G.mode == \"over\" then to_title() end", "view"),
    ("pause does not stop the clock", "Assets/Scripts/loom_game.lua", "    if not paused then L.play_frame(raw) end", "    L.play_frame(raw)", "view"),
    ("lone ponds allowed", S + "loom_rules.lua", 'if d.k == "~" and not R.water_joins(st, c, true) then', 'if false then', "rules"),
    ("orphan water accepted at the beat", S + "loom_rules.lua", 'if st.cur[c] == "~" and not st.forced[c] and not R.water_joins(st, c) then', 'if false then', "rules"),
    ("the pattern brings no hills", S + "loom_rules.lua", "    if st.hillrun then\n        local h = st.hillrun", "    if false then\n        local h = st.hillrun", "rules"),
    ("forced hills may block the path's head", S + "loom_rules.lua",
     "local function free(c) return c >= 0 and c < R.COLS and not st.forced[c] and not walkable(cell(st, c, st.K)) end",
     "local function free(c) return c >= 0 and c < R.COLS and not st.forced[c] end", "rules"),
    ("HUD chip wool text too small", "Assets/Scripts/loom_game.lua", "text(sub, x + 30 * u, y0 + 66 * u, 19 * u,", "text(sub, x + 30 * u, y0 + 66 * u, 12 * u,", "view"),
    ("the pattern's river is a straight full row again", S + "loom_rules.lua",
     'for c = 0, R.COLS - 1 do if (west and c <= j) or (not west and c >= j) then st.forced[c] = "~" end end',
     'for c = 0, R.COLS - 1 do st.forced[c] = "~" end', "rules"),
    ("the crossing's bend may stand before the path's head", S + "loom_rules.lua",
     "            if not walkable(cell(st, c, st.K)) then j = c end", "            j = c", "rules"),
    ("straight river cells do not meander", S + "loom_rules.lua",
     'if arms == "ns" and (row or r) % 2 == 1 then arms = "ns2" elseif arms == "ew" and c % 2 == 1 then arms = "ew2" end', "", "rules"),
    ("no save on game over", "Assets/Scripts/loom_game.lua", "    write_save()\nend\n\nlocal KIND_WORD", "end\n\nlocal KIND_WORD", "view"),
]


def copy():
    if WORK.exists():
        shutil.rmtree(WORK)
    shutil.copytree(ROOT / "Assets" / "Scripts", WORK / "Assets" / "Scripts")
    shutil.copytree(ROOT / "tests", WORK / "tests")


def run(test):
    f = "tests/rules_test.lua" if test == "rules" else "tests/view_smoke.lua"
    r = subprocess.run([str(LJ), f], cwd=WORK, capture_output=True, text=True, timeout=600)
    return r.returncode, [ln for ln in (r.stdout + r.stderr).splitlines() if ln.startswith("FAIL") or "rror" in ln]


def main():
    copy()
    for t in ("rules", "view"):
        code, fails = run(t)
        print("baseline %-5s exit %d %s" % (t, code, fails[:2]))
        if code != 0:
            raise SystemExit("baseline fails: fix the tests first")
    bad = 0
    for name, path, old, new, test in MUT:
        copy()
        p = WORK / path
        s = p.read_text(encoding="utf-8")
        if old not in s:
            print("SKIP (pattern not found):", name)
            bad += 1
            continue
        p.write_text(s.replace(old, new, 1), encoding="utf-8")
        code, fails = run(test)
        ok = code != 0
        bad += 0 if ok else 1
        print("%s  %-55s %s" % ("caught" if ok else "MISSED", name, fails[0][:120] if fails else ""))
    shutil.rmtree(WORK)
    print("all mutations caught" if bad == 0 else "%d mutations not caught" % bad)


if __name__ == "__main__":
    main()
