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
    return load(src, "@Scripts/data.lua", "bt", _ENV)()
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
local CARD_HOLD = 12.0
local CARD_SLIDE = 0.42
local DECAY_MIN = 0.9   -- game-clock floor; the clock itself maps the REAL half-life (see advance)
local TOAST_DUR = 3.0   -- decay toast on-screen time
local EMIT_DUR = 0.9    -- emitted decay particle lifetime
local BOND_DUR = 0.85   -- coalesce animation (two atoms -> molecule)
local FUSE_DUR = 0.45   -- fusion: the assembled chunk slams into the main nucleus
local FISS_IN = 0.34    -- fission: the fired neutron flies into the nucleus
local FISS_OUT = 0.75   -- fission: fragments + free neutrons fly off
local FISSION_Z = 90    -- actinides (Th+) and up can be split by an incoming neutron
local IRON_Z = 26       -- the binding-energy peak: fusion releases energy only up to iron;
local EC_Z = 40         -- heavier is endothermic. Proton-rich nuclei at/above EC_Z decay by
                        -- electron capture rather than beta+ (inner-shell e- density wins).

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
local GAMMA_DUR = 0.35  -- gamma de-excitation: an excited daughter nucleus relaxes to ground
local C_GAMMA = { 0.82, 0.76, 1.0, 1.0 } -- pale violet-white: the emitted gamma EM burst
local C_HINT     = { 0.66, 0.74, 0.86, 0.55 }
local C_DIMTEXT  = { 0.55, 0.60, 0.70, 1.0 }
local RING_PEAK  = 0.78
local NUC_MAX_DOTS = 28  -- past this a heavy nucleus draws a solid core + a scatter of dots
-- CPK-ish atom colours for the molecule (ball-and-stick) view, lightened so they read on the
-- dark bg (real carbon is black). Falls back to proton-orange for any element not listed.
local CPK = {
    H = { 0.92, 0.94, 0.98, 1.0 }, C = { 0.46, 0.50, 0.57, 1.0 }, N = { 0.30, 0.46, 0.96, 1.0 },
    O = { 0.94, 0.30, 0.26, 1.0 }, F = { 0.50, 0.86, 0.48, 1.0 }, Cl = { 0.42, 0.86, 0.44, 1.0 },
    Si = { 0.85, 0.72, 0.55, 1.0 }, P = { 0.98, 0.56, 0.22, 1.0 }, S = { 0.94, 0.82, 0.30, 1.0 },
}
local E_MAX_PER_RING = 12 -- cap electron dots per ring (perf: heavy atoms have up to 32)
local E_GLOW_MAX = 18     -- drop the per-electron soft glow once the atom has more e- than this
-- "last radiation fired": a persistent readout (bottom-right) naming the most recent
-- emission, with a hover legend explaining what that radiation actually is.
local RAD_INFO = {
    alpha   = { name = "alpha", c = C_PROTON, desc = "A helium-4 nucleus (2p+2n). Heavy and charged - a sheet of paper stops it." },
    betam   = { name = "beta-", c = C_ELEC, desc = "An electron flung out as a neutron becomes a proton. Millimetres of aluminium stop it." },
    betap   = { name = "beta+", c = C_POSITRON, desc = "A positron - antimatter. It meets an electron and annihilates into gamma rays; that is a PET scan." },
    ec      = { name = "e- capture", c = C_ELEC, desc = "The nucleus swallows one of its own inner electrons; a proton becomes a neutron and an X-ray follows." },
    n       = { name = "neutron", c = C_NEUTRON, desc = "A free neutron - no charge, deeply penetrating, and it can make other atoms radioactive." },
    gamma   = { name = "gamma", c = C_GAMMA, desc = "A high-energy photon shed by an excited nucleus. It takes lead or thick concrete to stop." },
    fission = { name = "fission", c = C_UNSTABLE, desc = "The nucleus tears into two fragments plus free neutrons - the energy source of reactors." },
}
local function set_lastrad(key, note) M.lastrad = { key = key, note = note } end
local CATALYSTS = { "spark", "heat", "pressure", "Fe", "Ni", "Pt", "V2O5" } -- the lab's real helpers (toggle chips)
local STEPPERS = { -- the left-hand assembly atom's manual controls
    { kind = "p", plus = "st_p_plus", minus = "st_p_minus" },
    { kind = "n", plus = "st_n_plus", minus = "st_n_minus" },
    { kind = "e", plus = "st_e_plus", minus = "st_e_minus" },
}
-- atom representation modes (dropdown). Bohr = the classic gameplay rings; the other three
-- read the real Madelung electron configuration (see data.config): a written readout, true
-- per-shell occupancy, and a quantum orbital / probability cloud.
local VIEWS = {
    { key = "bohr", name = "Bohr model" },
    { key = "shells", name = "True shells" },
    { key = "cloud", name = "Orbital cloud" },
}
local function view_name(key)
    for _, v in ipairs(VIEWS) do if v.key == key then return v.name end end
    return "?"
end

