"""Drive a throwaway, muted copy of Undertow in the Player over MCP (port 8912). Never the user's game or saves.

    python tools/live.py start            copy the player + Assets to %TEMP%/undertow_live, mute, launch, wait for MCP
    python tools/live.py lua "<code>"     run Lua (execute_lua) and print its result
    python tools/live.py shot <out.png>   take a screenshot, copy it to out.png, check it is Undertow
    python tools/live.py tools            list the MCP tools
    python tools/live.py key <Name> down|up|tap   post a key to the copy's window only (WM_KEYDOWN/UP)
    python tools/live.py click <x> <y>    post a left click at client pixel x, y to the copy's window only
    python tools/live.py stop             close the copy
Input is posted to the throwaway Player's own HWND (found by its PID): never SendInput, never focus or activation,
so the user's foreground window and keyboard are untouched. The window starts without activation (SW_SHOWNOACTIVATE)
and runs unfocused with the background FPS cap off (phasma_settings.json "background_fps_cap": false).
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
WORK = Path(__import__("tempfile").gettempdir()) / "undertow_live"
PORT = 8912


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
        self.send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "uw", "version": "0"}})
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

    def shot(self, dst, check=True):
        # %TEMP%\phasma_player_shot_N.png is shared with other agents' Players (per-process counter,
        # PlayerMcp.cpp:119-121): copy it at once, never move/delete it, and retake if it is not Undertow.
        dst = Path(dst)
        dst.parent.mkdir(parents=True, exist_ok=True)
        # Guard 1: an 8x8 magenta marker only this copy draws (bottom-right), checked in the copied file. Guard 2 (scene
        # shots, check=True): is_undertow. Full-screen cards hide the scene, so they rely on the marker.
        self.lua(GUARD_ON)
        time.sleep(0.15)
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
            if has_marker(dst) and (not check or is_undertow(dst)):
                self.lua(GUARD_OFF)
                return dst
            print(f"shot {src.name} is not Undertow (another Player?), retaking", file=sys.stderr)
        self.lua(GUARD_OFF)
        raise RuntimeError(f"no Undertow screenshot after 3 tries: {dst}")


GUARD_ON = """local s = runtime_ui.get_surface_size(); runtime_ui.set_quad("undertow", "__guard", { style = "text", label = "",
  x = s.width - 8, y = s.height - 8, width = 8, height = 8, z = 9999, fill = { 1, 0, 1, 1 }, border = { 0, 0, 0, 0 },
  accent = { 0, 0, 0, 0 }, no_input = true, visible = true }); return "guard" """
GUARD_OFF = """runtime_ui.set_quad("undertow", "__guard", { visible = false, x = 0, y = 0, width = 1, height = 1, no_input = true }); return "off" """


def has_marker(png):
    from PIL import Image
    im = Image.open(png).convert("RGB")
    w, h = im.size
    px = [im.getpixel((w - 1 - i, h - 1 - j)) for i in range(3, 6) for j in range(3, 6)]
    # magenta hue (a card's dim backdrop darkens it to ~99,0,102; the scene never has pure magenta)
    return all(p[0] > 60 and p[2] > 60 and p[1] < 0.15 * p[0] and abs(p[0] - p[2]) < 0.2 * max(p[0], p[2]) for p in px)


def is_undertow(png, limit=35.0):
    """Grey 64x36 thumbnail vs the approved targets: Undertow frames score 8-20, other games' concepts 51-57.
    ponytail: content heuristic, not proof of origin; upgrade = a per-process shot path in the engine."""
    import numpy as np
    from PIL import Image
    tdir = ROOT.parent / ".concepts" / "next" / "undertow"

    def thumb(p):
        im = Image.open(p).convert("L")
        if im.height == 1440:
            o = (1440 - 1369) // 2
            im = im.crop((0, o, 2560, o + 1369))
        return np.asarray(im.resize((64, 36), Image.BILINEAR), dtype=np.float32)

    t = thumb(png)
    return min(float(abs(t - thumb(tdir / n)).mean()) for n in ("target.png", "target_b.png")) < limit


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
    (assets / "Save" / "settings.cfg").write_text("# Phasma settings_menu v1\nmaster=0\nmute=true\n")
    (assets / "Agent").mkdir()
    (assets / "Agent" / "agent_config.json").write_text(json.dumps({"mcp": True, "mcp_port": PORT}))
    (rt / "phasma_settings.json").write_text(json.dumps({"project_path": str(assets), "project_manifest": "",
                                                          "startup_scene": "Scenes/main.pescene", "graphics_api": "vulkan",
                                                          "live_profiler": False, "background_fps_cap": False}))
    t0 = time.time()
    import ctypes, os
    user32 = ctypes.windll.user32
    fg0 = user32.GetForegroundWindow()
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP   # survive this shell closing
    proc = launch_hidden([str(rt / "PhasmaPlayer.exe"), "--api", "vulkan", "--display", "1"], str(rt), WORK / "player_stdout.txt")
    (WORK / "pid.txt").write_text(str(proc.pid))
    import threading
    watch = threading.Thread(target=give_back_focus, args=(fg0, proc.pid, 25.0), daemon=True)
    watch.start()          # from the moment the window can appear
    mcp = Mcp(PORT)
    deadline = time.time() + 180
    while True:
        if not proc.alive():
            raise SystemExit("Player exited early")
        try:
            mcp.init()
            break
        except OSError:
            if time.time() > deadline:
                raise SystemExit("no MCP after 180 s")
            time.sleep(0.5)
    while time.time() < deadline:
        try:
            if mcp.lua("return tostring(_G.undertow ~= nil)") == "true":
                break
        except Exception:
            pass
        time.sleep(0.5)
    # Never keep the user's focus. The Player maximizes its window after creating it (engine RuntimeHost.h:14,
    # RuntimeHost.cpp:145: SDL_MaximizeWindow -> SW_MAXIMIZE activates whenever Windows allows it, e.g. after the user
    # has been idle), so watch the foreground for 20 s and hand it straight back to the window that had it.
    watch.join()
    print("muted:", mcp.lua("if audio and audio.set_master_volume then audio.set_master_volume(0) end; return 'master 0'"))
    print("ready in %.1f s; player %s; port %d; log %s" % (time.time() - t0, player, PORT, rt / "PhasmaEngine.log"))


DESKTOP = "undertow_live_desk"


class Proc:
    def __init__(self, pid, handle):
        self.pid, self.handle = pid, handle

    def alive(self):
        import ctypes
        code = ctypes.c_ulong()
        ctypes.windll.kernel32.GetExitCodeProcess(self.handle, ctypes.byref(code))
        return code.value == 259           # STILL_ACTIVE


def launch_hidden(argv, cwd, log_path):
    """Start the Player on its own desktop (CreateDesktop + STARTUPINFO.lpDesktop): its window can never become the
    user's foreground window or receive the user's keys, whatever the engine does with it (it maximizes on start)."""
    import ctypes
    from ctypes import wintypes
    k32, user32 = ctypes.windll.kernel32, ctypes.windll.user32
    user32.CreateDesktopW.restype = wintypes.HANDLE
    desk = user32.CreateDesktopW(DESKTOP, None, None, 0, 0x10000000, None)    # GENERIC_ALL
    if not desk:
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
    cmd = subprocess.list2cmdline(argv)
    flags = 0x00000008 | 0x00000200            # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    k32.CreateProcessW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wintypes.BOOL,
                                   wintypes.DWORD, ctypes.c_void_p, wintypes.LPCWSTR, ctypes.c_void_p, ctypes.c_void_p]
    buf = ctypes.create_unicode_buffer(cmd)
    if not k32.CreateProcessW(argv[0], buf, None, None, False, flags, None, cwd, ctypes.byref(si), ctypes.byref(pi)):
        raise SystemExit("CreateProcess failed: %d" % k32.GetLastError())
    (WORK / "desktop.txt").write_text(DESKTOP)
    return Proc(pi.dwProcessId, pi.hProcess)


def give_back_focus(fg0, pid, seconds):
    import ctypes
    from ctypes import wintypes
    user32, kernel32 = ctypes.windll.user32, ctypes.windll.kernel32
    me = kernel32.GetCurrentThreadId()
    t_end, took = time.time() + seconds, 0
    while time.time() < t_end:
        fg = user32.GetForegroundWindow()
        p = wintypes.DWORD()
        tid = user32.GetWindowThreadProcessId(fg, ctypes.byref(p))
        if fg and fg != fg0 and p.value == pid:
            took += 1
            user32.AttachThreadInput(me, tid, True)        # share the foreground thread's input state, so the call is allowed
            user32.SetForegroundWindow(fg0)
            user32.AttachThreadInput(me, tid, False)
            print("focus: the Player took the foreground; returned to %s -> %s" % (fg0, user32.GetForegroundWindow()), flush=True)
        time.sleep(0.05)
    print("focus check: Player took the foreground %d times; foreground before %s, now %s" % (took, fg0, user32.GetForegroundWindow()))


def stop():
    pid = (WORK / "pid.txt").read_text().strip() if (WORK / "pid.txt").exists() else None
    if pid:
        subprocess.run(["taskkill", "/PID", pid, "/F"], capture_output=True)
        print("stopped", pid)


def hwnd():
    """The throwaway Player's top-level window (by its PID)."""
    import ctypes
    from ctypes import wintypes
    pid = int((WORK / "pid.txt").read_text().strip())
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(h, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(h, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(h):
            c = ctypes.create_unicode_buffer(64)
            user32.GetClassNameW(h, c, 64)
            if c.value == "SDL_app":         # the game window (the process also owns IME / input-indicator windows)
                found.append(h)
        return True
    desk = None
    if (WORK / "desktop.txt").exists():
        user32.OpenDesktopW.restype = wintypes.HANDLE
        desk = user32.OpenDesktopW((WORK / "desktop.txt").read_text().strip(), 0, False, 0x10000000)
    if desk:
        user32.EnumDesktopWindows(desk, cb, 0)
        user32.CloseDesktop(desk)
    else:
        user32.EnumWindows(cb, 0)
    if not found:
        raise SystemExit("no window for pid %d" % pid)
    return found[0]


def on_desk(fn, *args):
    """Run fn on a fresh thread attached to the copy's hidden desktop (SetThreadDesktop): window calls such as
    PostMessage and SetWindowPos only work from a thread on the window's desktop."""
    import ctypes
    import threading
    from ctypes import wintypes
    out = {}
    def run():
        try:
            if (WORK / "desktop.txt").exists():
                user32 = ctypes.windll.user32
                user32.OpenDesktopW.restype = wintypes.HANDLE
                d = user32.OpenDesktopW((WORK / "desktop.txt").read_text().strip(), 0, False, 0x10000000)
                if not d or not user32.SetThreadDesktop(d):
                    raise RuntimeError("SetThreadDesktop failed: %d" % ctypes.windll.kernel32.GetLastError())
            out["r"] = fn(*args)
        except Exception as e:      # noqa: BLE001
            out["e"] = e
    t = threading.Thread(target=run)
    t.start()
    t.join()
    if "e" in out:
        raise out["e"]
    return out.get("r")


def _size(w, h):
    """Resize the throwaway Player's window so its client area is w x h, without activating it."""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    hw = hwnd()
    user32.ShowWindow(hw, 4)                            # SW_SHOWNOACTIVATE (restores, never activates)
    r = wintypes.RECT(0, 0, w, h)
    style = user32.GetWindowLongW(hw, -16)
    user32.AdjustWindowRect(ctypes.byref(r), style, False)
    user32.SetWindowPos(hw, 0, 0, 0, r.right - r.left, r.bottom - r.top, 0x0004 | 0x0010)   # NOZORDER | NOACTIVATE
    cr = wintypes.RECT()
    user32.GetClientRect(hw, ctypes.byref(cr))
    return cr.right, cr.bottom


# Scan codes (set 1) for the keys the game reads; SDL2 maps WM_KEYDOWN by the scan code in lParam bits 16-23.
VK = {"Space": (0x20, 0x39), "Escape": (0x1B, 0x01), "Return": (0x0D, 0x1C), "M": (0x4D, 0x32), "S": (0x53, 0x1F),
      "Q": (0x51, 0x10), "R": (0x52, 0x13), "G": (0x47, 0x22), "Backspace": (0x08, 0x0E)}


def _post_key(name, down):
    import ctypes
    vk, sc = VK[name]
    lp = 1 | (sc << 16) | ((0xC0000000) if not down else 0)
    ok = ctypes.windll.user32.PostMessageW(hwnd(), 0x0100 if down else 0x0101, vk, ctypes.c_ssize_t(lp))
    if not ok:
        raise RuntimeError("PostMessage failed")


def _post_mouse(x, y, what):
    """what: move | down | up (left button), at client pixel x, y."""
    import ctypes
    lp = (int(y) & 0xFFFF) << 16 | (int(x) & 0xFFFF)
    msg, wp = {"move": (0x0200, 0), "down": (0x0201, 1), "up": (0x0202, 0)}[what]
    if not ctypes.windll.user32.PostMessageW(hwnd(), msg, wp, ctypes.c_ssize_t(lp)):
        raise RuntimeError("PostMessage failed")


def size(w, h): return on_desk(_size, w, h)
def post_key(name, down): return on_desk(_post_key, name, down)
def post_mouse(x, y, what): return on_desk(_post_mouse, x, y, what)


def click(x, y):
    # Posted back to back: SDL2 answers the first move with TrackMouseEvent, and as the real cursor is elsewhere it
    # gets WM_MOUSELEAVE and resets the position to the real cursor; batched, the leave queues behind the button up.
    def batch():
        _post_mouse(x, y, "move")
        _post_mouse(x, y, "down")
        _post_mouse(x, y, "up")
    on_desk(batch)


def main():
    cmd = sys.argv[1]
    if cmd == "start":
        start()
    elif cmd == "stop":
        stop()
    elif cmd == "size":
        print(size(int(sys.argv[2]), int(sys.argv[3])))
    elif cmd == "key":
        what = sys.argv[3] if len(sys.argv) > 3 else "tap"
        if what in ("down", "tap"):
            post_key(sys.argv[2], True)
        if what == "tap":
            time.sleep(0.15)
        if what in ("up", "tap"):
            post_key(sys.argv[2], False)
    elif cmd == "click":
        click(int(sys.argv[2]), int(sys.argv[3]))
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
