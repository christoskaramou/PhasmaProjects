------------------------------------------------------------------ course height field
-- cells[j*nx+i+1] = { h00, h10, h01, h11 } (corners (i,j) (i+1,j) (i,j+1) (i+1,j+1)) or false (void)
local R = 0.45
G.R = R
local function parse(c)
    local cells, lo = {}, 1e9
    for j, row in ipairs(c.rows) do
        local i = 0
        for cell in (row .. ";"):gmatch("([^;]*);") do
            if cell == "x" then cells[(j - 1) * c.nx + i + 1] = false
            else
                local a, b, d, e = cell:match("([^,]+),([^,]+),([^,]+),([^,]+)")
                local h = { tonumber(a), tonumber(b), tonumber(d), tonumber(e) }
                cells[(j - 1) * c.nx + i + 1] = h
                for q = 1, 4 do lo = min(lo, h[q]) end
            end
            i = i + 1
        end
    end
    c.cells, c.lo = cells, lo
end
for _, c in ipairs(COURSES) do parse(c) end
G.COURSES = COURSES
local CUR
-- height + gradient at (x, z); nil over void
local function hgt(x, z)
    local i, j = floor(x), floor(z)
    if i < 0 or j < 0 or i >= CUR.nx or j >= CUR.nz then return nil end
    local h = CUR.cells[j * CUR.nx + i + 1]
    if not h then return nil end
    local u, v = x - i, z - j
    local a = h[1] + (h[2] - h[1]) * u
    local b = h[3] + (h[4] - h[3]) * u
    local y = a + (b - a) * v
    local gx = (h[2] - h[1]) * (1 - v) + (h[4] - h[3]) * v
    local gz = b - a
    return y, gx, gz
end
G.hgt = hgt
------------------------------------------------------------------ state
local M = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, air = false, alive = true, roll = 0, head = 0, squash = 1 }
G.M = M
G.EN = {}
local G0 = 24          -- gravity
local ROLLK = 5 / 7    -- rolling solid sphere
local STEP = 0.32      -- a rise taller than this above the ball's base is a wall
local BREAK_DROP = 4.6 -- falls longer than this shatter the marble
local MAXV = 15
-- marble orientation as a 3x3 rotation matrix (rows), integrated from the rolling motion every step:
-- rolling without slipping spins the ball about (up x velocity) by |v| dt / R. Rendering slerps the last step.
M.rot = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }; M.prot = M.rot; M.wax, M.waz, M.wang = 1, 0, 0
local function mrot_axis(ax, ay, az, a)
    local c, s, t = cos(a), sin(a), 1 - cos(a)
    return { t * ax * ax + c, t * ax * ay - s * az, t * ax * az + s * ay,
             t * ax * ay + s * az, t * ay * ay + c, t * ay * az - s * ax,
             t * ax * az - s * ay, t * ay * az + s * ax, t * az * az + c }
end
local function mmul(A, B)
    local C = {}
    for r = 0, 2 do for c = 0, 2 do C[r * 3 + c + 1] = A[r * 3 + 1] * B[c + 1] + A[r * 3 + 2] * B[c + 4] + A[r * 3 + 3] * B[c + 7] end end
    return C
end
G.mrot_axis, G.mmul = mrot_axis, mmul
local function orient_step(dt)
    M.prot = M.rot
    local sp = sqrt(M.vx * M.vx + M.vz * M.vz)
    if sp > 1e-4 then
        local ax, az = M.vz / sp, -M.vx / sp          -- up x v
        local a = sp * dt / R
        if M.air then a = a * 0.98 end                 -- keeps spinning in the air
        M.wax, M.waz, M.wang = ax, az, a
        local Rm = mmul(mrot_axis(ax, 0, az, a), M.rot)
        -- re-orthonormalise occasionally against drift
        M.nrm = (M.nrm or 0) + 1
        if M.nrm > 120 then
            M.nrm = 0
            local function nz(a1, a2, a3) local l = sqrt(a1 * a1 + a2 * a2 + a3 * a3); return a1 / l, a2 / l, a3 / l end
            local x1, x2, x3 = nz(Rm[1], Rm[4], Rm[7]); local y1, y2, y3 = Rm[2], Rm[5], Rm[8]
            local d = x1 * y1 + x2 * y2 + x3 * y3; y1, y2, y3 = nz(y1 - d * x1, y2 - d * x2, y3 - d * x3)
            local z1, z2, z3 = x2 * y3 - x3 * y2, x3 * y1 - x1 * y3, x1 * y2 - x2 * y1
            Rm = { x1, y1, z1, x2, y2, z2, x3, y3, z3 }
        end
        M.rot = Rm
    else M.wang = 0 end
