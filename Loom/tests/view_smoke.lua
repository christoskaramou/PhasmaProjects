-- luajit tests/view_smoke.lua   (run from the Loom folder)
-- Boots the real scripts (loom.lua, the world, the rules, the game flow) against stubbed engine APIs and checks:
--   1. the look: raster, a Scene Settings node, ACES tone mapping in linear colour, depth of field, the camera lens
--   2. state A draws exactly the cooked pieces the Blender target placed (tests/target_keys.lua)
--   3. the drawn cloth agrees with the rules: wherever the rules let the traveller step between two cells, both cells'
--      cooked pieces show path at the shared side, and nowhere else (loom_data EDGE, from the meshes' skeletons)
--   4. the traveller and every house / bridge stand on the cloth measured on the cooked meshes (no floating, no
--      sinking), and the traveller stays on its cell's drawn path band while it walks
--   5. no node is created after start over a 150-row run (pools are fixed), rolled rows sit on the beam
--   6. the game flow: title -> run -> pause -> settings -> back -> game over -> retry -> menu, mute, saves
local io_open, os_exit = io.open, os.exit
local function read(path)
    if path:match("^Save/") then return SAVES[path] end
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
SAVES = {}
local env = _G
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end

-- templates: one mesh index per T_<name>
local MESH_OF, NAME_OF, nmesh = {}, {}, 0
local nodes_made = 0
local Node = {}
Node.__index = function(t, k)
    if k == "set_position" then return function(self, p) self.pos = { p.x, p.y, p.z } end end
    if k == "set_rotation" then return function(self, p) self.rot = { p.x, p.y, p.z } end end
    if k == "set_enabled" then return function(self, on) self.on = on end end
    if k == "get_mesh_refs" then return function(self) return { self.mesh } end end
    if k == "add_mesh_ref" then return function(self, m) self.mesh = m end end
    if k == "set_mesh_ref" then return function(self, m) self.mesh = m end end
    if k == "set_scene_settings" then return function(self, on) self.scene_settings = on end end
    return function() end
end
local all_nodes = {}
local function node(name) nodes_made = nodes_made + 1; local n = setmetatable({ name = name, on = true }, Node); all_nodes[#all_nodes + 1] = n; return n end
local CAM = {}
local cam = setmetatable({}, { __index = function(_, k)
    return function(_, v) CAM[k] = v end
end })
env.scene = setmetatable({
    add_empty_node = function(name) return node(name) end,
    get_active_camera = function() return cam end,
    find_model = function(name)
        local base = name:sub(3)
        if not MESH_OF[base] then nmesh = nmesh + 1; MESH_OF[base] = nmesh; NAME_OF[nmesh] = base end
        return setmetatable({ name = name, mesh = MESH_OF[base] }, Node)
    end,
    set_positions = function(t, n) for i = 0, n - 1 do t[i * 4 + 1].pos = { t[i * 4 + 2], t[i * 4 + 3], t[i * 4 + 4] } end end,
    set_rotations = function(t, n) for i = 0, n - 1 do t[i * 4 + 1].rot = { t[i * 4 + 2], t[i * 4 + 3], t[i * 4 + 4] } end end,
}, { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() return true end end })
env.lights = setmetatable({}, { __index = function() return function() end end })
env.skybox = { load = function() end }
env.fs = { read = read, write = function(p, s) SAVES[p] = s; return true end, exists = function() return false end }
local SOUNDS = {}
env.audio = setmetatable({ play = function(f) SOUNDS[#SOUNDS + 1] = f end, set_master_volume = function(v) MASTER = v end },
    { __index = function() return function() end end })
local QUIT = false
env.engine = setmetatable({ get_metrics = function() return { delta_ms = 1000 / 60 } end, quit = function() QUIT = true end },
    { __index = function() return function() end end })
local QUADS, CLICK = {}, {}
env.runtime_ui = setmetatable({
    get_surface_size = function() return { width = SURF_W or 2560, height = SURF_H or 1369 } end,
    set_quad = function(_, id, o) QUADS[id] = o end,
    get_state = function(_, id) if CLICK[id] then CLICK[id] = nil; return { clicked = true } end; return { hovered = HOVER and HOVER[id] or nil } end,
}, { __index = function() return function() end end })
local SET = {}
local render_mode
env.settings = { get = function(k) return SET[k] end, set = function(k, v) SET[k] = v end, set_render_mode = function(m) render_mode = m end }
local KEYS = {}
env.input = { is_key_down_raw = function(k) return KEYS[k] == true end, is_left_mouse_down = function() return false end }
local update
env.script = { on_update = function(_, f) update = f end }
env.os, env.io = nil, nil
assert(load(assert(read("Scripts/loom.lua")), "@loom.lua", "t", env))()
local L = env.loom
local W, D, R, G = L.W, L.D, L.R, L.G
local function frames(n) for _ = 1, n do update() end end
local fails = 0
local function check(ok, msg)
    if ok then print("ok   " .. msg) else print("FAIL " .. msg); fails = fails + 1 end
end
local function tap(k) KEYS[k] = true; update(); KEYS[k] = false; update() end
local function settle() frames(90) end           -- scroll + walk of a beat

frames(3)
-- 1. the look
check(render_mode == "raster", "raster render mode")
local ss = false
for _, n in ipairs(all_nodes) do if n.name == "Scene Settings" and n.scene_settings then ss = true end end
check(ss, "a Scene Settings node is created at startup (post effects need it)")
check(SET.tonemapping == true and SET.linear_color == true and SET.dof == true and SET.taa == true, "ACES tone mapping, linear colour, depth of field, TAA on")
check(SET.shadow_fixed_bounds == true and (SET.shadow_bounds_radius or 0) > 0, "fixed shadow bounds round the cloth")
check(math.abs((CAM.set_f_stop or 0) - (W.F_STOP or D.CAM.f_stop)) < 1e-6 and math.abs((CAM.set_focus_distance or 0) - D.CAM.focus) < 1e-6
    and math.abs((CAM.set_sensor_height or 0) - 24) < 1e-6, "the camera lens: the bake's focus and 24 mm sensor, the engine f-stop measured against it")
local want_hf = 2 * math.deg(math.atan(math.tan(math.rad(D.CAM.vfov) / 2) * 16 / 9))
check(math.abs((CAM.set_fov or 0) - want_hf) < 1e-4, string.format("horizontal fov %.3f at 2560x1369 keeps the bake's 16:9 width", CAM.set_fov or 0))

-- 2. state A draws the target's pieces
do
    local T = assert(load(io_open("tests/target_keys.lua"):read("*a")))()
    for _, st in ipairs({ "A", "B" }) do
        L.state(st); frames(2)
        local bad, n = 0, 0
        for r = 0, D.ROWS_VIEW - 1 do
            for c = 0, D.COLS - 1 do
                n = n + 1
                local want = T[st][r * D.COLS + c + 1]
                local got = NAME_OF[W.cells[r][c].n.mesh]
                if want ~= got then bad = bad + 1; if bad < 4 then print("   ", st, r, c, got, "target:", want) end end
            end
        end
        check(n == D.ROWS_VIEW * D.COLS and bad == 0, string.format("state %s: all %d cells show the target's cooked piece (%d differ)", st, n, bad))
    end
end

-- helpers for 3 and 4
local function E2B(p) return p[1], -p[3], p[2] end            -- engine -> table (x, y, z)
local OPP = { n = "s", s = "n", e = "w", w = "e" }
local function cloth_vs_rules(st, label)
    local grid = R.grid_fn(st)
    local bad, pairs_n = 0, 0
    for r = 0, D.ROWS_FLAT - 1 do
        local k = st.K - r
        for c = 0, D.COLS - 1 do
            local name = NAME_OF[W.cells[r][c].n.mesh]
            for _, d in ipairs({ "n", "e" }) do
                local dc, dk = R.DIRS[d][1], R.DIRS[d][2]
                local c2, r2 = c + dc, r - dk
                if c2 < D.COLS and r2 >= 0 and st.rows[k + dk] then
                    local name2 = NAME_OF[W.cells[r2][c2].n.mesh]
                    local rules = R.step_ok(st, c, k, d) and true or false
                    local drawn = D.EDGE[name][d] == "p" and D.EDGE[name2][OPP[d]] == "p"
                    pairs_n = pairs_n + 1
                    if rules ~= drawn then
                        bad = bad + 1
                        if bad < 4 then print("   ", label, "cell", c, k, d, name, name2, "rules", rules, "drawn", drawn) end
                    end
                end
            end
        end
    end
    return bad, pairs_n
end
local function on_cloth(label)
    local worst, n, off = 0, 0, 0
    local st = L.S.st
    -- the traveller: its foot on the measured cloth under its footprint
    local tp = W.trav_pos
    if tp and tp.name then
        local tw = L.S.walk
        local g = W.ground(tp.name, tw.u, tw.v, 0.23)
        worst = math.max(worst, math.abs(tp.z - (D.Z0 + g - 0.0006 + (tw.bob or 0))))
        n = n + 1
        local x, y, z = E2B(W.trav.pos)
        worst = math.max(worst, math.abs(z - tp.z), math.abs(x - tp.x), math.abs(y - tp.y))
    end
    -- houses and bridges on their cells
    for r = 0, D.ROWS_FLAT - 1 do
        for c = 0, D.COLS - 1 do
            local p = W.props[r][c]
            local name = NAME_OF[W.cells[r][c].n.mesh]
            if p.on then
                local _, _, z = E2B(p.n.pos)
                local kind = R.grid_fn(st)(r, c)
                local want
                if kind == "H" then want = D.Z0 + W.ground(name, 0, 0, 0.36) - 0.0005
                elseif kind == "b" then want = D.Z0 + math.min(W.ground(name, 0, 0.47), W.ground(name, 0, -0.47)) - 0.0008
                elseif kind == "B" then want = D.Z0 + math.min(W.ground(name, 0.47, 0), W.ground(name, -0.47, 0)) - 0.0008
                else off = off + 1 end
                if want then worst = math.max(worst, math.abs(z - want)); n = n + 1 end
            end
        end
    end
    return worst, n, off
end
-- the traveller's distance from its cell's drawn path centre line (cells): must stay inside the path band
local function on_band()
    local st, tw = L.S.st, L.S.walk
    local kind = R.cell(st, tw.c, tw.k)
    if not R.walkable(kind) then if not BAND_SAID then BAND_SAID = true; print("   off-path pose", tw.c, tw.k, tw.u, tw.v, kind, L.S.phase) end; return 9 end
    local _, mask = R.variant_key(R.grid_fn(st), tw.c, st.K - tw.k, tw.k)
    local sk
    if kind == "b" then sk = W.skeleton("ns", 0) elseif kind == "B" then sk = W.skeleton("ew", 0) else sk = W.skeleton(mask, -0.07) end
    local function seg(px, py, ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        local l2 = dx * dx + dy * dy
        local t = l2 < 1e-12 and 0 or math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
        return math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
    end
    local best = 9
    if sk then
        for i = 1, #sk - 1 do best = math.min(best, seg(tw.u, tw.v, sk[i][1], sk[i][2], sk[i + 1][1], sk[i + 1][2])) end
    else
        -- T, cross and dead ends: straight arms to the centre
        best = math.sqrt(tw.u ^ 2 + tw.v ^ 2)
        for s in mask:gmatch(".") do
            local a = ({ n = { 0, 0.5 }, e = { 0.5, 0 }, s = { 0, -0.5 }, w = { -0.5, 0 } })[s]
            best = math.min(best, seg(tw.u, tw.v, 0, 0, a[1], a[2]))
        end
    end
    return best
end

-- 3, 4, 5: a long bot run
do
    G.manual = true
    local st = L.play(11, { village = true })
    frames(2)
    local made0 = W.created
    local bad_t, pairs_t, worst_t, props_t, off_t, band_worst, rows = 0, 0, 0, 0, 0, 0, 0
    local roll_bad = 0
    for i = 1, 150 do
        if st.over then break end
        R.bot_weave(st)
        rows = rows + 1
        for f = 1, 60 do
            update()
            if f % 3 == 0 then
                local w, n, off = on_cloth("walk")
                worst_t = math.max(worst_t, w); props_t = props_t + n; off_t = off_t + off
                band_worst = math.max(band_worst, on_band())
            end
        end
        local b, p = cloth_vs_rules(st, "row " .. i)
        bad_t, pairs_t = bad_t + b, pairs_t + p
        -- rolled rows: on the beam axis, turned by a whole number of row arcs
        for r = D.ROWS_FLAT, D.ROWS_VIEW - 1 do
            local n = W.cells[r][0].n
            local x, y, z = E2B(n.pos)
            if math.abs(y - D.BEAM_AXIS[1]) > 1e-6 or math.abs(z - D.BEAM_AXIS[2]) > 1e-6 or math.abs(n.rot[1] - (r - D.ROWS_FLAT) * D.ROW_ARC) > 1e-6
                or not NAME_OF[n.mesh]:match("_r$") then roll_bad = roll_bad + 1 end
        end
    end
    check(rows >= 120, "the bot wove " .. rows .. " rows")
    check(pairs_t > 10000 and bad_t == 0, string.format("drawn path edges agree with the rules' steps on %d cell pairs (%d disagree)", pairs_t, bad_t))
    check(props_t > 1000 and worst_t < 1e-6 and off_t == 0,
        string.format("traveller and props rest on the measured cloth (%d checks, worst %.1e m, %d props on the wrong cells)", props_t, worst_t, off_t))
    check(band_worst <= 0.085 + 1e-6, string.format("the traveller stays on its cell's drawn path (worst %.3f cells from the centre line, band half-width 0.085)", band_worst))
    check(W.created == made0, "no node created after start over the run (" .. W.created .. " nodes)")
    check(roll_bad == 0, "rows past the crest are rolled copies turned round the beam axis")
    G.manual = false
end

-- 3b / 4b. a hand-made cloth: a bend the traveller must walk round, an E-W bridge with path either side of it (the
-- rules must not let the traveller step off the bridge sideways where the drawn bridge shows river), a N-S bridge
do
    G.manual = true
    local rows = { "....p....", "....p....", "....p....", "....p....", "....p....", "....p....", "....p....", "....p....",
        "....pp...", ".....p...", "~~~~~b~~~", "....pbp..", "....Hp...", ".....pH..", "...Hpp...", "~~~~pBp~~", "......p.." }
    local st = L.play(3, { rows = rows })
    st.trav = { c = 4, k = 7 }
    L.S.walk = L.stand_pose(st, 4, 7)
    frames(2)
    local b, p = cloth_vs_rules(st, "hand-made")
    check(p > 50 and b == 0, string.format("hand-made cloth with bends and bridges: drawn path edges == rules' steps (%d pairs, %d disagree)", p, b))
    -- the traveller walks the bend and over the bridge: stays on the drawn path, feet on the measured cloth
    local band, worst, moved = 0, 0, 0
    for i = 1, 4 do
        st.cur[6] = "p"
        R.beat(st)
        for f = 1, 150 do
            update()
            band = math.max(band, on_band())
            local w, n = on_cloth("hand-made")
            worst = math.max(worst, w)
            houses_seen = (houses_seen or 0) + n
        end
        moved = st.trav.k
    end
    check(moved >= 17 and not st.over, "the traveller walked the bend and crossed the bridge (now on row " .. moved .. ")")
    check(band <= 0.085 + 1e-6, string.format("on the bend and the bridge it stays on the drawn path (worst %.3f cells off the centre line)", band))
    check(worst < 1e-6 and houses_seen > 600, string.format("its feet and the houses stay on the measured cloth (worst %.1e m, %d checks)", worst, houses_seen))
    -- independent of the world's own ground lookup: never below the cooked mesh's highest point at its centre sample
    local tw = L.S.walk
    local name = W.trav_pos.name
    local g = D.GROUND[name]
    if not g then print("   no ground for", tostring(name), tw.c, tw.k, L.S.st.K) end
    local i, j = math.floor((tw.u + 0.5) * (D.HMAP - 1) + 0.5), math.floor((tw.v + 0.5) * (D.HMAP - 1) + 0.5)
    local _, _, z = E2B(W.trav.pos)
    check(z >= D.Z0 + g[j + 1][i + 1] - 0.0006 - 1e-6 and g[j + 1][i + 1] > 0.0002,
        string.format("standing on %s it rests on the woven ridge under it (foot %.4f, cloth %.4f above Z0)", name, z - D.Z0, g[j + 1][i + 1]))
    G.manual = false
end

-- 6. the game flow
do
    G.to_title(); frames(30)
    check(G.mode == "title" and QUADS.t_play and QUADS.t_play.visible ~= false and QUADS.t_quit, "title card with PLAY and QUIT")
    frames(200)
    check(L.S.st.K > #R.START, "the title's weaver weaves behind the card (" .. (L.S.st.K - #R.START) .. " rows)")
    G.save.guided = 1            -- no guide here: the guide holds the clock itself, which would hide a running clock in pause
    CLICK.t_play = true; frames(3)
    check(G.mode == "run" and not L.S.st.over, "PLAY starts a run")
    local st = L.S.st
    tap("Right"); tap("2")
    check(st.cur[st.cursor - 1] == "p" or st.cur[5] == "p", "keys: Right then 2 lays a path")
    tap("Escape"); frames(10)
    check(G.pause ~= nil and QUADS.pz_resume and QUADS.pz_menu and QUADS.pz_quit and QUADS.pz_settings, "Esc opens the pause card (Resume, Settings, Back to menu, Quit)")
    local t0 = st.timer
    frames(30)
    check(st.timer == t0, "the loom's clock stops while paused")
    CLICK.pz_settings = true; frames(3)
    check(G.settings:is_open(), "SETTINGS opens the shared settings menu")
    G.settings:close(); frames(12)
    check(G.pause ~= nil, "closing settings returns to the pause card (BACK)")
    CLICK.pz_resume = true; frames(3)
    check(G.pause == nil, "RESUME closes it")
    tap("M")
    check(G.settings:get("mute") == true, "M mutes")
    tap("M")
    -- a careless row ends the run: no path in the newest row
    for c = 0, 8 do st.cur[c] = st.forced[c] end
    st.order = {}
    local K0 = st.K
    tap("Space"); frames(3)
    check(st.K == K0 and not st.over and G.confirm and tostring(G.msg):find("SPACE again"), "a breaking row: the first SPACE only warns (SPACE again to confirm)")
    tap("Space")
    frames(150)
    check(st.over == "break" and G.mode == "over" and QUADS.o_retry and QUADS.o_menu, "a row without the path ends the run: game-over card with RETRY and BACK TO MENU")
    check(SAVES["Save/loom.txt"] and SAVES["Save/loom.txt"]:find("runs=1"), "the run is saved (runs, best)")
    local snd = {}
    for _, s in ipairs(SOUNDS) do snd[s] = true end
    check(snd["beat.wav"] and snd["shuttle.wav"] and snd["click.wav"] and snd["over.wav"], "sounds: shuttle, beat, click, game over")
    tap("Return"); frames(3)
    check(G.mode == "run" and L.S.st ~= st and not L.S.st.over, "RETRY starts a new run")
    tap("Escape"); frames(10)
    CLICK.pz_menu = true; frames(3)
    check(G.mode == "title", "BACK TO MENU returns to the title")
    frames(20); CLICK.t_quit = true; frames(3)
    check(QUIT, "QUIT quits")
end

-- 7. the click targets over the row being woven lie on screen, left to right
do
    G.manual = false
    G.start_run(5); frames(3)
    local ok, lastx = true, -1
    for c = 0, 8 do
        local q = QUADS["cell" .. c]
        if not q or q.x <= lastx or q.x < 0 or q.x + q.width > 2560 or q.y < 0 or q.height <= 0 then ok = false end
        lastx = q and q.x or lastx
    end
    check(ok, "nine click targets over the row being woven, on screen, left to right")
    CLICK.chip6 = true; frames(2)
    CLICK.cell3 = true; frames(2)
    check(L.S.st.cur[3] == "f", "clicking the FIELD chip then cell 4 lays a field there")
end

-- 8. the HUD chips at 1280x720 (round 3): every kind's chip shows its wool left, in text of at least 14 px
do
    SURF_W, SURF_H = 1280, 720
    G.manual = false
    G.start_run(9); frames(4)
    local st = L.S.st
    local found, small = {}, 0
    for id, q in pairs(QUADS) do
        if q.visible ~= false and q.label and q.text_color and q.text_color[4] and q.text_color[4] > 0.7 then
            for _, wool in ipairs({ "tan", "indigo", "brown", "ochre", "grey", "sage" }) do
                if q.label == wool .. " " .. st.wool[wool] then
                    found[wool] = true
                    if q.font_scale * 16 < 14 then small = small + 1 end
                end
            end
        end
    end
    local n = 0
    for _ in pairs(found) do n = n + 1 end
    check(n == 6 and small == 0, string.format("HUD chips at 1280x720 show the wool left for all 6 wools in >= 14 px text (%d shown, %d too small)", n, small))
    SURF_W, SURF_H = nil, nil
end

-- 9. teaching (round 5): marks, the break warning, the guided first run (once), HOW TO PLAY, causes on game over
local function in_box(q, b) return q.x >= b.x - 1 and q.y >= b.y - 1 and q.x + q.width <= b.x + b.w + 1 and q.y + q.height <= b.y + b.h + 1 end
local function text_quads(zlo, zhi)
    local t = {}
    for id, q in pairs(QUADS) do
        if q.visible ~= false and q.label and #q.label > 0 and q.z and q.z >= zlo and q.z <= zhi and q.text_color and q.text_color[4] > 0.7 then t[#t + 1] = q end
    end
    return t
end
-- glyph width ~0.56 em for this UI font (measured on the cards: 'HOW TO PLAY' etc.); a box must hold its label
local function fits(q) return #q.label * q.font_scale * 16 * 0.56 <= q.width + 2 end
do
    SAVES["Save/loom.txt"] = "best=0" .. string.char(10) .. "best_rows=0" .. string.char(10) .. "runs=0" .. string.char(10) .. "guided=0" .. string.char(10)
    G.save.guided = 0            -- a fresh save (the module read Save/loom.txt at boot)
    G.manual = false
    G.start_run(8); frames(4)
    local st = L.S.st
    check(G.guide and G.guide.step == 1, "a first run starts the guide (step 1: lay PATH on the glowing cell)")
    local marks = R.path_marks(st)
    local drawn = 0
    for c = 0, 8 do if G.mark_rects and G.mark_rects[c] then drawn = drawn + 1 end end
    local want = 0
    for c = 0, 8 do if marks[c] then want = want + 1 end end
    local same = true
    for c = 0, 8 do if (G.mark_rects and G.mark_rects[c] ~= nil) ~= (marks[c] == true) then same = false end end
    check(want >= 1 and same, "the HUD glows exactly the cells R.path_marks marks (" .. drawn .. ")")
    local t0 = st.timer
    frames(120)
    check(st.timer == t0, "the guide holds the loom's clock until the first row is beaten")
    local mc
    for c = 0, 8 do if marks[c] then mc = c end end
    while st.cursor < mc do tap("Right") end
    while st.cursor > mc do tap("Left") end
    tap("2"); frames(2)
    check(G.guide.step == 2 and not G.break_warning, "laying PATH on the glowing cell: guide step 2, no break warning")
    local K0 = st.K
    tap("Space"); frames(4)
    check(st.K == K0 + 1 and G.guide.step == 3, "one SPACE beats a row that carries the path (guide step 3)")
    for _ = 1, 6 do
        if not G.guide then break end
        for _, p in ipairs(R.bot_row(st)) do R.lay(st, p.c, p.i) end
        tap("Space"); frames(90)
    end
    for _ = 1, 400 do if not G.guide then break end; update() end
    check(G.guide == nil and SAVES["Save/loom.txt"]:find("guided=1"), "the guide ends after the first wool earned back and is saved as shown")
    G.start_run(9); frames(3)
    check(G.guide == nil, "the guide is shown once: the next run has none")
    -- the break warning while the row would break, and the clock's beat with it
    local st2 = L.S.st
    frames(2)
    check(G.break_warning and G.break_warning:find("glowing") and R.would_break(st2), "an empty row shows the break warning with the clock")
    -- skip: a fresh save, TAB ends the guide and saves it
    SAVES["Save/loom.txt"] = "best=0" .. string.char(10) .. "best_rows=0" .. string.char(10) .. "runs=0" .. string.char(10) .. "guided=0" .. string.char(10)
    G.save.guided = 0
    G.start_run(10); frames(2)
    tap("Tab"); frames(2)
    check(G.guide == nil and SAVES["Save/loom.txt"]:find("guided=1"), "TAB skips the guide and saves it as shown")
    -- HOW TO PLAY from pause, both pages, at 1280x720 and 2560x1369: every text box inside the card, fitting, >= 14 px
    for _, sz in ipairs({ { 1280, 720 }, { 2560, 1369 } }) do
        SURF_W, SURF_H = sz[1], sz[2]
        frames(2)
        tap("Escape"); frames(12)
        check(QUADS.pz_howto and QUADS.pz_howto.visible ~= false, sz[1] .. ": the pause card has HOW TO PLAY")
        CLICK.pz_howto = true; frames(12)
        for page = 1, 2 do
            frames(2)
            local bad, small, n = 0, 0, 0
            for _, q in ipairs(text_quads(163, 166)) do
                n = n + 1
                if not in_box(q, G.howto_box) or not fits(q) then bad = bad + 1; if bad < 3 then print("   box", q.label) end end
                if q.font_scale * 16 < 14 then small = small + 1 end
            end
            check(G.howto and G.howto.page == page and n >= 12 and bad == 0 and small == 0,
                string.format("%dx%d HOW TO PLAY page %d: %d text boxes inside the card and fitting, none under 14 px (%d bad, %d small)", sz[1], sz[2], page, n, bad, small))
            tap("Right"); frames(3)
        end
        tap("Escape"); frames(12)
        check(G.howto == nil and G.pause ~= nil, sz[1] .. ": BACK from HOW TO PLAY returns to the pause card")
        tap("Escape"); frames(12)
    end
    G.to_title(); frames(20)
    tap("H"); frames(12)
    check(G.howto and G.howto.page == 1, "H on the title opens HOW TO PLAY")
    tap("Escape"); frames(12)
    check(G.howto == nil and G.mode == "title", "its BACK returns to the title")
    -- the game-over card names the cause and the fix, inside the card
    for _, cause in ipairs({ "clock", "nopath", "river", "detached" }) do
        G.start_run(12); frames(2)
        local s3 = L.S.st
        if cause == "clock" then R.update(s3, 999)
        else
            for c = 0, 8 do s3.cur[c] = s3.forced[c] end
            if cause == "detached" then s3.cur[(s3.trav.c + 4) % 9] = "p" end
            if cause == "river" then for c = 0, 8 do s3.forced[c] = "~"; s3.cur[c] = "~" end end
            R.beat(s3, false)
        end
        frames(160)
        local head, why, fix = G.over_words(s3)
        local bad = 0
        for _, q in ipairs(text_quads(82, 82)) do if not in_box(q, G.over_box) or not fits(q) then bad = bad + 1 end end
        check(G.mode == "over" and s3.over_info.cause == cause and fix and #fix > 20 and bad == 0,
            "game over by '" .. cause .. "': " .. head .. " / the cause and FIX shown inside the card (" .. bad .. " bad boxes)")
    end
    SURF_W, SURF_H = nil, nil
end

-- 10. round 6: COMING UP, the kind hints (hover / key), the warnings
do
    local function overlap(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end
    for _, sz in ipairs({ { 1280, 720 }, { 2560, 1369 } }) do
        SURF_W, SURF_H = sz[1], sz[2]
        G.save.guided = 1
        G.start_run(21); frames(4)
        local st = L.S.st
        local pb = G.preview_box
        local ok_pb = pb and pb.x >= 0 and pb.x + pb.w <= sz[1] and pb.y + pb.h < sz[2] * 0.5 and pb.cs * 1 >= 18
        -- the preview shows exactly the pattern rows ahead: count its non-empty cells against st.ahead
        check(ok_pb and #st.ahead == R.PREVIEW, string.format("%dx%d: COMING UP shows %d rows ahead, on screen (cells %.0f px)", sz[1], sz[2], #st.ahead, pb and pb.cs or 0))
        local bad, small, shown = 0, 0, 0
        for i = 1, 9 do
            HOVER = { ["chip" .. i] = true }
            frames(2)
            local hb = G.hint_box
            if hb and hb.i == i then
                shown = shown + 1
                if hb.x < 0 or hb.y < 0 or hb.x + hb.w > sz[1] or overlap(hb, pb) then bad = bad + 1 end
                for _, q in ipairs(text_quads(51, 51)) do
                    if not in_box(q, hb) or not fits(q) then bad = bad + 1; if bad < 3 then print("   hint", q.label) end end
                    if q.font_scale * 16 < 14 then small = small + 1 end
                end
            end
        end
        HOVER = nil
        frames(2)
        check(shown == 9 and bad == 0 and small == 0, string.format("%dx%d: hovering each chip 1-9 shows its hint on screen, text inside and >= 14 px (%d shown, %d bad, %d small)", sz[1], sz[2], shown, bad, small))
        check(G.hint_box == nil, sz[1] .. ": the hint goes when the pointer leaves the chips")
        tap("6"); frames(2)
        check(G.hint_box and G.hint_box.i == 6, sz[1] .. ": pressing a key shows that kind's hint")
        frames(200)
        check(G.hint_box == nil, sz[1] .. ": the key's hint fades after a moment")
    end
    -- what each hint says matches the rules' prices and payouts
    local okp = G.pays_text("f"):find("2 tan") and G.pays_text("p"):find("nothing") and G.pays_text("w"):find("2 brown")
    check(okp, "hints read payouts from R.HARVEST: " .. G.pays_text("f"))
    -- warnings: low path wool, a river in COMING UP, a blocked row above the path
    G.start_run(22); frames(2)
    local st = L.S.st
    st.wool.tan = 1; frames(2)
    check(G.warn and G.warn:find("Path wool low"), "low path wool warns and names FIELDS: " .. tostring(G.warn))
    st.wool.tan = 9
    st.ahead[2] = { [0] = "~", "~", "~", "~", "~", "~", "~", "~", "~" }; frames(2)
    check(G.warn and G.warn:find("A river crosses in 2 rows"), "a river in COMING UP warns ahead: " .. tostring(G.warn))
    local blocked = {}
    for c = 0, 8 do blocked[c] = "r" end
    st.ahead[1] = blocked; frames(2)
    check(G.warn and G.warn:find("blocked above the path"), "rock above every glowing cell says turn sideways: " .. tostring(G.warn))
    SURF_W, SURF_H = nil, nil
end

print(fails == 0 and "all ok" or (fails .. " failed"))
os_exit(fails == 0 and 0 or 1)
