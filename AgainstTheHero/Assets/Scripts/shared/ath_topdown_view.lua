-- ath_topdown_view — top-down 2D presentation helper for flat-sprite modes.
--
-- PURE CONTENT. This touches NO shared engine file (ath_duel.lua / duel_creep.lua
-- stay pristine). It uses only the mode HOOKS the Duel already exposes plus public
-- node/material calls, so the whole "2D flat sprites under a straight-down camera"
-- look lives in mode-land.
--
-- HOW IT WORKS
--   * Straight-down orthographic camera (CAM_OFFSET) -> the floor reads as a flat
--     2D map and the arena is seen from directly above.
--   * Every sprite (hero + flagged creeps) is laid FLAT on the ground (FLAT_ROT)
--     with its textured face pointing up at the camera, so the front-facing art
--     reads head-up on screen with NO
--     redraw. A flat quad always faces a straight-down camera, so there is no
--     per-sprite billboard math and nothing stretches with the window aspect (the
--     ortho projection is already aspect-correct).
--   * The Duel yaws creep/hero roots toward the hero each frame (would spin a flat
--     card), so tick() resets those roots to identity and re-lays the bodies flat.
--
-- A mode opts in (see modes/spud_fields/mode.lua):
--   config.arena.cam_offset   = View.CAM_OFFSET
--   config.arena.ortho_size   = ~66   (full-arena top-down framing)
--   config.hero.sprite_texture = "Textures/modes/<id>/hero.png"
--   archetypes that are flat sprites set  sprite = true  and  texture = "..."
--   hooks.on_spawn       = function(D,c) View.on_spawn(D,c) end
--   hooks.on_combat_tick = function(D,dt) View.tick(D); <mode mechanic> end

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)

local View = {}

-- Dev-only hitbox overlay (ATH_DEV=1): translucent discs floating ABOVE the
-- flat sprites, showing the ACTUAL collision radii — cyan = hero body_radius,
-- red = each creep's contact reach. Discs are sized at NODE CREATION (the only
-- scale path that reliably renders) and repositioned per frame (position
-- writes always render).
local DEV_HITBOXES = ATH_COMMON.env_enabled and ATH_COMMON.env_enabled("ATH_DEV", false) or false
local HITBOX_Y = 2.5 -- above every flat-laid sprite

local function make_hitbox_disc(name, x, z, radius, color, parent)
    local disc = Art.cylinder(name, vec3(x, HITBOX_Y, z),
        vec3(radius * 2.0, 0.02, radius * 2.0), color, parent, 2.0)
    if Art.valid(disc) and material and material.set_render_type then
        material.set_render_type(disc, "alpha_blend")
    end
    return disc
end

-- Straight-down-ish ortho rig. The small z keeps the camera's `up` stable (a
-- perfectly vertical look_at is degenerate) and is visually imperceptible.
View.CAM_OFFSET = { x = 0.0, y = 60.0, z = 6.0 }

-- Flat-lay rotation (degrees, pitch/yaw/roll). A primitives.quad / cube face
-- points +Z by default; pitch -90 lays it flat with the textured face pointing UP
-- at the camera and the texture's "up" pointing along -Z (screen-up under this
-- rig). IF SPRITES COME OUT WRONG ON YOUR MACHINE, tune this one constant:
--   upside-down -> { -90.0, 180.0, 0.0 }   (or pitch 90)
--   rotated 90  -> change yaw by +/-90
View.FLAT_ROT = { -90.0, 0.0, 0.0 }

-- Cache the rotation vec3s. Calling vec3() per creep per frame allocates a fresh
-- userdata each time -> Lua GC churn -> recurring tiny frame spikes. These are
-- reused every frame; FLAT_VEC self-heals if FLAT_ROT is edited and reloaded.
local ZERO_VEC = vec3(0.0, 0.0, 0.0)
local FLAT_VEC = vec3(View.FLAT_ROT[1], View.FLAT_ROT[2], View.FLAT_ROT[3])

local function number_or(value, fallback)
    local n = tonumber(value)
    if n ~= nil then return n end
    return fallback
end

local function topdown_config(D)
    return (D and D.config and D.config.topdown) or {}
end

local function flatten(node)
    if not Art.valid(node) then return end
    if FLAT_VEC.x ~= View.FLAT_ROT[1] or FLAT_VEC.y ~= View.FLAT_ROT[2] or FLAT_VEC.z ~= View.FLAT_ROT[3] then
        FLAT_VEC = vec3(View.FLAT_ROT[1], View.FLAT_ROT[2], View.FLAT_ROT[3])
    end
    node:set_rotation(FLAT_VEC)