end
local function place(x, z)
    local y = hgt(x, z) or 0
    M.x, M.z, M.y = x, z, y + R
    M.ox, M.oy, M.oz = nil, nil, nil
    M.prot, M.wang = M.rot, 0          -- no leftover spin from the last step (it would be re-applied every frame)
    M.vx, M.vy, M.vz = 0, 0, 0
    M.air, M.alive, M.squash, M.dissolve = false, true, 1, 0
    M.fall_y = M.y
end
G.place = function(x, z) place(x, z) end
local function load_course(k)
    G.ci = k; CUR = COURSES[k]; G.CUR = CUR
    G.time = (G.carry or 0) + CUR.time
    G.check = 1; G.minz = CUR.start[2]
    place(CUR.start[1], CUR.start[2])
    G.EN = {}
    for _, e in ipairs(CUR.enemies) do
        local n = { k = e.k, t = 0 }
        if e.k == "steelie" then n.x, n.z, n.hx, n.hz, n.vx, n.vz = e.x, e.z, e.x, e.z, 0, 0; n.y = (hgt(e.x, e.z) or 0) + R
        elseif e.k == "muncher" then n.x, n.z, n.hx, n.hz, n.hop = e.x, e.z, e.x, e.z, 0
        elseif e.k == "acid" then n.path, n.v, n.s, n.dir = e.path, e.v, 0, 1; n.x, n.z = e.path[1][1], e.path[1][2]
        elseif e.k == "hammer" then n.x, n.z, n.per, n.ph = e.x, e.z, e.per, e.ph; n.drop = 0 end
        G.EN[#G.EN + 1] = n
    end
    G.phase = "ready"; G.pt = 0; G.dead = nil
    M.inv = 0; G.safe_log = {}; G.race_t = 0; G.safe_tick = 0
    G.banner_set(CUR.name, 2.2)
end
G.load_course = load_course
function G.new_game_sim()
    G.score = 0; G.carry = 0; G.won = false; G.time_up = false
    load_course(1)
end

------------------------------------------------------------------ deaths
local PROBE = false   -- true while safe_point test-rolls an idle marble (no deaths, sounds or particles)
local PROBE_DEAD = false
local function kill(kind)
    if PROBE then PROBE_DEAD = true; return end
    if not M.alive then return end
    -- respawn grace: enemies and hazards can't kill a freshly respawned marble (falls still count)
    if (M.inv or 0) > 0 and (kind == "munch" or kind == "acid" or kind == "slam") then return end
    M.alive = false; G.dead = { t = 0, kind = kind }; G.deaths = (G.deaths or 0) + 1
    local p = vec3(M.x, M.y, M.z)
    if kind == "break" then sfx("break"); G.shatter(p); G.shake = 0.5
    elseif kind == "fall" then sfx("fall")
    elseif kind == "acid" then sfx("splat"); G.goo(p)
    elseif kind == "munch" then sfx("munch"); G.goo(p)
    elseif kind == "slam" then sfx("slam"); G.dust(p, 14); G.shake = 0.6 end
end
------------------------------------------------------------------ safe respawn
-- The marble used to respawn exactly on the last checkpoint. Some checkpoints sit inside an enemy's reach (Aerial
-- Race: the Marble Muncher coils 1.1 m from checkpoint 7; Ultimate Race: two munchers 0.5-1 m from theirs, and an
-- acid slime patrols straight across another), so the marble reappeared in the jaws and died again, forever.
-- Now a respawn point must be solid, level-ish ground with no drop nearby, connected to the checkpoint, and clear of
-- every hazard's reach; enemies near it are sent home; and the marble gets 2.5 s of invulnerability.
local INV_T = 2.5
local ground_move, air_move   -- defined below (marble physics); safe_point test-rolls with them
local function seg_dist(px, pz, a, b)
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local t = clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / max(dx * dx + dz * dz, 1e-6), 0, 1)
    return sqrt((px - a[1] - t * dx) ^ 2 + (pz - a[2] - t * dz) ^ 2)
