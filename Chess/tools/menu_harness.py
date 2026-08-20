"""Click real menu rows without a mouse.

runtime_ui.get_state is a shared table function, like input.* and audio.*: wrapping it to
report `clicked` for ONE id for ONE frame drives the actual button path in menu.lua, so the
whole action-dispatch chain in menu_frame runs for real. The OS cursor is never touched.
"""
import json, sys, time, urllib.request

URL = "http://127.0.0.1:8765/tool"

def lua(code):
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps({"name": "execute_lua", "arguments": {"code": code}}).encode(),
        headers={"Content-Type": "application/json"}), timeout=60).read().decode())
    if r.get("isError"):
        raise SystemExit(json.dumps(r)[:700])
    return (r.get("structuredContent") or {}).get("output", "")

INSTALL = r"""
if not _G.__mc then
    _G.__mc = {real = runtime_ui.get_state, id = nil}
    runtime_ui.get_state = function(screen, id)
        local st = _G.__mc.real(screen, id) or {}
        if _G.__mc.id == id then
            _G.__mc.id = nil          -- exactly one frame, or the handler re-fires
            st.clicked = true
        end
        return st
    end
end
return "installed"
"""

RESTORE = r"""
if _G.__mc then runtime_ui.get_state = _G.__mc.real; _G.__mc = nil end
return "restored"
"""

def board_is_drawn():
    """Sample the centre of two squares that must differ in colour.

    Asserting a widget EXISTS proves nothing about whether it RENDERS -- the 2D board once
    came back from a view switch with every square hidden and only the pieces showing, and
    every widget-level check still passed. Light d4 vs dark e4 is the cheapest pixel proof
    that the checkerboard is actually on screen.
    """
    from PIL import Image
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps({"name": "take_screenshot", "arguments": {}}).encode(),
        headers={"Content-Type": "application/json"}), timeout=40).read().decode())
    path = r["structuredContent"]["path"]
    # b3/a3: EMPTY squares (a piece would be sampled instead of the square) on the far left
    # (the menu panel is centred and covers the middle). The backdrop dims both equally, so
    # the light-vs-dark contrast still holds with a menu open.
    px = lua('local x, y = script.chess.square_px(1, 3) '      # b3, a light square
             'local a, b = script.chess.square_px(0, 3) '      # a3, dark
             'local s = runtime_ui.get_surface_size() '
             'return x .. "," .. y .. "," .. a .. "," .. b .. "," .. s.w')
    x1, y1, x2, y2, sw = [float(v) for v in px.split(",")]
    im = Image.open(path).convert("RGB")
    k = im.width / sw                                          # the shot may be downscaled
    c1 = im.getpixel((int(x1 * k), int(y1 * k)))
    c2 = im.getpixel((int(x2 * k), int(y2 * k)))
    if sum(c1) > sum(c2) + 60 and sum(c2) > 60:
        return "drawn"
    return "MISSING light=%s dark=%s" % (c1, c2)

def inject(widget, expr):
    """Fire one real click on `widget` and report `expr`.

    A row that is not drawn never calls get_state, so the injected click cannot reach it --
    which is exactly how "this option is gone" is proved without reading pixels: the id may
    still exist as a hidden quad, but nothing happens when it is clicked.
    """
    return lua('_G.__mc.id = "%s" script.chess.tick() return tostring(%s)' % (widget, expr))

# The click wrapper below returns {} where the engine returns nil, so existence has to be
# asked of the REAL get_state -- through the wrapper every id looks alive.
def exists(widget_id):
    return lua('return tostring(_G.__mc.real("chess", "%s") ~= nil)' % widget_id) == "true"

def ids_nil(*ids):
    live = [i for i in ids if exists(i)]
    return "still there: " + ", ".join(live) if live else "gone"

def ids_live(*ids):
    dead = [i for i in ids if not exists(i)]
    return "missing: " + ", ".join(dead) if dead else "kept"

def survives(stmt):
    """Run `stmt` and ask, WITHOUT letting a frame pass, whether the 2D board is still up.

    The 3D set renders underneath the flat board, so a single frame with the square quads
    destroyed shows the 3D board through the gap. Anything that calls V.clear has to re-issue
    them in the same update -- which is exactly what this reads, since the check shares one
    execute_lua call with the action.
    """
    return lua('%s return tostring(_G.__mc.real("chess", "b2_s01") ~= nil) .. "/" .. '
               'tostring(_G.__mc.real("chess", "b2_rim") ~= nil)' % stmt)

def click(row_id):
    # status(), never menu(): menu() is a setter and closes the overlay when called bare.
    return lua('_G.__mc.id = "%s" script.chess.tick() '
               'return tostring(script.chess.status().menu_page)' % row_id)

def state():
    return lua('local s = script.chess.status() '
               'return tostring(s.menu_page) .. " | moves=" .. s.moves .. " bot=" .. '
               '(s.bot and ((s.bot.both and "both") or s.bot.side) or "off") .. '
               ' " 2d=" .. tostring(s.view2d)')

fails = []
def ck(name, got, want):
    ok = want in got
    print(("  PASS  " if ok else "  FAIL  ") + name + "  -> " + got +
          ("" if ok else "   (wanted %r)" % want))
    if not ok: fails.append(name)

