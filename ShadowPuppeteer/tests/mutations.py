"""Show every view_smoke.lua check failing with its feature removed (each in a temp copy of the game).

    python tests/mutations.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

GAME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUAJIT = os.path.normpath(os.path.join(GAME, "..", "..", "PhasmaEngine", "build-ninja-physics", "Release", "luajit.exe"))
WORLD = "Assets/Scripts/puppet_world.lua"
DATA = "Assets/Scripts/sp_data.lua"
GAMEF = "Assets/Scripts/puppet_game.lua"
MAINF = "Assets/Scripts/puppet.lua"
MUTATIONS = [
    ("1 shadow scale 1 % off the planar k", WORLD, "local k = W.k(ly, D.PROPS[name].y)\n    return",
     "local k = W.k(ly, D.PROPS[name].y) * 1.01\n    return", "shadow corner"),
    ("1 shadow core blended (overlaps keep only the last alpha)", WORLD, 'pcall(material.set_render_type, n, "alpha_cut")',
     'pcall(material.set_render_type, n, "alpha_blend")', "core not opaque"),
    ("1 penumbra card left behind", WORLD, 'place("N_shadowpen_" .. name .. sfx, v3(cx, cy, -D.SY + L.penumbra), v3(k, k, 1))',
     'place("N_shadowpen_" .. name .. sfx, v3(0, 0, -D.SY + L.penumbra), v3(k, k, 1))', "penumbra card does not follow"),
    ("6 slide drawn upright (the 2026-11-13 hover)", WORLD, "tilt = 90 - deg(th)", "tilt = 0", "slide pose"),
    ("6 slide drawn on the rules point, back not on the face", WORLD, "ox, oy = (p.dir or 1) * math.sin(th) * back, math.cos(th) * back", "ox, oy = 0, 0", "slide pose"),
    ("6 climb in the old pose (arms together)", WORLD, "arml, armr = 128 + 38 * s, 128 - 38 * s", "arml, armr = 150 + 22 * s, 150 - 22 * s", "do not alternate"),
    ("2 front card never shown", WORLD, "visible = W.front_on ~= false", "visible = false", "front card does not cover"),
    ("2 front-card bakes not verified opaque", DATA, "FRONT_COVERS = {", "FRONT_COVERS_UNUSED = {", "not a bake verified"),
    ("3 drag ignores the limits", WORLD, "local function clamp(v, r) return max(r[1], min(r[2], v)) end",
     "local function clamp(v, r) return v end", "limits"),
    ("4 a node made on every change", WORLD, "function W.apply()\n", "function W.apply()\n    scene.add_empty_node('leak')\n", "pools leak"),
    ("7 every prop placed, absent ones too (the 2026-11-13 startup crash)", WORLD, "local on = x ~= nil", "local on = true",
     "7. the game script failed to boot"),
    ("7 absent props asked for a place (not in the level)", WORLD, "if W.present[name] then x, z, left = W.prop_xz(name) end",
     "x, z, left = W.prop_xz(name)", "prop_xz"),  # (the title boots with no level: the first play crashes)
    ("7 a level's props never set present", WORLD, "        W.present[name] = true\n        if D.PROP_MOVE", "        if D.PROP_MOVE",
     "pressing on the comb grabs it"),
    ("8 locks ignored", GAMEF, "local function level_open(id)\n", "local function level_open(id)\n    do return true end\n", "8"),
    ("8 progress never saved", GAMEF, '    pcall(fs.write, SAVE, table.concat(t, "\\n") .. "\\n")', "", "8"),
    ("8 the rules run under the pause card", MAINF, '(live or Game.manual or Game.mode == "won" or Game.mode == "lost")', "true",
     "the rules stop while paused"),
    ("8 the title card's lines overflow at 1280x720", GAMEF, 'text(r[2], bx + 310 * u, ry, 18 * u, col4(CREAM, a), "left", 83, bw - 330 * u)',
     'text(r[2], bx + 310 * u, ry, 18 * u, col4(CREAM, a), "left", 83, bw - 630 * u)', "overflows"),
    ("8 Esc does not pause", GAMEF, 'if esc then sound("click"); open_pause()\n        elseif pressed("R") and not G.tut',
     'if false then sound("click"); open_pause()\n        elseif pressed("R") and not G.tut', "Esc pauses"),
    ('9 the guide never saved as seen', GAMEF, '    G.tut = nil\n    save.tutorial = true\n', '    G.tut = nil\n', 'the guide is saved as seen'),
    ('9 the rules run under the guide', GAMEF, 'if G.tut then tut_controls(raw); G.hold = G.tut ~= nil end', 'if G.tut then tut_controls(raw) end', 'the rules wait while the guide explains'),
    ('9 HOW TO PLAY not on the title', GAMEF, 'elseif pressed("H") or clicked("t_howto") then sound("click"); G.open_howto("title")', 'elseif false then', 'H on the title opens HOW TO PLAY'),
    ("9 a set's intro never saved", GAMEF, '        save.seen[I.map.id] = true\n', '', 'seen and saved'),
    ('9 the failed card without the hint', GAMEF, 'local hint = "Hint: " .. (lv.hint or "")', 'local hint = ""', 'failed card: cause and hint'),
    ("9 the guide shown from the console too (not only the player's own start)", GAMEF, 'if from_ui and not script then', 'if not script then', 'the puppet walks right'),
    ("9 the puppet not posed while the guide holds the rules", MAINF, "        World.pose_puppet(S.game, S.clock)         -- the rules wait", "        local _ = 0                                -- the rules wait", "drawn on its start under the guide"),
    ("4 an emitter made on every change", WORLD, "function W.apply()\n", "function W.apply()\n    particles.add_emitter({})\n", "pools leak"),
]


RULES = "Assets/Scripts/puppet_rules.lua"
# rules_test.lua: (name, file, anchor, replacement, the test that must fail)
RULE_MUTATIONS = [
    ("walk pace halved", RULES, "local nx = S.x + S.dir * r.walk * dt\n            -- a rise", "local nx = S.x + S.dir * r.walk * dt * 0.5\n            -- a rise", "walks right at a steady pace"),
    ("no step up", RULES, "local t = support(L, G, nx, S.y, r.step, 0, {", "local t = support(L, G, nx, S.y, 0, 0, {", "steps up a rise"),
    ("rises looked for behind it too", RULES, "{ nx - S.dir * hf, nx, nx + S.dir * hf, nx + S.dir * hw * 0.5, nx + S.dir * hw }", "{ nx - hw, nx, nx + hw }", "walks down a slope"),
    ("rises not looked for under the heels (summit turn)", RULES, "{ nx - S.dir * hf, nx, nx + S.dir * hf, nx + S.dir * hw * 0.5, nx + S.dir * hw }",
     "{ nx, nx + S.dir * hw * 0.5, nx + S.dir * hw }", "rounded summit"),
    ("a lifted slide turns to walk (flicker)", RULES, "if up and up > S.y and free(L, G, S.x, up, slide_cols(L, S)) then S.y = up; return end",
     "", "no walk/slide flicker"),
    ("a rise need not be a lip (ratchet up steep faces)", RULES, "if not base or t - base > r.step + EPS then t = nil end", "", "near-vertical face is a wall"),
    ("no slide re-arm time (mouse key flicker)", RULES, "local rearmed = S.t - (S.slide_end_t or -1e9) >= (r.slide_rearm or 0)",
     "local rearmed = true", "no slide/stand flicker"),
    ("a slide stands up on its own lip (double start)", RULES, "local off_lip = math.abs(S.x - (S.slide_x0 or S.x)) >= r.feet_w / 2",
     "local off_lip = true", "no walk/slide flicker"),
    ("feet wider than the shoe (0.035, before)", DATA, "feet_w = 0.02261,", "feet_w = 0.035,", "on a steep (55 degree) downhill slope"),
    ("feet narrower than the shoe (0.008)", DATA, "feet_w = 0.02261,", "feet_w = 0.008,", "on a steep (55 degree) downhill slope"),
    ("no slide (stands on any slope, 2026-11-13 hover)", DATA, "max_slope = 55.0,", "max_slope = 89.9,", "slides down a slope too steep"),
    ("slide without hysteresis (exit = 89.9 deg)", DATA, "slide_exit = 45.0,", "slide_exit = 89.9,", "never flickers back"),
    ("lips slid too (no face height)", RULES, "face_height(L, G, S.x, S.y, S.dir) >= r.step", "true", "stepped down, not slid"),
    ("slide held on the heel's corner, not the centre", RULES, "local ny = nx - hw >= L.u0 and nx + hw <= L.u1 and top(L, G, nx, S.y, EPS, r.step) or nil",
     "local ny = nx - hw >= L.u0 and nx + hw <= L.u1 and support(L, G, nx, S.y, r.step, r.step) or nil", "slides down a slope too steep"),
    ("ladder climbed where it is met, not in its middle", RULES,
     "if b and b.y1 > S.y + r.step and (abs(cx - S.x) <= r.walk * dt + EPS or (cx - S.x) * S.dir < 0) then",
     "if b and b.y1 > S.y + r.step then", "climbs a ladder shadow in its middle"),
    ("no turning", RULES, 'S.dir = -S.dir; event(S, "turn")', 'event(S, "turn")', "turns round"),
    ("no gravity (falls at full speed at once)", RULES, "S.vy = max(S.vy - r.gravity * dt, -r.fall_max)", "S.vy = -r.fall_max", "falls when unsupported"),
    ("landing checks only the end point", RULES, "support(L, G, nx, S.y, 0, S.y - ny)", "support(L, G, nx, ny, 0, 0)", "paper-thin ledge"),
    ("no ladder climbing", RULES, 'S.mode = "climb"; event(S, "climb")', 'event(S, "no climb")', "climbs a ladder"),
    ("thorns harmless", RULES, 'kill(S, "thorns"); return', "local _ = 0", "dies on thorns"),
    ("no falling off the paper", RULES, 'if S.y < r.fell_v then kill(S, "fell"); return end', "", "falling off the bottom"),
    ("no lifting", RULES, "if lift and lift > S.y and free(L, G, S.x, lift) then", "if false then", "is lifted"),
    ("no pushing", RULES, "if free(L, G, nx, S.y) then S.x = nx; return end", "", "is pushed"),
    ("never crushed", RULES, '    kill(S, "crushed")\nend', "end", "is crushed"),
    ("door does nothing", RULES, 'S.won = true; S.mode = "won"; event(S, "won")', 'event(S, "at door")', "reaching the door"),
    ("star not collected", RULES, 'S.star = true; event(S, "star")', 'event(S, "star seen")', "bonus star"),
    ("candle never runs out", RULES, 'if S.t >= (L.candle_s or r.candle_s) then kill(S, "candle"); return end', "", "candle burning down"),
    ("input held per frame, not per step", RULES, "    while S.acc >= dt - 1e-12 and steps < 240 do",
     "    local held = input(S.n * dt)\n    input = function() return held end\n    while S.acc >= dt - 1e-12 and steps < 240 do", "30, 60 and 144 fps"),
    ("shadow formula off (lantern height ignored)", RULES, "L.LZ + k * (az + q[2] - L.LZ)", "k * (az + q[2])", "vertex for vertex"),
    ("ground moving into the puppet ignored", RULES, "    resolve(L, G, S)\n    if S.dead then return end", "", "no tunnelling"),
    # the reference level's start = its LEVELS entry (props' x): moved into state A's solved bridge
    ("reference level starts solved", DATA, "comb = {\n          x = 1.1\n        },\n        cup = {\n          x = 0.3\n        },\n        ladder = {\n          x = 0.8\n",
     "comb = {\n          x = -0.4552\n        },\n        cup = {\n          x = -1.064\n        },\n        ladder = {\n          x = 0.53\n", "doing nothing loses"),
]


def run(root, test="tests/view_smoke.lua"):
    r = subprocess.run([LUAJIT, test], cwd=root, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main():
    code, out = run(GAME)
    print("unmutated:", "PASS" if code == 0 and "view_smoke: OK" in out else "FAIL\n" + out[-800:])
    bad = 0
    for name, path, a, b, expect in MUTATIONS:
        tmp = tempfile.mkdtemp(prefix="sp-mut-")
        try:
            shutil.copytree(os.path.join(GAME, "Assets", "Scripts"), os.path.join(tmp, "Assets", "Scripts"))
            shutil.copytree(os.path.join(GAME, "tests"), os.path.join(tmp, "tests"))
            p = os.path.join(tmp, path)
            src = open(p, encoding="utf-8").read()
            assert a in src, "mutation anchor missing: " + name
            open(p, "w", encoding="utf-8").write(src.replace(a, b, 1))
            code, out = run(tmp)
            failed = code != 0 and expect in out
            bad += not failed
            line = next((l for l in out.splitlines() if "view_smoke.lua:" in l and "luajit" in l), out.strip().splitlines()[-1] if out.strip() else "")
            print("%-42s %s   %s" % (name, "FAILS as it should" if failed else "DID NOT FAIL", line[-150:]))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    code, out = run(GAME, "tests/rules_test.lua")
    print("rules unmutated:", "PASS" if code == 0 and "0 failed" in out else "FAIL " + out[-800:])
    for name, path, a, b, expect in RULE_MUTATIONS:
        tmp = tempfile.mkdtemp(prefix="sp-mut-")
        try:
            shutil.copytree(os.path.join(GAME, "Assets", "Scripts"), os.path.join(tmp, "Assets", "Scripts"))
            shutil.copytree(os.path.join(GAME, "tests"), os.path.join(tmp, "tests"))
            p = os.path.join(tmp, path)
            src = open(p, encoding="utf-8").read()
            assert a in src, "mutation anchor missing: " + name
            open(p, "w", encoding="utf-8").write(src.replace(a, b, 1))
            code, out = run(tmp, "tests/rules_test.lua")
            failed = [l for l in out.splitlines() if l.startswith("FAIL")]
            hit = any(expect in l for l in failed)
            bad += not hit
            print("%-46s %s   (%d tests fail)" % (name, "FAILS as it should" if hit else "DID NOT FAIL", len(failed)))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
