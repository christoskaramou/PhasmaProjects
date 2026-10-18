------------------------------------------------------------------ vehicles
-- half sizes (x, y) for the collision boxes; they match the meshes
local DIM = { int = { .4, .76 }, boat = { .42, .88 }, civ = { .4, .75 }, truck = { .48, 1.25 }, van = { .5, 1.4 }, sw = { .44, .8 },
    rl = { .48, .86 }, enf = { .42, 1.06 }, eboat = { .5, .95 }, dumper = { .5, .95 }, heli = { .5, .7 } }
G.DIM = DIM
local PTS = { sw = 500, rl = 500, enf = 500, heli = 1500, eboat = 700, dumper = 700 }
local P = { x = 0, y = 0, v = 0, vx = 0, mode = "car", alive = true, inv = 0, weapon = nil, ammo = 0 }
G.P = P
G.EN, G.SHOTS, G.ESHOT, G.DROPS, G.BOMBS = {}, {}, {}, {}, {}
local VMAX, VMIN = 26, 0
local function pdim() return P.mode == "car" and DIM.int or DIM.boat end
G.pdim = pdim
local function overlap(ax, ay, ad, bx, by, bd) return abs(ax - bx) < ad[1] + bd[1] and abs(ay - by) < ad[2] + bd[2] end
-- a vehicle box is on the surface when all four corners are
local function box_on(x, y, d, mode)
    local on = G.on_surface
    return on(x - d[1] * 0.8, y - d[2] * 0.7, mode) and on(x + d[1] * 0.8, y - d[2] * 0.7, mode) and on(x - d[1] * 0.8, y + d[2] * 0.7, mode) and on(x + d[1] * 0.8, y + d[2] * 0.7, mode)
end
G.box_on = box_on
-- a lane position that stays on the surface from y to y + ahead (the car keeps rolling while it is protected).
-- The old respawn used the course centre line, which is the grass median wherever the road splits round an island.
local function safe_x(y, x, mode, ahead)
    local cx, hw, isl = G.course(y)
    local d = (mode == "car") and DIM.int or DIM.boat
    local pref = (x or cx) < cx and -1 or 1
    -- candidate = { side, a }: x = centre + side * (island + (half width - island) * a); side 0 = centre line
    local function at(c, h, i, cand) if cand[1] == 0 then return c end; return c + cand[1] * (i + (h - i) * cand[2]) end
    local cands = { { 0, 0 }, { pref, 0.5 }, { -pref, 0.5 }, { pref, 0.3 }, { -pref, 0.3 }, { pref, 0.7 }, { -pref, 0.7 } }
    for _, cand in ipairs(cands) do
        local ok = true
        for dy = 0, ahead or 0, 0.5 do
            local c2, h2, i2 = G.course(y + dy)
            if not box_on(at(c2, h2, i2, cand), y + dy, d, mode) then ok = false; break end
        end
        if ok then return at(cx, hw, isl, cand), cand end
    end
    return at(cx, hw, isl, { pref, 0.5 }), { pref, 0.5 }
end
G.safe_x = safe_x
-- which vehicle fits at y: the boat whenever any part of its length would be over the river (it may sit on the dock)
function G.mode_at(y)
    for _, dy in ipairs({ -DIM.boat[2], 0, DIM.boat[2] }) do
        local _, _, _, k = G.course(y + dy); if k == "river" then return "boat" end
    end
    return "car"
end
function G.new_game_sim()
    G.score = 0; G.free = 60; G.cars = 0; G.next_car = 10000; G.freeze = 0; G.out = false
    P.x, P.y, P.v, P.vx, P.mode, P.alive, P.inv, P.weapon, P.ammo = 0, 4, 10, 0, "car", true, 2, nil, 0
    G.EN, G.SHOTS, G.ESHOT, G.DROPS, G.BOMBS = {}, {}, {}, {}, {}
    G.spawn_t = 2; G.van_at = 260; G.heli_at = 520; G.lap = 1; G.dist_acc = 0
    G.phase = "drive"; G.pt = 0; G.weapon_i = 0
    P.x = G.safe_x(P.y, 0, "car", 12); P.swap_t = 9
    G.banner_set("Free Cars For 60 Seconds", 2.5)
