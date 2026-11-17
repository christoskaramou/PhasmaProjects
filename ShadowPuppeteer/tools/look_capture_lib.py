"""Shared by tools/look_capture.py and debugging: a throwaway, muted Player copy of Shadow Puppeteer on port 8914."""
import ctypes
import ctypes.wintypes as wt
import json
import shutil
import socket
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
ENGINE = GAME.parent.parent / "PhasmaEngine"
PORT = 8914               # (8911 is the user's installed copy now: coordinator 2026-11-13)
OUT = None
u32 = ctypes.windll.user32
u32.CreateDesktopW.restype = wt.HANDLE
u32.GetForegroundWindow.restype = wt.HWND
u32.SetThreadDesktop.argtypes = [wt.HANDLE]
WNDENUMPROC = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
u32.EnumDesktopWindows.argtypes = [wt.HANDLE, WNDENUMPROC, wt.LPARAM]
u32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
_k32 = ctypes.windll.kernel32
_k32.GetExitCodeProcess.argtypes = [wt.HANDLE, ctypes.POINTER(wt.DWORD)]
_k32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
_k32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
_k32.CloseHandle.argtypes = [wt.HANDLE]


class Mcp:
    def __init__(self, port):
        self.url, self.session, self.next_id = f"http://127.0.0.1:{port}/mcp", None, 0

    def send(self, method, params=None, notify=False):
        body = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            body["params"] = params
        if not notify:
            self.next_id += 1
            body["id"] = self.next_id
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, json.dumps(body).encode(), headers)
        with urllib.request.urlopen(req, timeout=60) as resp:
            self.session = resp.headers.get("Mcp-Session-Id") or self.session
            text = resp.read().decode()
        if notify or not text.strip():
            return None
        if "data:" in text:
            text = "\n".join(line[5:] for line in text.splitlines() if line.startswith("data:"))
        return json.loads(text)

    def call(self, name, arguments=None):
        return self.send("tools/call", {"name": name, "arguments": arguments or {}})["result"]

    def lua(self, code):
        r = self.call("execute_lua", {"code": code})
        if r.get("isError"):
            raise RuntimeError("lua failed: %s" % json.dumps(r)[:800])
        sc = r.get("structuredContent") or {}
        return sc.get("output", sc.get("result"))

    def shot(self, name, check="paper", size=None):
        # The Player names shots %TEMP%/phasma_player_shot_N.png with a per-process counter (PlayerMcp.cpp:121), so
        # another agent's Player can overwrite ours. Copy at once, keep only a frame that shows our own warm paper, and
        # delete the temp file only when it is ours (never move or delete another Player's shot).
        from PIL import Image
        for attempt in range(8):
            src, dst = self._shot(name)
            im = Image.open(dst).convert("RGB")
            w, h = im.size
            if check == "paper":      # the warm paper in the middle (look and play frames of the first set)
                ok = all(r > 110 and r > g > b and b < 100 for r, g, b in
                         (im.getpixel((int(w * fx), int(h * 0.36))) for fx in (0.35, 0.5, 0.65)))
            else:                     # "theatre": the dark header board and proscenium (any card, any set)
                import numpy as _np
                a_ = _np.asarray(im, float)
                lum = lambda blk: float((blk * [0.2126, 0.7152, 0.0722]).sum(-1).mean())
                ok = lum(a_[: max(2, h // 25)]) < 60 and lum(a_[-max(2, h // 25):]) < 70
            if size and (w, h) != tuple(size):
                ok = False
            im.close()
            if ok:
                try:
                    if src.exists() and src.stat().st_size == dst.stat().st_size and src.read_bytes() == dst.read_bytes():
                        src.unlink()
                except OSError:
                    pass
                print("  shot", dst.name, flush=True)
                return dst
            rej = dst.with_name("%s_rejected%d.png" % (name, attempt))
            dst.replace(rej)
            print("  shot for", name, "was not Shadow Puppeteer's frame (shared temp name): kept as", rej.name,
                  "left the temp file, retaking", flush=True)
            time.sleep(1.0)
        raise RuntimeError("could not take an uncontested screenshot")

    def _shot(self, name):
        r = self.call("take_screenshot")
        if r.get("isError"):
            raise RuntimeError("screenshot failed: %s" % r)
        src = Path(r["structuredContent"]["path"])
        prev = -1
        for _ in range(60):
            size = src.stat().st_size if src.exists() else -1
            if size > 0 and size == prev:
                break
            prev = size
            time.sleep(0.1)
        dst = Path(OUT) / (name + ".png")
        shutil.copy2(str(src), dst)
        return src, dst


DESKTOP = "puppet_live_desk"
_desk = None                    # kept open for the Player's lifetime


def _on_desk(fn, *args):
    """Run fn on a fresh thread attached to the Player's hidden desktop: window calls (EnumDesktopWindows is fine
    anywhere, but SetWindowPos / ShowWindow) only work from a thread on the window's desktop."""
    out = {}

    def run():
        try:
            if not u32.SetThreadDesktop(_desk):
                raise RuntimeError("SetThreadDesktop failed: %d" % ctypes.windll.kernel32.GetLastError())
            out["r"] = fn(*args)
        except BaseException as e:      # noqa: BLE001 - re-raised on the caller's thread
            out["e"] = e
    t = threading.Thread(target=run)
    t.start()
    t.join()
    if "e" in out:
        raise out["e"]
    return out.get("r")


def window_of(pid):
    """The game window (class SDL_app; the process also owns IME / input-indicator windows) on the hidden desktop."""
    found = []

    @WNDENUMPROC
    def cb(hwnd, _):
        p = wt.DWORD()
        u32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and u32.IsWindowVisible(hwnd):
            c = ctypes.create_unicode_buffer(64)
            u32.GetClassNameW(hwnd, c, 64)
            if c.value == "SDL_app":
                found.append(hwnd)
        return True
    u32.EnumDesktopWindows(_desk, cb, 0)
    return found[0] if found else None


def size_client(hwnd, w, h):
    """Client area w x h, without activating the window (SWP_NOACTIVATE | SWP_NOZORDER), from the hidden desktop."""
    def go():
        u32.ShowWindow(hwnd, 4)                               # SW_SHOWNOACTIVATE: restore if maximised
        style = u32.GetWindowLongW(hwnd, -16)
        exstyle = u32.GetWindowLongW(hwnd, -20)
        r = wt.RECT(0, 0, w, h)
        u32.AdjustWindowRectEx(ctypes.byref(r), style, False, exstyle)
        if not u32.SetWindowPos(hwnd, 0, 0, 0, r.right - r.left, r.bottom - r.top, 0x0010 | 0x0004):
            raise RuntimeError("SetWindowPos failed: %d" % ctypes.windll.kernel32.GetLastError())
    _on_desk(go)


# Scan codes (set 1): SDL2 maps WM_KEYDOWN by the scan code in lParam bits 16-23 (Undertow/tools/live.py).
VK = {"Space": (0x20, 0x39), "Escape": (0x1B, 0x01), "Return": (0x0D, 0x1C), "M": (0x4D, 0x32), "S": (0x53, 0x1F),
      "Q": (0x51, 0x10), "R": (0x52, 0x13), "N": (0x4E, 0x31), "H": (0x48, 0x23), "Backspace": (0x08, 0x0E), "Tab": (0x09, 0x0F),
      "A": (0x41, 0x1E), "D": (0x44, 0x20), "W": (0x57, 0x11), "Left": (0x25, 0x4B), "Right": (0x27, 0x4D),
      "Up": (0x26, 0x48), "Down": (0x28, 0x50)}
u32.PostMessageW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]


def post_key(hwnd, name, down):
    """A key to the Player's window only (never the user's foreground window)."""
    vk, sc = VK[name]
    ext = 0x01000000 if name in ("Left", "Right", "Up", "Down") else 0
    lp = 1 | (sc << 16) | ext | (0xC0000000 if not down else 0)
    if not _on_desk(lambda: u32.PostMessageW(hwnd, 0x0100 if down else 0x0101, vk, lp)):
        raise RuntimeError("PostMessage failed")


def tap(hwnd, name, hold=0.08):
    post_key(hwnd, name, True)
    time.sleep(hold)
    post_key(hwnd, name, False)


def mouse_batch(hwnd, events):
    """[(x, y, "move" | "down" | "up"), ...] posted back to back (SDL2 answers the first move with TrackMouseEvent; the
    real cursor is elsewhere, so a WM_MOUSELEAVE follows: batched, it queues behind the button up)."""
    def go():
        for x, y, what in events:
            lp = (int(y) & 0xFFFF) << 16 | (int(x) & 0xFFFF)
            # "drag": a move with the left button held (MK_LBUTTON), as Windows sends it while dragging
            msg, wp = {"move": (0x0200, 0), "drag": (0x0200, 1), "down": (0x0201, 1), "up": (0x0202, 0)}[what]
            if not u32.PostMessageW(hwnd, msg, wp, lp):
                raise RuntimeError("PostMessage failed")
    _on_desk(go)


def click(hwnd, x, y):
    mouse_batch(hwnd, [(x, y, "move"), (x, y, "down"), (x, y, "up")])


class _SI(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("lpReserved", wt.LPWSTR), ("lpDesktop", wt.LPWSTR), ("lpTitle", wt.LPWSTR),
                ("dwX", wt.DWORD), ("dwY", wt.DWORD), ("dwXSize", wt.DWORD), ("dwYSize", wt.DWORD),
                ("dwXCountChars", wt.DWORD), ("dwYCountChars", wt.DWORD), ("dwFillAttribute", wt.DWORD),
                ("dwFlags", wt.DWORD), ("wShowWindow", wt.WORD), ("cbReserved2", wt.WORD),
                ("lpReserved2", ctypes.c_void_p), ("hStdInput", wt.HANDLE), ("hStdOutput", wt.HANDLE),
                ("hStdError", wt.HANDLE)]


class _PI(ctypes.Structure):
    _fields_ = [("hProcess", wt.HANDLE), ("hThread", wt.HANDLE), ("dwProcessId", wt.DWORD), ("dwThreadId", wt.DWORD)]


class HiddenPlayer:
    """The Player process on its own desktop (CreateDesktopW + STARTUPINFO.lpDesktop): its window can never become
    the user's foreground window or get the user's keys, although the engine maximises/activates it on start
    (RuntimeHost.h:14, RuntimeHost.cpp:145). A watcher polls GetForegroundWindow every 50 ms for the process's whole
    life and counts samples where the foreground window belongs to the Player; kill() prints the count (must be 0)."""

    def __init__(self, argv, cwd):
        global _desk
        k32 = ctypes.windll.kernel32
        if not _desk:
            _desk = u32.CreateDesktopW(DESKTOP, None, None, 0, 0x10000000, None)    # GENERIC_ALL
            if not _desk:
                raise SystemExit("CreateDesktop failed: %d" % k32.GetLastError())
        si, pi = _SI(), _PI()
        si.cb = ctypes.sizeof(_SI)
        si.lpDesktop = "WinSta0\\" + DESKTOP
        buf = ctypes.create_unicode_buffer(subprocess.list2cmdline(argv))
        if not k32.CreateProcessW(argv[0], buf, None, None, False, 0x08000000, None, cwd,   # CREATE_NO_WINDOW
                                  ctypes.byref(si), ctypes.byref(pi)):
            raise SystemExit("CreateProcess failed: %d" % k32.GetLastError())
        k32.CloseHandle(pi.hThread)
        self.pid, self.handle, self.returncode = pi.dwProcessId, pi.hProcess, None
        self.focus_takes, self.focus_samples, self.t0 = 0, 0, time.time()
        self.fg0 = u32.GetForegroundWindow()
        self.watch = threading.Thread(target=self._watch, daemon=True)
        self.watch.start()

    def poll(self):
        code = wt.DWORD()
        ctypes.windll.kernel32.GetExitCodeProcess(self.handle, ctypes.byref(code))
        if code.value != 259:                                              # STILL_ACTIVE
            self.returncode = code.value
        return self.returncode

    def _watch(self):
        while self.poll() is None:
            fg = u32.GetForegroundWindow()
            p = wt.DWORD()
            u32.GetWindowThreadProcessId(fg, ctypes.byref(p))
            self.focus_samples += 1
            if fg and p.value == self.pid:
                self.focus_takes += 1
            time.sleep(0.05)

    def kill(self):
        if self.poll() is None:
            ctypes.windll.kernel32.TerminateProcess(self.handle, 1)
            ctypes.windll.kernel32.WaitForSingleObject(self.handle, 10000)
        self.watch.join(2)
        print("focus check: Player took the foreground in %d of %d samples (50 ms) over %.1f s; foreground before %s, now %s"
              % (self.focus_takes, self.focus_samples, time.time() - self.t0, self.fg0, u32.GetForegroundWindow()),
              flush=True)

    wait = kill


def launch(out_dir, relaunch=False):
    """Copy the newest Release Player and this game's Assets into out_dir/work (muted settings, port 8914) and start it.
    relaunch=True: start the copy already there again, its Save folder kept (the save-and-restart check); still muted."""
    global OUT
    OUT = Path(out_dir).resolve()
    WORK = OUT / "work"
    with socket.socket() as s:
        if s.connect_ex(("127.0.0.1", PORT)) == 0:
            raise SystemExit("port %d is in use: not launching" % PORT)
    if relaunch:
        rt, cfg = WORK / "rt", WORK / "game" / "Assets" / "Save" / "settings.cfg"
        keep = [l for l in cfg.read_text().splitlines() if not l.startswith(("master=", "mute="))] if cfg.exists() else []
        cfg.write_text("\n".join(keep + ["master=0", "mute=true"]) + "\n")
        return HiddenPlayer([str(rt / "PhasmaPlayer.exe"), "--api", "vulkan", "--display", "1"], str(rt))
    if WORK.exists():
        shutil.rmtree(WORK)
    OUT.mkdir(parents=True, exist_ok=True)
    rt, assets = WORK / "rt", WORK / "game" / "Assets"
    rt.mkdir(parents=True)
    builds = [p for p in ENGINE.glob("build*/Release/PhasmaPlayer.exe") if (p.parent / "RuntimeAssets").is_dir()]
    player = max(builds, key=lambda p: p.stat().st_mtime).parent
    shutil.copy2(player / "PhasmaPlayer.exe", rt)
    for dll in player.glob("*.dll"):
        if "_live_" not in dll.name:
            shutil.copy2(dll, rt)
    for folder in ("RuntimeAssets", "MaterialX"):
        if (player / folder).is_dir():
            shutil.copytree(player / folder, rt / folder)
    shutil.copytree(GAME / "Assets", assets, ignore=shutil.ignore_patterns("Save", "Agent", "Cache", "ShadersCache"))
    (assets / "Save").mkdir()
    (assets / "Save" / "settings.cfg").write_text("# Phasma settings_menu v1\nmaster=0\nmute=true\n")
    (assets / "Agent").mkdir()
    (assets / "Agent" / "agent_config.json").write_text(json.dumps({"mcp": True, "mcp_port": PORT}))
    (rt / "phasma_settings.json").write_text(json.dumps({"project_path": str(assets), "project_manifest": "",
        "startup_scene": "Scenes/main.pescene", "graphics_api": "vulkan", "live_profiler": False,
        "background_fps_cap": False}))
    return HiddenPlayer([str(rt / "PhasmaPlayer.exe"), "--api", "vulkan", "--display", "1"], str(rt))


def connect(mcp, proc):
    """Wait for the MCP server, then for the game's script."""
    deadline = time.time() + 120
    while True:
        if proc.poll() is not None:
            raise RuntimeError("Player exited early: %s" % proc.returncode)
        try:
            mcp.send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "sp", "version": "0"}})
            mcp.send("notifications/initialized", notify=True)
            break
        except OSError:
            if time.time() > deadline:
                raise RuntimeError("no MCP after 120 s")
            time.sleep(0.5)
    deadline = time.time() + 120
    while time.time() < deadline:
        try:
            if mcp.lua("return tostring(_G.puppet ~= nil and _G.puppet.W ~= nil)") == "true":
                return
        except Exception:
            pass
        time.sleep(1)
