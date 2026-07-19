-- Ylem — scene on_play entry. Slice 1 is a screen-space runtime_ui game (no 3D),
-- so this stays tiny: load the Lab module and drive its one update each frame.
-- (No gamekit here — Ylem needs a single UI tick, not the topdown pool/wave rig.)

local lab = (function()
    local path = "Scripts/lab.lua"
    local src = fs.read(path)
    if not src then error("[ylem] lab module not found at " .. path) end
    return load(src, "@" .. path, "bt", _ENV)()
end)()

lab.init()

-- One "play"-mode update. Re-registering the same id on Play->Stop->Play just
-- replaces the callback, so a replay is safe (lab.init() above re-seeds the atom).
script.on_update("ylem", function()
    local m = engine and engine.get_metrics and engine.get_metrics()
    local dt = (m and m.delta_ms or 16.6) / 1000.0
    if dt < 0.0 then dt = 0.0 elseif dt > 0.1 then dt = 0.1 end
    lab.update(dt)
end, "play")

if pe_log then pe_log("[ylem] lab ready") end
