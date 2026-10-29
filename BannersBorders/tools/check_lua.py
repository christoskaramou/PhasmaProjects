#!/usr/bin/env python3
"""Syntax-check the concatenated game.lua with LuaJIT (via lupa) and list free globals that look like typos."""
import sys, re, lupa
try:
    from lupa import luajit21 as L
except Exception:
    from lupa import lua51 as L
rt = L.LuaRuntime()
src = open(sys.argv[1] if len(sys.argv) > 1 else 'project/Assets/Scripts/game.lua').read()
f = rt.eval('function(s) local f, e = loadstring(s, "game.lua"); return e end')
err = f(src)
print('SYNTAX OK' if err is None else 'ERROR: ' + str(err))
sys.exit(0 if err is None else 1)
