"""Play a whole internet game against the real relay, on this machine.

Starts relay.py on 127.0.0.1 with a throwaway certificate, points the game at it (relay_config.lua
is rewritten and restored), relaunches the player, and then plays the opponent from Python over a
TLS socket — including the cases our own client would never send.

The pin is the point of the exercise: the game must refuse a relay whose key does not match, and
that check has to happen before a single byte of the game protocol moves.

    python tools/relay_harness.py
"""
import json
import os
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "relay"))
from test_relay import make_cert  # noqa: E402  (same cert recipe as the relay's own check)

URL = "http://127.0.0.1:8765/tool"
PORT = 27698
CONFIG = os.path.join(ROOT, "Assets", "Scripts", "chess", "relay_config.lua")
fails = []


def lua(code):
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps({"name": "execute_lua", "arguments": {"code": code}}).encode(),
        headers={"Content-Type": "application/json"}), timeout=30).read().decode())
    if r.get("isError"):
        raise SystemExit(json.dumps(r)[:600])
    return (r.get("structuredContent") or {}).get("output", "")


def ck(name, got, want):
    ok = want in str(got)
    print(("  PASS  " if ok else "  FAIL  ") + name + "  -> " + str(got) +
          ("" if ok else "   (wanted %r)" % want))
    if not ok:
        fails.append(name)


INSTALL = """
if not _G.__mc then
    _G.__mc = {real = runtime_ui.get_state, id = nil}
    runtime_ui.get_state = function(screen, id)
        local st = _G.__mc.real(screen, id) or {}
        if _G.__mc.id == id then _G.__mc.id = nil st.clicked = true end
        return st
    end
end
return "installed"
"""
RESTORE = 'if _G.__mc then runtime_ui.get_state = _G.__mc.real _G.__mc = nil end return "restored"'


def click(row_id):
    return lua('_G.__mc.id = "%s" script.chess.tick() return "ok"' % row_id)


def status(field):
    return lua("local s = script.chess.status() "
               "local ok, v = pcall(function() return s.%s end) "
               "return tostring(ok and v or false)" % field)


def wait_status(field, want, timeout=12.0):
    end = time.time() + timeout
    while time.time() < end:
        v = status(field)
        if want in v:
            return v
        time.sleep(0.3)
    return status(field)


def peer_connect(timeout=6):
    """A second player, from Python. Verification off here for the same reason the game turns it
    off: the certificate is self-signed and the PIN is what decides — checked separately below."""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx.wrap_socket(socket.create_connection(("127.0.0.1", PORT), timeout=timeout),
                           server_hostname="chess-relay")


def line(sock, timeout=6):
    """One line, keepalives skipped — a real client ignores them and so must the test."""
    while True:
        got = raw_line(sock, timeout)
        if got != "PING":
            return got


def raw_line(sock, timeout=6):
    sock.settimeout(timeout)
    buf = b""
    try:
        while b"\n" not in buf:
            chunk = sock.recv(256)
            if not chunk:
                return ""
            buf += chunk
    except (socket.timeout, OSError):
        return ""
    return buf.split(b"\n", 1)[0].decode(errors="replace")


def write_config(host, port, pin):
    with open(CONFIG, "w", encoding="utf-8") as f:
        f.write('-- written by tools/relay_harness.py; the real one is restored when it exits\n'
                'return {\n    host = "%s",\n    port = %d,\n    pin = "%s",\n}\n'
                % (host, port, pin))


