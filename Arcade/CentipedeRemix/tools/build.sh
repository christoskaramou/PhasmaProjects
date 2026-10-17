#!/bin/bash
cd "$(dirname "$0")/.."
cat parts/a.lua parts/b.lua parts/c.lua parts/d.lua parts/e.lua parts/f.lua > project/Assets/Scripts/game.lua
bin/luajit -e "assert(loadfile(\"project/Assets/Scripts/game.lua\"))" && echo built
