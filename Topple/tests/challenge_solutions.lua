-- One way to win each House Challenge, by challenge id (for view_smoke and live checks): each takes (board, F) and
-- places it. Built from tests/solutions/<room>.lua, which list them in the order of Scripts/challenges/<room>.lua.
local out = {}
for _, room in ipairs({ "hall", "living", "kitchen", "dining", "kids", "bath", "study", "attic" }) do
    local okd, defs = pcall(dofile, "Assets/Scripts/challenges/" .. room .. ".lua")
    local oks, sols = pcall(dofile, "tests/solutions/" .. room .. ".lua")
    if okd and oks and type(defs) == "table" and type(sols) == "table" then
        for i, def in ipairs(defs) do
            local s = sols[i]
            out[def.id] = type(s) == "function" and s or (type(s) == "table" and s.solve) or nil
        end
    end
end
return out
