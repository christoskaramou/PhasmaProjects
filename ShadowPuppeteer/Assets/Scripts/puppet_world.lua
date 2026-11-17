-- Shadow Puppeteer world: the look slice. Everything is placed from sp_data.lua (generated from tools/sp_common.py).
-- Layers (LOOKPLAN.md): the live paper and floor (baked ambient as emissive, baked albedo as base colour, lit by the
-- lantern's point light), the props' shadows as planar silhouette cards on the paper, the cut-paper level, the
-- puppet, the props, lantern and candle as cooked meshes, dust and glow as particles, and the front card: the baked
-- theatre as full-window UI images, cross-faded between the lantern positions it was baked at.
-- Coordinates: stage (Blender) point (x, y, z) is engine (x, z, -y).
return function(D)
local W = { D = D }
local min, max, abs, floor, sqrt = math.min, math.max, math.abs, math.floor, math.sqrt
local deg, rad = math.deg, math.rad
local function v3(x, y, z) return vec3(x, y, z) end
local function E(x, y, z) return v3(x, z, -y) end          -- stage -> engine

------------------------------------------------------------------ state (what the player changes)
W.state = { lantern = { D.STATE_A.lantern[1], D.STATE_A.lantern[2] }, cup = D.STATE_A.cup, comb = D.STATE_A.comb,
    ladder = D.STATE_A.ladder, pose = "a", candle = D.STATE_A.candle, puppet = { D.STATE_A.puppet[1], D.STATE_A.puppet[2] } }
-- Calibrated against target_2560x1369.png in the Player (2026-11-13; inverse-ACES fit of the lantern, measured props)
W.TUNE = { lantern = 31.9, lantern_rgb = { 1.0, 0.768, 0.533 }, floor_gain = { 0.585, 0.589, 0.817 }, candle = 2.5, bounce = 2.17,
    bounce_rgb = { 1.0, 0.63, 0.1 }, gold = 1.0, flame = 6.0,
    brass_amb = 1.0,
    -- cut paper (black pieces and puppet, red door): fitted in the Player against target_2560x1369.png (2026-11-13:
    -- left cliff 34/20/5 vs 32/16/3, door 48/1/0 vs 46/6/0); the engine has no ambient, so "black" needs this albedo
    black = { 0.21, 0.19, 0.11 }, red = { 0.60, 0.19, 0.055 }, red_em = { 0.024, 0.008, 0.002 },
    -- comb (base factor over comb.png) and track rails: fitted in the Player against target_2560x1369.png
    comb = { 0.86, 0.85, 0.25 }, rail = { 0.40, 0.34, 0.035 }, rail_rough = 0.4, rail_em = { 0, 0, 0 },
    dust_size = { 0.0045, 0.007 }, dust_a = 1.0,   -- round soft motes (.0035-.006 read as 2 px grey squares, .005-.008 haloed)
    -- lantern light 10 cm above the shadow-casting flame point: the boards get the target's grazing light (probe
    -- review/fix2: floor MAD R 24.3 -> 17.6, paper 3.9 -> 4.4); shadow cards still project from D.LZ
    light_dz = 0.10 }
-- The props on stage now (a level's, or the reference frames' cup, comb and ladder) and where each one is: the game sets
-- W.placer(name) -> anchor x, height z, facing left (the rules' own R.prop_place, so a self-moving prop is drawn where
-- the rules have it); without one, x-track props sit at state[name] and the balloon at height state.balloon.
W.present = { cup = true, comb = true, ladder = true }
W.placer = nil
W.ax = {}                                     -- fixed anchor x of props that move in height (the balloon's string)
function W.prop_xz(name)
    if W.placer then return W.placer(name) end
    if D.PROP_MOVE[name] == "z" then return W.ax[name] or 0, W.state[name] or 0, false end
    return W.state[name], 0, false
end
-- present: the level's props; placer: see above; ax: fixed anchor x of height-moving props; id: the level ("1-3"
-- for the reference frames), whose cut paper is shown; its stage set's textures, shadow grey and bounce colour.
function W.set_level(present, placer, ax, id)
    W.present, W.placer, W.ax = {}, placer, ax or {}
    W.auto_props = false
    for name in pairs(present) do
        W.present[name] = true
        if D.PROP_MOVE[name] == "auto" then W.auto_props = true end
    end
    id = id or "1-3"
    W.level_id, W.level_tag = id, id:gsub("-", "_")
    local map = "stage"
    for _, l in ipairs(D.LEVELS) do if l.id == id then map = l.map end end
    W.set_map(map)
    W.vis = W.vis or {}
    for _, l in ipairs(D.LEVELS) do
        local tag = l.id:gsub("-", "_")
        for _, k in ipairs({ "paper_black_", "paper_red_", "paper_gold_" }) do
            local nm = "N_" .. k .. tag
            local on = tag == W.level_tag
            if W.vis[nm] ~= on then W.vis[nm] = on; local n = W.N[nm]; if n then pcall(function() n:set_enabled(on) end) end end
        end
    end
    for _, name in ipairs({ "cup", "comb", "ladder", "mouse" }) do
        for _, k in ipairs({ "N_track_slot_", "N_track_brass_" }) do
            local nm, on = k .. name, W.present[name] == true
            if W.vis[nm] ~= on then W.vis[nm] = on; local n = W.N[nm]; if n then pcall(function() n:set_enabled(on) end) end end
        end
    end
