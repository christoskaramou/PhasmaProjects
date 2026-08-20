-- lan.lua — playing someone on the same network: discovery beacons, one TCP link, and the
-- line protocol that runs over it.
--
-- The rule this module exists to enforce: NOTHING that arrives on the wire is trusted. A peer
-- can send exactly four kinds of line, each matched against a fixed pattern before it means
-- anything, and a move is only ever handed to the caller as a STRING — game.lua then runs it
-- through R.legal_moves in its own position, for the side it believes is to move. The peer can
-- never set board state, only propose a move we already believe is legal. Anything else drops
-- the link. Nothing from here reaches fs.*, proc.*, or load().
--
-- The engine's `net` binding caps line length and buffer growth below this, so a peer that
-- never sends a newline is dropped before it costs us memory.

local L = {}

local PORT = 27500        -- TCP: the game itself
local BEACON_PORT = 27501 -- UDP: "there is a game here", broadcast about once a second
local BEACON_MS = 900
local STALE_MS = 4000     -- a lobby unheard from this long has gone away

-- Protocol. One version tag, and it is checked: a future build that changes the wire must not
-- half-play with an old one.
local PROTO = "PC1"
local MOVE = "^[a-h][1-8][a-h][1-8][qrbn]?$"

local role          -- "host" | "guest" | nil when offline
local ready         -- the handshake completed; the game may start
local my_id, my_name
local beacon_wait = 0
local browsing = false
local hello_sent = false
local found = {}    -- id -> {id, name, ip, age}
local note_text

local function reset(keep_browse)
    role, ready, hello_sent = nil, false, false
    beacon_wait = 0
    if not keep_browse then
        browsing = false
        found = {}
        net.discover_stop()
    end
    net.close()
end

-- Our own identity. There is no text entry in runtime_ui, so the name is generated rather than
-- typed; the id is what lets a host ignore its own beacon, which arrives from the same address
-- as everyone else's on this machine and so cannot be filtered by IP.
local function identity()
    if my_id then return end
    if script and script.random_seed then script.random_seed() end
    my_id = tostring(math.random(1000, 9999))
    my_name = "Player " .. my_id
end

function L.name()
    identity()
    return my_name
end

function L.role() return role end
function L.ready() return ready end
function L.note() return note_text end
function L.online() return role ~= nil end

local function fail(why)
    note_text = why
    reset(true)
end

-- ── lobbies ────────────────────────────────────────────────────────────────
function L.host()
    identity()
    reset()
    local ok, err = net.host(PORT)
    if not ok then
        note_text = "Could not open a lobby: " .. tostring(err)
        return false, err
    end
    -- The host also listens on the beacon port, which is what makes its own broadcast come
    -- back; found[] drops it by id.
    net.discover(BEACON_PORT)
    role, ready, beacon_wait = "host", false, 0
    note_text = "Waiting for a player to join..."
    return true
end

function L.browse(on)
    on = on and true or false
    if on == browsing then return end -- called every frame from the page; clearing found each
    identity()                        -- time would empty the list as fast as it fills
    browsing = on
    found = {}
    if browsing then
        net.discover(BEACON_PORT)
    else
        net.discover_stop()
    end
end

-- The menu drives the link from whichever page is open, so Back needs no hook of its own:
-- beacons are only drained on the browse page, and a lobby nobody joined does not outlive the
-- screen that opened it (a listener left advertising after you walk away is a door left open).
function L.on_page(page)
    L.browse(page == "lan")
    if role == "host" and not ready and page ~= "pvp" and page ~= "lan" then L.close() end
end

function L.join(ip)
    identity()
    local was_browsing = browsing
    reset(true)
    browsing = was_browsing
    local ok, err = net.join(ip, PORT)
    if not ok then
        note_text = "Could not join: " .. tostring(err)
        return false, err
    end
    role, ready = "guest", false
    note_text = "Connecting..."
    return true
end

