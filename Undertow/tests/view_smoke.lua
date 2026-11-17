-- luajit tests/view_smoke.lua   (run from the Undertow folder)
-- Boots the real scripts (undertow.lua, the world, the sea and the course) against stubbed engine APIs and checks:
--   1. the Lua sea height matches heights sampled from tools/uw_common.py (tests/sea_samples.lua),
--   2. the pooled set pieces, sea tiles and far cards do not leak while the pendulum scrolls 2,000 units,
--   3. every chain link drawn lies on the line from the hook to the float (state A, state B and while swinging).
local io_open = io.open
local function read(path)
    if path:match("^Save/") then return nil end
    local f = io_open("Assets/" .. path, "rb"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local env = _G
env.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end

-- nodes remember their transform so the test can read what the world drew
local nodes_made = 0
local Node = {}
Node.__index = function(t, k)
    if k == "set_position" then return function(self, p) self.pos = { p.x, p.y, p.z } end end
    if k == "set_enabled" then return function(self, on) self.on = on end end
    if k == "get_mesh_refs" then return function() return { 1 } end end
    if k == "set_scale" then return function(self, s) self.scale = { s.x, s.y, s.z } end end
    return function() end
end
local function node(name) nodes_made = nodes_made + 1; return setmetatable({ name = name, on = true }, Node) end
local cam = setmetatable({}, { __index = function() return function() end end })
env.scene = setmetatable({
    add_empty_node = function(name) return node(name) end,
    get_active_camera = function() return cam end,
    find_model = function(name) return setmetatable({ name = name }, Node) end,
    set_positions = function(t, n)
        for i = 0, n - 1 do t[i * 4 + 1].pos = { t[i * 4 + 2], t[i * 4 + 3], t[i * 4 + 4] } end
    end,
    set_rotations = function(t, n)
        for i = 0, n - 1 do t[i * 4 + 1].rot = { t[i * 4 + 2], t[i * 4 + 3], t[i * 4 + 4] } end
    end,
}, { __index = function() return function() end end })
env.material = setmetatable({}, { __index = function() return function() return true end end })
local n_emit = 0
env.particles = setmetatable({ add_emitter = function() n_emit = n_emit + 1; return n_emit - 1 end, load_texture = function() return 0 end },
    { __index = function() return function() return 0 end end })
local plights = {}
env.lights = setmetatable({
    add_point = function() plights[#plights + 1] = { name = "PointLight_" .. #plights } end,
    get_point_lights = function() return plights end,
}, { __index = function() return function() end end })
env.skybox = { load = function() end }
env.fs = { read = read, write = function() return true end, exists = function() return false end }
MUSIC = {}
env.audio = setmetatable({ play_music = function(f) MUSIC[#MUSIC + 1] = f end }, { __index = function() return function() end end })
SLOW_MS = nil       -- a test sets it to play slow engine frames (the game clamps its step to 50 ms)
env.engine = setmetatable({ get_metrics = function() return { delta_ms = SLOW_MS or 1000 / 60 } end }, { __index = function() return function() end end })
env.runtime_ui = setmetatable({ get_surface_size = function() return { width = 2560, height = 1369 } end },
    { __index = function() return function() end end })
local render_mode
env.settings = { get = function() return nil end, set = function() end, set_render_mode = function(m) render_mode = m end }
local update
env.script = { on_update = function(_, f) update = f end }
env.os, env.io = nil, nil
assert(load(assert(read("Scripts/undertow.lua")), "@undertow.lua", "t", env))()
local U = env.undertow
local W, D, Sea, Course = U.W, U.D, U.Sea, U.Course
local function frames(n) for _ = 1, n do update() end end
local fails = 0
local function check(ok, msg)
    if ok then print("ok   " .. msg) else print("FAIL " .. msg); fails = fails + 1 end
end

frames(3)
check(render_mode == "raster", "the world asks for raster")

-- 1. sea height parity with Python
do
    local samples = assert(load(io_open("tests/sea_samples.lua"):read("*a")))()
    local worst = 0
    for _, s in ipairs(samples) do
        worst = math.max(worst, math.abs(Sea.height(s[1], s[2], s[3]) - s[4]))
    end
    check(worst < 1e-5, string.format("sea_height matches %d Python samples (worst %.2e)", #samples, worst))
end

-- 3b. the chain reads at 1280x720 (found in play frames: the 0.05 / 0.013 links vanished): a link is at least 8 px
-- across and its wire 2 px thick where state A hangs (11.5 from the camera), and links overlap along the chain
do
    local r, w, step = D.CHAIN_LINK[1], D.CHAIN_LINK[2], D.CHAIN_LINK[3]
    local px = 11.5 * 2 * math.tan(math.rad(D.CAM.fovx / 2)) / 1280
    local across, wire = 2 * (r * 0.6 + w) / px, 2 * w / px
    check(across >= 8 and wire >= 2 and step < 2 * (r + w), string.format("the chain reads at 1280x720: links %.1f px across, wire %.1f px, step %.3f < link %.3f",
        across, wire, step, 2 * (r + w)))
end
-- 3a. chain links on the hook-float line, in both reference states
local function chain_on_line(label)
    local ch = W.chain
    if not ch then check(false, label .. ": no chain drawn"); return end
    local ax, ay, bx, by = ch.ax, ch.az, ch.bx, ch.bz       -- Blender x, z of the chain's ends
    local worst, outside = 0, 0
    local dx, dy = bx - ax, by - ay
    local L = math.sqrt(dx * dx + dy * dy)
    for i = 1, W.links_used do
        local p = W.links[i].pos                              -- engine (x, y, z) = Blender (x, z, -y)
        local px, py, pz = p[1], p[2], -p[3]
        local d = math.abs((px - ax) * dy - (py - ay) * dx) / L
        local u = ((px - ax) * dx + (py - ay) * dy) / (L * L)
        worst = math.max(worst, d, math.abs(pz - ch.y))
        if u < -1e-6 or u > 1 + 1e-6 then outside = outside + 1 end
    end
    -- the chain's ends: at the hook and at the float's top
    local F, H = U.S.F, U.S.H
    local top = math.sqrt((bx - F.x) ^ 2 + (by - F.z) ^ 2)
    local ok = W.links_used > 20 and worst < 1e-4 and outside == 0 and math.abs(ax - H.x) < 1e-6 and math.abs(ay - H.z) < 0.15
        and math.abs(top - (D.FLOAT_R + 0.06)) < 1e-6
    check(ok, string.format("%s: %d links on the hook-float line (worst off-line %.1e, outside %d)", label, W.links_used, worst, outside))
end
U.state("A"); frames(2); chain_on_line("state A")
do   -- a held state follows its buoy's bob when the sea runs: the chain still starts at the drawn hook
    U.S.t = U.S.t + 1.3
    frames(2)
    chain_on_line("state A, sea +1.3 s")
    local cur
    for _, c in pairs(W.ITEM) do if c.it == U.S.hook_item then cur = c end end
    local p = cur.node.pos
    local hx, _, hz = Course.tilt(D.ARM_FWD, -D.BUOY_BACK, D.HOOK_Z_BUOY, D.BUOY_TILT[2])
    check(math.abs(p[1] + hx - W.chain.ax) < 1e-4 and math.abs(p[2] + hz - W.chain.az) < 1e-4, "the chain follows the bobbing hook")
end
U.state("B"); frames(2); chain_on_line("state B")
do   -- state B (the coordinator saw two buoys numbered 4 here)
    plate_seen, plate_bad, plate_msg = 0, 0, ""
    local nums = {}
    for _, c in pairs(W.ITEM) do if c.it.no then nums[#nums + 1] = c.it.no end end
    table.sort(nums)
    local dup = false
    for i = 2, #nums do if nums[i] == nums[i - 1] then dup = true end end
    check(not dup and #nums >= 3, "state B: buoy numbers in view are distinct (" .. table.concat(nums, ",") .. ")")
end

-- 2. no leaks over a 2,000-unit scroll with the pendulum running
U.state("A"); frames(2)
local made0 = W.created
U.run(12)
local x0, maxused, steps, swings = U.S.cx, {}, 0, 0
local last_hook
local plate_bad, plate_seen, plate_msg = 0, 0, ""
local function plates_ok()
    -- every buoy in view carries its own course number as a decal at the buoy's pose, no number twice
    local seen = {}
    for _, c in pairs(W.ITEM) do
        local it = c.it
        if it.kind == "buoy_red" or it.kind == "buoy_white" then
            plate_seen = plate_seen + 1
            local want = string.format("plate_%02d", it.no or -1)
            local p, q = c.plate and c.plate.pos, c.node.pos
            if seen[it.no] or c.plate_pool ~= want or not p or not q or math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]) + math.abs(p[3] - q[3]) > 1e-9
                or (it.kind == "buoy_red") ~= (it.no % 2 == 0) then
                plate_bad = plate_bad + 1
                plate_msg = string.format("number %s at x %.1f", tostring(it.no), it.x)
            end
            seen[it.no] = true
        end
    end
end
while U.S.cx < x0 + 2000 and steps < 60 * 600 do
    update()
    steps = steps + 1
    if steps % 10 == 0 then plates_ok() end
    for k, v in pairs(W.pool_counts()) do maxused[k] = math.max(maxused[k] or 0, v.used) end
    if U.S.H and W.chain and swings < 4 and steps % 30 == 0 then
        chain_on_line("swinging at x " .. math.floor(U.S.F.x))
        swings = swings + 1
    end
end
check(U.S.cx >= x0 + 2000, string.format("the camera scrolled 2,000 units (%.0f in %d frames)", U.S.cx - x0, steps))
check(W.created == made0, string.format("no nodes made after init (%d before, %d after)", made0, W.created))
local sb = {}
for k, v in pairs(W.starved_by or {}) do sb[#sb + 1] = k .. "=" .. v end
check((W.starved or 0) == 0, "no pool ran dry (" .. tostring(W.starved or 0) .. " " .. table.concat(sb, ",") .. ")")
local over = {}
for k, v in pairs(W.pool_counts()) do
    if v.used + v.free ~= v.size then over[#over + 1] = k end
end
check(#over == 0, "every pooled node is accounted for (used + free = size) " .. table.concat(over, ","))
check(plate_bad == 0 and plate_seen > 500, string.format("buoy numbers: each buoy in view shows its own number, none twice (%d checked, %d bad %s)", plate_seen, plate_bad, plate_msg))
check(#U.course().items < 200, "the course forgets what is behind the camera (" .. #U.course().items .. " items)")
-- 4. after the long scroll the reference states still pose exactly (the course behind the camera was pruned)
do
    local ok, msg = pcall(U.state, "A")
    frames(2)
    local F = U.S.F
    local okA = ok and math.abs(F.x - 0.6690729526542281) < 1e-6 and math.abs(F.z - 0.9116786399830659) < 1e-6      -- (uw_common.float_pos("A"), printed by gen_assets)
    local lit = 0
    for _, it in ipairs(U.course().items) do if it.lit and it.kind == "buoy_red" and it.p.y == nil then lit = lit + 1 end end
    check(okA and lit == 1 and (W.starved or 0) == 0, "state A poses exactly after the scroll (" .. tostring(msg) .. ", lit red buoys " .. lit .. ")")
    check(W.created == made0, "still no nodes made after the state reset")
    -- the hook as drawn (the buoy node's position, scale and tilt applied to the cooked mesh's hook point) is where
    -- the chain starts
    local cur
    for _, c in pairs(W.ITEM) do if c.it == U.S.hook_item then cur = c end end
    local n = cur and cur.node
    local sc = n and n.scale and n.scale[1] or 1
    local hx, hy, hz = Course.tilt(D.ARM_FWD * sc, -D.BUOY_BACK * sc, D.HOOK_Z_BUOY * sc, D.BUOY_TILT[2])
    local p = n and n.pos or { 0, 0, 0 }
    local dx, dz = p[1] + hx - U.S.H.x, p[2] + hz - U.S.H.z
    check(n ~= nil and math.abs(dx) < 1e-4 and math.abs(dz) < 1e-4,
        string.format("the drawn hook meets the chain after recycling (off by %.3f, %.3f; scale %.2f)", dx, dz, sc))
end
-- 5. play: the rules drive the float through the real world script; every hazard the world draws stands exactly where
-- the rules' hit shape is (node transform == rules placement; mesh probes moved by the drawn transform are hits)
do
    local R = U.Rules
    U.play(5)
    local made1 = W.created
    local seen, bad, probes_ok, probes_n, msg = {}, 0, 0, 0, ""
    local kinds = {}
    local frames_n = 0
    -- the float stays inside the frame (found live at level 5: long releases left the top of the frame): its top
    -- below the top edge at 2560x1369, from the camera the world places (x = cx, y = CAM.y, z = cz, yaw, pitch)
    local C = D.CAM
    local cy, sy, cp, sp = math.cos(math.rad(C.yaw)), math.sin(math.rad(C.yaw)), math.cos(math.rad(C.pitch)), math.sin(math.rad(C.pitch))
    local tv = math.tan(math.rad(C.fovx / 2)) * 1369 / 2560
    local worst_top, out_top, peak_z = -9, 0, 0
    local mist_run, mist_worst, skims_seen = 0, 0, 0
    while frames_n < 60 * 240 and U.S.rs.mode ~= "dead" and U.S.rs.dist < 1500 do
        update()
        frames_n = frames_n + 1
        do
            local F = U.S.F
            local dx, dy, dz = F.x - U.S.cx, 0 - C.y, F.z + D.FLOAT_R - (U.S.cz or C.z)
            local depth = dx * sy * cp + dy * cy * cp + dz * sp
            local up = -dx * sy * sp - dy * cy * sp + dz * cp
            local r = up / depth / tv
            if r > worst_top then worst_top = r end
            if r > 1 then out_top = out_top + 1 end
            if F.z > peak_z then peak_z = F.z end
            -- the mist plume dies out after a skim (live: a long-lived mist left a glowing ball behind the float)
            if not U.S.skim and (W.mist_k or 0) > 0 then mist_run = mist_run + 1 else mist_run = 0 end
            if mist_run > mist_worst then mist_worst = mist_run end
            if U.S.skim then skims_seen = skims_seen + 1 end
        end
        if frames_n % 5 == 0 then
            local t = U.S.t
            for _, c in pairs(W.ITEM) do
                local it = c.it
                local gk = R.grid_of(it)
                if gk and not seen[it.id] then
                    seen[it.id] = true
                    kinds[gk] = (kinds[gk] or 0) + 1
                    local ox, oy, oz = Course.origin(it, t)
                    local ex, ey, ez = W.E(ox, oy, oz)
                    local p, r = c.node.pos, type(c.node.rot) == "table" and c.node.rot or { 0, 0, 0 }
                    local okpos = math.abs(p[1] - ex) + math.abs(p[2] - ey) + math.abs(p[3] - ez) < 1e-9
                    local okrot
                    if it.kind == "boat" then
                        okrot = r[1] == 0 and (r[2] == (it.p.yaw or 0)) and r[3] == 0 and ((gk == "boat_180") == (r[2] == 180))
                    elseif it.kind == "buoy_red" or it.kind == "buoy_white" then
                        okrot = r[1] == 0 and r[2] == 0 and math.abs(r[3] + (it.p.pitch or D.BUOY_TILT[2])) < 1e-12
                    else
                        okrot = r[1] == 0 and r[2] == 0 and r[3] == 0
                    end
                    if not (okpos and okrot) then bad = bad + 1; msg = gk .. " at " .. it.x end
                    -- probes: mesh points carried by the drawn transform (Blender axes)
                    for _, q in ipairs(R.HIT[gk].probes) do
                        local lx, ly, lz = q[1], q[2] - oy, q[3]       -- probes are offsets with the plane y included
                        if it.kind == "buoy_red" or it.kind == "buoy_white" then lx, ly, lz = Course.tilt(lx, ly, lz, -r[3]) end
                        local wx, wz = ox + lx, oz + lz
                        probes_n = probes_n + 1
                        if R.hit_at(U.course(), wx, wz, t) == it then probes_ok = probes_ok + 1 end
                    end
                end
            end
        end
    end
    local list = {}
    for k, v in pairs(kinds) do list[#list + 1] = k .. "=" .. v end
    table.sort(list)
    check(bad == 0 and kinds.boat_0 and kinds.boat_180 and kinds.bw_gap and kinds.pier and (kinds.buoy_red or 0) + (kinds.buoy_white or 0) > 10,
        "play: every drawn hazard stands where its hit shape is (" .. table.concat(list, " ") .. "; " .. bad .. " bad " .. msg .. ")")
    check(probes_ok == probes_n and probes_n > 100, string.format("play: %d of %d mesh probes, carried by the drawn transforms, are hits", probes_ok, probes_n))
    check(W.created == made1 and (W.starved or 0) == 0, "play: no nodes made, no pool ran dry (" .. tostring(W.starved or 0) .. (function()
        local t = {} for k, v in pairs(W.starved_by or {}) do t[#t + 1] = k .. "=" .. v end return " " .. table.concat(t, " ") end)() .. ")")
    check(skims_seen > 10 and mist_worst <= 20, string.format("play: the skim mist fades out within 20 frames of a skim ending (worst %d, %d skim frames)",
        mist_worst, skims_seen))
    check(out_top == 0, string.format("play: the float never leaves the top of the frame (highest %.1f; top at %.0f%% of the half-height; %d frames out)",
        peak_z, worst_top * 100, out_top))
    print(string.format("     play run: %s, %.0f units, score %s, lamps %d, skips %d, %d frames", U.S.rs.mode, U.S.rs.dist, tostring(U.S.rs.score), U.S.rs.lamps, U.S.rs.skips, frames_n))
end
-- 6. the game: title -> PLAY -> a run played through the hold key -> a death -> game-over card -> RETRY; Esc pause
-- (RESUME, SETTINGS, BACK TO MENU, QUIT), the settings menu, the mute key, the save file, the sounds, glass unlocks,
-- and every card's text boxes inside the screen and none overlapping, at 1280x720 and 2560x1369.
do
    local G = U.G
    local keys, clicks, quads, played, music, writes, quit = {}, {}, {}, {}, MUSIC, {}, 0
    local shown = {}
    local pilot, pilot_bot
    local surf = { width = 2560, height = 1369 }
    env.input = {
        is_key_down_raw = function(k)
            if k == "Space" and pilot then return U.Bot.input(pilot_bot, U.S.rs) end
            return keys[k] == true
        end,
        is_left_mouse_down = function() return keys.mouse == true end,
    }
    env.runtime_ui = setmetatable({
        get_surface_size = function() return surf end,
        set_quad = function(scr, id, o)
            o.width, o.height = o.width or o.w, o.height or o.h      -- (the settings menu says w, h)
            o.screen = scr
            quads[scr .. '/' .. id] = o
        end,
        show = function(scr) shown[scr] = true end,
        hide = function(scr) shown[scr] = false end,
        get_state = function(_, id) return clicks[id] and { clicked = true, hovered = true } or {} end,
    }, { __index = function() return function() end end })
    env.audio = setmetatable({ play = function(f) played[#played + 1] = f end, play_music = function(f) music[#music + 1] = f end },
        { __index = function() return function() end end })
    env.fs.write = function(path, txt) writes[path] = txt; return true end
    env.engine.quit = function() quit = quit + 1 end
    local function tap(k) keys[k] = true; frames(1); keys[k] = false; frames(1) end
    -- a click lasts one frame, as in the engine; cards ignore clicks in their first 0.12-0.35 s, so wait that out first
    local function click(id) frames(25); clicks[id] = true; frames(1); clicks[id] = nil; frames(1) end
    local function on(o) return o.visible ~= false and shown[o.screen] ~= false end
    local function visible(id) local o = quads['undertow/' .. id]; return o and on(o) end
    local function count(name) local n = 0 for _, f in ipairs(played) do if f == name then n = n + 1 end end return n end
    -- text quads: every visible labelled quad that is not a shadow copy
    local function texts()
        local t = {}
        for _, o in pairs(quads) do
            if on(o) and o.label and o.label ~= "" and o.text_color and o.text_color[1] > 0.05 then t[#t + 1] = o end
        end
        return t
    end
    -- glyph widths of the default font in ems, by kind (measured live at 1280x720: capitals ~0.66, lower case ~0.5;
    -- one average of 0.52 let "BACK TO MENU" pass while it wrapped onto two lines in the Player)
    local function em_width(label)
        local n = 0
        for c in label:gmatch(".") do
            if c:match("[A-Z0-9]") then n = n + 0.68 elseif c == " " then n = n + 0.3 else n = n + 0.52 end
        end
        return n
    end
    local function ink(o)
        local w = math.min(o.width, em_width(o.label) * 16 * (o.font_scale or 1))
        local x0 = o.align_h == "left" and o.x or (o.align_h == "right" and o.x + o.width - w or o.x + (o.width - w) / 2)
        return x0, x0 + w, o.y + o.height * 0.2, o.y + o.height * 0.8
    end
    local function layout_ok(label)
        local t, bad = texts(), {}
        for _, o in ipairs(t) do
            -- the text box wraps inside ~8 px of padding a side ("BACK TO MENU", 115 px live, wrapped in a 133 px box)
            -- (the shared settings menu's quads draw without that padding: "100%" fits its box live)
            local pad = o.screen == "undertow" and 16 or -1
            if em_width(o.label) * 16 * (o.font_scale or 1) > o.width - pad then bad[#bad + 1] = "wide:" .. o.label end
            if o.screen == "undertow" and 16 * (o.font_scale or 1) < 12 - 1e-6 then bad[#bad + 1] = "small:" .. o.label end
            if o.x < 0 or o.y < 0 or o.x + o.width > surf.width + 1 or o.y + o.height > surf.height + 1 then bad[#bad + 1] = "off:" .. o.label end
        end
        for i = 1, #t do for j = i + 1, #t do
            local ax0, ax1, ay0, ay1 = ink(t[i])
            local bx0, bx1, by0, by1 = ink(t[j])
            if ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1 then bad[#bad + 1] = "overlap:" .. t[i].label .. "|" .. t[j].label end
        end end
        -- no text under a button it does not belong to (the best-score line hid under QUIT on the title)
        for _, b in pairs(quads) do
            if on(b) and b.no_input == false and b.screen == "undertow" then
                for _, o in ipairs(t) do
                    local x0, x1, y0, y1 = ink(o)
                    local hit = x0 < b.x + b.width and b.x < x1 and y0 < b.y + b.height and b.y < y1
                    local inside = x0 >= b.x - 1 and x1 <= b.x + b.width + 1 and y0 >= b.y - 1 and y1 <= b.y + b.height + 1
                    if hit and not inside then bad[#bad + 1] = "under-button:" .. o.label end
                end
            end
        end
        check(#bad == 0 and #t > 3, string.format("%s at %dx%d: %d texts inside the screen and their boxes, none overlapping %s", label,
            surf.width, surf.height, #t, table.concat(bad, " "):sub(1, 300)))
    end
    local function both_sizes(label)
        for _, sz in ipairs({ { 1280, 720 }, { 2560, 1369 } }) do surf.width, surf.height = sz[1], sz[2]; frames(2); layout_ok(label) end
    end
    U.game_mode()
    frames(30)
    check(G.mode == "title" and visible("t_play") and visible("t_glass") and visible("t_settings") and visible("t_quit"),
        "title card: PLAY, GLASS, SETTINGS, QUIT shown (" .. G.info() .. ")")
    local says_controls = false
    for _, o in ipairs(texts()) do if o.label:find("HOLD") and o.label:find("Space") then says_controls = true end end
    check(says_controls, "the title card says what the inputs are")
    check(music[#music] == "ambience.wav", "the rain and sea ambience loops (" .. tostring(music[#music]) .. ")")
    check(U.S.rs and U.S.rs.mode ~= "dead" and U.S.bot ~= nil, "behind the title the bot plays the harbour")
    both_sizes("title")
    local function shown_text(pat)
        for _, o in ipairs(texts()) do if o.label:find(pat, 1, true) then return true end end
        return false
    end
    -- HOW TO PLAY (the user: "explain it in game ... have a card on how to play"): H or the button, every rule line
    -- shown, inside the screen and not overlapping at both sizes, BACK returns to the title
    check(visible("t_howto"), "the title card has a HOW TO PLAY button")
    frames(20); tap("H"); frames(12)
    local all_rows = true
    for _, r in ipairs(G.HOWTO_ROWS) do if not (shown_text(r[1]) and shown_text(r[2])) then all_rows = false end end
    check(G.howto ~= nil and visible("h_back") and all_rows and not visible("t_play"),
        "H opens HOW TO PLAY over the title: " .. #G.HOWTO_ROWS .. " rule lines (goal, hold, let go, skim, danger, score, harbour, glass, keys) and BACK")
    both_sizes("how to play")
    click("h_back"); frames(5)
    check(G.howto == nil and G.mode == "title" and visible("t_play"), "BACK closes HOW TO PLAY")
    click("t_howto"); frames(15)
    check(G.howto ~= nil, "the HOW TO PLAY button opens it too")
    tap("Escape"); frames(5)
    check(G.howto == nil and not G.pause, "Esc closes HOW TO PLAY (and does not open the pause card)")
    -- PLAY with Enter; the run waits hanging on its first hook until a press
    check(G.save.tut == 0, "a fresh save has not seen the guide")
    tap("Return")
    check(G.mode == "run" and G.waiting and U.S.rs.hook ~= nil and U.S.bot == nil, "Enter starts a run, hanging on the first hook (" .. G.info() .. ")")
    check(G.tut ~= nil and G.tut.step == 1 and shown_text(G.TUT[1][1]) and visible("tut_skip"), "the first run starts the guide: " .. G.TUT[1][1] .. " (SKIP GUIDE shown)")
    local gentle_ok = true
    for _, it in ipairs(U.S.rs.course.plane) do
        if it.x < G.GENTLE and not U.Rules.has_hook(it) then gentle_ok = false end
    end
    check(gentle_ok, "the guided run's first " .. G.GENTLE .. " units have hooks only (no boats or rocks)")
    frames(240)
    check(G.waiting and U.S.rs.mode == "swing", "with no press the float swings on its first hook (4 s): " .. U.S.rs.mode)
    keys.Space = true; frames(2)
    check(not G.waiting and U.S.rs.hook ~= nil, "pressing Space takes the swing")
    both_sizes("HUD")
    -- held on the first hook (guide step 2), the cue says NOW when the swing is near the top going forward
    do
        local now = false
        for _ = 1, 300 do frames(1); if shown_text("NOW!") then now = true; break end end
        check(now and G.tut and G.tut.step == 2, "holding on the first hook, the guide says LET GO and then NOW at the top of the forward swing")
    end
    -- the guide follows the play: let go, the marked hook, catch, done (saved)
    do
        pilot, pilot_bot = true, U.Bot.new()
        local seen, marker = {}, false
        for _ = 1, 60 * 30 do
            if G.tut then
                for k, line in ipairs(G.TUT) do if shown_text(line[1]) then seen[k] = true end end
                if shown_text("CATCH THIS HOOK") or shown_text("NEXT HOOK") then marker = true end
                if shown_text("NOW!") then seen.now = true end
            end
            frames(1)
            if not G.tut or U.S.rs.mode == "dead" then break end
        end
        check(seen[3] and seen[4] and marker and G.tut == nil and G.save.tut == 1
            and (writes["Save/undertow.txt"] or ""):find("tut=1", 1, true) ~= nil,
            string.format("then the marked hook, the catch, then the guide ends and is saved (steps 3 %s 4 %s, marker %s)",
                tostring(seen[3]), tostring(seen[4]), tostring(marker)))
    end
    -- the hold key drives the rules: the bot presses and lets go of Space for 60 s
    local rel0, hook0 = count("release.wav"), count("catch.wav")
    pilot, pilot_bot = true, U.Bot.new()
    local x0, n0 = U.S.rs.x, U.S.rs.nev or 0
    for _ = 1, 60 * 60 do
        frames(1)
        if U.S.rs.mode == "dead" then break end
    end
    local hooks = 0
    for _, e in ipairs(U.S.rs.events) do if e.kind == "hook" and e.n > n0 then hooks = hooks + 1 end end
    pilot = false
    keys.Space = true
    check(hooks >= 5 and U.S.rs.x - x0 > 50 and U.S.rs.mode ~= "dead", string.format("Space held and let go for 60 s: %d catches (last 64 events), %.0f units on, score %s, %s",
        hooks, U.S.rs.x - x0, tostring(U.S.rs.score), U.S.rs.mode))
    check(count("catch.wav") > hook0 and count("release.wav") > rel0, string.format("catch and release sounds play (%d, %d)",
        count("catch.wav") - hook0, count("release.wav") - rel0))
    -- the float's glow moves with it (found live: its 0.1 s particles, spawned still, trailed a fast float by a float's
    -- width): over 2 s of play the halo's velocity matches the float's wherever it moves fast
    do
        pilot, pilot_bot = true, U.Bot.new()
        local worst, n = 0, 0
        for _ = 1, 120 do
            local x0, z0 = U.S.F.x, U.S.F.z
            frames(1)
            local hv, dt = U.W.halo_v, U.S.raw
            local vx, vz = (U.S.F.x - x0) / dt, (U.S.F.z - z0) / dt
            local sp = math.sqrt(vx * vx + vz * vz)
            if hv and sp > 6 and U.S.rs.mode ~= "dead" then
                n = n + 1
                worst = math.max(worst, math.sqrt((hv[1] - vx) ^ 2 + (hv[2] - vz) ^ 2) / sp)
            end
        end
        pilot = false; keys.Space = true
        -- (the piloted run can end here; the checks below need a live run: retry and take the swing)
        if U.S.rs.mode == "dead" then
            for _ = 1, 300 do frames(1); if G.mode == "over" then break end end
            click("o_retry"); keys.Space = false; frames(2); keys.Space = true; frames(2)
        end
        -- slow engine frames (120 ms; the game moves the float 50 ms a frame): the glow's particles, moved by the engine
        -- for 120 ms, must land on the float (found in autoplay frames: the glow sat beside the float)
        pilot = true
        local worst2, n2 = 0, 0
        SLOW_MS = 120
        for _ = 1, 40 do
            local x0, z0 = U.S.F.x, U.S.F.z
            frames(1)
            local hv = U.W.halo_v
            local dx, dz = U.S.F.x - x0, U.S.F.z - z0
            local d = math.sqrt(dx * dx + dz * dz)
            if hv and d > 0.3 and U.S.rs.mode ~= "dead" then
                n2 = n2 + 1
                worst2 = math.max(worst2, math.sqrt((hv[1] * 0.12 - dx) ^ 2 + (hv[2] * 0.12 - dz) ^ 2) / d)
            end
        end
        SLOW_MS = nil
        pilot = false; keys.Space = true
        check(n2 > 5 and worst2 < 0.05, string.format("on slow frames the glow still lands on the float (%d frames, worst %.0f%% off)", n2, worst2 * 100))
        if U.S.rs.mode == "dead" then
            for _ = 1, 300 do frames(1); if G.mode == "over" then break end end
            click("o_retry"); keys.Space = false; frames(2); keys.Space = true; frames(2)
        end
        check(n > 20 and worst < 0.05, string.format("the glow moves with the float (%d fast frames, worst velocity error %.1f%%)", n, worst * 100))
    end
    -- Esc pauses: nothing moves; RESUME goes on
    tap("Escape")
    local xp = U.S.rs.x
    frames(30)
    check(G.pause and visible("pz_resume") and visible("pz_settings") and visible("pz_menu") and visible("pz_quit") and U.S.rs.x == xp,
        "Esc pauses the run: RESUME, SETTINGS, BACK TO MENU, QUIT shown, nothing moves")
    both_sizes("pause")
    click("pz_settings")
    check(G.settings:is_open() and not G.pause, "SETTINGS opens the shared settings menu from the pause card")
    tap("Escape"); frames(5)
    check(not G.settings:is_open() and G.pause, "BACK from settings returns to the pause card")
    click("pz_resume"); frames(5)
    check(not G.pause and U.S.rs.x ~= xp, "RESUME carries on")
    -- let go for good: the run ends (a sink or a hit), the game-over card follows
    keys.Space = false
    for _ = 1, 60 * 20 do frames(1); if G.mode == "over" then break end end
    frames(30)
    local rs = U.S.rs
    check(G.mode == "over" and visible("o_retry") and visible("o_menu"), "letting go ends the run: game-over card with RETRY and BACK TO MENU (" .. tostring(rs.cause) .. ")")
    check(count(rs.cause == "sink" and "sink.wav" or "crash.wav") >= 1, "the end of the run sounds (" .. tostring(rs.cause) .. ")")
    local sv = writes["Save/undertow.txt"] or ""
    check(sv:find("best=" .. G.save.best, 1, true) and G.save.best >= (rs.score or 0) and sv:find("runs=" .. G.save.runs, 1, true) ~= nil and G.save.runs >= 1,
        "the best score and the run count are saved: " .. sv:gsub("\n", " "))
    check(G.last_hint and #G.last_hint > 10 and shown_text("TIP   " .. G.last_hint), "the game-over card gives a tip: " .. tostring(G.last_hint))
    do
        local hints, distinct = {}, {}
        local cases = {
            { { cause = "sink", what = "40 deg 8.0 u/s", events = { { kind = "release", vz = 2 } } }, false },
            { { cause = "sink", what = "40 deg 8.0 u/s", events = { { kind = "release", vz = -3 } } }, true },
            { { cause = "sink", what = "10 deg 3.0 u/s", events = { { kind = "release", vz = 2 } } }, true },
            { { cause = "sink", what = "40 deg 8.0 u/s", events = { { kind = "release", vz = 2 } } }, true },
            { { cause = "hit", what = "boat", events = {} } }, { { cause = "hit", what = "bw_gap", events = {} } },
            { { cause = "hit", what = "pier", events = {} } }, { { cause = "hit", what = "buoy_red", events = {} } },
            { { cause = "tangle", what = "boat", events = {} } },
        }
        local px = 1280 / 1920
        for _, c in ipairs(cases) do
            local h = G.hint(c[1], c[2])
            hints[#hints + 1] = h
            distinct[h] = true
        end
        local n = 0
        for _ in pairs(distinct) do n = n + 1 end
        check(n == #cases, string.format("each way to lose has its own tip (%d of %d distinct): %s", n, #cases, table.concat(hints, " | "):sub(1, 200)))
    end
    both_sizes("game over")
    -- RETRY starts a fresh run
    local seed0 = G.seed
    click("o_retry")
    check(G.mode == "run" and G.waiting and U.S.rs.mode == "swing" and G.seed ~= seed0, "RETRY starts a new run (seed " .. tostring(G.seed) .. ")")
    check(G.tut == nil and not visible("tut_skip"), "the guide is shown once: no guide on the next run")
    -- HOW TO PLAY from the pause card, BACK returns to the pause card
    tap("Escape"); frames(10)
    check(G.pause and visible("pz_howto"), "the pause card has HOW TO PLAY")
    click("pz_howto"); frames(5)
    check(G.howto ~= nil and not G.pause, "HOW TO PLAY opens from the pause card")
    both_sizes("how to play (pause)")
    click("h_back"); frames(5)
    check(G.howto == nil and G.pause, "BACK from HOW TO PLAY returns to the pause card")
    click("pz_resume"); frames(5)
    -- Esc in the moment after a death (found live: the death delay ran on under the pause card, so the game-over card
    -- came up under it): the pause card holds, no game-over card until RESUME
    keys.Space = true; frames(3); keys.Space = false; frames(3); keys.Space = true; frames(20); keys.Space = false
    for _ = 1, 60 * 20 do frames(1); if U.S.rs.mode == "dead" then break end end
    tap("Escape"); frames(150)
    check(U.S.rs.mode == "dead" and G.pause and G.mode == "run" and not visible("o_retry"),
        "Esc just after a death: the pause card holds, no game-over card under it (" .. G.mode .. ")")
    click("pz_resume"); frames(90)
    check(not G.pause and G.mode == "over" and visible("o_retry"), "RESUME then shows the game-over card")
    click("o_retry")
    check(G.mode == "run", "RETRY again")
    -- BACK TO MENU from the pause card; on the title the pause card has no BACK TO MENU
    tap("Escape"); click("pz_menu"); frames(5)
    check(G.mode == "title" and not G.pause and visible("t_play"), "BACK TO MENU goes to the title")
    do
        G.save.tut = 0
        frames(20); tap("Return"); frames(5)
        local on = G.tut ~= nil
        tap("Tab"); frames(3)
        check(on and G.tut == nil and G.save.tut == 1 and (writes["Save/undertow.txt"] or ""):find("tut=1", 1, true) ~= nil,
            "Tab skips the guide, and the skip is saved")
        tap("Escape"); frames(10); click("pz_menu"); frames(5)
    end
    tap("Escape"); frames(10)
    check(G.pause and not visible("pz_menu") and visible("pz_quit"), "Esc on the title opens the pause card without BACK TO MENU")
    tap("Escape"); frames(10)
    check(not G.pause, "Esc closes it again")
    -- settings from the title, the mute key, quit
    tap("S")
    check(G.settings:is_open(), "S opens the settings from the title")
    both_sizes("settings")
    tap("Escape"); frames(3)
    check(not G.settings:is_open(), "BACK (Esc) closes the settings")
    local m0 = G.settings:get("mute")
    tap("M")
    check(G.settings:get("mute") ~= m0, "M toggles mute")
    tap("M")
    -- glass unlocks by best score
    G.save.best, G.save.glass = 0, "green"
    G.cycle_glass()
    check(G.save.glass == "green", "with best 0 only the green glass is open")
    G.save.best = 450
    G.cycle_glass()
    check(G.save.glass == "amber" and W.glass_name == "amber" and W.FLOAT_LIGHT.colour == W.GLASSES.amber.light, "best 450 opens the amber glass and the float wears it")
    G.save.glass = "green"; W.set_glass("green")
    tap("Q")
    check(quit == 1, "Q quits from the title")
end

local mu = {}
for k, v in pairs(maxused) do mu[#mu + 1] = k .. "=" .. v end
table.sort(mu)
print("     peak pool use: " .. table.concat(mu, " "))

if fails > 0 then print(fails .. " FAILED"); os_exit_code = 1; error("view_smoke failed") end
print("view_smoke: all passed")
