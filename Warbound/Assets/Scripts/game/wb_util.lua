-- wb_util — small, dependency-free helpers shared across the game.
-- Math on plain numbers (the engine vec3 is float32; keep gameplay math in Lua
-- doubles and only build vec3 at the set_position boundary).

local U = {}

-- ---- scalar math --------------------------------------------------------------

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.lerp(a, b, t) return a + (b - a) * t end

function U.approach(cur, target, max_step)
    local d = target - cur
    if d > max_step then return cur + max_step end
    if d < -max_step then return cur - max_step end
    return target
end

function U.sign(x) if x > 0 then return 1.0 elseif x < 0 then return -1.0 else return 0.0 end end

-- ---- 2D ground-plane math (x,z) -----------------------------------------------

function U.len2(dx, dz) return math.sqrt(dx * dx + dz * dz) end

function U.dist2(ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    return math.sqrt(dx * dx + dz * dz)
end

function U.dist2_sq(ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    return dx * dx + dz * dz
end

-- Normalize (dx,dz); returns (nx, nz, length). Zero vector → (0,0,0).
function U.norm2(dx, dz)
    local l = math.sqrt(dx * dx + dz * dz)
    if l < 1e-6 then return 0.0, 0.0, 0.0 end
    return dx / l, dz / l, l
end

-- ---- colors -------------------------------------------------------------------
-- {r,g,b} or {r,g,b,a}, 0..1. Kept as plain tables; converted to vec3/vec4 in art.

U.COLOR = {
    -- factions
    player      = { 0.30, 0.55, 0.95 },  -- Ironhold blue
    player_trim = { 0.92, 0.80, 0.32 },  -- gold trim
    enemy       = { 0.82, 0.28, 0.24 },  -- Wilds red
    enemy_trim  = { 0.35, 0.22, 0.18 },  -- dark hide
    hero        = { 0.42, 0.72, 1.0 },   -- brighter hero blue
    hero_trim   = { 1.0, 0.86, 0.30 },
    worker      = { 0.46, 0.54, 0.64 },  -- laborer steel-grey
    worker_trim = { 0.72, 0.58, 0.34 },  -- leather tan
    -- buildings
    stone       = { 0.55, 0.53, 0.49 },
    stone_dark  = { 0.42, 0.40, 0.37 },
    roof        = { 0.30, 0.34, 0.52 },  -- Ironhold slate-blue roof
    enemy_stone = { 0.34, 0.20, 0.18 }, enemy_roof = { 0.55, 0.16, 0.12 },
    -- world
    grass       = { 0.28, 0.42, 0.20 },
    grass_dark  = { 0.22, 0.34, 0.16 },
    dirt        = { 0.34, 0.26, 0.17 },
    tree_trunk  = { 0.30, 0.20, 0.12 },
    tree_leaf   = { 0.18, 0.40, 0.18 },
    rock        = { 0.45, 0.45, 0.48 },
    gold        = { 0.95, 0.78, 0.22 },
    -- ui / rings
    select      = { 0.35, 0.95, 0.45 },  -- friendly selection green
    select_foe  = { 0.95, 0.35, 0.30 },  -- enemy selection / target red
    hp_good     = { 0.36, 0.82, 0.40 },
    hp_warn     = { 0.92, 0.74, 0.28 },
    hp_low      = { 0.90, 0.30, 0.26 },
    mana        = { 0.34, 0.58, 0.95 },
    panel       = { 0.06, 0.07, 0.10, 0.92 },
    panel_edge  = { 0.45, 0.38, 0.22, 0.95 },
    ink         = { 0.93, 0.95, 0.99, 1.0 },
}

-- Build a vec3 color (engine type) from a {r,g,b} table, scaled by `k` (default 1).
function U.cv3(c, k)
    k = k or 1.0
    return vec3((c[1] or 0.0) * k, (c[2] or 0.0) * k, (c[3] or 0.0) * k)
end

-- Build a vec4 color from {r,g,b[,a]} (alpha default = a4 arg or table[4] or 1).
function U.cv4(c, a)
    return vec4(c[1] or 0.0, c[2] or 0.0, c[3] or 0.0, a or c[4] or 1.0)
end

-- ---- node art helpers ---------------------------------------------------------

function U.valid(node) return node and node.is_valid and node:is_valid() end

-- Tint a node: base color + a self-lit emissive wash so it reads regardless of
-- where the directional light falls. `emissive` is the wash strength (0..1).
function U.tint(node, color, emissive)
    if not U.valid(node) or not color then return end
    local e = emissive or 0.10
    if not material or not material.set then return end
    material.set(node, "base_color", U.cv4(color, color[4] or 1.0))
    material.set(node, "emissive", U.cv3(color, e))
    material.set(node, "roughness", color.roughness or 0.78)
    material.set(node, "metallic", color.metallic or 0.0)
end

-- Make an empty group node parented under `parent`.
function U.group(name, parent)
    local node = scene.add_empty_node(name)
    if not U.valid(node) then return nil end
    node:set_name(name)
    if U.valid(parent) then node:set_parent(parent) end
    return node
end

-- Create a primitive part and place/scale/color it once. scale is baked at
-- creation (per-frame scale writes are unreliable on this engine).
-- spec: { kind, pos = {x,y,z}, scale = {x,y,z}|n, color, emissive, parent, rot = {x,y,z} }
function U.part(spec)
    local node
    local kind = spec.kind or "cube"
    if kind == "sphere" then node = primitives.sphere(0.5)
    elseif kind == "cylinder" then node = primitives.cylinder(0.5, 1.0)
    elseif kind == "cone" then node = primitives.cone(0.5, 1.0)
    elseif kind == "torus" then node = primitives.torus(0.5, 0.12, 28, 12)
    elseif kind == "plane" then node = primitives.plane(1.0, 1.0)
    elseif kind == "quad" then node = primitives.quad(1.0, 1.0)
    else node = primitives.cube(1.0) end
    if not U.valid(node) then return nil end

    node:set_name(spec.name or kind)
    if U.valid(spec.parent) then node:set_parent(spec.parent) end

    local p = spec.pos or { 0.0, 0.0, 0.0 }
    node:set_position(vec3(p[1] or 0.0, p[2] or 0.0, p[3] or 0.0))

    local s = spec.scale or 1.0
    if type(s) == "number" then
        node:set_scale(vec3(s, s, s))
    else
        node:set_scale(vec3(s[1] or 1.0, s[2] or 1.0, s[3] or 1.0))
    end

    if spec.rot then node:set_rotation(vec3(spec.rot[1] or 0.0, spec.rot[2] or 0.0, spec.rot[3] or 0.0)) end
    if spec.color then U.tint(node, spec.color, spec.emissive) end
    return node
end

-- ---- list helpers -------------------------------------------------------------

-- Remove dead entries in place (entry.alive == false), keeping order.
function U.compact(list, keep)
    local n = 0
    for i = 1, #list do
        local e = list[i]
        if keep(e) then
            n = n + 1
            list[n] = e
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

-- ---- text ---------------------------------------------------------------------
-- The bundled font is ASCII-only; map common glyphs so labels never show "?".
local GLYPHS = { ["—"] = "-", ["–"] = "-", ["•"] = "-", ["…"] = "...", ["→"] = "->", ["×"] = "x" }
function U.ascii(s)
    if type(s) ~= "string" then return s end
    for from, to in pairs(GLYPHS) do s = s:gsub(from, to) end
    return s
end

return U
