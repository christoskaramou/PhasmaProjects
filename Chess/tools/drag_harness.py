"""Drive the chess drag-and-drop from outside, one gesture per MCP call.

Each gesture has to be its own call: a move starts a 0.28s tween and input is blocked while
`anim > 0`, so the frames in between must be REAL frames from the player's own pump. Only
the game's input source is stubbed -- the OS cursor is never touched.
"""
import json
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8765/tool"


def lua(code):
    req = urllib.request.Request(
        URL, data=json.dumps({"name": "execute_lua", "arguments": {"code": code}}).encode(),
        headers={"Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=90).read().decode())
    if r.get("isError"):
        raise SystemExit("MCP error: " + json.dumps(r)[:800])
    return (r.get("structuredContent") or {}).get("output", "")


INSTALL = r"""
_G.__dt = _G.__dt or {x = 0, y = 0, down = false}
if not _G.__dt.real_pos then
    _G.__dt.real_pos = input.get_mouse_position
    _G.__dt.real_down = input.is_left_mouse_down
    input.get_mouse_position = function() return {x = _G.__dt.x, y = _G.__dt.y} end
    input.is_left_mouse_down = function() return _G.__dt.down end
end

-- view.viewport(): the viewport rect when valid, else the runtime_ui surface.
function _G.__dt.vp()
    local r = engine.get_viewport_rect()
    if r and r.valid and r.w > 0 then return r.w, r.h end
    local s = runtime_ui.get_surface_size()
    return s.w, s.h
end

-- Ask the game where a square is, rather than re-deriving board2d's layout here: a copy
-- of that maths aims at the wrong square the moment the layout changes (it did, when the
-- captured-piece trays reserved a band above and below the board).
function _G.__dt.px2d(file, rank, _)
    return script.chess.square_px(file, rank)
end

-- Project a square with the live camera (view.project's exact math). `h` is the world
-- height aimed at: PRESS aims at a piece's body, because a base-point pixel is often
-- occluded by the taller piece standing in front of it. DROP aims at the board plane,
-- which is what view.pick_square intersects.
function _G.__dt.px3d(file, rank, h)
    local vw, vh = _G.__dt.vp()
    local x, z = (3.5 - file) * 0.0625, (rank - 4.5) * 0.0625
    local p = scene.get_active_camera():get_view_projection() * vec4(x, h or 0.0158, z, 1.0)
    if p.w <= 1e-6 then return nil end
    return (p.x / p.w + 1) * 0.5 * vw, (p.y / p.w + 1) * 0.5 * vh
end
_G.__dt.BODY = nil  -- board plane: at a steep camera the base point is not occluded

function _G.__dt.state()
    local h = script.chess.history()
    local s = script.chess.status()
    return #h .. "/" .. (h[#h] or "-") .. "/" .. s.turn
end
return "installed"
"""

RESTORE = r"""
if _G.__dt and _G.__dt.real_pos then
    input.get_mouse_position = _G.__dt.real_pos
    input.is_left_mouse_down = _G.__dt.real_down
    _G.__dt.real_pos, _G.__dt.real_down = nil, nil
end
_G.__dt = nil
return "restored"
"""


def gesture(kind, f0, r0, f1, r1, three_d=False):
    """One press-travel-release, or two clicks, inside a single frame batch."""
    fn = "px3d" if three_d else "px2d"
    if kind == "drag":
        body = f"""
        local d = _G.__dt
        d.x, d.y = d.{fn}({f0}, {r0}, d.BODY); d.down = true; script.chess.tick()
        d.x, d.y = d.{fn}({f1}, {r1}); script.chess.tick(); script.chess.tick()
        d.down = false; script.chess.tick()
        return d.state()"""
    else:
        body = f"""
        local d = _G.__dt
        d.x, d.y = d.{fn}({f0}, {r0}, d.BODY); d.down = true; script.chess.tick()
        d.down = false; script.chess.tick()
        d.x, d.y = d.{fn}({f1}, {r1}); d.down = true; script.chess.tick()
        d.down = false; script.chess.tick()
        return d.state()"""
    return lua(body)


def drop_off_board(f0, r0):
    return lua("""
        local d = _G.__dt
        local vw, vh = d.vp()
        d.x, d.y = d.px2d(%d, %d); d.down = true; script.chess.tick()
        d.x, d.y = vw - 60, vh * 0.5; script.chess.tick(); script.chess.tick()
        d.down = false; script.chess.tick()
        return d.state()""" % (f0, r0))


FILES = "abcdefgh"


def sq(f, r):
    return FILES[f] + str(r)


def main():
    print(lua(INSTALL))
    fails = []

    def check(name, got, want):
        ok = got.split("/")[0] == str(want[0]) and got.split("/")[1] == want[1]
        print(("  PASS  " if ok else "  FAIL  ") + name + "   -> " + got +
              ("" if ok else "   (wanted %s/%s)" % want))
        if not ok:
            fails.append(name)

    for label, view2d in (("2D", "true"), ("3D", "false")):
        print(label + " board")
        lua('script.chess.new_game({side = "hotseat", view2d = %s})' % view2d)
        lua("_G.__dt.flip = false")
        if view2d == "false":
            lua("script.chess.camera(180, 80, 0.75)")  # steep AND fully on screen: shallow angles hide a base point behind the piece in front, and dist 0.55 pushes rank 1 below the viewport
        time.sleep(0.4)
        three = view2d == "false"

        check("legal drag  e2-e4", gesture("drag", 4, 1 + 1, 4, 4, three), (1, "e4"))
        time.sleep(0.5)
        check("illegal drag e7-e4", gesture("drag", 4, 7, 4, 4, three), (1, "e4"))
        time.sleep(0.5)
        check("legal drag  e7-e5", gesture("drag", 4, 7, 4, 5, three), (2, "e5"))
        time.sleep(0.5)
        check("click-click g1-f3", gesture("click", 6, 1, 5, 3, three), (3, "Nf3"))
        time.sleep(0.5)
        check("knight drag b8-c6", gesture("drag", 1, 8, 2, 6, three), (4, "Nc6"))
        time.sleep(0.5)
        check("capture drag  none", gesture("drag", 5, 1, 2, 4, three), (5, "Bc4"))
        time.sleep(0.5)
        if not three:
            check("drop off board", drop_off_board(3, 7), (5, "Bc4"))
            time.sleep(0.4)

    print(lua(RESTORE))
    print("\nFAILURES: " + (", ".join(fails) if fails else "none"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
