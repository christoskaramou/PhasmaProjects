-- ath_art — the shared visual toolkit for Against The Hero.
--
-- This is the one place every mode and the menu reach for primitives, actors,
-- textures, and animation. It exists to make the project's #1 content rule true:
-- ADDING A NEW TEXTURE OR ANIMATION IS A DATA EDIT, NEVER A CODE EDIT.
--
--   * Appearance is data. An actor is a flat list of PART specs. Each part is a
--     primitive (cube/sphere/cylinder) with a position/scale/colour and an
--     OPTIONAL `texture = "Objects/foo.png"`. Drop a PNG next to the spec and the
--     part is textured — no new Lua. See Art.build_actor / Art.PART_SPEC.
--   * Animation is data. A clip is a named table of per-part CHANNELS (sine bob,
--     swing, pulse, slide). Adding a walk/cast/idle variation = adding a clip
--     table; Art.animate(actor, "walk", t) plays it. See Art.CLIPS / Art.animate.
--
-- Modes own their content tables (characters, props); this module owns the
-- machinery that turns those tables into nodes and motion. Nothing here knows
-- about gameplay — it is pure presentation, mirroring the discipline in
-- horde/creep.lua and rush/mode.lua (self-lit emissive primitives, because the
-- startup scene's lighting barely reaches a mode's freshly-built stage).

local Art = {}

-- ---------------------------------------------------------------------------
-- Readability scale — the one place to make EVERYTHING bigger.
-- ---------------------------------------------------------------------------
-- `global` multiplies every channel below; tune one channel to grow just that
-- kind. The wiring is automatic where it can be: all runtime_ui text auto-scales
-- (baked into Art.quad), particle bursts scale by `fx`, and the iso camera zooms
-- by `zoom`. UI element *sizes* multiply by these in the menu/HUD via Art.s(...).
--   text — every label/title/subtitle/body/footer font size
--   ui   — menu panels, buttons, card tiles, mode tiles
--   hud  — in-game HUD panels, bars, card hand
--   char — hero + creep world size
--   fx   — particle burst radius/size
--   zoom — camera zoom-in (ortho_size is DIVIDED by this; bigger = closer)
Art.SCALE = {
    global = 1.0,
    text   = 1.85,
    ui     = 1.85,
    hud    = 1.85,
    char   = 1.80,
    fx     = 1.65,
    zoom   = 1.65,
}

-- Resolved scale for a channel (global * channel). Unknown channels return global.
function Art.s(kind)
    local g = Art.SCALE.global or 1.0
    return g * (Art.SCALE[kind] or 1.0)
end

-- ---------------------------------------------------------------------------
-- Letterbox viewport — fixed 20:9 aspect ratio centred on the real surface.
-- ---------------------------------------------------------------------------
Art.TARGET_ASPECT = 20.0 / 9.0
Art._vp = { x = 0, y = 0, w = 2400, h = 1080, rw = 2400, rh = 1080 }

-- ---------------------------------------------------------------------------
-- Node helpers (the cube/sphere/cylinder/group quartet every mode duplicated)
-- ---------------------------------------------------------------------------

function Art.valid(node)
    return node and node:is_valid()
end

function Art.attach(node, parent)
    if Art.valid(node) and Art.valid(parent) then node:set_parent(parent) end
    return node
end

-- Colour a node from a {r,g,b[,a]} table. `emissive` self-lights the part so it
-- reads on the dark stage; default is a dim 0.12 wash like the existing modes.
function Art.tint(node, color, emissive)
    if not Art.valid(node) or not color then return end
    local e = emissive or 0.12
    material.set(node, "base_color", vec4(color[1], color[2], color[3], color[4] or 1.0))
    material.set(node, "emissive", vec3(color[1] * e, color[2] * e, color[3] * e))
    material.set(node, "roughness", color.roughness or 0.85)
    material.set(node, "metallic", color.metallic or 0.0)
end

-- Apply a texture by path. `slot` defaults to base_color/albedo. This is THE
-- "easy textures" hook: any part spec with `texture = "..."` flows through here.
function Art.texture(node, path, slot)
    if not Art.valid(node) or not path or path == "" then return false end
    if not material or not material.set_texture then return false end
    if slot then return material.set_texture(node, slot, path) end
    return material.set_texture(node, path)
end