-- Small math helpers --------------------------------------------------------
local function clamp01(t) return t < 0.0 and 0.0 or (t > 1.0 and 1.0 or t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function ease_out(t) return 1.0 - (1.0 - t) * (1.0 - t) end
local function sign(x) return x < 0.0 and -1.0 or 1.0 end
local function wrap_pi(a) return (a + math.pi) % TAU - math.pi end
local function col(c, a) return { c[1], c[2], c[3], a or c[4] } end
-- pulse alpha cached + quantised so unstable/decay labels don't re-set_quad every frame.
local function pulse_a(key, rate, lo, hi, period)
    period = period or 4
    if ((M.frame or 0) % period) ~= 0 and M._pulse and M._pulse[key] then return M._pulse[key] end
    M._pulse = M._pulse or {}
    local a = lo + (hi - lo) * (0.5 + 0.5 * math.sin(M.clock * rate))
    M._pulse[key] = math.floor(a * 20.0) / 20.0
    return M._pulse[key]
end

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
-- neutron drip line: exact through neon, playable stand-in beyond (see data.DRIP).
local function neutron_max(z) return data.neutron_max(z) end
local function can_add_neutron()
    if M.atom.protons < 1 then return false end
    return M.atom.neutrons < neutron_max(M.atom.protons)
end
local function iso_name() return string.format("%s-%d", element().sym, mass()) end

-- electrons grouped by principal quantum number n from the real Madelung config — the
-- True-shells (Aufbau) view. K(19) reads 2/8/8/1, not the period rings' 2/8/9.
local function n_shell_occ(e)
    local occ = {}
    for _, s in ipairs(data.config(e)) do occ[s.n] = (occ[s.n] or 0) + s.e end
    local out, nmax = {}, 0
    for i = 1, 7 do if occ[i] and occ[i] > 0 then nmax = i end end
    for i = 1, nmax do out[i] = occ[i] or 0 end
    return out, nmax
end

-- how far outside the stable band (0 = stable); drives tremble + decay speed. Elements
-- with no stable isotope (Z>83) are always unstable — the radioactive endgame.
local function instability()
    local z, n = M.atom.protons, M.atom.neutrons
    if not data.has_stable(z) then return 1 + math.abs(n - data.principal(z)) end
    local lo, hi = data.stable_span(z)
    if n > hi then return n - hi elseif n < lo then return lo - n end
    -- inside the span but on a real HOLE (K-40, Cl-36, Kr-85...): mildly unstable
    return data.is_stable(z, n) and 0 or 1
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
    if type(r.cond) == "table" then
        for _, c in ipairs(r.cond) do q[#q + 1] = c end -- Haber really needs heat AND pressure
    elseif r.cond then
        q[#q + 1] = r.cond
    end
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
    M.fusing = nil
    M.fission = nil
    M.gamma = nil
    M.hold = 0.0
    M.flash = 0.0
    M.wob = { t = 999.0, amp = 0.0, dx = 1.0, dy = 0.0 }
    M.acted = false
    M.won = false
    M.held_id = nil
    M.hold_t = 0.0
    M.stream_acc = 0.0
    M.stage = { p = 0, n = 0, e = 0 } -- the left-hand assembly atom: build a chunk, then MERGE it in
    M.chain = {} -- spontaneous-decay breadcrumb (U-238 > Th-234 > ...); manual builds clear it
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
    M.shelf = {} -- synthesized molecules by species count — the bench's reagent inventory
    M.mol_disc = {} -- molecules ever made (fills the discovered strip)
    M.lastrad = nil -- most recent radiation event (readout, bottom-right)
    M.view = M.view or "bohr" -- atom representation mode (dropdown); persists across runs
    if M.view ~= "bohr" and M.view ~= "cloud" and M.view ~= "shells" then M.view = "bohr" end
    M.viewOpen = false
    M.questOpen = false -- the pick-any-target quest catalog under the TARGET button
end

-- ==================== PERSISTENCE ====================
-- Progress (discovered board, molecule strip, shelf, stats, target range, view) survives
-- relaunch. Saved as a Lua chunk under Assets/Save/ (gitignored); loaded with the same
-- read+load pattern as data.lua. Restart resets only the atom, never the save.
local SAVE_PATH = "Save/progress.lua"

local function ser(t)
    local parts = {}
    for k, v in pairs(t) do
        local key = (type(k) == "number") and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        local val
        if type(v) == "table" then val = ser(v)
        elseif type(v) == "string" then val = string.format("%q", v)
        else val = tostring(v) end
        parts[#parts + 1] = key .. "=" .. val
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function save_progress()
    if not (fs and fs.write) then return end
    fs.write(SAVE_PATH, "return " .. ser({ v = 1, discovered = M.discovered, carded = M.carded,
        mol_disc = M.mol_disc, shelf = M.shelf, stats = M.stats, tcount = M.tcount, view = M.view }))
end

local function load_progress()
    if not (fs and fs.read) then return end
    local src = fs.read(SAVE_PATH)
    if not src then return end
    local ok, t = pcall(function() return load(src, "@" .. SAVE_PATH, "t", {})() end)
    if not ok or type(t) ~= "table" or t.v ~= 1 then return end
    M.discovered = t.discovered or M.discovered
    M.carded = t.carded or M.carded
    M.mol_disc = t.mol_disc or M.mol_disc
    M.shelf = t.shelf or M.shelf
    M.stats = t.stats or M.stats
    M.discovered[1], M.carded[1] = true, true
    if t.view == "bohr" or t.view == "cloud" or t.view == "shells" then M.view = t.view end
    M.tcount = t.tcount or 0
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
    -- bench products (acids...) become targets once every reagent has been made before
    for _, s in ipairs(data.species) do
        local known = true
        for k in pairs(s.needs) do if not M.mol_disc[k] then known = false; break end end
        if known then
            for k in pairs(s.gives) do if not M.mol_disc[k] then mols[#mols + 1] = k end end
        end
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

-- THE BENCH: true species-level stoichiometry. Reactions between MOLECULES pulled from
-- the shelf (N2 + 3 H2 needs three H2 you actually made), gated by the same catalyst
-- chips as formation reactions. Products land back on the shelf; new species get a card.
local function bench_offers()
    local out = {}
    for _, s in ipairs(data.species) do
        local ok = true
        if s.core then -- acid + metal: the reaction consumes the BUILT atom as its metal
            local el = element()
            ok = el ~= nil and el.sym == s.core and is_neutral() and is_stable_iso()
                and not (M.molecule or M.bonding or M.fusing or M.fission)
        end
        if ok then
            for k, cnt in pairs(s.needs) do
                if (M.shelf[k] or 0) < cnt then ok = false; break end
            end
        end
        if ok then out[#out + 1] = s end
    end
    return out
end

local function bench_react(s)
    if s.core then reset_atom() end -- the acid dissolves the built metal atom (before the
    -- card/win below — reset_atom clears M.card and M.won)
    for k, cnt in pairs(s.needs) do M.shelf[k] = (M.shelf[k] or 0) - cnt end
    local newk, won = nil, false
    for k, cnt in pairs(s.gives) do
        M.shelf[k] = (M.shelf[k] or 0) + cnt
        if not M.mol_disc[k] then newk = newk or k end
        M.mol_disc[k] = true
        if M.target and M.target.kind == "mol" and M.target.key == k and not M.won then
            M.won = true
            won = true
            M.goalflash = 1.0
            M.gtoast = { msg = "SYNTHESIZED   " .. target_label(), age = 0.0 }
        end
    end
    if not won then M.gtoast = { msg = "REACTION   " .. s.eq, age = 0.0 } end
    if newk then
        local m = data.molecules[newk]
        M.card = { el = { sym = m.sym, name = m.name, lore = m.lore, eq = s.eq }, age = 0.0 }
        M.hold = HOLD_DUR
        sfx(SFX_CARD)
    else
        sfx(SFX_LOCK)
    end
end

function M.init()
    runtime_ui.clear(SCREEN)
    runtime_ui.set_screen_overlay(SCREEN, true)
    runtime_ui.show(SCREEN)
    if os and os.time then math.randomseed(os.time()) end
    M.reset()
    load_progress()
    -- a returning player rolls a fresh target at their restored progression range
    if (M.tcount or 0) > 0 then M.tcount = M.tcount - 1; new_target() end
    M._prev = {}
    M._live = {}
    M._opt = {}
    M._eang = {} -- last packed pixel position per electron id (hold-skip; see draw_view_fg)
    M._pulse = {}
    M.g = {}
end

-- Draw plumbing -------------------------------------------------------------
-- value-equal for quad opts (flat fields + one level of colour arrays; colours never nest).
local function veq(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- The engine persists a quad across frames until removed (see the board), so re-submitting an
-- unchanged quad every frame is pure waste — skip the call when this id's opts match last frame.
-- (set_quad used to cost ~150us/call from per-call filesystem stats; the engine now memoizes the
-- image-path resolve so it's ~us-scale, but the skip still saves the marshalling + table churn.)
local function quad(id, opts)
    M._live[id] = true
    local prev = M._opt[id]
    if prev then
        local same = true
        for k, v in pairs(opts) do if not veq(v, prev[k]) then same = false; break end end
        if same then for k in pairs(prev) do if opts[k] == nil then same = false; break end end end
        if same then return end
    end
    M._opt[id] = opts
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
    -- Heavier atoms look bigger: the outer radius grows with Z on a sqrt curve (monotonic,
    -- bounded so period-7 still fits between the board and the bottom controls). An anion's
    -- extra electron sits one shell BEYOND the period, so lay out a ring per occupied shell
    -- (else that electron collapses onto an inner ring — 3 e- must never share the n=1 level).
    local nrings = data.period(M.atom.protons)
    for i, sh in ipairs(M.atom.shells) do if #sh.e > 0 then nrings = math.max(nrings, i) end end
    local r0 = g.unit * 0.05
    local rmaxT = g.unit * (0.13 + 0.15 * math.sqrt(M.atom.protons / data.MAX_Z))
    local step = nrings > 1 and (rmaxT - r0) / (nrings - 1) or 0
    g.radii = {}
    for i = 1, #data.SHELLS do g.radii[i] = r0 + (i - 1) * step end
    g.rmax = r0 + (math.max(1, nrings) - 1) * step
    g.nrings = nrings

    g.nucR = g.unit * 0.022  -- tight, small nucleus in every view (Bohr matches the old cloud size)
    g.de = g.unit * 0.030
    g.dp = g.unit * 0.010
    g.td = g.unit * 0.048
    g.catchR = g.unit * 0.42

    -- left-hand ASSEMBLY atom: a faint, smaller atom the player builds by hand (steppers),
    -- then MERGE fuses it into the main atom. Sits on the left so it reads as a second body.
    g.sx, g.sy = g.w * 0.16, g.h * 0.42
    g.sr0, g.srstep = g.unit * 0.032, g.unit * 0.028
    g.stepy = g.sy + g.unit * 0.20     -- first stepper row, below the faint atom
    g.stepdy = g.unit * 0.058
    g.stbtn = g.unit * 0.046           -- +/- button size
    g.stgap = g.unit * 0.085           -- +/- horizontal offset from the row centre
    g.mergew, g.mergeh = g.unit * 0.24, g.unit * 0.058
    g.mergey = g.stepy + 3 * g.stepdy + g.unit * 0.02

    -- molecule discovered-strip: every species (covalent, acids, salts) in two rows along
    -- the bottom, filling in as you synthesize. Cells sized so the whole list always fits.
    g.msN = #data.mol_list
    g.msCols = math.ceil(g.msN / 2)
    g.msW = g.w * 0.985
    g.msCell = g.msW / g.msCols
    g.msH = g.unit * 0.034
    g.msX = (g.w - g.msW) * 0.5
    g.msY = g.h - 2 * (g.msH + g.unit * 0.004) - g.unit * 0.006
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
    M.chain = {} -- hand-building breaks the spontaneous-decay story
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
    M.chain = {}
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

-- The left-hand ASSEMBLY atom: dial protons / neutrons / electrons by hand (the steppers
-- stream while held), then MERGE fuses the whole chunk into the main atom at once — a real
-- nuclear jump, not a proton-at-a-time grind. Nothing auto-fills: the player places every
-- particle, and the merge preview names the isotope the chunk will make.
local function stage_add(kind, d)
    local v = math.max(0, M.stage[kind] + d)
    if kind == "p" then v = math.min(v, data.MAX_Z - M.atom.protons) end -- can't overshoot Z=118
    -- an isolated atom binds at most Z+1 electrons (a singly-charged anion, e.g. F-); a second
    -- extra electron has no bound state, so cap the merged atom's electrons at protons + 1.
    if kind == "e" then v = math.min(v, math.max(0, M.atom.protons + M.stage.p + 1 - electrons())) end
    -- and it can't bind neutrons past the drip line (~2Z+2 for the merged proton count).
    if kind == "n" then v = math.min(v, math.max(0, neutron_max(M.atom.protons + M.stage.p) - M.atom.neutrons)) end
    M.stage[kind] = v
end

-- distribute an electron count into shells by the period caps (drives the faint staging render)
local function stage_shells(ecount)
    local out = {}
    for i, cap in ipairs(data.SHELLS) do
        local c = math.min(cap, ecount)
        out[i] = c; ecount = ecount - c
        if ecount <= 0 then break end
    end
    return out
end

-- FUSION (the up-the-table climb). do_merge launches the assembled chunk at the main
-- nucleus; the particle counts land on impact (apply_fusion, called from advance). Fusion
-- up to iron is exothermic (a bright energy flash); heavier is endothermic — real stellar
-- nucleosynthesis.
local function apply_fusion(f)
    local g = M.g
    local exo = (M.atom.protons + f.p) <= IRON_Z -- fusion below iron releases energy
    M.atom.protons = math.min(data.MAX_Z, M.atom.protons + f.p)
    M.atom.neutrons = M.atom.neutrons + f.n
    for _ = 1, f.e do if not add_electron_juicy() then break end end
    for _, sh in ipairs(M.atom.shells) do sh.locked = #sh.e >= sh.cap end
    M.discovered[M.atom.protons] = true
    M.acted = true
    M.chain = {}
    M.flash = exo and 1.4 or 0.8
    M.gamma = { t = 0.0 } -- radiative capture (n,gamma): the compound nucleus sheds a gamma
    set_lastrad("gamma", "radiative capture")
    M.hold = HOLD_DUR
    M.sw = { r = g.nucR, spd = (g.unit * (exo and 0.78 or 0.5) - g.nucR) / SW_DUR, alpha = 1.0 }
    M.wob = { t = 0.0, amp = g.unit * 0.035, dx = 1.0, dy = 0.0 }
    thump(); sfx(SFX_LOCK)
end

local function do_merge()
    local s = M.stage
    if s.p + s.n + s.e == 0 then return end
    -- energetics gate: fusion past the iron peak (Z>26) is endothermic — it doesn't proceed
    -- spontaneously. It needs stellar energy (heat/pressure = a supernova core). Otherwise the
    -- real path to heavier elements is NEUTRON CAPTURE: add neutrons -> beta- decay (s/r-process),
    -- so pure neutron/electron merges are always allowed.
    if s.p > 0 and (M.atom.protons + s.p) > IRON_Z and not (M.cat.heat or M.cat.pressure) then
        M.toast = { msg = "endothermic past iron (Z>26): enable heat/pressure, or go heavier by neutron capture (add n -> beta-)", age = 0.0 }
        sfx(SFX_THUMP)
        return
    end
    M.fusing = { t = 0.0, p = s.p, n = s.n, e = s.e } -- fly the chunk in from the staging pad
    M.stage = { p = 0, n = 0, e = 0 }
    sfx(SFX_THUMP)
end

-- FISSION (the down-the-table split). Fire a neutron into a heavy nucleus (actinides,
-- Z>=FISSION_Z): it absorbs the neutron and splits into two lighter fragments + a few free
-- neutrons + energy, exactly like a reactor / U-235. Asymmetric ~40/60 split; the main atom
-- keeps the heavier fragment, the lighter one and the free neutrons fly off.
local function can_fission() return M.atom.protons >= FISSION_Z end

local function start_fission()
    if not can_fission() or M.fusing or M.fission then return end
    local g = M.g
    M.fission = { phase = "in", t = 0.0, nx = g.w + g.unit * 0.05, ny = g.cy, parts = nil }
end

-- decay-chain breadcrumb: record each spontaneous step (seeded with the starting isotope).
local function chain_push(from, to)
    if #M.chain == 0 then M.chain[1] = from end
    M.chain[#M.chain + 1] = to
end

-- Shared by neutron-induced fission (absorbed = 1) and SPONTANEOUS fission (absorbed = 0):
-- the nucleus splits ~40/60, the main atom keeps the heavy fragment, the light fragment and
-- a few free neutrons fly off.
local function split_nucleus(absorbed)
    local g = M.g
    local z, n = M.atom.protons, M.atom.neutrons
    local from = iso_name()
    local kfree = (n >= 6) and 3 or 2                    -- free neutrons released (~2.4 avg)
    local z1 = math.max(1, math.floor(z * 0.42 + 0.5))   -- light fragment protons
    local z2 = math.max(1, z - z1)                       -- heavy fragment protons (kept)
    local navail = math.max(0, n + absorbed - kfree)
    local n1 = math.min(navail, math.floor(navail * (z1 / z) + 0.5))
    local n2 = navail - n1
    M.atom.protons, M.atom.neutrons = z2, n2             -- the main atom becomes the heavy fragment
    reneutralize()
    M.discovered[z1] = true; M.discovered[z2] = true
    local parts = {}
    parts[#parts + 1] = { kind = "frag", z = z1, n = n1, life = 1.0, x = g.cx, y = g.cy,
        vx = math.cos(math.pi + 0.35) * g.unit * 0.85, vy = math.sin(math.pi + 0.35) * g.unit * 0.85 }
    for i = 1, kfree do
        local a = (i / kfree) * TAU + 0.3
        parts[#parts + 1] = { kind = "n", life = 1.0, x = g.cx, y = g.cy,
            vx = math.cos(a) * g.unit * 1.4, vy = math.sin(a) * g.unit * 1.4 }
    end
    M.fission = M.fission or { t = 0.0 } -- spontaneous fission arrives with no "in" phase
    M.fission.parts = parts
    M.fission.phase = "out"; M.fission.t = 0.0
    M.flash = 1.5
    M.gamma = { t = 0.0, tag = true } -- prompt fission gammas from the highly-excited fragments
    M.hold = HOLD_DUR
    M.sw = { r = g.nucR, spd = (g.unit * 0.85 - g.nucR) / SW_DUR, alpha = 1.0 }
    M.wob = { t = 0.0, amp = g.unit * 0.04, dx = 1.0, dy = 0.0 }
    local le, he = data.get(z1), data.get(z2)
    M.toast = { msg = string.format("%s%s  ->  %s-%d + %s-%d + %dn", from, absorbed > 0 and " + n" or "",
        he and he.sym or "?", z2 + n2, le and le.sym or "?", z1 + n1, kfree), age = 0.0 }
    M.stats.decays = (M.stats.decays or 0) + 1
    if absorbed > 0 then M.chain = {} -- player-fired: not part of a spontaneous chain
    else chain_push(from, iso_name()) end
    set_lastrad("fission", absorbed > 0 and "induced fission" or "spontaneous fission")
    sfx(SFX_LOCK)
end

local function apply_fission() split_nucleus(1) end

-- Decay: one step toward the stable valley -----------------------------------
local function decay_step()
    local g = M.g
    local z, n = M.atom.protons, M.atom.neutrons
    local from = iso_name()
    -- REAL dominant mode when the nuclide is charted (data.nuclides covers every principal
    -- isotope, all four natural decay chains, and the reported superheavy chains — so U-238
    -- walks the textbook alpha/beta- zigzag to Pb-206). Heuristics fire only off that map.
    local mode = data.mode_of(z, n)
    if not mode then
        if z > 83 then
            -- uncharted heavy: neutron-rich beta-decays back toward the valley, else alpha;
            -- past Z=100 a high fissility parameter (Z^2/A > 41) tears it apart instead.
            if z > 100 and (z * z) / (z + n) > 41.0 then mode = "sf"
            elseif n > data.principal(z) and z < data.MAX_Z then mode = "betam"
            else mode = "alpha" end
        else
            local lo, hi = data.stable_span(z)
            if not data.has_stable(z) then
                -- Tc / Pm: NO stable N exists — the valley bottom itself decays (Tc-98 goes
                -- beta-, Pm-145 electron-captures; proton-rich isotopes go EC/beta+ as usual).
                if z == 61 or n < data.principal(z) then lo, hi = n + 1, n + 1
                else lo, hi = n - 1, n - 1 end
            elseif n >= lo and n <= hi and not data.is_stable(z, n) then
                -- an in-band HOLE (K-40, Cl-36, Kr-85, Zr-93): beta- dominates in practice
                lo, hi = n - 1, n - 1
            end
            if n > hi then
                mode = (z < data.MAX_Z) and "betam" or "nemit"
            elseif n < lo then
                -- beta+ needs Q > 1.022 MeV (light nuclei's steep mass parabolas provide it);
                -- heavy proton-rich nuclei electron-capture. Charted isotopes carry their
                -- real mode above; this threshold covers only the unknown.
                mode = (z >= EC_Z) and "ec" or "betap"
            else
                return
            end
        end
    end
    if mode == "sf" then split_nucleus(0); return end
    local txt, radkey
    if mode == "alpha" then
        M.atom.protons, M.atom.neutrons = math.max(1, z - 2), math.max(0, n - 2)
        M.emit = { kind = "a" }; txt = "alpha decay"; radkey = "alpha"
    elseif mode == "betam" then
        M.atom.protons, M.atom.neutrons = z + 1, n - 1
        M.emit = { kind = "e" }; txt = "beta- decay"; radkey = "betam"
    elseif mode == "nemit" then
        M.atom.neutrons = n - 1
        M.emit = { kind = "n" }; txt = "neutron emission"; radkey = "n"
    elseif mode == "ec" then
        M.atom.protons, M.atom.neutrons = math.max(1, z - 1), n + 1
        M.emit = { kind = "e", inward = true }; txt = "electron capture"; radkey = "ec"
    else -- betap
        M.atom.protons, M.atom.neutrons = math.max(1, z - 1), n + 1
        M.emit = { kind = "p" }; txt = "beta+ decay"; radkey = "betap"
    end
    mode = txt
    reneutralize()
    M.discovered[M.atom.protons] = true
    M.flash = 1.0
    M.gamma = { t = 0.0, tag = true } -- excited daughter relaxes to ground, emitting a gamma photon
    M.wob = { t = 0.0, amp = g.unit * 0.022, dx = math.cos(M.clock * 2.3), dy = math.sin(M.clock * 2.3) }
    local ang = (M.clock * 2.3) % TAU
    if M.emit.inward then                   -- electron capture: an inner e- falls INTO the nucleus
        local R = g.unit * 0.16
        M.emit.x, M.emit.y = g.cx + math.cos(ang) * R, g.cy + math.sin(ang) * R
        M.emit.vx, M.emit.vy = -math.cos(ang) * R / EMIT_DUR, -math.sin(ang) * R / EMIT_DUR
    else                                    -- everything else emits a particle outward
        M.emit.x, M.emit.y = g.cx, g.cy
        M.emit.vx, M.emit.vy = math.cos(ang) * g.unit * 1.3, math.sin(ang) * g.unit * 1.3
    end
    M.emit.life = 1.0
    M.toast = { msg = from .. "   ->   " .. iso_name() .. "     " .. mode, age = 0.0 }
    M.stats.decays = M.stats.decays + 1
    chain_push(from, iso_name())
    set_lastrad(radkey, mode)
    sfx(SFX_LOCK)
end

-- Catches -------------------------------------------------------------------
-- begin a coalesce; ionic bonds run longer to fit the electron-transfer beat first.
local function start_bond(kind)
    local r = data.reactions[kind]
    M.bonding = { kind = kind, t = 0.0, dur = (r and r.ionic) and (BOND_DUR * 1.6) or BOND_DUR }
end

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
    M.frame = (M.frame or 0) + 1
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
    if inst > 0 and not M.card and not M.held_id and not M.fusing and not M.fission then -- pause while pouring/animating
        if not M.decay then
            -- the game clock breathes with the REAL half-life (log-compressed): U-238's
            -- 4.5 Gy gives you ~4.3s to act; Og-294's 0.7 ms is gone in about a second.
            local hs = data.halflife_s(M.atom.protons, M.atom.neutrons)
            local t = 1.0 + 0.155 * (math.log(hs) / math.log(10) + 4.0)
            if t < DECAY_MIN then t = DECAY_MIN elseif t > 6.0 then t = 6.0 end
            M.decay = { t = t, dur0 = 0, hl = data.fmt_hl(hs) }
        end
        M.decay.dur0 = math.max(M.decay.dur0, M.decay.t)
        M.decay.t = M.decay.t - dt
        -- throttle nucleus tremble: heavy atoms every 4th frame (hold-skip 3/4), light every 3rd.
        local trem = (electrons() > E_GLOW_MAX) and 4 or 3
        if (M.frame % trem) == 0 then
            local a = g.unit * 0.006 * (0.6 + inst * 0.5)
            g.tx = a * math.sin(M.clock * 41.0)
            g.ty = a * math.sin(M.clock * 37.0 + 1.3)
        end
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
    if M.gamma then
        M.gamma.t = M.gamma.t + dt / GAMMA_DUR
        if M.gamma.t >= 1.0 then M.gamma = nil end
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
        M.bonding.t = M.bonding.t + dt / (M.bonding.dur or BOND_DUR)
        if M.bonding.t >= 1.0 then
            local m = data.molecules[M.bonding.kind]
            local rr = data.reactions[M.bonding.kind]
            M.molecule = { kind = M.bonding.kind }
            -- onto the shelf: molecules are the bench's reagents (species stoichiometry)
            M.shelf[M.bonding.kind] = (M.shelf[M.bonding.kind] or 0) + 1
            M.mol_disc[M.bonding.kind] = true
            M.bonding = nil
            M.hold = HOLD_DUR
            M.card = { el = { sym = m.sym, name = m.name, lore = m.lore, eq = rr and rr.eq }, age = 0.0 }
            sfx(SFX_CARD)
        end
    end
    -- fusion: the assembled chunk slams in, counts land on impact
    if M.fusing then
        M.fusing.t = M.fusing.t + dt / FUSE_DUR
        if M.fusing.t >= 1.0 then apply_fusion(M.fusing); M.fusing = nil end
    end
    -- fission: neutron flies in, then fragments + free neutrons fly out
    if M.fission then
        if M.fission.phase == "in" then
            M.fission.t = M.fission.t + dt / FISS_IN
            local er = clamp01(M.fission.t); er = er * er -- accelerate into the nucleus
            M.fission.nx = lerp(g.w + g.unit * 0.05, g.cx, er)
            M.fission.ny = g.cy
            if M.fission.t >= 1.0 then apply_fission() end
        else
            M.fission.t = M.fission.t + dt / FISS_OUT
            for _, p in ipairs(M.fission.parts) do
                p.x = p.x + p.vx * dt; p.y = p.y + p.vy * dt
                p.life = clamp01(1.0 - M.fission.t)
            end
            if M.fission.t >= 1.0 then M.fission = nil end
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
    -- quest catalog: pick any element/molecule as the target. Modal while open.
    local qb = runtime_ui.get_state(SCREEN, "questbtn")
    if qb and qb.clicked then M.questOpen = not M.questOpen; return end
    if M.questOpen then
        for z = 1, data.MAX_Z do
            local st = runtime_ui.get_state(SCREEN, "q_el" .. z)
            if st and st.clicked then
                M.target = { kind = "el", z = z }
                M.questOpen = false
                reset_atom()
                return
            end
        end
        for i, key in ipairs(data.mol_list) do
            local st = runtime_ui.get_state(SCREEN, "q_mol" .. i)
            if st and st.clicked then
                M.target = { kind = "mol", key = key }
                M.questOpen = false
                reset_atom()
                return
            end
        end
        return -- swallow everything else while the catalog is open
    end
    local rs = runtime_ui.get_state(SCREEN, "reset")
    if rs and rs.clicked then reset_atom(); return end
    local ts = runtime_ui.get_state(SCREEN, "target_btn")
    if ts and ts.clicked then new_target(); return end
    for _, c in ipairs(CATALYSTS) do
        local cs = runtime_ui.get_state(SCREEN, "cat_" .. c)
        if cs and cs.clicked then M.cat[c] = not M.cat[c]; return end
    end
    local fsn = runtime_ui.get_state(SCREEN, "fission")
    if fsn and fsn.clicked then start_fission(); M.held_id = nil; return end
    -- atom view dropdown: toggle open, or pick a mode
    local vb = runtime_ui.get_state(SCREEN, "viewbtn")
    if vb and vb.clicked then M.viewOpen = not M.viewOpen; return end
    if M.viewOpen then
        for _, v in ipairs(VIEWS) do
            local vs = runtime_ui.get_state(SCREEN, "view_" .. v.key)
            if vs and vs.clicked then M.view = v.key; M.viewOpen = false; return end
        end
    end

    if M.card then
        local cs = runtime_ui.get_state(SCREEN, "card")
        if cs and cs.clicked then M.card.age = math.max(M.card.age, CARD_HOLD) end
        return
    end

    -- bench reactions stay clickable even while a finished molecule is on display
    for i = 1, 3 do
        local s = M._bench and M._bench[i]
        if s then
            local bs = runtime_ui.get_state(SCREEN, "bench" .. i)
            if bs and bs.clicked then
                if reqs_met(s) then bench_react(s)
                else M.toast = { msg = "needs: " .. table.concat(reqs_of(s), " + "), age = 0.0 } end
                return
            end
        end
    end

    -- once bonded, or mid-coalesce / fusion / fission, the atom builder is inert.
    if M.molecule or M.bonding or M.fusing or M.fission then return end
    -- coalesce is a gesture: grab the reagent and drag it into the atom. It only fires when
    -- the reaction's real catalyst + condition are present. Click (no drag) binds too.
    local r = reaction_kind()
    if r and reqs_met(r) and not M.fly then
        local bs = runtime_ui.get_state(SCREEN, "bond_src")
        if bs then
            if bs.drag_started then
                M.fly = { kind = "bond", mol = r.product, psym = r.partner, state = "drag", src = "bond_src",
                    x = bs.mouse_x or g.cx, y = bs.mouse_y or g.cy }
                return
            elseif bs.clicked and not bs.dragging then
                start_bond(r.product); return
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
                    if d < g.catchR then start_bond(M.fly.mol) end
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

    -- MERGE: fuse the assembled left-hand atom into the main atom in one jump.
    local mgs = runtime_ui.get_state(SCREEN, "merge")
    if mgs and mgs.clicked then do_merge(); M.held_id = nil; return end

    -- assembly steppers: [+] and [-] both tap once / stream while held.
    local held
    for _, st in ipairs(STEPPERS) do
        local pls = runtime_ui.get_state(SCREEN, st.plus)
        if pls and pls.down then held = { id = st.plus, kind = st.kind, dir = 1 } end
        local ms = runtime_ui.get_state(SCREEN, st.minus)
        if ms and ms.down then held = { id = st.minus, kind = st.kind, dir = -1 } end
    end
    if held then
        if M.held_id ~= held.id then stage_add(held.kind, held.dir) end -- newly pressed: instant step
        M.held_id, M.held_kind, M.held_dir = held.id, held.kind, held.dir
    else
        M.held_id = nil
    end
end

-- Drawing -------------------------------------------------------------------
-- draw a nucleus (protons orange + neutrons grey, golden-angle packed) at (x,y). Heavy
-- nuclei cap the dot count and add a solid core so they read solid, not as a dot cloud.
-- returns its glow radius so callers can place bonds relative to it.
local function draw_nucleus(idp, x, y, protons, neutrons, al, cap, ballcol)
    al = al or 1.0
    cap = cap or NUC_MAX_DOTS
    local g = M.g
    local total = protons + neutrons
    local nucR = g.nucR * (0.62 + 0.11 * math.sqrt(math.max(1, total)))
    -- ball-and-stick mode (molecule view): one solid CPK-tinted sphere per atom instead of a
    -- proton-cloud + soft glow. The cloud's ~8 overlapping alpha dots per atom are pure
    -- overdraw at molecule scale (measured 7.4ms -> 2.4ms for CCl4); a ball is also the
    -- correct molecule metaphor. The nucleon cloud stays in the atom view + assemble replica.
    if ballcol then
        dot(idp .. "b", x, y, nucR * 2.0, col(ballcol, al), 22.0)
        return nucR
    end
    dot(idp .. "g", x, y, nucR * 3.0, col(C_NUCGLOW, C_NUCGLOW[4] * al), 18.0)
    local shown = math.min(total, cap)
    if total > cap then dot(idp .. "core", x, y, nucR * 1.7, col(C_PROTON, 0.5 * al), 21.0) end
    for i = 1, shown do
        local a = i * 2.399963
        -- pack from the CENTRE out: nucleon 1 sits dead centre, each new one accretes onto
        -- the rim, and the whole cluster grows with mass (sqrt(i/shown) left the centre
        -- empty — a lone proton drew at the rim).
        local rr = nucR * 0.82 * math.sqrt((i - 1) / math.max(1, shown - 1))
        dot(idp .. i, x + math.cos(a) * rr, y + math.sin(a) * rr, g.dp,
            col((i / shown) <= (protons / math.max(1, total)) and C_PROTON or C_NEUTRON, al), 22.0)
    end
    return nucR
end

-- pick + draw the outermost electron's real orbital texture (|psi|^2) for `e` electrons,
-- centred at (x,y), sized so its lobes reach the atom's outer radius R. Shared by the main
-- cloud view, the ASSEMBLE preview, and the MERGE fly-in so all three match.
local function draw_orbital(idp, x, y, e, R, alpha_mul)
    local cfg = data.config(e)
    local val = cfg[#cfg]
    if not val then return end
    local l = val.l
    local m = -l + ((val.e - 1) % (2 * l + 1))
    local side = R * 2.2
    local frac = clamp01(val.e / (2 * (2 * l + 1)))
    quad(idp, { x = x - side * 0.5, y = y - side * 0.5, width = side, height = side, z = 13.0,
        style = "image", path = "orbital_" .. val.n .. data.L_CHAR[l] .. "_m" .. math.abs(m) .. ".png",
        image_tint = { 1, 1, 1, math.min(1.0, (0.55 + 0.45 * frac) * alpha_mul) },
        fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, no_input = true })
end

-- a complete atom in the SELECTED view (Bohr rings+electrons OR the orbital cloud) plus its
-- nucleus, at (x,y) with outer shell radius R, faded by `al`. Nucleons stay full size (a
-- proton is a proton — same everywhere); only the electron cloud scales with R. Used for the
-- left ASSEMBLE preview and the MERGE fly-in replica.
local function mini_atom(idp, x, y, p, n, e, R, al)
    local g = M.g
    if M.view == "cloud" then
        draw_orbital(idp .. "orb", x, y, e, R, al)
    else
        local esh = (M.view == "shells") and n_shell_occ(e) or stage_shells(e)
        local nr = math.max(1, #esh)
        local r0 = R * 0.33
        local step = nr > 1 and (R - r0) / (nr - 1) or 0
        for i = 1, nr do ring(idp .. "ring" .. i, x, y, r0 + (i - 1) * step, col(C_RING, al * 0.7), 12.0) end
        for si = 1, nr do
            local cnt = esh[si] or 0
            for k = 1, math.min(cnt, E_MAX_PER_RING) do
                local ang = M.clock * 0.6 + (k - 1) / math.max(1, cnt) * TAU + si
                local rr = r0 + (si - 1) * step
                dot(idp .. "e" .. si .. "_" .. k, x + math.cos(ang) * rr, y + math.sin(ang) * rr,
                    g.de, col(C_ELEC, math.min(1.0, al + 0.35)), 30.0)
            end
        end
    end
    draw_nucleus(idp .. "n", x, y, p, n, math.min(1.0, al + 0.30))
end

-- the in-flight ghost of the bond partner you drag toward the atom: a CPK-tinted ball
-- with one orbiting electron. `s` scales it.
local function draw_partner_ghost(idp, x, y, s, z, sym)
    local g = M.g
    local c = CPK[sym or "H"] or C_PROTON
    dot(idp .. "g", x, y, g.de * 2.4 * s, col(c, 0.20), z)
    dot(idp .. "p", x, y, g.dp * 1.4 * s, c, z + 1.0)
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

    if m.render == "lattice" then
        -- IONIC: no shared cloud. Phase 1 (bonding only): the ELECTRON TRANSFER — the
        -- metal's valence electron(s) visibly leap to the incoming nonmetal, because that
        -- jump IS the ionic bond. Phase 2: the charged ions snap into a grid in the exact
        -- a:b ratio (1:1 = rock-salt checkerboard), anions bigger, cations smaller.
        local tt = M.bonding and clamp01(M.bonding.t) or 1.0
        local XFER = 0.42
        local ccol = CPK[m.cation] or C_PROTON
        local acol = CPK[m.anion] or C_NEUTRON
        if M.bonding and tt < XFER then
            local et = ease_out(tt / XFER)
            local ax = cx + lerp(g.unit * 0.52, g.unit * 0.17, et) -- the anion glides in
            dot("latxmg", cx, cy, g.nucR * 4.4, col(ccol, 0.16), 18.0)
            dot("latxm", cx, cy, g.nucR * 2.2, ccol, 22.0)
            dot("latxag", ax, cy, g.nucR * 6.0, col(acol, 0.14), 18.0)
            dot("latxa", ax, cy, g.nucR * 3.0, acol, 22.0)
            for k = 1, m.chg do -- one hop per transferred electron, slightly staggered
                local ek = clamp01((et - (k - 1) * 0.12) / 0.82)
                local ex = lerp(cx, ax, ek)
                local ey = cy - math.sin(ek * math.pi) * g.unit * 0.055 - (k - 1) * g.unit * 0.012
                dot("latxeh" .. k, ex, ey, g.de * 2.0, col(C_ELECGLW, 0.22), 29.0)
                dot("latxe" .. k, ex, ey, g.de, C_ELEC, 30.0)
            end
            label("latxlbl", cx, cy + g.unit * 0.10, g.unit * 0.7, g.unit * 0.035,
                string.format("%s gives %d electron%s  ->  %s", m.cation, m.chg,
                    m.chg > 1 and "s" or "", m.anion), C_DIMTEXT, 1.5, 41.0)
        else
            local prog2 = M.bonding and ease_out(clamp01((tt - XFER) / (1.0 - XFER))) or 1.0
            local cols, rows = 4, 3
            local pitch = g.unit * 0.075
            local x0, y0 = cx - (cols - 1) * 0.5 * pitch, cy - (rows - 1) * 0.5 * pitch
            local ab = m.a + m.b
            for i = 0, cols * rows - 1 do
                local ri = math.floor(i / cols)
                local ci = i % cols
                local isCat
                if ab == 2 then isCat = ((ci + ri) % 2) == 0        -- 1:1 rock-salt checkerboard
                else isCat = ((i * m.a) % ab) < m.a end             -- exact-ratio spread (1:2, 2:3...)
                local gx, gy = x0 + ci * pitch, y0 + ri * pitch
                local ex = M.bonding and lerp(cx + (gx - cx) * 2.6, gx, prog2) or gx
                local ey = M.bonding and lerp(cy + (gy - cy) * 2.6, gy, prog2) or gy
                local jx, jy = jit(i * 1.3)
                local d = isCat and g.nucR * 1.5 or g.nucR * 2.4
                dot("lat" .. i, ex + jx * 0.5, ey + jy * 0.5, d, col(isCat and ccol or acol, 0.55 + 0.45 * prog2), 22.0)
            end
            label("lat_legend", cx, y0 + rows * pitch + g.unit * 0.005, g.unit * 0.6, g.unit * 0.04,
                string.format("%s%s / %s%s   ionic lattice", m.cation, string.rep("+", m.chg),
                    m.anion, string.rep("-", m.achg)), C_DIMTEXT, 1.5, 41.0)
        end
    elseif m.render == "diatomic" then
        local pz, pn = partner_pn(m.core)
        local bd = g.unit * (m.core == "H" and 0.062 or 0.085)
        local lx = cx - bd
        local rx = M.bonding and lerp(g.cx + g.unit * 0.55, cx + bd, prog) or (cx + bd)
        local mid = (lx + rx) * 0.5
        local jlx, jly = jit(0.0)
        local jrx, jry = jit(3.1)
        dot("bondglow", mid, cy, g.nucR * 2.8, col(C_ELEC, 0.10 + 0.24 * prog), 19.0)
        local ccol = CPK[m.core] or C_PROTON
        draw_nucleus("molL", lx + jlx, cy + jly, pz, pn, nil, nil, ccol)
        draw_nucleus("molR", rx + jrx, cy + jry, pz, pn, nil, nil, ccol)
        for i = 0, 1 do
            local ang = M.clock * 1.3 + i * math.pi
            local ex = mid + math.cos(ang) * (bd + g.de * 1.6)
            local ey = cy + math.sin(ang) * g.radii[1] * 0.85
            dot("mole" .. i, ex, ey, g.de, C_ELEC, 30.0)
        end
    else -- central: the built core atom + partner atoms bonded around it
        local dCP = g.unit * 0.135
        local jcx, jcy = jit(0.0)
        local cR = draw_nucleus("molC", cx + jcx, cy + jcy, M.atom.protons, M.atom.neutrons, nil, nil, CPK[m.core] or C_PROTON)
        for idx, pa in ipairs(m.partners) do
            local sym, a = pa[1], pa[2]
            local pz, pn = partner_pn(sym)
            local r = M.bonding and lerp(g.unit * 0.6, dCP, prog) or dCP
            local jx, jy = jit(idx * 2.0)
            local hx, hy = cx + math.cos(a) * r + jx, cy + math.sin(a) * r + jy
            dot("molbond" .. idx, cx + math.cos(a) * dCP * 0.55, cy + math.sin(a) * dCP * 0.55,
                g.de * 2.2, col(C_ELEC, 0.12 + 0.2 * prog), 19.0) -- shared bonding pair
            draw_nucleus("molP" .. idx, hx, hy, pz, pn, nil, nil, CPK[sym] or C_PROTON)
        end
        -- lone pairs on the core sit OPPOSITE the bonds - they're what bend the molecule. Tuck
        -- them tight against the nucleus as dim little pairs, not free-drifting electrons.
        local lp_e = m.lone or 0
        if lp_e >= 2 and #m.partners > 0 then
            local bx, by = 0.0, 0.0
            for _, pa in ipairs(m.partners) do bx = bx + math.cos(pa[2]); by = by + math.sin(pa[2]) end
            local base = (bx == 0 and by == 0) and (-math.pi * 0.5) or math.atan(-by, -bx) -- away from bonds
            local npair = math.floor(lp_e / 2)
            for p = 1, npair do
                local ang = base + (p - (npair + 1) * 0.5) * 0.6
                local px, py = cx + math.cos(ang) * (cR + g.de * 1.3), cy + math.sin(ang) * (cR + g.de * 1.3)
                local perp = ang + math.pi * 0.5
                for _, s in ipairs({ -1, 1 }) do
                    dot("mololp" .. p .. "_" .. (s + 1), px + math.cos(perp) * g.de * s * 0.45,
                        py + math.sin(perp) * g.de * s * 0.45, g.de * 0.55, col(C_ELEC, 0.45), 19.0)
                end
            end
        end
    end

    label("mol_sym", g.cx, g.iy, g.unit * 0.5, g.unit * 0.09,
        m.sym, col(C_LOCK, math.min(1.0, 0.9 * g.bright)), 3.6, 41.0)
    if M.molecule then
        label("mol_sub", g.cx, g.iy + g.unit * 0.075, g.unit * 0.7, g.unit * 0.045,
            string.lower(m.name), C_DIMTEXT, 1.7, 41.0)
    end
end

-- The faint left-hand assembly atom + its manual steppers + the MERGE button. The player
-- dials protons/neutrons/electrons here, watches the preview name the isotope, then MERGEs
-- the chunk into the main atom. Nothing auto-fills — every particle is placed by hand.
local function draw_stage()
    local g, s = M.g, M.stage
    local x, y = g.sx, g.sy
    local FA = 0.40 -- faint alpha for the "not yet real" staging atom

    label("st_hdr", x, y - g.unit * 0.185, g.unit * 0.30, g.unit * 0.04, "ASSEMBLE", col(C_HINT, 0.75), 1.6, 41.0)

    -- the assembly atom in the currently-selected representation (Bohr or orbital cloud).
    local nr = math.max(1, #stage_shells(s.e))
    mini_atom("st", x, y, s.p, s.n, s.e, g.sr0 + (nr - 1) * g.srstep, FA)

    local rows = { { kind = "p", lbl = "protons", c = C_PROTON, v = s.p },
                   { kind = "n", lbl = "neutrons", c = C_NEUTRON, v = s.n },
                   { kind = "e", lbl = "electrons", c = C_ELEC, v = s.e } }
    for i, r in ipairs(rows) do
        local ry = g.stepy + (i - 1) * g.stepdy
        local onm = M.held_id == ("st_" .. r.kind .. "_minus")
        quad("st_" .. r.kind .. "_minus", { x = x - g.stgap - g.stbtn * 0.5, y = ry - g.stbtn * 0.5,
            width = g.stbtn, height = g.stbtn, z = 46.0, style = "button", title = "-", font_scale = 2.2,
            fill = onm and { 0.16, 0.20, 0.10, 0.95 } or { 0.10, 0.12, 0.16, 0.9 },
            border = col(r.c, onm and 0.95 or 0.5), accent = col(r.c, onm and 0.9 or 0.7),
            text_color = { 0.9, 0.92, 0.96, 1.0 } })
        label("st_" .. r.kind .. "_v", x, ry - g.unit * 0.020, g.unit * 0.14, g.unit * 0.05, tostring(r.v), col(r.c, 1.0), 2.6, 41.0)
        label("st_" .. r.kind .. "_l", x, ry + g.unit * 0.020, g.unit * 0.18, g.unit * 0.03, r.lbl, C_DIMTEXT, 1.2, 41.0)
        local on = M.held_id == ("st_" .. r.kind .. "_plus")
        quad("st_" .. r.kind .. "_plus", { x = x + g.stgap - g.stbtn * 0.5, y = ry - g.stbtn * 0.5,
            width = g.stbtn, height = g.stbtn, z = 46.0, style = "button", title = "+", font_scale = 2.2,
            fill = on and { 0.16, 0.20, 0.10, 0.95 } or { 0.10, 0.12, 0.16, 0.9 },
            border = col(r.c, on and 0.95 or 0.6), accent = col(r.c, 0.9),
            text_color = { 0.95, 0.95, 0.98, 1.0 } })
    end

    -- MERGE + a live preview of the isotope the chunk will make (gold when it hits the target).
    local rp = math.min(data.MAX_Z, M.atom.protons + s.p)
    local rn = M.atom.neutrons + s.n
    local re = electrons() + s.e
    local rel = data.get(rp)
    local any = (s.p + s.n + s.e) > 0
    local hit = M.target and M.target.kind == "el" and M.target.z == rp and re == rp
    quad("merge", { x = x - g.mergew * 0.5, y = g.mergey, width = g.mergew, height = g.mergeh, z = 46.0,
        style = "button", title = "MERGE", font_scale = 2.0,
        fill = any and { 0.10, 0.16, 0.11, 0.95 } or { 0.08, 0.09, 0.12, 0.7 },
        border = hit and C_LOCK or col(C_ELEC, any and 0.7 or 0.3), accent = col(C_LOCK, 0.85),
        text_color = any and { 0.90, 0.96, 0.90, 1.0 } or { 0.6, 0.65, 0.72, 0.8 } })
    if any and rel then
        label("merge_pv", x, g.mergey + g.mergeh + g.unit * 0.012, g.unit * 0.42, g.unit * 0.036,
            string.format("makes  %s-%d  %s", rel.sym, rp + rn, (re == rp) and "neutral" or (re < rp and "ion+" or "ion-")),
            hit and col(C_LOCK, 0.95) or C_DIMTEXT, 1.4, 41.0)
    end
end

local CAT_NAME = {
    alkali = "Alkali metal", alkaline = "Alkaline-earth metal", transition = "Transition metal",
    posttransition = "Post-transition metal", metalloid = "Metalloid", nonmetal = "Nonmetal",
    halogen = "Halogen", noble = "Noble gas", lanthanide = "Lanthanide", actinide = "Actinide",
}

-- tooltip for a discovered board element: name, symbol, ATOMIC NUMBER, category, common
-- isotope, and its one-line lore. Sits below the cursor (the board is up top), clamped on-screen.
local function draw_element_tip(z, mx, my)
    local g = M.g
    local e = data.get(z)
    if not e then return end
    local tw, th = g.unit * 0.40, g.unit * 0.21
    local tx = math.max(g.unit * 0.01, math.min(mx + g.unit * 0.015, g.w - tw - g.unit * 0.01))
    local ty = math.max(g.unit * 0.01, math.min(my + g.unit * 0.02, g.h - th - g.unit * 0.01))
    local mass0 = e.z + data.principal(e.z)
    -- t1/2 implies radioactive; the word itself would overflow the non-wrapping footer.
    local stable = data.has_stable(e.z) and "stable"
        or ("t1/2 " .. data.fmt_hl(data.halflife_s(e.z, data.principal(e.z))))
    -- footer is a single non-wrapping line in the backend, so keep it short (it overflowed
    -- before); the atomic number lives in the corner label and the lore wraps in the body.
    quad("eltip", {
        x = tx, y = ty, width = tw, height = th, z = 63.0, style = "panel",
        font_scale = 1.8, bring_to_front = true, no_input = true,
        label = "Atomic number " .. e.z, title = e.name .. "   (" .. e.sym .. ")",
        body = (CAT_NAME[e.cat] or "Element") .. ".   " .. e.lore,
        footer = string.format("%s-%d   -   %s", e.sym, mass0, stable),
        fill = { 0.05, 0.06, 0.10, 0.98 }, border = C_LOCK,
        accent = { 1.00, 0.82, 0.34, 1.0 }, text_color = { 0.92, 0.94, 0.98, 1.0 },
    })
end

-- what each condition chip does + when to use it (real chemistry + the fusion gate).
local CHIP_TIP = {
    spark    = { t = "spark  -  ignition", b = "Activation energy that starts a reaction (a flame or lightning). Lights combustion.", f = "use: H2O, CO2" },
    heat     = { t = "heat  -  thermal energy", b = "Drives endothermic reactions; past the iron peak it also powers endothermic FUSION (a stellar core).", f = "use: CH4, NH3, SO3, sulfides  -  fusion Z>26" },
    pressure = { t = "pressure", b = "Pushes an equilibrium reaction toward its product (Le Chatelier). With heat, enables fusion past iron.", f = "use: NH3   -   fusion Z>26" },
    Fe       = { t = "Fe  -  iron catalyst", b = "Speeds a reaction without being used up. Iron catalyses the Haber process, N2 + 3H2 -> NH3.", f = "use: NH3 (Haber)" },
    Ni       = { t = "Ni  -  nickel catalyst", b = "Nickel catalyses hydrogenation - adding hydrogen onto carbon.", f = "use: CH4" },
    Pt       = { t = "Pt  -  platinum catalyst", b = "The Ostwald process: burns ammonia to NO on platinum gauze - the road from Haber to nitric acid.", f = "use: NO from NH3 (needs heat)" },
    V2O5     = { t = "V2O5  -  vanadium(V) oxide", b = "The Contact-process catalyst: oxidises SO2 to SO3 on its surface at ~450C.", f = "use: SO3 (needs heat)" },
}

local function draw_chip_tip(c, mx, my)
    local g, tip = M.g, CHIP_TIP[c]
    if not tip then return end
    local tw, th = g.unit * 0.42, g.unit * 0.20
    local tx = math.max(g.unit * 0.01, mx - tw - g.unit * 0.02) -- left of the cursor (chips hug the right edge)
    local ty = math.max(g.unit * 0.01, math.min(my, g.h - th - g.unit * 0.01))
    quad("chiptip", {
        x = tx, y = ty, width = tw, height = th, z = 63.0, style = "panel",
        font_scale = 1.7, bring_to_front = true, no_input = true,
        label = M.cat[c] and "ON" or "off", title = tip.t, body = tip.b, footer = tip.f,
        fill = { 0.05, 0.06, 0.10, 0.98 }, border = C_LOCK,
        accent = { 1.00, 0.82, 0.34, 1.0 }, text_color = { 0.92, 0.94, 0.98, 1.0 },
    })
end

-- ATOM VIEWS -----------------------------------------------------------------
-- shells/cloud behind the nucleus. Bohr = the gameplay period rings (lock/flare juice);
-- cloud = the outermost electron's real orbital as a baked 2D |psi|^2 texture.
local function draw_view_bg(acx, acy, bright)
    local g = M.g
    if M.view == "cloud" then
        -- the OUTERMOST electron's exact orbital psi_{n,l,m}, sized to the Bohr outer ring so
        -- both views read as the same-size atom (m from Hund's rule; +/-m share |psi|^2).
        draw_orbital("orbital", acx, acy, electrons(), g.rmax, bright)
    elseif M.view == "shells" then
        -- Aufbau-exact: one ring per principal shell n, occupancy from the real Madelung
        -- config; alpha tracks fill vs the true 2n^2 capacity. No lock juice — gameplay
        -- locking stays on the Bohr period rings. (Highest occupied n == period, so the
        -- period-ring radii fit as-is.)
        local occ, nmax = n_shell_occ(electrons())
        for si = 1, math.max(1, nmax) do
            local frac = (occ[si] or 0) / (2 * si * si)
            ring("ring" .. si, acx, acy, g.radii[si],
                col(C_RING, math.min(1.0, (0.24 + 0.66 * frac) * bright)), 12.0)
        end
    else -- bohr
        for si, sh in ipairs(M.atom.shells) do
            if si <= g.nrings then -- period rings + any extra shell an anion's electron occupies
                local base = sh.locked and 0.95 or (#sh.e > 0 and 0.55 or 0.28)
                local a = math.min(1.0, (base + sh.flare * 0.55) * bright)
                ring("ring" .. si, acx, acy, g.radii[si] * (1.0 + sh.flare * 0.03),
                    col(sh.locked and C_LOCK or C_RING, a), 12.0)
            end
        end
    end
end

-- electrons in front of the nucleus (bohr only; cloud's texture is the whole thing).
local function draw_view_fg(ecx, ecy, bright)
    local g = M.g
    if M.view == "cloud" then return end -- the orbital texture (draw_view_bg) is the whole cloud
    local glow = electrons() <= E_GLOW_MAX
    -- heavy atoms: orbit centre is g.cx/cy (no recoil wobble) so hold-skip isn't busted by the
    -- ~13px damped sine after every landing. Light atoms still follow acx/acy for juice wobble.
    if glow then ecx, ecy = g.acx, g.acy end
    -- continuous orbit; hold-skip while the dot stays on the same PIXEL (no dot(), no set_quad).
    -- Sub-pixel motion is invisible on a soft sprite, so this is as smooth as the display can
    -- show while still rate-limiting submits to each dot's pixel-crossing rate (and avoiding
    -- per-frame opts-table churn for dots that haven't visibly moved).
    local function edot(si, i, ex, ey)
        local px = math.floor(ex) * 16384.0 + math.floor(ey) -- packed pixel key
        local id = "e" .. si .. "_" .. i
        if M._eang[id] == px then
            M._live[id] = true
            if glow then M._live["eh" .. si .. "_" .. i] = true end
        else
            M._eang[id] = px
            if glow then dot("eh" .. si .. "_" .. i, ex, ey, g.de * 2.1, col(C_ELECGLW, math.min(1.0, C_ELECGLW[4] * bright)), 29.0) end
            dot(id, ex, ey, g.de, C_ELEC, 30.0)
        end
    end
    if M.view == "shells" then
        -- True-shells dots are DERIVED from the config (not the gameplay electron objects),
        -- spinning per-ring like the assembly preview.
        local occ, nmax = n_shell_occ(electrons())
        for si = 1, nmax do
            local cnt = math.min(occ[si] or 0, E_MAX_PER_RING)
            for i = 1, cnt do
                local ang = M.clock * (RING_SPIN[si] or 0.5) + (i - 1) / cnt * TAU + si * 1.1
                edot(si, i, ecx + math.cos(ang) * g.radii[si], ecy + math.sin(ang) * g.radii[si])
            end
        end
        return
    end
    for si, sh in ipairs(M.atom.shells) do
        for i = 1, math.min(#sh.e, E_MAX_PER_RING) do
            local ang = sh.phase + sh.e[i].spread
            edot(si, i, ecx + math.cos(ang) * g.radii[si], ecy + math.sin(ang) * g.radii[si])
        end
    end
end

local function draw()
    local g = M.g
    local acx, acy = g.acx, g.acy
    local ncx, ncy = acx + (g.tx or 0.0), acy + (g.ty or 0.0) -- nucleus adds tremble
    local bright = g.bright
    -- heavy atoms: rings+e- at screen centre (stable); nucleus trembles inside. Light atoms wobble.
    local ecx, ecy = g.cx, g.cy
    if electrons() <= E_GLOW_MAX then ecx, ecy = acx, acy end

    quad("bg", { x = 0, y = 0, width = g.w, height = g.h, z = 0.0,
        style = "panel", fill = C_BG, border = { 0, 0, 0, 0 }, no_input = true })

    if M.sw then ring("shock", ecx, ecy, M.sw.r, col(C_LOCK, M.sw.alpha), 15.0) end
    if M.gamma then -- gamma photon: a fast violet EM burst as the nucleus sheds excitation energy
        local gt = clamp01(M.gamma.t)
        local a = 1.0 - gt
        ring("gamma1", ncx, ncy, g.nucR * (1.0 + gt * 7.0), col(C_GAMMA, a * 0.85), 16.0)
        ring("gamma2", ncx, ncy, g.nucR * (1.0 + gt * 4.0), col(C_GAMMA, a * 0.55), 16.0)
        if M.gamma.tag then
            label("gammatag", ncx, ncy - g.rmax - g.unit * 0.03, g.unit * 0.2, g.unit * 0.04, "gamma", col(C_GAMMA, a), 1.6, 41.0)
        end
    end

    if M.molecule or M.bonding then draw_molecule() else

    draw_view_bg(ecx, ecy, bright)

    -- nucleus: protons (orange) + neutrons (grey) packed by golden angle; grows with mass;
    -- trembles when the isotope is unstable + a shrinking decay ring. Heavy nuclei cap the
    -- dot count and draw a solid core. Hold-skip when quantised position + flash step match.
    local total = mass()
    local nucR = g.nucR * (0.62 + 0.11 * math.sqrt(math.max(1, total)))
    if M.decay then
        local frac = math.floor(clamp01(M.decay.t / math.max(0.001, M.decay.dur0)) * 16.0) / 16.0
        if frac ~= M._drfq then
            M._drfq = frac
            local pr = nucR * (1.35 + 1.3 * frac)
            ring("decayring", ncx, ncy, pr, col(C_UNSTABLE, 0.35 + 0.45 * (1.0 - frac)), 17.0)
        else
            M._live["decayring"] = true
        end
    else
        M._drfq = nil
    end
    local nqx, nqy = math.floor(ncx), math.floor(ncy)
    local fq = math.floor(M.flash * 8.0) / 8.0
    local shown = math.min(total, NUC_MAX_DOTS)
    if nqx == M._nqx and nqy == M._nqy and fq == M._nfq then
        M._live["nucglow"] = true
        if total > NUC_MAX_DOTS then M._live["nuccore"] = true end
        for i = 1, shown do M._live["nuc" .. i] = true end
    else
        M._nqx, M._nqy, M._nfq = nqx, nqy, fq
        dot("nucglow", ncx, ncy, nucR * (3.0 + M.flash * 1.6), col(C_NUCGLOW, math.min(0.7, 0.22 + M.flash * 0.5)), 18.0)
        if total > NUC_MAX_DOTS then dot("nuccore", ncx, ncy, nucR * 1.7, col(C_PROTON, 0.5), 21.0) end
        for i = 1, shown do
            local a = i * 2.399963
            -- centre-out packing (see draw_nucleus): first nucleon dead centre, newest on the rim
            local rr = nucR * 0.82 * math.sqrt((i - 1) / math.max(1, shown - 1))
            local c = (i / shown) <= (M.atom.protons / math.max(1, total)) and C_PROTON or C_NEUTRON
            dot("nuc" .. i, ncx + math.cos(a) * rr, ncy + math.sin(a) * rr, g.dp, c, 22.0)
        end
    end

    draw_view_fg(ecx, ecy, bright)

    if M.emit then
        local c = M.emit.kind == "e" and C_ELEC
            or (M.emit.kind == "p" and C_POSITRON or (M.emit.kind == "a" and C_PROTON or C_NEUTRON))
        local a = clamp01(M.emit.life)
        dot("emith", M.emit.x, M.emit.y, g.de * 2.2, col(c, 0.18 * a), 51.0)
        dot("emit", M.emit.x, M.emit.y, g.de * 0.9, col(c, a), 52.0)
    end

    if M.fly then
        if M.fly.kind == "bond" then
            draw_partner_ghost("fly", M.fly.x, M.fly.y, 1.15, 50.0, M.fly.psym)
        else
            local c = M.fly.kind == "e" and C_ELEC or (M.fly.kind == "p" and C_PROTON or C_NEUTRON)
            dot("flyh", M.fly.x, M.fly.y, g.de * 2.6, col(c, 0.22), 49.0)
            dot("fly", M.fly.x, M.fly.y, g.de * (M.fly.kind == "e" and 1.15 or 1.0), c, 50.0)
        end
    end

    -- FUSION: the assembled atom (full replica in the selected view, just smaller) streaks in
    -- from the staging pad and slams the nucleus.
    if M.fusing then
        local er = clamp01(M.fusing.t); er = er * er
        local fx, fy = lerp(g.sx, acx, er), lerp(g.sy, acy, er)
        local nm = math.max(1, #stage_shells(M.fusing.e))
        local R_m = g.sr0 + (nm - 1) * g.srstep
        dot("fuseglow", fx, fy, R_m * 1.5, col(C_LOCK, 0.20 + 0.30 * M.fusing.t), 11.0)
        mini_atom("fuse", fx, fy, M.fusing.p, M.fusing.n, M.fusing.e, R_m, math.min(1.0, 0.6 + 0.4 * M.fusing.t))
    end

    -- FISSION: the fired neutron (phase "in"), then fragments + free neutrons (phase "out").
    if M.fission then
        if M.fission.phase == "in" then
            dot("fissnh", M.fission.nx, M.fission.ny, g.de * 2.0, col(C_NEUTRON, 0.25), 49.0)
            dot("fissn", M.fission.nx, M.fission.ny, g.de, C_NEUTRON, 50.0)
        else
            for i, p in ipairs(M.fission.parts) do
                local a = clamp01(p.life)
                if p.kind == "n" then
                    dot("fp" .. i .. "h", p.x, p.y, g.de * 1.8, col(C_NEUTRON, 0.20 * a), 51.0)
                    dot("fp" .. i, p.x, p.y, g.de * 0.9, col(C_NEUTRON, a), 52.0)
                else
                    dot("fp" .. i .. "h", p.x, p.y, g.nucR * 2.0, col(C_PROTON, 0.30 * a), 51.0)
                    dot("fp" .. i, p.x, p.y, g.nucR, col(C_PROTON, a), 52.0)
                    local le = data.get(p.z)
                    if le then label("fpl" .. i, p.x, p.y - g.nucR * 1.7, g.unit * 0.14, g.unit * 0.04,
                        le.sym, col({ 1, 1, 1, 1 }, a), 1.8, 53.0) end
                end
            end
        end
    end

    -- live identity + isotope, as a header under the board
    local el = element()
    if el then
        local unstable = instability() > 0
        local sym_c = is_neutral() and col(C_LOCK, math.min(1.0, 0.9 * bright)) or { 0.86, 0.92, 1.0, 0.9 }
        label("ident_sym", g.cx, g.iy, g.unit * 0.4, g.unit * 0.10, el.sym, sym_c, 4.0, 41.0)
        local iso_c = unstable and col(C_UNSTABLE, pulse_a("iso", 6.0, 0.7, 1.0)) or C_DIMTEXT
        label("ident_iso", g.cx, g.iy + g.unit * 0.085, g.unit * 0.6, g.unit * 0.045,
            iso_name() .. (unstable and "   unstable" or ""), iso_c, 2.0, 41.0)
        label("ident_sub", g.cx, g.iy + g.unit * 0.125, g.unit * 0.6, g.unit * 0.038,
            string.format("%dp %dn / %de", M.atom.protons, M.atom.neutrons, electrons()), C_DIMTEXT, 1.5, 41.0)
        if M.view == "cloud" then
            local cfg = data.config(electrons())
            local val = cfg[#cfg]
            if val then
                local m = -val.l + ((val.e - 1) % (2 * val.l + 1))
                label("ident_orb", g.cx, g.iy + g.unit * 0.170, g.unit * 0.6, g.unit * 0.05,
                    string.format("outer  %d%s  (%d, %d, %d)", val.n, data.L_CHAR[val.l], val.n, val.l, m),
                    col(C_ELEC, 0.92), 1.7, 41.0)
            end
        elseif M.view == "shells" then
            local occ, nmax = n_shell_occ(electrons())
            local parts = {}
            for i = 1, nmax do parts[i] = tostring(occ[i] or 0) end
            label("ident_orb", g.cx, g.iy + g.unit * 0.170, g.unit * 0.6, g.unit * 0.05,
                "shells  " .. table.concat(parts, " . "), col(C_ELEC, 0.92), 1.7, 41.0)
        end
    end

    end -- end single-atom vs molecule branch

    -- "stabilize-the-decay": under the decay clock, name the stakes and the save move.
    -- Drop the hinted particle before the tick to QUENCH it; or let it decay (also valid).
    if M.decay and not M.card then
        -- period-7 atoms are huge: clamp so the 3-line block never spills into the strip
        local py = math.min(g.cy + g.rmax + g.unit * 0.04, g.msY - g.unit * 0.155)
        label("decay_hdr", g.cx, py, g.unit * 0.6, g.unit * 0.05, "UNSTABLE  -  DECAYING",
            col(C_UNSTABLE, pulse_a("decay", 7.0, 0.55, 1.0)), 2.2, 43.0)
        local hint = (stabilizes("n") and "MERGE +1 neutron to stabilize")
            or (stabilizes("p") and "MERGE +1 proton to stabilize")
            or "no stable route - let it decay"
        label("decay_hint", g.cx, py + g.unit * 0.052, g.unit * 0.75, g.unit * 0.04, hint,
            { 0.92, 0.86, 0.72, 0.92 }, 1.6, 43.0)
        if M.decay.hl then
            label("decay_hl", g.cx, py + g.unit * 0.092, g.unit * 0.6, g.unit * 0.036,
                "real half-life  " .. M.decay.hl, C_DIMTEXT, 1.4, 43.0)
        end
    end

    -- coalesce reagent: when a reaction is available (a molecule target whose core you've
    -- built), a reagent rests beside the atom. It only reacts once the required catalyst +
    -- condition chips are on; until then it's dim and shows what it needs.
    local rx = reaction_kind()
    local bdrag = M.fly and M.fly.src == "bond_src"
    if rx and not M.card and not M.fusing and not M.fission and (not M.fly or bdrag) then
        local met = reqs_met(rx)
        local bx, by = g.cx + g.unit * 0.40, g.cy
        local pc = CPK[rx.partner] or C_NEUTRON
        if not bdrag then
            local pulse = 1.0 + 0.10 * math.sin(M.clock * 3.0)
            ring("bond_ring", bx, by, g.td * 0.60 * (met and pulse or 1.0), col(pc, met and 0.5 or 0.18), 39.0)
            dot("bond_glow", bx, by, g.de * 2.4, col(pc, 0.18), 39.5)
            label("bond_lbl", bx, by + g.td * 0.62, g.unit * 0.6, g.unit * 0.036,
                rx.eq or data.molecules[rx.product].sym, -- the real balanced equation
                col(pc, met and 0.95 or 0.5), 1.5, 40.0)
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
        for _, s in ipairs(M._bench or {}) do
            if not reqs_met(s) then for _, k in ipairs(reqs_of(s)) do need[k] = true end end
        end
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
                fill = fill, border = border, text_color = tc,
                no_input = not M.discovered[z] }) -- discovered cells are hoverable for a tooltip
        end
    end

    -- hover a discovered element on the board -> tooltip (name, symbol, atomic number, lore).
    local hz, hmx, hmy
    for z in pairs(M.discovered) do
        local st = runtime_ui.get_state(SCREEN, "pt" .. z)
        if st and st.hovered then hz, hmx, hmy = z, st.mouse_x, st.mouse_y; break end
    end
    if hz then draw_element_tip(hz, hmx or g.cx, hmy or g.cy) end

    -- hover a condition chip -> what it does + when to use it.
    for _, c in ipairs(CATALYSTS) do
        local st = runtime_ui.get_state(SCREEN, "cat_" .. c)
        if st and st.hovered then draw_chip_tip(c, st.mouse_x or g.cx, st.mouse_y or g.cy); break end
    end

    -- THE BENCH (bottom-left): species reactions runnable from the shelf right now. The
    -- balanced eq is the recipe; the shelf counts are consumed on click.
    M._bench = bench_offers()
    do
        local nb = math.min(3, #M._bench)
        local bw, bh = g.unit * 0.36, g.unit * 0.042
        for i = 1, nb do
            local s = M._bench[i]
            local met = reqs_met(s)
            local by0 = g.msY - g.unit * 0.012 - (nb - i + 1) * (bh + g.unit * 0.008)
            quad("bench" .. i, { x = g.unit * 0.015, y = by0, width = bw, height = bh, z = 46.0,
                style = "button", font_scale = 1.3,
                title = "REACT:  " .. s.eq .. (met and "" or ("    needs " .. table.concat(reqs_of(s), "+"))),
                fill = met and { 0.10, 0.16, 0.11, 0.95 } or { 0.10, 0.12, 0.16, 0.9 },
                border = met and col(C_LOCK, 0.9) or col(C_UNSTABLE, 0.7),
                accent = col(C_LOCK, 0.8),
                text_color = met and { 0.92, 0.96, 0.90, 1.0 } or { 0.75, 0.78, 0.85, 0.9 } })
        end
    end

    -- molecule discovered-strip (bottom, two rows): every species fills in as you make it;
    -- shelf counts show as xN. Dirty-skip like the board: re-submit on signature change only.
    do
        local msum, mdisc = 0, 0
        for _, v in pairs(M.shelf) do msum = msum + v end
        for _ in pairs(M.mol_disc) do mdisc = mdisc + 1 end
        local mtkey = (M.target and M.target.kind == "mol") and M.target.key or "-"
        local mskey = string.format("%d|%d|%s|%.1f", msum, mdisc, mtkey, g.msCell)
        for i = 1, g.msN do M._live["ms" .. i] = true end
        if mskey ~= M._mskey then
            M._mskey = mskey
            for i, key in ipairs(data.mol_list) do
                local r0 = math.floor((i - 1) / g.msCols)
                local c0 = (i - 1) % g.msCols
                local x = g.msX + c0 * g.msCell
                local y = g.msY + r0 * (g.msH + g.unit * 0.004)
                local disc = M.mol_disc[key]
                local cnt = M.shelf[key] or 0
                local fill, border, tc
                if M.target and M.target.kind == "mol" and M.target.key == key then
                    fill = { 0.24, 0.18, 0.05, 0.95 }; border = col(C_LOCK, 0.95); tc = { 1.0, 0.90, 0.60, 1.0 }
                elseif disc then
                    fill = { 0.10, 0.13, 0.19, 0.92 }; border = { 0.40, 0.45, 0.55, 0.6 }; tc = { 0.94, 0.88, 0.72, 1.0 }
                else
                    fill = { 0.05, 0.06, 0.09, 0.5 }; border = { 0.20, 0.24, 0.30, 0.4 }; tc = { 0.42, 0.46, 0.54, 0.7 }
                end
                quad("ms" .. i, { x = x + g.msCell * 0.04, y = y, width = g.msCell * 0.92, height = g.msH,
                    z = 44.0, style = "text", body = key .. (cnt > 0 and (" x" .. cnt) or ""),
                    align_h = "center", align_v = "middle",
                    font_scale = math.max(0.65, math.min(1.15, g.msCell * 0.016)),
                    fill = fill, border = border, text_color = tc,
                    no_input = not disc }) -- discovered cells are hoverable for a tooltip
            end
        end
        -- hover a discovered molecule -> its name + lore
        for i, key in ipairs(data.mol_list) do
            if M.mol_disc[key] then
                local st = runtime_ui.get_state(SCREEN, "ms" .. i)
                if st and st.hovered then
                    local mm = data.molecules[key]
                    local tw, th = g.unit * 0.42, g.unit * 0.16
                    local tx = math.max(g.unit * 0.01, math.min((st.mouse_x or g.cx) - tw * 0.5, g.w - tw - g.unit * 0.01))
                    quad("mstip", {
                        x = tx, y = g.msY - th - g.unit * 0.012, width = tw, height = th, z = 63.0,
                        style = "panel", font_scale = 1.7, bring_to_front = true, no_input = true,
                        label = "on shelf: " .. (M.shelf[key] or 0), title = mm.name .. "   (" .. mm.sym .. ")",
                        body = mm.lore,
                        fill = { 0.05, 0.06, 0.10, 0.98 }, border = C_LOCK,
                        accent = { 1.00, 0.82, 0.34, 1.0 }, text_color = { 0.92, 0.94, 0.98, 1.0 },
                    })
                    break
                end
            end
        end
    end

    -- decay-chain breadcrumb (bottom-centre): the spontaneous chain walked so far —
    -- U-238 > Th-234 > Pa-234 > ... Truncates to the last 8 hops; count keeps the total.
    if M.chain and #M.chain > 1 then
        local MAXSHOW = 8
        local first = math.max(1, #M.chain - MAXSHOW + 1)
        local parts = {}
        if first > 1 then parts[1] = "..." end
        for i = first, #M.chain do parts[#parts + 1] = M.chain[i] end
        label("chain", g.cx, g.msY - g.unit * 0.040, g.w * 0.9, g.unit * 0.03,
            string.format("DECAY CHAIN  (%d steps):   %s", #M.chain - 1, table.concat(parts, "  >  ")),
            { 0.92, 0.82, 0.56, 0.92 }, 1.5, 43.0)
    end

    -- last radiation fired (bottom-right): persists until the next event; hover = legend.
    if M.lastrad and RAD_INFO[M.lastrad.key] then
        local ri = RAD_INFO[M.lastrad.key]
        local rw, rh = g.unit * 0.24, g.unit * 0.048
        local rxx = g.w - rw - g.unit * 0.02
        local ryy = g.msY - g.unit * 0.012 - rh
        quad("radout", { x = rxx, y = ryy, width = rw, height = rh, z = 46.0, style = "button",
            title = "radiation:  " .. ri.name, font_scale = 1.4,
            fill = { 0.07, 0.08, 0.12, 0.92 }, border = col(ri.c, 0.8), accent = col(ri.c, 0.9),
            text_color = { 0.88, 0.90, 0.95, 1.0 } })
        dot("radoutdot", rxx - g.unit * 0.018, ryy + rh * 0.5, g.de, ri.c, 47.0)
        local st = runtime_ui.get_state(SCREEN, "radout")
        if st and st.hovered then
            quad("radtip", { x = rxx + rw - g.unit * 0.44, y = ryy - g.unit * 0.172,
                width = g.unit * 0.44, height = g.unit * 0.16, z = 63.0,
                style = "panel", font_scale = 1.7, bring_to_front = true, no_input = true,
                label = M.lastrad.note or "", title = ri.name, body = ri.desc,
                fill = { 0.05, 0.06, 0.10, 0.98 }, border = col(ri.c, 0.9), accent = col(ri.c, 0.9),
                text_color = { 0.92, 0.94, 0.98, 1.0 } })
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
            body = M.won and "click for a new target"
                or (M.target and M.target.kind == "mol" and not data.reactions[M.target.key])
                and "made on the BENCH  -  react shelf molecules (bottom-left)"
                or "synthesize this  -  assemble on the left, then MERGE",
            align_h = "left", align_v = "middle", font_scale = 1.2,
            fill = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, text_color = C_DIMTEXT, no_input = true })
    end

    -- QUESTS: pick any element or molecule as the next target; the TARGET button above
    -- stays the random roll. A modal catalog — input is swallowed while it is open.
    do
        local qx, qy = g.unit * 0.02, g.unit * 0.105
        local qw, qh = g.unit * 0.32, g.unit * 0.036
        quad("questbtn", { x = qx, y = qy, width = qw, height = qh, z = 47.0, style = "button",
            title = "QUESTS  " .. (M.questOpen and "^" or "v"), font_scale = 1.4,
            fill = { 0.09, 0.11, 0.17, 0.94 }, border = col(C_LOCK, 0.55),
            accent = col(C_LOCK, 0.7), text_color = { 0.92, 0.90, 0.80, 0.96 } })
        if M.questOpen then
            local ec, mcw, mch = g.unit * 0.036, g.unit * 0.068, g.unit * 0.030
            local ecols, mcols = 15, 8
            local erows = math.ceil(data.MAX_Z / ecols)
            local mrows = math.ceil(#data.mol_list / mcols)
            local px, py2 = qx, qy + qh + g.unit * 0.008
            local pw = math.max(ecols * ec, mcols * mcw) + g.unit * 0.024
            local ph = erows * ec + mrows * mch + g.unit * 0.096
            quad("questpanel", { x = px, y = py2, width = pw, height = ph, z = 61.0,
                style = "panel", bring_to_front = true, no_input = true,
                fill = { 0.04, 0.05, 0.09, 0.98 }, border = col(C_LOCK, 0.6),
                accent = col(C_LOCK, 0.7), text_color = { 0.9, 0.9, 0.9, 1.0 } })
            label("quest_he", px + pw * 0.5, py2 + g.unit * 0.006, pw, g.unit * 0.024, "ELEMENTS", C_HINT, 1.2, 62.0)
            local gx0, gy0 = px + g.unit * 0.012, py2 + g.unit * 0.034
            for z = 1, data.MAX_Z do
                local r0 = math.floor((z - 1) / ecols)
                local c0 = (z - 1) % ecols
                local e = data.get(z)
                local hit = M.target and M.target.kind == "el" and M.target.z == z
                quad("q_el" .. z, { x = gx0 + c0 * ec, y = gy0 + r0 * ec,
                    width = ec * 0.92, height = ec * 0.92, z = 62.0, style = "text",
                    body = e.sym, align_h = "center", align_v = "middle", font_scale = 0.9,
                    bring_to_front = true,
                    fill = hit and { 0.24, 0.18, 0.05, 0.95 }
                        or (M.discovered[z] and { 0.10, 0.13, 0.19, 0.92 } or { 0.06, 0.07, 0.11, 0.9 }),
                    border = hit and col(C_LOCK, 0.95) or { 0.30, 0.34, 0.44, 0.5 },
                    text_color = M.discovered[z] and { 0.94, 0.88, 0.72, 1.0 } or { 0.55, 0.60, 0.70, 0.9 } })
            end
            local my0 = gy0 + erows * ec + g.unit * 0.004
            label("quest_hm", px + pw * 0.5, my0, pw, g.unit * 0.024, "MOLECULES", C_HINT, 1.2, 62.0)
            local mgy0 = my0 + g.unit * 0.028
            for i, key in ipairs(data.mol_list) do
                local r0 = math.floor((i - 1) / mcols)
                local c0 = (i - 1) % mcols
                local hit = M.target and M.target.kind == "mol" and M.target.key == key
                quad("q_mol" .. i, { x = gx0 + c0 * mcw, y = mgy0 + r0 * mch,
                    width = mcw * 0.94, height = mch * 0.9, z = 62.0, style = "text",
                    body = key, align_h = "center", align_v = "middle", font_scale = 0.85,
                    bring_to_front = true,
                    fill = hit and { 0.24, 0.18, 0.05, 0.95 }
                        or (M.mol_disc[key] and { 0.10, 0.13, 0.19, 0.92 } or { 0.06, 0.07, 0.11, 0.9 }),
                    border = hit and col(C_LOCK, 0.95) or { 0.30, 0.34, 0.44, 0.5 },
                    text_color = M.mol_disc[key] and { 0.94, 0.88, 0.72, 1.0 } or { 0.55, 0.60, 0.70, 0.9 } })
            end
        end
    end

    -- assembly atom + steppers + MERGE (hidden while a card is up or bonded). Build the
    -- chunk on the left by hand, HOLD +/- to pour fast, then MERGE it into the atom.
    if not M.card and not M.molecule and not M.bonding and not M.fusing and not M.fission then
        draw_stage()
        if not M.acted and #(M.chain or {}) <= 1 then -- the chain breadcrumb owns this line
            label("hint", g.cx, g.msY - g.unit * 0.052, g.unit * 0.8, g.unit * 0.045,
                "assemble an atom on the left  -  HOLD + to pour  -  then MERGE it in", C_HINT, 2.0, 42.0)
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
                label = e.eq or (e.sym .. (e.z and ("  -  Z " .. e.z) or "")), title = string.upper(e.name), body = e.lore,
                footer = "click to continue",
                fill = { 0.05, 0.06, 0.10, 0.97 }, border = C_LOCK,
                accent = { 1.00, 0.82, 0.34, 1.0 }, text_color = { 0.92, 0.94, 0.98, 1.0 },
            })
        end
    end

    -- FISSION: heavy nuclei (actinides) can be split by firing a neutron in — the down-the-
    -- table counterpart to fusion. Only offered when the atom is heavy enough.
    if can_fission() and not M.card and not M.molecule and not M.bonding and not M.fusing and not M.fission then
        local pulse = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(M.clock * 3.0))
        quad("fission", { x = g.cx - g.unit * 0.15, y = g.h * 0.78, width = g.unit * 0.30, height = g.unit * 0.06, z = 46.0,
            style = "button", title = "FISSION  -  fire neutron", font_scale = 1.6,
            fill = { 0.20, 0.10, 0.10, 0.95 }, border = col(C_UNSTABLE, pulse), accent = col(C_NEUTRON, 0.9),
            text_color = { 1.0, 0.86, 0.80, 1.0 } })
    end

    -- atom view dropdown (top-left, under the target): Bohr / config / shell occupancy / cloud.
    do
        local vx, vy = g.unit * 0.02, g.unit * 0.145
        local vw, vh = g.unit * 0.24, g.unit * 0.05
        quad("viewbtn", { x = vx, y = vy, width = vw, height = vh, z = 47.0, style = "button",
            title = "View:  " .. view_name(M.view) .. (M.viewOpen and "  ^" or "  v"), font_scale = 1.4,
            fill = { 0.09, 0.11, 0.17, 0.94 }, border = col(C_ELEC, 0.6),
            accent = col(C_ELEC, 0.7), text_color = { 0.86, 0.92, 1.0, 0.96 } })
        if M.viewOpen then
            for i, v in ipairs(VIEWS) do
                local sel = M.view == v.key
                quad("view_" .. v.key, { x = vx, y = vy + vh + (i - 1) * (vh * 0.92), width = vw, height = vh * 0.86,
                    z = 47.0, style = "button", title = v.name, font_scale = 1.3, bring_to_front = true,
                    fill = sel and { 0.16, 0.20, 0.10, 0.97 } or { 0.07, 0.09, 0.13, 0.97 },
                    border = sel and C_LOCK or { 0.4, 0.45, 0.55, 0.6 },
                    accent = col(C_ELEC, 0.6), text_color = { 0.86, 0.9, 0.96, 1.0 } })
            end
        end
    end

    quad("reset", { x = g.w - 150.0, y = 26.0, width = 122.0, height = 44.0, z = 45.0,
        style = "button", title = "Restart", font_scale = 1.7,
        fill = { 0.10, 0.12, 0.16, 0.9 }, border = { 0.4, 0.5, 0.62, 0.7 },
        accent = { 0.34, 0.55, 0.92, 0.8 }, text_color = { 0.86, 0.9, 0.96, 1.0 } })
end

local function reconcile()
    for id in pairs(M._prev) do
        if not M._live[id] then runtime_ui.remove(SCREEN, id); M._opt[id] = nil; M._eang[id] = nil end
    end
    if not M.decay then M._drfq = nil end
    if instability() == 0 and M.flash <= 0 then M._nqx, M._nqy, M._nfq = nil, nil, nil end
    M._prev = M._live
    M._live = {}
end

function M.update(dt)
    if not layout() then return end
    advance(dt)
    if not M.held_id then check_target() end -- don't surface the win toast mid-hold; fires on release
    handle_input()
    -- hold-to-stream: after a short press on a stepper, pour that particle into the
    -- staging chunk at an accelerating rate (so heavy chunks aren't a click-fest).
    if M.held_id then
        M.hold_t = (M.hold_t or 0.0) + dt
        if M.hold_t > 0.2 then
            M.stream_acc = (M.stream_acc or 0.0) + dt
            local interval = math.max(0.02, 0.09 - (M.hold_t - 0.2) * 0.02)
            while M.stream_acc >= interval do
                M.stream_acc = M.stream_acc - interval
                stage_add(M.held_kind, M.held_dir or 1)
            end
        end
    else
        M.hold_t, M.stream_acc = 0.0, 0.0
    end
    -- settle: land on a new, complete, stable element and its birth card slides up (once)
    if not M.held_id and not M.molecule and not M.bonding and not M.card and not M.fusing and not M.fission and is_neutral() then
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
    -- autosave: cheap progress signature every ~2s, write only when it actually changed
    M._st = (M._st or 0) + 1
    if M._st >= 150 then
        M._st = 0
        local dn, md, sh = 0, 0, 0
        for _ in pairs(M.discovered) do dn = dn + 1 end
        for _ in pairs(M.mol_disc) do md = md + 1 end
        for _, v in pairs(M.shelf) do sh = sh + v end
        local sig = string.format("%d|%d|%d|%d|%d|%d|%s", dn, md, sh,
            M.stats.decays or 0, M.stats.quenched or 0, M.tcount or 0, M.view)
        if sig ~= M._sig then M._sig = sig; save_progress() end
    end
end

return M
