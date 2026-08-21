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


# Existence has to be asked of the REAL get_state: the click shim below returns {} for every id.
def exists_now(widget_id):
    return lua('return tostring(_G.__mc.real("chess", "%s") ~= nil)' % widget_id).capitalize()


def status(field):
    # pcall: a nested field like peer.name is asked of `false` when there is no peer, and the
    # answer to "is there an opponent" should be "false", not a Lua error.
    return lua("local s = script.chess.status() "
               "local ok, v = pcall(function() return s.%s end) "
               "return tostring(ok and v or false)" % field)


_bufs = {}


def peer_line(sock, timeout=3.0):
    """One line from the game, keepalives skipped — a real client ignores PING and so must this."""
    sock.settimeout(timeout)
    buf = _bufs.get(id(sock), b"")
    while True:
        while b"\n" not in buf:
            try:
                chunk = sock.recv(256)
            except (socket.timeout, OSError):
                _bufs[id(sock)] = buf
                return ""
            if not chunk:
                _bufs[id(sock)] = buf
                return ""
            buf += chunk
        text, _, buf = buf.partition(b"\n")
        _bufs[id(sock)] = buf
        text = text.decode(errors="replace").strip()
        if text != "PING":
            return text


def ms(side):
    v = status("clock." + side)
    return float(v) if v not in ("false", "") else -1.0


def open_lobby():
    """Title -> Play -> Player vs Player -> Games on this Network -> Host, through the real rows.

    Hosting on the LAN moved onto the browse page when Create Game became the internet one: a
    beacon and a relay code are different ways to be found, and the menu says which is which."""
    lua('script.chess.menu("title")')
    time.sleep(0.3)
    click("m_play")
    click("m_pvp")
    click("m_join")
    click("m_lan_host")
    time.sleep(0.4)


