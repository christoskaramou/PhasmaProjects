-- pgn.lua — build and parse PGN. Pure, no engine globals.
--
-- Parse is the minimum a "Continue last game" / Replay button needs: tags, a main-line
-- SAN list, and optional [%emt] think-times. Other comments, NAGs and variations are
-- stripped, not interpreted.

local P = {}

local PGN_PATH = "Save/last_game.pgn"
local PGN_LEGACY = "Games/last_game.pgn"

function P.path() return PGN_PATH end

function P.read_last()
    return fs.read(PGN_PATH) or fs.read(PGN_LEGACY)
end

-- Movetext tokens wrapped at <= 80 columns per the PGN export format.
local function wrap(tokens)
    local lines, line = {}, ""
    for _, t in ipairs(tokens) do
        if line == "" then
            line = t
        elseif #line + 1 + #t <= 80 then
            line = line .. " " .. t
        else
            lines[#lines + 1] = line
            line = t
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

-- "h:mm:ss.t" — what [%emt] wants. Tenths are enough for replay pacing.
function P.fmt_emt(ms)
    ms = math.max(0, math.floor(ms or 0))
    local t = ms / 1000
    local h = math.floor(t / 3600)
    t = t - h * 3600
    local m = math.floor(t / 60)
    local s = t - m * 60
    return string.format("%d:%02d:%04.1f", h, m, s)
end

function P.parse_emt(s)
    if not s or s == "" then return nil end
    s = s:match("^%s*(.-)%s*$") or s
    local h, m, sec = s:match("^(%d+):(%d+):([%d%.]+)$")
    if h then return math.floor((tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec)) * 1000) end
    local m2, sec2 = s:match("^(%d+):([%d%.]+)$")
    if m2 then return math.floor((tonumber(m2) * 60 + tonumber(sec2)) * 1000) end
    local sec3 = tonumber(s)
    if sec3 then return math.floor(sec3 * 1000) end
end

function P.build(opts)
    opts = opts or {}
    local moves = opts.moves or {}
    local emts = opts.emts or {}
    local result = opts.result or "*"
    local tags = {
        {"Event", opts.event or "PhasmaChess casual game"},
        {"Site", "PhasmaEngine"},
        {"Date", opts.date or "????.??.??"},
        {"Round", "-"},
        {"White", opts.white or "?"},
        {"Black", opts.black or "?"},
        {"Result", result},
    }
    local out = {}
    for _, t in ipairs(tags) do
        out[#out + 1] = string.format('[%s "%s"]', t[1], t[2])
    end
    out[#out + 1] = ""
    local tokens = {}
    for i, san in ipairs(moves) do
        if i % 2 == 1 then tokens[#tokens + 1] = tostring(math.floor((i + 1) / 2)) .. "." end
        tokens[#tokens + 1] = san
        if emts[i] then
            tokens[#tokens + 1] = string.format("{[%%emt %s]}", P.fmt_emt(emts[i]))
        end
    end
    tokens[#tokens + 1] = result
    out[#out + 1] = wrap(tokens)
    return table.concat(out, "\n") .. "\n"
end

local function strip_balanced(s, open_ch, close_ch)
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == open_ch then
            local depth = 1
            i = i + 1
            while i <= n and depth > 0 do
                local d = s:sub(i, i)
                if d == open_ch then depth = depth + 1
                elseif d == close_ch then depth = depth - 1 end
                i = i + 1
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

function P.parse(text)
    if not text or text == "" then return nil, "empty" end
    local tags = {}
    local body = text:gsub("\r\n", "\n")
    body = body:gsub("%[(%S+)%s+\"(.-)\"%s*%]", function(k, v)
        tags[k] = v
        return " "
    end)
    -- Pull [%emt] into an integer sidecar token before `1.` number stripping, which
    -- would otherwise eat `01.` inside `0:00:01.5`.
    body = body:gsub("{%s*%[%%emt%s+([^%]]+)%]%s*}", function(t)
        return " __EMT_" .. tostring(P.parse_emt(t) or 0) .. " "
    end)
    body = strip_balanced(body, "{", "}")
    body = strip_balanced(body, "(", ")")
    body = body:gsub("%$%d+", " ")
    body = body:gsub("%d+%.%.%.", " ")
    body = body:gsub("%d+%.", " ")
    local result = tags.Result or "*"
    body = body:gsub("1%-0", function() result = "1-0" return " " end)
    body = body:gsub("0%-1", function() result = "0-1" return " " end)
    body = body:gsub("1/2%-1/2", function() result = "1/2-1/2" return " " end)
    body = body:gsub("%*", " ")
    local moves, emts = {}, {}
    for tok in body:gmatch("%S+") do
        local emt = tok:match("^__EMT_(%d+)$")
        if emt then
            if #moves > 0 then emts[#moves] = tonumber(emt) end
        else
            tok = tok:gsub("%.+$", "")
            if tok ~= "" and tok:sub(1, 1) ~= "$" then
                moves[#moves + 1] = tok
            end
        end
    end
    tags.Result = result
    return {tags = tags, moves = moves, emts = emts, result = result}
end

return P
