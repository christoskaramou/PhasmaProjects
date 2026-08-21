-- lan.lua — playing someone else, on this network or across the internet: discovery beacons,
-- one link, and the line protocol that runs over it.
--
-- Two ways to meet, one game protocol. On a LAN the host listens and beacons, and the guest
-- connects straight to it. Over the internet both sides instead dial OUT to a relay we run
-- (see relay/), which pairs them by a six-digit code and then pipes bytes: no player opens a
-- port and neither learns the other's address. That link is TLS with the relay's public key
-- PINNED (relay_config.lua) — anything else answering on that address is refused.
--
-- The rule this module exists to enforce: NOTHING that arrives on the wire is trusted. A peer
-- can send exactly six kinds of line, each matched against a fixed pattern before it means
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
local PROTO = "PC2" -- bumped with PING: an old build drops unknown verbs, so it must fail at
                    -- hello rather than mid-game
local MOVE = "^[a-h][1-8][a-h][1-8][qrbn]?$"

-- The verbs that are pure negotiation, mapped to the event the game reacts to. A table rather
-- than another elseif chain: every one of them is the same shape.
local OFFERS = {
    DRAW = "draw_offer", DRAW_OK = "draw_accept", DRAW_NO = "draw_decline",
    TAKEBACK = "takeback_offer", TAKEBACK_OK = "takeback_accept", TAKEBACK_NO = "takeback_decline",
}

local RELAY         -- {host, port, pin} from relay_config.lua, or nil
local via_relay     -- this link goes through the relay rather than the LAN
local relay_stage   -- "dial" | "wait" while the relay is still pairing us; nil once it is a pipe
local code          -- the six-digit lobby code: ours when hosting, theirs when joining
local ping_wait = 0

local PING_MS = 20000 -- a game can think for minutes, and a NAT will drop an idle TCP link long
                      -- before that; this is what keeps the path open

local role          -- "host" | "guest" | nil when offline
local ready         -- the handshake completed; the game may start
local my_id, my_name
local peer_name
local beacon_wait = 0
local browsing = false
local hello_sent = false
local found = {}    -- id -> {id, name, ip, age}
local note_text

local function reset(keep_browse)
    role, ready, hello_sent = nil, false, false
    via_relay, relay_stage, code = nil, nil, nil
    beacon_wait, ping_wait = 0, PING_MS
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

-- The relay is configuration, not code: the game is handed it once at load and never asks
-- where it came from.
function L.configure(cfg) RELAY = cfg end
function L.relay_ready() return RELAY ~= nil and RELAY.host ~= "" and RELAY.pin ~= "" end
function L.code() return code end
function L.role() return role end
function L.ready() return ready end
function L.note() return note_text end
function L.peer_name() return peer_name end
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
    if role == "host" and not ready and page ~= "pvp" and page ~= "lan" and page ~= "code" then
        L.close()
    end
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

-- ── the relay ──────────────────────────────────────────────────────────────
-- Dial out, pinned. Nothing is sent until net.status() says connected, which for a pinned link
-- means the TLS handshake finished AND the server's key matched.
local function dial_relay()
    if not L.relay_ready() then
        note_text = "No relay configured yet"
        return false
    end
    identity()
    reset()
    local ok, err = net.join(RELAY.host, RELAY.port or 27600, {pin = RELAY.pin})
    if not ok then
        note_text = "Could not reach the relay: " .. tostring(err)
        return false
    end
    return true
end

function L.host_online()
    if not dial_relay() then return false end
    role, via_relay, relay_stage = "host", true, "dial"
    note_text = "Contacting the relay..."
    return true
end

function L.join_online(entered)
    if type(entered) ~= "string" or not entered:match("^%d%d%d%d%d%d$") then
        note_text = "A code is six digits"
        return false
    end
    if not dial_relay() then return false end
    role, via_relay, relay_stage, code = "guest", true, "dial", entered
    note_text = "Contacting the relay..."
    return true
end

-- ── the link ───────────────────────────────────────────────────────────────
function L.send_move(uci)
    if ready then net.send("M " .. uci) end
end

function L.send_resign()
    if ready then net.send("RESIGN") end
end

-- A rematch is the one thing neither side can decide alone: restarting locally would leave the
-- opponent sitting in a finished game with a live socket. So it is offered, and only the
-- acceptance starts it.
-- Draw, takeback and rematch are all "ask, then be answered" -- none may be applied
-- unilaterally, because the other board would silently disagree with ours.
function L.offer(what)
    if ready then net.send(what) end
end

function L.send_rematch()
    if ready then net.send("REMATCH") end
