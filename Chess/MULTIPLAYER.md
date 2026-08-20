# Online play

**Decided 2026-08-20, and LAN play is built.** The routes below are kept as the record of why.

- **Transport: an engine binding, not a sidecar.** `Phasma/Runtime/Code/Script/Bindings/Net/NetBindings.cpp`
  gives Lua one TCP link and UDP broadcast. Route E (a helper exe over `proc`) was rejected on
  the facts: `proc` holds one child process-wide, so an online game would have had no hint and
  no eval; a sidecar has to be built and shipped per platform, Android included; and proc-lift
  plus a helper plus a second line protocol is more machinery than the binding.
- **LAN first, relay later.** There is nowhere to host a relay yet, so internet play is not
  built. The protocol and the validation are written so only the transport under them changes.
- **Friends-only, anonymous.** No accounts, no matchmaking. The display name is generated
  (`Player 4821`) because runtime_ui has no text entry — see below, it decides the whole UX.

## What is built

`Assets/Scripts/chess/lan.lua` over the `net` binding:

- **Create Lobby** opens a listener on TCP 27500 and broadcasts `PC1|<id>|<name>` on UDP 27501
  about once a second. **Join Lobby** lists what it hears and connects to the one you click.
  Leaving those screens closes the lobby.
- Host plays White, guest plays Black. A rule both sides compute identically, so the colours
  are never negotiated and cannot be argued about.
- Moves, resignation and a clean goodbye travel. Takeback and draw offers do NOT: both need a
  request/response round trip, so those rows are hidden in an online game rather than offered dead.
- **Watch Game is still unbuilt** — a spectator is a third connection to one game, which is a
  relay feature. Two peers on a LAN have nowhere to put a watcher.

### The wire

Five verbs, each matched against a fixed pattern before it means anything:

```
PC1 <id> <name>   guest -> host, hello
OK  <id> <name>   host -> guest, accepted
M <uci>           a move, e.g. "M e2e4" or "M e7e8q"
RESIGN
BYE
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

### A. Relay server — recommended for internet play

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

## Next, when there is a relay

1. **The relay (A)** for internet play, reusing the protocol and validation already written —
   only the transport underneath changes. Both clients connect outward, so no inbound ports and
   neither player learns the other's IP.
2. **Lobby codes need a way to enter one.** runtime_ui has no text entry, so a code is a
   button-pad or digit-stepper, not a text field. LAN discovery sidesteps this; the relay
   cannot.
3. **Transport integrity: TLS or HMAC-signed frames.** There is no OpenSSL in the engine build
   today, and httplib is vendored only inside the MCP tooling. Decide it when the relay exists —
   the answer depends on what hosts it.
4. **Spectating ("Watch Game")** is a relay feature: a third connection that receives moves and
   can send none.
5. **Takeback and draw offers online** need a request/response round trip. Cheap to add on top
   of the existing protocol whenever they are wanted.

## Still open

- **Who hosts the relay?** LAN-only until there is somewhere to put it.
- **Is lichess (D) interesting at all**, or does online stay ours?

## Sources

- [Cheaters & Peer-To-Peer Networking: A Beginner's Guide](https://edgegap.com/blog/cheaters-peer-to-peer-hosting-an-beginners-guide)
- [What is DDoS in gaming? How to stay safe as a player or host](https://www.comparitech.com/blog/vpn-privacy/what-is-ddos-in-gaming/)
- [GameRelay — self-hosted relay, no port forwarding](https://github.com/NexRelay/GameRelay)
- [simple-relay — WebSocket relay for small games](https://github.com/bilalakil/simple-relay)
- [Lichess API reference](https://lichess.org/api)
- [Usage of eBoards — Board API requirement and scopes](https://lichess.org/page/eboards)
