local Creep = {}

-- Universal enemy movement scale: every creep's travel speed (base stats,
-- card speed-buffs, summons — everything) is multiplied by this at use time.
-- The one knob to make the whole horde faster or slower.
--
-- The constants below tune the OPT-IN "slow aura" hero buff (hero.slow_aura),
-- which is OFF by default — creeps now keep full base speed all the way to the
-- hero. When the buff is on, creeps blend from full speed at SLOW_FAR down to
-- SPEED_SCALE by SLOW_NEAR (the close-quarters dodging zone). See the slow_aura
-- block in Creep.update.
Creep.SPEED_SCALE = 0.3 -- speed multiplier at point-blank when slow_aura is on
Creep.SLOW_NEAR = 2.5   -- world units from the hero where SPEED_SCALE fully applies
Creep.SLOW_FAR = 5.0    -- beyond this, creeps move at full base speed

Creep.archetypes = {
    rat = {
        name = "Rat",
        threat_cost = 1,
        hp = 4,
        dps = 1.5,
        range = 0.5,
        speed = 2.2,
        color = { 0.58, 0.46, 0.34 },
        head = { 0.72, 0.58, 0.42 },
        parts = 2,
    },
    skeleton = {
        name = "Skeleton",
        threat_cost = 2,
        hp = 10,
        dps = 3.0,
        range = 0.7,
        speed = 1.5,
        color = { 0.76, 0.74, 0.66 },
        head = { 0.90, 0.86, 0.72 },
        weapon = { 0.58, 0.62, 0.66 },
        parts = 3,
    },
    archer = {
        name = "Archer",
        threat_cost = 3,
        hp = 7,
        dps = 2.0,
        range = 6.0,
        speed = 1.2,
        color = { 0.30, 0.54, 0.38 },
        head = { 0.68, 0.52, 0.38 },
        weapon = { 0.48, 0.30, 0.16 },
        parts = 3,
        hold_range = 5.5,
        anchor_hold = true,
        needs_los = true,
        los_reposition_seconds = 2.0,
        projectile = {
            kind = "arrow",
            speed = 36.0,
            cooldown = 1.05,
            start_y = 0.62,
            target_y = 0.76,
            particle_size = 0.24,
            scale = { 0.045, 0.045, 0.42 },
            color = { 0.92, 0.72, 0.36 },
            emissive = 0.65,
            arc = 0.00,
            impact = false,
        },
    },
    bat = {
        name = "Bat",
        threat_cost = 1,
        hp = 3,
        dps = 1.0,
        range = 0.5,
        speed = 3.0,
        color = { 0.34, 0.28, 0.58 },
        head = { 0.48, 0.40, 0.72 },
        parts = 2,
        flies = true,
    },
    ogre = {
        name = "Ogre",
        threat_cost = 5,
        hp = 32,
        dps = 6.0,
        range = 0.9,
        speed = 0.85,
        color = { 0.42, 0.54, 0.34 },
        head = { 0.54, 0.64, 0.42 },
        weapon = { 0.42, 0.28, 0.18 },
        parts = 3,
        scale = 1.30,
    },
    necromancer = {
        name = "Necromancer",
        threat_cost = 3,
        hp = 16,
        dps = 2.5,
        range = 4.5,
        speed = 1.0,
        color = { 0.32, 0.24, 0.42 },
        head = { 0.70, 0.62, 0.86 },
        weapon = { 0.38, 0.70, 0.56 },
        parts = 3,
        hold_range = 4.0,
        anchor_hold = true,
        needs_los = true,
        los_reposition_seconds = 2.0,
        summon_archetype = "skeleton",
        summon_every = 3.0,
        projectile = {
            kind = "orb",
            speed = 9.5,
            cooldown = 0.85,
            start_y = 0.86,
            target_y = 0.98,
            particle_size = 0.36,
            scale = { 0.26, 0.26, 0.26 },
            color = { 0.42, 1.00, 0.72 },
            emissive = 1.55,
            arc = 0.20,
            pulse = true,
            impact = false,
        },
    },
}

Creep.default_archetype = "rat"
Creep.aliases = {}

-- ---------------------------------------------------------------------------
-- Rig pool — spawning a creep builds a small tree of primitive nodes. Fresh rigs
-- are expensive; parking and reusing them keeps combat on transform/material
-- updates instead of delete/create churn. Parked rigs stay enabled but tiny and
-- offstage, because toggling enabled rebuilds the scene draw/instance lists.
Creep.pool = {}      -- archetype id -> array of { root, parts } parked rigs
Creep.pool_cap = 110 -- max parked rigs kept per archetype. Kept ABOVE the arena's
                     -- per-type prewarm + cap_max so prewarmed rigs are all
                     -- retained and a death never overflows the pool into a
                     -- mid-combat scene.delete_node (delete = swap-and-pop hazard).

local PARK_X = -10000.0
local PARK_Y = -10000.0
local PARK_Z = -10000.0

