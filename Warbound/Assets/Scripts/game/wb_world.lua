-- wb_world — the battlefield: render stage, lighting, ground, scenery, gold mine.
-- All static geometry lives under one "World" group. Gameplay reads World.bounds
-- to clamp movement and the camera.

local U = WB.util

local World = {}

-- Playfield is a square centered on the origin: x,z in [-HALF, HALF].
World.HALF = 34.0
World.bounds = { min_x = -34.0, max_x = 34.0, min_z = -34.0, max_z = 34.0 }
-- Resource nodes harvested by Laborers (wb_economy). The gold mine sits on the
-- eastern frontier — reachable from the base but lightly guarded; the lumber forest
-- is a safe grove just west of the player base.
World.mine = { x = 24.0, z = 2.0 }
World.forest = { x = -22.0, z = 16.0 }

-- Configure the renderer for a clean, readable outdoor RTS look. Safe no-ops if a
-- bridge is missing.
function World.setup_stage()
    if settings and settings.set then
        settings.set("draw_grid", false)
        settings.set("draw_aabbs", false)
        settings.set("shadows", true)
        settings.set("ssao", true)
        settings.set("day", true)
        settings.set("IBL", true)
        settings.set("IBL_intensity", 0.7)
        settings.set("lights_intensity", 1.0)
        settings.set("tonemapping", false)
        settings.set("bloom", false)
        settings.set("motion_blur", false)
        settings.set("taa", false)
        settings.set("fxaa", true)
        settings.set("cas_sharpening", true)
        settings.set("cas_sharpness", 0.5)
    end
    -- One warm key light, angled like a low afternoon sun for long unit shadows.
    if lights then
        if lights.get_counts and lights.add_directional then
            local counts = lights.get_counts()
            if not counts or (counts.directional or 0) == 0 then lights.add_directional() end
        end
        if lights.set_directional_light then
            lights.set_directional_light(0, vec3(-0.55, -1.0, -0.35), vec3(1.0, 0.96, 0.86), 2.6)
        end
    end
end

-- Deterministic scatter so the map looks the same every run.
local function scatter_seed() if math.randomseed then math.randomseed(20260616) end end
local function rnd(a, b) return a + (b - a) * math.random() end

local function make_tree(parent, x, z, scale)
    local root = U.group("Tree", parent)
    if not U.valid(root) then return end
    root:set_position(vec3(x, 0.0, z))
    local h = 2.2 * scale
    U.part({ kind = "cylinder", name = "Trunk", parent = root,
        pos = { 0.0, h * 0.5, 0.0 }, scale = { 0.45 * scale, h, 0.45 * scale },
        color = U.COLOR.tree_trunk, emissive = 0.06 })
    U.part({ kind = "cone", name = "Canopy", parent = root,
        pos = { 0.0, h + 1.1 * scale, 0.0 }, scale = { 2.4 * scale, 2.8 * scale, 2.4 * scale },
        color = U.COLOR.tree_leaf, emissive = 0.12 })
    U.part({ kind = "cone", name = "CanopyTop", parent = root,
        pos = { 0.0, h + 2.4 * scale, 0.0 }, scale = { 1.6 * scale, 2.0 * scale, 1.6 * scale },
        color = U.COLOR.tree_leaf, emissive = 0.14 })
end

local function make_rock(parent, x, z, scale)
    U.part({ kind = "sphere", name = "Rock", parent = parent,
        pos = { x, 0.35 * scale, z }, scale = { 1.3 * scale, 0.9 * scale, 1.1 * scale },
        color = U.COLOR.rock, emissive = 0.08 })
end

local function make_gold_mine(parent, x, z)
    local root = U.group("GoldMine", parent)
    if not U.valid(root) then return end
    root:set_position(vec3(x, 0.0, z))
    -- A craggy mound with glittering gold veins.
    U.part({ kind = "cone", name = "Mound", parent = root,
        pos = { 0.0, 1.4, 0.0 }, scale = { 5.0, 3.2, 5.0 }, color = U.COLOR.rock, emissive = 0.06 })
    U.part({ kind = "sphere", name = "Vein1", parent = root,
        pos = { 1.1, 1.2, 0.6 }, scale = { 0.8, 0.8, 0.8 }, color = U.COLOR.gold, emissive = 0.5 })
    U.part({ kind = "sphere", name = "Vein2", parent = root,
        pos = { -0.9, 1.6, -0.4 }, scale = { 0.6, 0.6, 0.6 }, color = U.COLOR.gold, emissive = 0.5 })
    U.part({ kind = "sphere", name = "Vein3", parent = root,
        pos = { 0.2, 2.4, 0.9 }, scale = { 0.5, 0.5, 0.5 }, color = U.COLOR.gold, emissive = 0.5 })
