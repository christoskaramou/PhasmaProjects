-- ath_console — a backtick-toggled DEV overlay with HOTKEY commands.
--
-- WHY hotkeys, not a typed prompt: PhasmaRuntime exposes no text-input API to Lua
-- (InputBindings.cpp gives only input.is_key_down by SDL scancode name + mouse).
-- So "commands" are bound keys, not a parser. The Duel calls Console.update(D)
-- every frame and Console.draw(D) from the HUD; everything operates on the live
-- duel D. Scoped to manual_hero (the arena experiment) so it never touches the
-- shell/card modes.
--
-- Toggle:  `  (backtick)   — F1 also works if your layout names the key oddly.
-- While open (these don't move the hero — WASD is suppressed):
--   O / P   hero scale  - / +     (hold to ramp)
--   K / L   creep scale - / +     (hold to ramp; rescales live + future spawns)
--   U / I   wave budget - / +     (hold)
--   B       summon 1 brute        N   summon 8 swarm
--   X       kill all creeps       J   skip to next wave
--   G       toggle godmode        C   +50 gold
--
-- ENABLE: off unless ATH_DEV=1 at launch (then it still starts CLOSED; press the
-- toggle to open). When disabled, the toggle and all hotkeys are dead, nothing
-- draws -- a normal/shipped launch has no dev console. run_arena.ps1 sets ATH_DEV.

local Art = ATH_COMMON.load_script("Scripts/shared/ath_art.lua", "shared art", _ENV)

local Console = {}

local SCALE_STEP  = 0.006   -- per held frame
local BUDGET_STEP = 2.0     -- per held frame
local GOLD_STEP   = 50

local function state(D)
    local c = D.console
    if not c then
        c = { visible = false, godmode = false, msg = "" }   -- always starts closed
        D.console = c
    end
    return c
end

-- Edge-detect the toggle. Backtick resolves as "`" under SDL; OR a couple of
-- fallbacks (unknown names just return false) plus F1 as a guaranteed key.
local function toggle_pressed(D)
    local down = D:is_key_down("`") or D:is_key_down("Grave") or D:is_key_down("Backquote") or D:is_key_down("F1")
    local prev = D._console_toggle_down
    D._console_toggle_down = down
    return down and not prev
end

local function char_world_scale(D)
    return (Art.s and Art.s("char")) or 1.0
end

-- Sprite sizes are baked at rig CREATION (post-creation scale writes don't
-- reliably reach the renderer), so the scale keys edit the CONFIG value:
-- the hero updates visually on the next R-reset, creeps on their next spawn.
-- The hero's hitbox derivation is kept in sync immediately.
local function apply_hero_scale(D)
    local hero = D.hero
    if not hero then return end
    local base = hero.topdown_base_world_scale or hero.world_scale or char_world_scale(D)
    local hs = (D.config.topdown and D.config.topdown.hero_scale) or 1.0
    hero.world_scale = base * hs
    hero.body_radius = 0.55 * hero.world_scale
end