local function normalize_archetype_id(archetype)
    local id = tostring(archetype or "")
    local normalized = id:lower():gsub("%s+", "_"):gsub("%-+", "_")
    return normalized
end

local function resolve_archetype(archetype)
    local id = tostring(archetype or "")
    if Creep.archetypes[id] then return id end
    if Creep.aliases[id] then return Creep.aliases[id] end

    local normalized = normalize_archetype_id(archetype)
    if Creep.archetypes[normalized] then return normalized end
    if Creep.aliases[normalized] then return Creep.aliases[normalized] end

    return Creep.default_archetype or "rat"
end

local function archetype_def(archetype)
    local id = resolve_archetype(archetype)
    return id, Creep.archetypes[id] or Creep.archetypes[Creep.default_archetype] or Creep.archetypes.rat
end

function Creep.apply_roster(roster)
    if not roster then return end
    if roster.monster_archetypes then
        Creep.archetypes = roster.monster_archetypes
    end
    Creep.default_archetype = roster.default_monster_id or Creep.default_archetype
    Creep.aliases = roster.legacy_monster_aliases or {}
end

function Creep.resolve_archetype(archetype)
    return resolve_archetype(archetype)
end

local function valid(node)
    return node and node:is_valid()
end

-- Cascade deletes elsewhere swap-and-pop sibling nodes and bump their
-- revision, which stale-handles our cached root even though the scene node
-- lives on. Re-look up by name so update/destroy stay correct.
local function refresh_root(self)
    if valid(self.root) then return self.root end
    if not (self and self.id and self.archetype and scene and scene.find_model) then return nil end
    local fresh = scene.find_model("Horde_Creep_" .. tostring(self.id) .. "_" .. tostring(self.archetype))
    if valid(fresh) then
        self.root = fresh
        return fresh
    end
    return nil
end

local function attach(node, parent)
    if valid(node) and valid(parent) then
        node:set_parent(parent)
    end
    return node
end

local function tint(node, color, emissive)
    if not valid(node) then return end
    material.set(node, "base_color", vec4(color[1], color[2], color[3], color[4] or 1.0))
    material.set(node, "emissive", vec3(color[1] * (emissive or 0.12), color[2] * (emissive or 0.12), color[3] * (emissive or 0.12)))
    material.set(node, "roughness", 0.84)
    material.set(node, "metallic", 0.0)
end

local function make_group(name, parent)
    local node = scene.add_empty_node(name)
    if not valid(node) then return nil end
    node:set_name(name)
    attach(node, parent)
    return node
end

local function cube(name, pos, scale, color, parent, emissive)
    local node = primitives.cube(1.0)
    if not valid(node) then return nil end
    node:set_name(name)
    attach(node, parent)
    node:set_position(pos)
    node:set_scale(scale)
    tint(node, color, emissive or 0.12)
    return node
end

local function sphere(name, pos, scale, color, parent, emissive)
    local node = primitives.sphere(0.5)
    if not valid(node) then
        return cube(name, pos, scale, color, parent, emissive)
    end
    node:set_name(name)
    attach(node, parent)
    node:set_position(pos)
    node:set_scale(scale)
    tint(node, color, emissive or 0.12)
    return node
end

local function cylinder(name, pos, scale, color, parent, emissive)
    local node = primitives.cylinder(0.5, 1.0)
    if not valid(node) then
        return cube(name, pos, scale, color, parent, emissive)
    end
    node:set_name(name)
    attach(node, parent)
    node:set_position(pos)
    node:set_scale(scale)
    tint(node, color, emissive or 0.12)
    return node
end

local function v3(values, fallback)
    values = values or fallback or { 0.0, 0.0, 0.0 }
    return vec3(values[1] or 0.0, values[2] or 0.0, values[3] or 0.0)
end

local function rotate(node, values)
    if valid(node) and values then
        node:set_rotation(vec3(values[1] or 0.0, values[2] or 0.0, values[3] or 0.0))
    end
    return node
end

