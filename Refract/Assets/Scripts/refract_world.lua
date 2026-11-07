-- Refract 3D world: the board as a lit neon scene (PBR blocks, a mirror-polished channel, emissive
-- beams under bloom, coloured point lights, GPU particles). The HUD stays runtime UI on top.
-- Board cell (x, y) maps to world (x - (W+1)/2, *, y - (H+1)/2); y is up, the camera looks down from +z.
return function(R)
local W = {}
local floor, min, max, abs, sin, cos = math.floor, math.min, math.max, math.abs, math.sin, math.cos
local function v3(x, y, z) return vec3(x, y, z) end

local BLOCK_H = 0.26      -- ground block height; the lane is the floor between blocks
local BEAM_Y = 0.42       -- light travels at this height, through enemies in the lane
local MAX_BEAM_LIGHTS = 36
local LIGHT = { w = { 1, 0.9, 0.72 }, r = { 1, 0.1, 0.18 }, g = { 0.15, 1, 0.35 }, b = { 0.15, 0.32, 1 } }
local TIER = { { 0.35, 0.8, 1 }, { 1, 0.72, 0.2 }, { 1, 0.3, 0.9 } }
W.LIGHT = LIGHT

local cam
local S = { t = 0, shake = 0, surge = 0, flash = 0, flash_c = { 1, 1, 1 }, flash_x = 0, flash_z = 0, flip = nil }
local board_nodes, piece_nodes, enemy_nodes = {}, {}, {}
local lane_tiles = {}         -- cell index -> emissive floor tile in the lane
local beam_pool, beam_used = {}, 0
local LT = {}                 -- point light indices
-- The engine copies each light's position from its scene node every frame, so set_point_light's position alone is
-- overwritten and every lamp stays at the origin. Move the node too (looked up once per lamp), as 1942Remix does.
local LNODE = {}
local function point_light(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten, rad)
    local n = LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model and scene.find_model(l.name)) or false
        LNODE[i] = n
    end
    if n then n:set_position(pos) end
end
local function light_off(i) point_light(i, v3(0, -50, 0), v3(0, 0, 0), 0, 0.1) end
local core, gate = {}, {}
local cursor = {}
local ghost = { key = nil, nodes = {} }
local impacts, impact_t = {}, 0
local dust_emitter, rift_emitter, core_emitter
local scale_particles = function() return 1 end
local scale_shake = function() return 1 end

-- Visual strength of a beam: saturates, so stacked lenses (x1.5 each) cannot blow out the image.
local function vis(pw) return 1 - math.exp(-pw / 26) end
W.vis = vis

local function wx(x) return x - (R.W + 1) / 2 end
local function wz(y) return y - (R.H + 1) / 2 end
W.wx, W.wz = wx, wz

------------------------------------------------------------------ materials
local function mat(n, base, emis, metal, rough)
    material.set(n, "base_color", vec4(base[1], base[2], base[3], base[4] or 1))
    material.set(n, "emissive", v3(emis[1], emis[2], emis[3]))
    material.set(n, "metallic", metal or 0.5)
    material.set(n, "roughness", rough or 0.4)
end
local function glow(n, c, e, metal)
    mat(n, { c[1] * 0.25, c[2] * 0.25, c[3] * 0.25 }, { c[1] * e, c[2] * e, c[3] * e }, metal or 0.2, 0.35)
end
local function emis(n, c, e) material.set(n, "emissive", v3(c[1] * e, c[2] * e, c[3] * e)) end
local function place(n, parent, x, y, z, sx, sy, sz)
    if parent then n:set_parent(parent) end
    n:set_position(v3(x, y, z))
    if sx then n:set_scale(v3(sx, sy, sz)) end
    return n
