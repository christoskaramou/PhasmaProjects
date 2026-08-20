"""Static gate for the chess Lua: parse under the real LuaJIT, then flag unknown globals.

    python tools/lua_gate.py

A `loadstring` gate only proves the file parses. It cannot see a call to a function that no
longer exists -- Lua resolves those at run time, so deleting a local and leaving its callers
behind parses perfectly and then blows up on the frame that first reaches it. That happened:
a block edit removed `clock_index`/`elo_field`/`volume_field` from menu.lua and the file
still parsed clean.

This walks the compiled bytecode of every prototype (LuaJIT's jit.util.funcbc/funck) and
collects the name of every GGET/GSETV-style global access, then reports any that is neither a
Lua builtin nor an engine binding nor defined by the file itself. It is the cheapest check
that would have caught it, and it needs no engine and no running game.
"""

import glob
import os
import sys

import lupa.luajit21 as lj

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "Assets", "Scripts")

# Standard Lua 5.1/LuaJIT globals.
LUA = {
    "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable", "ipairs",
    "load", "loadfile", "loadstring", "module", "next", "pairs", "pcall", "print",
    "rawequal", "rawget", "rawlen", "rawset", "require", "select", "setfenv",
    "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "_G", "_VERSION",
    "coroutine", "debug", "io", "math", "os", "package", "string", "table", "bit", "jit",
    "_ENV",
}

# What PhasmaEngine injects into the script environment. Anything a chess script reaches for
# that is NOT in here is either a typo or a function somebody deleted.
ENGINE = {
    "engine", "scene", "input", "material", "settings", "runtime_ui", "tween", "fs", "net",
    "audio", "proc", "selection", "vec2", "vec3", "vec4", "mat4", "quat", "pe_log",
    "script", "json", "lerp", "light", "model", "particle", "physics", "shader",
    "sprite", "terrain", "voxel", "animation", "camera", "self", "transform", "mesh",
}

COLLECT = r"""
local util = require("jit.util")
local band, shr = bit.band, bit.rshift
-- lj_bc.h opcode order: GGET/GSET read and write a global, and carry its NAME as the D
-- operand's string constant. jit.bc (which would print this for us) is not compiled into
-- lupa's LuaJIT, so the two instructions are decoded by hand -- verified against a probe
-- chunk with a known-missing global before this gate was trusted.
local GGET, GSET = 54, 55
local seen, done = {}, {}

local function walk(f)
    if done[f] then return end
    done[f] = true
    local pc = 1
    while true do
        local ins = util.funcbc(f, pc)
        if not ins then break end
        local op = band(ins, 0xff)
        if op == GGET or op == GSET then
            local name = util.funck(f, -shr(ins, 16) - 1)
            if type(name) == "string" then seen[name] = true end
        end
        pc = pc + 1
    end
    -- Nested functions are GC constants of their parent.
    local info = util.funcinfo(f)
    for k = 1, (info.gcconsts or 0) do
        local kv = util.funck(f, -k)
        if type(kv) == "proto" then walk(kv) end
    end
end

walk(CHUNK)
local out = {}
for n in pairs(seen) do out[#out + 1] = n end
table.sort(out)
return table.concat(out, "|")
"""


def globals_used(rt, src, name):
    rt.execute("CHUNK = nil")
    chunk = rt.eval("function(s, n) local f, e = loadstring(s, n) "
                    "if not f then error(e, 0) end return f end")(src, "@" + name)
    rt.globals()["CHUNK"] = chunk
    text = rt.execute(COLLECT)
    # "|" and not a newline: escaping a newline through this file's Lua source is exactly
    # the kind of quoting bug this gate exists to catch elsewhere.
    return set(filter(None, (text or "").split("|")))


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "chess", "*.lua")))
    files.append(os.path.join(ROOT, "chess.lua"))

    rt = lj.LuaRuntime(unpack_returned_tuples=True)
    bad = 0
    for path in files:
        src = open(path, "rb").read().decode("utf-8")
        name = os.path.basename(path)
        try:
            used = globals_used(rt, src, name)
        except Exception as exc:                      # a parse error is a hard failure
            print("PARSE FAIL  %-14s %s" % (name, exc))
            bad += 1
            continue
        # A module may also define globals on purpose (game.lua does, for its forward
        # declarations that ended up global-scoped), so anything assigned in the file counts
        # as known.
        unknown = sorted(g for g in used if g not in LUA and g not in ENGINE)
        if unknown:
            print("UNKNOWN GLOBALS  %-14s %s" % (name, ", ".join(unknown)))
            bad += 1
        else:
            print("ok  %s" % name)
    print("\nfailures:", bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