local function add_silhouette(self, arch)
    local silhouette = arch and arch.silhouette or nil
    if silhouette == "debtor" then
        self.parts.identity = cylinder("Debtor_Yellow_Base", vec3(0.0, 0.035, 0.0), vec3(0.34, 0.035, 0.34), { 0.94, 0.72, 0.18 }, self.root, 0.38)
        self.parts.back_spike = cube("Ledger_Spike", vec3(0.0, 0.70, 0.12), vec3(0.07, 0.50, 0.07), { 0.18, 0.16, 0.12 }, self.root, 0.10)
        self.parts.ledger = cube("Huge_Ledger", vec3(0.0, 0.43, -0.23), vec3(0.46, 0.36, 0.06), { 0.76, 0.66, 0.42 }, self.root, 0.22)
        self.parts.ledger_nail = cube("Ledger_Nail", vec3(0.0, 0.46, -0.23), vec3(0.06, 0.32, 0.035), { 0.18, 0.16, 0.14 }, self.root, 0.12)
        self.parts.lantern = cube("Bright_Lantern", vec3(0.36, 0.34, -0.10), vec3(0.18, 0.26, 0.18), { 1.00, 0.72, 0.16 }, self.root, 1.10)
        self.parts.lantern_handle = rotate(cylinder("Lantern_Handle", vec3(0.30, 0.40, -0.10), vec3(0.11, 0.025, 0.11), { 0.34, 0.28, 0.16 }, self.root, 0.18), { 90.0, 0.0, 0.0 })
    elseif silhouette == "bell_maiden" then
        self.parts.identity = cylinder("Maiden_Violet_Base", vec3(0.0, 0.035, 0.0), vec3(0.40, 0.035, 0.40), { 0.64, 0.46, 0.92 }, self.root, 0.42)
        self.parts.skirt = cylinder("Wide_Bell_Robe", vec3(0.0, 0.26, 0.0), vec3(0.54, 0.42, 0.54), { 0.34, 0.30, 0.36 }, self.root, 0.14)
        self.parts.bell = cylinder("Huge_Hand_Bell", vec3(0.42, 0.46, -0.14), vec3(0.30, 0.34, 0.30), { 0.82, 0.62, 0.20 }, self.root, 0.62)
        self.parts.bell_handle = cube("Bell_Handle", vec3(0.34, 0.62, -0.12), vec3(0.07, 0.20, 0.07), { 0.42, 0.32, 0.14 }, self.root, 0.18)
        self.parts.clapper = sphere("Bell_Clapper", vec3(0.34, 0.26, -0.12), vec3(0.08, 0.08, 0.08), { 0.92, 0.76, 0.36 }, self.root, 0.36)
        self.parts.veil = cube("Tall_Black_Veil", vec3(0.0, 0.88, -0.04), vec3(0.58, 0.52, 0.10), { 0.08, 0.06, 0.10 }, self.root, 0.10)
        self.parts.halo = rotate(cylinder("Bell_Halo", vec3(0.0, 1.20, 0.0), vec3(0.48, 0.045, 0.48), { 0.86, 0.62, 0.18 }, self.root, 0.48), { 90.0, 0.0, 0.0 })
    elseif silhouette == "vault_knight" then
        self.parts.identity = cylinder("Vault_Blue_Base", vec3(0.0, 0.035, 0.0), vec3(0.42, 0.035, 0.42), { 0.34, 0.58, 0.94 }, self.root, 0.36)
        self.parts.shield = cube("Tower_Greatshield", vec3(-0.42, 0.46, 0.08), vec3(0.46, 0.82, 0.11), { 0.38, 0.40, 0.46 }, self.root, 0.20)
        self.parts.coin_seal = cylinder("Coin_Seal", vec3(0.0, 0.48, -0.20), vec3(0.22, 0.035, 0.22), { 0.80, 0.62, 0.30 }, self.root, 0.28)
        if valid(self.parts.coin_seal) then self.parts.coin_seal:set_rotation(vec3(90.0, 0.0, 0.0)) end
        self.parts.helmet = cube("Blocky_Vault_Helmet", vec3(0.0, 0.82, 0.0), vec3(0.54, 0.34, 0.48), { 0.20, 0.22, 0.26 }, self.root, 0.12)
        self.parts.visor = cube("Coin_Visor", vec3(0.0, 0.78, -0.22), vec3(0.34, 0.06, 0.035), { 0.78, 0.62, 0.30 }, self.root, 0.18)
        self.parts.left_pauldron = sphere("Left_Pauldron", vec3(-0.34, 0.58, 0.0), vec3(0.22, 0.14, 0.22), { 0.32, 0.34, 0.38 }, self.root, 0.12)
        self.parts.right_pauldron = sphere("Right_Pauldron", vec3(0.34, 0.58, 0.0), vec3(0.22, 0.14, 0.22), { 0.32, 0.34, 0.38 }, self.root, 0.12)
    elseif silhouette == "grave_bailiff" then
        self.parts.identity = cylinder("Bailiff_Teal_Base", vec3(0.0, 0.035, 0.0), vec3(0.38, 0.035, 0.38), { 0.22, 0.80, 0.76 }, self.root, 0.38)
        self.parts.hood = cube("Tall_Bailiff_Hood", vec3(0.0, 0.88, 0.0), vec3(0.46, 0.36, 0.40), { 0.06, 0.08, 0.08 }, self.root, 0.10)
        self.parts.pole = cube("Very_Tall_Hooked_Pole", vec3(0.46, 0.68, 0.08), vec3(0.07, 1.20, 0.07), { 0.72, 0.70, 0.58 }, self.root, 0.18)
        self.parts.hook = cube("Wide_Bailiff_Hook", vec3(0.58, 1.24, 0.08), vec3(0.36, 0.07, 0.07), { 0.82, 0.80, 0.66 }, self.root, 0.22)
        self.parts.hook_tip = cube("Hook_Tip", vec3(0.72, 1.08, 0.08), vec3(0.07, 0.34, 0.07), { 0.82, 0.80, 0.66 }, self.root, 0.22)
        self.parts.writ = cube("Large_Collection_Writ", vec3(-0.26, 0.46, -0.20), vec3(0.32, 0.34, 0.045), { 0.82, 0.72, 0.48 }, self.root, 0.18)
        self.parts.grave_tag = cube("Grave_Tag", vec3(-0.28, 0.64, -0.18), vec3(0.20, 0.08, 0.035), { 0.52, 0.50, 0.44 }, self.root, 0.12)
    elseif silhouette == "coffer_beast" then
        self.parts.identity = cylinder("Coffer_Orange_Base", vec3(0.0, 0.035, 0.0), vec3(0.48, 0.035, 0.48), { 0.92, 0.48, 0.16 }, self.root, 0.36)
        self.parts.coffer = cube("Giant_Chained_Coffer", vec3(0.0, 0.48, -0.32), vec3(0.82, 0.54, 0.22), { 0.48, 0.30, 0.16 }, self.root, 0.20)
        self.parts.chain = cube("Huge_Coffer_Chain", vec3(0.0, 0.66, -0.48), vec3(0.94, 0.09, 0.07), { 0.64, 0.62, 0.54 }, self.root, 0.22)
        self.parts.lock = cube("Bright_Coffer_Lock", vec3(0.0, 0.44, -0.52), vec3(0.22, 0.24, 0.06), { 0.92, 0.64, 0.22 }, self.root, 0.30)
        self.parts.left_arm = cube("Left_Brute_Arm", vec3(-0.62, 0.40, 0.02), vec3(0.24, 0.52, 0.22), { 0.30, 0.24, 0.18 }, self.root, 0.12)
        self.parts.right_arm = cube("Right_Brute_Arm", vec3(0.62, 0.40, 0.02), vec3(0.24, 0.52, 0.22), { 0.30, 0.24, 0.18 }, self.root, 0.12)
    elseif silhouette == "mother_tithe" then
        self.parts.identity = cylinder("Mother_Green_Base", vec3(0.0, 0.035, 0.0), vec3(0.56, 0.035, 0.56), { 0.24, 1.00, 0.62 }, self.root, 0.45)
        self.parts.cathedral = cube("Tall_Cathedral_Back", vec3(0.0, 0.98, 0.08), vec3(0.58, 0.78, 0.26), { 0.22, 0.20, 0.24 }, self.root, 0.22)
        self.parts.steeple = cube("Huge_Steeple", vec3(0.0, 1.62, 0.08), vec3(0.22, 0.72, 0.22), { 0.28, 0.26, 0.30 }, self.root, 0.28)
        self.parts.left_tower = cube("Left_Tower", vec3(-0.38, 1.18, 0.10), vec3(0.20, 0.60, 0.20), { 0.24, 0.22, 0.26 }, self.root, 0.20)
        self.parts.right_tower = cube("Right_Tower", vec3(0.38, 1.18, 0.10), vec3(0.20, 0.60, 0.20), { 0.24, 0.22, 0.26 }, self.root, 0.20)
        self.parts.window = cube("Bright_Tithe_Window", vec3(0.0, 0.98, -0.20), vec3(0.28, 0.42, 0.045), { 0.42, 1.00, 0.72 }, self.root, 1.10)
        self.parts.tithe_glow = sphere("Tithe_Glow", vec3(0.0, 0.78, -0.24), vec3(0.34, 0.34, 0.34), { 0.42, 1.00, 0.72 }, self.root, 1.40)
        self.parts.left_leg_arch = cube("Left_Leg_Arch", vec3(-0.22, 0.20, -0.06), vec3(0.12, 0.36, 0.12), { 0.18, 0.16, 0.20 }, self.root, 0.12)
        self.parts.right_leg_arch = cube("Right_Leg_Arch", vec3(0.22, 0.20, -0.06), vec3(0.12, 0.36, 0.12), { 0.18, 0.16, 0.20 }, self.root, 0.12)
    end
