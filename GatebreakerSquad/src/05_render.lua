------------------------------------------------------------------ 05_render: draws the sim state (lane x -> world X = -x), event -> fx/sfx
do
local D, SIM = G.D, G.SIM
local FX = G.FX
local R = { kinds = {}, sl = {}, kick = {}, coins = {}, streaks = {}, debris = {}, popups = {}, sfxt = {}, fxbudget = 0, t = 0 }
G.R = R
local deg = math.deg
local function use(kind) if not R.kinds[kind] then R.kinds[kind] = true end; return P_get(kind) end
local function xf(n, x, y, z, rx, ry, rz, s, sy, sz)
    n:set_transform(vec3(x, y, z), vec3(rx or 0, ry or 0, rz or 0), vec3(s or 1, sy or s or 1, sz or s or 1))
end
-- rate-limited sound
local function sfxr(name, gap)
    local t = R.sfxt[name] or -1
    if R.t - t >= (gap or 0.06) then R.sfxt[name] = R.t; sfx(name) end
end
G.sfxr = sfxr
local function fxok(cost) if R.fxbudget >= (cost or 1) then R.fxbudget = R.fxbudget - (cost or 1); return true end return false end

-- body + two legs, hip pivot; yaw in degrees; swing in degrees
local RIG = {
    sol = { leg = "sol_leg", hip = 0.45, hx = 0.1 }, vet = { leg = "vet_leg", hip = 0.45, hx = 0.1 }, hero = { leg = "sol_leg", hip = 0.45, hx = 0.1 },
    hvy = { leg = "hvy_leg", hip = 0.66, hx = 0.17 }, runner = { leg = "run_leg", hip = 0.45, hx = 0.1 }, shield = { leg = "run_leg", hip = 0.45, hx = 0.1 },
    brute = { leg = "brute_leg", hip = 0.95, hx = 0.32 }, goliath = { leg = "gol_leg", hip = 0.95, hx = 0.32 }, ironclad = { leg = "mech_leg", hip = 1.17, hx = 0.5 },
    amech = { leg = "amech_leg", hip = 0.73, hx = 0.31 }, sniper = { leg = "sol_leg", hip = 0.45, hx = 0.1 },
}
local function rig(body, rk, x, y, z, yaw, swing, sc, bob, lean, flash, roll)
    local r = RIG[rk]
    sc = sc or 1
    local fs = sc * (1 + (flash or 0))
    xf(use(body), x, y + (bob or 0) * sc, z, lean or 0, yaw, roll or 0, fs)
    if r then
        local a = math.rad(yaw)
        local ca, sa = math.cos(a), math.sin(a)
        for s = -1, 1, 2 do
            local lx = r.hx * s * sc
            xf(use(r.leg), x + lx * ca, y + r.hip * sc, z - lx * sa, swing * s, yaw, 0, sc)
        end
    end
end
R.rig = rig

function R.reset()
    P_reset(); R.sl = {}; R.kick = {}; R.coins = {}; R.streaks = {}; R.popups = {}; R.boss_seen = nil
    if R.trail_ids then for _, id in ipairs(R.trail_ids) do FX.lib:trail_at(id, nil, 0) end end
end

------------------------------------------------------------------ squad
local SOLW = { rifle = true, shotgun = true, minigun = true, rocket = true, laser = true }
local function body_mesh(kind, S)
    local w = SOLW[S.weapon] and S.weapon or "rifle"
    if kind == "hero" then return "hero_" .. (S.hero or "rook") end
    if kind == "hvy" then return "heavy" end
    if kind == "vet" then return "vet_" .. w end
    return "sol_" .. w
