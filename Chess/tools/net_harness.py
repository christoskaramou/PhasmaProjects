"""Play the opponent from Python so the LAN link can be tested with one game running.

Two instances of the player cannot share a machine for this (the MCP server binds a single
port), so the second player here is a plain socket: it connects to the game's listener, or
listens for the game to join it, and speaks the same line protocol. That also makes the
hostile-peer cases testable, which a second copy of our own client never would be.
"""
import json
import socket
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8765/tool"
PORT = 27500
DISCO = 27501


def lua(code):
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        URL, data=json.dumps({"name": "execute_lua", "arguments": {"code": code}}).encode(),
        headers={"Content-Type": "application/json"}), timeout=30).read().decode())
    if r.get("isError"):
        raise SystemExit(json.dumps(r)[:600])
    return (r.get("structuredContent") or {}).get("output", "")


# The menu rows are real runtime_ui buttons, so a lobby is created the way a player creates
# one: get_state is wrapped to report `clicked` for one id for one frame. The OS cursor is
# never touched. (Same shim as menu_harness.py; each harness stands alone on purpose.)
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
    return lua('_G.__mc.id = "%s" script.chess.tick() '
               'return tostring(script.chess.status().menu_page)' % row_id)


def status(field):
    return lua("local s = script.chess.status() return tostring(s.%s)" % field)


def open_lobby():
    """Title -> Play -> Player vs Player -> Create Lobby, through the real rows."""
    lua('script.chess.menu("title")')
    time.sleep(0.3)
    click("m_play")
    click("m_pvp")
    click("m_create")
    time.sleep(0.4)


def handshake(sock, hello=b"PC1 4242 Harness\n"):
    sock.sendall(hello)
    sock.settimeout(3)
    return sock.recv(64).decode().strip()


fails = []


def ck(name, got, want):
    ok = want in got
    print(("  PASS  " if ok else "  FAIL  ") + name + "  -> " + str(got) +
          ("" if ok else "   (wanted %r)" % want))
    if not ok:
        fails.append(name)


def wait_status(want, timeout=3.0):
    """Poll net.status() until it reads `want`. connect finishes over later frames."""
    end = time.time() + timeout
    while time.time() < end:
        s = lua("return net.status()")
        if s == want:
            return s
        time.sleep(0.1)
    return lua("return net.status()")


def read_line(timeout=3.0):
    end = time.time() + timeout
    while time.time() < end:
        line = lua('local l = net.read_line() return l and l or ""')
        if line:
            return line
        time.sleep(0.1)
    return ""