end

local function set_world(self, x, z)
    self.x = x
    self.z = z
    if valid(self.root) then
        self.root:set_position(vec3(x, 0.0, z))
    end
end

local function has_line_of_sight(map, ax, az, bx, bz)
    if not map or not map.is_walkable then return true end
    local dx = (bx or 0.0) - (ax or 0.0)
    local dz = (bz or 0.0) - (az or 0.0)
    local steps = math.max(math.ceil(math.max(math.abs(dx), math.abs(dz)) * 2.0), 1)
    for i = 1, steps - 1 do
        local t = i / steps
        local x = math.floor((ax or 0.0) + dx * t + 0.5)
        local y = math.floor((az or 0.0) + dz * t + 0.5)
        if not map:is_walkable(x, y) then return false end
    end
    return true
end

local function projectile_phase(id)
    return ((tonumber(id) or 0) * 37 % 100) / 100.0
end

local function projectile_duration(self, target, spec)
    if spec.duration then return math.max(spec.duration, 0.04) end
    local sx = self.x or 0.0
    local sy = spec.start_y or 0.76
    local sz = self.z or 0.0
    local tx = target.x or 0.0
    local ty = spec.target_y or 0.92
    local tz = target.z or 0.0
    local dx = tx - sx
    local dy = ty - sy
    local dz = tz - sz
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    return math.max(distance / math.max(spec.speed or 12.0, 0.1), 0.04)
end