end
R.body_mesh = body_mesh
-- muzzle tip of each carried gun in body space (x right, y up, z forward), from gen_meshes.py (gun on the right side)
local TIP = { rifle = { 0.15, 0.75, 0.89 }, shotgun = { 0.15, 0.76, 0.88 }, minigun = { 0.15, 0.73, 1.06 }, rocket = { 0.31, 1.0, 0.71 }, laser = { 0.15, 0.75, 0.89 } }
local function draw_squad(S, dt)
    local bodies = SIM.bodies()
    local n = #bodies
    if n == 0 then return end
    local F = SIM.formation(n)
    local moving = (S.v or 0) > 0.1
    local wph = R.t * 10.5
    for i = 1, n do
        local tx, tz = S.x + F.ox[i], F.oz[i]
        local sl = R.sl[i]
        if not sl then sl = { x = tx, z = tz - 1.5 }; R.sl[i] = sl; if R.t > 0.5 and fxok(1) then FX.puff(WX(tx), 0.6, tz, { .4, .7, 1.2 }, 1) end end
        -- frame-rate independent catch-up (exp decay): ~95% of the way in 0.1 s sideways, so the squad never trails the steering
        sl.x = sl.x + (tx - sl.x) * (1 - math.exp(-dt * 30))
        sl.z = sl.z + (tz - sl.z) * (1 - math.exp(-dt * 16))
        local k = R.kick[i] or 0
        R.kick[i] = max(0, k - dt * 9)
        local ph = wph + i * 1.7
        local sw = moving and math.sin(ph) * 30 or math.sin(R.t * 2 + i) * 3
        local bob = moving and abs(math.cos(ph)) * 0.07 or 0
        local roll = moving and math.sin(ph) * 4 or 0
        local bk = bodies[i]
        local bz = sl.z - k * 0.09
        rig(body_mesh(bk, S), bk, WX(sl.x), 0, bz, 0, sw, 1.18, bob, -k * 7, 0, roll)
        -- muzzle flash star at the gun tip for a few frames after each shot (cheap: one emissive mesh)
        if k > 0.5 and (bk == "sol" or bk == "vet" or bk == "hero") then
            local tp = TIP[S.weapon] or TIP.rifle
            local fsz = (S.weapon == "minigun" and 0.75 or (S.weapon == "shotgun" and 1.25 or 1.0)) * (0.55 + k * 0.6)
            xf(use("mflash"), WX(sl.x) + tp[1] * 1.18, tp[2] * 1.18 + bob * 1.18, bz + tp[3] * 1.18, 0, 0, (i * 47 + R.t * 700) % 360, fsz)
        end
    end
    for i = n + 1, #R.sl do
        local sl = R.sl[i]
        if sl and R.t > 0.5 and fxok(1) then FX.puff(WX(sl.x), 0.7, sl.z, { 1.2, .3, .3 }, 1.5) end
        R.sl[i] = nil
    end
    R.sqF = F
end