def relaunch():
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-File", os.path.join(ROOT, "run_smoke.ps1")],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def main():
    saved = open(CONFIG, "r", encoding="utf-8").read()
    tmp = os.path.join(os.environ.get("TEMP", "."), "chessrelayharness")
    os.makedirs(tmp, exist_ok=True)
    cert, key, pin = make_cert(tmp)
    relay = subprocess.Popen([sys.executable, os.path.join(ROOT, "relay", "relay.py"),
                              "--port", str(PORT), "--cert", cert, "--key", key],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.0)
    try:
        write_config("127.0.0.1", PORT, pin)
        print("relaunching the player against the test relay ...")
        relaunch()
        lua(INSTALL)

        # ── the pin, on its own, before any game is involved
        def dial(the_pin):
            lua('net.close() net.join("127.0.0.1", %d, {pin = "%s"})' % (PORT, the_pin))
            end = time.time() + 8
            while time.time() < end:
                st = lua("return net.status()")
                if st != "connecting":
                    return st
                time.sleep(0.2)
            return "connecting"

        ck("a pinned link comes up", dial(pin), "connected")
        ck("and a wrong pin does not", dial("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="), "idle")
        ck("and says why", lua("return net.last_error()"), "does not match the pin")
        lua("net.close()")

        # ── the game hosts: relay hands out a code, we join it from Python
        lua('script.chess.menu("title")')
        time.sleep(0.3)
        click("m_play")
        click("m_pvp")
        click("m_create")
        code = wait_status("lan.code", "0")
        ck("creating a game returns a code", str(len(code)) + "/" + str(code.isdigit()), "6/True")

        peer = peer_connect()
        peer.sendall(("JOIN %s Kostas\n" % code).encode())
        ck("the relay pairs us", line(peer), "PAIRED")
        peer.sendall(b"PC2 4242 Kostas\n")
        ck("the game answers the hello", line(peer), "OK ")
        ck("and the game is on", wait_status("online", "host"), "host")
        ck("we are White as the creator", status("color"), "W")
        ck("the opponent badge names them", status("peer.name"), "Kostas")

        lua('script.chess.move("e2e4")')
        ck("our move reaches them", line(peer), "M e2e4")
        peer.sendall(b"M e7e5\n")
        ck("their move lands on our board", wait_status("moves", "2"), "2")

        # A keepalive must be a no-op, not an unknown verb: unknown verbs drop the link.
        peer.sendall(b"PING\n")
        time.sleep(0.6)
        ck("a keepalive does not drop the link", status("online"), "host")

        # And one must actually be SENT: two players thinking send nothing for minutes, which
        # a NAT or the relay's idle timer reads as a dead link. Worth 20 slow seconds to prove.
        ck("the game sends its own keepalive", raw_line(peer, timeout=25), "PING")

        peer.close()
        time.sleep(1.2)
        ck("losing the relay link ends the session", wait_status("online", "false"), "false")

        # ── the other direction: Python hosts, the game joins by tapping the code in
        host = peer_connect()
        host.sendall(b"HOST Kostas\n")
        their_code = line(host).split(" ")[1]
        lua('script.chess.menu("title")')
        time.sleep(0.3)
        click("m_play")
        click("m_pvp")
        click("m_join_code")
        for digit in their_code:
            click("m_k" + digit)
        click("m_kjoin")
        ck("the code we tapped is the one we joined", wait_status("lan.code", their_code), their_code)
        ck("the relay pairs them too", line(host), "PAIRED")
        ck("the joiner says hello", line(host), "PC2 ")
        host.sendall(b"OK 4242 Kostas\n")
        ck("the game starts as guest", wait_status("online", "guest"), "guest")
        ck("and plays Black", status("color"), "B")
        host.sendall(b"M d2d4\n")
        ck("their first move arrives", wait_status("moves", "1"), "1")
        host.close()

        # ── a code that pairs with nothing
        time.sleep(1.0)
        lua('script.chess.menu("title")')
        time.sleep(0.3)
        click("m_play")
        click("m_pvp")
        click("m_join_code")
        for digit in "000000":
            click("m_k" + digit)
        click("m_kjoin")
        time.sleep(1.5)
        ck("a dead code says so", wait_status("lan.note", "No game"), "No game with that code")
        lua(RESTORE)
    finally:
        relay.terminate()
        with open(CONFIG, "w", encoding="utf-8") as f:
            f.write(saved)
        shutil.rmtree(tmp, ignore_errors=True)

    # Restoring relay_config.lua is a .lua write, and any project .lua write reloads the whole
    # ScriptSystem: the running player's `script.chess` is gone by now. Run this harness LAST,
    # or relaunch the player before the others.
    print("player scripts were reloaded by the config restore - relaunch before other harnesses")
    print("\nFAILURES: " + (", ".join(fails) if fails else "none"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