-- Sorted so the list does not reshuffle under the cursor between frames.
function L.lobbies()
    local out = {}
    for _, l in pairs(found) do out[#out + 1] = l end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- ── the link ───────────────────────────────────────────────────────────────
function L.send_move(uci)
    if ready then net.send("M " .. uci) end
end

function L.send_resign()
    if ready then net.send("RESIGN") end
end

function L.close()
    if ready or role then net.send("BYE") end
    reset()
    note_text = nil
end

-- One frame of the link. Returns a list of events for game.lua:
--   {kind = "ready"}            both sides are on; start playing
--   {kind = "move", uci = "…"}  a PROPOSED move, still to be validated by the caller
--   {kind = "resign"}           the peer resigned
--   {kind = "closed", why = "…"}
local function drain_beacons(delta_ms)
    for _, l in pairs(found) do l.age = l.age + delta_ms end
    for _ = 1, 16 do -- bounded: a flooded network must not spin this loop forever
        local text, ip = net.poll_discover()
        if not text then break end
        -- "PC1|id|name" and nothing else. A beacon is unauthenticated by nature, so it is
        -- parsed strictly and used for exactly one thing: an address to offer the player.
        local proto, id, name = text:match("^(%u%u%d)|(%d+)|(.-)$")
        if proto == PROTO and id and id ~= my_id and #name > 0 and #name <= 32 then
            found[id] = {id = id, name = name, ip = ip, age = 0}
        end
    end
    for id, l in pairs(found) do
        if l.age > STALE_MS then found[id] = nil end
    end
end

function L.tick(delta_ms)
    delta_ms = delta_ms or 16
    local events = {}
    if browsing or role == "host" then drain_beacons(delta_ms) end
    if not role then return events end

    if role == "host" and not ready then
        beacon_wait = beacon_wait - delta_ms
        if beacon_wait <= 0 then
            beacon_wait = BEACON_MS
            net.advertise(BEACON_PORT, PROTO .. "|" .. my_id .. "|" .. my_name)
        end
        if net.accept() then
            note_text = "Player connected"
        end
    end

    local status = net.status()
    if status == "idle" then
        -- Listening sockets report idle only after the link is gone, so reaching here with a
        -- role set means we lost it.
        local why = ready and "Opponent disconnected" or "Connection lost"
        reset(true)
        note_text = why
        events[#events + 1] = {kind = "closed", why = why}
        return events
    end
    if status ~= "connected" then return events end

    if role == "guest" and not ready and not hello_sent then
        net.send(PROTO .. " " .. my_id .. " " .. my_name)
        hello_sent = true
    end

    for _ = 1, 32 do -- bounded per frame, same reason as the beacons
        local line = net.read_line()
        if not line then break end

        local kind, rest = line:match("^(%S+)%s*(.*)$")
        if kind == PROTO and role == "host" and not ready then
            -- The joiner said hello. Names are display-only and never reach a path that could
            -- act on them, but they are still bounded and stripped of anything but text.
            local peer = (rest:match("^%d+%s+(.+)$") or "Player"):sub(1, 32):gsub("[^%w%s_-]", "")
            net.send("OK " .. my_id .. " " .. my_name)
            ready = true
            note_text = "Playing " .. peer
            events[#events + 1] = {kind = "ready"}
        elseif kind == "OK" and role == "guest" and not ready then
            local peer = (rest:match("^%d+%s+(.+)$") or "Player"):sub(1, 32):gsub("[^%w%s_-]", "")
            ready = true
            note_text = "Playing " .. peer
            events[#events + 1] = {kind = "ready"}
        elseif kind == "M" and ready then
            -- A move is a candidate, not an instruction: it is a coordinate string here and
            -- stays one until game.lua finds it among the legal moves for the side to move.
            if not rest:match(MOVE) then
                fail("Opponent sent a malformed move")
                events[#events + 1] = {kind = "closed", why = note_text}
                return events
            end
            events[#events + 1] = {kind = "move", uci = rest}
        elseif kind == "RESIGN" and ready then
            events[#events + 1] = {kind = "resign"}
        elseif kind == "BYE" then
            reset(true)
            note_text = "Opponent left"
            events[#events + 1] = {kind = "closed", why = note_text}
            return events
        else
            -- Anything else at all, including a message out of order: drop the link. There is
            -- no "best effort" reading of a peer that is not speaking our protocol.
            fail("Opponent sent something unexpected")
            events[#events + 1] = {kind = "closed", why = note_text}
            return events
        end
    end
    return events
end

return L