function Art.group(name, parent)
    local node = scene.add_empty_node(name)
    if not Art.valid(node) then return nil end
    node:set_name(name)
    Art.attach(node, parent)
    return node
end

local function shape_node(kind, spec)
    if kind == "sphere" then return primitives.sphere(0.5) end
    if kind == "cylinder" then return primitives.cylinder(0.5, 1.0) end
    if kind == "quad" then
        local qw = (spec and spec.quad_width) or 1.0
        local qh = (spec and spec.quad_height) or 1.0
        return primitives.quad(qw, qh)
    end
    return primitives.cube(1.0)
end

local function v3(values, fallback)
    values = values or fallback or { 0.0, 0.0, 0.0 }
    if type(values) == "number" then return vec3(values, values, values) end
    if type(values) == "userdata" then
        return vec3(values.x or 0.0, values.y or 0.0, values.z or 0.0)
    end
    return vec3(values.x or values[1] or 0.0, values.y or values[2] or 0.0, values.z or values[3] or 0.0)
end
Art.v3 = v3

-- Build ONE part from a spec and parent it. Spec fields (all optional except a
-- shape is implied by `kind`):
--   name, kind = "cube"|"sphere"|"cylinder",
--   position = {x,y,z}, scale = {x,y,z}, rotation = {pitch,yaw,roll} (degrees),
--   color = {r,g,b[,a]}, emissive = <number>, texture = "Path/to.png",
--   texture_slot = "base_color"|"normal"|...,
function Art.part(spec, parent)
    spec = spec or {}
    local node = shape_node(spec.kind, spec)
    if not Art.valid(node) then
        node = primitives.cube(1.0)
        if not Art.valid(node) then return nil end
    end
    node:set_name(spec.name or "Part")
    Art.attach(node, parent)
    node:set_position(v3(spec.position, { 0.0, 0.0, 0.0 }))
    node:set_scale(v3(spec.scale, { 1.0, 1.0, 1.0 }))
    if spec.rotation then node:set_rotation(v3(spec.rotation)) end
    Art.tint(node, spec.color or { 0.8, 0.8, 0.8 }, spec.emissive)
    if spec.texture then
        Art.texture(node, spec.texture, spec.texture_slot)
        if spec.kind == "quad" and material then
            -- alpha_cut (cutout) reads texture alpha reliably; alpha_blend was
            -- rendering the whole quad transparent on this deferred path.
            if spec.alpha_blend ~= false and material.set_render_type then
                material.set_render_type(node, spec.render_type or "alpha_cut")
            end
            -- Flat 2D sprite: drive the texture through the emissive slot too so the
            -- art reads at face value regardless of the stage lighting (dark armour
            -- would otherwise vanish). emissive factor is forced to white.
            if spec.emissive_texture and material.set_texture then
                material.set_texture(node, "emissive", spec.texture)
                material.set(node, "emissive", vec3(1.0, 1.0, 1.0))
            end
        end
    end
    return node
end

-- Convenience wrappers matching the (name,pos,scale,color,parent,emissive)
-- signature used throughout the existing modes, so a mode can drop ATH_COMMON
-- helpers and use these without rewriting call sites.
function Art.cube(name, pos, scale, color, parent, emissive, texture)
    return Art.part({ name = name, kind = "cube", position = pos, scale = scale, color = color, emissive = emissive, texture = texture }, parent)
end
function Art.sphere(name, pos, scale, color, parent, emissive, texture)
    return Art.part({ name = name, kind = "sphere", position = pos, scale = scale, color = color, emissive = emissive, texture = texture }, parent)
end
function Art.cylinder(name, pos, scale, color, parent, emissive, texture)
    return Art.part({ name = name, kind = "cylinder", position = pos, scale = scale, color = color, emissive = emissive, texture = texture }, parent)
end

-- ---------------------------------------------------------------------------
-- Actors — a named root + a part table built from a data spec.
-- ---------------------------------------------------------------------------

