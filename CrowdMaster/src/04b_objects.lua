------------------------------------------------------------------ level objects: gates, red crowds, cages, drops, coins, traps
do
local function opval(s)
    local o, v = s:sub(1, 1), tonumber(s:sub(2)) or 0
    return o, v
end
local function good(s) local o = s:sub(1, 1); return o == "+" or o == "x" or o == "M" end
local function panel_tpl(s) if s:sub(1, 1) == "M" then return "c_glassp" end; return good(s) and "c_glassb" or "c_glassr" end
local function label_of(s)
    local o, v = opval(s)
    if o == "M" then return "Merge" end
    if o == "x" then return "×" .. v end
    if o == "/" then return "÷" .. v end
    return s
end
G.label_of = label_of
R.panel_tpl = panel_tpl

local function mk_gate(e)
    local twin = e.b ~= nil
    local post = e.kind == "trick" and "post_warn" or "post"
    e.posts = {}
    local xs = twin and { -W, 0, W } or { -W, W }
    e.postx = xs
    for _, x in ipairs(xs) do local p = P_get(post); place(p, LX(x), 0, e.z, 1, 1.05, 1); e.posts[#e.posts + 1] = p end
    e.panels = {}
    local sides = twin and { { -W, 0, e.a }, { 0, W, e.b } } or { { -W, W, e.a } }
    for i, s in ipairs(sides) do
        local n = P_get("c_glassb")
        n:set_mesh_ref(mesh_of(panel_tpl(s[3])))
        -- 4 cm clear of the 0.2 m posts on both sides (it used to end exactly on the post surface, a tangent
        -- contact that flickered), and the top tucked 6 cm into the cross bar instead of 1 cm under its bottom face
        n:set_position(vec3(LX((s[1] + s[2]) / 2), 2.27, e.z)); n:set_scale(vec3(s[2] - s[1] - 0.48, 2.06, 0.12))
        e.panels[i] = { n = n, x = (s[1] + s[2]) / 2, w = s[2] - s[1], v = s[3], tpl = panel_tpl(s[3]) }
    end
    if e.kind == "timed" then
        e.lamps = {}
        for i, pn in ipairs(e.panels) do local l = P_get("lamp"); place(l, LX(pn.x), 3.7, e.z, 0.7); e.lamps[i] = l end
        e.alt = { e.b, e.a }
    end
    local bar = P_get("c_white"); bar:set_position(vec3(0, 3.35, e.z)); bar:set_scale(vec3(2 * W + 0.3, 0.22, 0.22)); e.bar = bar
end
local function set_panel(p, v)
    p.v = v
    local t = panel_tpl(v)
    if t ~= p.tpl then p.tpl = t; p.n:set_mesh_ref(mesh_of(t)) end
end
R.set_panel = set_panel

local function enemy_units(e)
    e.units = {}
    local vis = min(e.n, 80)
    for i = 1, vis do
        local n = F_get("man_r0")
        local r = sqrt(i - 0.5) * 0.37; local a = i * 2.39996
        local u = { n = n, ox = cos(a) * r, oz = sin(a) * r * 0.9, ph = rand() * 4, fr = -1 }
        n:set_scale(vec3(1, 1, 1)); n:set_rotation(vec3(0, 180, 0))
        e.units[i] = u
    end
    e.rmax = sqrt(vis) * 0.37 + 0.3
end
function R.enemy_sync(e)
    local want = min(e.n, 80)
    while #e.units > want do
        local u = table.remove(e.units)
        C.dead[#C.dead + 1] = { n = u.n, t = 1, col = "r", x = e.x + u.ox, y = 0, z = e.cz + u.oz, vx = rr(-3, 3), vy = rr(3, 6), vz = rr(1, 4), rx = 0, rz = 0, sp = rr(-500, 500), life = 0.6 }
    end
end

function R.build(L, foe)
    foe = foe or 1
    R.list = {}; R.coins = {}
    for _, src in ipairs(L.ev) do
        local e = {}
        for k, v in pairs(src) do e[k] = v end
        e.done = false
        local t = e.t
        if t == "gate" then mk_gate(e)
        elseif t == "enemy" then e.n = max(4, floor(e.n * foe + 0.5)); e.cz = e.z; e.state = "wait"; e.n0 = e.n; enemy_units(e)
        elseif t == "cage" then e.node = put("cage", e.x, 0, e.z, 1.0, 0); e.hp0 = e.hp; e.caps = {}
            for i = 1, min(e.n, 9) do
                local a, r = i * 2.39996, sqrt(i) * 0.33
                local n = F_get("man_g0"); n:set_mesh_ref(mesh_of("man_gi")); place(n, LX(e.x + cos(a) * r), 0, e.z + sin(a) * r * 0.7, 1, 1, 1, 180)
                e.caps[i] = n
            end
        elseif t == "drop" then e.state = "wait"; e.y = 30
        elseif t == "ally" then e.node = F_get("man_y0"); e.node:set_mesh_ref(mesh_of("man_yc")); place(e.node, LX(e.x), 0, e.z, 2.25, 2.25, 2.25, 180)
        elseif t == "coins" then
            for i = 1, e.n do
                local x = e.wave and (e.x + sin(i * 0.8) * 2.2) or e.x
                local c = { x = x, z = e.z + (i - 1) * 1.6, n = P_get("coin"), on = true, ph = i * 0.4 }
                R.coins[#R.coins + 1] = c
            end
        elseif t == "spin" then
            e.post = put("spin_post", e.x, 0, e.z, 1, 0); e.bar = put("spin_bar", e.x, 0.6, e.z, 1, 0); e.a = 0
        elseif t == "saw" then
            box("c_dark", e.x0 - 0.6, e.x1 + 0.6, G.DECAL.slot[1], G.DECAL.slot[2], e.z - 0.12, e.z + 0.12)
            e.saw = P_get("saw"); e.hub = P_get("saw_hub")
        elseif t == "ham" then
            for _, sx in ipairs({ -W - 0.4, W + 0.4 }) do local p = put("post", sx, 0, e.z, 1.25, 0, 1.72); end
            local cb = P_get("c_metal"); cb:set_position(vec3(0, 5.6, e.z)); cb:set_scale(vec3(2 * W + 1.2, 0.35, 0.35))
            e.h1 = P_get("hammer_handle"); e.h2 = P_get("hammer_head")
        elseif t == "crush" then
            e.blk = P_get("c_redpaint"); e.y = 4.5
            for _, sx in ipairs({ e.x - e.w / 2 - 0.25, e.x + e.w / 2 + 0.25 }) do put("post", sx, 0, e.z, 1.0, 0, 2.0) end
            box("c_warn", e.x - e.w / 2, e.x + e.w / 2, G.DECAL.crush[1], G.DECAL.crush[2], e.z - 1.1, e.z + 1.1)
        elseif t == "roll" then e.rz = e.z; e.state = "wait"; e.node = P_get("roller"); e.sp = {}
            for i = 1, max(1, round(e.w)) do e.sp[i] = P_get("spikes") end
        end
        R.list[#R.list + 1] = e
    end
end

-- world labels (gate signs, crowd badges) drawn by the HUD
function R.label(x, y, z, text, col, size, bg)
    R.labels[#R.labels + 1] = { x = x, y = y, z = z, text = text, col = col, size = size or 1, bg = bg }
end
end