end
-- clearance from every hazard: strict = outside a muncher's whole hunting range (it chases up to 3 m from home and
-- bites within 0.75 m), relaxed = only clear of where things are now (used if no strict point exists nearby)
local function hazard_clear(x, z, strict)
    for _, e in ipairs(G.EN) do
        if e.k == "muncher" then
            if sqrt((x - e.hx) ^ 2 + (z - e.hz) ^ 2) < (strict and 4.3 or 2.6) then return false end
            if sqrt((x - e.x) ^ 2 + (z - e.z) ^ 2) < 2.6 then return false end
        elseif e.k == "acid" then
            if seg_dist(x, z, e.path[1], e.path[2]) < (strict and 2.0 or 1.4) then return false end
        elseif e.k == "hammer" then
            if max(abs(x - e.x), abs(z - e.z)) < (strict and 1.9 or 1.5) then return false end
        elseif e.k == "steelie" then
            if sqrt((x - e.hx) ^ 2 + (z - e.hz) ^ 2) < (strict and 3.0 or 1.2) then return false end
        end
    end
    return true
end
-- solid ground: floor all round the ball (no edge within 0.9 m (a 2-wide bridge still counts)), no wall step, gentle slope
local function ground_ok(x, z, maxg)
    local y, gx, gz = hgt(x, z)
    if not y then return false end
    maxg = maxg or 0.45
    if abs(gx) > maxg or abs(gz) > maxg then return false end
    for k = 0, 7 do
        local a = k * PI / 4
        for _, r in ipairs({ 0.5, 0.9 }) do
            local h = hgt(x + cos(a) * r, z + sin(a) * r)
            if not h or abs(h - y) > STEP then return false end
        end
    end
    return true
