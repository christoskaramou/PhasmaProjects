-- Loom world: draws the loom the way .concepts/next/loom/LOOKPLAN.md says.
--   backdrop  the static Cycles bake (table, loom frame, reed, warp, wool stands) drawn unlit on a mesh cast from the
--             bake's camera (tools/scene.py backdrop_depth_mesh), so depth of field and occlusion see its real depth
--   cloth     9 x ROWS_VIEW cell nodes; each shows the cooked variant of its (kind, 3x3 neighbourhood) via set_mesh_ref;
--             rows past the front beam's crest show the rolled copy, turned about the beam axis
--   live      the loose weft of the row being woven, the cursor loop, the shuttle and its pirn, the traveller, the felt
--             houses and the wooden bridges on their cells, the seven wool balls (their size shows the wool left)
-- Logic in Blender table axes (x across, y toward the reed, z up); E() converts to engine (x, z, -y).
return function(D, R)
local W = {}
local floor, min, max, abs, sin, cos, sqrt, ceil = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt, math.ceil
local deg, rad, atan2 = math.deg, math.rad, math.atan2 or math.atan
local function v3(x, y, z) return vec3(x, y, z) end
local function E(x, y, z) return x, z, -y end
W.E = E
local CELL, COLS, Z0 = D.CELL, D.COLS, D.Z0
local ROWS_VIEW, ROWS_FLAT = D.ROWS_VIEW, D.ROWS_FLAT
local cam