local function make_rig(self, parent)
    local arch = self.stats
    self.root = make_group("Horde_Creep_" .. tostring(self.id) .. "_" .. self.archetype, parent)
    -- Sprite creeps are flat cards laid on the ground (View flattens the body).
    -- The body is a CUBE; its authored ~0.05 thickness shows its RIM as a thin
    -- line under the slightly tilted top-down camera. Flatten the slab to
    -- sub-pixel so only the textured top face reads. Non-sprite (3D) creeps keep
    -- their authored thickness.
    local bs = arch.body_scale or { 0.42, 0.48, 0.34 }
    local body_scale = arch.sprite
        and vec3(bs[1] or 0.42, bs[2] or 0.48, 0.004)
        or v3(arch.body_scale, { 0.42, 0.48, 0.34 })
    self.parts = {
        body = cube("Body", v3(arch.body_pos, { 0.0, 0.32, 0.0 }), body_scale, arch.color, self.root, 0.16),
        head = sphere("Head", v3(arch.head_pos, { 0.0, 0.72, 0.0 }), v3(arch.head_scale, { 0.30, 0.28, 0.30 }), arch.head or arch.color, self.root, 0.16),
    }

    if (arch.parts or 2) >= 3 then
        self.parts.weapon = cube("Weapon", v3(arch.weapon_pos, { 0.30, 0.42, 0.08 }), v3(arch.weapon_scale, { 0.08, 0.48, 0.08 }), arch.weapon or { 0.52, 0.52, 0.52 }, self.root, 0.12)
        if self.archetype == "archer" then
            self.parts.bow = cylinder("Bow", vec3(0.36, 0.52, 0.0), vec3(0.08, 0.62, 0.08), arch.weapon or { 0.48, 0.30, 0.16 }, self.root, 0.12)
            if valid(self.parts.bow) then self.parts.bow:set_rotation(vec3(0.0, 0.0, 82.0)) end
        end
    end
    add_silhouette(self, arch)

    set_world(self, self.x, self.z)
    if valid(self.root) then
        local scale = arch.scale or (self.elite and 1.18) or 1.0
        self.root:set_scale(vec3(scale, scale, scale))
    end
    self.visual_alive = valid(self.root) and valid(self.parts and self.parts.body)
end

local function hit_fx_prefix(self)
    if not self or self.id == nil then return nil end
    return "ath_hit_creep_" .. tostring(self.id) .. "_"
end

