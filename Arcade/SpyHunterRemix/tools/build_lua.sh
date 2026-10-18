#!/bin/bash
# rebuild Assets/Scripts/game.lua from the numbered source parts (C collation: 02_look before 02b_rigs)
cd "$(dirname "$0")/.." && cat $(ls src/0*.lua | LC_ALL=C sort) > project/Assets/Scripts/game.lua