end

function L.send_rematch_ok()
    if ready then net.send("REMATCH_OK") end
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
    if browsing or (role == "host" and not via_relay) then drain_beacons(delta_ms) end
    if not role then return events end

    if role == "host" and not ready and not via_relay then
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
        -- role set means we lost it. The last words first, though: the relay's refusal arrives
        -- immediately before it hangs up, and "no game with that code" is the useful message.
        local why = ready and "Opponent disconnected" or "Connection lost"
        for _ = 1, 8 do
            local line = net.read_line()
            if not line then break end
            local kind, rest = line:match("^(%S+)%s*(.*)$")
            if kind == "ERR" then
                why = ({["no-such-game"] = "No game with that code",
                        ["bad-code"] = "No game with that code",
                        ["slow-down"] = "Too many tries - wait a minute",
                        ["expired"] = "That game timed out",
                        ["busy"] = "The relay is full"})[rest] or ("Relay refused us: " .. rest)
            elseif kind == "BYE" then
                why = "Opponent left"
            end
        end
        reset(true)
        note_text = why
        events[#events + 1] = {kind = "closed", why = why}
        return events
    end
    if status ~= "connected" then return events end

    if via_relay and relay_stage == "dial" then
        -- Connected to the relay (and, because the link is pinned, to the RIGHT relay). Ask it
        -- for a code, or hand it the one we were given.
        net.send((role == "host") and ("HOST " .. my_name) or ("JOIN " .. code .. " " .. my_name))
        relay_stage = "wait"
        note_text = (role == "host") and "Asking for a code..." or "Looking for that game..."
    end

    if role == "guest" and not ready and not hello_sent and not relay_stage then
        net.send(PROTO .. " " .. my_id .. " " .. my_name)
        hello_sent = true
    end

    for _ = 1, 32 do -- bounded per frame, same reason as the beacons
        local line = net.read_line()
        if not line then break end

        local kind, rest = line:match("^(%S+)%s*(.*)$")
        if relay_stage then
            -- Three verbs, and only from the relay we pinned. Anything else here is not a relay
            -- we recognise, so the link goes.
            if kind == "CODE" and role == "host" and rest:match("^%d%d%d%d%d%d$") then
                code = rest
                note_text = "Code " .. code .. " - waiting for your friend"
            elseif kind == "PAIRED" then
                relay_stage = nil
                note_text = "Connected"
                if role == "guest" then
                    net.send(PROTO .. " " .. my_id .. " " .. my_name)
                    hello_sent = true
                end
            elseif kind == "ERR" then
                fail(({["no-such-game"] = "No game with that code",
                       ["bad-code"] = "No game with that code",
                       ["slow-down"] = "Too many tries - wait a minute",
                       ["expired"] = "That game timed out",
                       ["busy"] = "The relay is full"})[rest] or ("Relay refused us: " .. rest))
                events[#events + 1] = {kind = "closed", why = note_text}
                return events
            else
                fail("The relay said something unexpected")
                events[#events + 1] = {kind = "closed", why = note_text}
                return events
            end
        elseif kind == "PING" then
            -- Keepalive. Nothing to do: arriving at all is the whole point.
        elseif kind == PROTO and role == "host" and not ready then
            -- The joiner said hello. Names are display-only and never reach a path that could
            -- act on them, but they are still bounded and stripped of anything but text.
            local peer = (rest:match("^%d+%s+(.+)$") or "Player"):sub(1, 32):gsub("[^%w%s_-]", "")
            net.send("OK " .. my_id .. " " .. my_name)
            ready, peer_name = true, peer
            note_text = "Playing " .. peer
            events[#events + 1] = {kind = "ready"}
        elseif kind == "OK" and role == "guest" and not ready then
            local peer = (rest:match("^%d+%s+(.+)$") or "Player"):sub(1, 32):gsub("[^%w%s_-]", "")
            ready, peer_name = true, peer
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
        elseif kind == "REMATCH" and ready then
            events[#events + 1] = {kind = "rematch_offer"}
        elseif kind == "REMATCH_OK" and ready then
            events[#events + 1] = {kind = "rematch_start"}
        elseif OFFERS[kind] and ready then
            events[#events + 1] = {kind = OFFERS[kind]}
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

    -- Two players thinking is two players sending nothing, and a NAT or a relay counts that as
    -- a dead link long before the game does.
    if ready then
        ping_wait = ping_wait - delta_ms
        if ping_wait <= 0 then
            ping_wait = PING_MS
            net.send("PING")
        end
    end
    return events
end

return L
