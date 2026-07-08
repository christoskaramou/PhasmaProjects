-- lab.lua — Ylem Lab. Synthesize a TARGET (element or molecule) by coalescing real
-- particles through valid processes. The full periodic table (Z 1..118) is both the
-- target space and the board that fills in as you discover.
--
-- MODEL: the atom's rings are PERIODS (table rows). Ring caps {2,8,8,18,18,32,32} close
-- at cumulative 2,10,18,36,54,86,118 — exactly the noble gases — so "fill a ring -> lock
-- gold" stays correct across all 118 elements (see data.lua). The atom grows one ring per
-- period as Z climbs.
--
-- LOOP: a target card names what to make (random, escalating, or a molecule). Build the
-- nucleus (protons/neutrons) + electrons; reach the target -> SYNTHESIZED, tap for the
-- next. Trays: proton | neutron | electron. Neutron capture + beta decay is the real
-- climb up the table; unstable isotopes tremble + decay (stabilize before the tick to
-- QUENCH). Coalesce a hydrogen into the atom to bond (H2 / H2O). Everything past Bismuth
-- (Z>83) is radioactive and alpha-decays back toward lead. Realism deepens from here
-- (fusion, proton capture, real chemical reactions + catalysts).
--
-- The engine reports drag state but never moves a widget, so each tray is a draggable
-- quad polled with get_state; the in-flight particle is our own quad following the cursor.
-- Coords are absolute surface pixels.

local M = {}

local data = (function()
    local src = fs.read("Scripts/data.lua")
    if not src then error("[lab] data.lua not found at Scripts/data.lua") end
    return load(src, "@Scripts/data.lua", "t", _ENV)()
end)()

local SCREEN = "ylem"
local TAU = math.pi * 2.0

-- Tunables ------------------------------------------------------------------
local CATCH_DUR = 0.55  -- electron spiral-in
local PCATCH_DUR = 0.30 -- proton / neutron pull-into-nucleus
local WIND = 1.15       -- turns the electron winds while spiralling in
local FLARE_DUR = 0.55  -- shell-ring flare decay
local SW_DUR = 0.70     -- shockwave lifetime
local FLASH_DUR = 0.45  -- nucleus flash on a nucleon landing
local HOLD_DUR = 0.75   -- the "everything stills and glows" beat on completion
local WOB_FREQ = 26.0
local WOB_DAMP = 9.0
local CARD_HOLD = 4.0
local CARD_SLIDE = 0.42
local DECAY_BASE = 2.6  -- seconds an unstable isotope trembles before it decays
local DECAY_MIN = 0.9   -- ...floor (further from stability decays faster)
local TOAST_DUR = 3.0   -- decay toast on-screen time
local EMIT_DUR = 0.9    -- emitted decay particle lifetime
local BOND_DUR = 0.85   -- coalesce animation (two atoms -> molecule)

local SFX_TICK = "e_tick.wav"
local SFX_LOCK = "shell_lock.wav"
local SFX_THUMP = "p_thump.wav"
local SFX_CARD = "birth.wav"
local function sfx(path)
    if audio and audio.play then audio.play(path) end
end

-- Palette (all {r,g,b,a}; image_tint multiplies the white sprite) --------------
local C_BG       = { 0.030, 0.040, 0.060, 1.0 }
local C_PROTON   = { 1.00, 0.46, 0.32, 1.0 }
local C_NEUTRON  = { 0.74, 0.78, 0.85, 1.0 }
local C_NUCGLOW  = { 1.00, 0.52, 0.36, 0.22 }
local C_ELEC     = { 0.64, 0.87, 1.00, 1.0 }
local C_ELECGLW  = { 0.40, 0.72, 1.00, 0.20 }
local C_POSITRON = { 1.00, 0.55, 0.88, 1.0 }
local C_RING     = { 0.34, 0.55, 0.92, 1.0 }
local C_LOCK     = { 1.00, 0.82, 0.34, 1.0 }
local C_SLOT     = { 0.55, 0.78, 1.00, 1.0 }
local C_UNSTABLE = { 1.00, 0.42, 0.32, 1.0 }
local C_HINT     = { 0.66, 0.74, 0.86, 0.55 }
local C_DIMTEXT  = { 0.55, 0.60, 0.70, 1.0 }
local RING_PEAK  = 0.78
local NUC_MAX_DOTS = 28  -- past this a heavy nucleus draws a solid core + a scatter of dots
local E_MAX_PER_RING = 12 -- cap electron dots per ring (perf: heavy atoms have up to 32)
local E_GLOW_MAX = 18     -- drop the per-electron soft glow once the atom has more e- than this
local CATALYSTS = { "spark", "heat", "pressure", "Fe", "Ni" } -- the lab's real helpers (toggle chips)