end

------------------------------------------------------------------ shadow geometry (the rule, shared with the tests)
function W.k(ly, prop_y) return (D.SY - ly) / (prop_y - ly) end
-- Shadow card of a prop at anchor x: engine position and uniform scale (the card mesh is the silhouette's bounding
-- box in prop-local units, so stage point (x + px, z) lands on screen point (lx + k (x + px - lx), lz + k (z - lz))).
function W.shadow_card(name, x, lx, ly, az)
    local k = W.k(ly, D.PROPS[name].y)
    return lx + k * (x - lx), D.LZ * (1 - k) + k * (az or 0), k
end

------------------------------------------------------------------ materials (engine quirk: writes replayed, as Topple)
local mat_q = {}
local function mset(n, k, v)
    if not n then return end
    pcall(material.set, n, k, v)
    mat_q[#mat_q + 1] = { n = n, k = k, v = v, c = 0 }
end
local function tset(n, slot, path)
    if not n then return end
    pcall(material.set_texture, n, slot, path)
    mat_q[#mat_q + 1] = { c = 0, f = function() pcall(material.set_texture, n, slot, path) end }
end
local function flush_mats()
    for i = #mat_q, 1, -1 do
        local q = mat_q[i]
        q.c = q.c + 1
        if q.c == 2 or q.c == 6 or q.c == 20 then
            if q.f then q.f() else pcall(material.set, q.n, q.k, q.v) end
        end
        if q.c >= 20 then table.remove(mat_q, i) end
    end
end
local function mat(n, base, metal, rough, emis)
    mset(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    mset(n, "emissive", v3(emis and emis[1] or 0, emis and emis[2] or 0, emis and emis[3] or 0))
    mset(n, "metallic", metal or 0)
    mset(n, "roughness", rough or 0.5)
end

------------------------------------------------------------------ nodes
W.N = {}
local function node(name) return W.N[name] end
local function place(name, p, s)
    local n = node(name)
    if not n then return end
    n:set_position(p)
    if s then n:set_scale(s) end
end
local function show(name, on)
    local n = node(name)
    if n then pcall(function() n:set_enabled(on) end) end
end

local BRASS, GOLD = { 0.82, 0.56, 0.26 }, { 0.9, 0.62, 0.22 }
-- The stage set (sp_common.MAPS): its baked paper, floor and far backdrop, its front cards, the grey of a shadow on
-- its paper and the colour its paper bounces back (sp_data.MAPLOOK, written by gen_meshes from the bakes).
W.map, W.front_tex = "stage", "Textures/"
function W.set_map(id)
    local look = D.MAPLOOK and D.MAPLOOK[id]
    if not look or W.map_set == id then W.map = id; return end
    W.map, W.map_set, W.front_tex = id, id, look.tex
    local N = W.N
    for _, nm in ipairs({ "paper", "floor" }) do
        tset(N["N_" .. nm], "base_color", look.tex .. "albedo.png")
        tset(N["N_" .. nm], "emissive", look.tex .. "backdrop_em.png")
    end
    tset(N.N_backdrop, "emissive", look.tex .. "backdrop_em.png")
    local sh = look.shadow
    for pname in pairs(D.PROPS) do
        for _, sfx in ipairs({ "", "_l" }) do
            for _, k in ipairs({ "N_shadow_", "N_shadowpen_" }) do
                local n = N[k .. pname .. sfx]
                if n then mset(n, "emissive", v3(sh[1], sh[2], sh[3])) end
            end
        end
    end
    -- the lantern's light bounced off this set's paper: the reference bounce colour times its paper over the first's
    local p0, p1 = D.MAPLOOK.stage.paper, look.paper
    local b = W.TUNE.bounce_rgb0 or W.TUNE.bounce_rgb
    W.TUNE.bounce_rgb0 = b
    local c = { b[1] * p1[1] / p0[1], b[2] * p1[2] / p0[2], b[3] * p1[3] / p0[3] }
    local m = max(c[1], c[2], c[3])
    W.TUNE.bounce_rgb = { c[1] / m, c[2] / m, c[3] / m }
    if W.inited then W.apply_lights(); W.update_front() end
end
function W.preload()
    local imgs, mats = { "Textures/ui_star_on.png", "Textures/ui_star_off.png" }, {}
    for _, mp in ipairs(D.MAPS) do
        local tex = D.MAPLOOK and D.MAPLOOK[mp.id] and D.MAPLOOK[mp.id].tex or "Textures/"
        for i = 0, #D.FRONT_X - 1 do
            for j = 0, #D.FRONT_Y - 1 do imgs[#imgs + 1] = string.format("%sfront_%d_%d.png", tex, i, j) end
        end
        mats[#mats + 1] = tex .. "albedo.png"
        mats[#mats + 1] = tex .. "backdrop_em.png"
    end
    pcall(runtime_ui.preload_images, imgs)
    pcall(material.preload_textures, mats)
    return imgs, mats
end
function W.apply_materials()
    local T = W.TUNE
    local N = W.N
    -- the live paper and floor: baked albedo (lit by the lantern) + baked ambient (fill, spots) as emissive
    for _, nm in ipairs({ "paper", "floor" }) do
        -- the floor's gain stands in for the varnished boards' sheen and the bounce the target has (fitted)
        local k = nm == "floor" and T.floor_gain or { 1, 1, 1 }
        mat(N["N_" .. nm], k, 0, nm == "paper" and 0.95 or 0.6, { 1, 1, 1 })
        tset(N["N_" .. nm], "base_color", "Textures/albedo.png")
        tset(N["N_" .. nm], "emissive", "Textures/backdrop_em.png")
    end
    mat(N.N_backdrop, { 0, 0, 0 }, 0, 1, { 1, 1, 1 })
    tset(N.N_backdrop, "emissive", "Textures/backdrop_em.png")
    -- the props' shadows: the silhouette's alpha, cut at 0.5; the colour of the paper without the lantern
    local s = D.EMISSIVE.shadow            -- lands on the target's shadow grey after the tone map (tools/engine_tone.py)
    for pname in pairs(D.PROPS) do for _, sfx in ipairs({ "", "_l" }) do
        local name = pname .. sfx              -- "_l": the mirrored card of a prop that turns round (the mouse)
        -- core: opaque, cut at the 50 % contour, so overlapping shadows are an exact union (sp_common.LAYER)
        local n = N["N_shadow_" .. name]
        if n then
            pcall(material.set_render_type, n, "alpha_cut")
            mat(n, { 0, 0, 0, 1 }, 0, 1, { s[1], s[2], s[3] })
            mset(n, "alpha_cutoff", 0.5)
            tset(n, "base_color", "Textures/silhouette_" .. name .. ".png")
        end
        -- penumbra: the same card blended just behind the core; the core hides its inner half, the soft outer ramp
        -- shows (cutoff ~0: the engine discards below the cutoff even when blending, GBufferPS.hlsl:77)
        local pn = N["N_shadowpen_" .. name]
        if pn then
            pcall(material.set_render_type, pn, "alpha_blend")
            -- 0.6: the ramp outside the core stays under 50 %, so the drawn 50 % contour is the core's (IoU)
            mat(pn, { 0, 0, 0, 0.6 }, 0, 1, { s[1], s[2], s[3] })
            mset(pn, "alpha_cutoff", 0.002)
            tset(pn, "base_color", "Textures/silhouette_" .. name .. ".png")
        end
    end end
    mat(N.N_cup, { 0.86, 0.78, 0.72 }, 0, 0.35, { 0.30, 0.24, 0.18 })   -- china: lantern + the target's bounce
    mat(N.N_cup_rim, GOLD, 0.55, 0.35, { 0.02, 0.012, 0.004 })
    mat(N.N_comb, T.comb, 0, 0.55, { 1, 1, 1 })
    tset(N.N_comb, "base_color", "Textures/comb.png")
    tset(N.N_comb, "emissive", "Textures/comb_teeth_em.png")  -- the teeth's reflection of the paper (gen_meshes)
    mat(N.N_ladder, { 1, 1, 1 }, 0, 0.5, { 0.01, 0.006, 0.002 })
    tset(N.N_ladder, "base_color", "Textures/ladder.png")
    local b = T.brass_amb
    -- brass: half metal (no IBL to reflect) with a warm floor, so it reads as lit brass, not black
    for _, nm in ipairs({ "lantern_brass", "candle_holder", "puppet_a_pins", "puppet_b_pins", "pp_pins" }) do
        mat(N["N_" .. nm], BRASS, 0.5, 0.3, { b, b * 0.57, b * 0.2 })
    end
    local g = N.N_lantern_glass
    if g then
        pcall(material.set_render_type, g, "alpha_blend")
        mat(g, { 1.0, 0.9, 0.75, 0.35 }, 0, 0.05, { 2.0, 1.7, 1.3 })   -- glass lit from inside
    end
    for _, nm in ipairs({ "lantern_flame", "candle_flame_100", "candle_flame_055", "candle_flame_030" }) do
        mat(N["N_" .. nm], { 0, 0, 0 }, 0, 1, { T.flame, T.flame * 0.52, T.flame * 0.16 })
    end
    for _, nm in ipairs({ "candle_wax_100", "candle_wax_055", "candle_wax_030" }) do
        mat(N["N_" .. nm], { 0.88, 0.8, 0.66 }, 0, 0.45, { 0.55, 0.3, 0.1 })   -- wax glows round the flame
    end
    for _, nm in ipairs({ "puppet_a", "puppet_b", "pp_body", "pp_leg_l", "pp_leg_r", "pp_arm_l", "pp_arm_r" }) do
        mat(N["N_" .. nm], T.black, 0, 0.85)
    end
    for _, tn in ipairs({ "cup", "comb", "ladder", "mouse" }) do
        mat(N["N_track_slot_" .. tn], { 0.012, 0.008, 0.006 }, 0, 0.9)        -- the groove: dark, recessed
        mat(N["N_track_brass_" .. tn], T.rail, 0, T.rail_rough, T.rail_em)
    end
    -- the clockwork mouse and the balloon: baked albedo, a little warmth so the unlit side is not black (no ambient)
    mat(N.N_mouse, { 1, 1, 1 }, 0.3, 0.4, { 0.03, 0.03, 0.035 })
    tset(N.N_mouse, "base_color", "Textures/mouse.png")
    mat(N.N_balloon, { 1, 1, 1 }, 0, 0.6, { 0.03, 0.02, 0.012 })
    tset(N.N_balloon, "base_color", "Textures/balloon.png")
    -- brass rail edges: a lit highlight like the target's (no IBL here, so not metallic: metal would render black)
    -- the lantern: baked sprites of the target's lantern (unlit cards, emissive = inverse ACES / LSPRITE_E)
    local E_ = D.LSPRITE_E or 4
    for i = 0, #D.FRONT_X - 1 do
        for j = 0, #D.FRONT_Y - 1 do
            local n = N[string.format("N_lsprite_%d_%d", i, j)]
            if n then
                -- opaque, cut at 50 %: TAA antialiases the outline like the cliffs'. Blended, its edge pixels mixed
                -- the card's G-buffer (normal facing away from the lantern) into the floor's: a jagged dark fringe
                pcall(material.set_render_type, n, "alpha_cut")
                mat(n, { 0, 0, 0, 1 }, 0, 1, { E_, E_, E_ })
                mset(n, "alpha_cutoff", 0.3)    -- 0.5 thinned the right brass rod and notched the glass edge
                tset(n, "base_color", string.format("Textures/lsprite_%d_%d.png", i, j))
                tset(n, "emissive", string.format("Textures/lsprite_%d_%d_em.png", i, j))
            end
        end
    end
    local g = D.EMISSIVE.gold              -- painted gold paper: its own floor, bright wherever the lantern is
    for _, l in ipairs(D.LEVELS) do
        local tag = l.id:gsub("-", "_")
        mat(N["N_paper_black_" .. tag], T.black, 0, 0.85)
        mat(N["N_paper_red_" .. tag], T.red, 0, 0.8, T.red_em)
        mat(N["N_paper_gold_" .. tag], GOLD, 0.55, 0.35, { g[1] * T.gold, g[2] * T.gold, g[3] * T.gold })
    end
end

------------------------------------------------------------------ lights and particles
local function find_light(name)
    local ok, r = pcall(lights.find, name)
    if not ok or not r then return nil end
    for _, l in ipairs(r) do if l.name == name then return l end end
    return nil
end
function W.apply_lights()
    local T = W.TUNE
    -- light colours: with linear_color on the engine decodes them as sRGB, so the fitted linear colour is passed encoded
    -- fitted per channel against target_2560x1369.png (calib: inverse-ACES of the screenshots and the target)
    local ly = W.state.lantern[2]
    local bounce = T.bounce * ((D.SY - D.STATE_A.lantern[2]) / (D.SY - ly)) ^ 2
    for name, rec in pairs({ LanternLight = { T.lantern, T.lantern_rgb }, CandleLight = { T.candle, T.lantern_rgb },
        BounceLight = { bounce, T.bounce_rgb } }) do
        local l = find_light(name)
        if l then
            pcall(lights.set_property, l.type, l.index, "intensity", rec[1])
            pcall(lights.set_property, l.type, l.index, "color", v3(rec[2][1], rec[2][2], rec[2][3]))
            pcall(lights.set_property, l.type, l.index, "radius", 40.0)
        end
    end
end
-- Dust lives in the lantern's light: one emitter round the flame, one a third of the way along the beam toward the
-- paper; motes drift slowly and fade out within a few seconds, so they never reach the dark corners.
local function emitters()
    if W.em then return end
    W.em = {}
    local function add(k, o)
        o.color_start, o.color_end = W.PART[k][1], W.PART[k][2]
        local ok, i = pcall(particles.add_emitter, o)
        W.em[k] = ok and i or nil
    end
    add("dust", { position = v3(0, 0.2, 0), velocity = v3(0, 0.01, 0), gravity = v3(0, 0, 0), count = 24, size_min = W.TUNE.dust_size[1],
        size_max = W.TUNE.dust_size[2], life_min = 2.5, life_max = 4.5, spawn_rate = 5, spawn_radius = 0.3, noise_strength = 0.03, drag = 0.5 })
    add("beam", { position = v3(0, 0.4, 0), velocity = v3(0, 0.008, 0), gravity = v3(0, 0, 0), count = 24, size_min = W.TUNE.dust_size[1],
        size_max = W.TUNE.dust_size[2], life_min = 2.5, life_max = 4.5, spawn_rate = 5, spawn_radius = 0.45, noise_strength = 0.03, drag = 0.5 })
    add("halo", { position = v3(0, 0.12, 0), velocity = v3(0, 0, 0), gravity = v3(0, 0, 0), count = 6, size_min = 0.2,
        size_max = 0.22, life_min = 0.25, life_max = 0.3, spawn_rate = 22, spawn_radius = 0.0, noise_strength = 0, drag = 0 })
end

-- Dust and the lantern's halo on or off (measurement frames: motes drifting over a shadow are not its outline).
-- sparse, small, near-white points like the target's motes (2026-11-13: half the earlier rate, smaller)
W.PART = { dust = { vec4(1.0, 0.97, 0.92, W.TUNE.dust_a), vec4(1.0, 0.94, 0.86, 0.0) },
    beam = { vec4(1.0, 0.97, 0.92, W.TUNE.dust_a * 0.8), vec4(1.0, 0.94, 0.86, 0.0) },
    halo = { vec4(0.09, 0.05, 0.02, 0.35), vec4(0.09, 0.05, 0.02, 0.0) } }
function W.set_particles(on)
    W.particles_on = on
    for k, c in pairs(W.PART) do
        if W.em and W.em[k] then
            local z = vec4(0, 0, 0, 0)
            pcall(particles.set_emitter, W.em[k], { color_start = on and c[1] or z, color_end = on and c[2] or z })
        end
    end
end

------------------------------------------------------------------ the front card (UI images over the 3D)
W.FRONT = {}
-- Bilinear weights over the bake grid for the lantern at (lx, ly): list of { i, j, w } (up to 4, sum 1).
function W.front_weights(lx, ly)
    local X, Y = D.FRONT_X, D.FRONT_Y
    local i = 1
    while i < #X - 1 and lx > X[i + 1] do i = i + 1 end
    local t = max(0, min(1, (lx - X[i]) / (X[i + 1] - X[i])))
    local s = max(0, min(1, (ly - Y[1]) / (Y[2] - Y[1])))
    local out = {}
    for _, c in ipairs({ { i, 1, (1 - t) * (1 - s) }, { i + 1, 1, t * (1 - s) }, { i, 2, (1 - t) * s }, { i + 1, 2, t * s } }) do
        if c[3] > 1e-4 then out[#out + 1] = c end
    end
    return out
end
local UI = "puppet"                       -- the game's one overlay screen (puppet.lua sets it up)
function W.front_layout(sw, sh)
    local h = sh
    local w = h * D.WIDE[1] / D.WIDE[2]
    return (sw - w) / 2, 0, w, h
end
function W.update_front()
    local sw, sh = W.screen_size()
    local x, y, w, h = W.front_layout(sw, sh)
    local ws = W.front_weights(W.state.lantern[1], W.state.lantern[2])
    -- over-compositing: layer m gets alpha w_m / (w_1 + .. + w_m), so the stack is the weighted mean
    local acc = 0
    for m = 1, 4 do
        local c = ws[m]
        local id = "front" .. m
        if c then
            acc = acc + c[3]
            local a = c[3] / acc
            local path = string.format("%sfront_%d_%d.png", W.front_tex or "Textures/", c[1] - 1, c[2] - 1)
            local q = { style = "image", path = path, x = x, y = y, width = w, height = h, z = 4 + m, no_input = true,
                visible = W.front_on ~= false, image_tint = { 1, 1, 1, a }, fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 } }
            runtime_ui.set_quad(UI, id, q)
            W.FRONT[m] = q
        elseif W.FRONT[m] then
            W.FRONT[m] = nil
            runtime_ui.set_quad(UI, id, { visible = false, x = 0, y = 0, width = 1, height = 1, no_input = true })
        end
    end
end

------------------------------------------------------------------ init
function W.screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 720
end
function W.apply_look()
    -- ACES tone map on (the only operator: Tonemap.hlsl ACESFitted): it rolls the lantern's hot spot off like the
    -- target's AgX instead of clipping; every baked emissive is fed through its inverse (tools/engine_tone.py).
    -- linear_color: textures decoded from sRGB, light added in linear space (inverse-square falloff as in Cycles),
    -- one sRGB encode after the tone map. Off (the default) the engine lights and tone-maps sRGB values directly.
    for k, v in pairs({ tonemapping = true, bloom = false, render_scale = 1.0, taa = true, fxaa = true, cas_sharpening = false,
        motion_blur = false, ssao = false, ssr = false, IBL = false, shadows = false, color_grading = false, dof = false,
        fog = false, physical_point_falloff = true, linear_color = true }) do pcall(settings.set, k, v) end
end
local cam
function W.init()
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    pcall(settings.set_render_mode, "raster")
    W.apply_look()
    for _, name in ipairs(D.MESHES) do
        W.N["N_" .. name] = scene.find_model and scene.find_model("N_" .. name) or nil
    end
    W.N.LanternLight = scene.find_model and scene.find_model("LanternLight") or nil
    W.N.CandleLight = scene.find_model and scene.find_model("CandleLight") or nil
    W.N.BounceLight = scene.find_model and scene.find_model("BounceLight") or nil
    W.apply_materials()
    W.apply_lights()
    emitters()
    W.init_puppet()
    -- every stage set's bakes loaded before the first frame: the front cards are UI images loaded on first use (each
    -- new one stalled a frame ~95 ms; all ten of a set 767 ms, live profile 2026-11-13: a stutter whenever the lantern
    -- first entered a bake cell), the paper and floor bakes one dropped frame per set
    W.preloaded_images, W.preloaded_textures = W.preload()
    W.set_level({ cup = true, comb = true, ladder = true }, nil, nil, "1-3")
    W.inited = true
    W.apply()
end

------------------------------------------------------------------ placing everything from the state
function W.apply()
    local st, L = W.state, D.LAYER
    local lx, ly = st.lantern[1], st.lantern[2]
    -- the lantern is drawn by the nearest baked sprite (live brass/glass/flame meshes stay hidden)
    for _, nm in ipairs({ "lantern_brass", "lantern_glass", "lantern_flame" }) do show("N_" .. nm, false) end
    local bi, bj, bd = 0, 0, math.huge
    for i, fx in ipairs(D.FRONT_X) do
        for j, fy in ipairs(D.FRONT_Y) do
            local d = (fx - lx) ^ 2 + (fy - ly) ^ 2             -- grid: the nearest x and the nearest depth
            if d < bd then bi, bj, bd = i - 1, j - 1, d end
        end
    end
    local cur = string.format("N_lsprite_%d_%d", bi, bj)
    if W.ls_cur ~= cur then                                  -- pooled cards: show the nearest view, hide the rest
        for i = 0, #D.FRONT_X - 1 do
            for j = 0, #D.FRONT_Y - 1 do
                local nm = string.format("N_lsprite_%d_%d", i, j)
                show(nm, nm == cur)
            end
        end
        W.ls_cur = cur
    end
    place(cur, E(lx, ly, 0))
    place("LanternLight", E(lx, ly, D.LZ + (W.TUNE.light_dz or 0)))
    place("BounceLight", E(lx * D.BOUNCE.x_follow, D.SY + D.BOUNCE.behind, D.BOUNCE.z))
    if W.T_ly ~= ly then W.T_ly = ly; W.apply_lights() end
    if W.em and W.em.dust then
        -- motes hang in the light: round the flame, and a third of the way along the beam to the paper
        pcall(particles.set_emitter, W.em.dust, "position", E(lx, ly + 0.15, D.LZ + 0.18))
        pcall(particles.set_emitter, W.em.beam, "position", E(lx * 0.75, ly + (D.SY - ly) * 0.33, 0.45))
    end
    if W.em and W.em.halo then pcall(particles.set_emitter, W.em.halo, "position", E(lx, ly, D.LZ)) end
    -- props: absent ones (not in this level) hidden; present ones placed with their shadow (the mouse running left
    -- shows its mirrored card); visibility is only written when it changes
    W.vis = W.vis or {}
    local function vis(nm, on) if W.vis[nm] ~= on then W.vis[nm] = on; show(nm, on) end end
    for name, p in pairs(D.PROPS) do
        local x, z, left
        if W.present[name] then x, z, left = W.prop_xz(name) end
        local on = x ~= nil
        local sfx = (on and left and W.N["N_shadow_" .. name .. "_l"]) and "_l" or ""
        vis("N_" .. name, on)
        if name == "cup" then vis("N_cup_rim", on) end
        for _, s in ipairs({ "", "_l" }) do
            vis("N_shadow_" .. name .. s, on and s == sfx)
            vis("N_shadowpen_" .. name .. s, on and s == sfx)
        end
        if on then
            place("N_" .. name, E(x, p.y, z))
            local n3 = node("N_" .. name)
            if n3 and D.PROP_MOVE[name] == "auto" then n3:set_rotation(v3(0, left and 180 or 0, 0)) end
            if name == "cup" then place("N_cup_rim", E(x, p.y, z)) end
            local cx, cy, k = W.shadow_card(name, x, lx, ly, z)
            place("N_shadow_" .. name .. sfx, v3(cx, cy, -D.SY + L.shadow), v3(k, k, 1))
            place("N_shadowpen_" .. name .. sfx, v3(cx, cy, -D.SY + L.penumbra), v3(k, k, 1))
        end
    end
    for _, nm in ipairs({ "paper_black_", "paper_red_", "paper_gold_" }) do place("N_" .. nm .. (W.level_tag or "1_3"), v3(0, 0, -D.SY + L.paper)) end
    -- the look frames show the art's own poses (puppet_a / _b); play shows the jointed puppet the rules walk
    local look = st.pose == "a" or st.pose == "b"
    for _, pose in ipairs({ "a", "b" }) do
        local on = st.pose == pose
        show("N_puppet_" .. pose, on)
        show("N_puppet_" .. pose .. "_pins", on)
        place("N_puppet_" .. pose, v3(st.puppet[1], st.puppet[2], -D.SY + L.puppet))
        place("N_puppet_" .. pose .. "_pins", v3(st.puppet[1], st.puppet[2], -D.SY + L.puppet))
    end
    for _, nm in ipairs(W.PP) do show("N_" .. nm, not look) end
    W.place_candle(st.candle)
    W.update_front()
end

-- The candle burns down continuously: the fresh candle's wax scaled to what is left, its flame and light on top.
local WAX_TOP = 0.035 + 0.30                 -- the fresh wax's height (scene.candle at left = 1)
function W.place_candle(left)
    local cx, cy = D.CANDLE[1], D.CANDLE[2]
    left = max(0.02, min(1, left))
    local h = 0.035 + 0.30 * left
    place("N_candle_holder", E(cx, cy, 0))
    place("N_candle_wax_100", E(cx, cy, 0), v3(1, h / WAX_TOP, 1))
    place("N_candle_flame_100", E(cx, cy, h - WAX_TOP))
    for _, t in ipairs({ "055", "030" }) do show("N_candle_wax_" .. t, false); show("N_candle_flame_" .. t, false) end
    place("CandleLight", E(cx, cy, h + 0.03))
end

------------------------------------------------------------------ the jointed puppet (play)
W.PP = { "pp_body", "pp_pins", "pp_leg_l", "pp_leg_r", "pp_arm_l", "pp_arm_r" }
local PS = D.PUPPET.scale
local HIP, SHOULDER = D.PUPPET.hip * PS, D.PUPPET.shoulder * PS
-- the torso's back edge (scene.py puppet_parts: x -0.024 at the hip, prop units x scale): sliding, it lies on the face
local SLIDE_BACK = 0.024 * PS
function W.init_puppet()
    if W.pp_root then return end
    W.pp_root = scene.add_empty_node("pp_root")
    local local_pos = { pp_body = { 0, 0, 0 }, pp_pins = { 0, 0, 0 }, pp_leg_l = { 0, HIP, -0.0012 }, pp_leg_r = { 0, HIP, 0.0012 },
        pp_arm_l = { 0, SHOULDER, -0.0012 }, pp_arm_r = { 0, SHOULDER, 0.0012 } }
    for _, nm in ipairs(W.PP) do
        local n = W.N["N_" .. nm]
        if n then
            pcall(function() n:set_parent(W.pp_root) end)
            local q = local_pos[nm]
            n:set_position(v3(q[1], q[2], q[3]))
        end
    end
end
-- Pose from the rules' state p = { x, y, dir, mode, phase, dead, t_end }: walk swings legs and arms, climb reaches up
-- hand over hand, fall throws the arms up, death tips the puppet over, a win waves both arms.
function W.pose_puppet(p, t)
    if not W.pp_root then return end
    local s = math.sin((p.phase or 0) * math.pi)
    local legl, legr, arml, armr = 0, 0, 0, 0
    local tilt, sink, ox, oy = 0, 0, 0, 0
    -- a short hop down (a step, a steep bit stepped off) keeps the walk; the fall pose shows once it drops fast
    local falling = p.mode == "fall" and (p.vy or -9) < -0.5
    -- the stride shrinks on slopes: a rigid leg swung by a sits L sin(a) along the ground, L sin(a) tan(slope) off it,
    -- so a is held to 2 px (0.0063) of that (the rules stand the shoe itself on the ground: legs together are exact)
    if W.pp_prev and abs(p.x - W.pp_prev[1]) > 1e-5 and p.mode == "walk" then
        W.pp_tan = abs(p.y - W.pp_prev[2]) / abs(p.x - W.pp_prev[1])
    end
    W.pp_prev = { p.x, p.y }
    local amp = 24
    if (W.pp_tan or 0) > 0.01 then amp = min(24, math.deg(math.asin(min(1, 0.0063 / (W.pp_tan * HIP))))) end
    W.pp_amp = (W.pp_amp or amp) + (amp - (W.pp_amp or amp)) * 0.35
    if p.mode == "walk" or (p.mode == "fall" and not falling) then
        legl, legr, arml, armr = W.pp_amp * s, -W.pp_amp * s, -20 * s, 20 * s
    elseif p.mode == "climb" then
        -- hand over hand: one hand reaches up the ladder while the other pulls level with the shoulder, and the knee on
        -- the pulling side lifts to the next rung (straight up at 150 deg the arms hid behind the hat: read as walking)
        legl, legr = 34 * max(0, s), 34 * max(0, -s)
        arml, armr = 128 + 38 * s, 128 - 38 * s
    elseif p.mode == "slide" then
        -- sliding down a face too steep to stand on: the body lies back along it (lean = 90 - slope), knees up, arms up
        local th = rad(p.slope or D.RULES.max_slope)
        tilt = 90 - deg(th)
        local back = SLIDE_BACK                         -- the coat's back edge: on the face (rules: contact at p.x, p.y)
        ox, oy = (p.dir or 1) * math.sin(th) * back, math.cos(th) * back
        legl, legr, arml, armr = 28 + 6 * s, 20 - 6 * s, 150, 118
    elseif falling then
        legl, legr, arml, armr = 10, -6, 145, 125
    elseif p.mode == "won" then
        local w = math.sin(t * 9)
        legl, legr, arml, armr = 4, -4, 160 + 12 * w, 160 - 12 * w
    elseif p.mode == "dead" then
        local u = min(1, (t - (p.t_end or t)) / 0.45)
        tilt = -84 * u
        sink = (p.dead == "thorns" and 0.05 or 0) * u
        legl, legr, arml, armr = 20, -10, 40, 60
    end
    W.pp_root:set_position(v3(p.x + ox, p.y - sink + oy, -D.SY + D.LAYER.puppet))
    W.pp_pose = { x = p.x + ox, y = p.y - sink + oy, tilt = tilt, mode = p.mode }     -- for view_smoke
    W.pp_root:set_rotation(v3(0, p.dir < 0 and 180 or 0, tilt))
    local function rot(nm, a) local n = W.N["N_" .. nm]; if n then n:set_rotation(v3(0, 0, a)) end end
    rot("pp_leg_l", legl); rot("pp_leg_r", legr); rot("pp_arm_l", arml); rot("pp_arm_r", armr)
end

-- Exactly the reference frames (target.png = A, target_b.png = B).
function W.set_state(which)
    local S = which == "b" and D.STATE_B or D.STATE_A
    W.state = { lantern = { S.lantern[1], S.lantern[2] }, cup = S.cup, comb = S.comb, ladder = S.ladder, pose = which == "b" and "b" or "a",
        candle = S.candle, puppet = { S.puppet[1], S.puppet[2] } }
    W.set_level({ cup = true, comb = true, ladder = true }, nil, nil, "1-3")
    W.apply()
end

------------------------------------------------------------------ per frame
local t = 0
function W.update(dt)
    t = t + dt
    flush_mats()
    local sw, sh = W.screen_size()
    pcall(function() cam:set_fov(deg(2 * math.atan(math.tan(rad(D.CAM.vfov / 2)) * sw / max(1, sh)))) end)
    local p, l = D.CAM.pos, D.CAM.look
    cam:set_position(v3(p[1], p[2], p[3]))
    cam:look_at(v3(l[1], l[2], l[3]))
    W.vp, W.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    local ok, j = pcall(function() return cam:get_jitter() end)
    W.jx, W.jy = ok and j and j.x or 0, ok and j and j.y or 0
    if W.sw ~= sw or W.sh ~= sh then W.sw, W.sh = sw, sh; W.update_front() end
end

------------------------------------------------------------------ picking (Topple's method: mouse ray against a plane)
local function flip()
    if W.flip == nil then
        local vp = W.vp or cam:get_view_projection()
        local a, b = vp * vec4(0, 6, -3, 1), vp * vec4(0, 1, -3, 1)
        W.flip = (a.y / a.w) > (b.y / b.w)
    end
    return W.flip
end
-- Stage point -> window pixels (jitter-free).
function W.project(x, y, z)
    local vp = W.vp or cam:get_view_projection()
    local c = vp * vec4(x, z, -y, 1)
    if c.w <= 1e-5 then return nil end
    local sw, sh = W.screen_size()
    local nx, ny = c.x / c.w - (W.jx or 0), c.y / c.w - (W.jy or 0)
    return (nx * 0.5 + 0.5) * sw, (flip() and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)) * sh
end
local function ray(mx, my)
    local inv = W.inv or cam:get_inv_view_projection()
    local sw, sh = W.screen_size()
    local nx = mx / sw * 2 - 1 + (W.jx or 0)
    local ny = (flip() and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (W.jy or 0)
    local a, b = inv * vec4(nx, ny, 0.25, 1), inv * vec4(nx, ny, 0.75, 1)
    return { a.x / a.w, a.y / a.w, a.z / a.w }, { b.x / b.w, b.y / b.w, b.z / b.w }
end
-- Mouse -> stage point on the floor (z = 0).
function W.floor_point(mx, my)
    local a, b = ray(mx, my)
    if abs(b[2] - a[2]) < 1e-9 then return nil end
    local s = (0 - a[2]) / (b[2] - a[2])
    return a[1] + (b[1] - a[1]) * s, -(a[3] + (b[3] - a[3]) * s)
end
-- Mouse -> stage x on the upright plane y = depth (a prop's track).
function W.track_point(mx, my, depth)
    local a, b = ray(mx, my)
    if abs(b[3] - a[3]) < 1e-9 then return nil end
    local s = (-depth - a[3]) / (b[3] - a[3])
    return a[1] + (b[1] - a[1]) * s
end
-- Mouse -> stage height z on the upright plane y = depth (the balloon's pole).
function W.track_height(mx, my, depth)
    local a, b = ray(mx, my)
    if abs(b[3] - a[3]) < 1e-9 then return nil end
    local s = (-depth - a[3]) / (b[3] - a[3])
    return a[2] + (b[2] - a[2]) * s
end
-- What is under the mouse: "lantern" or a prop name (front-most first), by its projected bounding box.
function W.pick(mx, my)
    local st = W.state
    local cands = { { "lantern", st.lantern[1], st.lantern[2], -0.11, 0.11, 0.45 } }
    for name, p in pairs(D.PROPS) do
        local mv = D.PROP_MOVE[name]
        if W.present[name] and (mv == "x" or mv == "z") then
            local b = p.bbox
            local x, z = W.prop_xz(name)
            if x then cands[#cands + 1] = { name, x, p.y, b[1], b[3], b[4], z or 0 } end
        end
    end
    table.sort(cands, function(a, b) return a[3] < b[3] end)
    for _, c in ipairs(cands) do
        local z0 = c[7] or 0
        local x0, y0 = W.project(c[2] + c[4], c[3], z0 + c[6])
        local x1, y1 = W.project(c[2] + c[5], c[3], z0)
        if x0 and x1 and mx >= min(x0, x1) - 10 and mx <= max(x0, x1) + 10 and my >= min(y0, y1) - 10 and my <= max(y0, y1) + 10 then
            return c[1]
        end
    end
    return nil
end
local function clamp(v, r) return max(r[1], min(r[2], v)) end
function W.drag_begin(what, mx, my)
    local st = W.state
    if what == "lantern" then
        local x, y = W.floor_point(mx, my)
        if not x then return nil end
        return { what = what, dx = st.lantern[1] - x, dy = st.lantern[2] - y }
    end
    if D.PROP_MOVE[what] == "z" then
        local z = W.track_height(mx, my, D.PROPS[what].y)
        if not z then return nil end
        return { what = what, dz = (st[what] or 0) - z }
    end
    local x = W.track_point(mx, my, D.PROPS[what].y)
    if not x then return nil end
    return { what = what, dx = st[what] - x }
end
function W.drag_move(g, mx, my)
    local st = W.state
    if g.what == "lantern" then
        local x, y = W.floor_point(mx, my)
        if not x then return end
        st.lantern[1], st.lantern[2] = clamp(x + g.dx, D.LANTERN_X), clamp(y + g.dy, D.LANTERN_Y)
    elseif g.dz then
        local z = W.track_height(mx, my, D.PROPS[g.what].y)
        if not z then return end
        st[g.what] = clamp(z + g.dz, D.PROPS[g.what].z)
    else
        local x = W.track_point(mx, my, D.PROPS[g.what].y)
        if not x then return end
        st[g.what] = clamp(x + g.dx, D.PROPS[g.what].x)
    end
    W.apply()
end
return W
end