-- Build an actor from a spec:
--   { name = "Hero", scale = 1.0,
--     parts = { body = {<PART_SPEC>}, head = {...}, sword = {...}, ... } }
-- Returns { root, parts = { name -> node }, spec }. `parts` is keyed by the spec
-- key so animation clips can address channels by name (parts.body, parts.head).
function Art.build_actor(spec, parent)
    spec = spec or {}
    local actor = { spec = spec, parts = {}, base = {} }
    actor.root = Art.group(spec.name or "Actor", parent)
    for key, part_spec in pairs(spec.parts or {}) do
        local part_named = {}
        for k, v in pairs(part_spec) do part_named[k] = v end
        part_named.name = part_named.name or key
        local node = Art.part(part_named, actor.root)
        actor.parts[key] = node
        -- Remember each part's rest pose so animation channels add ON TOP of it
        -- (clips express deltas, not absolutes — see Art.animate).
        actor.base[key] = {
            position = part_spec.position or { 0.0, 0.0, 0.0 },
            scale = part_spec.scale or { 1.0, 1.0, 1.0 },
            rotation = part_spec.rotation or { 0.0, 0.0, 0.0 },
        }
    end
    if Art.valid(actor.root) and spec.scale then
        actor.root:set_scale(vec3(spec.scale, spec.scale, spec.scale))
    end
    return actor
end

-- Build an actor that includes a skinned_strip_2d soft cape.
-- spec.soft_cape = { width, height, segments, bones, texture, rotation }
-- The strip is parented to the actor root and stored in actor.parts.soft_cape.
function Art.build_soft_actor(spec, parent)
    local actor = Art.build_actor(spec, parent)
    local sc = spec.soft_cape
    if sc and primitives and primitives.skinned_strip_2d and animation then
        local w  = sc.width    or 2.0
        local h  = sc.height   or 1.2
        local sg = sc.segments or 48
        local bn = sc.bones    or 20
        local strip = primitives.skinned_strip_2d(w, h, sg, bn)
        if Art.valid(strip) then
            strip:set_name("Soft_Cape")
            Art.attach(strip, actor.root)
            local pos = sc.position or { 0.0, 0.0, 0.0 }
            local rot = sc.rotation or { 0.0, 0.0, -90.0 }
            strip:set_position(v3(pos))
            strip:set_rotation(v3(rot))
            if sc.scale then strip:set_scale(v3(sc.scale)) end
            if sc.texture and material then
                material.set(strip, "base_color", vec4(1.0, 1.0, 1.0, 1.0))
                material.set_texture(strip, "base_color", sc.texture)
                if material.set_texture then
                    material.set_texture(strip, "emissive", sc.texture)
                    material.set(strip, "emissive", vec3(1.0, 1.0, 1.0))
                end
                if material.set_render_type then material.set_render_type(strip, sc.render_type or "alpha_cut") end
            end
            if sc.color then Art.tint(strip, sc.color, sc.emissive or 0.12) end
            actor.parts.soft_cape = strip
            actor.soft_cape_cfg = sc
        end
    end
    return actor
end

-- Drive the soft cape wave each frame. Call from the hero update loop.
-- t = elapsed time, cfg = actor.soft_cape_cfg (optional override of wave params).
function Art.animate_soft_cape(actor, t, cfg)
    if not actor or not actor.parts or not Art.valid(actor.parts.soft_cape) then return end
    if not animation or not animation.get_joint_count or not animation.set_joint_rotations_z then return end
    cfg = cfg or actor.soft_cape_cfg or {}
    local strip = actor.parts.soft_cape
    local jc = animation.get_joint_count(strip)
    if jc <= 0 then return end
    local speed = cfg.wave_speed or 2.5
    local phase = cfg.wave_phase or 3.0
    local amp   = cfg.wave_amp_deg or 10.0
    local rotations = {}
    for i = 1, jc do
        local u = (i - 1) / math.max(jc - 1, 1)
        rotations[i] = math.sin(t * speed + u * phase) * math.rad(amp) * u
    end
    animation.set_joint_rotations_z(strip, rotations)
end

-- Attach EXTRA decorative parts (and per-part textures) to any existing root —
-- e.g. to decorate a horde/creep.lua creep with a mode's signature silhouette
-- without editing creep.lua. `extras` is a list of PART specs.
function Art.decorate(root, extras)
    if not Art.valid(root) or not extras then return {} end
    local added = {}
    for i, part_spec in ipairs(extras) do
        local node = Art.part(part_spec, root)
        added[part_spec.name or ("extra_" .. i)] = node
    end
    return added
end

function Art.destroy_actor(actor)
    if actor and Art.valid(actor.root) then scene.delete_node(actor.root) end
    if actor then actor.parts = {} end
end