end

-- A denser grove marking the lumber source. Trees cluster around the forest center
-- so Laborers visibly chop wood there (the harvest target is World.forest).
local function make_forest(parent, cx, cz)
    local root = U.group("Forest", parent)
    if not U.valid(root) then return end
    make_tree(root, cx, cz, 1.5)
    local ring = { { -3.4, -1.2 }, { 3.0, -2.0 }, { -2.2, 3.0 }, { 3.4, 2.4 },
                   { -4.6, 1.6 }, { 4.8, -0.6 }, { 0.4, 4.4 }, { 0.0, -4.2 } }
    for _, o in ipairs(ring) do make_tree(root, cx + o[1], cz + o[2], rnd(0.9, 1.3)) end
end

-- Build the whole static world under a fresh "World" group; returns that group.
function World.build()
    local root = U.group("World", nil)
    if not U.valid(root) then return nil end

    local H = World.HALF
    -- Ground: a thin slab (a flat cube — guaranteed horizontal and shadow-catching).
    U.part({ kind = "cube", name = "Ground", parent = root,
        pos = { 0.0, -0.25, 0.0 }, scale = { H * 2.0 + 8.0, 0.5, H * 2.0 + 8.0 },
        color = U.COLOR.grass, emissive = 0.10 })
    -- A few darker grass patches for texture (flat slabs just above the ground).
    U.part({ kind = "cube", name = "Patch1", parent = root,
        pos = { -10.0, 0.02, 8.0 }, scale = { 18.0, 0.05, 14.0 }, color = U.COLOR.grass_dark, emissive = 0.08 })
    U.part({ kind = "cube", name = "Patch2", parent = root,
        pos = { 14.0, 0.02, 12.0 }, scale = { 12.0, 0.05, 20.0 }, color = U.COLOR.grass_dark, emissive = 0.08 })
    -- A dirt path/clearing in the middle where the fight happens.
    U.part({ kind = "cube", name = "Clearing", parent = root,
        pos = { 0.0, 0.03, -2.0 }, scale = { 26.0, 0.05, 22.0 }, color = U.COLOR.dirt, emissive = 0.06 })

    make_gold_mine(root, World.mine.x, World.mine.z)
    make_forest(root, World.forest.x, World.forest.z)

    -- Keep these areas clear of scattered scenery: the central battlefield, the gold
    -- mine, the lumber forest, and the player's base yard (back +z, where the Town
    -- Hall / Barracks sit — see wb_game BUILDINGS).
    local function clear_of_structures(x, z)
        if U.dist2(x, z, World.mine.x, World.mine.z) <= 8.0 then return false end
        if U.dist2(x, z, World.forest.x, World.forest.z) <= 9.0 then return false end
        if z > 19.0 and math.abs(x) < 16.0 then return false end -- base yard
        return true
    end

    -- Scatter trees around the perimeter (leave the central clearing open) and rocks.
    scatter_seed()
    local placed = 0
    for _ = 1, 110 do
        if placed >= 46 then break end
        local x, z = rnd(-H, H), rnd(-H, H)
        if (math.abs(x) > 14.0 or math.abs(z + 2.0) > 13.0) and clear_of_structures(x, z) then
            make_tree(root, x, z, rnd(0.8, 1.4))
            placed = placed + 1
        end
    end
    for _ = 1, 18 do
        local x, z = rnd(-H + 2, H - 2), rnd(-H + 2, H - 2)
        if (math.abs(x) > 12.0 or math.abs(z + 2.0) > 11.0) and clear_of_structures(x, z) then
            make_rock(root, x, z, rnd(0.6, 1.3))
        end
    end

    World.root = root
    return root
end

-- Clamp an (x,z) to stay inside the playfield with a margin.
function World.clamp(x, z, margin)
    margin = margin or 1.0
    local b = World.bounds
    return U.clamp(x, b.min_x + margin, b.max_x - margin),
        U.clamp(z, b.min_z + margin, b.max_z - margin)
end

return World
