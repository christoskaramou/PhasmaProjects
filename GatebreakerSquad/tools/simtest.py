#!/usr/bin/env python3
"""Headless balance test: runs the real 03_data/03b_levels/04_sim Lua with an autoplay bot through all levels."""
import sys, os, lupa
from lupa import luajit21 as L
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.dirname(here)
rt = L.LuaRuntime()
rt.execute("G = {}; math.randomseed(%d)" % int(sys.argv[1] if len(sys.argv) > 1 else 1))
for f in ["src/03_data.lua", "src/03b_levels.lua", "src/04_sim.lua", "src/04b_bot.lua"]:
    rt.execute(open(os.path.join(root, f)).read())
rt.execute(open(os.path.join(here, "simrun.lua")).read())
