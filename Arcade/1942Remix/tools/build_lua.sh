#!/bin/bash
# rebuild Assets/Scripts/game.lua from the numbered source parts
cd "$(dirname "$0")" && cat src/0*.lua > ../project/Assets/Scripts/game.lua 2>/dev/null || cat src/0*.lua > ../Assets/Scripts/game.lua
