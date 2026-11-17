-- Undertow bot: plays the rules by looking ahead on copies of the state (pure Lua, deterministic).
-- When it hangs on a hook it tries releasing at each moment of the forward swing (every STRIDE steps) with a few
-- hooking habits (press when the next hook is within LW of the float, or at its closest approach), simulating each until
-- the float has swung through the bottom of the next hook. It keeps the plan that arrives with the most energy (a clean
-- arrival scores a little more); when a moored boat lies after that hook, the best plan that still leaves a release over
-- the boat. If nothing works it hangs on for another swing and plans again.
return function(D, R)
local B = {}
local STRIDE, LW, LIMIT = 4, { 3.0, 4.0, 7.5 }, 420
local sqrt = math.sqrt

local function energy(c) return D.RULES.G * c.z + 0.5 * (c.vx * c.vx + c.vz * c.vz) end

-- Hooking habit after the release: press when a hook ahead is within lw, or when it stops getting nearer.
local function hook_policy(st, c, lw)
    local it, d = R.find_hook(c)
    if not it then st.prev = nil; return false end
    local press = d <= lw or (st.prev and d > st.prev + 1e-6)
    st.prev = d
    return press
end

-- One decision for the planned hook p = { hook, rel, lw, st }: used by the look-ahead and by play alike, so a plan
-- plays out exactly as simulated.
local function decide(p, c)
    if c.hook == p.hook then
        if c.steps < p.rel then return true end
        hook_policy(p.st, c, p.lw)       -- the habit's memory runs from the release step on
        return false
    elseif c.hook then
        return true
    end
    return hook_policy(p.st, c, p.lw)
end

-- Simulate a plan; on success also return the state at the moment it hooked the next hook.
local function rollout(s, rel, lw)
    local c = R.clone(s)
    local h0 = c.hook
    local p = { hook = h0, rel = rel, lw = lw, st = {} }
    local at
    for _ = 1, LIMIT do
        R.step(c, decide(p, c))
        if c.mode == "dead" then return nil, c.x end
        if c.hook and c.hook ~= h0 and not at then at = R.clone(c) end
        -- through the bottom of the next hook on a TAUT chain (while slack th / om are the last hook's), and alive
        -- to the end of that forward swing (a long reeling chain can carry the float into what lies past the hook)
        if c.hook and c.hook ~= h0 and c.hook.x > h0.x and not c.slack and c.th >= 0 and c.om > 0 then
            local v = energy(c) + (c.touched and 0 or 3)
            for _ = 1, 360 do      -- up to 3 s: an over-the-top swing goes slack and can fall onto the lamp arm
                R.step(c, true)
                if c.mode == "dead" then return nil, c.x end
                if not c.slack and c.om <= 0 then break end
            end
            return v, c.x, at
        end
    end
    return nil, c.x
end

-- Is an in-plane boat between this hook and the next one? (Over a hull the next flight is 12.7-14.3 long; only some
-- arrivals on this hook can make it, so the plan that reaches this hook must leave one.)
local function boat_after(c, h)
    local pl = c.course.plane
    for i = c.course:plane_from(h.x + 1e-6), #pl do
        local it = pl[i]
        if it.x > h.x + 20 then return false end
        if it.kind == "boat" and it.p.inplane then return true end
        if R.has_hook(it) then return false end
    end
    return false
end

B._rollout = rollout
function B.new() return { plan = nil } end

-- The step at which the current forward swing turns back (or a short horizon).
local function turn_of(s)
    local c = R.clone(s)
    local prev_om = c.om
    for _ = 1, 240 do
        R.step(c, true)
        if c.mode == "dead" or c.hook ~= s.hook then return c.steps end
        if prev_om > 0 and c.om <= 0 then return c.steps end
        prev_om = c.om
    end
    return s.steps + 240
end

-- From the moment a plan hooked h: hold to the first forward swing (as play does), then is there a release that gets
-- past the next hook? (coarse: every 2 * STRIDE steps, the far hooking habit first)
local function can_continue(at)
    local c = R.clone(at)
    for _ = 1, 360 do
        if c.mode == "dead" then return false end
        if c.om > 0 or c.slack or R.looping(c) then break end
        R.step(c, true)
    end
    if c.mode == "dead" or not c.hook then return false end
    for rel = c.steps + 1, turn_of(c), 2 * STRIDE do
        for k = #LW, 1, -1 do
            if rollout(c, rel, LW[k]) then return true end
        end
    end
    return false
end

-- Does holding on for this swing and the next keep the float alive (a fast swing can loop into its own lamp arm)?
local function safe_to_hold(s)
    local c = R.clone(s)
    for _ = 1, 360 do
        R.step(c, true)
        if c.mode == "dead" then return false end
    end
    return true
end

B._can_continue, B._boat_after = can_continue, boat_after

local function make_plan(b, s)
    local turn = turn_of(s)
    local cands = {}
    for rel = s.steps + 1, turn, STRIDE do
        for _, lw in ipairs(LW) do
            local v, _, at = rollout(s, rel, lw)
            if v then cands[#cands + 1] = { rel = rel, lw = lw, v = v, at = at } end
        end
    end
    table.sort(cands, function(a, b2) return a.v > b2.v end)
    local best, bestv
    if cands[1] then best, bestv = cands[1], cands[1].v end
    -- a boat after the next hook: take the best plan that leaves a crossing (if none does, the best anyway)
    -- a boat after the next hook: take the best plan that leaves a release over the boat; if none does, hang on and
    -- plan again on the next swing (the pump settles the swing at 75 deg, and from there a far hook on the next
    -- buoy reels the chain in and gives the speed the boat needs)
    if best and best.at and boat_after(best.at, best.at.hook) then
        local found
        for i = 1, math.min(#cands, 12) do
            if can_continue(cands[i].at) then found = cands[i]; break end
        end
        b.boat_waits = (b.boat_waits or 0) + (found and 0 or 1)
        if found or b.boat_waits > 6 or not safe_to_hold(s) then best, bestv = found or best, (found or best).v else best = nil end
    else
        b.boat_waits = 0
    end
    b.plan = best and { hook = s.hook, rel = best.rel, lw = best.lw, st = {} } or { hook = s.hook, rel = turn + 1, wait = true }
    b.planned = (b.planned or 0) + 1
    if not best then b.waits = (b.waits or 0) + 1 end
end

-- hold for this step
function B.input(b, s)
    local p = b.plan
    if s.hook and (not p or p.hook ~= s.hook or (p.wait and s.steps >= p.rel)) then
        -- plan on a forward swing or a loop (on a back swing, keep holding until it turns)
        if not (s.om > 0 or s.slack or R.looping(s)) then return true end
        make_plan(b, s)
        p = b.plan
    end
    if not p then return false end
    if p.wait and s.hook == p.hook then return true end
    return decide(p, s)
end

return B
end
