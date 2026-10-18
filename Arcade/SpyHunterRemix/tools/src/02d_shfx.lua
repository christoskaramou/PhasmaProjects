------------------------------------------------------------------ Spy Hunter effects (built on 02c_fx; game units: the car is ~1.5 long)
FX.scale = 0.38
G.fx_light = function(pos, col, power, life, radius) flash(pos, col, power * 0.5, life, radius) end
local SFX = { fires = {}, t = {} }
G.SFX = SFX
local function W3(x, y, h) local p = WP(x, y, h or 0); return p.x, p.y, p.z end
-- explosion: flash, fireball, sparks, rolling smoke, plus a short-lived burning wreck left on the ground.
-- Over water it throws a spray column and a foam ring instead of leaving fire.
function G.sh_explode(p, big)
    local s = big and 3.5 or 1.8
    local gy = p.z   -- world z = course distance
    local gx = -p.x
    local _, _, _, kind = G.course(gy)
    local wet = kind == "river"
    local v = G.P and G.P.v or 0
    FX.explosion(p.x, p.y, p.z, s, { 0, 0.5, v * 0.35 })
    FX.emit("soft", p.x, p.y, p.z, { n = 8 * s, vel = { 0, 2, v * 0.3 }, c0 = { 1.6, 1.0, 0.45 }, c1 = { 0.4, 0.08, 0 }, s0 = .08, s1 = .16,
        l0 = .5, l1 = 1.1, r = .3, sp = 9, drag = .8, grav = { 0, -10, 0 } })                                  -- burning bits
    if wet then
        FX.spray(p.x, p.y, p.z, 2.5 * s, { 0, 4, v * 0.3 }, 1.6 * s)
        FX.emit("foam", p.x, 0.12, p.z, { n = 3, c0 = { .55, .6, .65 }, c1 = { 0, 0, 0 }, s0 = 3 * s, s1 = 4 * s, l0 = 1.0, l1 = 1.6, r = .3, sp = .5, flat = true })
    else
        FX.ring(p.x, 0.13, p.z, 4 * s, { .45, .42, .38 }, true)
        SFX.fires[#SFX.fires + 1] = { x = gx, y = gy, t = 0, life = big and 0 or 1.8 }
    end
end
-- muzzle flash at each gun barrel; dir = travel speed of the shooter
function G.muzzle(x, y, v, side_dir)
    local px, py, pz = W3(x, y, 0.32)
    if side_dir then
        FX.emit("fire", px, py, pz, { n = 2, vel = { -side_dir * 6, 0, v }, c0 = { 2, 1.4, .6 }, c1 = { .3, .05, 0 }, s0 = .5, s1 = .8, l0 = .04, l1 = .07, r = .02, sp = .5, drag = 6 })
    else
        FX.emit("fire", px, py, pz, { n = 2, vel = { 0, 0, v + 6 }, c0 = { 2, 1.5, .7 }, c1 = { .3, .05, 0 }, s0 = .45, s1 = .7, l0 = .04, l1 = .07, r = .02, sp = .5, drag = 6 })
        FX.emit("soft", px, py + 0.05, pz - 0.3, { n = 1, vel = { (rand() < 0.5 and -1 or 1) * 2.5, 1.5, v }, c0 = { 1.2, .9, .35 }, c1 = { .3, .2, .05 },
            s0 = .1, s1 = .14, l0 = .25, l1 = .4, r = .02, sp = 1, drag = 1, grav = { 0, -14, 0 } })                    -- brass
    end
    flash(WP(x, y, 0.6), { 1, .75, .4 }, 5, 0.06, 2.2)
end
-- dock swap: splash-down into the river / water streaming off the car on the ramp
function G.on_swap(mode)
    local P = G.P
    local px, py, pz = W3(P.x, P.y, 0)
    if mode == "boat" then
        FX.spray(px, py, pz + 0.4, 3, { 0, 3.5, P.v * 0.5 }, 1.8)
        FX.emit("foam", px, 0.12, pz, { n = 3, vel = { 0, 0, P.v * 0.3 }, c0 = { .6, .65, .7 }, c1 = { 0, 0, 0 }, s0 = 2.5, s1 = 3.5, l0 = .8, l1 = 1.3, r = .4, sp = .5, flat = true })
        FX.ring(px, 0.13, pz, 3.2, { .5, .55, .6 }, true)
    else
        FX.spray(px, py + 0.2, pz, 1.5, { 0, 1.0, P.v * 0.6 }, 1.0)
    end
    SFX.drip = (mode == "car") and 1.2 or 0
end
function G.on_respawn()
    local P = G.P
    local px, py, pz = W3(P.x, P.y, 0.05)
    if P.mode == "boat" then FX.spray(px, py, pz, 1.5, { 0, 2, P.v }, 1.2)
    else FX.dust(px, py, pz, { .35, .34, .32 }, 1, { 0, 0.5, P.v * 0.6 }, 1.4) end
end
-- per-frame effects that follow the vehicles (called from render_world)
local function every(key, period, dt)
    local t = (SFX.t[key] or 0) - dt
    if t <= 0 then SFX.t[key] = t + period; if SFX.t[key] < 0 then SFX.t[key] = period end; return true end
    SFX.t[key] = t; return false
end
local function wake(key, x, y, v, half, len, k, dt)
    if v < 2 or not every(key, 0.035, dt) then return end
    local f = clamp(v / 22, 0.3, 1.1) * (k or 1)
    for _, s in ipairs({ -1, 1 }) do
        local px, py, pz = W3(x + s * half, y - len, 0.12)   -- 12 cm up: the particle pass fades anything within 10 cm of a surface
        FX.emit("foam", px, py, pz, { n = 1, vel = { -s * (0.6 + v * 0.05), 0, v * 0.25 }, c0 = { .75 * f, .8 * f, .85 * f }, c1 = { 0, 0, 0 },
            s0 = 1.3, s1 = 2.1, l0 = 1.3, l1 = 2.0, r = .05, sp = .3, drag = .8, flat = true })
        local bx, by, bz = W3(x + s * half * 0.8, y + len * 0.7, 0.0)
        if rand() < 0.6 then FX.emit("foam", bx, by, bz, { n = 1, vel = { -s * (1 + v * 0.08), 1.2 + v * 0.05, v * 0.9 }, c0 = { .5 * f, .55 * f, .6 * f }, c1 = { 0, 0, 0 },
            s0 = .5, s1 = .9, l0 = .25, l1 = .45, r = .05, sp = 1, drag = 1.5, grav = { 0, -9, 0 } }) end      -- bow spray
    end
    local cx, cy, cz = W3(x, y - len - 0.1, 0.12)
    FX.emit("foam", cx, cy, cz, { n = 1, vel = { 0, 0.4, v * 0.3 }, c0 = { .6 * f, .65 * f, .7 * f }, c1 = { 0, 0, 0 }, s0 = 1.4, s1 = 2.0, l0 = .8, l1 = 1.3, r = .1, sp = .5, drag = 1.2, flat = true })  -- prop wash
end
local function tyres(key, x, y, v, k, dt)
    if not every(key, 0.05, dt) then return end
    for _, s in ipairs({ -1, 1 }) do
        local px, py, pz = W3(x + s * 0.34, y - 0.5, 0.08)
        FX.smoke(px, py, pz, 0.45 * k, { 0, 0.3, v * 0.7 }, 0.3, 0.9)
    end
end
function G.sh_frame_fx(dt)
    local P = G.P
    if G.state ~= "play" and G.state ~= "title" then return end
    if P.alive and G.phase == "drive" then
        if P.mode == "boat" then wake("pw", P.x, P.y, P.v, 0.38, 0.8, 1, dt)
        else
            local k = 0
            if P.brk then k = 1 elseif abs(P.vx or 0) > 4.2 then k = 0.6 end
            if k > 0 then tyres("pt", P.x, P.y, P.v, k, dt) end
            if (SFX.drip or 0) > 0 then
                SFX.drip = SFX.drip - dt
                if every("drip", 0.05, dt) then local px, py, pz = W3(P.x, P.y - 0.5, 0.2); FX.spray(px, py, pz, 0.4, { 0, 0.5, P.v * 0.8 }, 0.6) end
            end
            if every("exh", 0.09, dt) then
                local px, py, pz = W3(P.x, P.y - 0.8, 0.18)
                FX.emit("smoke", px, py, pz, { n = 1, vel = { 0, 0.3, P.v * 0.6 }, c0 = { .12, .12, .13 }, c1 = { 0, 0, 0 }, s0 = .35, s1 = .6, l0 = .3, l1 = .6, r = .03, sp = .5, drag = 3 })
            end
        end
    end
    for i, e in ipairs(G.EN) do
        if e.alive then
            if e.k == "eboat" or e.k == "dumper" then wake("ew" .. i, e.x, e.y, e.v, 0.45, 0.9, 0.8, dt)
            elseif e.spin > 0 then tyres("es" .. i, e.x, e.y, e.v, 1, dt) end
        end
    end
    for _, s in ipairs(G.SHOTS) do
        if s.k == "missile" then
            local px, py, pz = W3(s.x, s.y - 0.35, 0.3)
            FX.emit("fire", px, py, pz, { n = 1, vel = { 0, 0, P.v * 0.5 }, c0 = { 1.8, 1.1, .45 }, c1 = { .2, .03, 0 }, s0 = .35, s1 = .5, l0 = .05, l1 = .1, r = .02, sp = .4, drag = 4 })
            if every("ms", 0.03, dt) then FX.emit("smoke", px, py, pz, { n = 1, vel = { 0, 0.4, P.v * 0.4 }, c0 = { .3, .3, .31 }, c1 = { 0, 0, 0 }, s0 = .5, s1 = .8, l0 = .5, l1 = .9, r = .05, sp = .6, drag = 2.5 }) end
        end
    end
    for i, s in ipairs(G.ESHOT) do
        if s.k == "torpedo" and every("tp" .. i, 0.04, dt) then
            local px, py, pz = W3(s.x, s.y - 0.3, 0.12)
            FX.emit("foam", px, py, pz, { n = 1, c0 = { .4, .45, .5 }, c1 = { 0, 0, 0 }, s0 = .5, s1 = .8, l0 = .7, l1 = 1.1, r = .05, sp = .3, flat = true })
        end
    end
    for i, o in ipairs(G.DROPS) do
        if o.k == "smoke" and o.t < 3.0 and every("sm" .. i, 0.09, dt) then
            -- the smoke screen: a rolling wall across its whole catch width. Puffs are dim on purpose: the particle
            -- pass screen-blends, so twenty overlapping puffs already read as a thick white wall.
            local k = 1 - o.t / 3.0
            for j = -1, 1 do
                local px, py, pz = W3(o.x + j * 0.9 + rr(-0.25, 0.25), o.y + rr(-0.5, 0.5), 0.3 + rand() * 0.3)
                FX.emit("smoke", px, py, pz, { n = 1, vel = { j * 0.4, 0.5, 0 }, c0 = { .045 * k + .02, .045 * k + .02, .05 * k + .02 }, c1 = { 0, 0, 0 },
                    s0 = 2.4, s1 = 3.8, l0 = 1.2, l1 = 2.0, r = .5, sp = 1.0, drag = 1.5, grav = { 0, .4, 0 } })
            end
        elseif o.k == "oil" and o.t < 6 and every("oil" .. i, 0.35, dt) then
            -- rainbow sheen drifting over the slick (screen blending adds the thin-film colours)
            local hue = rand()
            local c = { .5 + .5 * sin(hue * 6.28), .5 + .5 * sin(hue * 6.28 + 2.1), .5 + .5 * sin(hue * 6.28 + 4.2) }
            local px, py, pz = W3(o.x + rr(-0.35, 0.35), o.y + rr(-0.5, 0.5), 0.12)
            FX.emit("ring", px, py, pz, { n = 1, c0 = { c[1] * .12, c[2] * .12, c[3] * .12 }, c1 = { 0, 0, 0 }, s0 = 1.2, s1 = 2.2, l0 = .8, l1 = 1.4, r = .05, sp = .1, flat = true })
        elseif o.k == "crater" and o.t < 3 and every("cr" .. i, 0.15, dt) then
            local px, py, pz = W3(o.x + rr(-0.2, 0.2), o.y, 0.1)
            FX.emit("smoke", px, py, pz, { n = 1, vel = { 0, 0.8, 0 }, c0 = { .14, .14, .14 }, c1 = { 0, 0, 0 }, s0 = .8, s1 = 1.3, l0 = 1, l1 = 1.6, r = .2, sp = .5, grav = { 0, .8, 0 } })
        end
    end
    -- burning wrecks left by explosions
    for i = #SFX.fires, 1, -1 do
        local f = SFX.fires[i]
        f.t = f.t + dt
        if f.t > f.life or f.y < P.y - 14 then table.remove(SFX.fires, i)
        elseif every("bf" .. i, 0.07, dt) then
            local k = 1 - f.t / f.life
            local px, py, pz = W3(f.x + rr(-0.15, 0.15), f.y + rr(-0.2, 0.2), 0.15)
            FX.fire(px, py, pz, 0.6 * k, 0.8)
            FX.smoke(px, py + 0.3, pz, 0.35 * k + 0.1, { 0, 1.0, 0 }, 0.25, 1.2)
        end
    end
end
function G.sh_fx_reset() SFX.fires = {}; SFX.t = {}; SFX.drip = 0 end