-- ---------------------------------------------------------------------------
-- Animation — named procedural clips driven by a single phase `t` (seconds).
--
-- A clip is a list of CHANNELS. Each channel targets one part and one transform
-- field, and is a simple oscillator:
--   { part = "hand_r", field = "position", axis = "y",
--     mode = "sin"|"cos"|"abs_sin"|"saw"|"const",
--     amp = 0.05, freq = 9.0, phase = 0.0, mul = nil }
-- `field` is "position" | "rotation" | "scale"; the result is ADDED to the part's
-- rest pose (multiplied, for scale). This keeps clips composable and lets a new
-- gait/cast/idle be expressed as pure data. Adding a clip = adding a table here
-- or passing one to Art.animate.
-- ---------------------------------------------------------------------------

local function osc(mode, x)
    if mode == "cos" then return math.cos(x) end
    if mode == "abs_sin" then return math.abs(math.sin(x)) end
    if mode == "saw" then return (x / (2.0 * math.pi)) % 1.0 end
    if mode == "const" then return 1.0 end
    return math.sin(x)
end

local AXIS_INDEX = { x = 1, y = 2, z = 3 }

-- Built-in clips. Modes may pass their own clip tables to Art.animate, but these
-- cover the common gaits so most actors animate with one call.
Art.CLIPS = {
    idle = {
        { part = "body", field = "position", axis = "y", mode = "sin", amp = 0.02, freq = 2.2 },
        { part = "head", field = "position", axis = "y", mode = "sin", amp = 0.015, freq = 2.2, phase = 0.4 },
    },
    walk = {
        { part = "body", field = "position", axis = "y", mode = "abs_sin", amp = 0.05, freq = 9.0 },
        { part = "hand_r", field = "position", axis = "z", mode = "sin", amp = 0.10, freq = 9.0 },
        { part = "hand_l", field = "position", axis = "z", mode = "sin", amp = 0.10, freq = 9.0, phase = 3.14159 },
        { part = "foot_r", field = "position", axis = "z", mode = "sin", amp = 0.16, freq = 9.0 },
        { part = "foot_l", field = "position", axis = "z", mode = "sin", amp = 0.16, freq = 9.0, phase = 3.14159 },
    },
    attack = {
        { part = "sword", field = "rotation", axis = "x", mode = "sin", amp = 70.0, freq = 16.0 },
        { part = "hand_r", field = "position", axis = "y", mode = "sin", amp = 0.08, freq = 16.0 },
    },
    cast = {
        { part = "weapon", field = "position", axis = "y", mode = "sin", amp = 0.06, freq = 5.0 },
        { part = "head", field = "rotation", axis = "y", mode = "sin", amp = 8.0, freq = 3.0 },
    },
}

-- Apply a clip to an actor at phase `t`. `clip` may be a clip name (looked up in
-- Art.CLIPS or in opts.clips) or a clip table. `weight` (0..1) scales amplitude
-- so a mode can blend in an attack flash over a walk. Channels add to rest pose.
function Art.animate(actor, clip, t, opts)
    if not actor or not actor.parts then return end
    opts = opts or {}
    if type(clip) == "string" then
        clip = (opts.clips and opts.clips[clip]) or Art.CLIPS[clip]
    end
    if type(clip) ~= "table" then return end
    local weight = opts.weight or 1.0

    -- Accumulate per-part deltas, then write each touched part once.
    local acc = {}
    for _, ch in ipairs(clip) do
        local node = actor.parts[ch.part]
        local base = actor.base[ch.part]
        if Art.valid(node) and base then
            local entry = acc[ch.part]
            if not entry then
                entry = {
                    position = { base.position[1] or 0.0, base.position[2] or 0.0, base.position[3] or 0.0 },
                    rotation = { base.rotation[1] or 0.0, base.rotation[2] or 0.0, base.rotation[3] or 0.0 },
                    scale = { base.scale[1] or 1.0, base.scale[2] or 1.0, base.scale[3] or 1.0 },
                    touched = {},
                }
                acc[ch.part] = entry
            end
            local idx = AXIS_INDEX[ch.axis or "y"] or 2
            local value = osc(ch.mode, (t or 0.0) * (ch.freq or 1.0) + (ch.phase or 0.0)) * (ch.amp or 0.0) * weight
            if ch.field == "scale" then
                entry.scale[idx] = entry.scale[idx] * (1.0 + value)
            elseif ch.field == "rotation" then
                entry.rotation[idx] = entry.rotation[idx] + value
            else
                entry.position[idx] = entry.position[idx] + value
            end
            entry.touched[ch.field or "position"] = true
        end
    end

    for part, entry in pairs(acc) do
        local node = actor.parts[part]
        if Art.valid(node) then
            if entry.touched.position then node:set_position(vec3(entry.position[1], entry.position[2], entry.position[3])) end
            if entry.touched.rotation then node:set_rotation(vec3(entry.rotation[1], entry.rotation[2], entry.rotation[3])) end
            if entry.touched.scale then node:set_scale(vec3(entry.scale[1], entry.scale[2], entry.scale[3])) end
        end
    end
