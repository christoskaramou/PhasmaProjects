"""Drive a throwaway, muted copy of Loom in the Player over MCP (port 8913). Never the user's game or saves.

    python tools/live.py start            copy the player + Assets to %TEMP%/loom_live, mute, launch, wait for MCP
    python tools/live.py lua "<code>"     run Lua (execute_lua) and print its result
    python tools/live.py shot <out.png>   take a screenshot, copy it to out.png, check it is Loom
    python tools/live.py tools            list the MCP tools
    python tools/live.py stop             close the copy
"""
import json
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENGINE = ROOT.parent.parent / "PhasmaEngine"
WORK = Path(__import__("tempfile").gettempdir()) / "loom_live"
PORT = 8913


class Mcp:
    def __init__(self, port):
        self.url, self.session, self.next_id = f"http://127.0.0.1:{port}/mcp", None, 0

    def send(self, method, params=None, notify=False, timeout=120):
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
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            self.session = resp.headers.get("Mcp-Session-Id") or self.session
            text = resp.read().decode()
        if notify or not text.strip():
            return None
        if "data:" in text:
            text = "\n".join(line[5:] for line in text.splitlines() if line.startswith("data:"))
        return json.loads(text)

    def init(self):
        self.send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "loom", "version": "0"}})
        self.send("notifications/initialized", notify=True)
        return self

    def call(self, name, arguments=None):
        return self.send("tools/call", {"name": name, "arguments": arguments or {}})["result"]

    def lua(self, code):
        r = self.call("execute_lua", {"code": code})
        if r.get("isError"):
            raise RuntimeError("lua failed: %s" % json.dumps(r)[:800])
        sc = r.get("structuredContent") or {}
        return sc.get("output", sc.get("result"))

    def shot(self, dst, check=True, ref=None):
        # %TEMP%\phasma_player_shot_N.png is shared with other agents' Players (per-process counter,
        # PlayerMcp.cpp:119-121): copy it at once, never move/delete it, and retake if it is not Loom.
        dst = Path(dst)
        dst.parent.mkdir(parents=True, exist_ok=True)
        for attempt in range(3):
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
            try:
                shutil.copyfile(src, dst)
            except OSError:
                continue
            if callable(ref):
                ok = ref(dst)
            elif ref is None:
                ok = is_loom(dst)
            elif isinstance(ref, tuple):
                ok = similar(dst, ref[0], ref[1])
            else:
                ok = similar(dst, ref)
            if not check or ok:
                return dst
            print(f"shot {src.name} is not Loom (another Player?), retaking", file=sys.stderr)
        raise RuntimeError(f"no Loom screenshot after 3 tries: {dst}")


def is_loom(png):
    """Grey 64x36 thumbnail: a Loom frame is closer to Loom's targets than to the other two games' concepts
    (Shadow Puppeteer on 8911, Undertow on 8912 may take shots into the same %TEMP% names).
    ponytail: content heuristic, not proof of origin; upgrade = a per-process shot path in the engine."""
    import numpy as np
    from PIL import Image
    nxt = ROOT.parent / ".concepts" / "next"

    def thumb(p):
        im = Image.open(p).convert("L")
        w, h = im.size
        if abs(w / h - 16 / 9) > 0.01:                 # crop to 16:9 like the game's camera (top and bottom)
            nh = round(w * 9 / 16)
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        return np.asarray(im.resize((64, 36), Image.BILINEAR), dtype=np.float32)

    def ncc(a, b):          # normalised correlation: robust to the cards' dimming and to brightness changes
        a, b = a - a.mean(), b - b.mean()
        return float((a * b).sum() / (np.sqrt((a * a).sum() * (b * b).sum()) + 1e-9))

    if not (nxt / "loom" / "target.png").exists():
        print("is_loom: no reference images (.concepts was removed); shot not checked")
        return True
    t = thumb(png)
    mine = max(ncc(t, thumb(nxt / "loom" / n)) for n in ("target.png", "target_b.png", "backdrop.png"))
    other = max(ncc(t, thumb(nxt / n)) for n in ("undertow.png", "shadow_puppeteer.png"))
    return mine > other