-- Small math helpers --------------------------------------------------------
local function clamp01(t) return t < 0.0 and 0.0 or (t > 1.0 and 1.0 or t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function ease_out(t) return 1.0 - (1.0 - t) * (1.0 - t) end
local function sign(x) return x < 0.0 and -1.0 or 1.0 end
local function wrap_pi(a) return (a + math.pi) % TAU - math.pi end
local function col(c, a) return { c[1], c[2], c[3], a or c[4] } end

-- Atom queries --------------------------------------------------------------
local function electrons()
    local n = 0
    for _, sh in ipairs(M.atom.shells) do n = n + #sh.e end
    return n
end
local function is_neutral() return electrons() == M.atom.protons end
local function element() return data.get(M.atom.protons) end
local function mass() return M.atom.protons + M.atom.neutrons end
local function is_stable_iso() return data.is_stable(M.atom.protons, M.atom.neutrons) end
local function can_add_proton() return M.atom.protons < data.MAX_Z end
local function can_add_electron() return electrons() < M.atom.protons end
local function can_add_neutron()
    if M.atom.protons < 1 then return false end
    local _, hi = data.stable_span(M.atom.protons)
    return M.atom.neutrons < hi + 3
end
local function iso_name() return string.format("%s-%d", element().sym, mass()) end

-- how far outside the stable band (0 = stable); drives tremble + decay speed. Elements
-- with no stable isotope (Z>83) are always unstable — the radioactive endgame.
local function instability()
    local z, n = M.atom.protons, M.atom.neutrons
    if not data.has_stable(z) then return 1 + math.abs(n - data.principal(z)) end
    local lo, hi = data.stable_span(z)
    if n > hi then return n - hi elseif n < lo then return lo - n end
    return 0
end

-- "stabilize-the-decay": would dropping one <kind> particle land the nucleus on a STABLE
-- isotope? Lets the UI hint the save move under the decay clock. For a proton we preview
-- on_proton_added's auto-accrete so the hint matches what happens.
local function stabilizes(kind)
    local z, n = M.atom.protons, M.atom.neutrons
    if kind == "n" then
        return data.is_stable(z, n + 1)
    elseif kind == "p" then
        if z >= data.MAX_Z then return false end
        return data.is_stable(z + 1, math.max(n, data.principal(z + 1)))
    end
    return false
end

-- the valid-process chemistry layer: when a MOLECULE target is active and you've built
-- its core element (neutral + stable), the reaction to make it becomes available. It only
-- FIRES when its real catalyst + condition are present (see reqs_met). Returns the reaction
-- table or nil.
local function reaction_kind()
    if M.molecule or M.bonding then return nil end
    if not is_neutral() then return nil end
    if not (M.target and M.target.kind == "mol") then return nil end
    local lo, hi = data.stable_span(M.atom.protons)
    if M.atom.neutrons < lo or M.atom.neutrons > hi then return nil end -- can't react an unstable atom
    local el = element()
    local r = el and data.reactions[M.target.key]
    if r and r.core == el.sym then return r end
    return nil
end

local function reqs_of(r)
    local q = {}
    if r.cat then q[#q + 1] = r.cat end
    if r.cond then q[#q + 1] = r.cond end
    return q
end

local function reqs_met(r)
    for _, k in ipairs(reqs_of(r)) do if not M.cat[k] then return false end end
    return true
end

local function target_shell()
    for si, sh in ipairs(M.atom.shells) do
        if #sh.e < sh.cap then return si end
    end
    return nil
end

-- State ---------------------------------------------------------------------
local RING_SPIN = { 0.90, -0.58, 0.72, -0.46, 0.60, -0.40, 0.52 }
local function build_rings()
    local shells = {}
    for i, cap in ipairs(data.SHELLS) do
        shells[i] = { cap = cap, spin = RING_SPIN[i] or 0.5, phase = i * 1.1,
            flare = 0.0, locked = false, e = {} }
    end
    shells[1].e = { { spread = 0.0 } } -- open on hydrogen: one electron already in orbit
    return shells
end

-- reset just the atom + its transient effects (a fresh synthesis run); keep the target,
-- the discovered board, and the session stats.
local function reset_atom()
    M.atom = { protons = 1, neutrons = 0, shells = build_rings() }
    M.fly = nil
    M.sw = nil
    M.card = nil
    M.toast = nil
    M.decay = nil
    M.emit = nil
    M.molecule = nil
    M.bonding = nil
    M.hold = 0.0
    M.flash = 0.0
    M.wob = { t = 999.0, amp = 0.0, dx = 1.0, dy = 0.0 }
    M.acted = false
    M.won = false
    M.held_id = nil
    M.hold_t = 0.0
    M.stream_acc = 0.0
    M.efill = 0.0
end

function M.reset()
    reset_atom()
    M.discovered = { [1] = true }
    M.stats = { decays = 0, quenched = 0 }
    M.clock = 0.0
    M.tcount = 0
    M.goalflash = 0.0
    M.gtoast = nil
    M.cat = {} -- active catalysts / conditions (the toggle chips)
    M.carded = { [1] = true } -- elements whose birth card was shown (H is the starting point)
    M.target = { kind = "el", z = 2 } -- first target: Helium (teaches proton + shell-lock)
end

local function target_label()
    if not M.target then return "?" end
    if M.target.kind == "mol" then
        local m = data.molecules[M.target.key]
        return m and (m.sym .. "  " .. m.name) or "?"
    end
    local e = data.get(M.target.z)
    return e and (e.sym .. "  " .. e.name) or "?"
end

-- pick the next target and start a fresh atom. Range widens with progress so early
-- targets are reachable; once a few are done, occasionally ask for a molecule.
local function new_target()
    M.tcount = (M.tcount or 0) + 1
    local cap = math.min(data.MAX_Z, 8 + M.tcount * 2)
    -- molecules whose core element is reachable within the current range
    local mols = {}
    for key, r in pairs(data.reactions) do
        if r.core_z <= cap then mols[#mols + 1] = key end
    end
    if M.tcount >= 3 and #mols > 0 and math.random() < 0.28 then
        M.target = { kind = "mol", key = mols[math.random(#mols)] }
    else
        M.target = { kind = "el", z = math.random(2, cap) }
    end
    reset_atom()
end

local function check_target()
    if not M.target or M.won then return end
    local hit = false
    if M.target.kind == "el" then
        hit = is_neutral() and M.atom.protons == M.target.z
    else
        hit = M.molecule ~= nil and M.molecule.kind == M.target.key
    end
    if hit then
        M.won = true
        M.goalflash = 1.0
        M.gtoast = { msg = "SYNTHESIZED   " .. target_label(), age = 0.0 }
        if M.target.kind == "el" then M.discovered[M.target.z] = true end
        sfx(SFX_CARD)
    end
end

function M.init()
    runtime_ui.clear(SCREEN)
    runtime_ui.set_screen_overlay(SCREEN, true)
    runtime_ui.show(SCREEN)
    if os and os.time then math.randomseed(os.time()) end
    M.reset()
    M._prev = {}
    M._live = {}
    M.g = {}
end

-- Draw plumbing -------------------------------------------------------------
local function quad(id, opts)
    M._live[id] = true
    runtime_ui.set_quad(SCREEN, id, opts)
end

local function dot(id, x, y, d, c, z)
    quad(id, {
        x = x - d * 0.5, y = y - d * 0.5, width = d, height = d, z = z or 30.0,
        style = "image", path = "dot.png", image_tint = c,
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, no_input = true,
    })
end

local function ring(id, x, y, radius, c, z)
    local d = 2.0 * radius / RING_PEAK
    quad(id, {
        x = x - d * 0.5, y = y - d * 0.5, width = d, height = d, z = z or 12.0,
        style = "image", path = "ring.png", image_tint = c,
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, no_input = true,
    })
end

local function label(id, x, y, w, h, text, c, fs, z)
    quad(id, {
        x = x - w * 0.5, y = y, width = w, height = h, z = z or 41.0,
        style = "text", body = text, text_color = c,
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 },
        align_h = "center", align_v = "middle", font_scale = fs, no_input = true,
    })
end

-- Geometry ------------------------------------------------------------------
local function layout()
    local surf = runtime_ui.get_surface_size()
    if not surf or not surf.valid then return false end
    local g = M.g
    g.w, g.h = surf.w, surf.h
    g.unit = math.min(g.w, g.h)
    g.cx, g.cy = g.w * 0.5, g.h * 0.58

    -- periodic-table board: compact, top-centre, fills in as you discover.
    g.pt_cols, g.pt_rows = 18, 9
    g.cell = math.min(g.w * 0.9 / g.pt_cols, g.h * 0.24 / g.pt_rows)
    g.boardW = g.cell * g.pt_cols
    g.boardX = (g.w - g.boardW) * 0.5
    g.boardY = g.h * 0.015
    g.iy = g.boardY + g.cell * g.pt_rows + g.unit * 0.012 -- identity header sits under the board

    -- rings model PERIODS; the atom grows one ring per period as Z climbs, sized to fit.
    local nrings = data.period(M.atom.protons)
    local r0, rmaxT = g.unit * 0.07, g.unit * 0.24
    local step = nrings > 1 and (rmaxT - r0) / (nrings - 1) or 0
    g.radii = {}
    for i = 1, #data.SHELLS do g.radii[i] = r0 + (i - 1) * step end
    g.rmax = r0 + (math.max(1, nrings) - 1) * step

    g.nucR = g.unit * 0.052
    g.de = g.unit * 0.030
    g.dp = g.unit * 0.024
    g.trayy = g.h * 0.90
    g.traypx = g.w * 0.5 - g.unit * 0.10
    g.traynx = g.w * 0.5 + g.unit * 0.10
    g.td = g.unit * 0.048
    g.catchR = g.unit * 0.42
    return true
end

-- Electron bookkeeping used by decay re-neutralisation (no juice) -------------
local function add_electron_quiet()
    local si = target_shell()
    if not si then return end
    local sh = M.atom.shells[si]
    sh.e[#sh.e + 1] = { spread = (#sh.e) / (#sh.e + 1) * TAU }
end

local function remove_electron_quiet()
    for si = #M.atom.shells, 1, -1 do
        local sh = M.atom.shells[si]
        if #sh.e > 0 then sh.e[#sh.e] = nil; return end
    end
end

-- Bring the electron count back to Z after a decay changed the proton number,
-- and refresh each shell's locked state to match its fill.
local function reneutralize()
    local z = M.atom.protons
    while electrons() > z do remove_electron_quiet() end
    while electrons() < z do add_electron_quiet() end
    for _, sh in ipairs(M.atom.shells) do sh.locked = #sh.e >= sh.cap end
end

-- Landings ------------------------------------------------------------------
-- throttled nucleon thump so hold-to-stream doesn't machine-gun the audio.
local function thump()
    if (M.clock - (M._lastthump or -1.0)) > 0.05 then M._lastthump = M.clock; sfx(SFX_THUMP) end
end

local function on_electron_added(si)
    local g, sh = M.g, M.atom.shells[si]
    M.acted = true
    sh.flare = 1.0
    local ang = sh.phase + sh.e[#sh.e].spread
    M.wob = { t = 0.0, amp = g.unit * 0.012, dx = math.cos(ang), dy = math.sin(ang) }
    sfx(SFX_TICK)
    if #sh.e == sh.cap and not sh.locked then
        sh.locked = true
        M.sw = { r = g.radii[si], spd = (g.unit * 0.52 - g.radii[si]) / SW_DUR, alpha = 0.95 }
        M.wob.amp = g.unit * 0.020
        sfx(SFX_LOCK)
    end
    if is_neutral() then
        local el = element()
        if el and not M.discovered[el.z] then
            M.discovered[el.z] = true
            M.card = { el = el, age = 0.0 }
            M.hold = HOLD_DUR
            sfx(SFX_CARD)
        end
    end
end

local function on_proton_added(a0)
    local g = M.g
    M.acted = true
    M.flash = 1.0
    -- a proton brings the neutrons of the element's principal stable isotope, so
    -- hand-built atoms stay stable; any extra neutrons the player added carry over.
    M.atom.neutrons = math.max(M.atom.neutrons, data.principal(M.atom.protons))
    M.wob = { t = 0.0, amp = g.unit * 0.016, dx = math.cos(a0), dy = math.sin(a0) }
    thump()
end

local function on_neutron_added(a0)
    local g = M.g
    M.acted = true
    M.flash = 0.7
    M.wob = { t = 0.0, amp = g.unit * 0.012, dx = math.cos(a0), dy = math.sin(a0) }
    thump()
end

-- Fast, juicy electron placement for the auto-cascade: snaps into the next open shell;
-- locks + shockwaves when a shell fills. No per-electron tick (would spam on heavy atoms).
local function add_electron_juicy()
    local si = target_shell()
    if not si then return false end
    local g, sh = M.g, M.atom.shells[si]
    sh.e[#sh.e + 1] = { spread = (#sh.e) / (#sh.e + 1) * TAU }
    sh.flare = 1.0
    if #sh.e == sh.cap and not sh.locked then
        sh.locked = true
        M.sw = { r = g.radii[si], spd = (g.unit * 0.52 - g.radii[si]) / SW_DUR, alpha = 0.95 }
        sfx(SFX_LOCK)
    end
    return true
end

-- electrons rush in to neutralise the atom on their own (rate-limited so it cascades; fast
-- when far behind) — the player never places electrons one by one.
local function sync_electrons(dt)
    local z = M.atom.protons
    if electrons() > z then
        while electrons() > z do remove_electron_quiet() end
        for _, sh in ipairs(M.atom.shells) do sh.locked = #sh.e >= sh.cap end
        return
    end
    if electrons() >= z then return end
    M.efill = (M.efill or 0.0) + dt
    local per = math.max(1, math.ceil((z - electrons()) * 0.15))
    while M.efill >= 0.03 and electrons() < z do
        M.efill = M.efill - 0.03
        for _ = 1, per do
            if electrons() >= z or not add_electron_juicy() then break end
        end
    end
end

-- add one nucleon directly (no fly): the trays are fast click/hold dispensers now.
local function add_nucleon(kind)
    if kind == "p" then
        if M.atom.protons >= data.MAX_Z then return false end
        M.atom.protons = M.atom.protons + 1
        on_proton_added(M.clock * 2.3)
        M.discovered[M.atom.protons] = true
    else
        if not can_add_neutron() then return false end
        M.atom.neutrons = M.atom.neutrons + 1
        on_neutron_added(M.clock * 2.3)
    end
    return true
end

-- Decay: one step toward the stable valley -----------------------------------
local function decay_step()
    local g = M.g
    local z, n = M.atom.protons, M.atom.neutrons
    local from = iso_name()
    local mode
    if not data.has_stable(z) and z > 2 then
        -- heavy radioactive: alpha decay (emit a He-4 nucleus), walk down toward lead
        M.atom.protons, M.atom.neutrons = z - 2, math.max(0, n - 2)
        M.emit = { kind = "a" }; mode = "alpha decay"
    else
        local lo, hi = data.stable_span(z)
        if n > hi then
            if z < data.MAX_Z then          -- beta-minus: neutron -> proton + emitted electron
                M.atom.protons, M.atom.neutrons = z + 1, n - 1
                M.emit = { kind = "e" }; mode = "beta- decay"
            else                            -- neutron-rich at the ceiling: eject a neutron
                M.atom.neutrons = n - 1
                M.emit = { kind = "n" }; mode = "neutron emission"
            end
        elseif n < lo then                  -- beta-plus: proton -> neutron + emitted positron
            M.atom.protons, M.atom.neutrons = math.max(1, z - 1), n + 1
            M.emit = { kind = "p" }; mode = "beta+ decay"
        else
            return
        end
    end
    reneutralize()
    M.discovered[M.atom.protons] = true
    M.flash = 1.0
    M.wob = { t = 0.0, amp = g.unit * 0.022, dx = math.cos(M.clock * 2.3), dy = math.sin(M.clock * 2.3) }
    local ang = (M.clock * 2.3) % TAU
    M.emit.x, M.emit.y = g.cx, g.cy
    M.emit.vx, M.emit.vy = math.cos(ang) * g.unit * 1.3, math.sin(ang) * g.unit * 1.3
    M.emit.life = 1.0
    M.toast = { msg = from .. "   ->   " .. iso_name() .. "     " .. mode, age = 0.0 }
    M.stats.decays = M.stats.decays + 1
    sfx(SFX_LOCK)
end

-- Catches -------------------------------------------------------------------
local function start_ecatch(x, y)
    local si = target_shell()
    if not si or not can_add_electron() then return false end
    local g = M.g
    M.fly = {
        kind = "e", state = "catch", t = 0.0,
        r0 = math.max(1.0, math.sqrt((x - g.cx) ^ 2 + (y - g.cy) ^ 2)),
        a0 = math.atan(y - g.cy, x - g.cx),
        shell = si, spin_sign = sign(M.atom.shells[si].spin), x = x, y = y,
    }
    return true
end

local function start_ncatch(x, y, kind, gate)
    if not gate then return false end
    local g = M.g
    M.fly = { kind = kind, state = "catch", t = 0.0, sx = x, sy = y,
        a0 = math.atan(y - g.cy, x - g.cx), x = x, y = y }
    return true
end

-- Per-frame -----------------------------------------------------------------
local function advance(dt)
    local g = M.g
    M.clock = M.clock + dt
    M.hold = math.max(0.0, M.hold - dt)
    M.flash = math.max(0.0, M.flash - dt / FLASH_DUR)
    local holdf = M.hold / HOLD_DUR
    g.bright = 1.0 + holdf * 0.45

    for _, sh in ipairs(M.atom.shells) do
        sh.phase = (sh.phase + sh.spin * dt * (1.0 - holdf * 0.6)) % TAU
        sh.flare = math.max(0.0, sh.flare - dt / FLARE_DUR)
        local n = #sh.e
        for i, e in ipairs(sh.e) do
            local tgt = (i - 1) / n * TAU
            e.spread = e.spread + wrap_pi(tgt - e.spread) * math.min(1.0, 10.0 * dt)
        end
    end

    -- whole-atom recoil wobble
    M.wob.t = M.wob.t + dt
    local damp = math.exp(-M.wob.t * WOB_DAMP)
    local osc = math.sin(M.wob.t * WOB_FREQ) * M.wob.amp * damp
    g.ox, g.oy = M.wob.dx * osc, M.wob.dy * osc
    g.acx, g.acy = g.cx + g.ox, g.cy + g.oy

    -- unstable nucleus trembles and a decay timer ticks (paused while a card is up).
    local inst = instability()
    if inst > 0 and not M.card then
        if not M.decay then M.decay = { t = math.max(DECAY_MIN, DECAY_BASE - inst * 0.5), dur0 = 0 } end
        M.decay.dur0 = math.max(M.decay.dur0, M.decay.t)
        M.decay.t = M.decay.t - dt
        local a = g.unit * 0.006 * (0.6 + inst * 0.5)
        g.tx = a * math.sin(M.clock * 41.0)
        g.ty = a * math.sin(M.clock * 37.0 + 1.3)
        if M.decay.t <= 0.0 then decay_step(); M.decay = nil end
    else
        -- was the clock ticking and the player just reached a stable isotope? that's a
        -- QUENCH — a skill save. (Card-paused decay clears silently: inst may still be >0.)
        if M.decay and inst == 0 then
            M.stats.quenched = (M.stats.quenched or 0) + 1
            M.gtoast = { msg = "QUENCHED  -  held it stable as " .. iso_name(), age = 0.0 }
            M.wob = { t = 0.0, amp = g.unit * 0.018, dx = 1.0, dy = 0.0 }
            sfx(SFX_LOCK)
        end
        M.decay = nil
        g.tx, g.ty = 0.0, 0.0
    end

    if M.sw then
        M.sw.r = M.sw.r + M.sw.spd * dt
        M.sw.alpha = M.sw.alpha - dt / SW_DUR
        if M.sw.alpha <= 0.0 then M.sw = nil end
    end
    if M.card then M.card.age = M.card.age + dt end
    if M.toast then
        M.toast.age = M.toast.age + dt
        if M.toast.age > TOAST_DUR then M.toast = nil end
    end
    if M.gtoast then
        M.gtoast.age = M.gtoast.age + dt
        if M.gtoast.age > TOAST_DUR then M.gtoast = nil end
    end
    M.goalflash = math.max(0.0, M.goalflash - dt / 0.8)
    if M.emit then
        M.emit.x = M.emit.x + M.emit.vx * dt
        M.emit.y = M.emit.y + M.emit.vy * dt
        M.emit.life = M.emit.life - dt / EMIT_DUR
        if M.emit.life <= 0.0 then M.emit = nil end
    end
    if M.bonding then
        M.bonding.t = M.bonding.t + dt / BOND_DUR
        if M.bonding.t >= 1.0 then
            local m = data.molecules[M.bonding.kind]
            M.molecule = { kind = M.bonding.kind }
            M.bonding = nil
            M.hold = HOLD_DUR
            M.card = { el = { sym = m.sym, name = m.name, lore = m.lore }, age = 0.0 }
            sfx(SFX_CARD)
        end
    end
end

local function update_fly(dt)
    local f = M.fly
    if not f or f.state ~= "catch" then return end
    local g = M.g
    if f.kind == "e" then
        f.t = f.t + dt / CATCH_DUR
        local er = ease_out(clamp01(f.t))
        local r = lerp(f.r0, g.radii[f.shell], er)
        local a = f.a0 + f.spin_sign * WIND * TAU * er
        f.x, f.y = g.acx + math.cos(a) * r, g.acy + math.sin(a) * r
        if f.t >= 1.0 then
            local sh = M.atom.shells[f.shell]
            sh.e[#sh.e + 1] = { spread = (a - sh.phase) % TAU }
            on_electron_added(f.shell)
            M.fly = nil
        end
    else -- proton / neutron pull into the nucleus
        f.t = f.t + dt / PCATCH_DUR
        local er = ease_out(clamp01(f.t))
        f.x, f.y = lerp(f.sx, g.acx, er), lerp(f.sy, g.acy, er)
        if f.t >= 1.0 then
            if f.kind == "p" then
                M.atom.protons = M.atom.protons + 1
                on_proton_added(f.a0)
            else
                M.atom.neutrons = M.atom.neutrons + 1
                on_neutron_added(f.a0)
            end
            M.fly = nil
        end
    end
end

local function handle_input()
    local g = M.g
    local rs = runtime_ui.get_state(SCREEN, "reset")
    if rs and rs.clicked then reset_atom(); return end
    local ts = runtime_ui.get_state(SCREEN, "target_btn")
    if ts and ts.clicked then new_target(); return end
    for _, c in ipairs(CATALYSTS) do
        local cs = runtime_ui.get_state(SCREEN, "cat_" .. c)
        if cs and cs.clicked then M.cat[c] = not M.cat[c]; return end
    end

    if M.card then
        local cs = runtime_ui.get_state(SCREEN, "card")
        if cs and cs.clicked then M.card.age = math.max(M.card.age, CARD_HOLD) end
        return
    end

    -- once bonded (or mid-coalesce) the atom builder is inert — Reset / new target to go on.
    if M.molecule or M.bonding then return end
    -- coalesce is a gesture: grab the reagent and drag it into the atom. It only fires when
    -- the reaction's real catalyst + condition are present. Click (no drag) binds too.
    local r = reaction_kind()
    if r and reqs_met(r) and not M.fly then
        local bs = runtime_ui.get_state(SCREEN, "bond_src")
        if bs then
            if bs.drag_started then
                M.fly = { kind = "bond", mol = r.product, state = "drag", src = "bond_src",
                    x = bs.mouse_x or g.cx, y = bs.mouse_y or g.cy }
                return
            elseif bs.clicked and not bs.dragging then
                M.bonding = { kind = r.product, t = 0.0 }; return
            end
        end
    end

    if M.fly and M.fly.state == "drag" then
        local st = runtime_ui.get_state(SCREEN, M.fly.src)
        if st then
            if st.mouse_x then M.fly.x, M.fly.y = st.mouse_x, st.mouse_y end
            if st.drag_released then
                local d = math.sqrt((M.fly.x - g.cx) ^ 2 + (M.fly.y - g.cy) ^ 2)
                if M.fly.kind == "bond" then
                    if d < g.catchR then M.bonding = { kind = M.fly.mol, t = 0.0 } end
                    M.fly = nil; return
                end
                local ok
                if d < g.catchR then
                    if M.fly.kind == "e" then ok = start_ecatch(M.fly.x, M.fly.y)
                    elseif M.fly.kind == "p" then ok = start_ncatch(M.fly.x, M.fly.y, "p", can_add_proton())
                    else ok = start_ncatch(M.fly.x, M.fly.y, "n", can_add_neutron()) end
                end
                if not ok then M.fly = nil end
            end
        end
        return
    end
    if M.fly then return end

    -- trays are click/hold dispensers: a tap adds one, holding streams them in fast (see
    -- M.update). Electrons auto-fill, so there is no electron tray, and no one-by-one grind.
    local held
    local ps = runtime_ui.get_state(SCREEN, "tray_p")
    local ns = runtime_ui.get_state(SCREEN, "tray_n")
    if ps and ps.down and can_add_proton() then held = { id = "tray_p", kind = "p" }
    elseif ns and ns.down and can_add_neutron() then held = { id = "tray_n", kind = "n" } end
    if held then
        if M.held_id ~= held.id then add_nucleon(held.kind) end -- newly pressed: instant +1
        M.held_id, M.held_kind = held.id, held.kind
    else
        M.held_id = nil
    end
end

-- Drawing -------------------------------------------------------------------
local function draw_tray(id, ring_id, x, cf, allowed, dragging)
    local g = M.g
    local pulse = 1.0 + 0.09 * math.sin(M.clock * 3.0)
    local a = allowed and (dragging and 0.15 or 0.5) or 0.12
    ring(ring_id, x, g.trayy, g.td * 0.85 * (allowed and pulse or 1.0), col(cf, a), 39.0)
    quad(id, {
        x = x - g.td * 0.5, y = g.trayy - g.td * 0.5, width = g.td, height = g.td, z = 40.0,
        style = "image", path = "dot.png",
        image_tint = col(cf, allowed and (dragging and 0.35 or 1.0) or 0.28),
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, draggable = allowed, bring_to_front = true,
    })
end

-- draw a nucleus (protons orange + neutrons grey, golden-angle packed) at (x,y). Heavy
-- nuclei cap the dot count and add a solid core so they read solid, not as a dot cloud.
-- returns its glow radius so callers can place bonds relative to it.
local function draw_nucleus(idp, x, y, protons, neutrons)
    local g = M.g
    local total = protons + neutrons
    local nucR = g.nucR * (0.62 + 0.11 * math.sqrt(math.max(1, total)))
    dot(idp .. "g", x, y, nucR * 3.0, C_NUCGLOW, 18.0)
    local shown = math.min(total, NUC_MAX_DOTS)
    if total > NUC_MAX_DOTS then dot(idp .. "core", x, y, nucR * 1.7, col(C_PROTON, 0.5), 21.0) end
    for i = 1, shown do
        local a = i * 2.399963
        local rr = nucR * 0.82 * math.sqrt(i / shown)
        dot(idp .. i, x + math.cos(a) * rr, y + math.sin(a) * rr, g.dp,
            (i / shown) <= (protons / math.max(1, total)) and C_PROTON or C_NEUTRON, 22.0)
    end
    return nucR
end

-- a hydrogen glyph (proton + one orbiting electron) — the in-flight ghost of the bond
-- partner you drag toward the atom. `s` scales it.
local function draw_hydrogen(idp, x, y, s, z)
    local g = M.g
    dot(idp .. "g", x, y, g.de * 2.4 * s, col(C_PROTON, 0.20), z)
    dot(idp .. "p", x, y, g.dp * 1.1 * s, C_PROTON, z + 1.0)
    local a = M.clock * 2.2
    dot(idp .. "e", x + math.cos(a) * g.de * 1.5 * s, y + math.sin(a) * g.de * 1.5 * s,
        g.de * 0.7 * s, C_ELEC, z + 2.0)
end

-- protons + principal neutrons for a partner/core atom named by symbol.
local function partner_pn(sym)
    local z = data.z_of[sym] or 1
    return z, data.principal(z)
end

-- a molecule — atoms settled at bond distances, sharing electron clouds with bright bond
-- glows. Data-driven from the molecule spec: "diatomic" (two equal nuclei) or "central"
-- (the built core atom + partner atoms bonded around it). `prog` (0..1) drives the fly-in.
local function draw_molecule()
    local g = M.g
    local kind = (M.molecule and M.molecule.kind) or (M.bonding and M.bonding.kind) or "H2"
    local prog = M.bonding and ease_out(clamp01(M.bonding.t)) or 1.0
    local m = data.molecules[kind]
    -- small movements: every atom gets the SAME tiny jitter (equal amplitude, its own
    -- phase), so the outer atoms move no more than the core. ~1/3 of the earlier amount.
    local cx, cy = g.cx, g.cy
    local JIT = g.unit * 0.0011
    local function jit(k) return math.sin(M.clock * 2.3 + k) * JIT, math.cos(M.clock * 1.9 + k * 1.7) * JIT end

    if m.render == "diatomic" then
        local pz, pn = partner_pn(m.core)
        local bd = g.unit * (m.core == "H" and 0.062 or 0.085)
        local lx = cx - bd
        local rx = M.bonding and lerp(g.cx + g.unit * 0.55, cx + bd, prog) or (cx + bd)
        local mid = (lx + rx) * 0.5
        local jlx, jly = jit(0.0)
        local jrx, jry = jit(3.1)
        dot("bondglow", mid, cy, g.nucR * 2.8, col(C_ELEC, 0.10 + 0.24 * prog), 19.0)
        draw_nucleus("molL", lx + jlx, cy + jly, pz, pn)
        draw_nucleus("molR", rx + jrx, cy + jry, pz, pn)
        for i = 0, 1 do
            local ang = M.clock * 1.3 + i * math.pi
            local ex = mid + math.cos(ang) * (bd + g.de * 1.6)
            local ey = cy + math.sin(ang) * g.radii[1] * 0.85
            dot("mole" .. i, ex, ey, g.de, C_ELEC, 30.0)
        end
    else -- central: the built core atom + partner atoms bonded around it
        local dCP = g.unit * 0.135
        local jcx, jcy = jit(0.0)
        local cR = draw_nucleus("molC", cx + jcx, cy + jcy, M.atom.protons, M.atom.neutrons)
        for idx, pa in ipairs(m.partners) do
            local sym, a = pa[1], pa[2]
            local pz, pn = partner_pn(sym)
            local r = M.bonding and lerp(g.unit * 0.6, dCP, prog) or dCP
            local jx, jy = jit(idx * 2.0)
            local hx, hy = cx + math.cos(a) * r + jx, cy + math.sin(a) * r + jy
            dot("molbond" .. idx, cx + math.cos(a) * dCP * 0.55, cy + math.sin(a) * dCP * 0.55,
                g.de * 2.2, col(C_ELEC, 0.12 + 0.2 * prog), 19.0) -- shared bonding pair
            draw_nucleus("molP" .. idx, hx, hy, pz, pn)
        end
        -- lone-pair electrons on the core (real count per molecule; 0 for CO2/CH4), drifting
        -- on the side away from the bonds.
        local lp = m.lone or 0
        for i = 1, lp do
            local ang = -math.pi * 0.5 + (i - (lp + 1) * 0.5) * 0.45 + M.clock * 0.3
            dot("mololp" .. i, cx + math.cos(ang) * (cR + g.de * 2.2), cy + math.sin(ang) * (cR + g.de * 2.2),
                g.de, col(C_ELEC, 0.85), 30.0)
        end
    end

    label("mol_sym", g.cx, g.iy, g.unit * 0.5, g.unit * 0.09,
        m.sym, col(C_LOCK, math.min(1.0, 0.9 * g.bright)), 3.6, 41.0)
    if M.molecule then
        label("mol_sub", g.cx, g.iy + g.unit * 0.075, g.unit * 0.7, g.unit * 0.045,
            string.lower(m.name), C_DIMTEXT, 1.7, 41.0)
    end
end

local function draw()
    local g = M.g
    local acx, acy = g.acx, g.acy
    local ncx, ncy = acx + (g.tx or 0.0), acy + (g.ty or 0.0) -- nucleus adds tremble
    local bright = g.bright

    quad("bg", { x = 0, y = 0, width = g.w, height = g.h, z = 0.0,
        style = "panel", fill = C_BG, border = { 0, 0, 0, 0 }, no_input = true })

    if M.sw then ring("shock", acx, acy, M.sw.r, col(C_LOCK, M.sw.alpha), 15.0) end

    if M.molecule or M.bonding then draw_molecule() else

    for si, sh in ipairs(M.atom.shells) do
        if si <= data.period(M.atom.protons) then
            local base = sh.locked and 0.95 or (#sh.e > 0 and 0.55 or 0.28)
            local c = sh.locked and C_LOCK or C_RING
            local a = math.min(1.0, (base + sh.flare * 0.55) * bright)
            ring("ring" .. si, acx, acy, g.radii[si] * (1.0 + sh.flare * 0.03), col(c, a), 12.0)
        end
    end

    -- nucleus: protons (orange) + neutrons (grey) packed by golden angle; grows with mass;
    -- trembles when the isotope is unstable + a shrinking decay ring. Heavy nuclei cap the
    -- dot count and draw a solid core.
    local total = mass()
    local nucR = g.nucR * (0.62 + 0.11 * math.sqrt(math.max(1, total)))
    if M.decay then
        local frac = clamp01(M.decay.t / math.max(0.001, M.decay.dur0))
        local pr = nucR * (1.35 + 1.3 * frac)
        ring("decayring", ncx, ncy, pr, col(C_UNSTABLE, 0.35 + 0.45 * (1.0 - frac)), 17.0)
    end
    dot("nucglow", ncx, ncy, nucR * (3.0 + M.flash * 1.6), col(C_NUCGLOW, math.min(0.7, 0.22 + M.flash * 0.5)), 18.0)
    local shown = math.min(total, NUC_MAX_DOTS)
    if total > NUC_MAX_DOTS then dot("nuccore", ncx, ncy, nucR * 1.7, col(C_PROTON, 0.5), 21.0) end
    for i = 1, shown do
        local a = i * 2.399963
        local rr = nucR * 0.82 * math.sqrt(i / shown)
        local c = (i / shown) <= (M.atom.protons / math.max(1, total)) and C_PROTON or C_NEUTRON
        dot("nuc" .. i, ncx + math.cos(a) * rr, ncy + math.sin(a) * rr, g.dp, c, 22.0)
    end

    local glow = electrons() <= E_GLOW_MAX -- glows are cheap juice for light atoms; drop on heavy ones
    for si, sh in ipairs(M.atom.shells) do
        for i = 1, math.min(#sh.e, E_MAX_PER_RING) do
            local ang = sh.phase + sh.e[i].spread
            local ex, ey = acx + math.cos(ang) * g.radii[si], acy + math.sin(ang) * g.radii[si]
            if glow then
                dot("eh" .. si .. "_" .. i, ex, ey, g.de * 2.1, col(C_ELECGLW, math.min(1.0, C_ELECGLW[4] * bright)), 29.0)
            end
            dot("e" .. si .. "_" .. i, ex, ey, g.de, C_ELEC, 30.0)
        end
    end

    if M.emit then
        local c = M.emit.kind == "e" and C_ELEC
            or (M.emit.kind == "p" and C_POSITRON or (M.emit.kind == "a" and C_PROTON or C_NEUTRON))
        local a = clamp01(M.emit.life)
        dot("emith", M.emit.x, M.emit.y, g.de * 2.2, col(c, 0.18 * a), 51.0)
        dot("emit", M.emit.x, M.emit.y, g.de * 0.9, col(c, a), 52.0)
    end

    if M.fly then
        if M.fly.kind == "bond" then
            draw_hydrogen("fly", M.fly.x, M.fly.y, 1.15, 50.0)
        else
            local c = M.fly.kind == "e" and C_ELEC or (M.fly.kind == "p" and C_PROTON or C_NEUTRON)
            dot("flyh", M.fly.x, M.fly.y, g.de * 2.6, col(c, 0.22), 49.0)
            dot("fly", M.fly.x, M.fly.y, g.de * (M.fly.kind == "e" and 1.15 or 1.0), c, 50.0)
        end
    end

    -- live identity + isotope, as a header under the board
    local el = element()
    if el then
        local unstable = instability() > 0
        local sym_c = is_neutral() and col(C_LOCK, math.min(1.0, 0.9 * bright)) or { 0.86, 0.92, 1.0, 0.9 }
        label("ident_sym", g.cx, g.iy, g.unit * 0.4, g.unit * 0.10, el.sym, sym_c, 4.0, 41.0)
        local iso_c = unstable and col(C_UNSTABLE, 0.7 + 0.3 * (0.5 + 0.5 * math.sin(M.clock * 6.0))) or C_DIMTEXT
        label("ident_iso", g.cx, g.iy + g.unit * 0.085, g.unit * 0.6, g.unit * 0.045,
            iso_name() .. (unstable and "   unstable" or ""), iso_c, 2.0, 41.0)
        label("ident_sub", g.cx, g.iy + g.unit * 0.125, g.unit * 0.6, g.unit * 0.038,
            string.format("%dp %dn / %de", M.atom.protons, M.atom.neutrons, electrons()), C_DIMTEXT, 1.5, 41.0)
    end

    end -- end single-atom vs molecule branch

    -- "stabilize-the-decay": under the decay clock, name the stakes and the save move.
    -- Drop the hinted particle before the tick to QUENCH it; or let it decay (also valid).
    if M.decay and not M.card then
        local py = g.cy + g.rmax + g.unit * 0.04
        local pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(M.clock * 7.0))
        label("decay_hdr", g.cx, py, g.unit * 0.6, g.unit * 0.05, "UNSTABLE  -  DECAYING",
            col(C_UNSTABLE, pulse), 2.2, 43.0)
        local hint = (stabilizes("n") and "drag a NEUTRON in to stabilize")
            or (stabilizes("p") and "drag a PROTON in to stabilize")
            or "no stable route - let it decay"
        label("decay_hint", g.cx, py + g.unit * 0.052, g.unit * 0.75, g.unit * 0.04, hint,
            { 0.92, 0.86, 0.72, 0.92 }, 1.6, 43.0)
    end

    -- coalesce reagent: when a reaction is available (a molecule target whose core you've
    -- built), a reagent rests beside the atom. It only reacts once the required catalyst +
    -- condition chips are on; until then it's dim and shows what it needs.
    local rx = reaction_kind()
    local bdrag = M.fly and M.fly.src == "bond_src"
    if rx and not M.card and (not M.fly or bdrag) then
        local met = reqs_met(rx)
        local bx, by = g.cx + g.unit * 0.40, g.cy
        local pc = (rx.partner == "H" and C_PROTON) or (rx.partner == "O" and C_RING) or C_NEUTRON
        if not bdrag then
            local pulse = 1.0 + 0.10 * math.sin(M.clock * 3.0)
            ring("bond_ring", bx, by, g.td * 0.60 * (met and pulse or 1.0), col(pc, met and 0.5 or 0.18), 39.0)
            dot("bond_glow", bx, by, g.de * 2.4, col(pc, 0.18), 39.5)
            local total = (rx.partner == rx.core) and (rx.n + 1) or rx.n
            label("bond_lbl", bx, by + g.td * 0.62, g.unit * 0.5, g.unit * 0.036,
                string.format("coalesce  %dx %s  =  %s", total, rx.partner, data.molecules[rx.product].sym),
                col(pc, met and 0.95 or 0.5), 1.4, 40.0)
            local q = reqs_of(rx)
            if not met and #q > 0 then
                label("bond_need", bx, by + g.td * 0.62 + g.unit * 0.04, g.unit * 0.5, g.unit * 0.034,
                    "needs: " .. table.concat(q, " + "), col(C_UNSTABLE, 0.9), 1.3, 40.0)
            end
        end
        quad("bond_src", { x = bx - g.dp * 1.1, y = by - g.dp * 1.1, width = g.dp * 2.2, height = g.dp * 2.2,
            z = 40.0, style = "image", path = "dot.png",
            image_tint = col(pc, bdrag and 0.28 or (met and 1.0 or 0.4)),
            fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, draggable = met, bring_to_front = true })
    end

    -- catalyst / condition chips (top-right, under Restart): the lab's real helpers. Toggle
    -- to enable reactions that require them (Haber = Fe + pressure, combustion = spark...).
    -- The pending reaction's needs are outlined red until satisfied.
    do
        local need = {}
        if rx then for _, k in ipairs(reqs_of(rx)) do need[k] = true end end
        local cw, chh = g.unit * 0.085, g.unit * 0.044
        local x0 = g.w - cw - g.unit * 0.02
        local y0 = g.unit * 0.135
        for i, c in ipairs(CATALYSTS) do
            local on = M.cat[c]
            quad("cat_" .. c, { x = x0, y = y0 + (i - 1) * (chh + g.unit * 0.012),
                width = cw, height = chh, z = 46.0, style = "button", title = c, font_scale = 1.4,
                fill = on and { 0.16, 0.20, 0.10, 0.95 } or { 0.10, 0.12, 0.16, 0.9 },
                border = on and C_LOCK or (need[c] and col(C_UNSTABLE, 0.85) or { 0.4, 0.45, 0.55, 0.55 }),
                accent = on and col(C_LOCK, 0.9) or col(C_ELEC, 0.5),
                text_color = on and { 0.95, 0.9, 0.6, 1.0 } or { 0.8, 0.85, 0.92, 0.9 } })
        end
    end

    -- periodic-table board: the whole table, filling in as you discover; target = gold.
    -- Perf: 118 set_quad every frame is expensive, and the board is static between visible
    -- changes, so keep its quads alive but only re-submit them when the signature changes.
    local dn = 0
    for _ in pairs(M.discovered) do dn = dn + 1 end
    local tkey = M.target and (M.target.kind == "el" and ("z" .. M.target.z) or M.target.key) or "-"
    local bkey = string.format("%d|%s|%d|%d|%.0f", M.atom.protons, tkey, dn, M.won and 1 or 0, g.cell)
    for z = 1, data.MAX_Z do M._live["pt" .. z] = true end
    if bkey ~= M._bkey then
        M._bkey = bkey
        for z = 1, data.MAX_Z do
            local gc, gr = data.grid(z)
            local e = data.get(z)
            local x = g.boardX + (gc - 1) * g.cell
            local y = g.boardY + (gr - 1) * g.cell
            local fill, border, tc
            if M.target and M.target.kind == "el" and M.target.z == z then
                fill = { 0.24, 0.18, 0.05, 0.95 }; border = col(C_LOCK, 0.95); tc = { 1.0, 0.90, 0.60, 1.0 }
            elseif M.discovered[z] then
                fill = { 0.10, 0.13, 0.19, 0.92 }
                border = (M.atom.protons == z) and col(C_ELEC, 0.9) or { 0.40, 0.45, 0.55, 0.6 }
                tc = { 0.94, 0.88, 0.72, 1.0 }
            else
                fill = { 0.05, 0.06, 0.09, 0.5 }; border = { 0.20, 0.24, 0.30, 0.4 }; tc = { 0.42, 0.46, 0.54, 0.7 }
            end
            quad("pt" .. z, { x = x + g.cell * 0.06, y = y + g.cell * 0.06,
                width = g.cell * 0.88, height = g.cell * 0.88, z = 44.0,
                style = "text", body = e.sym, align_h = "center", align_v = "middle",
                font_scale = math.max(0.7, math.min(1.3, g.cell * 0.028)),
                fill = fill, border = border, text_color = tc, no_input = true })
        end
    end

    -- TARGET banner (top-left). Click to reroll / advance to a new target.
    do
        local tx, ty = g.unit * 0.02, g.unit * 0.025
        local tc = (M.won or M.goalflash > 0.0)
            and col(C_LOCK, 0.85 + 0.15 * (M.goalflash > 0.0 and M.goalflash or 1.0))
            or { 0.86, 0.92, 1.0, 0.96 }
        quad("target_btn", { x = tx, y = ty, width = g.unit * 0.32, height = g.unit * 0.065, z = 46.0,
            style = "button", title = M.won and "DONE!  tap for next" or ("TARGET:  " .. target_label()),
            font_scale = 1.8, fill = { 0.09, 0.11, 0.17, 0.94 },
            border = M.won and C_LOCK or col(C_ELEC, 0.6), accent = col(C_LOCK, 0.8), text_color = tc })
        quad("target_sub", { x = tx, y = ty + g.unit * 0.072, width = g.unit * 0.36, height = g.unit * 0.03,
            z = 46.0, style = "text",
            body = M.won and "click for a new target" or "synthesize this  -  add particles, then coalesce",
            align_h = "left", align_v = "middle", font_scale = 1.2,
            fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, text_color = C_DIMTEXT, no_input = true })
    end

    -- trays (hidden while a card is up or bonded): proton | neutron. Tap adds one, HOLD to
    -- pour them in fast; electrons fill themselves so heavy elements aren't a grind.
    if not M.card and not M.molecule and not M.bonding then
        draw_tray("tray_p", "tray_pr", g.traypx, C_PROTON, can_add_proton(), M.held_id == "tray_p")
        draw_tray("tray_n", "tray_nr", g.traynx, C_NEUTRON, can_add_neutron(), M.held_id == "tray_n")
        label("tray_pl", g.traypx, g.trayy + g.td * 0.65, g.unit * 0.2, g.unit * 0.035, "proton", C_HINT, 1.4, 40.0)
        label("tray_nl", g.traynx, g.trayy + g.td * 0.65, g.unit * 0.2, g.unit * 0.035, "neutron", C_HINT, 1.4, 40.0)
        if not M.acted then
            label("hint", g.cx, g.h * 0.955, g.unit * 0.7, g.unit * 0.045,
                "tap to add a proton  -  hold to pour them in", C_HINT, 2.0, 42.0)
        end
    end

    -- decay toast (mid)
    if M.toast then
        local a = clamp01(math.min(M.toast.age / 0.25, (TOAST_DUR - M.toast.age) / 0.4))
        quad("toast", { x = g.w * 0.5 - g.unit * 0.28, y = g.h * 0.30, width = g.unit * 0.56, height = g.unit * 0.06,
            z = 58.0, style = "text", body = M.toast.msg, align_h = "center", align_v = "middle", font_scale = 2.0,
            fill = { 0.06, 0.05, 0.04, 0.9 * a }, border = col(C_UNSTABLE, 0.7 * a),
            text_color = { 1.0, 0.86, 0.7, a }, no_input = true })
    end

    -- synthesized / quench toast (gold)
    if M.gtoast then
        local a = clamp01(math.min(M.gtoast.age / 0.25, (TOAST_DUR - M.gtoast.age) / 0.4))
        quad("gtoast", { x = g.w * 0.5 - g.unit * 0.28, y = g.h * 0.36, width = g.unit * 0.56, height = g.unit * 0.06,
            z = 59.0, style = "text", body = M.gtoast.msg, align_h = "center", align_v = "middle", font_scale = 2.0,
            fill = { 0.05, 0.06, 0.04, 0.9 * a }, border = col(C_LOCK, 0.7 * a),
            text_color = { 1.0, 0.92, 0.72, a }, no_input = true })
    end

    -- birth card
    if M.card then
        local cw2 = math.min(g.w * 0.66, g.unit * 0.95)
        local ch = g.unit * 0.24
        local rest = g.h - ch - g.unit * 0.05
        local yy
        if M.card.age < CARD_HOLD then
            yy = lerp(g.h, rest, ease_out(clamp01(M.card.age / CARD_SLIDE)))
        else
            yy = lerp(rest, g.h + 4.0, ease_out(clamp01((M.card.age - CARD_HOLD) / CARD_SLIDE)))
            if M.card.age > CARD_HOLD + CARD_SLIDE then M.card = nil end
        end
        if M.card then
            local e = M.card.el
            quad("card", {
                x = (g.w - cw2) * 0.5, y = yy, width = cw2, height = ch, z = 60.0,
                style = "panel", font_scale = 2.2, bring_to_front = true,
                label = e.sym .. (e.z and ("  -  Z " .. e.z) or ""), title = string.upper(e.name), body = e.lore,
                footer = "click to continue",
                fill = { 0.05, 0.06, 0.10, 0.97 }, border = C_LOCK,
                accent = { 1.00, 0.82, 0.34, 1.0 }, text_color = { 0.92, 0.94, 0.98, 1.0 },
            })
        end
    end

    quad("reset", { x = g.w - 150.0, y = 26.0, width = 122.0, height = 44.0, z = 45.0,
        style = "button", title = "Restart", font_scale = 1.7,
        fill = { 0.10, 0.12, 0.16, 0.9 }, border = { 0.4, 0.5, 0.62, 0.7 },
        accent = { 0.34, 0.55, 0.92, 0.8 }, text_color = { 0.86, 0.9, 0.96, 1.0 } })
end

local function reconcile()
    for id in pairs(M._prev) do
        if not M._live[id] then runtime_ui.remove(SCREEN, id) end
    end
    M._prev = M._live
    M._live = {}
end

function M.update(dt)
    if not layout() then return end
    advance(dt)
    check_target()
    handle_input()
    -- hold-to-stream: after a short press, pour nucleons in at an accelerating rate
    if M.held_id then
        M.hold_t = (M.hold_t or 0.0) + dt
        if M.hold_t > 0.2 then
            M.stream_acc = (M.stream_acc or 0.0) + dt
            local interval = math.max(0.02, 0.09 - (M.hold_t - 0.2) * 0.02)
            while M.stream_acc >= interval do
                M.stream_acc = M.stream_acc - interval
                if not add_nucleon(M.held_kind) then break end
            end
        end
    else
        M.hold_t, M.stream_acc = 0.0, 0.0
    end
    sync_electrons(dt)
    -- settle: land on a new, complete, stable element and its birth card slides up (once)
    if not M.held_id and not M.molecule and not M.bonding and not M.card and is_neutral() then
        local el = element()
        if el and is_stable_iso() and not M.carded[el.z] then
            M.carded[el.z] = true
            M.discovered[el.z] = true
            M.card = { el = el, age = 0.0 }
            M.hold = HOLD_DUR
            sfx(SFX_CARD)
        end
    end
    update_fly(dt)
    draw()
    reconcile()
end

return M