lua("net.close() net.discover_stop()")
try:
    # ── the game hosts, we join
    ck("host", lua('local ok, err = net.host(%d) return tostring(ok) .. "/" .. tostring(err)' % PORT),
       "true/nil")
    ck("listening before anyone joins", lua("return net.status()"), "listening")
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    ck("accept", lua("return tostring(net.accept())"), "true")
    ck("connected", lua("return net.status()"), "connected")

    peer.sendall(b"M e2e4\n")
    ck("inbound line", read_line(), "M e2e4")
    lua('net.send("M e7e5")')
    peer.settimeout(3)
    ck("outbound line", peer.recv(64).decode().strip(), "M e7e5")

    # Two lines in one packet must come back as two reads, not one.
    peer.sendall(b"M g1f3\nM b8c6\n")
    ck("first of a batched pair", read_line(), "M g1f3")
    ck("second of a batched pair", read_line(), "M b8c6")

    # ── hostile peer: no newline, ever. The link must drop instead of buffering forever.
    peer.sendall(b"x" * 9000)
    time.sleep(0.3)
    lua("net.read_line()")
    ck("flood with no newline drops the link", wait_status("idle"), "idle")
    peer.close()

    # ── the game joins us
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen(1)
    ck("join", lua('local ok, err = net.join("127.0.0.1", %d) return tostring(ok) .. "/" .. tostring(err)'
                   % PORT), "true/nil")
    conn, _ = server.accept()
    ck("connect completes on a later frame", wait_status("connected"), "connected")
    lua('net.send("PC1 harness")')
    conn.settimeout(3)
    ck("handshake reaches us", conn.recv(64).decode().strip(), "PC1 harness")
    conn.close()
    server.close()
    ck("peer hangup ends the link", wait_status("idle"), "idle")

    # ── an unreachable host must fail without stalling the frame
    t0 = time.time()
    lua('net.join("127.0.0.1", 27599)')
    ck("connect to a closed port does not block", "%.2fs" % (time.time() - t0),
       "0.0" if time.time() - t0 < 1.0 else "SLOW")
    ck("and settles as idle", wait_status("idle"), "idle")

    # ── discovery both ways
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    udp.bind(("", DISCO))
    udp.settimeout(3)
    ck("advertise", lua("return tostring(net.advertise(%d, 'PC1 Chess|Christos'))" % DISCO), "true")
    ck("beacon reaches the LAN", udp.recvfrom(256)[0].decode(), "PC1 Chess|Christos")

    lua("return tostring(net.discover(%d))" % DISCO)
    udp.sendto(b"PC1 Chess|peer", ("255.255.255.255", DISCO))
    time.sleep(0.4)
    # A broadcast loops back to every socket bound to the port INCLUDING the sender, so our own
    # beacons come back too. Drain until the peer's shows up -- filtering self is the caller's
    # job (the lobby ignores its own id), and this mirrors what the lobby does each frame.
    seen = []
    for _ in range(20):
        got = lua('local t, ip = net.poll_discover() return tostring(t) .. "|" .. tostring(ip)')
        if got.startswith("nil"):
            break
        seen.append(got)
    ck("beacon from the LAN is seen", " ".join(seen), "PC1 Chess|peer|")
    # Our own beacon comes back with the SAME source address as the peer's (both left this
    # machine), so a lobby cannot filter itself by IP -- it has to filter on an id in the
    # payload. The address that arrives is the LAN one, which is what you then net.join.
    ck("our own beacon loops back too", " ".join(seen), "PC1 Chess|Christos|")
    ck("beacons carry a routable address, not loopback",
       "lan" if seen and seen[0].split("|")[-1].count(".") == 3 else " ".join(seen), "lan")
    udp.close()
    # ── the lobby, driven through the real menu rows
    lua(INSTALL)
    open_lobby()
    ck("Create Lobby opens a listener", lua("return net.status()"), "listening")
    ck("and says so on the page", status("lan.note"), "Waiting")

    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    ck("host answers the handshake", handshake(peer), "OK ")
    time.sleep(0.6)
    ck("the game starts as host", status("online"), "host")
    ck("with a fresh board", status("moves"), "0")
    ck("and no menu in the way", status("menu"), "false")

    # ── a real exchange
    lua('script.chess.move("e2e4")')
    ck("our move reaches the opponent", peer.recv(64).decode().strip(), "M e2e4")
    peer.sendall(b"M e7e5\n")
    time.sleep(0.5)
    ck("their move lands on our board", status("moves"), "2")

    # ── the peer moves OUR pieces: legal chess, but not theirs to play
    peer.sendall(b"M g1f3\n")
    time.sleep(0.5)
    ck("a move for our side is refused", status("online"), "false")
    ck("and the link is gone", lua("return net.status()"), "idle")
    peer.close()

    # ── an illegal move
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.6)
    peer.sendall(b"M e7e5\n")  # black pawn two squares, but White is to move
    time.sleep(0.5)
    ck("an illegal move drops the link", status("online"), "false")
    peer.close()

    # ── garbage that is not the protocol at all
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.6)
    peer.sendall(b"scene.load_model_async('x')\n")
    time.sleep(0.5)
    ck("an unknown verb drops the link", status("online"), "false")
    peer.close()

    # ── resignation travels
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.6)
    peer.sendall(b"RESIGN\n")
    time.sleep(0.5)
    ck("the opponent resigning ends the game", status("result"), "wins by resignation")
    peer.close()

    # ── the lobby is discoverable, in the format the browser parses
    open_lobby()
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp.bind(("", DISCO))
    udp.settimeout(3)
    ck("the lobby beacons itself", udp.recvfrom(256)[0].decode(), "PC1|")
    udp.close()
    # Walking away from the lobby screens must take the lobby with it, or the game keeps
    # advertising and answering from a menu the player has left.
    click("m_back")
    click("m_back")
    time.sleep(0.3)
    ck("leaving the page closes the lobby", lua("return net.status()"), "idle")
    ck("and clears the note", status("lan.note"), "false")
    lua('script.chess.menu("title")')
    print(lua(RESTORE))
finally:
    print(lua("net.close() net.discover_stop() return 'closed'"))

print("\nFAILURES: " + (", ".join(fails) if fails else "none"))
sys.exit(1 if fails else 0)
