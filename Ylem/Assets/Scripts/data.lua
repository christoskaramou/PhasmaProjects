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

-- Principal isotope mass number A per Z (most abundant stable, or longest-lived known for
-- radioactive). principal-N = A - Z. Standard values; exact enough for nucleus size + the
-- neutron auto-accrete.
D.mass = {
    1, 4, 7, 9, 11, 12, 14, 16, 19, 20,
    23, 24, 27, 28, 31, 32, 35, 40, 39, 40,
    45, 48, 51, 52, 55, 56, 59, 58, 64, 65,
    70, 73, 75, 79, 80, 84, 85, 88, 89, 91,
    93, 96, 98, 101, 103, 106, 108, 112, 115, 119,
    122, 128, 127, 131, 133, 137, 139, 140, 141, 144,
    145, 150, 152, 157, 159, 163, 165, 167, 169, 173,
    175, 178, 181, 184, 186, 190, 192, 195, 197, 201,
    204, 207, 209, 209, 210, 222, 223, 226, 227, 232,
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

function D.get(z)
    local e = D.elements[z]
    if not e then return nil end
    return { z = e[1], sym = e[2], name = e[3], cat = e[4], lore = D.lore(z) }
end

-- Electron configuration (Madelung / Aufbau fill order) — the foundation for the orbital
-- cloud view. FILL_ORDER lists subshells (n, l) in fill order up to 7p (covers Z 1..118);
-- l = 0/1/2/3 = s/p/d/f, subshell capacity 2(2l+1).
D.L_CHAR = { [0] = "s", [1] = "p", [2] = "d", [3] = "f" }
D.FILL_ORDER = {
    { 1, 0 }, { 2, 0 }, { 2, 1 }, { 3, 0 }, { 3, 1 }, { 4, 0 }, { 3, 2 }, { 4, 1 }, { 5, 0 }, { 4, 2 },
    { 5, 1 }, { 6, 0 }, { 4, 3 }, { 5, 2 }, { 6, 1 }, { 7, 0 }, { 5, 3 }, { 6, 2 }, { 7, 1 },
}

-- subshells filling `nelec` electrons in Madelung order: { {n=,l=,e=}, ... }
function D.config(nelec)
    local out = {}
    for _, s in ipairs(D.FILL_ORDER) do
        if nelec <= 0 then break end
        local cap = 2 * (2 * s[2] + 1)
        local e = math.min(cap, nelec)
        out[#out + 1] = { n = s[1], l = s[2], e = e }
        nelec = nelec - e
    end
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

-- Isotope stability (ponytail band model). Nothing past Bismuth has a stable isotope.
function D.has_stable(z) return z <= 83 end
function D.band(z) return 1 + math.floor(z / 22) end -- stable-N half-width, widens with Z
function D.principal(z) return (D.mass[z] or (2 * z)) - z end

function D.stable_span(z)
    local n0 = D.principal(z)
    local b = D.band(z)
    return n0 - b, n0 + b
end

function D.is_stable(z, n)
    if not D.has_stable(z) then return false end
    local lo, hi = D.stable_span(z)
    return n >= lo and n <= hi
end

-- sym -> Z, so a molecule can look up its partner atoms' nuclei.
D.z_of = {}
for _, e in ipairs(D.elements) do D.z_of[e[2]] = e[1] end

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
    NH3 = { cat = "Fe", cond = "pressure", lore = "The Haber process pulled it from the air and fed billions." },
    CH4 = { cat = "Ni", cond = "heat", lore = "Natural gas, swamp gas, and the flame on your stove." },
    H2S = { cond = "heat", lore = "Rotten eggs and volcanic vents; deadlier than cyanide, yet life may have begun on it." },
    HF  = { lore = "Etches glass and dissolves silicon; a weak acid with a vicious bite." },
    HCl = { lore = "Your stomach's acid and the workhorse of the chemistry bench." },
    PH3 = { lore = "Phosphine - toxic, spontaneously flammable, smelling of garlic and decay." },
    SiH4 = { lore = "Silane - silicon's answer to methane; bursts into flame in air." },
    CO  = { cond = "heat", lore = "The silent killer - odourless, it binds your blood 200x tighter than oxygen." },
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

D.molecules, D.reactions = {}, {}
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
    D.reactions[sym] = { core = core, partner = ligand, n = n, product = sym,
        cat = ov.cat, cond = ov.cond, eq = ov.eq or eq }
end

for sym, c in pairs(CHEM) do
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

for _, r in pairs(D.reactions) do r.core_z = D.z_of[r.core] end

return D