def similar(png, ref, box=None, limit=0.8):
    """A card that hides the scene (the settings menu): compare with an earlier verified shot of the same card."""
    import numpy as np
    from PIL import Image

    def th(p):                # the card itself: the middle half of the window (the scene around it may change), or box
        im = Image.open(p).convert("L")
        w, h = im.size
        b = (w // 4, 0, 3 * w // 4, h) if box is None else tuple(int(f * d) for f, d in zip(box, (w, h, w, h)))
        return np.asarray(im.crop(b).resize((64, 12) if box else (32, 36), Image.BILINEAR), dtype=np.float32)
    a, b = th(png), th(ref)
    a, b = a - a.mean(), b - b.mean()
    return float((a * b).sum() / (np.sqrt((a * a).sum() * (b * b).sum()) + 1e-9)) > limit


def port_free(port):
    with socket.socket() as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def start():
    assert PORT not in (8881,)
    if not port_free(PORT):
        raise SystemExit(f"port {PORT} is busy: another copy is running (python tools/live.py stop) or something else uses it")
    if WORK.exists():
        shutil.rmtree(WORK)
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
    shutil.copytree(ROOT / "Assets", assets, ignore=shutil.ignore_patterns("Save", "Agent", "Cache", "ShadersCache"))
    (assets / "Save").mkdir()
    # muted before the first frame: the shared settings menu reads these (master volume 0, mute on)
    (assets / "Save" / "settings.cfg").write_text("# Phasma settings_menu v1\nmaster=0\nmute=true\nbloom=false\nssao=true\n")
    (assets / "Agent").mkdir()
    (assets / "Agent" / "agent_config.json").write_text(json.dumps({"mcp": True, "mcp_port": PORT}))
    (rt / "phasma_settings.json").write_text(json.dumps({"project_path": str(assets), "project_manifest": "",
                                                          "startup_scene": "Scenes/main.pescene", "graphics_api": "vulkan",
                                                          "live_profiler": False,
                                                          # the copy is never focused (hidden desktop): render it uncapped
                                                          # (PhasmaEngine Timer.cpp:26, read at Timer.cpp:74, applied 104)
                                                          "background_fps_cap": False}))
    t0 = time.time()
    watch = FocusWatch()
    watch.start()
    proc = launch_hidden([str(rt / "PhasmaPlayer.exe"), "--api", "vulkan", "--display", "1"], str(rt))
    watch.pid = proc.pid
    (WORK / "pid.txt").write_text(str(proc.pid))
    mcp = Mcp(PORT)
    deadline = time.time() + 180
    while True:
        if proc.poll() is not None:
            raise SystemExit("Player exited early: %s" % proc.returncode)
        try:
            mcp.init()
            break
        except OSError:
            if time.time() > deadline:
                raise SystemExit("no MCP after 180 s")
            time.sleep(0.5)
    while time.time() < deadline:
        try:
            if mcp.lua("return tostring(_G.loom ~= nil)") == "true":
                break
        except Exception:
            pass
        time.sleep(0.5)
    time.sleep(3.0)
    watch.stop()
    (WORK / "focus.json").write_text(json.dumps(watch.report()))
    print("focus watch:", watch.report())
    print("muted:", mcp.lua("if audio and audio.set_master_volume then audio.set_master_volume(0) end; return 'master 0'"))
    print("ready in %.1f s; player %s; port %d; log %s" % (time.time() - t0, player, PORT, rt / "PhasmaEngine.log"))


DESKTOP = "loom_live_desk"


class _Proc:
    def __init__(self, pid, handle):
        self.pid, self.handle, self.returncode = pid, handle, None

    def poll(self):
        import ctypes
        code = ctypes.c_ulong()
        ctypes.windll.kernel32.GetExitCodeProcess(self.handle, ctypes.byref(code))
        if code.value != 259:                       # STILL_ACTIVE
            self.returncode = code.value
        return self.returncode


def launch_hidden(argv, cwd):
    """Start the copy on its own desktop (CreateDesktop + STARTUPINFO.lpDesktop; UndertowLead's fix, round 4). The
    Player maximises and activates its window at launch (PhasmaEngine RuntimeHost.h:14, RuntimeHost.cpp:145); on a
    desktop nobody sees, that window can never become the user's foreground window or receive the user's keys. It
    still renders, resizes and takes posted input (window calls must come from a thread on that desktop: on_desk)."""
    import ctypes
    from ctypes import wintypes
    k32, user32 = ctypes.windll.kernel32, ctypes.windll.user32
    user32.CreateDesktopW.restype = wintypes.HANDLE
    if not user32.CreateDesktopW(DESKTOP, None, None, 0, 0x10000000, None):      # GENERIC_ALL
        raise SystemExit("CreateDesktop failed: %d" % k32.GetLastError())

    class SI(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("lpReserved", wintypes.LPWSTR), ("lpDesktop", wintypes.LPWSTR),
                    ("lpTitle", wintypes.LPWSTR), ("dwX", wintypes.DWORD), ("dwY", wintypes.DWORD), ("dwXSize", wintypes.DWORD),
                    ("dwYSize", wintypes.DWORD), ("dwXCountChars", wintypes.DWORD), ("dwYCountChars", wintypes.DWORD),
                    ("dwFillAttribute", wintypes.DWORD), ("dwFlags", wintypes.DWORD), ("wShowWindow", wintypes.WORD),
                    ("cbReserved2", wintypes.WORD), ("lpReserved2", ctypes.c_void_p), ("hStdInput", wintypes.HANDLE),
                    ("hStdOutput", wintypes.HANDLE), ("hStdError", wintypes.HANDLE)]

    class PI(ctypes.Structure):
        _fields_ = [("hProcess", wintypes.HANDLE), ("hThread", wintypes.HANDLE), ("dwProcessId", wintypes.DWORD),
                    ("dwThreadId", wintypes.DWORD)]
    si, pi = SI(), PI()
    si.cb = ctypes.sizeof(SI)
    si.lpDesktop = "WinSta0\\" + DESKTOP
    k32.CreateProcessW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wintypes.BOOL,
                                   wintypes.DWORD, ctypes.c_void_p, wintypes.LPCWSTR, ctypes.c_void_p, ctypes.c_void_p]
    buf = ctypes.create_unicode_buffer(subprocess.list2cmdline(argv))
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP   # survive this shell closing
    if not k32.CreateProcessW(argv[0], buf, None, None, False, flags, None, cwd, ctypes.byref(si), ctypes.byref(pi)):
        raise SystemExit("CreateProcess failed: %d" % k32.GetLastError())
    k32.CloseHandle(pi.hThread)
    (WORK / "desktop.txt").write_text(DESKTOP)
    return _Proc(pi.dwProcessId, pi.hProcess)


