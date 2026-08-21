# Online play

**Decided 2026-08-20; LAN play and internet play are both built.** The routes below are kept as
the record of why.

- **Transport: an engine binding, not a sidecar.** `Phasma/Runtime/Code/Script/Bindings/Net/NetBindings.cpp`
  gives Lua one TCP link and UDP broadcast. Route E (a helper exe over `proc`) was rejected on
  the facts: `proc` holds one child process-wide, so an online game would have had no hint and
  no eval; a sidecar has to be built and shipped per platform, Android included; and proc-lift
  plus a helper plus a second line protocol is more machinery than the binding.
- **Internet play goes through a relay we run** (route A below), and the game **pins its public
  key**: TLS, but no certificate authority is trusted — the server's key must hash to exactly the
  pin baked into `Assets/Scripts/chess/relay_config.lua` or nothing is sent. The relay itself is
  in `relay/`; `relay/deploy.sh` puts it on a box and prints the pin.
- **The same game protocol runs over both.** LAN and relay differ only in how the two sockets
  find each other: a beacon on one, a six-digit code on the other. Everything above that — the
  hello, moves, offers, rematch, keepalive — is identical, and so is the validation.
- **Friends-only, anonymous.** No accounts, no matchmaking. The display name is generated
  (`Player 4821`) because runtime_ui has no text entry — see below, it decides the whole UX.

## What is built

`Assets/Scripts/chess/lan.lua` over the `net` binding:

- **Create Game** dials the relay and comes back with a six-digit code to read out to a friend;
  **Join with a Code** taps one in on a keypad (runtime_ui has no text entry, so a code is
  tapped, not typed). Codes are single use and expire after ten minutes.
- **Games on this Network** is the LAN path: **Host on this Network** opens a listener on TCP
  27500 and broadcasts `PC2|<id>|<name>` on UDP 27501 about once a second, and the list below it
  shows what is heard. Leaving those screens closes the lobby.
- Host plays White, guest plays Black — and they swap on every rematch. A rule both sides
  compute identically, so the colours are never negotiated and cannot be argued about.
- Moves, resignation and a clean goodbye travel. So do **draw, takeback and rematch**, each as
  an offer the other side answers: none may be applied unilaterally, or the two boards would
  silently disagree. An arriving offer is a **prompt on the left**, not a card over the board —
  it costs the asker nothing to send, so it must not stop the person who has to answer. The
  board stays live and the clock keeps running underneath it.
- **Nothing local pauses an online game.** Our overlay cannot stop the opponent's copy of our
  clock, so it does not stop ours either: the clock burns behind the pause card, behind the
  draw prompt and behind the promotion picker, and the HUD stays on screen so you can watch it
  do so. The offer card has no Resume for the same reason, and review (the move list, `|< Start`,
  Replay) is refused while the game is live — rewinding would stop the clock, and a move off the
  wire would then be checked against, and truncate, the position we rewound to.
- **Watch Game is still unbuilt** — a spectator is a third connection to one game, and the relay
  pairs exactly two sockets. It is a change to the relay, not a menu row.

### The wire

Five verbs, each matched against a fixed pattern before it means anything:

```
PC2 <id> <name>   guest -> host, hello
OK  <id> <name>   host -> guest, accepted
PING              keepalive, every 20s: two players thinking send nothing for minutes, and a
                  NAT (or the relay's idle timer) reads that as a dead link
M <uci>           a move, e.g. "M e2e4" or "M e7e8q"
RESIGN
BYE
DRAW / DRAW_OK / DRAW_NO              offer, accept, decline
TAKEBACK / TAKEBACK_OK / TAKEBACK_NO  same shape; the undo runs back to the asker's own move
REMATCH / REMATCH_OK
```

### Never trust the wire — as implemented

- An inbound move is a **string** until `G.move` finds it among `R.legal_moves` for the side to
  move **in the position we hold**. The peer cannot set board state, only propose a move we
  already believe is legal.
- It must also be **their** turn. A peer moving our pieces would otherwise be perfectly legal
  chess, so that check is explicit and separate.
- Anything else at all — an unknown verb, a malformed move, a message out of order — drops the
  link. There is no best-effort reading of a peer that is not speaking our protocol.
- Line length, buffer growth and datagram size are capped **in the C++ binding**, so a peer that
  never sends a newline is dropped before it costs us memory. The trust boundary is there too,
  not only in Lua.
