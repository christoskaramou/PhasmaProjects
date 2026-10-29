#!/usr/bin/env python3
# Cross-platform twin of build_lua.sh: rebuild project/Assets/Scripts/game.lua from src/0*.lua (C collation order).
# Parts 03*/04* are engine-agnostic (shared with tools/simtest.py) and are wrapped in do..end so their locals stay
# out of the main chunk (LuaJIT allows 200 locals per function).
import os, glob
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = []
for f in sorted(glob.glob(os.path.join(root, 'src', '0*.lua')), key=lambda p: os.path.basename(p).encode()):
    b = os.path.basename(f); body = open(f, 'rb').read()
    out.append(b'do -- ' + b.encode() + b'\n' + body + b'end\n' if b[:2] in ('03', '04') else body)
open(os.path.join(root, 'project', 'Assets', 'Scripts', 'game.lua'), 'wb').write(b''.join(out))