end
local function box(list, parent, x, y, z, sx, sy, sz)
    local n = place(primitives.cube(1), parent, x, y, z, sx, sy, sz)
    if list then list[#list + 1] = n end
    return n
end
local function ghostify(n, a)
    pcall(material.set_render_type, n, "alpha_blend")
    material.set(n, "base_color", vec4(0.5, 0.8, 1, a))
end
local function remove_all(list)
    for i = #list, 1, -1 do pcall(function() list[i]:remove() end); list[i] = nil end
end

------------------------------------------------------------------ init: renderer, camera, lights, backdrop
function W.init(opts)
    scale_particles = opts and opts.particle_scale or scale_particles
    scale_shake = opts and opts.shake_scale or scale_shake
    cam = scene.get_active_camera()
    pcall(function() cam:set_projection_mode("perspective") end)
    pcall(function() cam:perspective() end)
    cam:set_fov(38)
    -- Post-processing (TAA jitter, bloom, tonemapping, colour grading, ...) only runs when the scene has
    -- a Scene Settings node; loaded scenes do not get one by default, so without this TAA is a no-op.
    if not W.settings_node then
        W.settings_node = scene.add_empty_node("Scene Settings")
        pcall(function() W.settings_node:set_scene_settings(true) end)
    end
    -- Raster: the engine's hybrid default refits a ray-tracing TLAS every frame, which can fault the GPU.
    pcall(settings.set_render_mode, "raster")
    settings.set("bloom", true)
    settings.set("bloom_strength", 1.0)       -- full strength now that the Scene Settings node enables it
    settings.set("bloom_range", 1.0)        -- tight tap spacing: wider spacing stair-steps the bloom
    -- Anti-aliasing: TAA on full-resolution rendering (the engine starts at 0.75 scale, which the
    -- settings menu would keep as its baseline). FXAA off: on top of TAA it only blurs.
    settings.set("render_scale", 1.0)
    settings.set("taa", true)
    settings.set("cas_sharpening", false)
    settings.set("motion_blur", false)
    settings.set("tonemapping", true)
    settings.set("fxaa", false)
    settings.set("ssao", true)
    settings.set("ssr", true)
    settings.set("IBL_intensity", 0.7)
    settings.set("shadows", false)            -- the board is lit from above; shadows only blacken the blocks
    settings.set("color_grading", false)      -- crushes the dark blocks; the neon palette is saturated already
    pcall(function() lights.set_directional_light(0, v3(-8, 30, 14), v3(0.62, 0.7, 1.0), 4.0) end)
    pcall(function()
        local base = #lights.get_point_lights()
        for _ = 1, MAX_BEAM_LIGHTS + 4 do lights.add_point() end
        for i = 0, MAX_BEAM_LIGHTS - 1 do LT[i + 1] = base + i end
        LT.core, LT.gate, LT.flash, LT.boss = base + MAX_BEAM_LIGHTS, base + MAX_BEAM_LIGHTS + 1, base + MAX_BEAM_LIGHTS + 2, base + MAX_BEAM_LIGHTS + 3
        -- New lamps default to intensity 1, radius 10 at the origin; keep them dark until first set.
        for i = base, base + MAX_BEAM_LIGHTS + 3 do light_off(i) end
    end)

    -- Deep space below and behind the board: a dark plane, stars and nebula glows.
    local back = primitives.plane(220, 160)
    back:set_position(v3(0, -14, -20))
    mat(back, { 0, 0, 0.01 }, { 0.002, 0.003, 0.012 }, 0, 1)
    math.randomseed(4242)
    W.stars = {}
    for _ = 1, 220 do
        local s = primitives.cube(1)
        local sz = 0.06 + math.random() * 0.12
        s:set_position(v3((math.random() - 0.5) * 120, -13.5 + math.random() * 2, (math.random() - 0.5) * 90 - 16))
        s:set_scale(v3(sz, sz, sz))
        local tint = ({ { 1, 1, 1 }, { 0.6, 0.8, 1 }, { 1, 0.8, 0.6 }, { 0.8, 0.6, 1 } })[math.random(4)]
        local e = 1.5 + math.random() * 5
        glow(s, tint, e, 0)
        W.stars[#W.stars + 1] = { n = s, c = tint, e = e, ph = math.random() * 6.28, sp = 0.4 + math.random() * 2 }
    end
    for _, nb in ipairs({ { -30, -12, -30, 16, { 0.35, 0.05, 0.55 } }, { 34, -12, -8, 18, { 0.02, 0.18, 0.45 } }, { 4, -13, -46, 14, { 0.4, 0.05, 0.3 } } }) do
        local s = primitives.sphere(nb[4]); s:set_position(v3(nb[1], nb[2], nb[3]))
        mat(s, { 0, 0, 0 }, { nb[5][1] * 0.1, nb[5][2] * 0.1, nb[5][3] * 0.1 }, 0, 1)
    end
    dust_emitter = particles.add_emitter({ name = "refract_dust", position = v3(0, 0.6, 0), velocity = v3(0, 0.12, 0),
        color_start = vec4(0.5, 0.6, 1.4, 0.7), color_end = vec4(0.6, 0.3, 1.0, 0), gravity = v3(0, 0, 0),
        count = floor(180 * scale_particles()), size_min = 0.02, size_max = 0.05, life_min = 5, life_max = 9,
        spawn_rate = 18 * scale_particles(), spawn_radius = 11, noise_strength = 0.25, drag = 0 })
end

------------------------------------------------------------------ board
local build_trim
local function lane_kind(game, x, y)
    local k = game:kind(x, y)
    return k == "path" or k == "gate" or k == "core"
end

-- Neon lane trim: the lane outline traced as continuous polylines on the grid lines, straight runs as
-- single bars (no seams) and every turn as a rounded fillet, so corners always connect.
local TRIM_R = 0.18          -- fillet radius (cells)
local TRIM_ARC = 7           -- bars per quarter arc
local function seg_bar(B, x0, z0, x1, z1, y, th, h, c, e)
    local dx, dz = x1 - x0, z1 - z0
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 1e-4 then return end
    local n = box(B, nil, (x0 + x1) / 2, y, (z0 + z1) / 2, len + th * 0.6, h, th)
    n:set_rotation(v3(0, math.deg(math.atan2(-dz, dx)), 0))
    glow(n, c, e)
end

build_trim = function(game, B, c)
    -- Corner grid point (i, j), i in 0..W, j in 0..H; cell (x, y) spans corners x-1..x, y-1..y.
    local function key(i, j) return j * (R.W + 1) + i end
    local adj, edges = {}, {}
    local function add(i0, j0, i1, j1, nx, nz)
        local e = { i0, j0, i1, j1, nx = nx, nz = nz }    -- (nx, nz): unit normal pointing into the lane
        edges[#edges + 1] = e
        for _, k in ipairs({ key(i0, j0), key(i1, j1) }) do adj[k] = adj[k] or {}; adj[k][#adj[k] + 1] = e end
    end
    for y = 1, R.H do
        for x = 1, R.W do
            if lane_kind(game, x, y) then
                if game:kind(x, y - 1) and not lane_kind(game, x, y - 1) then add(x - 1, y - 1, x, y - 1, 0, 1) end
                if game:kind(x, y + 1) and not lane_kind(game, x, y + 1) then add(x - 1, y, x, y, 0, -1) end
                if game:kind(x - 1, y) and not lane_kind(game, x - 1, y) then add(x - 1, y - 1, x - 1, y, 1, 0) end
                if game:kind(x + 1, y) and not lane_kind(game, x + 1, y) then add(x, y - 1, x, y, -1, 0) end
            end
        end
    end
    -- Walk polylines: start at dead ends first, then any loops left.
    local used = {}
    local function other(e, i, j) if e[1] == i and e[2] == j then return e[3], e[4] end return e[1], e[2] end
    local lines = {}
    local function walk(e0, i, j)
        local pts, en = { { i, j } }, {}
        local e = e0
        while e and not used[e] do
            used[e] = true
            i, j = other(e, i, j)
            pts[#pts + 1] = { i, j }
            en[#en + 1] = { e.nx, e.nz }
            local nxt
            for _, f in ipairs(adj[key(i, j)] or {}) do if not used[f] then nxt = f; break end end
            e = (#(adj[key(i, j)] or {}) == 2) and nxt or nil
        end
        lines[#lines + 1] = { pts = pts, en = en }
    end
    for k, list in pairs(adj) do
        if #list ~= 2 then
            local i, j = k % (R.W + 1), floor(k / (R.W + 1))
            for _, e in ipairs(list) do if not used[e] then walk(e, i, j) end end
        end
    end
    for _, e in ipairs(edges) do if not used[e] then walk(e, e[1], e[2]) end end
    local function W_(i) return i + 0.5 - (R.W + 1) / 2 end
    local function Z_(j) return j + 0.5 - (R.H + 1) / 2 end
    for _, line in ipairs(lines) do
        local pts, en = line.pts, line.en
        -- Keep only the turning points; sn[k] is the lane-side normal of the run from v[k] to v[k+1].
        local v, sn = { pts[1] }, { en[1] }
        for n = 2, #pts - 1 do
            local a, b, d = pts[n - 1], pts[n], pts[n + 1]
            if (b[1] - a[1]) ~= (d[1] - b[1]) or (b[2] - a[2]) ~= (d[2] - b[2]) then v[#v + 1] = b; sn[#sn + 1] = en[n] end
        end
        v[#v + 1] = pts[#pts]
        local closed = #v > 2 and v[1][1] == v[#v][1] and v[1][2] == v[#v][2]
        -- Layers: the top trim on the block edge (on the grid line), and the floor glow line moved into
        -- the lane (inset along the normals, mitred at turns) so blocks never clip it or show it in gaps.
        -- The top trim sits fully above the tallest block top (heights vary by +-0.015), so no part of it
        -- shows through the seams between blocks.
        for _, layer in ipairs({ { BLOCK_H + 0.042, 0.05, 0.05, 1.5, 0 }, { 0.012, 0.06, 0.02, 0.8, 0.1 } }) do
            local y, th, h, e, inset = layer[1], layer[2], layer[3], layer[4], layer[5]
            local P = {}
            for n, q in ipairs(v) do
                local a = sn[n - 1] or (closed and sn[#sn]) or { 0, 0 }
                local b = sn[n] or (closed and sn[1]) or { 0, 0 }
                if a[1] == b[1] and a[2] == b[2] then b = { 0, 0 } end   -- endpoint: single normal
                P[n] = { W_(q[1]) + (a[1] + b[1]) * inset, Z_(q[2]) + (a[2] + b[2]) * inset }
            end
            local function dir(a, b)
                local dx, dz = b[1] - a[1], b[2] - a[2]
                local l = math.sqrt(dx * dx + dz * dz)
                return dx / l, dz / l, l
            end
            -- Straight runs, shortened by the fillet radius at every turn.
            for n = 1, #P - 1 do
                local ux, uz = dir(P[n], P[n + 1])
                local turn0 = n > 1 or closed
                local turn1 = n < #P - 1 or closed
                local x0, z0 = P[n][1] + (turn0 and ux * TRIM_R or 0), P[n][2] + (turn0 and uz * TRIM_R or 0)
                local x1, z1 = P[n + 1][1] - (turn1 and ux * TRIM_R or 0), P[n + 1][2] - (turn1 and uz * TRIM_R or 0)
                seg_bar(B, x0, z0, x1, z1, y, th, h, c, e)
                if inset == 0 then
                    -- Dark curb under the top trim: closes the seams between blocks along the lane, which
                    -- otherwise show the floor glow line through them as little violet ticks.
                    local cx0, cz0 = P[n][1], P[n][2]
                    local cx1, cz1 = P[n + 1][1], P[n + 1][2]
                    local len = math.sqrt((cx1 - cx0) ^ 2 + (cz1 - cz0) ^ 2)
                    local cb = box(B, nil, (cx0 + cx1) / 2, BLOCK_H / 2 + 0.01, (cz0 + cz1) / 2, len, BLOCK_H + 0.02, 0.04)
                    cb:set_rotation(v3(0, math.deg(math.atan2(-(cz1 - cz0), cx1 - cx0)), 0))
                    mat(cb, { 0.05, 0.055, 0.08 }, { 0, 0, 0 }, 0.8, 0.35)
                end
            end
            -- Fillets: arc from V - u*r to V + w*r around C = V - u*r + w*r.
            local function fillet(a, V, b)
                local ux, uz = dir(a, V)
                local wx_, wz_ = dir(V, b)
                local cx, cz = V[1] - ux * TRIM_R + wx_ * TRIM_R, V[2] - uz * TRIM_R + wz_ * TRIM_R
                local px, pz
                for m = 0, TRIM_ARC do
                    local t = m / TRIM_ARC * math.pi / 2
                    local qx = cx + TRIM_R * (-wx_ * cos(t) + ux * sin(t))
                    local qz = cz + TRIM_R * (-wz_ * cos(t) + uz * sin(t))
                    if px then seg_bar(B, px, pz, qx, qz, y, th, h, c, e) end
                    px, pz = qx, qz
                end
            end
            for n = 2, #P - 1 do fillet(P[n - 1], P[n], P[n + 1]) end
            if closed then fillet(P[#P - 1], P[1], P[2]) end
        end
    end
end

function W.build(game)
    remove_all(board_nodes)
    for k, set in pairs(piece_nodes) do remove_all(set.nodes); piece_nodes[k] = nil end
    for id, e in pairs(enemy_nodes) do remove_all(e.nodes); enemy_nodes[id] = nil end
    remove_all(ghost.nodes); ghost.key = nil
    lane_tiles = {}
    local B = board_nodes
    -- Mirror-polished floor: the lane channel shows it, and SSR reflects every beam in it.
    local fl = primitives.plane(R.W + 3, R.H + 3)
    fl:set_position(v3(0, 0, 0))
    -- Matte under the blocks (seams between blocks must not reflect the trim); the lane tiles carry
    -- the mirror finish.
    mat(fl, { 0.01, 0.011, 0.02 }, { 0, 0, 0 }, 0.1, 0.95)
    B[#B + 1] = fl
    -- Underside slab so the board reads as a floating platform from the tilted camera.
    local slab = box(B, nil, 0, -0.45, 0, R.W + 1.2, 0.9, R.H + 1.2)
    mat(slab, { 0.03, 0.035, 0.06 }, { 0, 0, 0 }, 0.9, 0.3)
    -- Neon frame around the board.
    local fc = { 0.25, 0.5, 1 }
    local hw, hh = (R.W + 1.2) / 2, (R.H + 1.2) / 2
    glow(box(B, nil, 0, 0.02, -hh, R.W + 1.25, 0.05, 0.05), fc, 1.3)
    glow(box(B, nil, 0, 0.02, hh, R.W + 1.25, 0.05, 0.05), fc, 1.3)
    glow(box(B, nil, -hw, 0.02, 0, 0.05, 0.05, R.H + 1.25), fc, 1.3)
    glow(box(B, nil, hw, 0.02, 0, 0.05, 0.05, R.H + 1.25), fc, 1.3)
    local rnd = 0
    local edge_c = { 0.55, 0.22, 1 }
    for y = 1, R.H do
        for x = 1, R.W do
            local kind = game:kind(x, y)
            local X, Z = wx(x), wz(y)
            if kind == "ground" or kind == "rock" then
                rnd = (rnd * 1103515245 + 12345 + x * 31 + y * 17) % 2147483648
                local j = (rnd % 1000) / 1000
                local h = BLOCK_H + (j - 0.5) * 0.03
                local b = box(B, nil, X, h / 2, Z, 0.95, h, 0.95)
                local g = 0.1 + j * 0.05
                mat(b, { g * 0.8, g * 0.88, g * 1.3 }, { 0, 0, 0 }, 0.8, 0.22 + j * 0.12)
                -- A faint inset light on some blocks: a living tech floor.
                if j > 0.94 then
                    local d = box(B, nil, X + (j - 0.9) * 3, h + 0.004, Z - 0.25, 0.1, 0.01, 0.1)
                    glow(d, { 0.3, 0.6, 1 }, 1.4)
                end
                if kind == "rock" then
                    local r = place(primitives.ico_sphere(0.36, 1), nil, X, h + 0.22, Z, 1.0 + j * 0.3, 0.75, 0.95 - j * 0.2)
                    r:set_rotation(v3(j * 40, j * 300, 0))
                    mat(r, { 0.1, 0.1, 0.13 }, { 0.01, 0.005, 0.02 }, 0.2, 0.75)
                    B[#B + 1] = r
                end
            else
                -- Lane floor tile: dark, glows with the colour of the light crossing it.
                local t = place(primitives.plane(0.98, 0.98), nil, X, 0.004, Z)
                mat(t, { 0.01, 0.01, 0.02 }, { 0.03, 0.01, 0.06 }, 1.0, 0.06)
                B[#B + 1] = t
                lane_tiles[R.idx(x, y)] = t
            end
        end
    end
    build_trim(game, B, edge_c)
    -- Rift: a spinning ring over a dark well.
    local g = game.path[1]
    gate.x, gate.z = wx(g[1]), wz(g[2])
    gate.well = place(primitives.circle(0.42, 48), nil, gate.x, 0.01, gate.z); B[#B + 1] = gate.well
    mat(gate.well, { 0, 0, 0 }, { 0.15, 0.0, 0.25 }, 0, 1)
    gate.ring = place(primitives.torus(0.44, 0.05, 64, 12), nil, gate.x, 0.12, gate.z); B[#B + 1] = gate.ring
    glow(gate.ring, { 1, 0.15, 0.8 }, 2.4)
    gate.ring2 = place(primitives.torus(0.3, 0.03, 48, 10), nil, gate.x, 0.3, gate.z); B[#B + 1] = gate.ring2
    glow(gate.ring2, { 0.6, 0.15, 1 }, 2.0)
    -- Core: a floating octahedron crystal inside two orbit rings, on a pedestal.
    local c = game.path[#game.path]
    core.x, core.z = wx(c[1]), wz(c[2])
    local ped = place(primitives.cylinder(0.38, 0.12), nil, core.x, 0.06, core.z); B[#B + 1] = ped
    mat(ped, { 0.08, 0.1, 0.16 }, { 0.02, 0.06, 0.1 }, 0.9, 0.25)
    core.root = scene.add_empty_node("refract_core"); B[#B + 1] = core.root
    core.root:set_position(v3(core.x, 0.85, core.z))
    core.top = place(primitives.pyramid(0.5, 0.42), core.root, 0, 0, 0); B[#B + 1] = core.top
    core.bot = place(primitives.pyramid(0.5, 0.42), core.root, 0, 0, 0); B[#B + 1] = core.bot
    core.bot:set_rotation(v3(180, 0, 0))
    core.o1 = place(primitives.torus(0.62, 0.025, 64, 8), nil, core.x, 0.85, core.z); B[#B + 1] = core.o1
    core.o2 = place(primitives.torus(0.5, 0.02, 64, 8), nil, core.x, 0.85, core.z); B[#B + 1] = core.o2
    W.set_core_health(1)
    -- Hover cursor: four glowing bars.
    cursor = {}
    for i = 1, 4 do
        local n = primitives.cube(1); B[#B + 1] = n
        glow(n, { 1, 1, 1 }, 3)
        n:set_enabled(false)
        cursor[i] = n
    end
    -- Particles that live with the map.
    if rift_emitter then pcall(particles.remove_emitter, rift_emitter) end
    rift_emitter = particles.add_emitter({ name = "refract_rift", position = v3(gate.x, 0.15, gate.z), velocity = v3(0, 0.9, 0),
        color_start = vec4(2.2, 0.4, 2.2, 1), color_end = vec4(0.5, 0.1, 1, 0), gravity = v3(0, 0, 0),
        count = floor(160 * scale_particles()), size_min = 0.03, size_max = 0.08, life_min = 0.8, life_max = 1.6,
        spawn_rate = 50 * scale_particles(), spawn_radius = 0.4, noise_strength = 1.2, drag = 0.4 })
    if core_emitter then pcall(particles.remove_emitter, core_emitter) end
    core_emitter = particles.add_emitter({ name = "refract_core", position = v3(core.x, 0.85, core.z), velocity = v3(0, 0.4, 0),
        color_start = vec4(0.6, 2.0, 2.4, 1), color_end = vec4(0.2, 0.5, 1, 0), gravity = v3(0, 0, 0),
        count = floor(120 * scale_particles()), size_min = 0.02, size_max = 0.06, life_min = 0.6, life_max = 1.4,
        spawn_rate = 36 * scale_particles(), spawn_radius = 0.45, noise_strength = 0.8, drag = 0.3 })
    pcall(particles.set_emitter, dust_emitter, { position = v3(0, 0.6, 0) })
end

function W.set_core_health(f)
    core.tint = { 1 - 0.5 * f, 0.3 + 0.65 * f, 0.35 + 0.65 * f }
    if core.top then
        glow(core.top, core.tint, 1.8, 0.3)
        glow(core.bot, core.tint, 1.2, 0.3)
        glow(core.o1, core.tint, 1.6, 0)
        glow(core.o2, core.tint, 1.2, 0)
    end
end

-- Lane tiles take the colour of the light crossing them (called on every retrace).
function W.set_lane_light(cov)
    for k, t in pairs(lane_tiles) do
        local c = cov[k]
        if c then
            local tot = c.w + c.r + c.g + c.b
            local m = { 0, 0, 0 }
            for _, col in ipairs(R.COLORS) do
                for i = 1, 3 do m[i] = m[i] + LIGHT[col][i] * c[col] / tot end
            end
            -- Saturate the mix so white light tints the lane warm gold, never a grey wash.
            local lo = min(m[1], m[2], m[3])
            for i = 1, 3 do m[i] = (m[i] - lo * 0.7) / (1 - lo * 0.7) end
            local e = min(0.16, 0.04 + tot / 300)
            material.set(t, "emissive", v3(m[1] * e + 0.03, m[2] * e + 0.01, m[3] * e + 0.06))
        else
            material.set(t, "emissive", v3(0.03, 0.01, 0.06))
        end
    end
end

------------------------------------------------------------------ pieces
local function build_piece(p, X, Z, list, alpha)
    local y0 = BLOCK_H
    local ghost_a = alpha and alpha < 1 and alpha or nil
    local function fin(n) list[#list + 1] = n; if ghost_a then ghostify(n, ghost_a) end; return n end
    local root = scene.add_empty_node("refract_piece"); list[#list + 1] = root
    root:set_position(v3(X, 0, Z))
    if p.kind == "emitter" then
        local tc = TIER[p.tier]
        local base = fin(box(nil, root, 0, y0 + 0.09, 0, 0.66, 0.18, 0.66))
        mat(base, { 0.12, 0.13, 0.18 }, { 0, 0, 0 }, 0.95, 0.22)
        local collar = fin(box(nil, root, 0, y0 + 0.19, 0, 0.5, 0.04, 0.5))
        glow(collar, tc, 1.2, 0.6)
        local d = R.DIRS[p.dir]
        local bx, bz = d[1] * 0.26, d[2] * 0.26
        local barrel = fin(box(nil, root, bx, BEAM_Y, bz, d[1] ~= 0 and 0.46 or 0.17, 0.17, d[2] ~= 0 and 0.46 or 0.17))
        mat(barrel, { 0.2, 0.22, 0.28 }, { 0, 0, 0 }, 1.0, 0.18)
        local tip = fin(box(nil, root, d[1] * 0.5, BEAM_Y, d[2] * 0.5, d[1] ~= 0 and 0.05 or 0.2, 0.2, d[2] ~= 0 and 0.05 or 0.2))
        glow(tip, tc, 2.5, 0)
        local gem = fin(place(primitives.ico_sphere(0.13, 1), root, 0, BEAM_Y + 0.12, 0))
        glow(gem, tc, 3, 0)
        for i = 1, p.tier do
            local pip = fin(box(nil, root, -0.22 + (i - 1) * 0.11, y0 + 0.19, d[2] ~= 0 and -d[2] * 0.3 or 0.3, 0.06, 0.05, 0.06))
            glow(pip, tc, 3, 0)
        end
        return root, gem, tc
    elseif p.kind == "mirror" then
        local ped = fin(place(primitives.cylinder(0.12, 0.12), root, 0, y0 + 0.06, 0))
        mat(ped, { 0.1, 0.11, 0.15 }, { 0, 0, 0 }, 0.9, 0.3)
        local yaw = p.flip == "/" and 45 or -45
        local plate = fin(box(nil, root, 0, BEAM_Y, 0, 0.95, 0.36, 0.05))
        plate:set_rotation(v3(0, yaw, 0))
        mat(plate, { 0.92, 0.96, 1.0 }, { 0.02, 0.04, 0.06 }, 1.0, 0.02)
        local rim = fin(box(nil, root, 0, BEAM_Y + 0.19, 0, 0.97, 0.03, 0.07))
        rim:set_rotation(v3(0, yaw, 0))
        glow(rim, { 0.3, 0.8, 1 }, 2.2, 0)
        return root, rim, { 0.4, 0.85, 1 }
    elseif p.kind == "prism" then
        local ped = fin(place(primitives.cylinder(0.3, 0.08), root, 0, y0 + 0.04, 0))
        mat(ped, { 0.1, 0.11, 0.15 }, { 0, 0, 0 }, 0.9, 0.3)
        local core_n = fin(place(primitives.pyramid(0.5, 0.55), root, 0, y0 + 0.08, 0))
        mat(core_n, { 0.7, 0.85, 1.0 }, { 0.25, 0.25, 0.35 }, 0.1, 0.05)
        pcall(material.set, core_n, "transmission", 0.8)
        pcall(material.set, core_n, "ior", 1.5)
        -- A neon triangle hovering in the beam plane, with r / g / b vertex lights.
        -- Yaw: rotating +X by +a about Y gives (cos a, 0, -sin a), so an edge (dx, dz) has yaw atan2(-dz, dx).
        local rr = 0.36
        local vs = {}
        for i = 0, 2 do
            local a = math.rad(90 + i * 120)
            vs[i + 1] = { cos(a) * rr, -sin(a) * rr }
        end
        for i = 1, 3 do
            local p1, p2 = vs[i], vs[i % 3 + 1]
            local dx, dz = p2[1] - p1[1], p2[2] - p1[2]
            local len = math.sqrt(dx * dx + dz * dz)
            local e = fin(box(nil, root, (p1[1] + p2[1]) / 2, BEAM_Y + 0.1, (p1[2] + p2[2]) / 2, len + 0.03, 0.03, 0.03))
            e:set_rotation(v3(0, math.deg(math.atan2(-dz, dx)), 0))
            glow(e, { 0.9, 0.95, 1 }, 1.8, 0)
            local dot = fin(place(primitives.sphere(0.055), root, p1[1], BEAM_Y + 0.1, p1[2]))
            glow(dot, ({ LIGHT.r, LIGHT.g, LIGHT.b })[i], 4, 0)
        end
        return root, core_n, { 1, 1, 1 }
    elseif p.kind == "lens" then
        local ped = fin(place(primitives.cylinder(0.1, 0.12), root, 0, y0 + 0.06, 0))
        mat(ped, { 0.1, 0.11, 0.15 }, { 0, 0, 0 }, 0.9, 0.3)
        local ring = fin(place(primitives.torus(0.3, 0.045, 48, 12), root, 0, BEAM_Y, 0))
        mat(ring, { 0.55, 0.45, 0.3 }, { 0.3, 0.22, 0.08 }, 1.0, 0.2)
        local disc = fin(place(primitives.sphere(0.28), root, 0, BEAM_Y, 0, 1, 0.35, 1))
        mat(disc, { 0.75, 0.9, 1.0 }, { 0.08, 0.14, 0.22 }, 0.1, 0.02)
        pcall(material.set, disc, "transmission", 0.85)
        return root, ring, { 1, 0.85, 0.5 }
    end
    return root
end

local function sig(p) return p.kind .. (p.dir or "") .. (p.flip or "") .. (p.tier or "") end

-- Create, rebuild or remove piece models so they match game.pieces. Returns cells that are new.
function W.sync_pieces(game)
    local born = {}
    for k, set in pairs(piece_nodes) do
        local p = game.pieces[k]
        if not p or sig(p) ~= set.sig then remove_all(set.nodes); piece_nodes[k] = nil end
    end
    for k, p in pairs(game.pieces) do
        if not piece_nodes[k] then
            local x, y = (k - 1) % R.W + 1, floor((k - 1) / R.W) + 1
            local list = {}
            local root, accent, ac = build_piece(p, wx(x), wz(y), list)
            piece_nodes[k] = { sig = sig(p), nodes = list, root = root, accent = accent, ac = ac, t = 0, kind = p.kind, x = x, y = y }
            born[#born + 1] = k
        end
    end
    return born
end

-- Pop a piece (place / turn / upgrade): it scales up from small with a slight overshoot.
function W.pop(x, y)
    local set = piece_nodes[R.idx(x, y)]
    if set then set.t = 0; set.pop = true end
end

function W.set_ghost(p, x, y, ok)
    local key = p and (sig(p) .. x .. "_" .. y .. tostring(ok)) or nil
    if key == ghost.key then return end
    remove_all(ghost.nodes); ghost.key = key
    if not p then return end
    build_piece(p, wx(x), wz(y), ghost.nodes, ok and 0.45 or 0.18)
end

------------------------------------------------------------------ beams
local function beam_node(i)
    local b = beam_pool[i]
    if not b then
        b = { n = primitives.cube(1) }
        glow(b.n, { 1, 1, 1 }, 3, 0)

        beam_pool[i] = b
    end
    return b
end

-- segs: { x0, y0, x1, y1, colour, power } in cell space. ghost = preview (dimmer, pulsing).
W.segs = {}
function W.set_beams(segs, is_ghost)
    W.segs, W.ghost_beams = segs, is_ghost
    impacts = {}
    for i, s in ipairs(segs) do
        local b = beam_node(i)
        local x0, z0, x1, z1 = wx(s[1]), wz(s[2]), wx(s[3]), wz(s[4])
        local len = abs(x1 - x0) + abs(z1 - z0)
        local th = (0.045 + 0.03 * vis(s[6])) * (W.beam_th or 1)  -- >= ~2 px so TAA can smooth it
        local hor = abs(z1 - z0) < 1e-3
        local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        local sx, sz = hor and len + th or th, hor and th or len + th
        b.n:set_enabled(len > 1e-3)
        b.n:set_position(v3(cx, BEAM_Y, cz)); b.n:set_scale(v3(sx, th, sz))

        b.c, b.pw, b.len, b.x0, b.z0, b.x1, b.z1, b.hor = LIGHT[s[5]], s[6], len, x0, z0, x1, z1, hor
        -- A beam that ends half a cell past a centre has hit a rock, the edge or a blocker: sparks there.
        if (s[3] % 1) ~= 0 or (s[4] % 1) ~= 0 then impacts[#impacts + 1] = { x1, z1, s[5] } end
    end
    for i = #segs + 1, beam_used do
        beam_pool[i].n:set_enabled(false)
    end
    beam_used = #segs
    -- Lights: strongest segments get a coloured point light at their middle, spilling onto the board.
    local order = {}
    for i = 1, #segs do order[i] = i end
    table.sort(order, function(a, b) return segs[a][6] * (beam_pool[a].len + 1) > segs[b][6] * (beam_pool[b].len + 1) end)
    W.beam_lights = {}
    for j = 1, MAX_BEAM_LIGHTS do
        local i = order[j]
        if i and LT[j] then W.beam_lights[j] = i end
    end
end

local function update_beams(dt)
    local t = S.t
    local surge = S.surge > 0 and 1.6 or 1     -- brighter, but not clipped to pure white
    local g = W.ghost_beams and (0.35 + 0.15 * sin(t * 6)) or 1
    for i = 1, beam_used do
        local b = beam_pool[i]
        local pulse = (0.93 + 0.07 * sin(t * 4.5 + i * 1.7)) * surge * g
        local e = (2.25 + 1.5 * vis(b.pw)) * pulse * (W.beam_gain or 1)
        emis(b.n, { b.c[1] * 0.6 + 0.4, b.c[2] * 0.6 + 0.4, b.c[3] * 0.6 + 0.4 }, e)

    end
    -- Photons race along the longer segments.
    local used = 0
    W.photons = {}
    for i = 1, beam_used do
        local b = beam_pool[i]
        if b.len > 0.9 then
            for j = 0, b.len > 5 and 1 or 0 do
                -- Glint positions only: the overlay draws them after post-processing. Small bright meshes
                -- moved every frame leave dotted TAA ghost trails along the beam.
                used = used + 1
                local f = (t * 7 / b.len + i * 0.37 + j * 0.5) % 1
                W.photons[used] = { b.x0 + (b.x1 - b.x0) * f, b.z0 + (b.z1 - b.z0) * f, b.c }
            end
        end
    end
    -- Beam lights: intensity follows the saturating curve and is normalised by how many are lit, so
    -- a board full of beams (or lenses) stays exposed the same.
    local lit = 0
    for j = 1, MAX_BEAM_LIGHTS do if W.beam_lights and W.beam_lights[j] and W.beam_lights[j] <= beam_used then lit = lit + 1 end end
    local norm = min(1, math.sqrt(10 / max(1, lit)))
    for j = 1, MAX_BEAM_LIGHTS do
        local i = W.beam_lights and W.beam_lights[j]
        if LT[j] then
            if i and i <= beam_used then
                local b = beam_pool[i]
                local inten = (1.4 + 3.6 * vis(b.pw)) * norm * (S.surge > 0 and 1.5 or 1) * g
                point_light(LT[j], v3((b.x0 + b.x1) / 2, BEAM_Y + 0.35, (b.z0 + b.z1) / 2), v3(b.c[1], b.c[2], b.c[3]), inten, b.len / 2 + 1.6)
            else
                light_off(LT[j])
            end
        end
    end
    -- Impact sparks where light hits stone.
    impact_t = impact_t - dt
    if impact_t <= 0 and not W.ghost_beams then
        impact_t = 0.09
        for n = 1, min(10, #impacts) do
            local im = impacts[math.random(#impacts)]
            local c = LIGHT[im[3]]
            particles.emit_burst({ position = v3(im[1], BEAM_Y, im[2]), velocity = v3(0, 0.6, 0),
                color_start = vec4(c[1] * 3 + 0.5, c[2] * 3 + 0.5, c[3] * 3 + 0.5, 1), color_end = vec4(c[1], c[2], c[3], 0),
                gravity = v3(0, -3, 0), count = 3, size_min = 0.02, size_max = 0.05, life_min = 0.2, life_max = 0.45,
                spawn_radius = 0.05, noise_strength = 3, drag = 1 })
        end
    end
end

------------------------------------------------------------------ enemies
local ENEMY_C = {
    mote = { 0.6, 0.75, 1 }, dart = { 1, 0.7, 0.15 }, hulk = { 0.6, 0.35, 1 },
    mirrorback = { 0.9, 0.95, 1 }, splitter = { 1, 0.45, 0.15 }, eclipse = { 0.05, 0.03, 0.08 },
}
W.ENEMY_C = ENEMY_C

local function build_enemy(e)
    local def = R.ENEMIES[e.kind]
    local list = {}
    local root = scene.add_empty_node("refract_enemy"); list[1] = root
    local r = def.size
    local shield = R.shield_of(e)
    local o = { nodes = list, root = root, r = r, kind = e.kind, t = 0, glow_nodes = {} }
    local function add(n, glow_c, glow_e)
        n:set_parent(root); list[#list + 1] = n
        if glow_c then o.glow_nodes[#o.glow_nodes + 1] = { n = n, c = glow_c, e = glow_e } end
        return n
    end
    if e.kind == "mote" then
        local s = add(primitives.sphere(r), ENEMY_C.mote, 0.35); mat(s, { 0.25, 0.4, 0.95 }, { 0.2, 0.26, 0.35 }, 0.4, 0.2)
        local c = add(place(primitives.sphere(r * 0.42), nil, 0, r * 0.2, 0), { 0.7, 0.85, 1 }, 2.2); glow(c, { 0.7, 0.85, 1 }, 2.2, 0)
    elseif e.kind == "dart" then
        local s = add(primitives.sphere(r), ENEMY_C.dart, 0.9); mat(s, { 0.9, 0.55, 0.1 }, { 0.9, 0.55, 0.1 }, 0.5, 0.2)
        o.stretch = s
        local tail = add(primitives.sphere(r * 0.6), ENEMY_C.dart, 1.6); mat(tail, { 0.5, 0.3, 0.05 }, { 1.6, 1.0, 0.2 }, 0.5, 0.3)
        o.tail = tail
    elseif e.kind == "hulk" then
        local b = add(place(primitives.cube(1), nil, 0, 0, 0, r * 1.5, r * 1.3, r * 1.5)); mat(b, { 0.14, 0.12, 0.2 }, { 0, 0, 0 }, 0.95, 0.25)
        o.spin = b
        local band = add(place(primitives.cube(1), nil, 0, 0, 0, r * 1.56, r * 0.22, r * 1.56), ENEMY_C.hulk, 1.8)
        glow(band, ENEMY_C.hulk, 1.8, 0)
        o.spin2 = band
    elseif def.shield then
        local s = add(primitives.sphere(r)); mat(s, { 0.02, 0.02, 0.03 }, { 0, 0, 0 }, 1.0, 0.08)
        local ring = add(primitives.torus(r * 1.12, 0.03, 48, 10), LIGHT[shield], 2.2)
        glow(ring, LIGHT[shield], 2.2, 0)
        o.ring = ring
        local eye = add(place(primitives.sphere(r * 0.28), nil, 0, r * 0.62, 0), LIGHT[shield], 2.6)
        glow(eye, LIGHT[shield], 2.6, 0)
    elseif e.kind == "mirrorback" then
        local s = add(primitives.sphere(r)); mat(s, { 0.95, 0.97, 1 }, { 0.01, 0.01, 0.02 }, 1.0, 0.02)
        local band = add(primitives.torus(r * 1.04, 0.02, 48, 8), { 0.7, 0.9, 1 }, 1.4); glow(band, { 0.7, 0.9, 1 }, 1.4, 0)
    elseif e.kind == "splitter" then
        o.orbs = {}
        for j = 1, 3 do
            local s = add(primitives.sphere(r * 0.55), ENEMY_C.splitter, 0.8); mat(s, { 0.9, 0.35, 0.08 }, { 0.8, 0.3, 0.06 }, 0.4, 0.25)
            o.orbs[j] = s
        end
        local c = add(primitives.sphere(r * 0.3)); glow(c, { 1, 0.8, 0.4 }, 3, 0)
    elseif e.kind == "eclipse" then
        local s = add(primitives.sphere(r)); mat(s, { 0.0, 0.0, 0.0 }, { 0, 0, 0 }, 1.0, 0.05)
        o.ring = add(primitives.torus(r * 1.3, 0.07, 64, 12))
        o.ring2 = add(primitives.torus(r * 1.6, 0.035, 64, 8))
        o.ring2:set_rotation(v3(70, 0, 0))
        o.eclipse = true
    end
    root:set_scale(v3(0.01, 0.01, 0.01))
    return o
end

function W.enemy_world(game, e)
    local ex, ey = game:pos(e)
    return wx(ex), wz(ey)
end

function W.update_enemies(game, dt, burn_of)
    local seen = {}
    for _, e in ipairs(game.enemies) do
        seen[e.id] = true
        local o = enemy_nodes[e.id]
        if not o then o = build_enemy(e); enemy_nodes[e.id] = o end
        o.t = o.t + dt
        local X, Z = W.enemy_world(game, e)
        local bob = sin(S.t * 6 + e.id) * 0.03
        local yc = (e.kind == "eclipse" and 0.75 or BEAM_Y) + bob
        o.root:set_position(v3(X, yc, Z))
        o.last = { X, yc, Z }
        local grow = min(1, o.t / 0.35)
        grow = 1 - (1 - grow) * (1 - grow)
        o.root:set_scale(v3(grow, grow, grow))
        -- Direction of travel (for darts).
        local px, pz = o.px or X, o.pz or Z
        local dx, dz = X - px, Z - pz
        o.px, o.pz = X, Z
        if o.stretch then
            local ax = abs(dx) > abs(dz)
            o.stretch:set_scale(v3(ax and 1.8 or 0.85, 0.85, ax and 0.85 or 1.8))
            local l = math.sqrt(dx * dx + dz * dz)
            if l > 1e-5 then o.tail:set_position(v3(-dx / l * o.r * 1.4, 0, -dz / l * o.r * 1.4)) end
        end
        if o.spin then
            o.spin:set_rotation(v3(0, S.t * 40 + e.id * 20, 0))
            o.spin2:set_rotation(v3(0, S.t * 40 + e.id * 20, 0))
        end
        if o.ring then
            local sh = R.shield_of(e)
            if o.eclipse then
                local c = LIGHT[sh]
                glow(o.ring, c, 3 + 0.8 * sin(S.t * 8), 0)
                glow(o.ring2, c, 1.8, 0)
                o.ring:set_rotation(v3(sin(S.t) * 20, S.t * 50, 0))
                o.ring2:set_rotation(v3(70, -S.t * 70, 0))
                W.boss = { X, Z, c }
            else
                o.ring:set_rotation(v3(sin(S.t * 3 + e.id) * 18, 0, cos(S.t * 2.6 + e.id) * 18))
            end
        end
        if o.orbs then
            for j, s in ipairs(o.orbs) do
                local a = S.t * 3 + j * 2.094
                s:set_position(v3(cos(a) * o.r * 0.55, 0, sin(a) * o.r * 0.55))
            end
        end
        -- Burning: parts flare hot in the beam's colour, sparks fly.
        local burn = e.hit > 0 and burn_of(e)
        if burn ~= o.burn_state then
            o.burn_state = burn
            for _, gn in ipairs(o.glow_nodes) do
                if burn then emis(gn.n, { gn.c[1] * 0.5 + burn[1] * 0.8, gn.c[2] * 0.5 + burn[2] * 0.8, gn.c[3] * 0.5 + burn[3] * 0.8 }, gn.e * 1.8)
                else emis(gn.n, gn.c, gn.e) end
            end
        end
        if burn and math.random() < dt * 18 then
            particles.emit_burst({ position = v3(X, yc, Z), velocity = v3(0, 1.2, 0),
                color_start = vec4(burn[1] * 3 + 0.6, burn[2] * 3 + 0.6, burn[3] * 3 + 0.6, 1), color_end = vec4(burn[1], burn[2], burn[3], 0),
                gravity = v3(0, -2, 0), count = 2, size_min = 0.02, size_max = 0.06, life_min = 0.2, life_max = 0.5,
                spawn_radius = o.r * 0.8, noise_strength = 2.5, drag = 1 })
        end
    end
    local boss_alive = false
    for id, o in pairs(enemy_nodes) do
        if not seen[id] then remove_all(o.nodes); enemy_nodes[id] = nil
        elseif o.eclipse then boss_alive = true end
    end
    if not boss_alive then W.boss = nil end
end

------------------------------------------------------------------ fx
function W.burst(X, Z, c, n, speed, y)
    n = max(1, floor((n or 40) * scale_particles()))
    particles.emit_burst({ position = v3(X, y or BEAM_Y, Z), velocity = v3(0, 1.5, 0),
        color_start = vec4(c[1] * 2.6 + 0.4, c[2] * 2.6 + 0.4, c[3] * 2.6 + 0.4, 1), color_end = vec4(c[1], c[2] * 0.5, c[3], 0),
        gravity = v3(0, -4, 0), count = n, size_min = 0.03, size_max = 0.12, life_min = 0.4, life_max = 1.1,
        spawn_radius = 0.25, noise_strength = speed or 5, drag = 1.4 })
    particles.emit_burst({ position = v3(X, y or BEAM_Y, Z), velocity = v3(0, 0, 0), color_start = vec4(3, 3, 3, 1),
        color_end = vec4(c[1], c[2], c[3], 0), gravity = v3(0, 0, 0), count = max(1, floor(n / 3)),
        size_min = 0.08, size_max = 0.2, life_min = 0.1, life_max = 0.25, spawn_radius = 0.12, noise_strength = 1.5, drag = 3 })
end

function W.shock(X, Z, c, size, y)
    local ring = primitives.torus(0.5, 0.035, 64, 8)
    ring:set_position(v3(X, y or 0.1, Z))
    glow(ring, c, 2.2, 0)
    local s1 = size or 2.4
    tween.to(v3(0.2, 0.2, 0.2), v3(s1, 1, s1), 0.42, function(sv) ring:set_scale(sv) end, { on_done = function() ring:remove() end })
end

function W.flash(X, Z, c, e)
    S.flash, S.flash_c, S.flash_x, S.flash_z = e or 1, c, X, Z
end

function W.shake(a) S.shake = max(S.shake, a * scale_shake()) end

-- Re-apply the PARTICLES setting to the long-lived emitters (bursts read it when they fire).
function W.refresh_particles()
    local k = scale_particles()
    if dust_emitter then pcall(particles.set_emitter, dust_emitter, { count = floor(180 * k), spawn_rate = 18 * k }) end
    if rift_emitter then pcall(particles.set_emitter, rift_emitter, { count = floor(160 * k), spawn_rate = 50 * k }) end
    if core_emitter then pcall(particles.set_emitter, core_emitter, { count = floor(120 * k), spawn_rate = 36 * k }) end
end
function W.set_surge(t) S.surge = t end

function W.cell_world(x, y) return wx(x), wz(y) end

function W.set_cursor(x, y, c, on, lane)
    if not cursor[1] then return end
    if not on then for i = 1, 4 do cursor[i]:set_enabled(false) end return end
    local X, Z = wx(x), wz(y)
    local h = lane and 0.0 or BLOCK_H
    local s = 1.0 + 0.04 * sin(S.t * 7)
    local parts = { { 0, -0.5, 1, 0.04 }, { 0, 0.5, 1, 0.04 }, { -0.5, 0, 0.04, 1 }, { 0.5, 0, 0.04, 1 } }
    for i, q in ipairs(parts) do
        local n = cursor[i]
        n:set_enabled(true)
        n:set_position(v3(X + q[1] * s, h + 0.03, Z + q[2] * s))
        n:set_scale(v3(q[3] * s, 0.04, q[4] * s))
        emis(n, c, 2)
    end
end

------------------------------------------------------------------ per-frame
-- Live beam data for the overlay glow: list of { x0, z0, x1, z1, colour, power, horizontal }.
function W.beam_list()
    local out = {}
    for i = 1, beam_used do
        local b = beam_pool[i]
        if b.len > 1e-3 then out[#out + 1] = b end
    end
    return out
end
function W.surge_on() return S.surge > 0 end
function W.time() return S.t end

function W.update(dt, game)
    S.t = S.t + dt
    -- Pieces: pops, gem pulse, accent breathing.
    for _, set in pairs(piece_nodes) do
        set.t = set.t + dt
        if set.pop then
            local f = min(1, set.t / 0.32)
            local s = 1 + 0.35 * sin(f * math.pi) * (1 - f) - 0.3 * (1 - f) ^ 3
            set.root:set_scale(v3(s, s, s))
            if f >= 1 then set.pop = false; set.root:set_scale(v3(1, 1, 1)) end
        end
        if set.accent and set.kind == "emitter" then
            emis(set.accent, set.ac, 2.6 + 1.2 * sin(S.t * 5 + set.x + set.y))
        end
    end
    update_beams(dt)
    -- Rift and core spin.
    if gate.ring then
        gate.ring:set_rotation(v3(0, S.t * 90, 0))
        gate.ring2:set_rotation(v3(sin(S.t * 1.3) * 25, -S.t * 140, 0))
    end
    if core.root then
        local bob = sin(S.t * 2) * 0.06
        core.root:set_position(v3(core.x, 0.88 + bob, core.z))
        core.root:set_rotation(v3(0, S.t * 45, 0))
        core.o1:set_rotation(v3(60 + sin(S.t * 0.7) * 10, S.t * 70, 0))
        core.o2:set_rotation(v3(-50, -S.t * 95, 20))
        core.o1:set_position(v3(core.x, 0.88 + bob, core.z)); core.o2:set_position(v3(core.x, 0.88 + bob, core.z))
    end
    -- Twinkle.
    for _ = 1, 6 do
        local s = W.stars[math.random(#W.stars)]
        local e = s.e * (0.3 + 0.7 * (0.5 + 0.5 * sin(S.t * s.sp + s.ph)))
        emis(s.n, s.c, e)
    end
    -- Lights: core, rift, flash, boss.
    S.flash = max(0, S.flash - dt * 3)
    pcall(function()
        local ct = core.tint or { 0.5, 1, 1 }
        point_light(LT.core, v3(core.x or 0, 1.4, core.z or 0), v3(ct[1], ct[2], ct[3]), 7 + 1.5 * sin(S.t * 2.2), 4.5)
        point_light(LT.gate, v3(gate.x or 0, 0.9, gate.z or 0), v3(1, 0.25, 0.9), 5 + 1.2 * sin(S.t * 3), 3.5)
        point_light(LT.flash, v3(S.flash_x, 1.2, S.flash_z), v3(S.flash_c[1], S.flash_c[2], S.flash_c[3]), S.flash * 14, 5)
        if W.boss then
            local c = W.boss[3]
            point_light(LT.boss, v3(W.boss[1], 1.4, W.boss[2]), v3(c[1], c[2], c[3]), 10, 4)
        else
            light_off(LT.boss)
        end
    end)
    -- Camera: framed on the board with a slow drift and shake.
    S.shake = max(0, S.shake - dt * 1.8)
    local sk = S.shake
    -- Smooth shake: summed sines, not per-frame random jumps.
    local t = S.t
    local sx = sk * 0.32 * (sin(t * 31.7) + 0.6 * sin(t * 17.3 + 1.3))
    local sy = sk * 0.32 * (sin(t * 27.1 + 0.7) + 0.6 * sin(t * 13.9 + 2.1))
    local d = sin(S.t * 0.25) * 0.25
    cam:set_position(v3(d + sx, W.cam_h or 35, (W.cam_z or 21.5) + sy))
    cam:look_at(v3(d * 0.4 + sx * 0.4, 0, (W.cam_look_z or 0.9) + sy * 0.4))
    W.begin_frame()
end

------------------------------------------------------------------ picking
-- World -> UI pixels (nil when behind the camera).
local function screen_size()
    local s = runtime_ui.get_surface_size()
    return s.width or 1280, s.height or 800
end
-- Per-frame cache: the overlay projects hundreds of points a frame; fetching the matrix and the
-- surface size across the Lua/C++ boundary for each one was most of the overlay's cost.
local VC = {}
function W.begin_frame()
    VC.vp, VC.inv = cam:get_view_projection(), cam:get_inv_view_projection()
    VC.sw, VC.sh = screen_size()
    -- TAA shifts the projection by a new sub-pixel jitter every frame; overlay points projected through it trembled.
    local ok, j = pcall(function() return cam:get_jitter() end)
    VC.jx, VC.jy = ok and j and j.x or 0, ok and j and j.y or 0
end
function W.project(X, Y, Z)
    local vp = VC.vp or cam:get_view_projection()
    local c = vp * vec4(X, Y, Z, 1)
    if c.w <= 1e-5 then return nil end
    local nx, ny = c.x / c.w - (VC.jx or 0), c.y / c.w - (VC.jy or 0)   -- jitter-free, so the overlay holds still
    local sw, sh = VC.sw, VC.sh
    if not sw then sw, sh = screen_size() end
    if S.flip == nil then
        -- Decide once whether NDC y points down: a point nearer the camera (+z) sits lower on screen.
        local a = vp * vec4(0, 0, -3, 1)
        local b = vp * vec4(0, 0, 3, 1)
        S.flip = (b.y / b.w) < (a.y / a.w)
    end
    local sy = S.flip and (0.5 - ny * 0.5) or (0.5 + ny * 0.5)
    return (nx * 0.5 + 0.5) * sw, sy * sh
end

-- UI pixels -> board cell (or nil), by intersecting the mouse ray with the block tops.
function W.cell_at(mx, my)
    local inv = VC.inv or cam:get_inv_view_projection()
    local sw, sh = VC.sw, VC.sh
    if not sw then sw, sh = screen_size() end
    if S.flip == nil then W.project(0, 0, 0) end
    local nx = mx / sw * 2 - 1 + (VC.jx or 0)                          -- back into the jittered space inv lives in
    local ny = (S.flip and (1 - my / sh * 2) or (my / sh * 2 - 1)) + (VC.jy or 0)
    local a = inv * vec4(nx, ny, 0.25, 1)
    local b = inv * vec4(nx, ny, 0.75, 1)
    local ax, ay, az = a.x / a.w, a.y / a.w, a.z / a.w
    local bx, by, bz = b.x / b.w, b.y / b.w, b.z / b.w
    local dy = by - ay
    if abs(dy) < 1e-6 then return nil end
    local t = (BLOCK_H - ay) / dy
    local X, Z = ax + (bx - ax) * t, az + (bz - az) * t
    local x = floor(X + (R.W + 1) / 2 + 0.5)
    local y = floor(Z + (R.H + 1) / 2 + 0.5)
    if x < 1 or y < 1 or x > R.W or y > R.H then return nil end
    return x, y
end

W.BLOCK_H, W.BEAM_Y = BLOCK_H, BEAM_Y
return W
end
