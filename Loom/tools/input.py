"""Real input for the throwaway Player, posted only to its own window (PostMessage to its HWND, found by the copy's
PID). No SendInput, no focus change, nothing reaches the desktop or the foreground window.

    from input import Win; w = Win(pid); w.key("Space"); w.click(x, y)

SDL2's window procedure turns WM_KEYDOWN / WM_KEYUP (scan code in lParam) into its keyboard state, which the game
polls (input.is_key_down_raw -> SDL_GetKeyboardState), and WM_MOUSEMOVE / WM_LBUTTON* into mouse events.
"""
import ctypes
import time
from ctypes import wintypes

user32 = ctypes.windll.user32
WM_KEYDOWN, WM_KEYUP = 0x0100, 0x0101
WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP = 0x0200, 0x0201, 0x0202
MK_LBUTTON = 0x0001
MAPVK_VK_TO_VSC = 0
VK = {"Escape": 0x1B, "Return": 0x0D, "Space": 0x20, "Backspace": 0x08, "Left": 0x25, "Right": 0x27, "Up": 0x26, "Down": 0x28,
      "A": 0x41, "D": 0x44, "M": 0x4D, "Q": 0x51, "R": 0x52, "S": 0x53}
for _d in "123456789":
    VK[_d] = ord(_d)
EXTENDED = {"Left", "Right", "Up", "Down"}
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostMessageW.restype = wintypes.BOOL


def find_window(pid):
    """The copy's game window on its hidden desktop; this thread joins that desktop so PostMessage reaches it."""
    import live
    return live.game_window(pid)


class Win:
    def __init__(self, pid):
        self.pid, self.hwnd = pid, find_window(pid)
        self.sent = 0

    def _post(self, msg, wp, lp):
        if not user32.PostMessageW(self.hwnd, msg, wp, lp):
            raise RuntimeError("PostMessage failed")
        self.sent += 1

    def down(self, name):
        vk = VK[name]
        sc = user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC)
        ext = (1 << 24) if name in EXTENDED else 0
        self._post(WM_KEYDOWN, vk, 1 | (sc << 16) | ext)

    def up(self, name):
        vk = VK[name]
        sc = user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC)
        ext = (1 << 24) if name in EXTENDED else 0
        self._post(WM_KEYUP, vk, 1 | (sc << 16) | ext | (1 << 30) | (1 << 31))

    def key(self, name, hold=0.07):
        vk = VK[name]
        sc = user32.MapVirtualKeyW(vk, MAPVK_VK_TO_VSC)
        ext = (1 << 24) if name in EXTENDED else 0
        down = 1 | (sc << 16) | ext
        up = 1 | (sc << 16) | ext | (1 << 30) | (1 << 31)
        self._post(WM_KEYDOWN, vk, down)
        time.sleep(hold)                     # the game polls key state once per frame: hold it for a few frames
        self._post(WM_KEYUP, vk, up)
        time.sleep(0.05)

    def click(self, x, y):
        """x, y in the window's client pixels. Move, press and release are queued together: posted to an unfocused
        window, a lone move is followed by Windows' own WM_MOUSELEAVE (the real cursor is elsewhere), which clears the
        UI's pointer before a later press could land; queued together, the UI sees the pointer, the press and the
        release in order (measured: separate posts never clicked, the burst always did)."""
        lp = (int(y) << 16) | (int(x) & 0xFFFF)
        self._post(WM_MOUSEMOVE, 0, lp)
        self._post(WM_LBUTTONDOWN, MK_LBUTTON, lp)
        self._post(WM_LBUTTONUP, 0, lp)
        time.sleep(0.25)

    def foreground_is_mine(self):
        """Read on a fresh thread: this one sits on the copy's hidden desktop, where GetForegroundWindow returns 0
        (measured); a new thread starts on the process's own desktop, the user's, and sees the real foreground."""
        import threading
        out = []

        def look():
            p = wintypes.DWORD()
            user32.GetWindowThreadProcessId(user32.GetForegroundWindow(), ctypes.byref(p))
            out.append(p.value == self.pid)
        t = threading.Thread(target=look)
        t.start()
        t.join()
        return out[0]