-- Pop a still-valid parked rig for this archetype, discarding any whose handles
-- went stale while parked (a sibling delete can swap-and-pop them). Returns the
-- { root, parts } entry, or nil when the pool is empty / all stale.
local function pop_pooled(archetype)
    local list = Creep.pool[archetype]
    if not list then return nil end
    while #list > 0 do
        local entry = list[#list]
        list[#list] = nil
        if entry and valid(entry.root) and entry.parts and valid(entry.parts.body) then
            return entry
        end
    end
    return nil
end

-- Re-dress a reused rig for a new creep: rename to the new id (refresh_root
-- looks the root up by name), restore the rest pose, reposition, then enable.
-- The per-archetype glow/extras/scale ath_duel applies on spawn are constant
-- across reuses, so they survive parking and only the node-adding extras need
-- skipping on reuse (see Duel:dress_creep + creep.fresh_rig). Parked rigs keep
-- their original parent (the actors group), which is also where spawns go, so
-- no re-parent is needed here.
local function reset_rig(self)
    local root = self.root
    if not valid(root) then return false end
    root:set_name("Horde_Creep_" .. tostring(self.id) .. "_" .. self.archetype)
    local arch = self.stats
    local scale = arch.scale or (self.elite and 1.18) or 1.0
    root:set_scale(vec3(scale, scale, scale))
    root:set_rotation(vec3(0.0, 0.0, 0.0))
    set_world(self, self.x, self.z)
    if valid(self.parts.body) then self.parts.body:set_position(v3(arch.body_pos, { 0.0, 0.32, 0.0 })) end
    if valid(self.parts.head) then self.parts.head:set_position(v3(arch.head_pos, { 0.0, 0.72, 0.0 })) end
    if valid(self.parts.weapon) then self.parts.weapon:set_rotation(vec3(0.0, 0.0, 0.0)) end
    self.visual_alive = valid(self.parts.body)
    return true
end

function Creep.create(args)
    local archetype, arch = archetype_def(args.archetype)
    local mods = args.mods or {}
    local hp_multiplier = (args.hp_multiplier or 1.0) * (mods.hp_multiplier or 1.0)
    local dps_multiplier = (args.dps_multiplier or 1.0) * (mods.dps_multiplier or 1.0)
    local stats = {
        name = arch.name,
        threat_cost = arch.threat_cost,
        hp = math.max(1.0, ((arch.hp or 1.0) + (mods.hp_add or 0.0)) * hp_multiplier),
        dps = math.max(0.1, ((arch.dps or 1.0) + (mods.dps_add or 0.0)) * dps_multiplier),
        range = math.max(0.1, (arch.range or 0.5) + (mods.range_add or 0.0)),
        speed = math.max(0.1, (arch.speed or 1.0) + (mods.speed_add or 0.0)),
        color = arch.color,
        head = arch.head,
        weapon = arch.weapon,
        body_pos = arch.body_pos,
        body_scale = arch.body_scale,
        head_pos = arch.head_pos,
        head_scale = arch.head_scale,
        weapon_pos = arch.weapon_pos,
        weapon_scale = arch.weapon_scale,
        parts = arch.parts,
        sprite = arch.sprite == true,
        silhouette = arch.silhouette,
        hold_range = arch.hold_range and math.max(0.1, arch.hold_range + (mods.range_add or 0.0)) or nil,
        anchor_hold = arch.anchor_hold == true,
        needs_los = arch.needs_los == true,
        los_reposition_seconds = arch.los_reposition_seconds or 2.0,
        summon_archetype = arch.summon_archetype,
        summon_every = arch.summon_every,
        projectile = arch.projectile,
        flies = arch.flies == true,
        scale = arch.scale,
    }
    local self = {
        id = args.id,
        archetype = archetype,
        arch = arch,
        stats = stats,
        -- no_pool rigs are never parked OR reused: each one is freshly built
        -- and really deleted. Costs a primitive build per spawn but immunises
        -- the rig against stale-handle remaps across park/reuse cycles.
        no_pool = args.no_pool == true,
        elite = args.elite == true,
        anchor_id = args.anchor_id,
        room_id = args.room_id,
        x = args.x,
        z = args.z,
        spawn_x = args.x,
        spawn_z = args.z,
        hp = stats.hp,
        hp_max = stats.hp,
        alive = true,
        phase = 0.0,
        contact_t = 0.0,
        los_blocked_t = 0.0,
        repositioning = false,
        summon_t = 0.0,
        projectile_t = 0.0,
        projectile_flight_t = 0.0,
        projectile_started = false,
        root = nil,
        parts = {},
        summoned = args.summoned == true,
        source_id = args.source_id,
    }
    -- Reuse a parked rig for this archetype when one is available; otherwise
    -- build a fresh one. `fresh_rig` tells ath_duel whether the archetype's
    -- node-adding decoration still needs applying (it survives parking).
    -- `no_pool` forces a fresh build for callers that explicitly need a new rig
    -- instead of recycling a parked one.
    local pooled = (not args.no_pool) and pop_pooled(archetype) or nil
    local reused = false
    if pooled then
        self.root = pooled.root
        self.parts = pooled.parts
        reused = reset_rig(self)
    end
    if reused then
        self.fresh_rig = false
    else
        self.root = nil
        self.parts = {}
        make_rig(self, args.parent)
        self.fresh_rig = true
    end
    return self
end

function Creep.hit_fx_name(self, kind)
    local prefix = hit_fx_prefix(self)
    if not prefix then return nil end
    return prefix .. tostring(kind or "hit")
end

function Creep.has_line_of_sight(map, a, b)
    if not a or not b then return false end
    return has_line_of_sight(map, a.x, a.z, b.x, b.z)
end

function Creep.attack_projectile(self, target, damage)
    if not self or not target or not self.alive then return nil end
    local stats = self.stats or {}
    local spec = stats.projectile
    if not spec and (stats.range or 0.0) < 1.25 then return nil end

    spec = spec or {}
    if not self.projectile_started then
        self.projectile_started = true
        local opening = spec.opening_delay
        if opening == nil then
            opening = 0.05 + projectile_phase(self.id) * 0.65
        end
        if opening > 0.0 then
            self.projectile_t = opening
            return nil
        end
    end
    if (self.projectile_t or 0.0) > 0.0 then return nil end
    if spec.allow_overlap ~= true and (self.projectile_flight_t or 0.0) > 0.0 then return nil end

    local duration = projectile_duration(self, target, spec)
    local max_flight_time = spec.max_flight_time or math.max(duration + (spec.flight_grace or 0.08), 0.08)
    local cooldown = spec.cooldown or 0.65
    local jitter = (projectile_phase(self.id) - 0.5) * (spec.cooldown_jitter or 0.24)
    self.projectile_t = math.max(cooldown + jitter, 0.20)
    if spec.allow_overlap ~= true then
        self.projectile_flight_t = max_flight_time
    end

    local color = spec.color or stats.weapon or stats.head or stats.color or { 0.82, 0.86, 1.00 }
    local scale = spec.scale or { 0.10, 0.10, 0.46 }

    local sy = spec.start_y or 0.76
    local ty = spec.target_y or 0.92
    local dx = (target.x or 0.0) - self.x
    local dz = (target.z or 0.0) - self.z
    local dy = ty - sy
    local horizontal = math.sqrt(dx * dx + dz * dz)
    local speed = spec.speed or 12.0
    local gravity = spec.gravity or 0.0

    -- Aim direction: pre-compensate the vertical aim for gravity drop over
    -- the estimated flight time so a straight-shot keeps hitting the target.
    local flight_time_est = horizontal > 0.001 and (horizontal / speed) or 0.0
    local aim_y = dy - 0.5 * gravity * flight_time_est * flight_time_est
    local aim_dist = math.sqrt(horizontal * horizontal + aim_y * aim_y)
    local inv = aim_dist > 0.001 and (1.0 / aim_dist) or 0.0
    local vx = dx * inv * speed
    local vy = aim_y * inv * speed
    local vz = dz * inv * speed

    return {
        kind = spec.kind or "bolt",
        source_id = self.id,
        source_archetype = self.archetype,
        sx = self.x,
        sy = sy,
        sz = self.z,
        tx = target.x or 0.0,
        ty = ty,
        tz = target.z or 0.0,
        vx = vx, vy = vy, vz = vz,
        gravity = gravity,
        drag = spec.drag or 0.0,
        hit_radius = spec.hit_radius or 0.6,
        max_flight_time = max_flight_time,
        speed = speed,
        duration = duration,
        particle_size = spec.particle_size,
        scale = { scale[1] or 0.10, scale[2] or 0.10, scale[3] or 0.46 },
        color = { color[1] or 0.82, color[2] or 0.86, color[3] or 1.00, color[4] or 1.0 },
        emissive = spec.emissive or 0.90,
        arc = spec.arc or 0.0,
        pulse = spec.pulse == true,
        impact = spec.impact == true,
        damage = damage or 0.0,
    }
end

function Creep.threat_cost(archetype)
    local _, arch = archetype_def(archetype)
    return arch.threat_cost or 1
end

function Creep.damage(self, amount)
    if not self or not self.alive then return false end
    self.hp = self.hp - math.max(amount or 0.0, 0.0)
    if self.hp > 0.0 then return false end
    self.alive = false
    return true
end

function Creep.clear_hit_fx(self)
    local prefix = hit_fx_prefix(self)
    if not prefix or not particles or not particles.find or not particles.set_emitter then return end

    for _ = 1, 64 do
        local index = particles.find(prefix)
        if not index or index < 0 then return end
        if particles.kill_emitter_particles then particles.kill_emitter_particles(index) end
        particles.set_emitter(index, {
            name = "__ath_hidden_hit_fx",
            spawn_rate = 0.0,
            color_start = vec4(0.0, 0.0, 0.0, 0.0),
            color_end = vec4(0.0, 0.0, 0.0, 0.0),
            size_min = 0.0,
            size_max = 0.0,
        })
    end
end

-- Park a dead creep's rig for reuse instead of deleting it. Keep the node enabled
-- and hide it by transform; enabled toggles rebuild draw/instance lists.
function Creep.destroy(self)
    if not self then return end
    Creep.clear_hit_fx(self)
    self.visual_alive = false
    local handle = refresh_root(self)
    if valid(handle) and self.no_pool then
        handle:set_scale(vec3(0.001, 0.001, 0.001))
        scene.delete_node(handle)
        self.root = nil
        self.parts = {}
        return
    end
    if valid(handle) and self.parts and valid(self.parts.body) then
        local list = Creep.pool[self.archetype]
        if not list then
            list = {}
            Creep.pool[self.archetype] = list
        end
        if #list < Creep.pool_cap then
            handle:set_position(vec3(PARK_X, PARK_Y, PARK_Z))
            handle:set_scale(vec3(0.001, 0.001, 0.001))
            list[#list + 1] = { root = handle, parts = self.parts }
        else
            handle:set_scale(vec3(0.001, 0.001, 0.001))
            scene.delete_node(handle)
        end
    elseif valid(handle) then
        handle:set_scale(vec3(0.001, 0.001, 0.001))
        scene.delete_node(handle)
    end
    self.root = nil
    self.parts = {}
end

-- Delete every parked rig and empty the pool. Call when the scene/duel is torn
-- down or rebuilt so pooled handles don't dangle into a new scene.
function Creep.clear_pool()
    for _, list in pairs(Creep.pool) do
        for _, entry in ipairs(list) do
            if valid(entry.root) then scene.delete_node(entry.root) end
        end
    end
    Creep.pool = {}
end

function Creep.update(self, dt, field, map, hero)
    if not self or not self.alive then return false end
    -- Only the root's existence indicates the creep is still in the scene;
    -- part handles can stale-out independently without the node being gone.
    self.visual_alive = valid(refresh_root(self))
    if not self.visual_alive then
        self.alive = false
        return false
    end

    self.projectile_t = math.max((self.projectile_t or 0.0) - dt, 0.0)
    self.projectile_flight_t = math.max((self.projectile_flight_t or 0.0) - dt, 0.0)

    local dxh = (hero.x or 0.0) - self.x
    local dzh = (hero.z or 0.0) - self.z
    local hero_dist = math.sqrt(dxh * dxh + dzh * dzh)
    local vx, vz = 0.0, 0.0
    local event = nil
    local has_los = not self.stats.needs_los or has_line_of_sight(map, self.x, self.z, hero.x, hero.z)
    local in_hold_range = self.stats.anchor_hold and hero_dist <= (self.stats.hold_range or self.stats.range or 5.0)
    if in_hold_range and not has_los then
        self.los_blocked_t = (self.los_blocked_t or 0.0) + dt
    else
        self.los_blocked_t = 0.0
    end

    local repositioning = in_hold_range
        and not has_los
        and (self.los_blocked_t or 0.0) >= (self.stats.los_reposition_seconds or 2.0)
    if repositioning and not self.repositioning then
        event = event or {}
        event.reposition_started = true
    end
    self.repositioning = repositioning
    local holding = in_hold_range and not repositioning

    if not holding then
        if field and field.sample then
            local sx, sz = field.sample(field, self.x, self.z)
            vx = sx or 0.0
            vz = sz or 0.0
        end
        if vx == 0.0 and vz == 0.0 and hero_dist > 0.001 then
            vx = dxh / hero_dist
            vz = dzh / hero_dist
        end
    end

    -- Close-quarters slow is now an OPT-IN HERO BUFF (hero.slow_aura), OFF by
    -- default: creeps keep FULL base speed all the way in, so the swarm keeps its
    -- pressure on the ranged hero. A future gear/card sets hero.slow_aura=true (a
    -- "slow aura" buff) to re-enable the blend: creeps ramp from full speed at
    -- SLOW_FAR down to SPEED_SCALE by SLOW_NEAR. Was previously always-on (melee).
    local speed_scale = 1.0
    if hero and hero.slow_aura then
        local slow_t = 0.0
        if hero_dist >= Creep.SLOW_FAR then
            slow_t = 1.0
        elseif hero_dist > Creep.SLOW_NEAR then
            slow_t = (hero_dist - Creep.SLOW_NEAR) / (Creep.SLOW_FAR - Creep.SLOW_NEAR)
        end
        speed_scale = Creep.SPEED_SCALE + (1.0 - Creep.SPEED_SCALE) * slow_t
    end
    local speed = (self.stats.speed or 1.0) * speed_scale
    local next_x = self.x + vx * speed * dt
    local next_z = self.z + vz * speed * dt
    local tile_x = math.floor(next_x + 0.5)
    local tile_y = math.floor(next_z + 0.5)
    if self.stats.flies or not map or map:is_walkable(tile_x, tile_y) then
        set_world(self, next_x, next_z)
    end

    self.contact_t = hero_dist <= (hero.body_radius or 0.65) and (self.contact_t + dt) or 0.0

    self.phase = self.phase + dt * (holding and 3.0 or 8.0)
    local sprite = self.stats.sprite == true
    if valid(self.root) and not sprite then
        local facing = hero_dist > 0.001 and math.deg(math.atan(dxh, dzh)) or 0.0
        self.root:set_rotation(vec3(0.0, facing, 0.0))
    end
    if valid(self.parts.body) and not sprite then
        local bob = holding and 0.02 or 0.05 * math.abs(math.sin(self.phase))
        local pos = self.stats.body_pos or { 0.0, 0.32, 0.0 }
        self.parts.body:set_position(vec3(pos[1] or 0.0, (pos[2] or 0.32) + bob, pos[3] or 0.0))
    end
    if valid(self.parts.head) and not sprite then
        local pos = self.stats.head_pos or { 0.0, 0.72, 0.0 }
        self.parts.head:set_position(vec3(pos[1] or 0.0, (pos[2] or 0.72) + 0.04 * math.sin(self.phase + 0.6), pos[3] or 0.0))
    end
    if valid(self.parts.weapon) and not sprite then
        local swing = holding and 0.20 or 0.70
        self.parts.weapon:set_rotation(vec3(math.deg(math.sin(self.phase) * swing), 0.0, 0.0))
    end

    if self.stats.summon_archetype then
        self.summon_t = (self.summon_t or 0.0) + dt
        if self.summon_t >= (self.stats.summon_every or 3.0) then
            self.summon_t = self.summon_t - (self.stats.summon_every or 3.0)
            event = event or {}
            event.summon = self.stats.summon_archetype
        end
    end

    return event
end

return Creep
