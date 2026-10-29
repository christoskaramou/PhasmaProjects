#!/bin/bash
# rebuild Assets/Scripts/game.lua from the numbered source parts (C collation order).
# Parts 03*/04* are engine-agnostic (shared with tools/simtest.py) and are wrapped in do..end so their
# locals stay out of the main chunk (LuaJIT allows 200 locals per function).
cd "$(dirname "$0")/.." || exit 1
out=project/Assets/Scripts/game.lua
: > "$out"
for f in $(ls src/0*.lua | LC_ALL=C sort); do
  case "$(basename "$f")" in
    03*|04*) { echo "do -- $(basename "$f")"; cat "$f"; echo "end"; } >> "$out" ;;
    *) cat "$f" >> "$out" ;;
  esac
done
