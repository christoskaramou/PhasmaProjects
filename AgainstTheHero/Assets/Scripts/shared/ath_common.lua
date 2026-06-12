local Common = {}

function Common.script_env(env)
    local parent = env or _ENV
    return setmetatable({ ATH_COMMON = Common }, {
        __index = parent,
        __newindex = parent,
    })
end

function Common.load_script(path, label, env, opts)
    opts = opts or {}
    local source = fs and fs.read and fs.read(path) or nil
    if not source then
        if opts.optional then return nil end
        error("Against The Hero: missing " .. tostring(label or "script") .. " at " .. tostring(path))
    end

    local parent_env = env or _ENV
    local chunk_env = Common.script_env(parent_env)
    local chunk, err = load(source, "@" .. tostring(assets_path or "") .. path, "t", chunk_env)
    if not chunk then
        if opts.optional then return nil, err end
        error(err)
    end

    local function propagate_engine_metadata()
        if parent_env and chunk_env.__hooks then parent_env.__hooks = chunk_env.__hooks end
        if parent_env and chunk_env.__exposed then parent_env.__exposed = chunk_env.__exposed end
    end

    if opts.protected then
        local ok, result = pcall(chunk)
        if not ok then return nil, result end
        propagate_engine_metadata()
        return result
    end
    local result = chunk()
    propagate_engine_metadata()
    return result
end

function Common.getenv(name, fallback)
    if os and os.getenv then
        local value = os.getenv(name)
        if value and value ~= "" then return value end
    end
    return fallback
end

function Common.getenv_number(name, fallback)
    local value = tonumber(Common.getenv(name, nil))
    if value ~= nil then return value end
    return fallback
end

function Common.env_enabled(name, fallback)
    local default = fallback == false and "0" or "1"
    local value = string.lower(tostring(Common.getenv(name, default)))
    return value ~= "0" and value ~= "false" and value ~= "off" and value ~= "no"
end

function Common.with_trailing_slash(path)
    path = tostring(path or "")
    if path == "" or path:sub(-1) == "/" or path:sub(-1) == "\\" then return path end
    return path .. "/"
end

function Common.session_id()
    local wall_time = os and os.time and os.time() or 0
    local marker = tostring({}):gsub("%W", "")
    return tostring(wall_time) .. "_" .. marker
end

function Common.clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function Common.copy_list(list)
    local out = {}
    for _, value in ipairs(list or {}) do
        out[#out + 1] = value
    end
    return out
end

function Common.append_capped(list, value, max_count)
    list[#list + 1] = value
    while #list > (max_count or #list) do
        table.remove(list, 1)
    end
end

function Common.merge_number_fields(target, source, excluded)
    excluded = excluded or {}
    for key, value in pairs(source or {}) do
        if type(value) == "number" and not excluded[key] then
            target[key] = (target[key] or 0.0) + value
        end
    end
    return target
end

local function json_escape(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    return value
end

local function is_array(value)
    local count = 0
    local max_index = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        if key > max_index then max_index = key end
    end
    return max_index == count
end

function Common.json_encode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then return tostring(value) end
    if kind == "string" then return "\"" .. json_escape(value) .. "\"" end
    if kind ~= "table" then return "\"" .. json_escape(value) .. "\"" end

    local parts = {}
    if is_array(value) then
        for i = 1, #value do
            parts[#parts + 1] = Common.json_encode(value[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    for key, entry in pairs(value) do
        parts[#parts + 1] = "\"" .. json_escape(key) .. "\":" .. Common.json_encode(entry)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

function Common.json_decode(text)
    text = tostring(text or "")
    local index = 1
    local length = #text

    local function fail(message)
        return nil, message .. " at byte " .. tostring(index)
    end

    local function peek()
        return text:sub(index, index)
    end

    local function skip_ws()
        while index <= length do
            local c = peek()
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then break end
            index = index + 1
        end
    end

    local parse_value

    local function parse_string()
        if peek() ~= "\"" then return fail("expected string") end
        index = index + 1
        local out = {}
        while index <= length do
            local c = peek()
            index = index + 1
            if c == "\"" then return table.concat(out) end
            if c == "\\" then
                local esc = peek()
                index = index + 1
                if esc == "\"" or esc == "\\" or esc == "/" then
                    out[#out + 1] = esc
                elseif esc == "b" then
                    out[#out + 1] = "\b"
                elseif esc == "f" then
                    out[#out + 1] = "\f"
                elseif esc == "n" then
                    out[#out + 1] = "\n"
                elseif esc == "r" then
                    out[#out + 1] = "\r"
                elseif esc == "t" then
                    out[#out + 1] = "\t"
                elseif esc == "u" then
                    local hex = text:sub(index, index + 3)
                    index = index + 4
                    local codepoint = tonumber(hex, 16)
                    out[#out + 1] = codepoint and utf8 and utf8.char and utf8.char(codepoint) or "?"
                else
                    return fail("invalid string escape")
                end
            else
                out[#out + 1] = c
            end
        end
        return fail("unterminated string")
    end

    local function parse_number()
        local start = index
        if peek() == "-" then index = index + 1 end
        while index <= length and peek():match("%d") do index = index + 1 end
        if peek() == "." then
            index = index + 1
            while index <= length and peek():match("%d") do index = index + 1 end
        end
        local c = peek()
        if c == "e" or c == "E" then
            index = index + 1
            c = peek()
            if c == "+" or c == "-" then index = index + 1 end
            while index <= length and peek():match("%d") do index = index + 1 end
        end
        local value = tonumber(text:sub(start, index - 1))
        if value == nil then return fail("invalid number") end
        return value
    end

    local function parse_array()
        index = index + 1
        local out = {}
        skip_ws()
        if peek() == "]" then
            index = index + 1
            return out
        end
        while index <= length do
            local value, err = parse_value()
            if err then return nil, err end
            out[#out + 1] = value
            skip_ws()
            local c = peek()
            if c == "]" then
                index = index + 1
                return out
            end
            if c ~= "," then return fail("expected ',' or ']'") end
            index = index + 1
        end
        return fail("unterminated array")
    end

    local function parse_object()
        index = index + 1
        local out = {}
        skip_ws()
        if peek() == "}" then
            index = index + 1
            return out
        end
        while index <= length do
            skip_ws()
            local key, key_err = parse_string()
            if key_err then return nil, key_err end
            skip_ws()
            if peek() ~= ":" then return fail("expected ':'") end
            index = index + 1
            local value, value_err = parse_value()
            if value_err then return nil, value_err end
            out[key] = value
            skip_ws()
            local c = peek()
            if c == "}" then
                index = index + 1
                return out
            end
            if c ~= "," then return fail("expected ',' or '}'") end
            index = index + 1
        end
        return fail("unterminated object")
    end

    function parse_value()
        skip_ws()
        local c = peek()
        if c == "\"" then return parse_string() end
        if c == "{" then return parse_object() end
        if c == "[" then return parse_array() end
        if c == "-" or c:match("%d") then return parse_number() end
        if text:sub(index, index + 3) == "true" then
            index = index + 4
            return true
        end
        if text:sub(index, index + 4) == "false" then
            index = index + 5
            return false
        end
        if text:sub(index, index + 3) == "null" then
            index = index + 4
            return nil
        end
        return fail("unexpected JSON value")
    end

    local value, err = parse_value()
    if err then return nil, err end
    skip_ws()
    if index <= length then return nil, "trailing JSON data at byte " .. tostring(index) end
    return value
end

return Common
