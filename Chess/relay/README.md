# The relay

A ~200-line Python process that pairs two players by a six-digit code and then pipes bytes
between them. It is the only part of this game exposed to the internet, which is the reason it
is this small and this boring: it does not understand chess, and it never looks at a byte once
two players are paired.

## Put it on a box

```sh
./deploy.sh root@your.server        # copies, makes a certificate, starts it, prints the pin
```

Then paste the two lines it prints into `Assets/Scripts/chess/relay_config.lua` and export the
game. Both players need that build — the pin is baked in.

Open TCP **27600** in the provider's firewall as well as the box's own (`deploy.sh` handles
`ufw` if it is installed).

Re-running `deploy.sh` updates the code and restarts the service. It keeps the existing
certificate on purpose: a new one is a new pin, and every copy of the game with the old pin
would refuse to connect — correctly.

## Why it is safe to run

- **TLS with a pinned key.** The game checks that the server's public key hashes to exactly the
  pin in its config, before it sends anything. No certificate authority is trusted, so nobody
  can present a "valid" certificate for this address and be believed.
- **Nothing is parsed.** Two verbs (`HOST`, `JOIN`) with fixed patterns, then bytes. A relay
  that understood the game would be a second chess implementation to get wrong.
- **Bounded everywhere**: line length, hello timeout, lobby lifetime, idle timeout, bytes per
  session, lobbies at once, connections per address, and wrong-code attempts per minute
  (guessing a six-digit code at ten a minute takes about two centuries).
- **Unprivileged and confined.** `chess-relay.service` runs it as its own user with no
  capabilities, a read-only filesystem, a syscall filter, and a 128 MB cap.
- **Single use codes.** A code pairs exactly once and is then gone.

What it does NOT protect against: the relay operator. Whoever runs this machine can see the
moves — they are chess moves, and both players chose this relay.

## Check it

```sh
python test_relay.py                # pairing, and every way a stranger can misbehave at it
python ../tools/relay_harness.py    # the real game, playing through it, in both directions
```

Neither needs a server: they start a relay on 127.0.0.1 with a throwaway certificate.

## Files

| | |
|---|---|
| `relay.py` | the whole thing |
| `make_cert.sh` | self-signed certificate + the pin to paste into the game |
| `chess-relay.service` | systemd unit, hardened |
| `deploy.sh` | copy, install, start, print the pin |
| `test_relay.py` | runnable check |
