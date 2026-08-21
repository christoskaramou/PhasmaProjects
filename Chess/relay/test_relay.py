"""Runnable check for the relay: pairing, and every way a stranger can misbehave at it.

Needs no engine and no network — it starts relay.py on 127.0.0.1 with a throwaway certificate
and talks to it with plain Python sockets, which is also the only way to send the hostile cases
(our own client never would).

    python relay.py-dir/test_relay.py            # uses a temp cert, exits non-zero on failure
"""
import os
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 27699
fails = []


def ck(name, got, want):
    ok = want in str(got)
    print(("  PASS  " if ok else "  FAIL  ") + name + "  -> " + str(got) +
          ("" if ok else "   (wanted %r)" % want))
    if not ok:
        fails.append(name)


def openssl(args, stdin=None):
    return subprocess.run(["openssl"] + args, input=stdin, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, check=True).stdout


def make_cert(dirpath):
    """Same shape as make_cert.sh, driven from Python so the test needs no shell."""
    cert, key = os.path.join(dirpath, "cert.pem"), os.path.join(dirpath, "key.pem")
    openssl(["req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "2", "-nodes",
             "-keyout", key, "-out", cert, "-subj", "/CN=chess-relay"])
    pub = openssl(["x509", "-in", cert, "-pubkey", "-noout"])
    der = openssl(["pkey", "-pubin", "-outform", "der"], stdin=pub)
    digest = openssl(["dgst", "-sha256", "-binary"], stdin=der)
    return cert, key, openssl(["base64"], stdin=digest).decode().strip()


def connect(timeout=5):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE     # the game pins the key instead; see relay_config.lua
    raw = socket.create_connection(("127.0.0.1", PORT), timeout=timeout)
    return ctx.wrap_socket(raw, server_hostname="chess-relay")


def line(sock, timeout=5):
    sock.settimeout(timeout)
    buf = b""
    try:
        while b"\n" not in buf:
            chunk = sock.recv(128)
            if not chunk:
                return ""
            buf += chunk
    except (socket.timeout, OSError):
        return ""
    return buf.split(b"\n", 1)[0].decode(errors="replace")


def main():
    tmp = tempfile.mkdtemp(prefix="chessrelay")
    cert, key, pin = make_cert(tmp)
    relay = subprocess.Popen([sys.executable, os.path.join(HERE, "relay.py"),
                              "--port", str(PORT), "--cert", cert, "--key", key],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    time.sleep(1.2)
    try:
        # ── the happy path: a code, a join, and bytes in both directions
        host = connect()
        host.sendall(b"HOST Host\n")
        reply = line(host)
        ck("hosting returns a code", reply, "CODE ")
        code = reply.split(" ")[1]
        ck("the code is six digits", str(len(code)) + "/" + str(code.isdigit()), "6/True")

        guest = connect()
        guest.sendall(("JOIN %s Guest\n" % code).encode())
        ck("the joiner is paired", line(guest), "PAIRED Host")
        ck("and so is the host", line(host), "PAIRED Guest")

        guest.sendall(b"M e2e4\n")
        ck("guest -> host", line(host), "M e2e4")
        host.sendall(b"M e7e5\n")
        ck("host -> guest", line(guest), "M e7e5")

        # The relay must not understand any of it: an unknown verb is the game's problem,
        # and the relay forwarding it unchanged is the proof.
        guest.sendall(b"NONSENSE 1 2 3\n")
        ck("the relay forwards what it does not understand", line(host), "NONSENSE 1 2 3")

        # ── a used code is gone
        late = connect()
        late.sendall(("JOIN %s Late\n" % code).encode())
        ck("a code pairs exactly once", line(late), "ERR no-such-game")
        late.close()

        # ── one side leaving closes the other
        guest.close()
        ck("the peer's socket closes with it", line(host, timeout=8), "")
        host.close()

        # ── the ghost host: take a code, vanish, then join it yourself. Only the host's own
        # thread ever owns the joiner's socket, so if it leaves without closing it — the PAIRED
        # write to a dead socket can raise — that connection leaks, repeatably and for free.
        # This walks the path; the `finally` in handle_host is what makes every ordering safe.
        ghost = connect()
        ghost.sendall(b"HOST Ghost\n")
        ghost_code = line(ghost).split(" ")[1]
        ghost.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                         struct.pack("hh" if os.name == "nt" else "ii", 1, 0))  # close = RST
        ghost.close()
        time.sleep(0.3)
        orphan = connect()
        orphan.sendall(("JOIN %s Orphan\n" % ghost_code).encode())
        line(orphan)                        # PAIRED, from a host that is already gone
        ck("a joiner is not left hanging by a vanished host", line(orphan, timeout=8), "")
        orphan.close()

        # ── hostile hellos
        bad = connect()
        bad.sendall(b"HELLO there\n")
        ck("an unknown hello is refused", line(bad), "ERR bad-hello")
        bad.close()

        bad = connect()
        bad.sendall(b"HOST ../../etc/passwd\n")
        ck("a name outside the alphabet is refused", line(bad), "ERR bad-hello")
        bad.close()

        bad = connect()
        bad.sendall(b"JOIN abcdef Guest\n")
        ck("a malformed code is refused", line(bad), "ERR bad-code")
        bad.close()

        # A peer that never sends a newline must be dropped, not buffered forever.
        flood = connect()
        flood.sendall(b"x" * 9000)
        ck("a flood with no newline is dropped", line(flood, timeout=8), "")
        flood.close()

        # ── guessing is rate-limited: ten wrong codes, then the door shuts for a minute
        for _ in range(10):
            s = connect()
            s.sendall(b"JOIN 000000 Guesser\n")
            line(s)
            s.close()
        s = connect()
        s.sendall(b"JOIN 000000 Guesser\n")
        ck("wrong codes are rate-limited", line(s), "ERR slow-down")
        s.close()

        # ── the pin the game will check is the one make_cert printed
        probe = connect()
        der = probe.getpeercert(binary_form=True)
        probe.close()
        got = openssl(["base64"], stdin=openssl(
            ["dgst", "-sha256", "-binary"], stdin=openssl(
                ["pkey", "-pubin", "-outform", "der"], stdin=openssl(
                    ["x509", "-inform", "der", "-pubkey", "-noout"], stdin=der)))).decode().strip()
        ck("the served key matches the printed pin", got, pin)
    finally:
        relay.terminate()

    print("\nFAILURES: " + (", ".join(fails) if fails else "none"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