- Nothing off the wire reaches `fs.*`, `proc.*`, or `load()`.

`tools/net_harness.py` plays the opponent from Python — which is also how the hostile cases are
tested, since a second copy of our own client would never send them.

## The blocker (what shaped every option)

Same shape as the bot problem in `BOTS.md`, and it decides the routes below:

- `ScriptSystem.cpp` opens Lua with `base, math, string, table, coroutine` — **no `io`, no
  `os`** — and there is **no socket, HTTP or network binding anywhere** in
  `Phasma/Runtime/Code/Script/Bindings/`. A script cannot open a connection today.
- The engine's only outside-world escape hatch is `proc` (added for Stockfish). It spawns a
  child under a kill-on-close job object and gives Lua a non-blocking line reader.
- **`proc` holds exactly one child, process-wide** — `ProcessBindings.cpp` keeps a single
  `static ChildProcess child`. Stockfish already occupies that slot. A network helper and
  the engine cannot both run until that limit is lifted.
- The engine *does* already run an HTTP **server** (the MCP transport on 127.0.0.1:8765),
  so the codebase has precedent for sockets — it is just not exposed to Lua and is
  loopback-only.

## What "safe" has to mean here

Threats worth designing against, in the order they actually matter for this game:

1. **A hostile peer sending malformed or illegal data.** The one that is guaranteed to
   happen, because it costs an attacker nothing. Mitigation is architectural, not
   cryptographic — see "Never trust the wire" below.
2. **IP exposure between players.** In direct peer-to-peer, connecting to someone *is*
   handing them your IP; the common consequence is a DDoS that boots the opponent, and it
   is a real pattern in small P2P titles. A relay hides both sides from each other.
3. **Inbound ports on a player's machine.** "Create Lobby" implemented as "listen on a
   port" means port forwarding, UPnP, or a machine reachable from the internet — a much
   bigger attack surface than a chess game deserves.
4. **Cheating (engine assistance).** Unsolvable between two consenting clients and,
   honestly, out of scope for a game we play with friends. Worth saying out loud so we do
   not spend effort on it.

### Never trust the wire — the rule that makes the rest cheap

Whatever transport we pick, the peer must be able to send **exactly one kind of message: a
move**, and it must be validated locally before it touches anything:

- An inbound move is a coordinate string, run through `R.legal_moves` for the side to move,
  in the position *we* have. Illegal or out-of-turn → drop the connection. The peer can
  never set board state, only propose a move we already believe is legal.
- Fixed, bounded line protocol. Length caps on every field. Anything unparseable is a
  disconnect, not a "best effort" parse.
- **Never `load()` or `loadstring()` anything that came off the network.** The Lua state is
  the game; a code-execution bug here is a code-execution bug on the player's machine.
- Nothing from the wire ever reaches `fs.*` or `proc.*`.

This is the same discipline `bot.lua` already uses on Stockfish's output, and it means a
malicious opponent's worst case is "the game ends and says the peer misbehaved".

## Routes

### Through the relay, before the game protocol starts

```
HOST <name>          -> CODE <nnnnnn>     then wait
JOIN <nnnnnn> <name> -> PAIRED <name>     both sides, and the relay becomes a pipe
                     -> ERR <reason>      and the link closes
```

### A. Relay server — BUILT, and what internet play uses

Both clients connect **outward** to a small server we run; it pairs them by lobby code and
forwards bytes. No inbound ports on either player, no NAT traversal, no port forwarding, and
neither player learns the other's IP. `wss://` (TLS) is the baseline for anything real, with
a token in the connection carrying the lobby code. Self-hosted relays of exactly this shape
are a well-trodden pattern for small games, and a single modern process handles far more
concurrent connections than we will ever have.

Cost: something has to host it, and it is a service we own and have to keep patched.

### B. LAN only — the genuinely simple one

On a trusted local network, none of threat 2 or 3 applies. UDP broadcast for discovery
("Join Lobby" lists games on the LAN), then a direct TCP connection. No TLS, no accounts, no
relay, nothing exposed to the internet. This is a small, safe, self-contained feature and it
is the obvious first milestone.

### C. Direct peer-to-peer over the internet — not recommended

Host opens a port, opponent connects to their IP. Cheapest to write, worst safety profile:
IP exposure plus an inbound port, for no benefit over the relay.

### D. Lichess Board API — no networking of our own at all

