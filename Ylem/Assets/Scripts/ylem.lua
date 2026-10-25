-- Ylem — scene on_play entry. Slice 1 is a screen-space runtime_ui game (no 3D).
-- Load the Lab module and drive its one update each frame. Jev rides that same
-- tick; the decay clock is not paused while the driver thinks.

local lab = (function()
    local path = "Scripts/lab.lua"
    local src = fs.read(path)
    if not src then error("[ylem] lab module not found at " .. path) end
    return assert(load(src, "@" .. path, "bt", _ENV))()
end)()

local JevAuto = (function()
    local path = "Scripts/jev_auto.lua"
    local source = assert(fs.read(path), "Missing Jev module: " .. path)
    return assert(load(source, "@" .. path, "t", _ENV))()
end)()

lab.init()

local jev = JevAuto.attach({
    port = 9147,
    id = "ylem",
    description = "Build the target atom by adding one proton, neutron, or electron. When the nucleus is decaying, quench it before the clock runs out.",
    playing = function()
        return lab.playing()
    end,
    terminal = function()
        return lab.terminal()
    end,
    score = function()
        return lab.score()
    end,
    busy = function()
        return lab.busy()
    end,
    human_edge = function()
        return lab.human_edge()
    end,
    observe = function()
        return lab.observe()
    end,
    actions = function()
        return lab.actions()
    end,
    apply = function(id)
        lab.apply(id)
    end,
    reset = function(seed)
        lab.reset_match(seed)
    end,
    on_human = function()
        lab.on_human()
    end,
})
lab.bind_jev(jev)

-- One "play"-mode update. Re-registering the same id on Play->Stop->Play just
-- replaces the callback, so a replay is safe (lab.init() above re-seeds the atom).
script.on_update("ylem", function()
    local m = engine and engine.get_metrics and engine.get_metrics()
    local dt = (m and m.delta_ms or 16.6) / 1000.0
    if dt < 0.0 then dt = 0.0 elseif dt > 0.1 then dt = 0.1 end
    jev:tick(dt)
    lab.update(dt)
end, "play")

if pe_log then pe_log("[ylem] lab ready") end
