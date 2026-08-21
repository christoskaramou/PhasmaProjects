#!/usr/bin/env python3
"""Chess relay — pairs two players by a 6-digit code and then pipes bytes between them.

Why a relay at all: both players connect OUTWARD to this process, so neither opens an inbound
port and neither learns the other's IP. The relay is the only machine on the internet, which is
also why it is this small: every line here is attack surface.

What it is NOT: it does not understand chess, and it never inspects a byte once two players are
paired. Move validation lives in the game, against its own board (see MULTIPLAYER.md, "Never
trust the wire"). A relay that parsed the game would be a second implementation to get wrong.

Transport is TLS with a self-signed certificate; the game pins the public key rather than
trusting a CA (make_cert.sh prints the pin). Run:

    python3 relay.py --cert cert.pem --key key.pem
"""
import argparse
import re
import secrets
import select
import socket
import ssl
import sys
import threading
import time

MAX_LINE = 512            # one protocol line, same cap the engine's net binding enforces
MAX_SESSION_BYTES = 4 << 20  # a whole game is a few KB; this is a flood cut-off, not a budget
HELLO_TIMEOUT = 10.0      # say who you are, promptly
LOBBY_TTL = 600.0         # a lobby nobody joins in ten minutes is gone
IDLE_TIMEOUT = 120.0      # paired: the game sends a keepalive every 20s, so 2 min means gone
MAX_LOBBIES = 200
MAX_PER_IP = 8            # concurrent connections from one address
BAD_CODE_WINDOW = 60.0    # wrong-code attempts are rate-limited per address
BAD_CODE_LIMIT = 10

NAME = re.compile(r"^[A-Za-z0-9 _-]{1,32}$")
CODE = re.compile(r"^[0-9]{6}$")

lock = threading.Lock()
lobbies = {}      # code -> Lobby
per_ip = {}       # ip -> live connection count
bad_codes = {}    # ip -> [timestamps]


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


class Lobby:
    """A host waiting to be joined. The joiner hands its socket over, and the host's thread
    runs the session from there."""

    def __init__(self, code, name, sock):
        self.code = code
        self.name = name
        self.sock = sock
        self.born = time.time()
        self.joined = threading.Event()
        self.peer = None       # the joiner's socket, set exactly once
        self.peer_name = None


def send_line(sock, text):
    sock.sendall((text + "\n").encode("ascii", "replace"))


def read_line(sock, limit=MAX_LINE):
    """One newline-terminated line, or None. Bounded: a peer that never sends one is dropped."""
    buf = b""
    while b"\n" not in buf:
        if len(buf) > limit:
            return None
        try:
            chunk = sock.recv(256)
        except (socket.timeout, ssl.SSLError, OSError):
            return None
        if not chunk:
            return None
        buf += chunk
    line = buf.split(b"\n", 1)[0]
    if len(line) > limit:
        return None
    try:
        return line.decode("ascii").strip()
    except UnicodeDecodeError:
        return None


def rate_limited(ip):
    """True when this address has burned through its wrong-code attempts. Guessing a 6-digit
    code takes a million tries; ten a minute makes that about two centuries."""
    now = time.time()
    hits = [t for t in bad_codes.get(ip, []) if now - t < BAD_CODE_WINDOW]
    bad_codes[ip] = hits
    return len(hits) >= BAD_CODE_LIMIT


def note_bad_code(ip):
    bad_codes.setdefault(ip, []).append(time.time())


def new_code():
    """Unguessable, not sequential: the code IS the secret that pairs two strangers' sockets."""
    for _ in range(50):
        code = "%06d" % secrets.randbelow(1000000)
        if code not in lobbies:
            return code
    return None


def reap_lobbies():
    now = time.time()
    for code, lobby in list(lobbies.items()):
        if not lobby.joined.is_set() and now - lobby.born > LOBBY_TTL:
            del lobbies[code]
            try:
                send_line(lobby.sock, "ERR expired")
            except OSError:
                pass
            close(lobby.sock)


def close(sock):
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    try:
        sock.close()
    except OSError:
        pass


def pump(a, b, budget):
    """A paired session, both directions, in ONE thread.

    One thread per direction reads freely, but a TLS socket cannot be read by one thread while
    another writes to it — OpenSSL needs the SSL object serialised, and doing it anyway ends in
    an occasional "EOF in violation of protocol" mid-game. So a single thread owns both sockets
    and select decides who spoke. `pending()` first: select only sees the raw socket, and a TLS
    record already decrypted into the buffer would otherwise sit there unnoticed.

    Bytes only — this is where the relay stops thinking about what it is carrying.
    """
    sent = 0
    a.settimeout(5.0)
    b.settimeout(5.0)
    last = time.time()
    while time.time() - last < IDLE_TIMEOUT:
        ready = [s for s in (a, b) if s.pending()]
        if not ready:
            try:
                ready, _, _ = select.select([a, b], [], [], 1.0)
            except (OSError, ValueError):
                break
        for src in ready:
            dst = b if src is a else a
            try:
                chunk = src.recv(4096)
            except ssl.SSLWantReadError:
                continue
            except (socket.timeout, ssl.SSLError, OSError):
                chunk = b""
            if not chunk:
                close(a)
                close(b)
                return
            sent += len(chunk)
            if sent > budget:
                log("session over budget, dropping")
                close(a)
                close(b)
                return
            try:
                dst.sendall(chunk)
            except (ssl.SSLError, OSError):
                close(a)
                close(b)
                return
            last = time.time()
    close(a)
    close(b)


