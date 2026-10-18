------------------------------------------------------------------ stages: 32 (Midway) counting down to 1 (Tokyo)
local function stage_name(n)
    if n >= 29 then return "Midway" elseif n >= 25 then return "Marshall" elseif n >= 21 then return "Attu"
    elseif n >= 17 then return "Rabaul" elseif n >= 13 then return "Leyte" elseif n >= 9 then return "Saipan"
    elseif n >= 5 then return "Iwo Jima" elseif n >= 2 then return "Okinawa" end
    return "Tokyo"
end
local function is_boss(n) return n % 4 == 1 end            -- 29, 25, ... 5, 1: the Ayako heavy bomber
G.stage_name, G.is_boss = stage_name, is_boss
-- enemy kinds: radius list = collider circles {dx, dy, r} in field units (dy = along the nose)
local EK = {
    zero = { hp = 1, score = 50, circles = { { 0, 0.05, 0.55 }, { 0.62, 0.02, 0.3 }, { -0.62, 0.02, 0.3 } }, meshes = { "zero_body", "zero_cowl", "zero_glass", "zero_mark", "zero_prop" } },
    red  = { hp = 1, score = 100, circles = { { 0, 0.05, 0.55 }, { 0.62, 0.02, 0.3 }, { -0.62, 0.02, 0.3 } }, meshes = { "red_body", "zero_cowl", "zero_glass", "zero_mark", "zero_prop" } },
    mid  = { hp = 14, score = 1500, circles = { { 0, 0.1, 0.45 }, { 0, 1.0, 0.35 }, { 0, -1.0, 0.35 }, { 0.95, 0.3, 0.45 }, { -0.95, 0.3, 0.45 }, { 1.8, 0.1, 0.35 }, { -1.8, 0.1, 0.35 } },
             meshes = { "mid_body", "mid_glass", "mid_prop" } },
    big  = { hp = 150, score = 10000, circles = { { 0, 0.3, 0.75 }, { 0, 1.9, 0.6 }, { 0, -1.5, 0.6 }, { 1.6, 0.75, 0.55 }, { -1.6, 0.75, 0.55 }, { 3.0, 0.65, 0.5 }, { -3.0, 0.65, 0.5 },
             { 4.2, 0.25, 0.4 }, { -4.2, 0.25, 0.4 }, { 0, -2.75, 0.45 } }, meshes = { "big_body", "big_glass", "big_prop" } },
}
G.EK = EK
-- deterministic per-stage randomness (same waves every play, like the arcade)
local function lcg(seed) local s = seed % 2147483647; if s <= 0 then s = s + 2147483646 end
    return function(a, b) s = (s * 16807) % 2147483647; local u = (s - 1) / 2147483646; if a then return a + (b - a) * u end; return u end end
-- a wave spawns one or more planes: {t, kind, ai, x, y, h, v, extra...}
local function build_waves(k)                 -- k = 1 (stage 32) .. 32 (stage 1)
    local R = lcg(k * 7919 + 13)
    local W = {}
    local T = 56 + min(k, 16) * 1.25
    local t = 3.0
    local sp = 1 + min(k, 24) * 0.015
    local red_next, mid_next = 6 + R(0, 3), 14 + R(0, 4)
    local function add(o) W[#W + 1] = o end
    while t < T do
        if t >= red_next then
            local side = R() < 0.5 and -1 or 1
            local y0, A, f = R(17, 25), R(1.6, 2.4) * (R() < 0.5 and -1 or 1), R(1.2, 1.7)
            for i = 0, 4 do add({ t = t + i * 0.26, kind = "red", ai = "snake", x = side * 15, y = y0, h = -side * math.pi / 2, v = 9.5 * sp, A = A, f = f, grp = "r" .. k .. "_" .. floor(t) }) end
            red_next = t + R(9, 13); t = t + 2.4
        elseif k >= 2 and t >= mid_next then
            if R() < 0.6 then add({ t = t, kind = "mid", ai = "rise", x = R(-6, 6), y = -4, h = 0, v = 6.5 * sp })
            else add({ t = t, kind = "mid", ai = "sink", x = R(-7, 7), y = FH + 4, h = math.pi, v = 3.2 * sp }) end
            mid_next = t + R(15, 21) - min(k, 20) * 0.2; t = t + 2.2
        else
            local r = R()
            local nb = floor(2 + R(0, 1 + min(k, 20) * 0.08))
            if r < 0.28 then                                   -- dive at the player
                local x0 = R(-9, 9)
                for i = 0, nb - 1 do add({ t = t + i * 0.32, kind = "zero", ai = "dive", x = clamp(x0 + (i - nb / 2) * 2.1, -11, 11), y = FH + 2, h = math.pi, v = 10 * sp }) end
            elseif r < 0.5 then                                -- dive and loop
                local x0, dir = R(-7, 7), R() < 0.5 and -1 or 1
                for i = 0, nb - 1 do add({ t = t + i * 0.4, kind = "zero", ai = "loop", x = x0, y = FH + 2, h = math.pi, v = 9.5 * sp, ly = R(11, 16), dir = dir }) end
            elseif r < 0.68 then                               -- cross from a side, gently weaving
                local side, y0 = R() < 0.5 and -1 or 1, R(14, 26)
                for i = 0, nb do add({ t = t + i * 0.35, kind = "zero", ai = "cross", x = side * 15, y = y0, h = -side * math.pi / 2, v = 9 * sp }) end
            elseif r < 0.84 and k >= 2 then                    -- up from behind the player
                local x0 = R(-8, 8)
                for i = 0, nb - 1 do add({ t = t + i * 0.3, kind = "zero", ai = "behind", x = clamp(x0 + i * 1.8, -11, 11), y = -3, h = 0, v = 15 * sp }) end
            else                                               -- swoop across from a top corner
                local side = R() < 0.5 and -1 or 1
                for i = 0, nb - 1 do add({ t = t + i * 0.3, kind = "zero", ai = "swoop", x = side * 13, y = FH + 1, h = math.pi + side * 0.6, v = 10 * sp, w = -side * R(0.55, 0.8) }) end
            end
            t = t + R(1.5, 2.4) - min(k, 20) * 0.025
        end
    end
    return W, T
end
G.build_waves = build_waves
local POWSEQ = { "red", "green", "gray", "white", "yellow", "red", "orange", "green", "white", "gray", "yellow", "orange" }
G.POWSEQ = POWSEQ