end

-- Skeletal/imported-clip passthrough for actors that DO carry glTF clips. Most
-- ATH actors are primitive rigs (use Art.animate), but this keeps the door open.
function Art.play_clip(node, clip_name, loop)
    if Art.valid(node) and animation and animation.play then
        animation.play(node, clip_name, loop ~= false)
    end
end

-- ---------------------------------------------------------------------------
-- Particles — one tiny wrapper so every mode emits bursts the same way.
-- ---------------------------------------------------------------------------

function Art.burst(name, position, opts)
    if not (particles and particles.emit_burst) then return end
    opts = opts or {}
    particles.emit_burst({
        preset = opts.preset or "enemy_take",
        name = name,
        position = position,
        count = opts.count or 12,
        life_min = opts.life_min or 0.08,
        life_max = opts.life_max or 0.22,
        -- Bursts grow with the world so effects stay visible at the larger scale.
        spawn_radius = (opts.spawn_radius or 0.18) * Art.s("fx"),
        noise_strength = opts.noise_strength or 3.0,
        size_max = (opts.size_max or 0.16) * Art.s("fx"),
    })
end

-- ---------------------------------------------------------------------------
-- Camera — the fixed orthographic iso rig every mode uses (rush conventions).
-- ---------------------------------------------------------------------------

