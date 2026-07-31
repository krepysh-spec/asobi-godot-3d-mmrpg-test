# Open world server — specification

How the asobi world server should behave for this game. Written as the target
contract: sections 1–7 are what we want, section 8 lists where the current
server build falls short of it, and section 9 is how to check any of it.

Implementation lives in [`asobi/lua/world.lua`](../asobi/lua/world.lua) (server)
and [`scripts/net_world.gd`](../scripts/net_world.gd) (client).

---

## 1. Geometry and coordinates

| Property | Value |
|---|---|
| World size | 2000 × 2000 units |
| Zone grid | 20 × 20 |
| Zone size | 100 × 100 units |
| Origin | `(0, 0)` at a corner; world spans `0..2000` on both axes |
| Spawn point | `(1000, 1000)` — centre of zone `10,10` |

The server is 2D. The client is 3D and maps the axes directly:

```
server x  ->  Godot x
server y  ->  Godot z
              Godot y is height and is client-only; the server never sees it
```

No scaling factor, no offset. A server coordinate is a Godot coordinate, so
anything logged on either side can be compared without conversion.

Zone coordinates are `cx = floor(x / zone_size)`, `cy = floor(y / zone_size)`,
giving `0..19` on each axis. Positions outside `0..2000` are invalid; the client
clamps the player and the server must reject or clamp them too.

## 2. Zone lifecycle

Zones are **lazy**. A world of 400 zones must not start 400 zone processes.

1. A world starts with **no** zone processes. `generate_world` returns `{}`.
2. A zone process is created the first time a player's position falls inside it.
3. A zone that has held no players for `zone_idle_timeout` (30 s) is snapshotted
   and terminated.
4. Re-entering a reaped zone recreates it, and it must look **identical** to
   before — see §3.

Config expressing this:

```lua
grid_size         = 20
zone_size         = 100
view_radius       = 1
lazy_zones        = true
zone_idle_timeout = 30000
max_active_zones  = 512
cold_tick_divisor = 10     -- zones with nobody in them tick 10x slower
tick_rate         = 50     -- ms per tick
```

## 3. Zone contents (the cubes)

Each zone owns a fixed set of props: 3–6 cubes, one ore, one chest.

The layout is a **pure function of `(cx, cy)`**, never of random state:

- every player in a zone sees the props in the same places;
- a player who leaves and comes back sees the same zone;
- a zone reaped and recreated is indistinguishable from before;
- no layout state needs persisting.

The hash is plain integer arithmetic (`scatter/3`), because Luerl cannot be
relied on for bitwise operators.

Props carry their `cx`/`cy` so the server can decide what to unload without
parsing entity ids.

## 4. Interest and streaming

This is the core requirement.

- A player is subscribed to **their own zone plus one ring of neighbours**
  (`view_radius = 1`, so up to 3 × 3 = 9 zones).
- On subscribing to a zone, the client receives that zone's full entity set.
- On crossing a zone border, the player is re-homed: the zones that dropped out
  of the ring are unsubscribed and the client receives **removals** for their
  entities; newly entered zones send **additions**.
- Neighbour zones are populated before the player reaches the border, so nothing
  pops into existence in view.
- Two players standing in the same zone are subscribed to the same zone and so
  receive byte-identical entity sets for it.

Consequence the client relies on: cubes appear as you walk into a zone and are
freed as you walk out, with no client-side culling logic.

## 5. Players as entities

One entity per connected player, in the zone containing them:

```
{ type = "player", x, y, yaw, name, seq }
```

- `name` rides on the entity, so every subscriber can draw a name tag without a
  second lookup.
- `yaw` is the facing angle; props do not have one.
- `seq` increments on every client input and exists purely as a liveness signal
  (see §8.4).

The client sends its position at **15 Hz**, unconditionally, including while
standing still. It starts reporting only *after* it has received its
server-assigned spawn position — otherwise its first input would overwrite the
spawn point with wherever the scene happened to place the cube.

When a player disconnects, their entity must disappear from the zone for
everyone else.

## 6. Wire protocol

Only these messages are used. Payloads are as asobi documents them.

**Client → server**

| Message | Payload | When |
|---|---|---|
| `world.find_or_create` | `{mode: "spawns"}` | after the socket opens |
| `world.join` | `{world_id}` | only if the reply was not `world.joined` |
| `world.input` | `{kind: "move", x, y, yaw, name, seq}` | 15 Hz |
| `world.input` | `{kind: "spawn_cube", x, y}` | on `E` |
| `world.leave` | `{}` | leaving the scene |

**Server → client**

| Message | Payload |
|---|---|
| `world.joined` | `{world_id, mode, grid_size, max_players, player_count, players[], status}` |
| `world.tick` | `{tick, updates: [...]}` |
| `world.left` | `{success}` |

`world.tick` carries per-zone deltas, and the first tick after `world.joined` is
the initial snapshot — handlers must be registered before joining. Ops:

