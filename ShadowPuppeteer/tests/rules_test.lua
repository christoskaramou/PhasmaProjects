-- luajit tests/rules_test.lua   (run from the ShadowPuppeteer folder)
-- The rules (Assets/Scripts/puppet_rules.lua) in minimal scenes, then on the reference level:
-- walk pace, step up, turn at a wall, fall and land (and on a paper-thin ledge: no tunnelling), climb a ladder shadow
-- and step off its top, thorns, falling off the paper, lifted by rising ground, pushed by ground moving into its side,
-- crushed between ground and ground above, door, bonus star, candle; the same input gives the same result at 30, 60
-- and 144 fps; a scripted drag wins the reference level and doing nothing loses it; the rules' ground equals the
-- drawn shadow cards vertex for vertex at 20 random settings; no NaN and no tunnelling when the lantern is thrown
-- across its whole range every frame.
local D = assert(loadfile("Assets/Scripts/sp_data.lua"))()
local R = assert(loadfile("Assets/Scripts/puppet_rules.lua"))()
local RU = D.RULES
local abs, fails = math.abs, 0
local function check(cond, msg) if not cond then error("FAIL: " .. msg, 2) end end
local function near(a, b, tol) return abs(a - b) <= (tol or 1e-6) end

-- A minimal scene: fixed rectangles (solids), a box prop (its shadow is a box), optional thorns and ladder.
local function rect(x0, y0, x1, y1) return { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } } end
local LX, LY = 0.0, -1.2                                           -- lantern for the minimal scenes
local function prop_box(w, h, y) return { y = y or 0.0, silhouette = { rect(-w / 2, 0, w / 2, h) }, x = { -9, 9 } } end
local function scene(o)
    return R.level(D, { solids = o.solids or { rect(-2.5, -0.5, 2.5, 0.2) }, thorns = o.thorns or {}, props = o.props or {},
        kinds = o.kinds or {}, door = o.door or { 99, 99 }, star = o.star or false,
        start = { puppet = o.start or { -1.0, 0.2 }, dir = o.dir or 1 } })
end
local function run(L, seconds, input, fps)
    local S = R.new_state(L)
    input = input or function() return { lantern = { LX, LY } } end
    fps = fps or 120
    for _ = 1, math.floor(seconds * fps + 0.5) do
        R.update(L, S, 1 / fps, input)
        if S.dead or S.won then break end
    end
    return S