def handshake(sock, hello=b"PC2 4242 Harness\n"):
    sock.sendall(hello)
    sock.settimeout(3)
    return peer_line(sock)


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
    ck("outbound line", peer_line(peer), "M e7e5")

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
    lua('net.send("PC2 harness")')
    conn.settimeout(3)
    ck("handshake reaches us", peer_line(conn), "PC2 harness")
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
    ck("advertise", lua("return tostring(net.advertise(%d, 'PC2 Chess|Christos'))" % DISCO), "true")
    ck("beacon reaches the LAN", udp.recvfrom(256)[0].decode(), "PC2 Chess|Christos")

    lua("return tostring(net.discover(%d))" % DISCO)
    udp.sendto(b"PC2 Chess|peer", ("255.255.255.255", DISCO))
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
    ck("beacon from the LAN is seen", " ".join(seen), "PC2 Chess|peer|")
    # Our own beacon comes back with the SAME source address as the peer's (both left this
    # machine), so a lobby cannot filter itself by IP -- it has to filter on an id in the
    # payload. The address that arrives is the LAN one, which is what you then net.join.
    ck("our own beacon loops back too", " ".join(seen), "PC2 Chess|Christos|")
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
    ck("our move reaches the opponent", peer_line(peer), "M e2e4")
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

    # ── the pause card in an online game is a GAME card, not the analysis one
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.8)
    ck("online is not an analysis board", status("analysis"), "false")
    ck("the opponent badge names them", status("peer.name"), "Harness")
    ck("and shows them connected", status("peer.live"), "true")
    lua('script.chess.menu("pause")')
    time.sleep(0.3)
    ck("pause offers Resign", exists_now("menu_pause_resign"), "True")
    ck("pause offers a draw", exists_now("menu_pause_draw"), "True")
    ck("and is not the analysis card", exists_now("menu_pause_reset"), "False")

    # ── a draw is offered, not taken
    click("menu_pause_draw")
    ck("offering a draw asks them", peer_line(peer), "DRAW")
    ck("and does not end the game", status("result"), "false")
    peer.sendall(b"DRAW_NO\n")
    time.sleep(0.5)
    ck("a declined draw leaves the game running", status("result"), "false")
    peer.sendall(b"DRAW\n")
    time.sleep(0.6)
    ck("their offer does NOT take the screen", status("menu"), "false")
    ck("it asks from the side instead", exists_now("off_yes"), "True")
    ck("and knows what it is asking", status("offer_in"), "draw")
    click("off_yes")
    ck("accepting answers them", peer_line(peer), "DRAW_OK")
    time.sleep(0.4)
    ck("and agrees the draw here", status("result"), "Draw - agreed")

    # ── takeback, both boards undoing the same plies
    peer.sendall(b"REMATCH\n")
    time.sleep(0.5)
    click("menu_end_rematch")
    peer_line(peer)
    time.sleep(1.2)
    lua('script.chess.move("e2e4")')
    time.sleep(0.5)
    peer_line(peer)
    ck("a move was played", status("moves"), "1")
    lua('script.chess.menu("pause")')
    time.sleep(0.3)
    click("menu_pause_takeback")
    ck("takeback is offered", peer_line(peer), "TAKEBACK")
    ck("and the board has not moved yet", status("moves"), "1")
    peer.sendall(b"TAKEBACK_OK\n")
    time.sleep(0.6)
    ck("their acceptance undoes it", status("moves"), "0")

    # ── a dropped opponent stays on screen, greyed
    peer.close()
    time.sleep(1.0)
    ck("the badge survives the disconnect", status("peer.name"), "Harness")
    ck("but the dot goes grey", status("peer.live"), "false")

    # ── rematch: neither side may restart alone
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.6)
    ck("we are White as host", status("color"), "W")
    peer.sendall(b"RESIGN\n")
    time.sleep(2.6)
    ck("end card is up", status("menu"), "end")

    click("menu_end_rematch")
    ck("clicking Rematch asks the opponent", peer_line(peer), "REMATCH")
    ck("and waits instead of restarting", status("rematch"), "sent")
    ck("the finished game is still on screen", status("result"), "wins by resignation")

    peer.sendall(b"REMATCH_OK\n")
    time.sleep(1.5)
    ck("their acceptance starts the new game", status("moves"), "0")
    ck("the link survived it", status("online"), "host")
    ck("and colours swapped", status("color"), "B")

    # ── the other direction: they ask, we accept
    peer.sendall(b"RESIGN\n")
    time.sleep(2.6)
    peer.sendall(b"REMATCH\n")
    time.sleep(0.5)
    ck("their offer turns the button into an acceptance", status("rematch"), "offered")
    click("menu_end_rematch")
    ck("accepting answers them", peer_line(peer), "REMATCH_OK")
    time.sleep(1.0)
    ck("and starts the game here too", status("moves"), "0")
    ck("colours swapped back", status("color"), "W")
    peer.close()
    time.sleep(0.5)

    # -- the clock does not stop for a card. A local overlay cannot stop the opponent's copy
    # of our clock, so the two boards would disagree about who flagged.
    peer.close()
    lua("script.chess.new_game{clock_min = 1}")
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.8)
    lua('script.chess.move("e2e4")')
    peer_line(peer)
    peer.sendall(b"M e7e5\n")
    time.sleep(0.7)
    ck("it is our move again", status("turn"), "W")
    lua('script.chess.menu("pause")')
    time.sleep(0.3)
    t0 = ms("w")
    time.sleep(1.2)
    ck("the clock burns behind the pause card", str(t0 - ms("w") > 700), "True")

    click("menu_pause_resume")
    peer.sendall(b"DRAW\n")
    time.sleep(0.7)
    ck("their offer is a side prompt, not a card", status("menu"), "false")
    ck("and the board is still playable behind it", status("offer_in"), "draw")
    t0 = ms("w")
    time.sleep(1.2)
    ck("the clock runs while they wait for an answer", str(t0 - ms("w") > 700), "True")
    click("off_no")
    peer_line(peer)

    # Rewinding is the other way to stop a clock -- and a move off the wire would then be
    # checked against, and truncate, the position we rewound to.
    # A row that is not drawn never asks get_state, so the injected click is never
    # consumed -- which is how "this button is gone" is proved without reading pixels
    # (a hidden quad still answers get_state, so existence proves nothing here).
    pend = '_G.__mc.id = "%s" script.chess.tick() return tostring(_G.__mc.id)'
    ck("the review transport is not drawn", lua(pend % "mv_start"), "mv_start")
    ck("while the panel around it is", lua(pend % "mv_bg"), "nil")
    lua("script.chess.goto_ply(0)")
    time.sleep(0.3)
    ck("and a rewind is refused", status("ply"), "2")

    # -- flagging behind the card ends the game there, on the end card
    peer.close()
    lua("script.chess.new_game{clock_min = 0.05}")
    open_lobby()
    peer = socket.create_connection(("127.0.0.1", PORT), timeout=3)
    handshake(peer)
    time.sleep(0.8)
    lua('script.chess.move("e2e4")')
    peer_line(peer)
    peer.sendall(b"M e7e5\n")
    time.sleep(0.4)
    lua('script.chess.menu("pause")')
    time.sleep(3.5)
    ck("our clock flagged behind the card", status("result"), "Black wins on time")
    ck("and the end card took over", status("menu"), "end")
    peer.close()
    time.sleep(0.4)

    # -- offline, a pause is still a pause: there is nobody else's clock to disagree with.
    lua('script.chess.new_game{side = "hotseat", clock_min = 1}')
    time.sleep(0.8)
    lua('script.chess.move("e2e4")')
    time.sleep(0.5)
    lua('script.chess.menu("pause")')
    time.sleep(0.3)
    t0 = ms("b")
    time.sleep(1.2)
    ck("offline the card still stops the clock", str(ms("b") == t0), "True")
    lua("script.chess.new_game{}")
    time.sleep(0.6)

    # ── the lobby is discoverable, in the format the browser parses
    open_lobby()
    udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp.bind(("", DISCO))
    udp.settimeout(3)
    ck("the lobby beacons itself", udp.recvfrom(256)[0].decode(), "PC2|")
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
