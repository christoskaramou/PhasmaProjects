#!/usr/bin/env python3
"""Run the paper balance harness (tools/paper_balance.lua) without the player.

Usage:
    python tools/paper_balance.py                 # full matrix + gates
    python tools/paper_balance.py --class brawler # one class, gates skipped
    python tools/paper_balance.py --map 3 --gear mid --policy offense
"""
import argparse
import sys
from pathlib import Path

from lupa import LuaRuntime  # pip install lupa

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--class", dest="cls", help="only this class id")
    ap.add_argument("--map", type=int, help="only this map index (1-13)")
    ap.add_argument("--gear", choices=["none", "mid", "top"], help="only this gearset")
    ap.add_argument("--policy", choices=["spec", "universal"],
                    help="draft policy: rank the class spec first (default) or universals only")
    ap.add_argument("--spec", help="specialization id to rank (default: class's first)")
    ap.add_argument("--debug", action="store_true", help="dump alive creeps on wave stall")
    ap.add_argument("--no-gates", action="store_true", help="report only, skip gates")
    ap.add_argument("--save-baseline", action="store_true",
                    help="pin current outcomes as tools/paper_baseline.txt")
    a = ap.parse_args()

    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.PAPER_ROOT = ROOT.as_posix()
    g.PAPER_ARGS = lua.table(
        **{k: v for k, v in {
            "class": a.cls, "map": a.map, "gear": a.gear, "policy": a.policy,
            "spec": a.spec, "debug": a.debug or None, "no_gates": a.no_gates or None,
            "save_baseline": a.save_baseline or None,
        }.items() if v is not None}
    )
    failures = lua.execute((ROOT / "tools" / "paper_balance.lua").read_text(encoding="utf-8"))
    return 1 if failures and int(failures) > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