lua(INSTALL)
try:
    # ── Play -> Player vs Bot -> Start
    lua('script.chess.menu("title")'); time.sleep(0.3)
    ck("root -> Play", click("m_play"), "play")
    ck("Play -> Player vs Bot", click("m_pvb"), "pvb")
    click("m_side_b"); time.sleep(0.25)
    ck("Black selected", lua('return tostring(script.chess.status().menu_page)'), "pvb")
    click("m_clock"); time.sleep(0.2)
    click("m_start_pvb"); time.sleep(1.4)
    ck("Start game -> bot plays White", state(), "bot=W")

    # ── Bot vs Bot
    lua('script.chess.menu("title")'); time.sleep(0.3)
    click("m_play"); ck("Play -> Bot vs Bot", click("m_bvb"), "bvb")
    click("m_start_bvb"); time.sleep(1.4)
    ck("Start game -> bot plays both", state(), "bot=both")

    # ── Analysis -> New Board
    lua('script.chess.menu("title")'); time.sleep(0.3)
    ck("root -> Analysis", click("m_analysis"), "analysis")
    click("m_newboard"); time.sleep(1.0)
    ck("New Board -> no bot, fresh game", state(), "moves=0 bot=off")

    # ── Player vs Player -> the not-built rows must answer
    lua('script.chess.menu("title")'); time.sleep(0.3)
    click("m_play"); ck("Play -> Player vs Player", click("m_pvp"), "pvp")
    click("m_create"); time.sleep(0.4)
    ck("Create Lobby -> note row rendered",
       lua('return tostring((runtime_ui.get_state("chess", "m_pvp_note") or {}).hovered ~= nil)'), "true")
    ck("Back -> play", click("m_back"), "play")
    ck("Back -> root", click("m_back"), "root")

    # ── Settings
    ck("root -> Settings", click("m_settings"), "settings")
    before = state()
    click("m_board"); time.sleep(0.4)
    after = state()
    ck("Board Type toggled", "changed" if before.split("2d=")[1] != after.split("2d=")[1] else "same", "changed")
    click("m_board"); time.sleep(0.5)
    ck("Board Type toggled back", state(), "2d=true")
    # The regression: 2D -> 3D -> 2D used to come back with the squares hidden, because the
    # square cache trusted its layout key while finish() had already retired the quads.
    ck("board squares survive a view round-trip", board_is_drawn(), "drawn")
    ck("Back -> root", click("m_back"), "root")
    # ── the in-game panel: only the review transport, the pause menu, and eval in analysis
    lua('script.chess.menu("title")'); time.sleep(0.3)
    click("m_play"); click("m_pvb"); click("m_start_pvb"); time.sleep(1.6)
    ck("panel drops the option rows",
       ids_nil("mv_hint", "mv_view", "mv_bot", "mv_botside", "mv_elo", "mv_replay"), "gone")
    ck("panel keeps Start / Live / Menu", ids_live("mv_start", "mv_end", "mv_quit"), "kept")
    ck("eval toggle is dead in a game", inject("mv_eval", "script.chess.status().eval"), "false")

    # ── pause card in a GAME: takeback, and no way to the title until it is over
    lua('script.chess.menu("pause")'); time.sleep(0.3)
    ck("game: no way to the title",
       inject("menu_pause_menu", "script.chess.status().menu"), "pause")
    ck("game: Offer takeback undoes the move",
       inject("menu_pause_takeback", "script.chess.status().moves"), "0")
    lua('script.chess.menu("pause")'); time.sleep(0.3)
    inject("menu_pause_resign", "script.chess.status().result")
    time.sleep(2.5)  # game_over_fx holds the end card back so the final move is seen
    ck("game: resign raises the end card",
       lua('return tostring(script.chess.status().menu)'), "end")
    lua('script.chess.menu("pause")'); time.sleep(0.3)
    ck("game over: Main menu returns to the title",
       inject("menu_pause_menu", "script.chess.status().menu"), "title")

    # ── analysis board: eval, and a pause card of Resume / Reset / Back only
    click("m_analysis"); click("m_newboard"); time.sleep(1.0)
    ck("New Board is an analysis board",
       lua('return tostring(script.chess.status().analysis)'), "true")
    ck("eval toggle works in analysis", inject("mv_eval", "script.chess.status().eval"), "true")
    inject("mv_eval", "script.chess.status().eval")  # off again: it drives a live search
    lua('script.chess.move("e2e4")'); time.sleep(0.3)
    lua('script.chess.menu("pause")'); time.sleep(0.3)
    ck("analysis: nothing to resign",
       inject("menu_pause_resign", "script.chess.status().result"), "nil")
    ck("analysis: Reset clears the board",
       inject("menu_pause_reset", "script.chess.status().moves"), "0")
    lua('script.chess.menu("pause")'); time.sleep(0.3)
    ck("analysis: Back returns to the title",
       inject("menu_pause_menu", "script.chess.status().menu"), "title")
    # ── no bare frame: every clear re-issues the flat board in the same update
    ck("opening a menu keeps the 2D board up", survives('script.chess.menu("title")'), "true/true")
    ck("starting a game keeps the 2D board up",
       survives('script.chess.new_game({side="hotseat", volume=0.15, view2d=true})'), "true/true")
finally:
    print(lua(RESTORE))

print("\nFAILURES: " + (", ".join(fails) if fails else "none"))
sys.exit(1 if fails else 0)