def on_desk():
    """Move the calling thread to the copy's desktop (SetThreadDesktop) so its window calls (EnumDesktopWindows,
    PostMessage, SetWindowPos) reach the copy. Call it on a thread that owns no windows; repeat calls are no-ops."""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    if not (WORK / "desktop.txt").exists():
        return
    user32.OpenDesktopW.restype = wintypes.HANDLE
    d = user32.OpenDesktopW((WORK / "desktop.txt").read_text().strip(), 0, False, 0x10000000)
    if not d or not user32.SetThreadDesktop(wintypes.HANDLE(d)):
        raise RuntimeError("SetThreadDesktop failed: %d" % ctypes.windll.kernel32.GetLastError())


def game_window(pid):
    """The copy's game window (class SDL_app; the process also owns IME / input-indicator windows)."""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    on_desk()
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(h, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(h, ctypes.byref(p))
        c = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(h, c, 64)
        if p.value == pid and user32.IsWindowVisible(h) and c.value == "SDL_app":
            found.append(h)
        return True
    user32.EnumDesktopWindows(user32.GetThreadDesktop(ctypes.windll.kernel32.GetCurrentThreadId()), cb, 0)
    if not found:
        raise SystemExit("no game window for pid %d" % pid)
    return found[0]


class FocusWatch:
    """Polls the foreground window every 5 ms from before the launch until stopped and records any moment it belongs
    to the copy's process (the user's focus must never move to it)."""
    def __init__(self):
        import threading
        self.pid, self.hits, self.polls, self.first, self._run = None, 0, 0, None, True
        self.t0 = time.time()
        self.th = threading.Thread(target=self._loop, daemon=True)

    def start(self):
        self.th.start()

    def _loop(self):
        import ctypes
        from ctypes import wintypes
        user32 = ctypes.windll.user32
        while self._run:
            h = user32.GetForegroundWindow()
            p = wintypes.DWORD()
            user32.GetWindowThreadProcessId(h, ctypes.byref(p))
            self.polls += 1
            if self.pid is not None and p.value == self.pid:
                self.hits += 1
                if self.first is None:
                    self.first = time.time() - self.t0
            time.sleep(0.005)

    def stop(self):
        self._run = False
        self.th.join(1.0)

    def report(self):
        return {"polls": self.polls, "foreground_hits": self.hits, "first_hit_s": self.first, "seconds": round(time.time() - self.t0, 1)}


def stop():
    pid = (WORK / "pid.txt").read_text().strip() if (WORK / "pid.txt").exists() else None
    if pid:
        subprocess.run(["taskkill", "/PID", pid, "/F"], capture_output=True)
        print("stopped", pid)


def size(w, h):
    """Resize the throwaway Player's window (found by its PID) so its client area is w x h; 0 0 = maximize."""
    import ctypes
    from ctypes import wintypes
    pid = int((WORK / "pid.txt").read_text().strip())
    user32 = ctypes.windll.user32
    hwnd = game_window(pid)
    # never activate or focus it (round 3): no maximise, no SetForegroundWindow; 0 0 = the maximised client size
    if w == 0:
        w, h = 2560, 1369
    r = wintypes.RECT(0, 0, w, h)
    style = user32.GetWindowLongW(hwnd, -16)
    user32.AdjustWindowRect(ctypes.byref(r), style, False)
    SWP_NOZORDER, SWP_NOACTIVATE = 0x0004, 0x0010
    user32.ShowWindow(hwnd, 4)                      # SW_SHOWNOACTIVATE: un-maximise (it starts maximised), never activate
    user32.SetWindowPos(hwnd, 0, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE)
    cr = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(cr))
    return cr.right, cr.bottom


def main():
    cmd = sys.argv[1]
    if cmd == "start":
        start()
    elif cmd == "stop":
        stop()
    elif cmd == "size":
        print(size(int(sys.argv[2]), int(sys.argv[3])))
    else:
        mcp = Mcp(PORT).init()
        if cmd == "lua":
            print(mcp.lua(sys.argv[2]))
        elif cmd == "shot":
            print(mcp.shot(sys.argv[2]))
        elif cmd == "tools":
            for t in mcp.send("tools/list")["result"]["tools"]:
                print(t["name"], "-", (t.get("description") or "")[:110])


if __name__ == "__main__":
    main()
