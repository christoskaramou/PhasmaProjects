-- CROWD MASTER (Phasma Engine, Lua)
-- A Count Masters style crowd runner: steer a crowd of stickmen through math gates, merge pawns into brutes and giants,
-- crush red crowds, survive traps and treacherous terrain, then climb the Trophy Staircase or topple the King.
-- World: Y up, metres, the track runs along +Z, x = lateral (+ = right as seen from behind the crowd).
-- Fixed 60 Hz simulation with capped catch-up; everything game-specific lives in this project.
local PI = math.pi
local sin, cos, sqrt, rand, floor, abs, min, max, atan2 = math.sin, math.cos, math.sqrt, math.random, math.floor, math.abs, math.min, math.max, math.atan2
math.randomseed(20261029)
local function rr(a, b) return a + (b - a) * rand() end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function damp(a, b, k, dt) return lerp(a, b, 1 - math.exp(-k * dt)) end
local function round(v) return floor(v + 0.5) end
local G = { state = "boot", t = 0, test = {} }
_G.CM = G

------------------------------------------------------------------ deferred materials (engine quirk: replay writes)
local _mset, _mtex, _mds = material.set, material.set_texture, material.set_double_sided
local mat_q = {}
local function qpush(f) mat_q[#mat_q + 1] = { f = f, n = 0 } end
local function mset(n, k, v) pcall(_mset, n, k, v); qpush(function() pcall(_mset, n, k, v) end) end
local function mtex(n, k, v) pcall(_mtex, n, k, v); qpush(function() pcall(_mtex, n, k, v) end) end
local function flush_mats()   -- replay in queue order so later writes (world tints) win over earlier ones (base paint)
    if #mat_q == 0 then return end
    local keep = {}
    for i = 1, #mat_q do
        local q = mat_q[i]; q.n = q.n + 1
        if q.n == 2 or q.n == 6 then q.f() end
        if q.n < 6 then keep[#keep + 1] = q end
    end
    mat_q = keep
end
local function paint(n, base, emis, rough, metal, alpha)
    if not n then return end
    mset(n, "base_color", vec4(base[1], base[2], base[3], alpha or 1))
    mset(n, "emissive", vec3(emis[1], emis[2], emis[3]))
    mset(n, "roughness", rough or 0.5)
    mset(n, "metallic", metal or 0.0)
end
local function sfx(name) pcall(audio.play, name .. ".wav") end
G.music_cur = nil
local function music(name)
    if G.music_cur == name then return end
    G.music_cur = name
    pcall(audio.stop_music)
    if name then pcall(audio.play_music, name .. ".wav") end
end

------------------------------------------------------------------ camera + projection
local surf = runtime_ui.get_surface_size()
local SW, SH = surf.width or 1920, surf.height or 1080
G.SW, G.SH = SW, SH
local cam = (get_camera and get_camera()) or scene.get_cameras()[1]
local VFOV = math.rad(52)
local function set_vfov(v)
    VFOV = v
    pcall(function() cam:set_fov(math.deg(2 * math.atan(math.tan(VFOV / 2) * SW / SH))) end)
end
set_vfov(VFOV)
pcall(function() cam:set_far_plane(2500) end)
pcall(function() cam:set_near_plane(0.3) end)
G.cam = { pos = vec3(0, 7, -10), look = vec3(0, 0.5, 10) }
local function project(x, y, z)
    local c, l = G.cam.pos, G.cam.look
    local fx, fy, fz = l.x - c.x, l.y - c.y, l.z - c.z
    local fl = sqrt(fx * fx + fy * fy + fz * fz); fx, fy, fz = fx / fl, fy / fl, fz / fl
    local rx, rz = -fz, fx; local rl = sqrt(rx * rx + rz * rz); rx, rz = rx / rl, rz / rl
    local ux, uy, uz = -rz * fy, rz * fx - rx * fz, rx * fy
    local dx, dy, dz = x - c.x, y - c.y, z - c.z
    local zc = dx * fx + dy * fy + dz * fz
    if zc < 0.3 then return -9999, -9999, zc end
    local th = math.tan(VFOV / 2)
    -- r = screen right; looking down +Z it is world -X (game code uses lane x = -world X, so +x is screen right)
    return SW / 2 + (dx * rx + dz * rz) / (zc * th) * SH / 2, SH / 2 - (dx * ux + dy * uy + dz * uz) / (zc * th) * SH / 2, zc
end

------------------------------------------------------------------ templates -> clones, pools
local TPL = {}
local function tpl(name)
    if TPL[name] ~= nil then return TPL[name] end
    local n = scene.find_model("T_" .. name)
    if not n then pe_log("[CM] missing template " .. name); TPL[name] = false; return false end
    TPL[name] = { node = n, mesh = n:get_mesh_refs()[1] }
    return TPL[name]
end
local function mesh_of(name) local t = tpl(name); return t and t.mesh end
local seq = 0
local HIDE = vec3(0, -1000, 0)
local function clone(name, pos, scale)
    local t = tpl(name); seq = seq + 1
    local n = scene.add_empty_node(name .. "_c" .. seq)
    if t and t.mesh then n:add_mesh_ref(t.mesh) end
    n:set_position(pos or HIDE)
    if scale then n:set_scale(scale) end
    return n
end
local function tnode(name) local t = tpl(name); return t and t.node end
-- pools: P_get(kind) hands out clones (reused across levels); P_reset hides everything for a rebuild
local POOL = {}
G.POOL = POOL   -- debug access from MCP (lua.sh)
local function P_get(kind)
    local p = POOL[kind]; if not p then p = { n = {}, used = 0 }; POOL[kind] = p end
    p.used = p.used + 1
    local n = p.n[p.used]
    if not n then n = clone(kind); p.n[p.used] = n end
    return n
end
local function P_reset(kinds)
    for k, p in pairs(POOL) do
        if not kinds or kinds[k] then
            for i = 1, #p.n do p.n[i]:set_position(HIDE); p.n[i]:set_rotation(vec3(0, 0, 0)); p.n[i]:set_scale(vec3(1, 1, 1)) end
            p.used = 0
        end
    end
end
-- free-list pools for transient things (units, debris): get/put
local FREE = {}
local function F_get(kind)
    local f = FREE[kind]; if f and #f > 0 then return table.remove(f) end
    return clone(kind)
end
local function F_put(kind, n)
    n:set_position(HIDE)
    local f = FREE[kind]; if not f then f = {}; FREE[kind] = f end
    f[#f + 1] = n
end
local function place(n, x, y, z, sx, sy, sz, ry, rx, rz)
    n:set_position(vec3(x, y, z))
    n:set_scale(vec3(sx or 1, sy or sx or 1, sz or sx or 1))
    n:set_rotation(vec3(rx or 0, ry or 0, rz or 0))
    return n
end

------------------------------------------------------------------ lights
local LIGHT_GAIN = 0.12
local LNODE = {}
local function add_point() lights.add_point(); return #lights.get_point_lights() - 1 end
local function set_point(i, pos, col, inten, rad)
    pcall(lights.set_point_light, i, pos, col, inten * LIGHT_GAIN, rad)
    local n = LNODE[i]
    if n == nil then
        local l = lights.get_point_lights()[i + 1]
        n = (l and scene.find_model(l.name)) or false
        LNODE[i] = n
    end
    if n then n:set_position(pos) end
end

------------------------------------------------------------------ input (raw keys, edges, mouse)
local prev = {}
local keyfn = input.is_key_down_raw or input.is_key_pressed
local function held(k) if G.vk and G.vk[k] then return true end local ok, v = pcall(keyfn, k); return ok and v end
local function edge(k) local d = held(k); local p = prev[k]; prev[k] = d; return d and not p end
local function anyedge(...) local r = false; for _, k in ipairs({ ... }) do if edge(k) then r = true end end; return r end
local function anyheld(...) for _, k in ipairs({ ... }) do if held(k) then return true end end; return false end
local MOUSE = { x = 0, y = 0, down = false, pressed = false, released = false, px = 0 }
local function poll_mouse()
    local ok, p = pcall(input.get_mouse_position)
    if ok and p then MOUSE.x = p.x or p[1] or MOUSE.x; MOUSE.y = p.y or p[2] or MOUSE.y end
    if G.vmouse then MOUSE.x, MOUSE.y = G.vmouse.x, G.vmouse.y end
    local ok2, d = pcall(input.is_left_mouse_down)
    d = (ok2 and d) or (G.vmouse and G.vmouse.down) or false
    MOUSE.pressed = d and not MOUSE.down
    MOUSE.released = (not d) and MOUSE.down
    MOUSE.down = d
end

------------------------------------------------------------------ tiny serializer for the save file
local function ser(v, ind)
    ind = ind or ""
    local t = type(v)
    if t == "number" then return (v == floor(v)) and string.format("%d", v) or string.format("%.4f", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
            parts[#parts + 1] = ind .. " " .. key .. "=" .. ser(x, ind .. " ")
        end
        table.sort(parts)
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
    end
    return "nil"
end
local function deser(s)
    if not s or s == "" then return nil end
    local f = load("return " .. s, "@save", "t", {})
    if not f then return nil end
    local ok, v = pcall(f)
    return ok and type(v) == "table" and v or nil
end