def handle_host(sock, ip, name):
    with lock:
        reap_lobbies()
        if len(lobbies) >= MAX_LOBBIES:
            send_line(sock, "ERR busy")
            return close(sock)
        code = new_code()
        if code is None:
            send_line(sock, "ERR busy")
            return close(sock)
        lobby = Lobby(code, name, sock)
        lobbies[code] = lobby
    send_line(sock, "CODE " + code)
    log("lobby", code, "for", repr(name), "from", ip)

    # Wait for a joiner. The socket keeps its hello timeout until then: a host that walks away
    # is a lobby that should not outlive the screen it was opened from.
    if not lobby.joined.wait(LOBBY_TTL):
        with lock:
            lobbies.pop(code, None)
        try:
            send_line(sock, "ERR expired")
        except OSError:
            pass
        return close(sock)

    try:
        # This thread runs the whole session, both directions; the joiner's thread has already
        # handed its socket over and finished.
        send_line(sock, "PAIRED " + lobby.peer_name)
        pump(sock, lobby.peer, MAX_SESSION_BYTES)
    finally:
        # BOTH sockets are this thread's from the moment the lobby was joined, and nothing else
        # will ever close them. That matters on the path where the host has already gone: the
        # PAIRED line above raises, and without this the joiner's connection would be left open
        # forever — hostable on purpose by taking a code, vanishing, then joining it yourself.
        close(sock)
        close(lobby.peer)
    log("session", code, "over")


def handle_join(sock, ip, code, name):
    with lock:
        reap_lobbies()
        lobby = lobbies.get(code)
        if lobby is None or lobby.joined.is_set():
            note_bad_code(ip)
            send_line(sock, "ERR no-such-game")
            return close(sock)
        del lobbies[code]          # single use: a code that pairs twice is a code that leaks
        lobby.peer = sock
        lobby.peer_name = name
        lobby.joined.set()
    send_line(sock, "PAIRED " + lobby.name)
    log("paired", code, repr(name), "from", ip)
    # Hand the socket to the host's thread and get out of its way -- see pump().


def serve(sock, ip):
    sock.settimeout(HELLO_TIMEOUT)
    line = read_line(sock)
    if not line:
        return close(sock)

    verb, _, rest = line.partition(" ")
    if verb == "HOST" and NAME.match(rest):
        sock.settimeout(None)
        handle_host(sock, ip, rest)
    elif verb == "JOIN":
        code, _, name = rest.partition(" ")
        if rate_limited(ip):
            send_line(sock, "ERR slow-down")
            return close(sock)
        if not CODE.match(code) or not NAME.match(name):
            note_bad_code(ip)
            send_line(sock, "ERR bad-code")
            return close(sock)
        sock.settimeout(None)
        handle_join(sock, ip, code, name)
    else:
        # Anything else at all: no negotiation, no second guess. Same rule as the game's wire.
        try:
            send_line(sock, "ERR bad-hello")
        except OSError:
            pass
        close(sock)


def wrap(client, ip, context):
    try:
        tls = context.wrap_socket(client, server_side=True)
    except (ssl.SSLError, OSError) as err:
        log("tls refused", ip, err)
        close(client)
        with lock:
            per_ip[ip] = max(0, per_ip.get(ip, 1) - 1)
        return
    try:
        serve(tls, ip)
    except Exception as err:                      # one bad session must not take the relay down
        log("session error", ip, type(err).__name__, err)
        close(tls)
    finally:
        with lock:
            per_ip[ip] = max(0, per_ip.get(ip, 1) - 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=27600)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    args = ap.parse_args()

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(args.cert, args.key)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((args.host, args.port))
    listener.listen(64)
    log("relay listening on %s:%d" % (args.host, args.port))

    while True:
        try:
            client, addr = listener.accept()
        except OSError as err:
            log("accept failed", err)
            continue
        ip = addr[0]
        with lock:
            if per_ip.get(ip, 0) >= MAX_PER_IP:
                close(client)
                continue
            per_ip[ip] = per_ip.get(ip, 0) + 1
        client.settimeout(HELLO_TIMEOUT)
        threading.Thread(target=wrap, args=(client, ip, context), daemon=True).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