end

-- Paint a body so a transparent PNG reads correctly and full-bright: drive the
-- texture through the emissive slot (white emissive) + alpha-cut, like the knight
-- hero. Idempotent — safe to call every spawn (incl. reused pooled rigs).
function View.dress_sprite(node, tex)
    if not (Art.valid(node) and material) then return end
    if tex then
        material.set(node, "base_color", vec4(1.0, 1.0, 1.0, 1.0))
        if material.set_texture then
            material.set_texture(node, tex)
            material.set_texture(node, "emissive", tex)
        end
        material.set(node, "emissive", vec3(1.0, 1.0, 1.0))
    end
    if material.set_render_type then material.set_render_type(node, "alpha_cut") end
end

-- Per-spawn hook: dress + flat-lay a flagged creep's body ONCE per underlying rig.
-- Material state + the flat rotation persist on the node across the Duel's rig
-- pooling, so re-dressing on every (re)spawn is wasted work that shows up as spawn
-- spikes; D._topdown_dressed tracks already-dressed bodies and we skip them on reuse.
function View.on_spawn(D, creep)
    local adef = (D.config.archetypes or {})[creep.archetype]
    if not (adef and adef.sprite) then return end
    local body = creep.parts and creep.parts.body
    if not Art.valid(body) then return end
    if Art.valid(creep.root) then
        local cfg = topdown_config(D)
        local mult = number_or(adef.sprite_scale, number_or(cfg.creep_scale, number_or(cfg.sprite_scale, 1.0)))
        -- Rendered width = root creation-frame scale (adef.scale * char *
        -- mult, baked by Duel:dress_creep in the spawn call stack) * authored
        -- body_scale. No scale is written after creation — post-creation
        -- writes don't reliably reach the renderer.
        local rendered = ((adef and adef.scale) or 1.0) * Art.s("char") * mult
        -- Melee contact reach = the rendered sprite's half-width, so the
        -- creep->hero touch matches what's on screen. Ranged stand-off creeps
        -- (anchor_hold/hold_range) keep their authored attack range. 0.35 (not
        -- 0.5) because the sprite PNGs carry transparent padding.
        if not (adef.anchor_hold or adef.hold_range) then
            local bw = (adef.body_scale and adef.body_scale[1]) or 1.0
            creep.stats.range = 0.35 * bw * rendered
        end
        -- No discs for prewarm rigs (created+destroyed immediately), and reuse
        -- parked discs: deleting nodes mid-combat corrupts other nodes' draw
        -- constants (swap-and-pop), so discs are parked far away, never deleted.
        if DEV_HITBOXES and D.groups and D.groups.world and not creep.no_pool then
            local r = creep.stats.range or 0.5
            local pool = D._ring_pool
            if not pool then pool = {}; D._ring_pool = pool end
            local free = pool[r]
            local ring = free and table.remove(free) or nil
            if Art.valid(ring) then
                ring:set_position(vec3(creep.x, HITBOX_Y - 0.1, creep.z))
            else
                ring = make_hitbox_disc("Hitbox_C" .. tostring(creep.id),
                    creep.x, creep.z, r, { 1.0, 0.2, 0.1, 0.45 }, D.groups.world)
            end
            creep._hitbox_ring = ring
            creep._hitbox_ring_r = r
        end
    end
    local dressed = D._topdown_dressed
    if not dressed then dressed = {}; D._topdown_dressed = dressed end
    if dressed[body] then return end
    dressed[body] = true
    View.dress_sprite(body, adef.texture)
    flatten(body)
end

-- Pre-build (and park) creep rigs at start/reset so NONE are created during combat
-- (primitives.* mid-combat stalls the renderer -> frame spikes). Mirrors the
-- Plague-Quarter prewarm fix, but content-side via the Duel's own D:warm_archetype.
-- Modes pass config.prewarm = { <archetype> = count, ... } and set warm_pool_count=0.
function View.prewarm(D)
    local counts = D.config and (D.config.prewarm_counts or D.config.prewarm)
    if not (counts and D.warm_archetype) then return end
    local order = D.config.prewarm_order
    if order then
        for _, arch in ipairs(order) do
            D:warm_archetype(arch, counts[arch] or 0)
        end
        return
    end
    for arch, n in pairs(counts) do
        D:warm_archetype(arch, n)
    end
end