Play real online games through lichess: they do matchmaking, accounts, anti-cheat and
transport; we become a client. Attractive because the safest network service is the one we
do not run.

Costs, and they are real: every player needs a lichess account and an OAuth token with the
`board:play` scope; the Board API is restricted to rapid/classical/correspondence (blitz
only for direct challenges and bot games); and lichess requires board software to use the
official Board API — using anything else risks the account being banned. It also is not
"our" multiplayer: no private in-game lobby, no spectating our own games.

### E. Sidecar over `proc` — the zero-engine-change trick

Ship a small helper executable under `Assets/` that does the networking and speaks a line
protocol over stdin/stdout, exactly like Stockfish does. Route A, B or C could all be
implemented this way with **no C++ change at all**.

The catch is the one-child limit: while the net helper runs, Stockfish cannot, so an online
game would have no hint and no eval bar. Lifting `proc` to a handful of named children is a
small, contained engine change and probably worth doing regardless.

## How it was built, and what each part cost

1. **The relay (A)**, in `relay/` — Python, standard library only, one thread per session. It
   pairs by code and pipes bytes; it does not parse the game. `deploy.sh` puts it on a box.
2. **TLS in the engine.** mbedTLS is now a build dependency of the net binding (`PE_TLS`, on by
   default, and the binding still compiles without it). Client side only: the game never
   terminates TLS. `net.join(host, port, {pin = ...})` is the whole API change.
3. **Key pinning instead of a CA.** The relay's certificate is self-signed and the game checks
   the SHA-256 of its public key against `relay_config.lua`. Stronger than the browser model
   here — a certificate signed by a real CA for the same address is still refused — and it means
   no CA bundle to ship and no domain to own. The cost is that changing the relay's key locks
   out builds carrying the old pin, which is the point.
4. **A keypad, because runtime_ui has no text entry.** Six digits, tapped. Same reason LAN play
   uses a beacon list rather than an address field.
5. **A keepalive.** Two players thinking send nothing for minutes; NATs and the relay's idle
   timer both read that as gone. `PING` every 20 seconds, and the protocol tag went `PC1` → `PC2`
   so an old build fails at hello instead of dropping an unknown verb mid-game.

## Turning internet play on (parked 2026-08-21)

Everything is built and tested; `Assets/Scripts/chess/relay_config.lua` is blank, so the Online
rows say "No relay configured yet" and open no socket. Two lines of config switch it on. The
decision that is parked is only **where the relay runs**, and the answer changes nothing in the
game:

- **Tailscale on this PC** — free, no card, no port forwarding, home IP never handed out, and
  the link is encrypted twice. The relay runs here and `host` is the Tailscale address. Cost:
  every player installs Tailscale once, and this machine must be on. Needs a Windows start
  script for `relay.py` (it does not exist yet — `deploy.sh` is the Linux/systemd path).
- **A rented Linux box** — `relay/deploy.sh user@host` and paste what it prints. Friends install
  nothing and it works with this PC off. Hetzner is about €4/month.
- **Oracle Cloud Always Free** — a real always-free VM, but it needs a phone number and a
  non-prepaid credit card to verify, and Oracle STOPS Always Free instances that stay under 20%
  CPU for seven days. A relay is idle by nature, so this route wants a keepalive of its own.
- **playit.gg is not an option** — its free tier is Minecraft-only.

## Still open

- **Spectating ("Watch Game")** — a third connection to one game. The relay pairs exactly two
  sockets, so this needs a real change there, not just a menu row.
- **Clock drift near a flag.** Each side runs both clocks off its own frame time, so within a
  second or two of a time-out the two can disagree; the loser's last-instant move can arrive
  after the winner has already called it, where it reads as illegal and drops the link.
- **Is lichess (D) interesting at all**, or does online stay ours?

## Sources

- [Cheaters & Peer-To-Peer Networking: A Beginner's Guide](https://edgegap.com/blog/cheaters-peer-to-peer-hosting-an-beginners-guide)
- [What is DDoS in gaming? How to stay safe as a player or host](https://www.comparitech.com/blog/vpn-privacy/what-is-ddos-in-gaming/)
- [GameRelay — self-hosted relay, no port forwarding](https://github.com/NexRelay/GameRelay)
- [simple-relay — WebSocket relay for small games](https://github.com/bilalakil/simple-relay)
- [Lichess API reference](https://lichess.org/api)
- [Usage of eBoards — Board API requirement and scopes](https://lichess.org/page/eboards)
