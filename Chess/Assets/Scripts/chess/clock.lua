-- clock.lua — chess clock math. Pure module: the caller integrates frame deltas
-- (engine.get_metrics().delta_ms) and calls tick for the side to move.

local K = {}

function K.new(minutes, increment_seconds)
    local ms = minutes * 60 * 1000
    return {W = ms, B = ms, inc = increment_seconds * 1000, flagged = nil}
end

-- Burns delta_ms off side's time. Returns the side whose flag fell on THIS tick
-- (time clamped to 0), else nil. Fires at most once per game.
function K.tick(k, side, delta_ms)
    if k.flagged then return nil end
    k[side] = k[side] - delta_ms
    if k[side] <= 0 then
        k[side] = 0
        k.flagged = side
        return side
    end
    return nil
end

function K.add_increment(k, side)
    k[side] = k[side] + k.inc
end

function K.remaining(k, side)
    return k[side]
end

-- "M:SS", or "0:SS.t" with tenths under 20 s.
function K.fmt(ms)
    if ms < 0 then ms = 0 end
    if ms < 20000 then
        local tenths = math.floor(ms / 100)
        return string.format("0:%02d.%d", math.floor(tenths / 10), tenths % 10)
    end
    local s = math.floor(ms / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

return K