end
local function add_pts(n)
    if G.freeze > 0 then return end
    add_score(n)
    if G.score >= G.next_car then G.next_car = G.next_car + 10000; G.cars = G.cars + 1; sfx("extra"); G.banner_set("Extra Car", 1.4) end
end
G.add_pts = add_pts
------------------------------------------------------------------ crashes
local function wreck(e, by_player)
    e.alive = false
    G.boom(WP(e.x, e.y, 0.4), false); sfx("boom")
    if e.k == "civ" or e.k == "truck" then
        if by_player then G.freeze = 6; sfx("penalty"); G.banner_set("Don't Destroy Civilians", 2.0) end
    elseif by_player then add_pts(PTS[e.k] or 300) end
end
local function crash()
    if not P.alive or P.inv > 0 then return end
    P.alive = false; G.phase = "crash"; G.pt = 0
    sfx(P.mode == "car" and "crash" or "splash"); G.boom(WP(P.x, P.y, 0.4), false); G.shake = 0.8
    if P.mode == "boat" then G.spray(WP(P.x, P.y, 0.2), 20) end
end
G.crash = crash
------------------------------------------------------------------ spawning
local function lane_x(y, f) local cx, hw, isl = G.course(y); local side = f < 0 and -1 or 1; return cx + side * (isl + (hw - isl) * abs(f)) end
local function spawn(k, y, f, v)
    local x = lane_x(y, f)
    local e = { k = k, x = x, y = y, v = v, vx = 0, f = f, hp = ({ sw = 2, enf = 3, eboat = 2, dumper = 2, civ = 1, truck = 2, rl = 99, van = 99, heli = 99 })[k] or 1,
        alive = true, t = 0, fire = rr(1.5, 3), slash = 0, spin = 0 }
    if G.box_on(x, y, DIM[k] or DIM.civ, (k == "eboat" or k == "dumper") and "boat" or "car") or k == "heli" then G.EN[#G.EN + 1] = e; return e end
end
local function spawn_traffic()
    local _, _, _, kind = G.course(P.y + 30)
    local boat = kind == "river"
    if (P.mode == "boat") ~= boat then return end
    local r = rand()
    local ahead = rand() < 0.65
    local y = ahead and P.y + rr(26, 32) or P.y - 9
    local f = (rand() < 0.5 and -1 or 1) * rr(0.25, 0.75)
    if boat then
        if r < 0.5 then spawn("eboat", P.y - 9, f, P.v + 4)
        else spawn("dumper", P.y + 28, f, max(4, P.v - 4)) end
        return
    end
    local prog = P.y / 300
    if r < 0.38 then spawn("civ", y, f, ahead and rr(9, 14) or P.v + rr(3, 6))
    elseif r < 0.5 then spawn("truck", y, f, ahead and rr(8, 11) or P.v + 3)
    elseif r < 0.68 then spawn("sw", P.y - 9, f, P.v + rr(4, 6))
    elseif r < 0.84 or prog < 1 then spawn("rl", y, f, ahead and rr(10, 13) or P.v + 4)
    else spawn("enf", P.y - 10, f, P.v + 5) end
end
------------------------------------------------------------------ weapons
local WEAPS = { "smoke", "oil", "missile" }
local WNAME = { smoke = "Smoke Screen", oil = "Oil Slick", missile = "Missiles" }
G.WNAME = WNAME
local function fire_guns()
    if not P.alive or #G.SHOTS >= 8 then return end
    for _, s in ipairs({ -1, 1 }) do G.SHOTS[#G.SHOTS + 1] = { x = P.x + s * 0.18, y = P.y + 0.9, py = P.y + 0.9, d = 0, k = "bullet" }; G.muzzle(P.x + s * 0.18, P.y + 0.9, P.v) end
    sfx("gun")
end
local function fire_special()
    if not P.alive or not P.weapon or P.ammo <= 0 then return end
    P.ammo = P.ammo - 1
    if P.weapon == "missile" then G.SHOTS[#G.SHOTS + 1] = { x = P.x, y = P.y + 0.9, py = P.y + 0.9, d = 0, k = "missile" }; sfx("missile")
    elseif P.weapon == "oil" then G.DROPS[#G.DROPS + 1] = { k = "oil", x = P.x, y = P.y - 1.2, t = 0, rot = rr(0, 360) }; sfx("oil")
    else G.DROPS[#G.DROPS + 1] = { k = "smoke", x = P.x, y = P.y - 1.2, t = 0 }; sfx("smoke"); G.smoke(WP(P.x, P.y - 1.2, 0.5), 18) end
    if P.ammo <= 0 then P.weapon = nil end
end
------------------------------------------------------------------ enemy AI
local function enemy_step(e, dt)
    e.t = e.t + dt
    local cx, hw, isl = G.course(e.y)
    local d = DIM[e.k] or DIM.civ
    if e.spin > 0 then
        -- spinning out on oil / blinded by smoke: drift off and crash
        e.spin = e.spin - dt; e.x = e.x + e.vx * dt; e.v = max(0, e.v - 10 * dt)
        e.y = e.y + e.v * dt
        if not G.box_on(e.x, e.y, d, "car") then wreck(e, true) end
        return
    end
    local tx = lane_x(e.y, e.f)
    if e.k == "sw" or e.k == "rl" or e.k == "enf" then
        -- hunters pull alongside the Interceptor
        local side = (e.x < P.x) and -1 or 1
        if abs(e.y - P.y) < 6 and P.alive then
            tx = P.x + side * (e.k == "rl" and 0.7 or 0.95)
            e.v = e.v + clamp((P.v + (P.y - e.y) * 1.5) - e.v, -8, 8) * dt * 2
        end
        if e.k == "sw" and P.alive and abs(e.y - P.y) < 0.6 and abs(abs(e.x - P.x) - 0.9) < 0.2 then
            -- the Switch Blade's tyre slashers
            e.slash = e.slash + dt
            if e.slash > 0.5 then crash() end
        else e.slash = 0 end
        if e.k == "enf" then
            e.fire = e.fire - dt
            if e.fire <= 0 and P.alive and abs(e.y - P.y) < 0.8 then
                e.fire = rr(1.6, 2.4); sfx("gun"); G.muzzle(e.x + ((P.x > e.x) and 0.45 or -0.45), e.y, e.v, (P.x > e.x) and 1 or -1)
                G.ESHOT[#G.ESHOT + 1] = { x = e.x, y = e.y, vx = (P.x > e.x) and 9 or -9, vy = 0, life = 0.4, k = "bullet" }
            end
        end
    elseif e.k == "heli" then
        -- the Mad Bomber hovers ahead and drops bombs on the road in front of you
        e.y = P.y + 9 + 1.5 * sin(e.t * 0.8); e.x = e.x + (P.x - e.x) * min(1, dt * 1.2)
        e.fire = e.fire - dt
        if e.fire <= 0 and P.alive then e.fire = rr(1.3, 2.0); G.BOMBS[#G.BOMBS + 1] = { x = e.x, y = e.y - 1, t = 0, T = 0.9 }; sfx("bombfall") end
        if e.t > 26 then e.alive = false end
        return
    elseif e.k == "eboat" then
        -- Doctor Torpedo: comes up from behind and fires straight ahead
        e.v = e.v + clamp((P.v + (P.y - 3 - e.y) * 1.2) - e.v, -6, 6) * dt
        tx = P.x
        e.fire = e.fire - dt
        if e.fire <= 0 and P.alive and e.y < P.y and abs(e.x - P.x) < 0.6 then e.fire = rr(2, 3); G.ESHOT[#G.ESHOT + 1] = { x = e.x, y = e.y + 1, vx = 0, vy = P.v + 9, life = 3, k = "torpedo" } end
    elseif e.k == "dumper" then
        e.fire = e.fire - dt
        if e.fire <= 0 and abs(e.y - P.y) < 22 then e.fire = rr(1.2, 2); G.DROPS[#G.DROPS + 1] = { k = "barrel", x = e.x, y = e.y - 1.1, t = 0, v = e.v * 0.3 } end
    end
    e.x = e.x + clamp(tx - e.x, -1, 1) * 2.4 * dt + e.vx * dt
    e.vx = e.vx * (1 - min(1, dt * 3))
    e.y = e.y + e.v * dt
    if e.k ~= "heli" and not G.box_on(e.x, e.y, d, (e.k == "eboat" or e.k == "dumper") and "boat" or "car") then wreck(e, e.pushed and e.pushed > 0) end
    e.pushed = max(0, (e.pushed or 0) - dt)
end
------------------------------------------------------------------ main step
function G.drive_step(inp, dt)
    G.pt = G.pt + dt
    G.freeze = max(0, G.freeze - dt)
    if G.free > 0 then G.free = max(0, G.free - dt); if G.free == 0 then G.banner_set("Free Cars Over", 1.5) end end
    local d = pdim()
    if G.phase == "crash" then
        P.v = max(0, P.v - 30 * dt); P.y = P.y + P.v * dt
        if G.pt > 2.0 then
            if G.free <= 0 then
                if G.cars <= 0 then G.out = true; return end
                G.cars = G.cars - 1
            end
            -- a fresh car is set down in a lane: never on the median island (the old code used the centre line, which
            -- is grass wherever the road splits) and on a lane that stays clear for the protected roll-out ahead
            P.mode = G.mode_at(P.y)
            P.x, G.respawn_lane = safe_x(P.y, P.x, P.mode, 2.5 * 8 + 4)
            P.vx, P.v, P.alive, P.inv = 0, 8, true, 2.5
            G.phase = "drive"; G.pt = 0; G.cam_snap = true
            if G.on_respawn then G.on_respawn() end
        end
        return
    end
    if G.phase == "dock" then
        -- inside the weapons van
        local van = G.dock_van
        P.y = van.y; P.x = van.x; P.v = van.v
        van.y = van.y + van.v * dt
        if G.pt > 1.3 then
            G.weapon_i = G.weapon_i % 3 + 1
            P.weapon = WEAPS[G.weapon_i]; P.ammo = P.weapon == "missile" and 4 or 8
            P.y = van.y + 2.3; P.v = van.v + 6; P.inv = 1
            G.phase = "drive"; G.pt = 0; sfx("van"); G.banner_set(WNAME[P.weapon], 1.4)
            van.done = true
        end
        return
    end
    P.inv = max(0, P.inv - dt)
    -- throttle and steering
    if inp.my > 0 then P.v = min(VMAX, P.v + 13 * dt) elseif inp.my < 0 then P.v = max(VMIN, P.v - 22 * dt) end
    P.brk = inp.my < 0 and P.v > 6
    local steer = (3 + P.v * 0.18) * inp.mx
    P.vx = P.vx + (steer - P.vx) * min(1, dt * 10)
    P.x = P.x + P.vx * dt
    P.y = P.y + P.v * dt
    G.dist_acc = G.dist_acc + P.v * dt
    while G.dist_acc >= 1 do G.dist_acc = G.dist_acc - 1; add_pts(5) end
    -- car <-> boat at the boathouse. The swap is keyed to the vehicle's LEADING edge, not its centre: the surface test
    -- checks the box corners, so with a centre-keyed swap the car's nose reached the river (or the boat's bow reached
    -- the road) while still in the old mode, and you crashed / "drowned" on a perfectly clean run through the dock.
    -- The dock itself is valid for both, so after the swap the trailing corners are still on legal ground.
    local _, _, _, kfront = G.course(P.y + d[2] * 0.75)
    if kfront == "river" and P.mode == "car" then
        P.mode = "boat"; d = pdim(); P.swap_t = 0; sfx("splash")
        if G.on_swap then G.on_swap("boat") end
    elseif kfront ~= "river" and kfront ~= "dock" and P.mode == "boat" then
        P.mode = "car"; d = pdim(); P.swap_t = 0; sfx("dock")
        if G.on_swap then G.on_swap("car") end
    end
    local lap = 1 + floor(P.y / G.TOTAL)
    if lap ~= G.lap then G.lap = lap; G.set_season(lap); G.banner_set(({ "Summer", "Autumn", "Winter", "Spring" })[(lap - 1) % 4 + 1], 1.6) end
    -- leaving the road (or the river) wrecks the Interceptor
    if not box_on(P.x, P.y, d, P.mode) then
        if P.inv > 0 then local tx = safe_x(P.y, P.x, P.mode, 3); P.x = P.x + (tx - P.x) * min(1, dt * 4) else crash(); return end
    end
    -- weapons
    if inp.fire then fire_guns() end
    if inp.special then fire_special() end
    -- spawns
    G.spawn_t = G.spawn_t - dt
    local live = 0; for _, e in ipairs(G.EN) do if e.alive then live = live + 1 end end
    if G.spawn_t <= 0 and live < 7 then G.spawn_t = rr(1.0, 2.2) - min(0.6, P.y / 4000); spawn_traffic() end
    if P.y > G.van_at and P.mode == "car" then
        local _, _, _, k2 = G.course(P.y + 28)
        if k2 == "road" then G.van_at = P.y + rr(700, 900); local v = spawn("van", P.y + 28, 0.2, 9); if v then sfx("warn"); G.banner_set("Weapons Van", 1.2) end
        else G.van_at = P.y + 60 end
    end
    if P.y > G.heli_at and P.mode == "car" then G.heli_at = P.y + rr(500, 700); local h = spawn("heli", P.y + 14, 0, P.v); if h then h.x = P.x; sfx("heli"); G.banner_set("Mad Bomber", 1.2) end end
    -- enemies
    for _, e in ipairs(G.EN) do if e.alive then enemy_step(e, dt) end end
    -- vehicle contact: bumping trades sideways shoves; a car shoved off the road is wrecked (you get the points)
    for _, e in ipairs(G.EN) do
        if e.alive and e.k ~= "heli" and P.alive and P.inv <= 0 and overlap(P.x, P.y, d, e.x, e.y, DIM[e.k]) then
            if e.k == "van" then
                if P.y < e.y - 1.0 and abs(P.x - e.x) < 0.35 and not e.done then G.phase = "dock"; G.pt = 0; G.dock_van = e; sfx("dock"); return end
            end
            local side = (e.x > P.x) and 1 or -1
            local heavy = (e.k == "rl" or e.k == "truck" or e.k == "van") and 1.6 or 1
            e.vx = e.vx + side * 5 / heavy; P.vx = P.vx - side * 3 * heavy
            e.x = e.x + side * 0.06; P.x = P.x - side * 0.06
            if abs(P.y - e.y) > (d[2] + DIM[e.k][2]) * 0.8 then
                -- rear-ended: speeds swap a little
                if P.y < e.y then e.v = e.v + 2; P.v = P.v * 0.7 else P.v = P.v + 2; e.v = e.v * 0.7 end
            end
            e.pushed = 1.0
            if G.SHAKE_OK ~= false then G.shake = max(G.shake, 0.2) end
            sfx("hit")
        end
    end
    -- player shots (swept) and missiles
    for i = #G.SHOTS, 1, -1 do
        local s = G.SHOTS[i]
        s.py = s.y
        local sp = (s.k == "missile" and 30 or 44) + P.v
        if s.k == "missile" then
            -- missiles lock on to the Mad Bomber
            for _, e in ipairs(G.EN) do if e.alive and e.k == "heli" then s.x = s.x + clamp(e.x - s.x, -1, 1) * 6 * dt end end
            -- exhaust flame + smoke trail: G.sh_frame_fx
        end
        s.y = s.y + sp * dt; s.d = s.d + sp * dt
        local hit = false
        for _, e in ipairs(G.EN) do
            if e.alive and not hit then
                local ed = DIM[e.k] or DIM.civ
                if abs(s.x - e.x) < ed[1] + 0.05 and s.y > e.y - ed[2] and s.py < e.y + ed[2] then
                    if e.k == "heli" then if s.k == "missile" then e.alive = false; add_pts(PTS.heli); sfx("boom"); G.boom(WP(e.x, e.y, 3), true); hit = true end
                    elseif e.k == "van" then hit = true
                    else
                        hit = true
                        if s.k == "missile" then wreck(e, true)
                        elseif e.k == "rl" then G.sparks(WP(s.x, e.y - ed[2], 0.4), 4); sfx("hit")      -- Road Lord is bulletproof
                        else e.hp = e.hp - 1; G.sparks(WP(s.x, s.y, 0.4), 4); if e.hp <= 0 then wreck(e, true) else sfx("hit") end end
                    end
                end
            end
        end
        if hit or s.d > (s.k == "missile" and 30 or 16) then table.remove(G.SHOTS, i) end
    end
    -- enemy shots / torpedoes
    for i = #G.ESHOT, 1, -1 do
        local s = G.ESHOT[i]
        s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt; s.life = s.life - dt
        if P.alive and P.inv <= 0 and abs(s.x - P.x) < d[1] and abs(s.y - P.y) < d[2] then crash(); table.remove(G.ESHOT, i)
        elseif s.life <= 0 then table.remove(G.ESHOT, i) end
    end
    -- bombs from the helicopter
    for i = #G.BOMBS, 1, -1 do
        local b = G.BOMBS[i]
        b.t = b.t + dt; b.y = b.y + P.v * 0.2 * dt
        if b.t >= b.T then
            table.remove(G.BOMBS, i); sfx("boom"); G.boom(WP(b.x, b.y, 0.2), false)
            G.DROPS[#G.DROPS + 1] = { k = "crater", x = b.x, y = b.y, t = 0 }
            if P.alive and P.inv <= 0 and abs(b.x - P.x) < 0.7 and abs(b.y - P.y) < 0.9 then crash() end
        end
    end
    -- drops: oil and smoke catch enemies behind you, barrels and craters catch you
    for i = #G.DROPS, 1, -1 do
        local o = G.DROPS[i]
        o.t = o.t + dt
        if o.k == "barrel" then o.y = o.y + (o.v or 0) * dt end
        if o.k == "oil" or o.k == "smoke" then
            for _, e in ipairs(G.EN) do
                if e.alive and e.spin <= 0 and e.k ~= "heli" and e.k ~= "van" and abs(e.x - o.x) < (o.k == "smoke" and 1.2 or 0.8) and abs(e.y - o.y) < 1.2 then
                    e.spin = 2; e.vx = (rand() < 0.5 and -1 or 1) * rr(2.5, 4); e.pushed = 2
                end
            end
        elseif P.alive and P.inv <= 0 and abs(o.x - P.x) < d[1] + 0.25 and abs(o.y - P.y) < d[2] + 0.25 then
            if o.k == "barrel" then crash()
            elseif o.k == "crater" and P.mode == "car" then crash() end
        end
        if o.y < P.y - 14 or o.t > 20 then table.remove(G.DROPS, i) end
    end
    -- cull
    for i = #G.EN, 1, -1 do local e = G.EN[i]; if not e.alive or e.y < P.y - 16 or e.y > P.y + 45 then table.remove(G.EN, i) end end
end
G.boom_fx, G.spray, G.smoke, G.puff, G.sparks, G.boom, G.flash = boom, spray, smoke, puff, sparks, boom, flash