------------------------------------------------------------------ foes
local function draw_foe(f, S)
    local x, z = WX(f.x), f.z
    if z > D.SPAWN_Z - 2 then return end
    local yaw = 180 + deg(math.atan2(min(1, max(-1, (S.x - f.x) * 0.15)), 1))
    local fl = (f.hit or 0) * 1.6
    local ph = R.t * (f.slow > 0 and 4 or 11) + f.ph
    local sw = math.sin(ph) * 32
    if f.boss then
        local b = f.boss
        local walk = not f.arrived or f.enr > 25
        local swb = walk and math.sin(R.t * 4) * 22 or math.sin(R.t * 1.4) * 4
        if b == "goliath" then
            rig("gol_body", "goliath", x, 0, z, 180, swb, 2.3, abs(math.cos(R.t * 4)) * 0.06, 0, fl * 0.15)
        elseif b == "ironclad" then
            rig("mech_body", "ironclad", x, 0, z, 180, swb * 0.8, 1.75, abs(math.cos(R.t * 4)) * 0.05, 0, fl * 0.15)
        else
            local y = 4.2 + math.sin(R.t * 2.2) * 0.4
            local sc = 1.7 * (1 + fl * 0.1)
            xf(use("wasp_body"), x, y, z, 8, 180, math.sin(R.t * 1.3) * 6, sc)
            local fa = math.sin(R.t * 38) * 35
            xf(use("wasp_wing"), x - 0.4 * sc, y + 0.55 * sc, z - 0.25 * sc, 0, 180, -fa, sc * 1.5)
            xf(use("wasp_wing"), x + 0.4 * sc, y + 0.55 * sc, z - 0.25 * sc, 0, 0, fa, sc * 1.5)
        end
        return
    end
    local t = f.t
    if t == "runner" then rig("run_body", "runner", x, 0, z, yaw, sw, 1.25, abs(math.cos(ph)) * 0.06, 8, fl * 0.25)
    elseif t == "shield" then rig(f.shield > 0 and "shd_body" or "shd_body_ns", "shield", x, 0, z, yaw, sw * 0.8, 1.25, abs(math.cos(ph)) * 0.05, 4, fl * 0.2)
    elseif t == "brute" then rig("brute_body", "brute", x, 0, z, yaw, math.sin(ph * 0.6) * 24, 1.3, abs(math.cos(ph * 0.6)) * 0.07, 3, fl * 0.12)
    elseif t == "flyer" then
        local y = 2.0 + math.sin(R.t * 3 + f.ph) * 0.25
        xf(use("fly_body"), x, y, z, 12, yaw, math.sin(R.t * 2 + f.ph) * 10, 1.3 * (1 + fl * 0.2))
        xf(use("fly_rotor"), x, y, z, 12, R.t * 2200 % 360, 0, 1.3)
    elseif t == "orb" then
        local s = 0.9 + math.sin(R.t * 18 + f.ph) * 0.1
        xf(use("orb"), x, 1.6, z, 0, R.t * 200, 0, s)
        if fxok(0.3) then FX.emit("ember", x, 1.6, z + 0.4, { n = 1, c0 = { 1.6, .7, .2 }, c1 = { 0, 0, 0 }, s0 = .15, s1 = .3, l0 = .2, l1 = .35, r = .2, sp = .5, drag = 2 }) end
    end
end

------------------------------------------------------------------ props, gates
local function draw_prop(p, S)
    local x, z = WX(p.x), p.z
    local fl = (p.hit or 0) * 1.2
    if p.t == "crate" then
        local y = p.drop and (p.drop * 9) or 0
        local wob = p.drop and math.sin(R.t * 3) * 8 or 0
        xf(use("crate"), x, y, z, wob, 20 + (p.drop and R.t * 40 or 0), 0, 1.15 * (1 + fl))
        if p.drop and fxok(0.3) then FX.smoke(x, y + 1.2, z, 0.5, 0.4) end
    elseif p.t == "container" then
        local orange = (p.ally == "heli" or p.ally == "sniper")
        xf(use(orange and "container_o" or "container"), x, 0, z, 0, 0, 0, 1 + fl * 0.3)
    elseif p.t == "barrel" then xf(use("barrel_red"), x, 0, z, 0, 30, 0, 1.2 * (1 + fl))
    elseif p.t == "cryo" then xf(use("barrel_blue"), x, 0, z, 0, 30, 0, 1.2 * (1 + fl))
    elseif p.t == "barricade" then xf(use("barricade"), x, 0, z, 0, 0, 0, 1 + fl * 0.2) end
end
local function draw_gate(g, S)
    local x, z = WX(g.x), g.z
    local sink = g.passed and g.gone * 3.5 or 0
    local s = g.passed and max(0.01, 1 - g.gone * 0.6) or 1
    local pulse = 1 + (g.hit or 0) * 0.5
    xf(use("gate_frame"), x, -sink, z, 0, 0, 0, 1, s, 1)
    xf(use("gpanel_" .. SIM.gate_color(g)), x, -sink, z, 0, 0, 0, pulse * s, s, 1)
end