-- center = {x,z} world look point. opts: ortho_size, offset = {x,y,z}, near, far.
-- REUSES the scene's existing active camera (the renderer keeps drawing through
-- it) and reconfigures it to an orthographic iso rig — the proven horde pattern.
-- Adding a brand-new camera + set_active does NOT swap the render camera mid-run,
-- which left modes rendering through the scene's default perspective camera.
function Art.setup_iso_camera(center, opts)
    opts = opts or {}
    local cam = (get_camera and get_camera()) or nil
    if not cam and scene.add_camera then
        cam = scene.add_camera()
        if cam and scene.set_active_camera then scene.set_active_camera(cam) end
    end
    if not cam then return nil end
    if cam.set_projection_mode then cam:set_projection_mode("orthographic") end
    -- Divide by the zoom channel so the whole stage (map + characters) reads bigger.
    -- The 20:9 letterbox bars cover part of the 3D render too, so scale by the
    -- surface/band height ratio: opts.ortho_size means "world height visible in
    -- the LETTERBOXED band", not in the full (partly hidden) surface.
    Art.surface_size() -- refresh Art._vp
    local vp = Art._vp
    local crop = (vp.h and vp.h > 0) and (vp.rh / vp.h) or 1.0
    local ortho = (opts.ortho_size or 34.0) / Art.s("zoom") * crop
    if cam.set_orthographic_size then cam:set_orthographic_size(ortho) end
    if pe_log then
        pe_log(string.format("[ISO_CAM] surface=%dx%d band=%dx%d crop=%.3f requested=%.1f final_ortho=%.1f",
            vp.rw, vp.rh, vp.w, vp.h, crop, opts.ortho_size or 34.0, ortho))
    end
    if cam.set_near then cam:set_near(opts.near or 0.1) end
    if cam.set_far then cam:set_far(opts.far or 640.0) end
    local off = opts.offset or { x = -44.0, y = 44.0, z = 44.0 }
    local cx, cz = center.x or 0.0, center.z or 0.0
    cam:set_position(vec3(cx + off.x, off.y, cz + off.z))
    if cam.look_at then cam:look_at(vec3(cx, 0.0, cz)) end
    -- Remember the rig so Art.tick_iso_camera can RE-ASSERT it every frame:
    -- a one-shot setup races with the startup scene's own camera activation
    -- (the view sometimes renders with the scene camera's saved ortho instead).
    Art._iso = { ortho = ortho, cx = cx, cz = cz, off = off }
    return cam
end

-- Re-assert the iso camera every frame (cheap setters). Fixes runs where the
-- startup scene's camera state lands AFTER the one-shot setup and the view
-- renders massively zoomed-in.
function Art.tick_iso_camera()
    local iso = Art._iso
    if not iso then return end
    local cam = (get_camera and get_camera()) or nil
    if not cam then return end
    if cam.set_projection_mode then cam:set_projection_mode("orthographic") end
    if cam.set_orthographic_size then cam:set_orthographic_size(iso.ortho) end
    cam:set_position(vec3(iso.cx + iso.off.x, iso.off.y, iso.cz + iso.off.z))
    if cam.look_at then cam:look_at(vec3(iso.cx, 0.0, iso.cz)) end
end

-- Configure the render stage the way the duel modes expect (mirrors horde): grid
-- and debug overlays off, day/IBL lighting on, no TAA/bloom motion-blur, plus one
-- directional light so non-emissive geometry still reads. Safe no-ops if the
-- settings/lights bridges are unavailable.
function Art.setup_stage(opts)
    opts = opts or {}
    if settings and settings.set then
        settings.set("draw_grid", false)
        settings.set("draw_aabbs", false)
        settings.set("shadows", opts.shadows == true)
        settings.set("ssao", false)
        settings.set("day", true)
        settings.set("IBL", true)
        settings.set("IBL_intensity", opts.ibl or 0.6)
        settings.set("lights_intensity", opts.lights or 2.4)
        settings.set("tonemapping", false)
        settings.set("motion_blur", false)
        settings.set("bloom", false)
        settings.set("taa", false)
        settings.set("fxaa", true)
    end
    if lights and lights.get_counts and lights.add_directional then
        local counts = lights.get_counts()
        if not counts or (counts.directional or 0) == 0 then lights.add_directional() end
    end
    if lights and lights.set_directional_light then
        lights.set_directional_light(0, vec3(-1.5, 7.0, -1.0), vec3(0.92, 0.90, 0.84), 2.6)
    end
end

-- ---------------------------------------------------------------------------
-- HUD widgets — thin helpers over runtime_ui so every mode/menu draws panels
-- and bars identically. `screen` is the runtime_ui screen id.
-- ---------------------------------------------------------------------------

-- The bundled font is ASCII-only, so common typographic glyphs render as "?".
-- Map them to ASCII centrally — every label in the game (menus, HUD, and every
-- mode's win/lose text) is covered without touching a single call site.
local GLYPHS = {
    ["—"] = "-", ["–"] = "-", ["•"] = "-", ["·"] = "-", ["…"] = "...",
    ["▶"] = ">", ["◀"] = "<", ["▲"] = "^", ["▼"] = "v", ["→"] = "->", ["←"] = "<-",
    ["★"] = "*", ["☆"] = "*", ["“"] = '"', ["”"] = '"', ["‘"] = "'", ["’"] = "'",
}
function Art.ascii(text)
    if type(text) ~= "string" then return text end
    for from, to in pairs(GLYPHS) do text = text:gsub(from, to) end
    return text
end

function Art.surface_size()
    local rw, rh
    if runtime_ui and runtime_ui.get_surface_size then
        local s = runtime_ui.get_surface_size()
        if s and s.width and s.width > 0 then rw, rh = s.width, s.height end
    end
    rw = rw or 2400.0
    rh = rh or 1080.0
    local target = Art.TARGET_ASPECT
    local vw, vh, vx, vy
    if rw / rh > target then
        vh = rh
        vw = math.floor(rh * target)
        vx = math.floor((rw - vw) * 0.5)
        vy = 0
    else
        vw = rw
        vh = math.floor(rw / target)
        vx = 0
        vy = math.floor((rh - vh) * 0.5)
    end
    Art._vp = { x = vx, y = vy, w = vw, h = vh, rw = rw, rh = rh }
    return vw, vh
end

-- A panel/quad. opts mirrors runtime_ui.set_quad fields plus convenient names.
function Art.quad(screen, id, x, y, w, h, fill, opts)
    if not (runtime_ui and runtime_ui.set_quad) then return end
    opts = opts or {}
    local vp = Art._vp
    runtime_ui.set_quad(screen, id, {
        x = x + vp.x, y = y + vp.y, width = w, height = h,
        label = Art.ascii(opts.label or ""), title = Art.ascii(opts.title or ""), subtitle = Art.ascii(opts.subtitle or ""),
        body = Art.ascii(opts.body or ""), footer = Art.ascii(opts.footer or ""),
        fill = fill or { 0.0, 0.0, 0.0, 0.0 },
        border = opts.border or { 0.0, 0.0, 0.0, 0.0 },
        accent = opts.accent or { 0.0, 0.0, 0.0, 0.0 },
        text_color = opts.text_color or { 0.92, 0.94, 0.98, 1.0 },
        image = opts.image, image_tint = opts.image_tint,
        -- All UI text auto-scales: a caller's font_scale is RELATIVE to the global
        -- text scale, so bumping Art.SCALE.text grows every label everywhere.
        font_scale = (opts.font_scale or 1.0) * Art.s("text"), selected = opts.selected,
        draggable = opts.draggable, bring_to_front = opts.bring_to_front,
        -- no_input: a decorative/background quad that must NOT capture clicks or be
        -- raised over the UI (prevents the "click empty space -> black screen" bug).
        no_input = opts.no_input,
    })
end

-- A horizontal value bar (background + coloured fill + label above).
function Art.bar(screen, id, x, y, w, h, pct, color, opts)
    opts = opts or {}
    pct = math.max(0.0, math.min(1.0, pct or 0.0))
    Art.quad(screen, id .. "_bg", x, y, w, h, { 0.05, 0.05, 0.06, 0.85 }, { border = opts.border or { 0.2, 0.2, 0.24, 0.95 }, no_input = true })
    Art.quad(screen, id .. "_fg", x, y, w * pct, h, color or { 0.36, 0.78, 0.42, 0.95 }, { no_input = true })
    if opts.label then
        -- The backend top-anchors a quad's label at (top + 15*scale). Shift the
        -- label quad up so the text lands vertically CENTRED on the bar.
        local ts = Art.s("text")
        local ly = y + h * 0.5 - ts * 21.0
        Art.quad(screen, id .. "_label", x, ly, w, h, { 0.0, 0.0, 0.0, 0.0 },
            { label = opts.label, text_color = opts.text_color or { 0.98, 0.98, 1.0, 1.0 }, no_input = true })
    end
end

-- Read a widget's interaction state (hover/click). Returns nil if unavailable.
function Art.widget_state(screen, id)
    if runtime_ui and runtime_ui.get_state then return runtime_ui.get_state(screen, id) end
    return nil
end

-- Was this quad clicked this frame? NOTE: runtime_ui.consume_click only works for
-- BUTTON widgets (it ignores quads), so we read the per-quad interaction state,
-- where `clicked` IS populated for quads (RuntimeUi stores backend->Quad() state).
function Art.consume_click(screen, id)
    local st = Art.widget_state(screen, id)
    return (st and st.clicked) == true
end

function Art.remove(screen, id)
    if runtime_ui and runtime_ui.remove then runtime_ui.remove(screen, id) end
end

function Art.remove_ids(screen, ids)
    for _, id in ipairs(ids or {}) do Art.remove(screen, id) end
end

-- Draw black letterbox bars. Routes through Art.quad() (which adds the viewport
-- offset), so we pass COMPENSATED coordinates that cancel the offset out and land
-- at the raw surface edges. Call on an always-on-top screen (e.g. the HUD).
function Art.draw_letterbox(screen)
    local vp = Art._vp
    local black = { 0.0, 0.0, 0.0, 1.0 }
    if vp.y > 0 then
        Art.quad(screen, "lb_t", -vp.x, -vp.y, vp.rw, vp.y, black, { no_input = true })
        Art.quad(screen, "lb_b", -vp.x, vp.h, vp.rw, vp.rh - vp.y - vp.h, black, { no_input = true })
    else
        Art.remove(screen, "lb_t"); Art.remove(screen, "lb_b")
    end
    if vp.x > 0 then
        Art.quad(screen, "lb_l", -vp.x, -vp.y, vp.x, vp.rh, black, { no_input = true })
        Art.quad(screen, "lb_r", vp.w, -vp.y, vp.rw - vp.x - vp.w, vp.rh, black, { no_input = true })
    else
        Art.remove(screen, "lb_l"); Art.remove(screen, "lb_r")
    end
end

return Art
