-- data.lua — Ylem element table, the full periodic table (Z 1..118). Pure data +
-- small query helpers; lab.lua reads it.
--
-- THE MODEL: the atom's rings are PERIODS (table rows), not textbook electron shells.
-- Ring capacities {2,8,8,18,18,32,32} are the period lengths, so a filled ring closes
-- at cumulative 2,10,18,36,54,86,118 — exactly the noble gases (He/Ne/Ar/Kr/Xe/Rn/Og).
-- So "fill a ring -> lock gold -> noble gas" stays correct across all 118 elements with
-- no subshell/Aufbau bookkeeping. (True n-shells are 2,8,18,32; periods are the rows a
-- periodic table actually shows, which is the intuition the board leans on.)
--
-- ISOTOPES (ponytail): a principal-mass table gives the common/most-stable isotope; a
-- stability BAND around it stands in for real stable-N sets (exact sets for 118 elements
-- aren't worth hand-coding). Everything past Bismuth (Z>83) has no stable isotope, so it
-- is always radioactive and decays — which is real, and is the endgame tension.

local D = {}

D.MAX_Z = 118
D.SHELLS = { 2, 8, 8, 18, 18, 32, 32 } -- period (ring) capacities; cumulative = the noble gases

-- z, symbol, name, category. Categories drive the fallback lore + board tint.
D.elements = {
    { 1, "H", "Hydrogen", "nonmetal" }, { 2, "He", "Helium", "noble" },
    { 3, "Li", "Lithium", "alkali" }, { 4, "Be", "Beryllium", "alkaline" },
    { 5, "B", "Boron", "metalloid" }, { 6, "C", "Carbon", "nonmetal" },
    { 7, "N", "Nitrogen", "nonmetal" }, { 8, "O", "Oxygen", "nonmetal" },
    { 9, "F", "Fluorine", "halogen" }, { 10, "Ne", "Neon", "noble" },
    { 11, "Na", "Sodium", "alkali" }, { 12, "Mg", "Magnesium", "alkaline" },
    { 13, "Al", "Aluminium", "posttransition" }, { 14, "Si", "Silicon", "metalloid" },
    { 15, "P", "Phosphorus", "nonmetal" }, { 16, "S", "Sulfur", "nonmetal" },
    { 17, "Cl", "Chlorine", "halogen" }, { 18, "Ar", "Argon", "noble" },
    { 19, "K", "Potassium", "alkali" }, { 20, "Ca", "Calcium", "alkaline" },
    { 21, "Sc", "Scandium", "transition" }, { 22, "Ti", "Titanium", "transition" },
    { 23, "V", "Vanadium", "transition" }, { 24, "Cr", "Chromium", "transition" },
    { 25, "Mn", "Manganese", "transition" }, { 26, "Fe", "Iron", "transition" },
    { 27, "Co", "Cobalt", "transition" }, { 28, "Ni", "Nickel", "transition" },
    { 29, "Cu", "Copper", "transition" }, { 30, "Zn", "Zinc", "transition" },
    { 31, "Ga", "Gallium", "posttransition" }, { 32, "Ge", "Germanium", "metalloid" },
    { 33, "As", "Arsenic", "metalloid" }, { 34, "Se", "Selenium", "nonmetal" },
    { 35, "Br", "Bromine", "halogen" }, { 36, "Kr", "Krypton", "noble" },
    { 37, "Rb", "Rubidium", "alkali" }, { 38, "Sr", "Strontium", "alkaline" },
    { 39, "Y", "Yttrium", "transition" }, { 40, "Zr", "Zirconium", "transition" },
    { 41, "Nb", "Niobium", "transition" }, { 42, "Mo", "Molybdenum", "transition" },
    { 43, "Tc", "Technetium", "transition" }, { 44, "Ru", "Ruthenium", "transition" },
    { 45, "Rh", "Rhodium", "transition" }, { 46, "Pd", "Palladium", "transition" },
    { 47, "Ag", "Silver", "transition" }, { 48, "Cd", "Cadmium", "transition" },
    { 49, "In", "Indium", "posttransition" }, { 50, "Sn", "Tin", "posttransition" },
    { 51, "Sb", "Antimony", "metalloid" }, { 52, "Te", "Tellurium", "metalloid" },
    { 53, "I", "Iodine", "halogen" }, { 54, "Xe", "Xenon", "noble" },
    { 55, "Cs", "Caesium", "alkali" }, { 56, "Ba", "Barium", "alkaline" },
    { 57, "La", "Lanthanum", "lanthanide" }, { 58, "Ce", "Cerium", "lanthanide" },
    { 59, "Pr", "Praseodymium", "lanthanide" }, { 60, "Nd", "Neodymium", "lanthanide" },
    { 61, "Pm", "Promethium", "lanthanide" }, { 62, "Sm", "Samarium", "lanthanide" },
    { 63, "Eu", "Europium", "lanthanide" }, { 64, "Gd", "Gadolinium", "lanthanide" },
    { 65, "Tb", "Terbium", "lanthanide" }, { 66, "Dy", "Dysprosium", "lanthanide" },
    { 67, "Ho", "Holmium", "lanthanide" }, { 68, "Er", "Erbium", "lanthanide" },
    { 69, "Tm", "Thulium", "lanthanide" }, { 70, "Yb", "Ytterbium", "lanthanide" },
    { 71, "Lu", "Lutetium", "lanthanide" }, { 72, "Hf", "Hafnium", "transition" },
    { 73, "Ta", "Tantalum", "transition" }, { 74, "W", "Tungsten", "transition" },
    { 75, "Re", "Rhenium", "transition" }, { 76, "Os", "Osmium", "transition" },
    { 77, "Ir", "Iridium", "transition" }, { 78, "Pt", "Platinum", "transition" },
    { 79, "Au", "Gold", "transition" }, { 80, "Hg", "Mercury", "transition" },
    { 81, "Tl", "Thallium", "posttransition" }, { 82, "Pb", "Lead", "posttransition" },
    { 83, "Bi", "Bismuth", "posttransition" }, { 84, "Po", "Polonium", "posttransition" },
    { 85, "At", "Astatine", "halogen" }, { 86, "Rn", "Radon", "noble" },
    { 87, "Fr", "Francium", "alkali" }, { 88, "Ra", "Radium", "alkaline" },
    { 89, "Ac", "Actinium", "actinide" }, { 90, "Th", "Thorium", "actinide" },
    { 91, "Pa", "Protactinium", "actinide" }, { 92, "U", "Uranium", "actinide" },
    { 93, "Np", "Neptunium", "actinide" }, { 94, "Pu", "Plutonium", "actinide" },
    { 95, "Am", "Americium", "actinide" }, { 96, "Cm", "Curium", "actinide" },
    { 97, "Bk", "Berkelium", "actinide" }, { 98, "Cf", "Californium", "actinide" },
    { 99, "Es", "Einsteinium", "actinide" }, { 100, "Fm", "Fermium", "actinide" },
    { 101, "Md", "Mendelevium", "actinide" }, { 102, "No", "Nobelium", "actinide" },
    { 103, "Lr", "Lawrencium", "actinide" }, { 104, "Rf", "Rutherfordium", "transition" },
    { 105, "Db", "Dubnium", "transition" }, { 106, "Sg", "Seaborgium", "transition" },
    { 107, "Bh", "Bohrium", "transition" }, { 108, "Hs", "Hassium", "transition" },
    { 109, "Mt", "Meitnerium", "transition" }, { 110, "Ds", "Darmstadtium", "transition" },
    { 111, "Rg", "Roentgenium", "transition" }, { 112, "Cn", "Copernicium", "transition" },
    { 113, "Nh", "Nihonium", "posttransition" }, { 114, "Fl", "Flerovium", "posttransition" },
    { 115, "Mc", "Moscovium", "posttransition" }, { 116, "Lv", "Livermorium", "posttransition" },
    { 117, "Ts", "Tennessine", "halogen" }, { 118, "Og", "Oganesson", "noble" },
}

-- Principal isotope mass number A per Z: the MOST ABUNDANT stable isotope (longest-lived
-- known for radioactive elements). principal-N = A - Z. NOT rounded atomic weights — those
-- land on radioisotopes for half the table (Cu-64, Zn-65, Br-80, Ag-108, Ir-192, Tl-204...).
-- Geologically-quasi-stable 2vbb/soft-beta nuclides (Te-130, Re-187, In-115, Bi-209) count
-- as stable, as convention lists them.
D.mass = {
    1, 4, 7, 9, 11, 12, 14, 16, 19, 20,
    23, 24, 27, 28, 31, 32, 35, 40, 39, 40,
    45, 48, 51, 52, 55, 56, 59, 58, 63, 64,
    69, 74, 75, 80, 79, 84, 85, 88, 89, 90,
    93, 98, 98, 102, 103, 106, 107, 114, 115, 120,
    121, 130, 127, 132, 133, 138, 139, 140, 141, 142,
    145, 152, 153, 158, 159, 164, 165, 166, 169, 174,
    175, 180, 181, 184, 187, 192, 193, 195, 197, 202,
    205, 208, 209, 209, 210, 222, 223, 226, 227, 232,
    231, 238, 237, 244, 243, 247, 247, 251, 252, 257,
    258, 259, 266, 267, 268, 269, 270, 269, 278, 281,
    282, 285, 286, 289, 290, 293, 294, 294,
}

-- Curated lore for the famous elements; everything else gets a category line. Lore is
-- ASCII (the UI font has no em-dash/curly-quote) and arrives as reward on the birth card.
D.lore_override = {
    [1] = "Fuels the stars; the first atom after the Big Bang.",
    [2] = "Floats balloons; 2nd most abundant thing in existence - perfectly content.",
    [3] = "The spark in your phone battery; lightest metal, soft enough to cut.",
    [4] = "Stiffens spacecraft and X-ray windows; light, rare, toxic.",
    [5] = "Borax and heatproof glass; strengthens rocket parts.",
    [6] = "The backbone of all life; diamond, graphite, and you.",
    [7] = "78% of the air you breathe; locked so tight it starves fire.",
    [8] = "The other 21% of air; pair me with two hydrogens and you're 60% of a human.",
    [9] = "In your toothpaste and non-stick pans; the most reactive element there is.",
    [10] = "The glow in every bar sign; a full shell - wants nothing, reacts with nothing.",
    [11] = "Explodes in water, yet half of table salt; the yellow of sodium street lamps.",
    [13] = "The metal of foil, cans, and airplanes; once more precious than gold.",
    [14] = "Sand, glass, and every computer chip; the bedrock of the digital age.",
    [16] = "Brimstone - the yellow of volcanoes and the smell of a struck match.",
    [17] = "Bleach and pool water; a green war gas tamed into a disinfectant.",
    [18] = "Nearly 1% of every breath; the lazy gas sealed inside lightbulbs and welding.",
    [19] = "Fires every heartbeat and nerve; bananas are faintly radioactive because of it.",
    [20] = "Your bones and teeth, chalk and seashells; the scaffold of bodies.",
    [26] = "The heart of steel and your blood; where a dying star's fusion finally stops.",
    [29] = "The first metal we mastered; wiring, pipes, and the Statue of Liberty's green skin.",
    [36] = "A whisper in the atmosphere; its orange-red glow once defined the metre.",
    [47] = "The best conductor there is; mirrors, coins, and old photographs.",
    [50] = "Bronze-age tin; the faint cry of a bent bar and the coat on a soup can.",
    [53] = "Paints wounds brown and keeps your thyroid running; violet vapor when it sublimes.",
    [54] = "A noble gas that still forms rare compounds; ion engines and blinding lamps.",
    [74] = "The glow of old lightbulb filaments; the highest melting point of any metal.",
    [78] = "Catalytic converters and lab crucibles; rarer and denser than gold.",
    [79] = "Never tarnishes, forged only in colliding stars; the metal that built empires.",
    [80] = "The only liquid metal; quicksilver of old thermometers, beautiful and poisonous.",
    [82] = "Dense, soft, and toxic; where every heavy decay chain finally comes to rest.",
    [86] = "A radioactive gas seeping from rocks into basements; heavy and unseen.",
    [92] = "The fuel of reactors and bombs; splits in two and unleashes the atom's fury.",
    [94] = "Made in reactors; powers spacecraft all the way to the edge of the solar system.",
    [118] = "The heaviest element ever made - a few atoms, alive for less than a blink.",
}

D.cat_lore = {
    alkali         = "A soft, hungry metal that flares on water; one lone outer electron it can't wait to give away.",
    alkaline       = "A reactive light metal of bones, fireworks, and coloured flame; two electrons to spare.",
    transition     = "A hard, lustrous metal of tools, wires, and machines; the workhorse middle of the table.",
    posttransition = "A soft, workable metal that shapes easily into the everyday.",
    metalloid      = "Neither quite metal nor nonmetal; the in-between that makes semiconductors possible.",
    nonmetal       = "A building block of life and air; it shares electrons rather than giving them up.",
    halogen        = "Fiercely reactive; one electron short of full, it snatches from anything nearby.",
    noble          = "A full shell - serene and aloof, it reacts with almost nothing.",
    lanthanide     = "A rare-earth metal hidden in magnets, lasers, and screens; the table's secret spice.",
    actinide       = "A dense, radioactive metal of reactors and glowing dials; heavy and restless.",
}

function D.lore(z)
    if D.lore_override[z] then return D.lore_override[z] end
    if z >= 104 then return "A synthetic superheavy, forged atom-by-atom in a collider and gone in a heartbeat." end
    local e = D.elements[z]
    return (e and D.cat_lore[e[4]]) or "One of the building blocks of the universe."
end

-- Cached: lab calls this from draw (identity, board, quests). Lore is static.
D._get = {}
function D.get(z)
    local c = D._get[z]
    if c then return c end
    local e = D.elements[z]
    if not e then return nil end
    c = { z = e[1], sym = e[2], name = e[3], cat = e[4], lore = D.lore(z) }
    D._get[z] = c
    return c
end

-- Electron configuration (Madelung / Aufbau fill order) — the foundation for the orbital
-- cloud view. FILL_ORDER lists subshells (n, l) in fill order up to 7p (covers Z 1..118);
-- l = 0/1/2/3 = s/p/d/f, subshell capacity 2(2l+1).
D.L_CHAR = { [0] = "s", [1] = "p", [2] = "d", [3] = "f" }
D.FILL_ORDER = {
    { 1, 0 }, { 2, 0 }, { 2, 1 }, { 3, 0 }, { 3, 1 }, { 4, 0 }, { 3, 2 }, { 4, 1 }, { 5, 0 }, { 4, 2 },
    { 5, 1 }, { 6, 0 }, { 4, 3 }, { 5, 2 }, { 6, 1 }, { 7, 0 }, { 5, 3 }, { 6, 2 }, { 7, 1 },
}

-- Real ground states deviate from Madelung for ~20 elements (Cr 3d5 4s1, Cu 3d10 4s1,
-- Pd 4d10 with NO 5s, La/Ce/Gd 5d1, Th 6d2 with NO 5f, Lr 7p1...). Encoded as one electron
-- MOVE {fromN, fromL, toN, toL, count} applied on top of the Madelung fill when the
-- electron count matches that neutral atom.
local CONFIG_FIX = {
    [24] = { 4, 0, 3, 2, 1 }, [29] = { 4, 0, 3, 2, 1 },
    [41] = { 5, 0, 4, 2, 1 }, [42] = { 5, 0, 4, 2, 1 }, [44] = { 5, 0, 4, 2, 1 },
    [45] = { 5, 0, 4, 2, 1 }, [46] = { 5, 0, 4, 2, 2 }, [47] = { 5, 0, 4, 2, 1 },
    [57] = { 4, 3, 5, 2, 1 }, [58] = { 4, 3, 5, 2, 1 }, [64] = { 4, 3, 5, 2, 1 },
    [78] = { 6, 0, 5, 2, 1 }, [79] = { 6, 0, 5, 2, 1 },
    [89] = { 5, 3, 6, 2, 1 }, [90] = { 5, 3, 6, 2, 2 }, [91] = { 5, 3, 6, 2, 1 },
    [92] = { 5, 3, 6, 2, 1 }, [93] = { 5, 3, 6, 2, 1 }, [96] = { 5, 3, 6, 2, 1 },
    [103] = { 6, 2, 7, 1, 1 },
}

-- subshells filling `nelec` electrons in Madelung order + the real-ground-state fix:
-- { {n=,l=,e=}, ... }. Cached: cloud/shells views call this every frame.
D._cfg = {}
function D.config(nelec)
    local hit = D._cfg[nelec]
    if hit then return hit end
    local out = {}
    local left = nelec
    for _, s in ipairs(D.FILL_ORDER) do
        if left <= 0 then break end
        local cap = 2 * (2 * s[2] + 1)
        local e = math.min(cap, left)
        out[#out + 1] = { n = s[1], l = s[2], e = e }
        left = left - e
    end
    local fx = CONFIG_FIX[nelec]
    if fx then
        local from, to
        for _, s in ipairs(out) do
            if s.n == fx[1] and s.l == fx[2] then from = s end
            if s.n == fx[3] and s.l == fx[4] then to = s end
        end
        if from and from.e >= fx[5] then
            from.e = from.e - fx[5]
            if to then to.e = to.e + fx[5]
            else out[#out + 1] = { n = fx[3], l = fx[4], e = fx[5] } end
            if from.e == 0 then
                for i, s in ipairs(out) do
                    if s == from then table.remove(out, i); break end
                end
            end
        end
    end
    D._cfg[nelec] = out
    return out
end


-- how many rings (periods) this element needs — used to size the atom.
function D.period(z)
    local sum = 0
    for i, cap in ipairs(D.SHELLS) do
        sum = sum + cap
        if z <= sum then return i end
    end
    return #D.SHELLS
end

-- periodic-table board position: col 1..18, row 1..9 (rows 8/9 are the lanthanide /
-- actinide strips). This is the standard 18-column layout with the f-block pulled out.
function D.grid(z)
    if z == 1 then return 1, 1 elseif z == 2 then return 18, 1 end
    if z <= 4 then return z - 2, 2 elseif z <= 10 then return z + 8, 2 end   -- Li,Be | B..Ne
    if z <= 12 then return z - 10, 3 elseif z <= 18 then return z, 3 end       -- Na,Mg | Al..Ar
    if z <= 36 then return z - 18, 4 end                                        -- K..Kr
    if z <= 54 then return z - 36, 5 end                                        -- Rb..Xe
    if z <= 56 then return z - 54, 6 end                                        -- Cs,Ba
    if z == 57 then return 3, 6 elseif z <= 71 then return z - 54, 8 end         -- La | Ce..Lu (strip)
    if z <= 86 then return z - 68, 6 end                                        -- Hf..Rn
    if z <= 88 then return z - 86, 7 end                                        -- Fr,Ra
    if z == 89 then return 3, 7 elseif z <= 103 then return z - 86, 9 end        -- Ac | Th..Lr (strip)
    return z - 100, 7                                                            -- Rf..Og
end

-- Isotope stability. EXACT stable-N sets where the band model is wrong enough to matter:
-- all of Z<=20 (the early game, with real holes like K-40 and Cl-36), every monoisotopic
-- element, Tc/Pm (NO stable isotope at all — empty sets), and the hosts of the famous
-- fission products (Kr-85, Sr-90, Zr-93 must not read stable). Everything else keeps the
-- band approximation around the principal isotope (ponytail: full sets for 83 elements
-- aren't worth the error risk of hand-entering them).
D.stable_sets = {
    [1] = { 0, 1 }, [2] = { 1, 2 }, [3] = { 3, 4 }, [4] = { 5 }, [5] = { 5, 6 },
    [6] = { 6, 7 }, [7] = { 7, 8 }, [8] = { 8, 9, 10 }, [9] = { 10 }, [10] = { 10, 11, 12 },
    [11] = { 12 }, [12] = { 12, 13, 14 }, [13] = { 14 }, [14] = { 14, 15, 16 }, [15] = { 16 },
    [16] = { 16, 17, 18, 20 }, [17] = { 18, 20 }, [18] = { 18, 20, 22 }, [19] = { 20, 22 },
    [20] = { 20, 22, 23, 24, 26, 28 },
    [21] = { 24 }, [25] = { 30 }, [27] = { 32 }, [33] = { 42 },
    [36] = { 42, 44, 46, 47, 48, 50 }, [38] = { 46, 48, 49, 50 }, [39] = { 50 },
    [40] = { 50, 51, 52, 54, 56 }, [41] = { 52 }, [43] = {},
    [44] = { 52, 54, 55, 56, 57, 58, 60 }, -- Ru: Tc-98's beta- daughter Ru-98 must read stable (no EC loop back)
    [45] = { 58 },
    [53] = { 74 }, [55] = { 78 }, [59] = { 82 }, [61] = {}, [65] = { 94 }, [67] = { 98 },
    [69] = { 100 }, [79] = { 118 }, [83] = { 126 },
}
D.stable_lut = {}
for z, set in pairs(D.stable_sets) do
    local lut = {}
    for _, n in ipairs(set) do lut[n] = true end
    D.stable_lut[z] = lut
end

-- Neutron drip line: max bound N per Z. EXACT (experimentally established heaviest bound
-- isotope) through neon: H-3, He-8, Li-11, Be-14, B-19, C-22, N-23, O-24 (the famous oxygen
-- anomaly), F-31, Ne-34. Beyond neon the drip line is UNKNOWN TO SCIENCE — 2Z+2 is the
-- playable stand-in for that frontier, not an approximation of known data.
D.DRIP = { 2, 6, 8, 10, 14, 16, 16, 16, 22, 24 }
function D.neutron_max(z) return D.DRIP[z] or (2 * z + 2) end

function D.has_stable(z)
    local set = D.stable_sets[z]
    if set then return #set > 0 end
    return z <= 83
end
function D.band(z) return 1 + math.floor(z / 22) end -- stable-N half-width, widens with Z
function D.principal(z) return (D.mass[z] or (2 * z)) - z end

function D.stable_span(z)
    local set = D.stable_sets[z]
    if set and #set > 0 then return set[1], set[#set] end
    local n0 = D.principal(z)
    local b = D.band(z)
    return n0 - b, n0 + b
end

function D.is_stable(z, n)
    if not D.has_stable(z) then return false end
    local lut = D.stable_lut[z]
    if lut then return lut[n] == true end
    local lo, hi = D.stable_span(z)
    return n >= lo and n <= hi
end

-- sym -> Z, so a molecule can look up its partner atoms' nuclei.
D.z_of = {}
for _, e in ipairs(D.elements) do D.z_of[e[2]] = e[1] end

-- ==================== REAL NUCLIDES: half-life + decay mode ====================
-- Curated { t1/2 seconds, dominant decay mode } for every isotope the game lands on: the
-- principal isotope of every radioactive element, the famous lab isotopes, ALL FOUR natural
-- decay chains (4n thorium, 4n+1 neptunium, 4n+2 uranium, 4n+3 actinium) so a heavy atom
-- walks the textbook chain to its real lead/bismuth endpoint, the transuranic feeders that
-- join those chains, and the reported superheavy alpha chains. Modes: alpha | betam | betap
-- | ec | sf. Where branches compete, the dominant one is used (Bi-212 64% beta-, Fl-286
-- ~50% alpha...). Estimates only cover nuclides off this charted map.
local MIN, HR, DAY, YR = 60, 3600, 86400, 3.156e7
D.nuclides = {
    -- light: the famous lab / cosmogenic isotopes (real modes: Be-7 is PURE EC, not beta+)
    ["H-3"] = { 12.32 * YR, "betam" }, ["Be-7"] = { 53.2 * DAY, "ec" },
    ["Be-10"] = { 1.39e6 * YR, "betam" }, ["C-11"] = { 20.4 * MIN, "betap" },
    ["C-14"] = { 5730 * YR, "betam" }, ["N-13"] = { 9.97 * MIN, "betap" },
    ["O-15"] = { 122, "betap" }, ["F-18"] = { 1.83 * HR, "betap" },
    ["Na-22"] = { 2.60 * YR, "betap" }, ["Na-24"] = { 15.0 * HR, "betam" },
    ["P-32"] = { 14.27 * DAY, "betam" }, ["S-35"] = { 87.4 * DAY, "betam" },
    ["Cl-36"] = { 3.0e5 * YR, "betam" }, ["K-40"] = { 1.25e9 * YR, "betam" },
    ["Ca-45"] = { 163 * DAY, "betam" }, ["Fe-59"] = { 44.5 * DAY, "betam" },
    ["Co-60"] = { 5.27 * YR, "betam" }, ["Kr-85"] = { 10.76 * YR, "betam" },
    ["Sr-90"] = { 28.8 * YR, "betam" }, ["Zr-93"] = { 1.61e6 * YR, "betam" },
    ["Tc-98"] = { 4.2e6 * YR, "betam" }, ["Tc-99"] = { 2.11e5 * YR, "betam" },
    ["I-131"] = { 8.02 * DAY, "betam" }, ["Cs-137"] = { 30.1 * YR, "betam" },
    ["Pm-145"] = { 17.7 * YR, "ec" },
    -- polonium-to-uranium principals + the 4n+2 URANIUM chain (U-238 -> ... -> Pb-206)
    ["Po-209"] = { 102 * YR, "alpha" }, ["Po-210"] = { 138.4 * DAY, "alpha" },
    ["At-210"] = { 8.1 * HR, "ec" }, ["Rn-222"] = { 3.82 * DAY, "alpha" },
    ["Fr-223"] = { 22.0 * MIN, "betam" }, ["Ra-226"] = { 1600 * YR, "alpha" },
    ["Ac-227"] = { 21.8 * YR, "betam" }, ["Th-232"] = { 1.40e10 * YR, "alpha" },
    ["Pa-231"] = { 3.28e4 * YR, "alpha" }, ["U-235"] = { 7.04e8 * YR, "alpha" },
    ["U-238"] = { 4.47e9 * YR, "alpha" },
    ["Th-234"] = { 24.1 * DAY, "betam" }, ["Pa-234"] = { 6.70 * HR, "betam" },
    ["U-234"] = { 2.455e5 * YR, "alpha" }, ["Th-230"] = { 7.54e4 * YR, "alpha" },
    ["Po-218"] = { 3.1 * MIN, "alpha" }, ["Pb-214"] = { 26.8 * MIN, "betam" },
    ["Bi-214"] = { 19.9 * MIN, "betam" }, ["Po-214"] = { 1.643e-4, "alpha" },
    ["Pb-210"] = { 22.2 * YR, "betam" }, ["Bi-210"] = { 5.01 * DAY, "betam" },
    -- 4n THORIUM chain (Th-232 -> ... -> Pb-208)
    ["Ra-228"] = { 5.75 * YR, "betam" }, ["Ac-228"] = { 6.15 * HR, "betam" },
    ["Th-228"] = { 1.91 * YR, "alpha" }, ["Ra-224"] = { 3.63 * DAY, "alpha" },
    ["Rn-220"] = { 55.6, "alpha" }, ["Po-216"] = { 0.145, "alpha" },
    ["Pb-212"] = { 10.64 * HR, "betam" }, ["Bi-212"] = { 60.55 * MIN, "betam" },
    ["Po-212"] = { 3.0e-7, "alpha" },
    -- 4n+3 ACTINIUM chain (U-235 -> ... -> Pb-207)
    ["Th-231"] = { 25.5 * HR, "betam" }, ["Th-227"] = { 18.7 * DAY, "alpha" },
    ["Ra-223"] = { 11.43 * DAY, "alpha" }, ["Rn-219"] = { 3.96, "alpha" },
    ["Po-215"] = { 1.78e-3, "alpha" }, ["Pb-211"] = { 36.1 * MIN, "betam" },
    ["Bi-211"] = { 2.14 * MIN, "alpha" }, ["Tl-207"] = { 4.77 * MIN, "betam" },
    -- 4n+1 NEPTUNIUM chain (Np-237 -> ... -> Bi-209)
    ["Np-237"] = { 2.14e6 * YR, "alpha" }, ["Pa-233"] = { 27.0 * DAY, "betam" },
    ["U-233"] = { 1.592e5 * YR, "alpha" }, ["Th-229"] = { 7880 * YR, "alpha" },
    ["Ra-225"] = { 14.9 * DAY, "betam" }, ["Ac-225"] = { 10.0 * DAY, "alpha" },
    ["Fr-221"] = { 4.8 * MIN, "alpha" }, ["At-217"] = { 3.23e-2, "alpha" },
    ["Bi-213"] = { 45.6 * MIN, "betam" }, ["Po-213"] = { 3.7e-6, "alpha" },
    ["Pb-209"] = { 3.23 * HR, "betam" },
    -- transuranic principals + the feeders that join the natural chains
    ["Pu-239"] = { 2.41e4 * YR, "alpha" }, ["Pu-244"] = { 8.0e7 * YR, "alpha" },
    ["U-240"] = { 14.1 * HR, "betam" }, ["Np-240"] = { 61.9 * MIN, "betam" },
    ["Pu-240"] = { 6561 * YR, "alpha" }, ["U-236"] = { 2.342e7 * YR, "alpha" },
    ["Am-243"] = { 7370 * YR, "alpha" }, ["Np-239"] = { 2.36 * DAY, "betam" },
    ["Cm-247"] = { 1.56e7 * YR, "alpha" }, ["Pu-243"] = { 4.96 * HR, "betam" },
    ["Bk-247"] = { 1380 * YR, "alpha" }, ["Cf-251"] = { 900 * YR, "alpha" },
    ["Es-252"] = { 471.7 * DAY, "alpha" }, ["Fm-257"] = { 100.5 * DAY, "alpha" },
    ["Cf-253"] = { 17.8 * DAY, "betam" }, ["Es-253"] = { 20.5 * DAY, "alpha" },
    ["Bk-249"] = { 330 * DAY, "betam" }, ["Cf-249"] = { 351 * YR, "alpha" },
    ["Cm-245"] = { 8500 * YR, "alpha" }, ["Pu-241"] = { 14.35 * YR, "betam" },
    ["Am-241"] = { 432.6 * YR, "alpha" },
    ["Md-258"] = { 51.5 * DAY, "alpha" }, ["Es-254"] = { 275.7 * DAY, "alpha" },
    ["Bk-250"] = { 3.21 * HR, "betam" }, ["Cf-250"] = { 13.1 * YR, "alpha" },
    ["Cm-246"] = { 4760 * YR, "alpha" }, ["Pu-242"] = { 3.75e5 * YR, "alpha" },
    ["No-259"] = { 58 * MIN, "alpha" }, ["Fm-255"] = { 20.1 * HR, "alpha" },
    -- superheavies: real dominant modes (SF only where SF really dominates) + their
    -- reported alpha chains down to a charted endpoint
    ["Lr-266"] = { 10 * HR, "sf" }, ["Rf-267"] = { 1.3 * HR, "sf" },
    ["Db-268"] = { 28 * HR, "sf" }, ["Sg-269"] = { 14 * MIN, "alpha" },
    ["Rf-265"] = { 1.1 * MIN, "sf" }, ["Bh-270"] = { 61, "alpha" },
    ["Hs-269"] = { 9.7, "alpha" }, ["Sg-265"] = { 9.0, "alpha" },
    ["Rf-261"] = { 68, "alpha" }, ["No-257"] = { 24.5, "alpha" },
    ["Fm-253"] = { 3.0 * DAY, "ec" },
    ["Mt-278"] = { 7.0, "alpha" }, ["Bh-274"] = { 54, "alpha" },
    ["Db-270"] = { 1.0 * HR, "alpha" },
    ["Ds-281"] = { 13.0, "sf" }, ["Rg-282"] = { 100, "alpha" },
    ["Cn-285"] = { 28, "alpha" }, ["Nh-286"] = { 9.5, "alpha" },
    ["Fl-289"] = { 1.9, "alpha" }, ["Mc-290"] = { 0.65, "alpha" },
    ["Lv-293"] = { 0.057, "alpha" }, ["Ts-294"] = { 0.051, "alpha" },
    ["Og-294"] = { 0.00069, "alpha" }, ["Lv-290"] = { 0.0083, "alpha" },
    ["Fl-286"] = { 0.12, "alpha" }, ["Cn-282"] = { 8.0e-4, "sf" },
}

local function nuclide_of(z, n)
    local e = D.elements[z]
    return e and D.nuclides[e[2] .. "-" .. (z + n)] or nil
end

-- real dominant decay mode when charted, nil when science (or this table) has no entry.
function D.mode_of(z, n)
    local nu = nuclide_of(z, n)
    return nu and nu[2] or nil
end

-- t1/2 in seconds: charted nuclide first, else a rough trend for the unknown corners.
-- The trends aren't real data — alpha t1/2 is really Geiger-Nuttall in Q-alpha — but they
-- only ever fire off the charted map above.
function D.halflife_s(z, n)
    local nu = nuclide_of(z, n)
    if nu then return nu[1] end
    local lg
    if z > 83 then
        if n > D.principal(z) then
            lg = 6.0 - 1.5 * (n - D.principal(z)) -- beta- side of the heavy valley
        else
            lg = 7.1 - 0.30 * (z - 84) - 1.5 * math.abs(n - D.principal(z))
        end
    else
        local lo, hi = D.stable_span(z)
        local d = (n > hi) and (n - hi) or (lo - n)
        lg = 8.5 - 4.2 * (math.max(1, d) - 1)
    end
    if lg < -4 then lg = -4 elseif lg > 18 then lg = 18 end
    return 10.0 ^ lg
end

-- human-readable half-life, ASCII only (the UI font has no mu).
function D.fmt_hl(s)
    local function f(v, u) return string.format("%.3g %s", v, u) end
    if s < 1e-3 then return f(s * 1e6, "us") end
    if s < 1.0 then return f(s * 1e3, "ms") end
    if s < 90 then return f(s, "s") end
    if s < 90 * MIN then return f(s / MIN, "min") end
    if s < 48 * HR then return f(s / HR, "h") end
    if s < 2 * YR then return f(s / DAY, "d") end
    local y = s / YR
    if y < 1e3 then return f(y, "y") end
    if y < 1e6 then return f(y / 1e3, "ky") end
    if y < 1e9 then return f(y / 1e6, "My") end
    if y < 1e12 then return f(y / 1e9, "Gy") end
    return string.format("%.1e y", y)
end

-- Molecules the player can coalesce, with how to render them: "diatomic" = two equal
-- nuclei sharing a cloud; "central" = a core nucleus (the built atom) with partner atoms
-- bonded around it at the given angles (radians, y-down screen).
-- ==================== MOLECULE / REACTION GENERATOR ====================
-- Covalent binary compounds are NOT hand-listed. Each element's valence DERIVES: the formula
-- (valence crossover), the shape (VSEPR steric number -> bond angles), the lone pairs, and the
-- balanced formation equation. A small `overrides` table supplies only what a formula cannot:
-- lore text, the real catalyst/condition, and the memorable industrial equation.
--   ve  = valence electrons (main-group number)   val = normal covalent valence (# bonds)
--   diatomic = forms an X2 gas   hydride = X + val H   chloride = X + val Cl
--   ox  = oxidation states forming a single-central molecular oxide XO_(k/2)  (k even)
local CHEM_ORDER = { "H", "C", "N", "O", "F", "Si", "P", "S", "Cl" } -- stable gen order (pairs() is not)
local CHEM = {
    H  = { ve = 1, val = 1, diatomic = true },
    C  = { ve = 4, val = 4, hydride = true, chloride = true, ox = { 2, 4 } },
    N  = { ve = 5, val = 3, diatomic = true, hydride = true, chloride = true, ox = { 2, 4 } },
    O  = { ve = 6, val = 2, diatomic = true, hydride = true },
    F  = { ve = 7, val = 1, diatomic = true, hydride = true },
    Si = { ve = 4, val = 4, hydride = true, chloride = true },
    P  = { ve = 5, val = 3, hydride = true, chloride = true },
    S  = { ve = 6, val = 2, hydride = true, chloride = true, ox = { 4, 6 } },
    Cl = { ve = 7, val = 1, diatomic = true, hydride = true },
}

-- what formulas can't give: lore + real conditions/catalysts + the memorable equation.
local overrides = {
    H2  = { name = "Hydrogen gas", lore = "The fuel of stars and the future; two atoms sharing, each now complete." },
    O2  = { name = "Oxygen gas",   lore = "Two oxygens double-bonded; the air's fire - what everything that burns or breathes needs." },
    N2  = { name = "Nitrogen gas", lore = "Two nitrogens bound so tightly they make up 78% of the air and smother flame." },
    F2  = { name = "Fluorine gas", lore = "Pale-yellow and savage - the most reactive element; it burns almost anything." },
    Cl2 = { name = "Chlorine gas", lore = "Green and choking - a war gas, and the guardian of clean water." },
    H2O = { cond = "spark", eq = "2 H2 + O2 -> 2 H2O", lore = "You are 60% of this. Two hydrogens embracing one oxygen - the molecule of life." },
    NH3 = { cat = "Fe", cond = { "heat", "pressure" }, lore = "The Haber process pulled it from the air and fed billions." },
    CH4 = { cat = "Ni", cond = "heat", lore = "Natural gas, swamp gas, and the flame on your stove." },
    H2S = { cond = "heat", lore = "Rotten eggs and volcanic vents; deadlier than cyanide, yet life may have begun on it." },
    HF  = { lore = "Etches glass and dissolves silicon; a weak acid with a vicious bite." },
    HCl = { lore = "Your stomach's acid and the workhorse of the chemistry bench." },
    PH3 = { lore = "Phosphine - toxic, spontaneously flammable, smelling of garlic and decay." },
    SiH4 = { lore = "Silane - silicon's answer to methane; bursts into flame in air." },
    CO  = { cond = "spark", lore = "The silent killer - odourless, it binds your blood 200x tighter than oxygen." },
    CO2 = { cond = "spark", lore = "The breath you exhale and the blanket warming the world." },
    NO  = { cond = "spark", lore = "Made by lightning and your own blood vessels; a signal molecule and smog's start." },
    NO2 = { eq = "2 NO + O2 -> 2 NO2", lore = "The brown haze over cities; oxidises further and rains down as nitric acid." },
    SO2 = { cond = "spark", lore = "Sharp, choking gas of volcanoes and struck matches; the sting in acid rain." },
    SO3 = { cat = "V2O5", cond = "heat", eq = "2 SO2 + O2 -> 2 SO3", lore = "Reacts with water to make sulfuric acid - the most produced chemical on Earth." },
    CCl4 = { lore = "Once a dry-cleaning solvent and fire extinguisher; now known to wreck ozone and liver." },
    SiCl4 = { lore = "Fumes in moist air; the feedstock for pure silicon and optical fibre." },
    PCl3 = { lore = "A fuming liquid that chlorinates almost anything it touches." },
    SCl2 = { lore = "Cherry-red and foul; the precursor to mustard gas." },
    NCl3 = { lore = "Nitrogen trichloride - an oily, touch-sensitive explosive." },
}
local HYDRIDE_NAME = { CH4 = "Methane", NH3 = "Ammonia", H2O = "Water", HF = "Hydrogen fluoride",
    SiH4 = "Silane", PH3 = "Phosphine", H2S = "Hydrogen sulfide", HCl = "Hydrogen chloride" }
local OX_PREFIX = { [1] = "mon", [2] = "di", [3] = "tri", [4] = "tetr" }     -- + "oxide"
local CL_PREFIX = { [1] = "mono", [2] = "di", [3] = "tri", [4] = "tetra" }   -- + "chloride"
local HALF = math.pi / 2  -- "down" in y-down screen; bent/pyramidal molecules open downward

local function sub(n) return n > 1 and tostring(n) or "" end            -- formula subscript
local function coef(n) return n > 1 and (tostring(n) .. " ") or "" end  -- equation coefficient
local function fullname(sym) local z = D.z_of[sym]; return z and D.get(z).name or sym end

-- VSEPR: n bonding atoms + lp effective lone pairs -> screen angles (radians). Reproduces
-- linear (CO2), bent (H2O/SO2/NO2), trigonal (SO3), pyramidal (NH3), tetrahedral (CH4).
local function geometry(n, lp)
    if n <= 1 then return { 0.0 } end
    if n == 2 then
        if lp <= 0 then return { 0.0, math.pi } end                 -- linear
        local th = (lp == 1) and 2.09 or 1.81                       -- bent ~120 (SO2) / ~105 (H2O)
        return { HALF - th / 2, HALF + th / 2 }
    end
    if n == 3 then
        if lp <= 0 then return { HALF, HALF + 2.0944, HALF + 4.1888 } end  -- trigonal 120
        return { HALF - 0.79, HALF, HALF + 0.79 }                   -- pyramidal (NH3)
    end
    local a = {}                                                    -- tetrahedral+: evenly spaced
    for i = 0, n - 1 do a[i + 1] = 0.785 + i * (2 * math.pi / n) end
    return a
end

-- balanced formation eq: a (core|core2) + b ligand2 -> c product.  ligand2 = "H2"/"O2"/"Cl2".
local function formation_eq(core, coreDi, ligand2, n, product)
    local a, b, c, corestr
    if coreDi then a, b, c, corestr = 1, n, 2, core .. "2"                 -- X2 + n L2 -> 2 XLn
    elseif n % 2 == 0 then a, b, c, corestr = 1, math.floor(n / 2), 1, core -- X + (n/2) L2 -> XLn
    else a, b, c, corestr = 2, n, 2, core end                             -- 2 X + n L2 -> 2 XLn
    return string.format("%s%s + %s%s -> %s%s", coef(a), corestr, coef(b), ligand2, coef(c), product)
end

D.molecules, D.reactions, D.mol_list = {}, {}, {}
-- rem = non-bonding electrons on the core; a lone electron (radical, e.g. NO2) still bends the
-- shape, so geometry rounds it up while the lone-pair dots show only full pairs.
local function emit(sym, name, render, core, ligand, n, rem, eq)
    local ov = overrides[sym] or {}
    local m = { sym = sym, name = ov.name or name, render = render, core = core, lore = ov.lore or (name .. ".") }
    if render == "central" then
        local ang = geometry(n, math.ceil(rem / 2))
        local p = {}
        for i = 1, n do p[i] = { ligand, ang[i] } end
        m.partners, m.lone = p, math.floor(rem / 2) * 2
    end
    D.molecules[sym] = m
    D.mol_list[#D.mol_list + 1] = sym
    D.reactions[sym] = { core = core, partner = ligand, n = n, product = sym,
        cat = ov.cat, cond = ov.cond, eq = ov.eq or eq }
end

for _, sym in ipairs(CHEM_ORDER) do
    local c = CHEM[sym]
    local grp = c.ve + 10  -- main-group number (C=14 ... Cl=17)
    if c.diatomic then
        emit(sym .. "2", fullname(sym) .. " gas", "diatomic", sym, sym, 1, 0, sym .. " + " .. sym .. " -> " .. sym .. "2")
    end
    if c.hydride then
        local v = c.val
        local f = (grp >= 16) and ("H" .. sub(v) .. sym) or (sym .. "H" .. sub(v)) -- H first for O/F/S/Cl
        emit(f, HYDRIDE_NAME[f] or (fullname(sym) .. " hydride"), "central", sym, "H", v, c.ve - v,
            formation_eq(sym, c.diatomic, "H2", v, f))
    end
    if c.ox then
        for _, k in ipairs(c.ox) do
            local m = math.floor(k / 2)
            local f = sym .. "O" .. sub(m)
            emit(f, fullname(sym) .. " " .. (OX_PREFIX[m] or (m .. "-")) .. "oxide", "central", sym, "O", m, c.ve - k,
                formation_eq(sym, c.diatomic, "O2", m, f))
        end
    end
    if c.chloride then
        local v = c.val
        local f = sym .. "Cl" .. sub(v)
        emit(f, fullname(sym) .. " " .. (CL_PREFIX[v] or (v .. "-")) .. "chloride", "central", sym, "Cl", v, c.ve - v,
            formation_eq(sym, c.diatomic, "Cl2", v, f))
    end
end

-- ==================== ACIDS (species-reaction products) ====================
-- Made on the BENCH by reacting molecules with molecules (see D.species), never coalesced
-- from a core atom — so they carry no render spec (card + discovered-strip only).
local ACIDS = {
    { "H2SO4", "Sulfuric acid", "The king of chemicals - battery acid, fertiliser, and the world's most-made compound." },
    { "H2SO3", "Sulfurous acid", "Acid rain's opening act - sulfur dioxide dissolved in cloud water." },
    { "H2CO3", "Carbonic acid", "The fizz in soda and the slow sculptor of caves." },
    { "HNO3", "Nitric acid", "Aqua fortis - dissolves silver, feeds crops, and fuels explosives." },
    -- other bench-only products (same treatment: card + strip, no live render)
    { "NH4Cl", "Ammonium chloride", "The white-smoke demo - two invisible gases meet and a salt snows out of thin air." },
    { "MgSO4", "Magnesium sulfate", "Epsom salt - bath soaks, laxatives, and the gardener's magnesium fix." },
    { "CaSO4", "Calcium sulfate", "Gypsum - plaster casts, drywall, and chalkboard chalk." },
    { "SiO2", "Silicon dioxide", "Quartz, sand, and glass - the skin of the Earth." },
    { "O3", "Ozone", "The sharp smell after lightning; the fragile shield soaking up the sun's UV." },
}
for _, a in ipairs(ACIDS) do
    D.molecules[a[1]] = { sym = a[1], name = a[2], lore = a[3] }
    D.mol_list[#D.mol_list + 1] = a[1]
end

-- ==================== IONIC SALTS ====================
-- Metal + nonmetal -> electron TRANSFER -> a lattice of ions (render = "lattice", not
-- ball-and-stick). Generated from ion charges: M(+m) + X(-x) -> M_a X_b with a=x/g, b=m/g.
local METALS = { { "Li", 1 }, { "Na", 1 }, { "K", 1 }, { "Mg", 2 }, { "Ca", 2 }, { "Al", 3 } }
local SALT_ANIONS = { { "F", 1, "fluoride" }, { "Cl", 1, "chloride" }, { "O", 2, "oxide" }, { "S", 2, "sulfide" } }
local salt_lore = {
    NaCl = "Table salt - the taste of the sea; wars were fought and roads were built for it.",
    NaF = "The fluoride in toothpaste; a trace of it armours your enamel.",
    KCl = "Salt substitute and plant fertiliser; the potassium your nerves run on.",
    LiF = "So tough X-rays barely pass; the window on radiation detectors.",
    LiCl = "Drinks moisture straight from the air; the saltiest-tasting salt there is.",
    MgO = "Firebrick and milk of magnesia; refuses to melt below 2800 C.",
    MgCl2 = "De-ices roads and firms tofu; harvested from seawater.",
    CaO = "Quicklime - roasted limestone; slaked with water it built Rome's concrete.",
    CaCl2 = "Road de-icer and moisture eater; the brine that never quite dries.",
    CaF2 = "Fluorite - the glowing mineral that gave fluorescence its name.",
    Al2O3 = "Corundum - sapphire and ruby are this lattice with a pinch of colour.",
}
local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end
for _, mt in ipairs(METALS) do
    for _, an in ipairs(SALT_ANIONS) do
        local g = gcd(mt[2], an[2])
        local a, b = math.floor(an[2] / g), math.floor(mt[2] / g) -- metal count, anion count (int: 5.3+ / is float)
        local f = mt[1] .. sub(a) .. an[1] .. sub(b)
        local diatomicX = an[1] ~= "S" -- F2/Cl2/O2 gases; sulfur reacts as the solid (ponytail: really S8)
        local eq
        if not diatomicX then
            eq = string.format("%s%s + %s%s -> %s%s", coef(a), mt[1], coef(b), an[1], "", f)
        elseif b % 2 == 0 then
            eq = string.format("%s%s + %s%s2 -> %s", coef(a), mt[1], coef(math.floor(b / 2)), an[1], f)
        else
            eq = string.format("%s%s + %s%s2 -> %s%s", coef(2 * a), mt[1], coef(b), an[1], "2 ", f)
        end
        D.molecules[f] = { sym = f, name = fullname(mt[1]) .. " " .. an[3], render = "lattice",
            cation = mt[1], anion = an[1], a = a, b = b, chg = mt[2], achg = an[2],
            lore = salt_lore[f] or "An ionic crystal - a lattice of + and - ions locked by pure attraction." }
        D.mol_list[#D.mol_list + 1] = f
        -- burning a metal in oxygen needs ignition; metal + sulfur needs heat (the classic
        -- Fe/S demo); alkali metal + halogen just goes.
        D.reactions[f] = { core = mt[1], partner = an[1], n = b, product = f, ionic = true,
            cond = (an[1] == "O") and "spark" or (an[1] == "S") and "heat" or nil, eq = eq }
    end
end

for _, r in pairs(D.reactions) do r.core_z = D.z_of[r.core] end

-- ==================== SPECIES REACTIONS (the bench) ====================
-- True stoichiometry: react MOLECULES with MOLECULES from the shelf. needs/gives are
-- species counts; cat/cond use the same catalyst chips as formation reactions.
D.species = {
    { needs = { H2 = 2, O2 = 1 }, gives = { H2O = 2 }, cond = "spark", eq = "2 H2 + O2 -> 2 H2O" },
    { needs = { N2 = 1, H2 = 3 }, gives = { NH3 = 2 }, cat = "Fe", cond = { "heat", "pressure" }, eq = "N2 + 3 H2 -> 2 NH3" },
    { needs = { CH4 = 1, O2 = 2 }, gives = { CO2 = 1, H2O = 2 }, cond = "spark", eq = "CH4 + 2 O2 -> CO2 + 2 H2O" },
    { needs = { CO = 2, O2 = 1 }, gives = { CO2 = 2 }, cond = "spark", eq = "2 CO + O2 -> 2 CO2" },
    { needs = { NO = 2, O2 = 1 }, gives = { NO2 = 2 }, eq = "2 NO + O2 -> 2 NO2" },
    { needs = { SO2 = 2, O2 = 1 }, gives = { SO3 = 2 }, cat = "V2O5", cond = "heat", eq = "2 SO2 + O2 -> 2 SO3" },
    { needs = { SO3 = 1, H2O = 1 }, gives = { H2SO4 = 1 }, eq = "SO3 + H2O -> H2SO4" },
    { needs = { SO2 = 1, H2O = 1 }, gives = { H2SO3 = 1 }, eq = "SO2 + H2O -> H2SO3" },
    { needs = { CO2 = 1, H2O = 1 }, gives = { H2CO3 = 1 }, eq = "CO2 + H2O -> H2CO3" },
    { needs = { NO2 = 3, H2O = 1 }, gives = { HNO3 = 2, NO = 1 }, eq = "3 NO2 + H2O -> 2 HNO3 + NO" },
    -- gas-phase classics
    { needs = { NH3 = 1, HCl = 1 }, gives = { NH4Cl = 1 }, eq = "NH3 + HCl -> NH4Cl" }, -- white smoke, on contact
    { needs = { H2S = 2, O2 = 3 }, gives = { SO2 = 2, H2O = 2 }, cond = "spark", eq = "2 H2S + 3 O2 -> 2 SO2 + 2 H2O" },
    { needs = { NH3 = 4, O2 = 5 }, gives = { NO = 4, H2O = 6 }, cat = "Pt", cond = "heat",
        eq = "4 NH3 + 5 O2 -> 4 NO + 6 H2O" }, -- Ostwald: Haber -> here -> NO2 -> HNO3
    { needs = { SiH4 = 1, O2 = 2 }, gives = { SiO2 = 1, H2O = 2 }, eq = "SiH4 + 2 O2 -> SiO2 + 2 H2O" }, -- silane is pyrophoric
    { needs = { O2 = 3 }, gives = { O3 = 2 }, cond = "spark", eq = "3 O2 -> 2 O3" }, -- lightning makes ozone
    -- acid + metal -> salt + hydrogen: `core` = the reaction consumes the BUILT atom as the
    -- metal reagent (divalent metals only, so whole H2 molecules come off one atom).
    { core = "Mg", needs = { H2SO4 = 1 }, gives = { MgSO4 = 1, H2 = 1 }, eq = "Mg + H2SO4 -> MgSO4 + H2" },
    { core = "Ca", needs = { H2SO4 = 1 }, gives = { CaSO4 = 1, H2 = 1 }, eq = "Ca + H2SO4 -> CaSO4 + H2" },
    { core = "Mg", needs = { HCl = 2 }, gives = { MgCl2 = 1, H2 = 1 }, eq = "Mg + 2 HCl -> MgCl2 + H2" },
    { core = "Ca", needs = { HCl = 2 }, gives = { CaCl2 = 1, H2 = 1 }, eq = "Ca + 2 HCl -> CaCl2 + H2" },
}

return D