------------------------------------------------------------------ shots, beams, missiles, bombs, markers, allies, air support
local function draw_bullets(S)
    local W = D.WEAPONS[S.weapon]
    local mesh = (S.weapon == "rocket") and "rocket" or ((S.weapon == "shotgun") and "pellet" or "tracer")
    local nb = #S.bullets
    local step = (nb > 140) and 2 or 1
    local homing = W.homing
    for i = 1, nb, step do
        local b = S.bullets[i]
        local yaw = deg(math.atan2(-b.vx, b.vz))
        if homing then
            -- guided rocket: a shallow lob (rises then dives onto the lock) with a smoke trail, so it reads as the one curved shot
            local u = min(1, max(0, (b.z - (b.z0 or b.z)) / 26))
            local y = 0.78 + math.sin(u * math.pi) * 1.1
            local pitch = -math.cos(u * math.pi) * 9
            xf(use("rocket"), WX(b.x), y, b.z, pitch, yaw, 0, 1.6)
            if fxok(0.3) then FX.emit("soft", WX(b.x - b.vx * 0.012), y, b.z - 0.45, { n = 1, c0 = { 1.5, .95, .5 }, c1 = { .45, .45, .5 }, s0 = .28, s1 = .45, l0 = .22, l1 = .4, r = .03, sp = .3, drag = 2, grav = { 0, .5, 0 } }) end
        else
            xf(use(mesh), WX(b.x), 0.78, b.z, 0, yaw, 0, 1.0)
        end
    end
    -- lock-on reticle under every foe a rocket is tracking (spinning red ring)
    if homing then
        for _, f in ipairs(S.foes) do
            if not f.dead and (f.lockt or 0) > 0 and f.z < D.SPAWN_Z - 2 then
                local r = (f.r or 0.6) * 1.35 * (1 + math.sin(R.t * 14) * 0.08)
                xf(use("ring"), WX(f.x), (f.fly and 1.4 or 0) + 0.1, f.z, 0, R.t * 220 % 360, 0, r, 1, r)
            end
        end
    end
    -- subtle aim cue: faint glow dashes flowing straight ahead along the edges of the squad's fire strip
    local F = R.sqF
    if F and F.R and (#S.bullets > 0 or S.beams) then
        local hw = max(0.5, F.R - 0.35)
        local ph = (R.t * 9) % 2.2
        for side = -1, 1, 2 do
            for k = 0, 5 do
                local z = 1.6 + ph + k * 2.2
                local sc = 1 - (z - 1.6) / 16
                if sc > 0 then xf(use("aimdash"), WX(S.x + side * hw), 0.035, z, 0, 0, 0, sc, 1, 1) end
            end
        end
    end
    if S.beams then
        for _, bm in ipairs(S.beams) do
            local len = max(0.1, bm.z1 - bm.z0)
            local wob = 1 + math.sin(R.t * 50 + bm.slot) * 0.25
            xf(use("beam"), WX(bm.x), 0.78, bm.z0, 0, 0, 0, wob * 1.4, wob * 1.4, len)
            if fxok(0.4) then FX.sparks(WX(bm.x), 0.9, bm.z1, 2, { 0, 2, -2 }, 4, { .6, 1.6, 2.0 }) end
        end
    end
end
local function draw_air(S, dt)
    for _, m in ipairs(S.missiles) do
        local dx, dz, dy = m.tx - m.x, m.tz - m.z, 1 - m.y
        local yaw = deg(math.atan2(-dx, dz))
        local pitch = -deg(math.atan2(dy, sqrt(dx * dx + dz * dz)))
        xf(use("rocket"), WX(m.x), m.y, m.z, pitch, yaw, 0, 2.2)
        if fxok(0.5) then FX.emit("smoke", WX(m.x), m.y, m.z - 0.5, { n = 1, c0 = { .8, .8, .82 }, c1 = { 0, 0, 0 }, s0 = .35, s1 = .6, l0 = .4, l1 = .7, r = .05, sp = .4, drag = 2, grav = { 0, .6, 0 } }) end
    end
    for _, b in ipairs(S.bombs) do xf(use("bomb"), WX(b.x), b.y, b.z, 70, 0, R.t * 300 % 360, 1.6) end
    for _, mk in ipairs(S.markers) do
        local k = 1 - mk.t / mk.t0
        local pul = 1 + math.sin(R.t * (10 + k * 30)) * 0.06
        -- two rings at clearly different heights, and the inner one never reaches the outer radius (they used to coincide at y .06/.07)
        xf(use("ring"), WX(mk.x), 0.08, mk.z, 0, R.t * 60, 0, mk.r * pul, 1, mk.r * pul)
        xf(use("ring"), WX(mk.x), 0.16, mk.z, 0, -R.t * 60, 0, mk.r * k * 0.88, 1, mk.r * k * 0.88)
        if mk.kind == "rocket" then xf(use("rocket"), WX(mk.x), 0.5 + 26 * (mk.t / mk.t0), mk.z, 90, 0, 0, 3.0) end
    end
    if S.jet then
        local t = S.jet.t
        xf(use("jet"), 0, 19 + t * 0.6, -35 + t * 55, -4, 0, math.sin(t * 2) * 8, 1.6)
        xf(use("jet"), 9, 21 + t * 0.6, -45 + t * 55, -4, 0, math.sin(t * 2 + 1) * 8, 1.6)
    end
    if S.gunship then
        local gs = S.gunship
        local x = gs.side * (-9 + gs.t * 3)
        local y = 9 + math.sin(gs.t * 1.3) * 0.4
        xf(use("heli"), WX(x), y, 8, 6, 180 + gs.side * 20, math.sin(gs.t) * 5, 1.5)
        xf(use("heli_rotor"), WX(x), y, 8, 6, R.t * 1600 % 360, 0, 1.5)
    end
    -- allies
    for _, al in ipairs(S.allies) do
        local x, z = WX(al.x), al.z
        local yaw = -deg(al.ang or 0)
        if al.t == "turret" then
            xf(use("tur_base"), x, 0, z, 0, 0, 0, 1.1)
            xf(use("tur_gun"), x, 1.05, z, 0, yaw, 0, 1.1)
        elseif al.t == "heli" then
            local y = (al.y or 7) + math.sin(R.t * 1.7) * 0.3
            xf(use("heli"), x, y, z, 4, yaw * 0.3, math.sin(R.t * 1.1) * 4, 1.3)
            xf(use("heli_rotor"), x, y, z, 4, R.t * 1700 % 360, 0, 1.3)
        elseif al.t == "mech" then
            rig("amech_body", "amech", x, 0, z, yaw * 0.5, math.sin(R.t * 6) * 18, 1.25, abs(math.cos(R.t * 6)) * 0.04)
        elseif al.t == "sniper" then
            xf(use("container_o"), x, 0, z, 0, 0, 0, 0.75)
            rig("sniper", "sniper", x, 1.8, z, yaw, 0, 1.1)
        else
            local nn = al.n or 3
            for j = 1, nn do
                local a = R.t * 1.6 + j * 2 * PI / nn
                local dx, dz = math.cos(a) * 1.6, math.sin(a) * 0.8
                local y = (al.y or 2.5) + math.sin(R.t * 3 + j) * 0.2
                xf(use("ally_drone"), x + dx, y, z + dz + 1, 0, yaw, 0, 1.0)
                xf(use("fly_rotor"), x + dx, y, z + dz + 1, 0, R.t * 2000 % 360, 0, 1.0)
            end
        end
    end
    -- short-lived streaks (ally shots)
    for i = #R.streaks, 1, -1 do
        local s = R.streaks[i]
        s.t = s.t - dt
        if s.t <= 0 then table.remove(R.streaks, i)
        else
            local k = s.t / s.t0
            local dx, dy, dz = s.x1 - s.x0, s.y1 - s.y0, s.z1 - s.z0
            local len = sqrt(dx * dx + dy * dy + dz * dz)
            local h = 1 - k
            local cx, cy, cz = s.x0 + dx * (0.2 + h * 0.6), s.y0 + dy * (0.2 + h * 0.6), s.z0 + dz * (0.2 + h * 0.6)
            local yaw = deg(math.atan2(dx, dz))
            local pitch = -deg(math.atan2(dy, sqrt(dx * dx + dz * dz)))
            xf(use("tracer"), cx, cy, cz, pitch, yaw, 0, s.w, s.w, min(len * 0.35, 6) / 1.1 * 2)
        end
    end
    -- coin pops
    for i = #R.coins, 1, -1 do
        local c = R.coins[i]
        c.t = c.t + dt; c.vy = c.vy - 22 * dt; c.y = max(0.2, c.y + c.vy * dt); c.z = c.z - (S.v or 0) * dt
        if c.t > 0.9 then table.remove(R.coins, i)
        else xf(use("coin"), c.x, c.y + 0.2, c.z, 90, 0, R.t * 720 % 360, 1.3 * min(1, (0.9 - c.t) * 5)) end
    end
    -- finish banner
    if S.finish_z and S.finish_z > -5 and not S.over then
        xf(use("gate_frame"), 0, 0, S.finish_z, 0, 0, 0, 2.45, 1.25, 1.2)
        xf(use("gpanel_gold"), 0, 0, S.finish_z, 0, 0, 0, 2.45, 1.25, 0.4)
    end
end

------------------------------------------------------------------ events -> fx / sfx / hud
local KILL_COL = { runner = { .9, .25, .35 }, shield = { .9, .5, .2 }, brute = { .9, .2, .3 }, flyer = { .9, .3, .3 }, orb = { 1.4, .6, .2 } }
local function coin_pop(x, z, n)
    for j = 1, min(n, 4) do
        R.coins[#R.coins + 1] = { x = x + (rand() - 0.5) * 0.6, y = 1.0, z = z, vy = 6 + rand() * 3, t = 0 }
    end
end
function R.events(S)
    local H = G.HUD
    for _, e in ipairs(S.events) do
        local k = e.k
        if k == "shot" then
            R.kick[e.slot] = 1
            local sl = R.sl[e.slot]
            if sl and fxok(0.35) then FX.muzzle(WX(sl.x) + 0.18, 0.9, sl.z + 1.05, D.WEAPONS[S.weapon].col) end
            sfxr("shot_" .. S.weapon, S.weapon == "minigun" and 0.05 or 0.08)
        elseif k == "impact" then
            if fxok(0.6) then
                if e.kind == 1 then FX.blood(WX(e.x), e.fly and 2.0 or 0.9, e.z, 3)
                elseif e.kind == 3 and e.thru then FX.sparks(WX(e.x), 1.5, e.z, 2, { 0, 0.5, 3 }, 2, { 1.2, 1.4, 2.0 })   -- shot passing through the glass
                elseif e.kind == 3 then FX.sparks(WX(e.x), 1.8, e.z - 0.1, 3, { 0, 1, -3 }, 4, { 1.2, 1.4, 2.0 })
                else FX.sparks(WX(e.x), 0.8, e.z, 4, { 0, 2, -3 }, 5) end
            end
            sfxr("hit", 0.07)
        elseif k == "kill" then
            local x = WX(e.x)
            if e.boss then
                FX.boom(x, 2.5, e.z, 3.0); FX.boom(x + 1.5, 1.5, e.z + 1, 2.0); FX.confetti(x, 3, e.z, 60, 2)
                G.flash(x, 4, e.z, { 1, .7, .4 }, 120, 0.8, 30)
                sfx("boom_big"); coin_pop(x, e.z, 4)
                if H then H.toast(D.BOSS[e.boss].name .. " Destroyed!", "gold") end
            else
                if fxok(1) then FX.blood(x, e.fly and 2 or 0.8, e.z, e.t == "brute" and 14 or 6); FX.puff(x, 0.8, e.z, KILL_COL[e.t] or { .9, .3, .3 }, e.t == "brute" and 3 or 1) end
                if e.t == "brute" then FX.dust(x, 0.3, e.z, { .6, .5, .45 }, 2, 1.6); sfxr("boom_small", 0.1) end
                if e.fly then FX.sparks(x, 2, e.z, 8) end
                sfxr("splat", 0.05)
                if e.t ~= "orb" and (e.t ~= "runner" or rand() < 0.35) then coin_pop(x, e.z, e.t == "brute" and 3 or 1) end
            end
        elseif k == "shieldbreak" then FX.sparks(WX(e.x), 1, e.z, 16, { 0, 3, -2 }, 7); FX.shards(WX(e.x), 1, e.z, { 1.2, .9, .2 }, 8); sfxr("unlock", 0.1)
        elseif k == "boom" then
            local x = WX(e.x)
            if e.kind == "cryo" then
                FX.ring(x, 0.3, e.z, e.r * 2, { .4, .8, 1.4 }, true); FX.emit("soft", x, 1, e.z, { n = 10, c0 = { .5, .8, 1.3 }, c1 = { 0, 0, 0 }, s0 = 1, s1 = 2, l0 = .4, l1 = .8, r = e.r * 0.6, sp = 2, drag = 2 })
                FX.shards(x, 1, e.z, { .7, .9, 1.3 }, 14); sfx("flip")
            else
                local s = (e.kind == "rocket") and 0.55 or (e.r / 3.2)
                if e.kind ~= "rocket" or fxok(1.5) then FX.boom(x, 0.8, e.z, s) end
                if e.kind ~= "rocket" then G.flash(x, 2, e.z, { 1, .6, .3 }, 60, 0.4, 14); FX.ring(x, 0.2, e.z, e.r * 2.2, { .7, .45, .2 }, true) end
                sfxr(e.kind == "rocket" and "boom_small" or "boom", 0.06)
            end
        elseif k == "weapon" then
            FX.confetti(WX(e.x), 1.5, e.z, 30, 1); sfx("crate"); G.weapon_tint(D.WEAPONS[e.w].col)
            if H then H.toast(D.WEAPONS[e.w].name .. "!", "orange", "w_" .. e.w) end
        elseif k == "ally" then
            FX.confetti(WX(e.x), 2, e.z, 40, 1.2); FX.boom(WX(e.x), 1, e.z, 0.6); sfx("ally")
            if H then H.toast(e.name .. " Freed!", "blue") end
        elseif k == "gatetick" then
            local v = e.v or 0
            sfxr("tick" .. (e.up and 5 or min(5, floor(abs(v) / 4))), 0.05)
        elseif k == "flip" then FX.shards(WX(e.x), 1.8, e.z, { 1.4, .3, .2 }, 16); sfx("flip"); if H then H.toast("Trap Gate Overloaded!", "red") end
        elseif k == "unlock" then FX.shards(WX(e.x), 1.8, e.z, { .8, .85, .9 }, 22); FX.ring(WX(e.x), 1.8, e.z, 4, { .5, 1.2, .6 }); sfx("unlock")
        elseif k == "gate" then
            local x = WX(S.x)
            local c = e.good and { .4, 1.0, 1.4 } or { 1.4, .4, .3 }
            if e.good == nil then c = { .6, .6, .7 } end
            FX.glow_trail(x, 1, 0.5, c); FX.shards(x, 2.2, 0.4, c, 18)
            if e.good then sfx(e.mult and "gate_mult" or "gate_good") elseif e.good == false then sfx("gate_bad") end
            if H then H.gate_pop(e) end
        elseif k == "merge" then
            FX.ring(WX(S.x), 0.3, -1, 5, { 1.4, 1.0, .3 }, true); FX.confetti(WX(S.x), 1.5, -1, 25, 1); sfx("merge")
            -- reads as an upgrade: the counter (worth) does not move; merges inside 1.5 s fold into one toast
            local m = R.mg
            if not m or R.t - m.t > 1.5 then m = { nv = 0, nh = 0 }; R.mg = m end
            m.t = R.t; m.nv = m.nv + (e.nv or 0); m.nh = m.nh + (e.nh or 0)
            if H then
                if m.nh > 0 then H.toast("Merged! " .. (m.nh * 4) .. " Veterans into " .. m.nh .. (m.nh == 1 and " Heavy" or " Heavies"), "gold", nil, "merge_h") end
                if m.nv > 0 then H.toast("Merged! " .. (m.nv * 5) .. " Soldiers into " .. m.nv .. (m.nv == 1 and " Veteran" or " Veterans"), "gold", nil, "merge_v") end
                H.merge_flash()
            end
        elseif k == "hurt" then
            if e.n > 0 then sfxr("hurt", 0.1); if H then H.hurt(e.n) end end
        elseif k == "contact" then if fxok(1) then FX.blood(WX(e.x), 0.8, e.z, 5) end
        elseif k == "boss" then
            music("music_boss"); sfx("roar")
            if H then H.banner(e.name, "Boss Incoming!") end
        elseif k == "bossarrive" then S.shake = max(S.shake, 0.6); sfx("roar"); FX.dust(0, 0.3, 16, { .7, .6, .5 }, 3, 3)
        elseif k == "windup" or k == "volley" then sfxr("warn", 0.3)
        elseif k == "roar" then sfxr("roar", 0.5)
        elseif k == "spit" then sfxr("shot_rocket", 0.2)
        elseif k == "airstrike" then sfx("jet"); if H then H.toast("Airstrike Inbound!", "blue", "air") end
        elseif k == "bombdrop" then sfxr("whistle", 0.6)
        elseif k == "gunship" then sfx("heli"); if H then H.toast("Gunship Support!", "blue") end
        elseif k == "missile" then sfxr("shot_rocket", 0.12)
        elseif k == "drop" then sfx("whistle"); if H then H.toast("Supply Drop!", "orange") end
        elseif k == "land" then FX.dust(WX(e.x), 0.2, e.z, { .8, .75, .7 }, 2, 1.4); sfx("crate")
        elseif k == "hint" then if H and not G.demo then H.hint(e.txt) end
        elseif k == "assist" then if H and not G.demo then H.toast("Rookie Boost: +" .. e.n .. " Recruits", "green") end
        elseif k == "recruit" then FX.puff(WX(S.x), 0.8, -1.5, { .4, 1.2, .5 }, 2)
        elseif k == "stomp" then FX.blood(WX(e.x), 0.6, e.z, 8); sfxr("splat", 0.05)
        elseif k == "breakwall" then FX.grit(WX(e.x), 1, e.z, { .6, .5, .4 }, 18, { 0, 4, -2 }); FX.dust(WX(e.x), 0.5, e.z, { .7, .65, .6 }, 3, 2); sfx("boom_small")
        elseif k == "trace" then
            R.streaks[#R.streaks + 1] = { x0 = WX(e.x0), y0 = e.y0 or 1.2, z0 = e.z0, x1 = WX(e.x1), y1 = e.y1, z1 = e.z1, t = 0.09, t0 = 0.09, w = (e.kind == "sniper") and 2.2 or 1.2 }
            if e.kind == "sniper" then sfxr("shot_sniper", 0.2); FX.sparks(WX(e.x1), e.y1, e.z1, 8) else sfxr("shot_minigun", 0.09) end
        elseif k == "allyleave" then if H then H.toast("Gunship Leaving", "grey") end
        elseif k == "allydown" then if H then H.toast("Ally Mech Down!", "red") end
        elseif k == "finishline" then sfx("levelup")
        end
    end
    S.events = {}
end

------------------------------------------------------------------ frame
local DRAWN = {}
function R.draw(S, dt)
    R.t = R.t + dt
    R.fxbudget = min(30, R.fxbudget + dt * 90)
    for kind in pairs(R.kinds) do P_begin(kind) end
    if S then
        G.world_scroll(S.travel, WX(S.x) * 0.3)
        draw_squad(S, dt)
        for _, f in ipairs(S.foes) do if not f.dead then draw_foe(f, S) end end
        for _, p in ipairs(S.props) do if not p.dead then draw_prop(p, S) end end
        for _, g in ipairs(S.gates) do draw_gate(g, S) end
        draw_bullets(S)
        draw_air(S, dt)
    end
    for kind in pairs(R.kinds) do P_end(kind) end
end
end
