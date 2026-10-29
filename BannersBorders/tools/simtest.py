#!/usr/bin/env python3
"""Headless balance test: runs the real game Lua (maps, data, levels, sim, AI) with player autopilots through all levels.
Env: SIMBOT=skilled,casual,lazy,idle  SIMSEEDS=3  SIMLVL=0  SIMV=1"""
import sys, os, glob
from lupa import luajit21 as L
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.dirname(here)
rt = L.LuaRuntime()
rt.execute("G = {}; math.randomseed(1)")
files = sorted(glob.glob(os.path.join(root, "src/03m_*.lua"))) + [os.path.join(root, f) for f in ["src/03_data.lua", "src/03b_levels.lua", "src/04_sim.lua", "src/04b_ai.lua"]]
for f in files:
    rt.execute(open(f).read())
rt.execute(open(os.path.join(here, "simbot.lua")).read())
rt.execute(open(os.path.join(here, "simrun.lua")).read())
