#!/usr/bin/env python
"""Capture Phasma* windows to tools/_ui_overlap_out/live/."""
from __future__ import annotations

import ctypes
import os
import re
from ctypes import wintypes
from pathlib import Path

from PIL import ImageGrab

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "_ui_overlap_out" / "live"

user32 = ctypes.windll.user32
user32.SetProcessDPIAware()


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


def list_phasma_windows():
    EnumWindows = user32.EnumWindows
    EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    found = []

    def foreach(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        n = user32.GetWindowTextLengthW(hwnd)
        if n <= 0:
            return True
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(hwnd, buf, n + 1)
        if "Phasma" in buf.value:
            found.append((hwnd, buf.value))
        return True

    EnumWindows(EnumWindowsProc(foreach), 0)
    return found


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    wins = list_phasma_windows()
    if not wins:
        print("no Phasma windows found")
        return 1
    for hwnd, title in wins:
        rect = RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        img = ImageGrab.grab(bbox=(rect.left, rect.top, rect.right, rect.bottom), all_screens=True)
        safe = re.sub(r"[^\w\-]+", "_", title)[:72]
        path = OUT / f"{safe}.png"
        img.save(path)
        print("wrote", path, img.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