end
-- the checkpoint can be rolled to from here: walk the straight line from the candidate (x0, z0) to the checkpoint and
-- require floor all the way, no wall-sized rise, and no drop that would shatter the marble (Aerial Race drops 1.2 m
-- from its ramp onto the snake's platform, so the upstream ramp counts as connected)
local function connected(x0, z0, x1, z1)
    -- flood fill over cells (4-neighbours, centre to centre) from the candidate's cell to the checkpoint's cell
    local i0, j0, i1, j1 = floor(x0), floor(z0), floor(x1), floor(z1)
    if not hgt(i0 + 0.5, j0 + 0.5) then return false end
    local seen, q, h = { [j0 * 1000 + i0] = true }, { { i0, j0 } }, 1
    while h <= #q and #q < 600 do
        local i, j = q[h][1], q[h][2]; h = h + 1
        if i == i1 and j == j1 then return true end
        local y = hgt(i + 0.5, j + 0.5)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local ni, nj = i + d[1], j + d[2]
            if not seen[nj * 1000 + ni] and abs(ni - i0) + abs(nj - j0) <= 14 then
                local ny = hgt(ni + 0.5, nj + 0.5)
                if ny and ny - y <= STEP + 0.05 and y - ny <= 3 then seen[nj * 1000 + ni] = true; q[#q + 1] = { ni, nj } end
            end
        end
    end
    return false
end
-- would a marble left alone here stay safe? Roll it with the real physics for 3.5 s, no input: it must not fall,
-- shatter or roll into a hazard's reach, and must end on solid ground (Aerial Race: the spot behind the snake is a
-- ramp that drops the marble onto the snake's platform and then off its far side)
local function idle_safe(x, z)
    local keep = {}
    for _, k in ipairs({ "x", "y", "z", "vx", "vy", "vz", "air", "fall_y" }) do keep[k] = M[k] end
    PROBE, PROBE_DEAD = true, false
    M.x, M.z = x, z; M.y = (hgt(x, z) or 0) + R; M.vx, M.vy, M.vz, M.air, M.fall_y = 0, 0, 0, false, M.y
    local ok = true
    for _ = 1, 420 do
        if M.air then air_move(1 / 120, 0, 0) else ground_move(1 / 120, 0, 0) end
        if PROBE_DEAD or (not M.air and not hazard_clear(M.x, M.z, false)) then ok = false; break end
    end
    if ok then ok = not M.air and ground_ok(M.x, M.z) and hazard_clear(M.x, M.z, true) end
    PROBE = false
    for k, v in pairs(keep) do M[k] = v end
    return ok
end
G.idle_safe = idle_safe
-- good = strict hazard clearance, an idle marble stays safe there, and not ahead of the checkpoint (a respawn
-- shouldn't skip the marble past the hazard that killed it); otherwise the best fallback is returned with good = false
local function safe_point(ci, good_only)
    local c = CUR.checks[ci]
    local cands = {}
    for _, strict in ipairs({ true, false }) do
        for r = 0, 7, 0.5 do
            local nrm = max(1, floor(r * 2 * PI / 0.6))
            for k = 0, nrm - 1 do
                local a = k * 2 * PI / nrm
                local x, z = c[1] + cos(a) * r, c[2] + sin(a) * r
                if ground_ok(x, z) and hazard_clear(x, z, strict) and connected(x, z, c[1], c[2]) then
                    local _, gx, gz = hgt(x, z)
                    local ahead = z < c[2] - 0.5
                    cands[#cands + 1] = { x, z, strict = strict, ahead = ahead, sc = r + (ahead and 6 or 0) + (abs(gx) + abs(gz)) * 3 + (strict and 0 or 20) }
                end
            end
        end
    end
    table.sort(cands, function(p, q) return p.sc < q.sc end)
    local fb
    for i, p in ipairs(cands) do
        if i > 80 then break end
        local idle = idle_safe(p[1], p[2])
        if p.strict and not p.ahead and idle then return p[1], p[2], true end
        if not fb and idle then fb = p end
    end
    if good_only then return nil end
    fb = fb or cands[1]
    if fb then return fb[1], fb[2], false end
    return nil
end
G.safe_point = safe_point
local function respawn()
    -- newest recorded safe spot (logged while rolling, at least 1 s before the death), else the checkpoint search;
    -- fall back to earlier checkpoints if a checkpoint has no safe ground at all
    local x, z, how
    local log = G.safe_log or {}
    for i = #log, 1, -1 do
        local p = log[i]
        if G.race_t - p.t > 1.0 and ground_ok(p.x, p.z) and hazard_clear(p.x, p.z, true) and idle_safe(p.x, p.z) then x, z, how = p.x, p.z, "last safe spot"; break end
    end
    -- else the latest checkpoint with a good spot near it (flat, clear, not past the hazard); else the best fallback
    if not x then
        for ci = G.check, 1, -1 do
            local sx, sz = safe_point(ci, true)
            if sx then x, z, how = sx, sz, "checkpoint " .. ci; break end
        end
    end
    if not x then
        local sx, sz = safe_point(G.check)
        if sx then x, z, how = sx, sz, "checkpoint " .. G.check .. " (fallback)" end
    end
    if not x then local c = CUR.checks[G.check]; x, z, how = c[1], c[2], "checkpoint (raw)" end
    place(x, z); G.dead = nil; sfx("hop")
    M.inv = INV_T; G.respawn_info = how
    -- enemies near the respawn or its checkpoint go back home (steelies stop dead), so nothing is waiting there
    local c = CUR.checks[G.check]
    for _, e in ipairs(G.EN) do
        local d = min(sqrt((e.x - x) ^ 2 + (e.z - z) ^ 2), sqrt((e.x - c[1]) ^ 2 + (e.z - c[2]) ^ 2))
        if (e.k == "muncher" or e.k == "steelie") and d < 8 then
            e.x, e.z = e.hx, e.hz; e.ox, e.oz = e.x, e.z
            if e.k == "steelie" then e.vx, e.vz = 0, 0; e.y = (hgt(e.x, e.z) or e.y - R) + R; e.oy = e.y end
        end
    end
    G.safe_log = {}
end
G.respawn = function() respawn() end
G.kill = function(k) kill(k) end

------------------------------------------------------------------ marble physics
function ground_move(dt, ax, az)
    local y, gx, gz = hgt(M.x, M.z)
    if not y then M.air = true; return end
    local gs = CUR.gravity
    -- slope acceleration of a rolling ball (Silly Race: gravity pulls you UP the slopes)
    local den = 1 + gx * gx + gz * gz
    ax = ax - G0 * ROLLK * gs * gx / den
    az = az - G0 * ROLLK * gs * gz / den
    M.vx = M.vx + ax * dt; M.vz = M.vz + az * dt
    local fr = 1 - min(1, 0.35 * dt)
    M.vx, M.vz = M.vx * fr, M.vz * fr
    local sp = sqrt(M.vx * M.vx + M.vz * M.vz)
    if sp > MAXV then M.vx, M.vz = M.vx / sp * MAXV, M.vz / sp * MAXV end
    -- per-axis wall test against the next surface
    local base = M.y - R
    local nx, nz = M.x + M.vx * dt, M.z + M.vz * dt
    local function blocked(px, pz)
        local hy = hgt(px + (px > M.x and R * 0.6 or (px < M.x and -R * 0.6 or 0)), pz + (pz > M.z and R * 0.6 or (pz < M.z and -R * 0.6 or 0)))
        return hy and hy > base + STEP
    end
    local hit = false
    if blocked(nx, M.z) then nx = M.x; if abs(M.vx) > 2 then hit = true end; M.vx = -M.vx * 0.4 end
    if blocked(nx, nz) then nz = M.z; if abs(M.vz) > 2 then hit = true end; M.vz = -M.vz * 0.4 end
    if hit and not PROBE then sfx("bump"); G.sparks(vec3(M.x, M.y, M.z), 6) end
    M.x, M.z = nx, nz
    local y2, gx2, gz2 = hgt(M.x, M.z)
    if not y2 or y2 < base - 0.5 then
        -- launched off an edge: keep the slope's vertical velocity
        M.air = true; M.vy = M.vx * gx + M.vz * gz; M.fall_y = M.y
    else
        M.vy = M.vx * gx2 + M.vz * gz2
        M.y = y2 + R
    end
end
function air_move(dt, ax, az)
    M.vx = M.vx + ax * 0.25 * dt; M.vz = M.vz + az * 0.25 * dt
    M.vy = M.vy - G0 * dt
    local base = M.y - R
    local nx, nz = M.x + M.vx * dt, M.z + M.vz * dt
    local hx = hgt(nx, M.z); if hx and hx > base + STEP then nx = M.x; M.vx = -M.vx * 0.3 end
    local hz = hgt(nx, nz); if hz and hz > base + STEP then nz = M.z; M.vz = -M.vz * 0.3 end
    M.x, M.z = nx, nz
    M.y = M.y + M.vy * dt
    M.fall_y = max(M.fall_y, M.y)
    local y = hgt(M.x, M.z)
    if y and M.y - R <= y then
        local drop = M.fall_y - M.y
        M.y = y + R
        if drop > BREAK_DROP then kill("break"); return end
        if drop > 0.8 and not PROBE then sfx("clack"); G.dust(vec3(M.x, y + 0.05, M.z), 5) end
        M.air = false; M.vy = 0
    elseif M.y < CUR.lo - 8 then kill("fall") end
end

------------------------------------------------------------------ enemies
local function enemies_step(dt)
    for _, e in ipairs(G.EN) do
        e.ox, e.oy, e.oz = e.x, e.y, e.z
        e.t = e.t + dt
        if e.k == "steelie" then
            -- chases the marble when close, otherwise drifts home
            local tx, tz = M.x, M.z
            local dx, dz = tx - e.x, tz - e.z
            local d = sqrt(dx * dx + dz * dz)
            if d > 9 or not M.alive or (M.inv or 0) > 0 then tx, tz = e.hx, e.hz; dx, dz = tx - e.x, tz - e.z; d = sqrt(dx * dx + dz * dz) end
            if d > 0.05 then e.vx = e.vx + dx / d * 7 * dt; e.vz = e.vz + dz / d * 7 * dt end
            local fr = 1 - min(1, 1.2 * dt); e.vx, e.vz = e.vx * fr, e.vz * fr
            local nx, nz = e.x + e.vx * dt, e.z + e.vz * dt
            local hy = hgt(nx, nz); local cy = hgt(e.x, e.z) or hy
            if hy and cy and abs(hy - cy) < STEP then e.x, e.z = nx, nz else e.vx, e.vz = -e.vx * 0.5, -e.vz * 0.5 end
            e.y = (hgt(e.x, e.z) or e.y - R) + R
            e.roll = (e.roll or 0) + sqrt(e.vx * e.vx + e.vz * e.vz) * dt / R
            -- collide with the marble: heavier steelie, elastic push
            if M.alive and not M.air and (M.inv or 0) <= 0 then   -- a respawning marble is a ghost to steelies
                local cx, cz = M.x - e.x, M.z - e.z
                local cd = sqrt(cx * cx + cz * cz)
                if cd < 2 * R and cd > 1e-4 then
                    local nxx, nzz = cx / cd, cz / cd
                    local rel = (M.vx - e.vx) * nxx + (M.vz - e.vz) * nzz
                    if rel < 0 then
                        M.vx = M.vx - 1.6 * rel * nxx; M.vz = M.vz - 1.6 * rel * nzz
                        e.vx = e.vx + 0.4 * rel * nxx; e.vz = e.vz + 0.4 * rel * nzz
                        sfx("clack"); G.sparks(vec3(e.x + nxx * R, e.y, e.z + nzz * R), 8)
                    end
                    local push = 2 * R - cd
                    M.x, M.z = M.x + nxx * push * 0.8, M.z + nzz * push * 0.8
                    e.x, e.z = e.x - nxx * push * 0.2, e.z - nzz * push * 0.2
                end
            end
        elseif e.k == "muncher" then
            -- Marble Muncher: hops toward the marble when it comes close
            e.hop = (e.hop + dt * 2.4) % 1
            local dx, dz = M.x - e.x, M.z - e.z
            local d = sqrt(dx * dx + dz * dz)
            local hd = sqrt((e.x - e.hx) ^ 2 + (e.z - e.hz) ^ 2)
            if M.alive and (M.inv or 0) <= 0 and d < 4.5 and d > 0.1 and hd < 3 then e.x, e.z = e.x + dx / d * 1.6 * dt, e.z + dz / d * 1.6 * dt
            elseif hd > 0.1 then e.x, e.z = e.x + (e.hx - e.x) * dt, e.z + (e.hz - e.z) * dt end
            if e.hop < dt * 2.4 then sfx("hop") end
            if M.alive and d < 0.75 and M.y - R < (hgt(e.x, e.z) or 0) + 0.9 then kill("munch") end
        elseif e.k == "acid" then
            local a, b = e.path[1], e.path[2]
            local L = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
            e.s = e.s + e.dir * e.v * dt / L
            if e.s > 1 then e.s, e.dir = 1, -1 elseif e.s < 0 then e.s, e.dir = 0, 1 end
            e.x, e.z = lerp(a[1], b[1], e.s), lerp(a[2], b[2], e.s)
            local d = sqrt((M.x - e.x) ^ 2 + (M.z - e.z) ^ 2)
            if M.alive and not M.air and d < 0.85 then kill("acid") end
        elseif e.k == "hammer" then
            -- raised, then a quick slam (12% of the cycle), then a slow lift
            local c = ((e.t + e.ph) / e.per) % 1
            local was = e.drop
            if c < 0.7 then e.drop = 0 elseif c < 0.78 then e.drop = (c - 0.7) / 0.08 elseif c < 0.9 then e.drop = 1 else e.drop = 1 - (c - 0.9) / 0.1 end
            if was < 1 and e.drop >= 1 then sfx("slam"); G.dust(vec3(e.x, (hgt(e.x, e.z) or 0) + 0.1, e.z), 8) end
            local d = max(abs(M.x - e.x), abs(M.z - e.z))
            if M.alive and e.drop > 0.85 and d < 0.75 + R * 0.5 then kill("slam") end
        end
    end
end

------------------------------------------------------------------ course step
-- The renderer draws every moving thing between its previous and current step (AL = leftover fraction of a step).
-- Any step that does NOT integrate something must collapse that interpolation to the current state, otherwise the
-- stale "previous" values keep being blended in with a different AL every frame and the object trembles in place.
local function hold_marble()
    M.ox, M.oy, M.oz = M.x, M.y, M.z
    M.prot, M.wang = M.rot, 0
end
local function hold_enemies() for _, e in ipairs(G.EN) do e.ox, e.oy, e.oz = e.x, e.y, e.z end end
G.hold_marble = hold_marble
-- after the goal line the marble coasts to a stop on the goal pad instead of freezing mid-roll
local function goal_coast(dt)
    M.ox, M.oy, M.oz = M.x, M.y, M.z
    if M.air or not M.alive then hold_marble(); return end
    local k = math.exp(-4.5 * dt)
    M.vx, M.vz = M.vx * k, M.vz * k
    local g = CUR.goal
    local nx, nz = M.x + M.vx * dt, M.z + M.vz * dt
    if (nx < g[1] + R and M.vx < 0) or (nx > g[3] - R and M.vx > 0) then M.vx = 0 end   -- stay on the pad
    if (nz < g[2] + R and M.vz < 0) or (nz > g[4] - R and M.vz > 0) then M.vz = 0 end
    if M.vx * M.vx + M.vz * M.vz < 1e-4 then M.vx, M.vz = 0, 0 end
    ground_move(dt, 0, 0)
    M.vx, M.vz = M.vx * k, M.vz * k
    if M.air then M.air = false; M.y = (hgt(M.x, M.z) or M.y - R) + R; M.vy = 0 end
    orient_step(dt)
    if M.vx == 0 and M.vz == 0 then M.prot, M.wang = M.rot, 0 end
end
function G.course_step(inp, dt)
    G.pt = G.pt + dt
    if G.phase == "ready" then
        hold_marble()
        if G.pt > 1.6 then G.phase = "race"; G.pt = 0; sfx("go"); G.music_race() end
        enemies_step(dt); return
    end
    if G.phase == "goal" then
        goal_coast(dt); hold_enemies()
        if G.pt > 3.2 then
            if G.ci >= #COURSES then G.won = true; G.finished = true
            else G.carry = G.carry_next; load_course(G.ci + 1) end
        end
        return
    end
    if G.phase == "timeup" then hold_marble(); hold_enemies(); if G.pt > 2.4 then G.finished = true end; return end
    -- clock (keeps running while the marble is broken)
    local before = math.ceil(G.time)
    G.time = G.time - dt
    if math.ceil(G.time) ~= before and G.time < 10 and G.time > 0 then sfx("tick") end
    if G.time <= 0 then G.time = 0; G.phase = "timeup"; G.pt = 0; sfx("timeup"); G.banner_set("Time Out", 2.4); return end
    enemies_step(dt)
    if not M.alive then
        hold_marble()
        G.dead.t = G.dead.t + dt
        if G.dead.t > 2 then respawn() end
        return
    end
    M.ox, M.oy, M.oz = M.x, M.y, M.z
    G.race_t = (G.race_t or 0) + dt
    M.inv = max(0, (M.inv or 0) - dt)
    -- remember where the marble was recently safe (on the ground, away from edges and every hazard's reach)
    G.safe_tick = (G.safe_tick or 0) - dt
    if G.safe_tick <= 0 and not M.air then
        G.safe_tick = 0.25
        if ground_ok(M.x, M.z) and hazard_clear(M.x, M.z, true) then
            local log = G.safe_log; log[#log + 1] = { x = M.x, z = M.z, t = G.race_t }
            if #log > 24 then table.remove(log, 1) end
        end
    end
    local ax, az = inp.ax * 16, inp.az * 16
    local n = 2
    for _ = 1, n do
        if not M.alive then break end
        if M.air then air_move(dt / n, ax, az) else ground_move(dt / n, ax, az) end
    end
    local sp = sqrt(M.vx * M.vx + M.vz * M.vz)
    if M.alive then orient_step(dt) end
    M.roll = (M.roll + sp * dt / R * 57.2958) % 360
    if sp > 0.3 then M.head = math.deg(atan2(M.vx, M.vz)) end
    G.speed = sp
    -- progress points and checkpoints
    if M.z < G.minz - 1 then local d = floor(G.minz - M.z); G.minz = G.minz - d; add_score(10 * d * G.ci) end
    local nc = CUR.checks[G.check + 1]
    if nc and (M.x - nc[1]) ^ 2 + (M.z - nc[2]) ^ 2 < 9 then G.check = G.check + 1 end
    -- goal
    local g = CUR.goal
    if M.x >= g[1] and M.x <= g[3] and M.z >= g[2] and M.z <= g[4] and not M.air then
        G.phase = "goal"; G.pt = 0
        local left = floor(G.time)
        G.bonus = left * 100 * G.ci; add_score(G.bonus); G.carry_next = left
        sfx("goal"); G.banner_set("Goal!", 3)
        G.flash(vec3(M.x, M.y + 2, M.z), { 1, .9, .6 }, 60, 0.6, 9)
    end
end
G.shatter, G.sparks, G.goo, G.dust, G.flash = shatter, sparks, goo, dust, flash