end
local function has(S, e) for _, v in ipairs(S.events) do if v.e == e then return v.t end end end
-- anchor x that puts a prop's shadow centre at screen u
local function ax_for(u, py, lx, ly) local k = (D.SY - ly) / (py - ly); return lx + (u - lx) / k end
-- The highest ground top under the drawn shoe (legs together: the shin's width round x; 9 samples) at or below y + up.
local SHOE = D.PUPPET.shin_w * D.PUPPET.scale
local function shoe_top(G, x, y, up)
    local best
    for k = -4, 4 do
        local iv = R.column(G.solids, x + SHOE * k / 4)
        for i = 2, #iv, 2 do if iv[i] <= y + up and (not best or iv[i] > best) then best = iv[i] end end
    end
    return best
end

local T = {}
T[#T + 1] = { "walks right at a steady pace", function()
    local S = run(scene({}), 2.0)
    check(S.mode == "walk" and near(S.x, -1.0 + 2.0 * RU.walk, 1e-4) and near(S.y, 0.2), "steady pace: x " .. S.x)
end }
T[#T + 1] = { "steps up a rise no taller than a step", function()
    local L = scene({ solids = { rect(-2.5, -0.5, 2.5, 0.2), rect(-0.8, 0.2, 2.5, 0.2 + RU.step * 0.8) } })
    local S = run(L, 2.0)
    check(near(S.y, 0.2 + RU.step * 0.8) and S.x > -0.6 and not has(S, "turn"), "step up: y " .. S.y)
end }
T[#T + 1] = { "turns round at anything taller", function()
    local L = scene({ solids = { rect(-2.5, -0.5, 2.5, 0.2), rect(-0.8, 0.2, 2.5, 0.2 + RU.step * 1.3) } })
    local S = run(L, 2.0)
    check(has(S, "turn") and S.dir == -1 and S.x < -0.8 and near(S.y, 0.2), "turn at a wall")
end }
T[#T + 1] = { "walks down a slope on its feet (never held up by the ground behind it)", function()
    -- a 50 degree slope falling to the right, as the side of the cup's shadow
    local L = scene({ solids = { { { -2.5, -0.5 }, { -0.8, -0.5 }, { -0.8, 0.2 }, { -2.5, 0.2 } },
        { { -0.8, -0.5 }, { -0.3, -0.5 }, { -0.3, 0.0 }, { -0.8, 0.2 } }, rect(-2.5, -0.5, 2.5, -0.4) }, start = { -1.0, 0.2 } })
    local S = R.new_state(L)
    local inp = { lantern = { LX, LY } }
    local walked = 0
    for _ = 1, 120 * 4 do
        R.step(L, S, inp)
        if S.mode == "walk" and S.x > -0.75 and S.x < -0.35 then
            walked = walked + 1
            local t = R.support_top(L, S, inp)
            check(t and near(t, S.y, 1e-6), string.format("held off the slope at x %.3f: y %.4f ground %s", S.x, S.y, tostring(t)))
        end
    end
    check(walked > 50, "walked down the slope")
end }
T[#T + 1] = { "on a steep (55 degree) downhill slope its shoe stays on the ground", function()
    -- the shoe touches: the highest ground under the drawn shoe is within 2 px (0.0063) of the feet, never above them
    -- by more. (Live run 2026-11-13: support columns wider than the shoe held it 7-19 px above the cup shadow's side.)
    local L = scene({ solids = { { { -2.5, -0.5 }, { -0.8, -0.5 }, { -0.8, 0.2 }, { -2.5, 0.2 } },
        { { -0.8, -0.5 }, { -0.5, -0.5 }, { -0.5, -0.2284 }, { -0.8, 0.2 } }, rect(-2.5, -0.5, 2.5, -0.4) }, start = { -1.0, 0.2 } })
    local S = R.new_state(L)
    local inp = { lantern = { LX, LY } }
    local G = R.ground(L, inp)
    local walked = 0
    for _ = 1, 120 * 4 do
        R.step(L, S, inp)
        if S.mode == "walk" and S.x > -0.79 and S.x < -0.52 then
            walked = walked + 1
            local top = shoe_top(G, S.x, S.y, 0.05)
            check(top and abs(top - S.y) <= 0.0063, string.format("shoe %.4f off the slope at x %.3f", S.y - (top or -9), S.x))
        end
    end
    check(walked > 20, "walked down the slope (" .. walked .. " steps)")
end }
T[#T + 1] = { "slides down a slope too steep to stand on (75 degrees), attached to it, then stands", function()
    -- the cup shadow's side near the thorns (live run 2026-11-13: it stood upright beside the face on its heel's corner)
    local L = scene({ solids = { { { -2.5, -0.5 }, { -0.8, -0.5 }, { -0.8, 0.2 }, { -2.5, 0.2 } },
        { { -0.8, -0.5 }, { -0.7, -0.5 }, { -0.7, -0.1732 }, { -0.8, 0.2 } }, rect(-2.5, -0.5, 2.5, -0.4) }, start = { -1.0, 0.2 } })
    local S = R.new_state(L)
    local inp = { lantern = { LX, LY } }
    local G = R.ground(L, inp)
    local slid, stood_on_face, fell_on_face = 0, 0, 0
    for _ = 1, 120 * 4 do
        R.step(L, S, inp)
        if S.mode == "fall" and S.x < -0.705 then fell_on_face = fell_on_face + 1 end
        if S.mode == "slide" then
            slid = slid + 1
            local top = R.column(G.solids, S.x)                -- its centre is on the face, not its heel's corner
            local tt
            for i = 2, #top, 2 do if top[i] <= S.y + 1e-6 then tt = top[i] end end
            check(tt and near(tt, S.y, 1e-6), string.format("slide off the face at x %.3f: y %.4f top %s", S.x, S.y, tostring(tt)))
            check(S.slope and S.slope > 55, "slide slope " .. tostring(S.slope))
        elseif S.mode == "walk" and S.x > -0.79 and S.x < -0.71 then
            stood_on_face = stood_on_face + 1                  -- standing on the face itself: the old hovering pose
        end
    end
    check(slid > 20, "slid down the face (" .. slid .. " steps)")
    check(stood_on_face <= 2, "stood on the 75 degree face for " .. stood_on_face .. " steps")
    check(fell_on_face == 0, "no fall/land cycle on the face (" .. fell_on_face .. " falling steps)")
    -- it slid the whole face: from its top edge to its foot at x -0.7 (then a drop taller than a step)
    local t0 = has(S, "slide")
    check(t0 and t0 < 1.0 and S.x > -0.705, "slid from the top edge to the foot of the face")
end }
T[#T + 1] = { "a steep lip shorter than a step (5 cm at 75 degrees) is stepped down, not slid", function()
    -- the ledge's chamfer, a rung's edge (live 2026-11-13: a slide pose leaned along a face that was not there)
    local L = scene({ solids = { { { -2.5, -0.5 }, { -0.8, -0.5 }, { -0.8, 0.2 }, { -2.5, 0.2 } },
        { { -0.8, -0.5 }, { 2.5, -0.5 }, { 2.5, 0.15 }, { -0.7866, 0.15 }, { -0.8, 0.2 } } }, start = { -1.0, 0.2 } })
    local S = run(L, 2.0)
    check(not has(S, "slide") and S.x > -0.6 and near(S.y, 0.15, 1e-6), "stepped down the lip and walked on")
end }
T[#T + 1] = { "a steep slope's slide never flickers back to walking (hysteresis) and agrees with the drawn face", function()
    -- a 62 degree face: in slide the whole way down, every step's contact on the polygon edge itself
    local L = scene({ solids = { { { -2.5, -0.5 }, { -0.8, -0.5 }, { -0.8, 0.2 }, { -2.5, 0.2 } },
        { { -0.8, -0.5 }, { -0.4, -0.5 }, { -0.4, -0.5524 + 0.0 }, { -0.8, 0.2 } }, rect(-2.5, -0.5, 2.5, -0.4) }, start = { -1.0, 0.2 } })
    local S = R.new_state(L)
    local inp = { lantern = { LX, LY } }
    local changes, last = 0, nil
    for _ = 1, 120 * 5 do
        R.step(L, S, inp)
        if S.mode ~= last then changes = changes + 1; last = S.mode end
        if S.mode == "slide" then
            local v = 0.2 - (S.x + 0.8) * math.tan(math.rad(62))   -- the face's own line
            check(abs(v - S.y) < 1e-4, string.format("contact %.5f off the face line at x %.3f", S.y - v, S.x))
        end
    end
    local n = 0
    for _, v in ipairs(S.events) do if v.e == "slide" or v.e == "stand" then n = n + 1 end end
    check(changes <= 3 and n <= 2, "walk -> slide -> walk once, not " .. changes .. " mode changes / " .. n .. " slide-stand events")
end }
T[#T + 1] = { "climbs a ladder shadow in its middle", function()
    local ly = LY
    local lad = { y = 0.0, silhouette = { rect(-0.12, 0, -0.1, 0.6), rect(0.1, 0, 0.12, 0.6), rect(-0.12, 0.3, 0.12, 0.32) }, x = { -9, 9 } }
    local ax = ax_for(-0.5, 0.0, LX, ly)
    local inp = { lantern = { LX, ly }, ladder = ax }
    local L = scene({ props = { ladder = lad }, kinds = { ladder = "ladder" } })
    local b = R.ground(L, inp).ladders[1]
    local cx = (b.x0 + b.x1) / 2
    local S = R.new_state(L)
    local climbed = 0
    for _ = 1, 120 * 8 do
        R.step(L, S, inp)
        if S.mode == "climb" then
            climbed = climbed + 1
            check(abs(S.x - cx) <= 0.002, string.format("climbs at x %.4f, the ladder's middle is %.4f", S.x, cx))
        end
    end
    check(climbed > 60, "climbed (" .. climbed .. " steps)")
end }
T[#T + 1] = { "falls when unsupported and lands (gravity)", function()
    local L = scene({ solids = { rect(-2.5, -0.5, -0.9, 0.6), rect(-2.5, -0.5, 2.5, 0.0) }, start = { -1.0, 0.6 } })
    local S = run(L, 3.0)
    local tf, tl = has(S, "fall"), has(S, "land")
    check(tf and tl and near(S.y, 0.0), "fall and land")
    local drop = 0.6 - 0.0
    check(abs((tl - tf) - math.sqrt(2 * drop / RU.gravity)) < 0.05, "fall time obeys gravity: " .. (tl - tf))
end }
T[#T + 1] = { "lands on a paper-thin ledge at full speed (no tunnelling)", function()
    local L = scene({ solids = { rect(-2.5, 2.0, -0.95, 2.05), rect(-0.9, 0.300, 2.5, 0.302), rect(-2.5, -0.5, 2.5, -0.4) },
        start = { -1.0, 2.05 } })
    local S = run(L, 3.0)
    check(near(S.y, 0.302, 1e-4) and has(S, "land"), "thin ledge caught: y " .. S.y)
end }
T[#T + 1] = { "climbs a ladder shadow it walks into and steps off its top", function()
    local ly = LY
    local lad = { y = 0.0, silhouette = { rect(-0.12, 0, -0.1, 0.6), rect(0.1, 0, 0.12, 0.6), rect(-0.12, 0.3, 0.12, 0.32) }, x = { -9, 9 } }
    local ax = ax_for(-0.5, 0.0, LX, ly)
    local top = D.LZ + (D.SY - ly) / (0.0 - ly) * (0.6 - D.LZ)
    local L = scene({ props = { ladder = lad }, kinds = { ladder = "ladder" },
        solids = { rect(-2.5, -0.5, 2.5, 0.2), rect(-0.3, top - 0.05, 2.5, top - 0.02) } })
    local S = run(L, 12.0, function() return { lantern = { LX, ly }, ladder = ax } end)
    check(has(S, "climb") and has(S, "top"), "climbed")
    check(near(S.y, top - 0.02, 1e-4) and S.x > -0.2, "stepped off onto the ledge: x " .. S.x .. " y " .. S.y)
end }
T[#T + 1] = { "dies on thorns", function()
    local L = scene({ thorns = { rect(-0.5, 0.2, -0.3, 0.3) } })
    local S = run(L, 4.0)
    check(S.dead == "thorns", "thorns kill: " .. tostring(S.dead))
end }
T[#T + 1] = { "dies falling off the bottom of the paper", function()
    local L = scene({ solids = { rect(-2.5, -0.5, -0.8, 0.2) } })
    local S = run(L, 4.0)
    check(S.dead == "fell", "fell off: " .. tostring(S.dead))
end }
T[#T + 1] = { "is lifted by ground rising under it", function()
    -- a wide box shadow under the puppet; the lantern coming nearer grows it upward through the puppet's feet
    local box = prop_box(1.6, 0.2, 0.0)
    local L = scene({ props = { box = box }, solids = { rect(-2.5, -0.5, 2.5, 0.15) }, start = { -0.2, 0.15 } })
    L.rules = setmetatable({ walk = 0 }, { __index = RU })
    local function inp(t)
        local ly = -1.2 + math.min(1, t / 2) * 0.45
        return { lantern = { LX, ly }, box = ax_for(-0.2, 0.0, LX, ly) }
    end
    local S = run(L, 3.0, inp)
    local top = D.LZ + (D.SY + 0.75) / 0.75 * (0.2 - D.LZ)
    check(S.mode == "walk" and near(S.y, top, 1e-6), "lifted to the box top " .. top .. ": " .. S.y .. " " .. S.mode)
end }
T[#T + 1] = { "is pushed by ground moving into its side", function()
    local box = prop_box(0.2, 0.4, 0.0)
    local L = scene({ props = { box = box } })
    L.rules = setmetatable({ walk = 0 }, { __index = RU })
    local x0 = -1.0
    local function inp(t) return { lantern = { LX, LY }, box = ax_for(x0 + 0.6 - t * 0.5, 0.0, LX, LY) } end
    local S = run(L, 1.5, inp)
    check(not S.dead and S.x < x0 - 0.1 and R.body_free(L, S, inp(S.t - RU.dt)), "pushed aside: x " .. S.x)
end }
T[#T + 1] = { "is crushed between rising ground and ground above", function()
    local box = prop_box(2.0, 0.3, 0.0)
    local L = scene({ props = { box = box }, solids = { rect(-2.5, -0.5, 2.5, 0.0), rect(-2.5, 0.45, 2.5, 0.6) },
        start = { -0.2, 0.0 } })
    L.rules = setmetatable({ walk = 0 }, { __index = RU })
    local function inp(t)
        local ly = -1.2 + math.min(1, t / 2) * 0.45
        return { lantern = { LX, ly }, box = ax_for(-0.2, 0.0, LX, ly) }
    end
    local S = run(L, 3.0, inp)
    check(S.dead == "crushed", "crushed: " .. tostring(S.dead))
end }
T[#T + 1] = { "reaching the door wins", function()
    local S = run(scene({ door = { -0.5, 0.2 } }), 4.0)
    check(S.won and S.mode == "won", "door")
end }
T[#T + 1] = { "touching the bonus star collects it", function()
    local S = run(scene({ star = { -0.6, 0.35 } }), 3.0)
    check(S.star and has(S, "star"), "star")
end }
T[#T + 1] = { "the candle burning down loses", function()
    local L = scene({})
    L.rules = setmetatable({ candle_s = 1.0, walk = 0 }, { __index = RU })
    local S = run(L, 2.0)
    check(S.dead == "candle" and near(S.t, 1.0, RU.dt + 1e-9), "candle")
end }

-- The reference level.
local A, st = D.STATE_A, D.LEVEL.start
local function read_asset(p) local f = io.open("Assets/" .. p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local SCR = assert(loadfile("Assets/Scripts/puppet_scripts.lua"))()(D, read_asset)    -- the same scripts the live runs use
local REFL = R.level(D)
local nothing, scripted = SCR.for_level(REFL, "nothing"), SCR.for_level(REFL, "win")
T[#T + 1] = { "the same input gives the same result at 30, 60 and 144 fps", function()
    local res = {}
    for _, fps in ipairs({ 30, 60, 144 }) do
        local L = R.level(D)
        local S = R.new_state(L)
        local steps = 0
        -- the scripted drag, then the lantern keeps swaying while the puppet rides the shadows (lift, step, fall)
        local function sway(t)
            local i = scripted(t)
            if t > 4 then i.lantern = { i.lantern[1] + 0.05 * math.sin(t * 4.1), i.lantern[2] + 0.04 * math.sin(t * 2.3) } end
            return i
        end
        while S.n < 120 * 20 and not (S.dead or S.won) do R.update(L, S, 1 / fps, sway) end
        -- compare at the same simulated step
        res[#res + 1] = S
    end
    for i = 2, 3 do
        check(res[i].x == res[1].x and res[i].y == res[1].y and res[i].mode == res[1].mode and res[i].dir == res[1].dir,
            string.format("fps result differs: %.9f,%.9f vs %.9f,%.9f", res[i].x, res[i].y, res[1].x, res[1].y))
        check(#res[i].events == #res[1].events, "event count differs")
    end
end }
T[#T + 1] = { "a scripted drag wins the reference level, doing nothing loses it", function()
    local L = R.level(D)
    local S = run(L, 60, scripted, 60)
    check(S.won, "scripted input wins: " .. tostring(S.dead) .. " at " .. S.t)
    local S2 = run(L, 60, nothing, 60)
    check(not S2.won and S2.dead ~= nil, "doing nothing loses")
end }
T[#T + 1] = { "the rules' ground is the drawn shadow, vertex for vertex (20 random settings)", function()
    -- the view module under minimal stubs: its shadow card transform applied to the shared silhouettes
    _G.vec3 = function(x, y, z) return { x = x, y = y, z = z } end
    _G.vec4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
    local W = assert(loadfile("Assets/Scripts/puppet_world.lua"))()(D)
    local L = R.level(D, { props = D.PROPS, solids = {}, thorns = {}, star = false, door = { 9, 9 } })   -- every prop
    math.randomseed(11)
    for i = 1, 20 do
        local lx = D.LANTERN_X[1] + math.random() * (D.LANTERN_X[2] - D.LANTERN_X[1])
        local ly = D.LANTERN_Y[1] + math.random() * (D.LANTERN_Y[2] - D.LANTERN_Y[1])
        for name, p in pairs(D.PROPS) do
            local ax = p.x[1] + math.random() * (p.x[2] - p.x[1])
            local az = p.z and p.z[1] + math.random() * (p.z[2] - p.z[1]) or 0     -- the balloon's height
            local left = p.silhouette_l ~= nil and i % 2 == 0                        -- the mouse running back
            local cx, cy, k = W.shadow_card(name, ax, lx, ly, az)
            local polys = R.shadow_polys(L, name, ax, lx, ly, az, left)
            for j, poly in ipairs(left and p.silhouette_l or p.silhouette) do
                for m, q in ipairs(poly) do
                    local du, dv = cx + k * q[1], cy + k * q[2]
                    check(near(du, polys[j][m][1], 1e-9) and near(dv, polys[j][m][2], 1e-9),
                        string.format("setting %d %s vertex %d.%d: drawn (%.6f, %.6f) rules (%.6f, %.6f)", i, name, j, m, du, dv,
                            polys[j][m][1], polys[j][m][2]))
                end
            end
        end
    end
end }
T[#T + 1] = { "no NaN and no tunnelling when the lantern crosses its whole range every frame", function()
    local L = R.level(D)
    local S = R.new_state(L)
    local frame = 0
    local function wild(t)
        local f = math.floor(t * 60)
        local e = f % 2 == 0
        return { lantern = { e and D.LANTERN_X[1] or D.LANTERN_X[2], e and D.LANTERN_Y[1] or D.LANTERN_Y[2] },
            cup = e and D.PROPS.cup.x[1] or D.PROPS.cup.x[2], comb = e and D.PROPS.comb.x[2] or D.PROPS.comb.x[1],
            ladder = A.ladder }
    end
    for f = 1, 60 * 20 do
        R.update(L, S, 1 / 60, wild)
        check(S.x == S.x and S.y == S.y and abs(S.x) < 10 and abs(S.y) < 10, "NaN or runaway at frame " .. f)
        if S.dead or S.won then break end
        check(R.body_free(L, S, wild(S.n * RU.dt - RU.dt)), string.format("inside the ground at frame %d (x %.3f y %.3f %s)", f, S.x, S.y, S.mode))
        frame = f
    end
    check(frame > 60 or S.dead == "crushed" or S.dead == "thorns" or S.dead == "fell", "ended sanely: " .. tostring(S.dead))
end }

T[#T + 1] = { "walks over a rounded summit (a balloon's top) without turning back", function()
    -- the raised balloon's envelope: a half ellipse 0.546 wide, 0.33 tall (2026-11-13: the summit, between the samples
    -- ahead and under a heel, met the body test as a wall: the puppet turned on top of the balloon)
    local arc = {}
    for i = 0, 24 do
        local a = math.pi - math.pi * i / 24
        arc[#arc + 1] = { 0.273 * math.cos(a), 1.32 + 0.33 * math.sin(a) }
    end
    arc[#arc + 1] = { 0.273, 1.0 }
    arc[#arc + 1] = { -0.273, 1.0 }
    local x0 = -0.15
    local L = scene({ solids = { arc, rect(-2.5, -0.5, 2.5, -0.4) }, start = { x0, 1.32 + 0.33 * math.sqrt(1 - (x0 / 0.273) ^ 2) } })
    local S = run(L, 1.2)
    check(not has(S, "turn"), string.format("turned on the summit at %.2f s (x %.3f)", has(S, "turn") or -1, S.x))
    check(S.x > 0.08, string.format("walked over the summit: x %.3f", S.x))
end }
T[#T + 1] = { "ground rising under a sliding puppet lifts it, still sliding (no walk/slide flicker)", function()
    -- a 70 degree face 0.6 tall on a prop at the paper plane (shadow = silhouette), raised 0.3 / s from 1.5 s while the
    -- puppet slides down it (2026-11-13: the lift switched it to walk, the walk back to slide, every step)
    local wedge = { { -0.9, 0.0 }, { 0.118, 0.0 }, { -0.1, 0.6 }, { -0.9, 0.6 } }
    local L = R.level(D, { solids = { rect(-2.5, -0.5, 2.5, -0.4) }, thorns = {}, door = { 99, 99 }, star = false,
        props = { lifter = { y = D.SY, silhouette = { wedge }, x = { -9, 9 }, z = { 0, 5 } } },
        kinds = { lifter = "solid" }, moves = { lifter = "z" }, cfg = { lifter = { x = 0.0 } },
        start = { puppet = { -0.5, 0.6 }, dir = 1 } })
    local function inp(t) return { lantern = { LX, LY }, lifter = math.max(0, t - 1.5) * 0.3 } end
    local S = R.new_state(L)
    local slid = 0
    for _ = 1, 120 * 3 do
        R.update(L, S, 1 / 120, inp)
        if S.mode == "slide" and S.t > 1.5 then slid = slid + 1 end
        if S.dead then break end
    end
    local starts = 0                     -- each "slide" event starts a slide (its sound, its pose): one for one face
    for _, e in ipairs(S.events) do if e.e == "slide" then starts = starts + 1 end end
    check(slid > 10, "slid down the face while it rose")
    check(starts <= 1, string.format("the slide restarted %d times while the face rose (walk/slide flicker)", starts))
end }

T[#T + 1] = { "walking over the clockwork mouse's key and onto its back: no slide/stand flicker", function()
    -- level 2-3's mouse shadow (its real silhouette and projection: lantern (0.104, -0.972), anchor 0.118); the puppet
    -- drops from a ledge onto the key's upper lobe and walks over the stem onto the dome (2026-11-13: slide, stand,
    -- slide, stand every 50-75 ms there: the pose and the slide sound flickered)
    local L = R.level(D, { solids = { rect(-2.5, -0.5, -0.56, 0.36), rect(-2.5, -0.5, 2.5, -0.4) }, thorns = {},
        door = { 99, 99 }, star = false, props = { mouse = D.PROPS.mouse }, kinds = { mouse = "solid" },
        moves = { mouse = "x" }, start = { puppet = { -1.0, 0.36 }, dir = 1 } })
    local S = R.new_state(L)
    local inp = { lantern = { 0.1042, -0.9716 }, mouse = 0.118 }
    for _ = 1, 120 * 5 do R.step(L, S, inp); if S.dead then break end end
    local lastslide, worst, n = nil, 9, 0
    for _, e in ipairs(S.events) do
        if e.e == "slide" then
            n = n + 1
            if lastslide then worst = math.min(worst, e.t - lastslide) end
            lastslide = e.t
        end
    end
    check(S.x > -0.2 and not S.dead, string.format("walked over the key onto the mouse (x %.3f, %s)", S.x, tostring(S.dead)))
    check(n >= 1, "it slid off a lobe (the case is reproduced)")
    check(worst >= 0.3, string.format("slides restarted %.3f s apart (flicker)", worst))
end }

T[#T + 1] = { "every level: its scripted solution wins (no twitching), doing nothing loses", function()
    local maps = {}
    for _, lv in ipairs(D.LEVELS) do
        local L = R.level(D, lv.id)
        local sol = SCR.for_level(L, "solution")
        check(sol, "level " .. lv.id .. " has no solution in puppet_solutions.lua")
        local S = R.new_state(L)
        while not S.dead and not S.won and S.t < 120 do R.update(L, S, 1 / 60, sol) end
        check(S.won, string.format("level %s: the solution does not win (%s at %.2f s)", lv.id, tostring(S.dead), S.t))
        local last, jit = -9, 0
        for _, e in ipairs(S.events) do if e.e == "turn" then if e.t - last < 0.6 then jit = jit + 1 end; last = e.t end end
        check(jit == 0, "level " .. lv.id .. ": the solution traps the puppet turning " .. jit .. " times")
        local N = R.new_state(L)
        local nothing_ = SCR.for_level(L, "nothing")
        while not N.dead and not N.won and N.t < 120 do R.update(L, N, 1 / 60, nothing_) end
        check(N.dead and not N.won, "level " .. lv.id .. ": doing nothing does not lose")
        maps[lv.map] = (maps[lv.map] or 0) + 1
    end
    for _, m in ipairs(D.MAPS) do check((maps[m.id] or 0) >= 3, "stage set " .. m.id .. " has fewer than 3 levels") end
end }

T[#T + 1] = { "a near-vertical face is a wall: no ratcheting up it a few cm a step", function()
    -- an 86 degree face (level 3-3's block side): the leading edge always finds ground within a step above, and the
    -- puppet used to stand on it there and climb, floating off the face, onto the high block (solver, 2026-11-13)
    local face = { { 0.0, -0.5 }, { 0.0, 0.0 }, { 0.04, 0.55 }, { 0.6, 0.55 }, { 0.6, -0.5 } }
    local L = scene({ solids = { face, rect(-2.5, -0.5, 2.5, 0.0) }, start = { -0.4, 0.0 } })
    local S = run(L, 6)
    check(S.y < 0.12, string.format("climbed the face to y %.3f", S.y))
    check(has(S, "turn"), "it turned at the face")
end }

local passed = 0
for _, t in ipairs(T) do
    local ok, err = pcall(t[2])
    if ok then passed = passed + 1; print("ok    " .. t[1])
    else fails = fails + 1; print("FAIL  " .. t[1] .. ": " .. tostring(err)) end
end
print(string.format("rules_test: %d passed, %d failed", passed, fails))
if fails > 0 then os.exit(1) end
