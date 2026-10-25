local function read(path)
    local f = assert(io.open(path, "rb"), "missing " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

local function fail(msg)
    io.stderr:write(msg .. "\n")
    os.exit(1)
end

local function box(cx, cy, cz, sx, sy, sz)
    return {
        x0 = cx - sx * 0.5, x1 = cx + sx * 0.5,
        y0 = cy - sy * 0.5, y1 = cy + sy * 0.5,
        z0 = cz - sz * 0.5, z1 = cz + sz * 0.5,
    }
end

local function overlap(a, b)
    return a.x0 < b.x1 and a.x1 > b.x0
        and a.y0 < b.y1 and a.y1 > b.y0
        and a.z0 < b.z1 and a.z1 > b.z0
end

local function same_face(a, b)
    local function near(u, v) return math.abs(u - v) < 1e-4 end
    if near(a.z1, b.z1) and a.x0 < b.x1 and a.x1 > b.x0 and a.y0 < b.y1 and a.y1 > b.y0 then
        return true
    end
    if near(a.x0, b.x0) and a.y0 < b.y1 and a.y1 > b.y0 and a.z0 < b.z1 and a.z1 > b.z0 then
        return true
    end
    return false
end

-- Posts, lintel, floor. Posts are thinner in z and inset in x, so corners do not share a face.
local post_l = box(-25, 13.05, -0.2, 1.92, 26.5, 5.1)
local post_r = box(25, 13.05, -0.2, 1.92, 26.5, 5.1)
local lintel = box(0, 27, -0.2, 52, 2, 5.4)
local floor = box(0, -1.5, -0.2, 52, 3, 5.4)

for _, post in ipairs({ post_l, post_r }) do
    if same_face(post, lintel) or same_face(post, floor) then
        fail("frame corner still shares a face")
    end
end

local old_l = box(-25, 12.2, -0.2, 2, 30.4, 5.4)
local old_r = box(25, 12.2, -0.2, 2, 30.4, 5.4)
if not (same_face(old_l, lintel) and same_face(old_r, floor)) then
    fail("old corner overlap is gone from the regression, so the test no longer matches the bug")
end

for _, path in ipairs({
    "Arcade/PangRemix/Assets/Scripts/game.lua",
    "Arcade/PangRemix/tools/src/03_stage.lua",
}) do
    local src = read(path)
    if src:find("fr(-25, 12.2, 2, 30.4)", 1, true) then
        fail(path .. " still builds posts through the floor and the lintel")
    end
    if not src:find("fr(-25, 13.05, 1.92, 26.5, -0.2, 5.1)", 1, true) then
        fail(path .. " is missing the inset corner posts")
    end
end

print("pang frame: corner faces do not overlap")