-- Reskin the forced knight into this mode's flat 2D hero. We leave the shared
-- engine untouched, so we repaint the knight's existing body quad and hide its
-- sword + soft cape. Re-applied whenever the hero node changes (e.g. after an
-- R-reset rebuilds it), detected by a root-handle change.
local function skin_hero(D)
    local hero = D.hero
    if not (hero and hero.parts and Art.valid(hero.root)) then return end
    if D._topdown_hero_root == hero.root then return end
    D._topdown_hero_root = hero.root
    local tex = D.config.hero and D.config.hero.sprite_texture
    View.dress_sprite(hero.parts.body, tex)
    local cfg = topdown_config(D)
    local mult = number_or(D.config.hero and D.config.hero.sprite_scale,
        number_or(cfg.hero_scale, number_or(cfg.sprite_scale, 1.0)))
    -- Size + hitbox both derive from base (creation-frame root scale, which is
    -- what actually renders) x the topdown multiplier; the multiplier itself is
    -- applied to the body part every tick in View.tick. The body quad is 1.6
    -- units wide but the PNG has transparent padding around the figure, hence
    -- the 0.55 (≈ visible half-width) rather than 0.8.
    hero.topdown_base_world_scale = hero.topdown_base_world_scale or hero.world_scale or 1.0
    hero.world_scale = hero.topdown_base_world_scale * mult
    hero.body_radius = 0.55 * hero.world_scale
    if pe_log then
        pe_log(string.format("[TOPDOWN] hero base=%.2f mult=%.2f body_radius=%.2f",
            hero.topdown_base_world_scale, mult, hero.body_radius))
    end
    for _, k in ipairs({ "sword", "soft_cape", "aura" }) do
        if Art.valid(hero.parts[k]) then hero.parts[k]:set_scale(vec3(0.0001, 0.0001, 0.0001)) end
    end
end

-- Per combat-tick hook: runs AFTER the Duel's update_hero/update_creeps, so our
-- orientation overrides win. Lays every sprite flat & head-up. NO scale writes
-- here: sprite sizes are baked at rig creation (flat_hero_actor quad dims;
-- Duel:dress_creep root scale) because only creation-frame transforms reliably
-- reach the renderer. Rotations/positions are fine to write per frame.
function View.tick(D)
    skin_hero(D)
    local hero = D.hero
    if hero and hero.parts and not hero.dead and Art.valid(hero.root) then
        hero.root:set_rotation(ZERO_VEC)
        flatten(hero.parts.body)
    end
    if DEV_HITBOXES then View.tick_hitboxes(D) end
end

-- Move the dev hitbox rings to their actors and drop rings of dead creeps.
-- Hero ring is (re)built whenever body_radius changes (R-reset, gear, tuning).
function View.tick_hitboxes(D)
    local hero = D.hero
    if hero and hero.body_radius then
        if D._hero_ring_r ~= hero.body_radius or not Art.valid(D._hero_ring) then
            -- Park the old disc (never delete mid-combat — swap-and-pop).
            if Art.valid(D._hero_ring) then D._hero_ring:set_position(vec3(-10000.0, -10000.0, -10000.0)) end
            D._hero_ring = make_hitbox_disc("Hitbox_Hero", hero.x, hero.z, hero.body_radius,
                { 0.1, 0.9, 1.0, 0.45 }, D.groups and D.groups.world)
            D._hero_ring_r = hero.body_radius
        end
        if Art.valid(D._hero_ring) then D._hero_ring:set_position(vec3(hero.x, HITBOX_Y, hero.z)) end
    end

    local rings = D._creep_rings
    if not rings then rings = {}; D._creep_rings = rings end
    local seen = {}
    for _, c in ipairs(D.creeps or {}) do
        if c.alive and c._hitbox_ring then
            seen[c.id] = true
            rings[c.id] = { ring = c._hitbox_ring, r = c._hitbox_ring_r or 0.5 }
            if Art.valid(c._hitbox_ring) then c._hitbox_ring:set_position(vec3(c.x, HITBOX_Y - 0.1, c.z)) end
        end
    end
    -- Dead creeps: PARK the disc offstage for reuse (never scene.delete_node
    -- mid-combat — swap-and-pop corrupts other nodes' draw constants).
    for id, entry in pairs(rings) do
        if not seen[id] then
            if Art.valid(entry.ring) then
                entry.ring:set_position(vec3(-10000.0, -10000.0, -10000.0))
                local pool = D._ring_pool
                if not pool then pool = {}; D._ring_pool = pool end
                pool[entry.r] = pool[entry.r] or {}
                table.insert(pool[entry.r], entry.ring)
            end
            rings[id] = nil
        end
    end
end

return View