| Op | Meaning |
|---|---|
| `a` | added, with full state |
| `u` | updated, **changed fields only** |
| `r` | removed, id only |

Because `u` is partial, the client keeps a merged copy of every entity's state
rather than reading each update in isolation.

Ticks are only sent when something actually changed, so silence is not a fault.

## 7. Authority

Positions are currently **client-authoritative**: the server stores whatever
`x`/`y` a client reports. That is fine for this prototype and wrong for
anything shipped. The intended end state:

- the server rejects a reported position that implies impossible speed;
- the server rejects positions outside `0..2000`;
- `spawn_cube` is rate-limited server-side rather than deduplicated by rounded
  coordinates.

Cube drops are keyed by rounded position (`drop:1004,997`), so holding the key
down cannot flood a zone. That is a mitigation, not a rate limit.

## 8. Gaps in the current build

Verified against `ghcr.io/widgrensit/asobi_lua:latest`, built 2026-07-29 from
`main` (`asobi-0.45.0`). Each of these forced a workaround.

### 8.1 `game.zone.spawn` does not materialise entities

Calling it returns `true` and nothing appears in the entity map. Reproduced with
a byte-for-byte copy of `examples/world-spawns/lua/world.lua` — only the player
entity ever arrives. No error is logged; the cast is dropped silently.

`asobi_zone.erl` guards the cast with
`when is_binary(TemplateId), is_number(PX), is_number(PY), is_map(Overrides)`,
which is a plausible place for a Luerl-marshalled table to fail the match.

**Workaround:** props are written straight into the entity map, which replicates
reliably. `spawn_templates` is still declared, so switching back is a small edit
in `populate_zone`.

### 8.2 Players are never re-homed between zones

`asobi_world_server` has `handle_move/8` and `pos_to_zone/2`, and
`asobi_zone_manager` has `ensure_zone/2` — but `asobi_zone` never tells the world
server that a player moved. So a player keeps the zone they spawned into for the
whole session.

Observed directly: while a client walked from zone `11,10` to `20,10`, the server
kept reporting `zone=10,10`.

Both official examples (`world-spawns`, `world-walkers`) use `grid_size = 1`, so
neither exercises a zone transition.

**Workaround:** §4 is implemented in `zone_tick` from the positions players
report — populate the ring around every occupied zone, drop props outside every
player's ring. Behaviour matches the spec; the mechanism is Lua, not the
server's own subscriptions.

### 8.3 Zone lifecycle hooks are not called

`on_zone_loaded(cx, cy, state)` never fires, so a zone is not told where it sits
in the grid. The coordinates are re-derived from any entity the zone holds. The
hooks are left in place for builds that do call them.

### 8.4 `leave/2` cannot remove the player's entity

`leave(player_id, state)` receives world state but not the entity map, so a
disconnected player's cube would stay forever — and did, accumulating ghosts
across test runs.

**Workaround:** the client increments `seq` on every input; `zone_tick` drops any
player entity whose `seq` has not advanced for 100 ticks (~5 s).

### 8.5 `game.log` does not exist

`game.log(level, msg, meta)` is documented but absent, and calling it raises,
which aborts the whole `zone_tick` callback every tick. This was the cause of a
silent total failure of zone seeding. Do not call it.

### 8.6 `guest_auth` is manifest-only

`guest_auth = true` must be in `lua/config.lua`. In `world.lua` it is silently
ignored. Guest sign-in additionally needs `ASOBI_GUEST_VERIFIER_PEPPER` of at
least 32 bytes, or it fails closed with `guest_auth_disabled`.

## 9. Acceptance checks

Each is observable from a client with no server access.

1. **Lazy start** — a fresh world reports no props until a player is placed.
2. **Zone streaming** — walking east, the set of `cx,cy` values present in
   received entities slides with the player and its size stays constant:
   `["10,9".."12,11"]` → `["13,9".."15,11"]` → `["15,9".."17,11"]`.
3. **Bounded memory** — entity node count stays flat while walking the map
   (~57 for one player at `view_radius = 1`).
4. **Determinism** — leaving a zone and returning yields the same props in the
   same places.
5. **Shared view** — two clients in one zone list identical prop ids for it.
6. **Names** — each client sees the other's `display_name` above their cube.
7. **Cleanup** — killing one client removes its cube from the other within ~5 s.
8. **Bounds** — the player cannot leave `0..2000`.
9. **Quiet server** — no `call_failed` in the server log during any of the above.

Two clients on one machine need separate credential files, because both share
one `user://` directory:

```
ASOBI_NAME=Ada ASOBI_DEVICE=user://dev_a.json godot4 --path .
ASOBI_NAME=Bob ASOBI_DEVICE=user://dev_b.json godot4 --path .
```

Without distinct `ASOBI_DEVICE` values both instances sign in as the same
player and drive one cube.
