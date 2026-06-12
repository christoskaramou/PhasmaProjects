local Flow = {}

local function key(width, x, y)
    return y * width + x
end

local function in_bounds(map, x, y)
    return x >= 0 and x < map.width and y >= 0 and y < map.height
end

local function ensure_row(map, y)
    map.walkable[y] = map.walkable[y] or {}
    map.tile_kind[y] = map.tile_kind[y] or {}
    map.room_by_tile[y] = map.room_by_tile[y] or {}
end

local function set_tile(map, x, y, kind, room_id)
    if not in_bounds(map, x, y) then return end
    ensure_row(map, y)
    map.walkable[y][x] = true
    map.tile_kind[y][x] = kind
    if room_id then
        map.room_by_tile[y][x] = room_id
    end
end

local function stamp_rect(map, rect, kind, room_id)
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            set_tile(map, x, y, kind, room_id)
        end
    end
end

local function build_walls(map)
    local seen = {}
    local dirs = {
        { x = 1, y = 0 }, { x = -1, y = 0 }, { x = 0, y = 1 }, { x = 0, y = -1 },
        { x = 1, y = 1 }, { x = 1, y = -1 }, { x = -1, y = 1 }, { x = -1, y = -1 },
    }

    for y = 0, map.height - 1 do
        for x = 0, map.width - 1 do
            if map:is_walkable(x, y) then
                for _, dir in ipairs(dirs) do
                    local wx = x + dir.x
                    local wy = y + dir.y
                    local wall_key = key(map.width, wx, wy)
                    if in_bounds(map, wx, wy) and not map:is_walkable(wx, wy) and not seen[wall_key] then
                        seen[wall_key] = true
                        map.walls[#map.walls + 1] = { x = wx, y = wy }
                    end
                end
            end
        end
    end
end

-- Per-archetype spawn defaults. Dungeon anchors only specify id/archetype/position
-- (plus the rare per-anchor override), so this spawn tuning lives in one place
-- instead of being copy-pasted onto every anchor in every dungeon file.
local ANCHOR_DEFAULTS = {
    hollow_debtor = { spawn_rate = 3, concurrency_cap = 7, aggro_radius = 18 },
    bell_maiden   = { spawn_rate = 2, concurrency_cap = 5, aggro_radius = 22 },
    vault_knight  = { spawn_rate = 2, concurrency_cap = 5, aggro_radius = 20 },
    grave_bailiff = { spawn_rate = 1, concurrency_cap = 4, aggro_radius = 24 },
    coffer_beast  = { spawn_rate = 1, concurrency_cap = 2, aggro_radius = 20 },
    mother_tithe  = { spawn_rate = 1, concurrency_cap = 3, aggro_radius = 24 },
}

local function copy_anchor(anchor, room)
    local defaults = ANCHOR_DEFAULTS[anchor.archetype] or {}
    return {
        id = anchor.id,
        archetype = anchor.archetype,
        spawn_rate = anchor.spawn_rate or defaults.spawn_rate or 1,
        concurrency_cap = anchor.concurrency_cap or defaults.concurrency_cap or 1,
        aggro_radius = anchor.aggro_radius or defaults.aggro_radius or 16,
        room_id = room.id,
        room_name = room.name,
        position = { x = anchor.position.x, y = anchor.position.y },
    }
end

function Flow.build_map(def)
    local map = {
        id = def.id,
        title = def.title,
        width = def.width,
        height = def.height,
        tile_world = def.tile_world or 1.0,
        max_intervals = def.max_intervals,
        threat_budget_add = def.threat_budget_add or 0,
        camera_center = def.camera_center,
        hero_start = def.hero_start,
        hero_patrol = def.hero_patrol,
        rooms = def.rooms or {},
        corridors = def.corridors or {},
        walkable = {},
        tile_kind = {},
        room_by_tile = {},
        anchors = {},
        anchors_by_id = {},
        walls = {},
    }

    function map:is_walkable(x, y)
        return in_bounds(self, x, y) and self.walkable[y] and self.walkable[y][x] == true
    end

    function map:tile_kind_at(x, y)
        return self.tile_kind[y] and self.tile_kind[y][x] or "wall"
    end

    function map:room_at(x, y)
        return self.room_by_tile[y] and self.room_by_tile[y][x] or nil
    end

    for _, room in ipairs(map.rooms) do
        stamp_rect(map, room.rect, "floor", room.id)
        for _, anchor in ipairs(room.anchors or {}) do
            local copied = copy_anchor(anchor, room)
            map.anchors[#map.anchors + 1] = copied
            map.anchors_by_id[copied.id] = copied
        end
    end

    for _, corridor in ipairs(map.corridors) do
        stamp_rect(map, corridor.rect, "corridor", nil)
    end

    build_walls(map)
    return map
end

function Flow.world_from_tile(map, x, y)
    local scale = map and map.tile_world or 1.0
    return x * scale, y * scale
end

function Flow.tile_from_world(_map, x, z)
    return math.floor((x or 0.0) + 0.5), math.floor((z or 0.0) + 0.5)
end

function Flow.nearest_walkable(map, tile)
    if map:is_walkable(tile.x, tile.y) then return { x = tile.x, y = tile.y } end

    for radius = 1, math.max(map.width, map.height) do
        local min_x = tile.x - radius
        local max_x = tile.x + radius
        local min_y = tile.y - radius
        local max_y = tile.y + radius

        for x = min_x, max_x do
            if map:is_walkable(x, min_y) then
                return { x = x, y = min_y }
            end
            if map:is_walkable(x, max_y) then
                return { x = x, y = max_y }
            end
        end

        for y = min_y + 1, max_y - 1 do
            if map:is_walkable(min_x, y) then
                return { x = min_x, y = y }
            end
            if map:is_walkable(max_x, y) then
                return { x = max_x, y = y }
            end
        end
    end
    return { x = 0, y = 0 }
end

-- Allocation-free BFS flow field.
--
-- The previous version minted a fresh `{x,y}` table for every walkable tile
-- (one for the BFS queue entry, one for `field.next`) plus two hash tables, on
-- EVERY recompute. At a few thousand tiles several times a second that both
-- cost CPU and flooded the Lua GC, which showed up as periodic frame spikes.
--
-- Now every tile is referenced by its integer `key` (y*width + x). The queue,
-- distance, next and visited maps are persistent scratch tables carried on the
-- `field` and reused across recomputes — a per-call generation stamp (`gen`)
-- stands in for clearing them, so a recompute allocates essentially nothing.
function Flow.compute(map, target, field)
    target = Flow.nearest_walkable(map, target or map.hero_start or { x = 0, y = 0 })

    local width = map.width

    field = field or {}
    field.map = map
    field.target = target
    field.distance = field.distance or {}
    field.next = field.next or {}
    field.queue = field.queue or {}
    field.seen = field.seen or {}
    field.gen = (field.gen or 0) + 1
    field.reachable = 0

    local distance = field.distance
    local nextk = field.next
    local queue = field.queue
    local seen = field.seen
    local gen = field.gen

    local start = target.y * width + target.x
    distance[start] = 0
    seen[start] = gen
    nextk[start] = nil -- target tile has no parent; clear any stale prior-gen entry
    queue[1] = start
    field.start_key = start
    local head, tail = 1, 1

    local function visit(nx, ny, ckey, nd)
        if not map:is_walkable(nx, ny) then return end
        local nkey = ny * width + nx
        if seen[nkey] == gen then return end
        seen[nkey] = gen
        distance[nkey] = nd
        nextk[nkey] = ckey
        tail = tail + 1
        queue[tail] = nkey
    end

    while head <= tail do
        local ckey = queue[head]
        head = head + 1
        field.reachable = field.reachable + 1
        local cx = ckey % width
        local cy = (ckey - cx) / width
        local nd = distance[ckey] + 1
        visit(cx + 1, cy, ckey, nd)
        visit(cx - 1, cy, ckey, nd)
        visit(cx, cy + 1, ckey, nd)
        visit(cx, cy - 1, ckey, nd)
    end

    return field
end

function Flow.sample(field, x, z)
    if not field or not field.map then return 0.0, 0.0, nil end

    local map = field.map
    local width = map.width
    local tx, ty = Flow.tile_from_world(map, x, z)
    local tile_key = ty * width + tx

    -- `next` holds the parent tile's integer key (the step back toward the
    -- target). Only trust it when this tile was reached in the current field
    -- generation; otherwise (unreachable / off-grid) head straight at the target.
    local ntx, nty
    local nkey = field.next[tile_key]
    if nkey ~= nil and field.seen[tile_key] == field.gen then
        ntx = nkey % width
        nty = (nkey - ntx) / width
    else
        ntx, nty = field.target.x, field.target.y
    end

    local target_x, target_z = Flow.world_from_tile(map, ntx, nty)
    local dx = target_x - x
    local dz = target_z - z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist < 0.001 then return 0.0, 0.0, nil end
    return dx / dist, dz / dist, nil
end

function Flow.distance_to_target(field, x, z)
    if not field or not field.map then return nil end
    local tx, ty = Flow.tile_from_world(field.map, x, z)
    local k = ty * field.map.width + tx
    -- distance is persistent scratch reused across generations; a value is only
    -- meaningful if this tile was visited in the current field generation.
    if field.seen and field.seen[k] ~= field.gen then return nil end
    return field.distance[k]
end

return Flow