local function summon(D, role, n)
    local arch = D:role_archetype(role)
    if not (arch and D.spawns and #D.spawns > 0) then return 0 end
    local made = 0
    for k = 1, n do
        local sp = D.spawns[((D.spawn_counter + k) % #D.spawns) + 1]
        if D:spawn_one(sp, arch, true) then made = made + 1 end
    end
    return made
end

-- Called every frame from Duel:update (before input/drain). Self-gates to arena.
function Console.update(D)
    if not D.manual_hero then return end
    -- Master gate: dev console (toggle + hotkeys) is OFF unless ATH_DEV=1 at launch.
    if D._console_enabled == nil then D._console_enabled = ATH_COMMON.env_enabled("ATH_DEV", false) end
    if not D._console_enabled then return end
    local c = state(D)

    if toggle_pressed(D) then
        c.visible = not c.visible
        c.msg = c.visible and "dev console ON" or ""
    end

    -- Godmode is enforced whether or not the panel is showing.
    if c.godmode and D.hero and not D.hero.dead then D.hero.hp = D.hero.hp_max end

    if not c.visible then return end

    local td = D.config.topdown
    if td then
        if D:is_key_down("O") then td.hero_scale = math.max(0.02, (td.hero_scale or 1.0) - SCALE_STEP); apply_hero_scale(D); c.msg = string.format("hero_scale %.2f (R to apply visual)", td.hero_scale) end
        if D:is_key_down("P") then td.hero_scale = (td.hero_scale or 1.0) + SCALE_STEP; apply_hero_scale(D); c.msg = string.format("hero_scale %.2f (R to apply visual)", td.hero_scale) end
        if D:is_key_down("K") then td.creep_scale = math.max(0.02, (td.creep_scale or 1.0) - SCALE_STEP); c.msg = string.format("creep_scale %.2f (new spawns)", td.creep_scale) end
        if D:is_key_down("L") then td.creep_scale = (td.creep_scale or 1.0) + SCALE_STEP; c.msg = string.format("creep_scale %.2f (new spawns)", td.creep_scale) end
    end

    if D:is_key_down("U") then D.reserve = math.max(0.0, (D.reserve or 0.0) - BUDGET_STEP) end
    if D:is_key_down("I") then D.reserve = (D.reserve or 0.0) + BUDGET_STEP end

    if D:key_pressed("G") then c.godmode = not c.godmode; c.msg = "godmode " .. (c.godmode and "ON" or "OFF") end
    if D:key_pressed("B") then c.msg = "summon brute x" .. summon(D, "brute", 1) end
    if D:key_pressed("N") then c.msg = "summon swarm x" .. summon(D, "swarm", 8) end
    if D:key_pressed("C") then D.gold = (D.gold or 0) + GOLD_STEP; c.msg = "+" .. GOLD_STEP .. " gold" end
    if D:key_pressed("X") then
        local n = 0
        for _, cr in ipairs(D.creeps or {}) do if cr.alive then cr.alive = false; n = n + 1 end end
        c.msg = "killed " .. n
    end
    if D:key_pressed("J") then
        for _, cr in ipairs(D.creeps or {}) do cr.alive = false end
        D.reserve = 0.0; D.spawn_queue = {}
        c.msg = "skip wave"
    end
end

function Console.draw(D)
    if not (D.manual_hero and D._console_enabled) then return end
    local c = D.console
    if not (c and c.visible) then
        if c then Art.remove(D.hud, "console") end
        return
    end
    local sw = select(1, Art.surface_size())
    local function S(v) return v * Art.s("hud") end
    local td = D.config.topdown or {}
    local lines = {
        "DEV CONSOLE   ( ` or F1 to close )",
        "",
        string.format("hero scale   [O]- [P]+    %.3f", td.hero_scale or -1.0),
        string.format("creep scale  [K]- [L]+    %.3f", td.creep_scale or -1.0),
        string.format("wave budget  [U]- [I]+    %d", math.floor((D.reserve or 0.0) + 0.5)),
        "[B] +brute   [N] +swarm x8   [X] kill all",
        "[G] godmode   [C] +gold   [J] skip wave",
        string.format("godmode %s    gold %d    alive %d",
            (c.godmode and "ON" or "off"), D.gold or 0, D:count_alive()),
        (c.msg ~= "" and ("> " .. c.msg) or ""),
    }
    local w, h = S(440.0), S(264.0)
    Art.quad(D.hud, "console", sw * 0.5 - w * 0.5, S(70.0), w, h, { 0.03, 0.05, 0.06, 0.93 }, {
        border = { 0.40, 0.95, 0.55, 0.95 }, no_input = true, font_scale = 1.1,
        text_color = { 0.90, 0.99, 0.92, 1.0 },
        label = table.concat(lines, "\n"),
    })
end

return Console