------------------------------------------------------------------ materials (template clones replay writes: engine quirk)
local mat_q = {}
local function mq(f) f(); mat_q[#mat_q + 1] = { f = f, c = 0 } end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 20 then pcall(q.f) end
        if q.c >= 20 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, metal, rough, emis)
    mq(function()
        pcall(material.set, n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
        pcall(material.set, n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
        pcall(material.set, n, "metallic", metal or 0)
        pcall(material.set, n, "roughness", rough or 0.5)
    end)
end
local function tex(n, slot, path) mq(function() pcall(material.set_texture, n, slot, path) end) end
local function render_type(n, t) mq(function() pcall(material.set_render_type, n, t) end) end

-- The cloth: vertex colour (cooked) x the shared weave tile (baked at 1 / 1.2: the factor's sRGB 1.083 is 1.2 linear).
W.CLOTH = { factor = 1.083, rough = 0.9 }
local function cloth_look(n)
    mat(n, { W.CLOTH.factor, W.CLOTH.factor, W.CLOTH.factor }, 0, W.CLOTH.rough)
    tex(n, "base_color", "Textures/weave_albedo.png")
    tex(n, "normal", "Textures/weave_normal.png")
end
-- Props a little darker than their cooked colours: the felt houses came out brighter than the bake (houses region
-- 166,144,115 against 143,119,88, round 3).
W.PROP_FACTOR = 0.84
local function prop_look(rough) return function(n) local k = W.PROP_FACTOR; mat(n, { k, k, k }, 0, rough or 0.85) end end
-- Unlit: black base, metallic 1 (no diffuse, black F0: no specular), the picture as emissive.
-- The backdrop texture is the bake through the inverse of the engine's tone curve, / EMIS_SCALE (gen_assets.py).
local function unlit(png)
    local k = D.EMIS_SCALE or 1
    return function(n) mat(n, { 0, 0, 0, 1 }, 1, 1, { k, k, k }); tex(n, "emissive", "Textures/" .. png) end
end

------------------------------------------------------------------ templates and nodes
local TPL = {}           -- name -> { node = template node, mesh = mesh index }
W.TPL = TPL
local function tpl(name)
    local t = TPL[name]
    if t then return t end
    local n = scene.find_model and scene.find_model("T_" .. name)
    t = { node = n, mesh = n and n:get_mesh_refs()[1] or nil }
    TPL[name] = t
    return t
end
W.created = 0
local function node(name, mesh)
    W.created = W.created + 1
    local n = scene.add_empty_node(name)
    local t = mesh and tpl(mesh)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    return n
end
local function show(n, on) if n then pcall(function() n:set_enabled(on and true or false) end) end end
local function set_mesh(slot, name)
    if slot.mesh == name then return end
    local t = tpl(name)
    if t.mesh then slot.n:set_mesh_ref(t.mesh); slot.mesh = name; W.swaps = (W.swaps or 0) + 1 end
end

-- Batched transforms (engine euler degrees).
local PB, PN, RB, RN = {}, 0, {}, 0
local function setpos(n, bx, by, bz)
    local x, y, z = E(bx, by, bz)
    PB[PN * 4 + 1], PB[PN * 4 + 2], PB[PN * 4 + 3], PB[PN * 4 + 4] = n, x, y, z
    PN = PN + 1
end
local function setrot(n, rx, ry, rz)
    RB[RN * 4 + 1], RB[RN * 4 + 2], RB[RN * 4 + 3], RB[RN * 4 + 4] = n, rx, ry, rz
    RN = RN + 1
end
local function flush_xf()
    if PN > 0 then pcall(scene.set_positions, PB, PN) end
    if RN > 0 then pcall(scene.set_rotations, RB, RN) end
    PN, RN = 0, 0
end

------------------------------------------------------------------ geometry shared with the bake (loom_grid.py)
local function col_x(c) return (c - (COLS - 1) / 2) * CELL end
local function row_y(r) return -(r + 0.5) * CELL end
W.col_x, W.row_y = col_x, row_y
-- Cloth height above Z0 at cell-local (u, v) of a cooked variant: bilinear in the measured grid, or with rad > 0 the
-- highest sample within rad (a prop's footprint rests on the highest ridge under it).
local HM = D.HMAP
function W.ground(name, u, v, rad)
    local g = D.GROUND[name]
    if not g then return 0 end
    local fi, fj = (u + 0.5) * (HM - 1), (v + 0.5) * (HM - 1)
    if rad and rad > 0 then
        local best = -1
        local rr = rad * (HM - 1)
        for j = max(0, floor(fj - rr)), min(HM - 1, ceil(fj + rr)) do
            for i = max(0, floor(fi - rr)), min(HM - 1, ceil(fi + rr)) do
                if (i - fi) ^ 2 + (j - fj) ^ 2 <= rr * rr + 1e-9 then best = max(best, g[j + 1][i + 1]) end
            end
        end
        if best >= 0 then return best end
    end
    fi, fj = max(0, min(HM - 1.000001, fi)), max(0, min(HM - 1.000001, fj))
    local i0, j0 = floor(fi), floor(fj)
    local a, b = fi - i0, fj - j0
    local r0, r1 = g[j0 + 1], g[j0 + 2] or g[j0 + 1]
    return (r0[i0 + 1] * (1 - a) + (r0[i0 + 2] or r0[i0 + 1]) * a) * (1 - b) + (r1[i0 + 1] * (1 - a) + (r1[i0 + 2] or r1[i0 + 1]) * a) * b
end

-- The path's centre line inside a cell (as loom_grid.skeleton): pieces of (u, v) from side midpoints.
local ARMS = { n = { 0, 0.5 }, e = { 0.5, 0 }, s = { 0, -0.5 }, w = { -0.5, 0 } }
local function skeleton(mask, bulge)
    local a = {}
    for s in mask:gmatch(".") do a[#a + 1] = s end
    table.sort(a)
    if #a == 2 and ((a[1] == "n" and a[2] == "s") or (a[1] == "e" and a[2] == "w")) then
        local out = {}
        for k = 0, 24 do
            local t = k / 24
            local off = bulge * (1 - cos(2 * math.pi * t)) / 2
            if a[1] == "n" then out[#out + 1] = { off, -0.5 + t } else out[#out + 1] = { -0.5 + t, off } end
        end
        return out
    end
    if #a == 2 then
        local ax, ay = ARMS[a[1]][1], ARMS[a[1]][2]
        local bx, by = ARMS[a[2]][1], ARMS[a[2]][2]
        local cx, cy = ax + bx, ay + by
        local a0, a1 = atan2(ay - cy, ax - cx), atan2(by - cy, bx - cx)
        if a1 - a0 > math.pi then a1 = a1 - 2 * math.pi end
        if a0 - a1 > math.pi then a1 = a1 + 2 * math.pi end
        local out = {}
        for k = 0, 16 do out[#out + 1] = { cx + 0.5 * cos(a0 + (a1 - a0) * k / 16), cy + 0.5 * sin(a0 + (a1 - a0) * k / 16) } end
        return out
    end
    return nil
end
W.skeleton = skeleton
local MEANDER_PATH = -0.07
-- Points (u, v) from the midpoint of side `side` of a walkable cell to where the traveller stands in it.
function W.cell_half(kind, mask, side)
    local pl
    if kind == "b" then pl = skeleton("ns", 0) elseif kind == "B" then pl = skeleton("ew", 0) else pl = skeleton(mask, MEANDER_PATH) end
    local m = ARMS[side]
    if pl then
        local n = #pl
        local mid = floor(n / 2) + 1
        local first = pl[1]
        local out = {}
        if abs(first[1] - m[1]) + abs(first[2] - m[2]) < 1e-6 then
            for i = 1, mid do out[#out + 1] = pl[i] end
        else
            for i = n, mid, -1 do out[#out + 1] = pl[i] end
        end
        return out
    end
    return { { m[1], m[2] }, { 0, 0 } }
end
function W.stand_point(kind, mask)
    local pl
    if kind == "b" then pl = skeleton("ns", 0) elseif kind == "B" then pl = skeleton("ew", 0) else pl = skeleton(mask, MEANDER_PATH) end
    if pl then local p = pl[floor(#pl / 2) + 1]; return p[1], p[2] end
    return 0, 0
end

------------------------------------------------------------------ look and init
W.BALL_SHADOW_ALPHA = 0.78
-- The engine's depth of field blurs more than Cycles at the same f-number: f/5.6 here matched the bake's sharpness on
-- the working area (fell, traveller, bridge: variance of the Laplacian, tools/sharp.py, round 3) where the bake has f/4.
W.F_STOP = 5.6
W.SUN = { intensity = 9.5, colour = { 1.0, 0.9, 0.78 } }      -- matched live to target.png (revision 2): cloth MAD 51 -> 17
W.SETTINGS = { tonemapping = true, linear_color = true, bloom = false, render_scale = 1.0, taa = true, fxaa = false,
    cas_sharpening = false, motion_blur = false, ssao = true, ssao_radius = 0.012, ssao_intensity = 1.0, ssr = false, IBL = true,
    IBL_intensity = 3.2, shadows = true, color_grading = false, dof = true, dof_blur_range = 24.0, fog = false,
    shadow_map_size = 4096, shadow_filter_radius = 1.6,
    -- with fixed bounds the shadow depth range is max(shadow_distance, 2 r) (ShadowPass.cpp:507) and the receiver bias is
    -- up to two texels of it (Lighting.hlsl:357): at the default 250 m that is ~12 cm and hides every prop's shadow
    shadow_distance = 1.6 }
function W.apply_look()
    if skybox and skybox.load then pcall(skybox.load, "day.hdr") end
    for k, v in pairs(W.SETTINGS) do pcall(settings.set, k, v) end
    -- fixed shadow bounds round the cloth and the wool balls (Settings.h:182)
    local bx, by, bz = E(0.15, -0.3, Z0)
    for k, v in pairs({ shadow_bounds_x = bx, shadow_bounds_y = by, shadow_bounds_z = bz, shadow_bounds_radius = 0.75 }) do pcall(settings.set, k, v) end
    pcall(settings.set, "shadow_fixed_bounds", true)
    pcall(lights.set_property, "directional", 0, "intensity", W.SUN.intensity)
    pcall(lights.set_property, "directional", 0, "color", v3(W.SUN.colour[1], W.SUN.colour[2], W.SUN.colour[3]))
end

function W.init()
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    pcall(function() cam:set_near(0.02) end)
    pcall(function() cam:set_far(50) end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- raster: the hybrid default refits a ray-tracing TLAS every frame (lost the GPU device in other games here)
    pcall(settings.set_render_mode, "raster")
    W.apply_look()
    -- style every template once (materials live on the mesh entries: every node showing a mesh shares its look)
    for name in pairs(D.GROUND) do
        local a, b = tpl(name), tpl(name .. "_r")
        if a.node then cloth_look(a.node) end
        if b.node then cloth_look(b.node) end
    end
    for _, w in ipairs(R.WOOLS) do
        for lv = 0, 4 do local t = tpl("ball_" .. w .. "_" .. lv); if t.node then prop_look(0.95)(t.node) end end
        for _, p in ipairs({ "weft_", "pirn_" }) do local t = tpl(p .. w); if t.node then prop_look(0.95)(t.node) end end
    end
    for _, p in ipairs({ "house0", "house1", "house2", "bridge", "traveller", "shuttle", "cursor" }) do
        local t = tpl(p)
        if t.node then prop_look(p == "shuttle" and 0.45 or (p == "bridge" and 0.6 or 0.9))(t.node) end
    end
    local sh = tpl("shadow_card")
    if sh.node then
        render_type(sh.node, "alpha_blend")
        mat(sh.node, { 0.035, 0.022, 0.015, W.BALL_SHADOW_ALPHA }, 0, 1)
        tex(sh.node, "base_color", "Textures/ball_shadow.png")
    end
    local bt = tpl("backdrop")
    if bt.node then unlit("backdrop.png")(bt.node) end
    W.backdrop = node("loom_backdrop", "backdrop")
    -- the cloth grid, its props, the loose weft row
    W.cells, W.props = {}, {}
    for r = 0, ROWS_VIEW - 1 do
        W.cells[r], W.props[r] = {}, {}
        for c = 0, COLS - 1 do
            W.cells[r][c] = { n = node("cell_" .. r .. "_" .. c, "c_meadow_0"), mesh = "c_meadow_0" }
            if r < ROWS_FLAT + 1 then
                local p = { n = node("prop_" .. r .. "_" .. c, "house0"), mesh = "house0", on = true }
                W.props[r][c] = p
            end
        end
    end
    W.weft = {}
    for c = 0, COLS - 1 do W.weft[c] = { n = node("weft_" .. c, "weft_sage"), mesh = "weft_sage", on = true } end
    W.cursor = node("cursor", "cursor")
    W.shuttle = node("shuttle", "shuttle")
    W.pirn = { n = node("pirn", "pirn_tan"), mesh = "pirn_tan" }
    W.trav = node("traveller", "traveller")
    W.balls = {}
    for i, b in ipairs(D.BALLS) do
        W.balls[i] = { n = node("ball_" .. b[1], "ball_" .. b[1] .. "_4"), mesh = "ball_" .. b[1] .. "_4", wool = b[1], x = b[2], y = b[3] }
        setpos(W.balls[i].n, b[2], b[3], 0)
        W.balls[i].shadow = node("ball_shadow_" .. b[1], "shadow_card")
    end
    setpos(W.backdrop, 0, 0, 0)
    flush_xf()
    W.cx = 4
end

------------------------------------------------------------------ the frame
-- view: { st = rules state, scroll = 0..1 (beat animation: rows slide one row toward the weaver), walk = traveller
-- pose { c, k, u, v, heading, bob } (cloth coordinates), cursor = column or nil, pirn = wool, show_row = bool }
local function key_names(st, grid)
    local names = {}
    for r = 0, ROWS_VIEW - 1 do
        names[r] = {}
        local k = st.K - r
        for c = 0, COLS - 1 do
            if st.rows[k] then
                local kind, mask = R.variant_key(grid, c, r, k)
                names[r][c] = R.key_name(kind, mask)
            else
                names[r][c] = "c_meadow_" .. R.alt_of(".", c, k)
            end
        end
    end
    return names
end
W.key_names = key_names

local cache = { K = -1 }
function W.frame(view)
    local st = view.st
    local s = view.scroll or 1
    local grid = R.grid_fn(st)
    if cache.K ~= st.K or cache.st ~= st then cache.names = key_names(st, grid); cache.K = st.K; cache.st = st end
    local names = cache.names
    for r = 0, ROWS_VIEW - 1 do
        local rho = r - 1 + s                -- fractional row while the cloth slides on
        for c = 0, COLS - 1 do
            local cell = W.cells[r][c]
            local name = names[r][c]
            local rolled = r >= ROWS_FLAT and not (r == ROWS_FLAT and s < 1)
            set_mesh(cell, rolled and (name .. "_r") or name)
            if rolled then
                setpos(cell.n, col_x(c), D.BEAM_AXIS[1], D.BEAM_AXIS[2])
                setrot(cell.n, (rho - ROWS_FLAT) * D.ROW_ARC, 0, 0)
            else
                setpos(cell.n, col_x(c), row_y(rho), Z0)
                setrot(cell.n, 0, 0, 0)
            end
            -- props on flat rows
            local p = W.props[r] and W.props[r][c]
            if p then
                local k = st.K - r
                local kind = grid(r, c)
                local want = nil
                if r < ROWS_FLAT then
                    if kind == "H" then want = "house" .. ((c + 2 * k + 1) % 3)
                    elseif kind == "b" or kind == "B" then want = "bridge" end
                end
                if want then
                    set_mesh(p, want)
                    if not p.on then show(p.n, true); p.on = true end
                    if want == "bridge" then
                        local zg
                        if kind == "b" then zg = min(W.ground(name, 0, 0.47), W.ground(name, 0, -0.47))
                        else zg = min(W.ground(name, 0.47, 0), W.ground(name, -0.47, 0)) end
                        setpos(p.n, col_x(c), row_y(rho), Z0 + zg - 0.0008)
                        setrot(p.n, 0, kind == "b" and 0 or 90, 0)
                    else
                        local zg = W.ground(name, 0, 0, 0.36)
                        setpos(p.n, col_x(c), row_y(rho), Z0 + zg - 0.0005)
                        setrot(p.n, 0, ((c * 37 + k * 11) % 17) - 8, 0)
                    end
                    p.z = Z0 + 0
                elseif p.on then show(p.n, false); p.on = false end
            end
        end
    end
    -- the row being woven: loose weft on the bare warp
    local row_on = view.show_row ~= false and s >= 1
    for c = 0, COLS - 1 do
        local wf = W.weft[c]
        local k = st.cur and st.cur[c]
        if row_on and k then
            set_mesh(wf, "weft_" .. R.KIND_OF[k].wool)
            if not wf.on then show(wf.n, true); wf.on = true end
            setpos(wf.n, col_x(c), 0, 0)
        elseif wf.on then show(wf.n, false); wf.on = false end
    end
    -- cursor loop and shuttle (+ its pirn of the chosen wool), eased toward the cursor column
    local cur = view.cursor
    if cur then
        W.cx = W.cx + (cur - W.cx) * min(1, (view.dt or 1 / 60) * 14)
        if abs(W.cx - cur) < 0.002 then W.cx = cur end
    end
    show(W.cursor, cur ~= nil and row_on)
    if cur then setpos(W.cursor, col_x(cur), 0, 0) end
    local sx = col_x(view.shuttle_col or W.cx) + (view.dir or 1) * (CELL / 2 + 0.07)
    show(W.shuttle, view.show_row ~= false)
    show(W.pirn.n, view.show_row ~= false)
    setpos(W.shuttle, sx, 0, 0)
    setpos(W.pirn.n, sx, 0, 0)
    set_mesh(W.pirn, "pirn_" .. (view.pirn or "tan"))
    -- the traveller: cloth coordinates -> table, standing on the measured cloth of its cell
    local tw = view.walk
    if tw then
        local r = st.K - tw.k
        local rho = r - 1 + s
        local name = names[r] and names[r][tw.c]
        local zg = name and W.ground(name, tw.u, tw.v, 0.23) or 0
        local x, y = col_x(tw.c) + tw.u * CELL, row_y(rho) + tw.v * CELL
        W.trav_pos = { x = x, y = y, z = Z0 + zg - 0.0006 + (tw.bob or 0), name = name }
        setpos(W.trav, x, y, Z0 + zg - 0.0006 + (tw.bob or 0))
        setrot(W.trav, 0, tw.heading or -28, 0)
        show(W.trav, r < ROWS_FLAT)
    end
    -- the wool balls: size by the wool left (5 cooked fill levels)
    for _, b in ipairs(W.balls) do
        local left = st.wool[b.wool] or 0
        local lv = (b.wool == "cream" and not st.village) and 0 or min(4, ceil(left * 4 / R.MAXWOOL))
        set_mesh(b, "ball_" .. b.wool .. "_" .. lv)
        -- its shadow on the baked table: the sun's projection of the ball (an ellipse), a soft card
        if b.lv ~= lv then
            b.lv = lv
            local B = D.BALL
            local rb = (B.r0 ^ 3 + (B.r1 ^ 3 - B.r0 ^ 3) * lv / 4) ^ (1 / 3)
            local cz = B.cup_z + sqrt(max(rb * rb - B.cup_r * B.cup_r, 0))
            local sd = D.SUN_DIR
            local l = sqrt(sd[1] ^ 2 + sd[2] ^ 2 + sd[3] ^ 2)
            local se = sd[3] / l
            local ce = sqrt(1 - se * se)
            local hx, hy = -sd[1] / sqrt(sd[1] ^ 2 + sd[2] ^ 2), -sd[2] / sqrt(sd[1] ^ 2 + sd[2] ^ 2)
            local off = cz * ce / se
            setpos(b.shadow, b.x + hx * off, b.y + hy * off, 0.0012)
            setrot(b.shadow, 0, deg(atan2(-hx, hy)), 0)
            local wdt, len = 2 * rb * 1.3, 2 * rb / se * 1.45
            pcall(function() b.shadow:set_scale(v3(wdt, 1, len)) end)
        end
    end
    flush_xf()
    flush_mats()
    -- camera: the bake's camera; the vertical field is kept down to 16:9 and the horizontal one beyond it (wider
    -- windows crop the top and bottom, so the backdrop always covers the frame)
    local C = D.CAM
    local aspect = (view.aspect and view.aspect > 0) and view.aspect or C.aspect
    local hf = 2 * deg(math.atan(math.tan(rad(C.vfov) / 2) * min(aspect, C.aspect)))
    pcall(function() cam:set_fov(hf) end)
    pcall(function() cam:set_position(v3(C.pos[1], C.pos[2], C.pos[3])) end)
    pcall(function() cam:look_at(v3(C.target[1], C.target[2], C.target[3])) end)
    pcall(function() cam:set_f_stop(W.F_STOP or C.f_stop) end)
    pcall(function() cam:set_focus_distance(C.focus) end)
    pcall(function() cam:set_sensor_height(C.sensor_h) end)
end

-- Project a table point to window pixels (for the HUD's click targets on the row being woven).
function W.project(x, y, z, w, h)
    local C = D.CAM
    local ex, ey, ez = E(x, y, z)
    local px, py, pz = C.pos[1], C.pos[2], C.pos[3]
    local fx, fy, fz = C.target[1] - px, C.target[2] - py, C.target[3] - pz
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, ry, rz = fy * 0 - fz * 1, fz * 0 - fx * 0, fx * 1 - fy * 0     -- f x up(0,1,0)
    local rl = sqrt(rx * rx + ry * ry + rz * rz); rx, ry, rz = rx / rl, ry / rl, rz / rl
    local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    local dx, dy, dz = ex - px, ey - py, ez - pz
    local cz = dx * fx + dy * fy + dz * fz
    local cx = dx * rx + dy * ry + dz * rz
    local cy = dx * ux + dy * uy + dz * uz
    local aspect = w / h
    local tv = math.tan(rad(C.vfov) / 2)
    if aspect > C.aspect then tv = tv * C.aspect / aspect end
    local th = tv * aspect
    return w / 2 + cx / cz / th * w / 2, h / 2 - cy / cz / tv * h / 2
end

return W
end
