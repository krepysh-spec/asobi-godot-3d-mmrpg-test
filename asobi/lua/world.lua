-- Large streaming world: players plus per-zone props.
--
-- The grid is far too big to instantiate: 2000 x 2000 zones of 16 units is
-- 4,000,000 zones. Nothing is built up front; a zone's contents are created
-- when a player comes within view of it and dropped once nobody can see it.
--
-- One zone is one floor tile on the client, which streams the same grid around
-- the player (see scripts/floor_grid.gd). Keep zone_size in step with the
-- client's, or the visible tiles stop matching the simulated ones.
--
-- Two behaviours this file has to guarantee, both required by the client:
--
--   * every player standing in a zone sees the same props in the same places,
--     and a zone that is unloaded and re-entered looks identical. That is why
--     the layout is a pure function of (cx, cy): the positions are recomputed,
--     never stored. Only the fact that a zone has been seeded is remembered.
--   * nothing is kept alive for zones nobody is near.

game_type         = "world"
match_size        = 1
max_players       = 16
tick_rate         = 50      -- ms per tick -> ~30 ticks/s
grid_size         = 2000    -- zones per axis
-- Deliberately smaller than the camera's view of the ground (~40 units), so a
-- zone boundary is something you can see yourself cross. The client draws one
-- floor tile per zone, and a tile bigger than the screen shows nothing.
zone_size         = 16      -- units per zone side
view_radius       = 1       -- own zone + one ring = up to 3x3 zones
lazy_zones        = true
zone_idle_timeout = 30000   -- ms with no subscribers before a zone is reaped
max_active_zones  = 10000
cold_tick_divisor = 10      -- zones with nobody in them tick 10x slower
empty_grace_ms    = 10000

-- The playable extent is the whole grid, not one zone: grid_size * zone_size.
local WORLD_SIZE  = grid_size * zone_size
local SPAWN_X     = WORLD_SIZE / 2   -- centre of the map
local SPAWN_Y     = WORLD_SIZE / 2
-- The expensive part of zone_tick runs at this interval rather than every tick.
local SWEEP_TICKS    = 4             -- 50 ms ticks -> a sweep every 200 ms
local STALE_SWEEPS   = 25            -- ~5 s of silence before a player is reaped
local ZONES_PER_TICK = 2             -- zones seeded per sweep, to avoid bursts

-- Props are seeded only for the zone a player is standing in, never for
-- neighbours. A zone transfers any non-player entity lying outside its own
-- bounds to the zone that owns it (asobi_zone:transfer_out_of_bounds_npcs), so
-- seeding a neighbour's props here means the server moves them away and the
-- next tick seeds them again -- an endless create/transfer loop that spawns
-- zone processes until the node runs out of memory.
local PROP_RADIUS = 0

-- The registry populate_zone spawns from. Reaching the zone's spawner at all
-- needs asobi > 0.46: before the fix for widgrensit/asobi#246 the templates
-- were looked up in the world config instead of its game state, so the spawner
-- started empty and every game.zone.spawn returned true and created nothing.
--
-- `type` is the prop's own name rather than asobi's generic object/resource,
-- because the client styles props by it (scripts/prop.gd) and anything it does
-- not recognise is drawn as a grey cube.
--
-- No respawn rule on the ore: props are despawned when the last player walks
-- out of view, and a respawn rule would have the server rebuild them in a zone
-- nobody can see, keeping the zone process alive with it.
function spawn_templates(config)
    return {
        cube = {
            type       = "cube",
            base_state = { solid = true },
        },
        ore = {
            type       = "ore",
            base_state = { quantity = 5 },
        },
        chest = {
            type       = "chest",
            base_state = { loot = "common" },
        },
    }
end

function init(config)
    return { tick = 0 }
end

-- Empty: with lazy_zones a zone is created on demand, so pre-declaring all
-- 4,000,000 would defeat the point.
function generate_world(seed, config)
    return {}
end

function spawn_position(player_id, state)
    return { x = SPAWN_X, y = SPAWN_Y }
end

function join(player_id, state)
    return state
end

-- leave/2 is handed world state but not the entity map, so the player's entity
-- cannot be dropped here. zone_tick reaps it once seq stops advancing.
function leave(player_id, state)
    return state
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Integer hash of a zone coordinate plus a salt. Plain arithmetic on purpose:
-- Luerl cannot be relied on for bitwise operators.
local function scatter(cx, cy, salt)
    local h = (cx + 1) * 73856093 + (cy + 1) * 19349663 + salt * 83492791
    h = h % 1000003
    if h < 0 then
        h = h + 1000003
    end
    return h
end

-- math.floor returns a float in Luerl, and concatenating one renders "1000.0"
-- or even "1.0e3". Formatting through %d keeps zone keys and entity ids stable
-- integers -- without it the same zone can produce two different id strings and
-- its props get written twice.
local function zone_key(cx, cy)
    return string.format("%d,%d", cx, cy)
end

-- Which zone an entity stands in. Server-created entities carry only what
-- their template gave them, so cx/cy is derived from the position unless the
-- entity states it; reading e.cx blindly is how zone_tick used to die with
-- "bad argument '%d,%d',nil,nil to 'format'" as soon as one appeared.
local function entity_zone(e)
    local cx = e.cx or math.floor((e.x or 0) / zone_size)
    local cy = e.cy or math.floor((e.y or 0) / zone_size)
    return zone_key(cx, cy)
end

-- The props of a zone are a pure function of its coordinates, so every player
-- in the zone gets the same layout and re-entering a dropped zone reproduces it
-- exactly.
--
-- The ids are not: game.zone.spawn mints its own, so a re-entered zone gets the
-- same props in the same places under new ids. That is why nothing keys off an
-- id, and why seeding is guarded by zone_state rather than by writing to a
-- known key -- spawning is a cast, and the entity is not in the map yet when
-- the next sweep runs.
--
-- cx/cy are passed as overrides so props keep announcing their zone to the
-- client, which culls on it (scripts/net_world.gd). That is the 4-argument
-- form, also unusable before asobi#246: its overrides guard was is_map, and
-- Luerl hands Erlang a proplist.
local function populate_zone(cx, cy)
    local ox = cx * zone_size
    local oy = cy * zone_size
    local zone = { cx = cx, cy = cy }

    local cubes = 3 + scatter(cx, cy, 1) % 4   -- 3..6 per zone
    for i = 1, cubes do
        game.zone.spawn("cube",
            ox + scatter(cx, cy, 100 + i) % zone_size,
            oy + scatter(cx, cy, 200 + i) % zone_size,
            zone)
    end

    game.zone.spawn("ore",
        ox + scatter(cx, cy, 7) % zone_size,
        oy + scatter(cx, cy, 8) % zone_size,
        zone)

    game.zone.spawn("chest",
        ox + scatter(cx, cy, 11) % zone_size,
        oy + scatter(cx, cy, 12) % zone_size,
        zone)
end

function handle_input(player_id, input, entities)
    if not input or input.kind ~= "move" then
        return entities
    end

    local e = entities[player_id] or { x = SPAWN_X, y = SPAWN_Y }

    e.type = "player"
    e.x    = clamp(tonumber(input.x) or e.x, 0, WORLD_SIZE)
    e.y    = clamp(tonumber(input.y) or e.y, 0, WORLD_SIZE)
    e.yaw  = tonumber(input.yaw) or 0
    e.name = input.name or e.name or "player"
    e.seq  = tonumber(input.seq) or 0
    e.cx   = math.floor(e.x / zone_size)
    e.cy   = math.floor(e.y / zone_size)

    entities[player_id] = e
    return entities
end

-- Runs only every SWEEP_TICKS ticks. Everything it does -- reaping silent
-- players, deciding which zones are in view, seeding and dropping props --
-- walks the whole entity map and builds temporary tables, and the entity map
-- is marshalled between Erlang and Luerl on every call.
--
-- Doing that at the tick rate is what pinned the CPU at 100% and grew the node
-- to several GB: once the callback stops finishing inside a tick the ticks
-- queue up behind it, and the queue is what consumes the memory. At 5 Hz the
-- same work is comfortably inside budget, and nothing here needs to be
-- responsive faster than that -- the reap threshold alone is 5 seconds.
function zone_tick(entities, zone_state)
    zone_state = zone_state or {}

    local since = (zone_state.since_sweep or 0) + 1
    if since < SWEEP_TICKS then
        zone_state.since_sweep = since
        return entities, zone_state
    end
    zone_state.since_sweep = 0

    local last = zone_state.last_seq or {}
    local idle = zone_state.idle or {}

    -- 1. Drop players whose seq stopped advancing. This is what removes a
    -- disconnected player, because leave/2 never sees the entity map.
    local stale = {}
    for id, e in pairs(entities) do
        if e.type == "player" then
            local seq = e.seq or 0
            if last[id] == seq then
                local sweeps = (idle[id] or 0) + 1
                idle[id] = sweeps
                if sweeps > STALE_SWEEPS then
                    stale[#stale + 1] = id
                end
            else
                last[id] = seq
                idle[id] = 0
            end
        end
    end
    for i = 1, #stale do
        entities[stale[i]] = nil
        last[stale[i]] = nil
        idle[stale[i]] = nil
    end

    -- 2. Every zone within view_radius of a live player.
    local wanted = {}
    for _, e in pairs(entities) do
        if e.type == "player" then
            local cx = math.floor(e.x / zone_size)
            local cy = math.floor(e.y / zone_size)
            for dx = -PROP_RADIUS, PROP_RADIUS do
                for dy = -PROP_RADIUS, PROP_RADIUS do
                    local zx = cx + dx
                    local zy = cy + dy
                    if zx >= 0 and zy >= 0 and zx < grid_size and zy < grid_size then
                        wanted[zone_key(zx, zy)] = true
                    end
                end
            end
        end
    end

    -- 3. Which zones already hold props, and which props nobody can see.
    local seeded = zone_state.seeded or {}
    local filled = {}
    local orphaned = {}
    for id, e in pairs(entities) do
        if e.type ~= "player" then
            local key = entity_zone(e)
            if wanted[key] then
                filled[key] = true
            else
                orphaned[#orphaned + 1] = id
            end
        end
    end
    -- Despawn rather than just dropping the key: the zone's spawner keeps its
    -- own record of what it created, and clearing the map behind its back
    -- leaves it counting entities that no longer exist. The map is cleared too,
    -- because the one this callback returns is what the zone stores.
    for i = 1, #orphaned do
        game.zone.despawn(orphaned[i])
        entities[orphaned[i]] = nil
    end

    -- A zone whose props were just despawned has to be seedable again the next
    -- time somebody walks into it.
    local forgotten = {}
    for key in pairs(seeded) do
        if not wanted[key] then
            forgotten[#forgotten + 1] = key
        end
    end
    for i = 1, #forgotten do
        seeded[forgotten[i]] = nil
    end

    -- 4. Fill in zones that came into view, a few per tick. Seeding a whole
    -- 3x3 ring at once is a big enough burst to blow the callback's heap when a
    -- player spawns; spread over ticks the ring is complete in a fraction of a
    -- second and nothing spikes.
    --
    -- Both guards are needed: `seeded` covers the spawns still in flight, which
    -- are not in the entity map yet and would otherwise be spawned again on
    -- every sweep until they land; `filled` covers a zone process that was
    -- reaped and rebuilt, which comes back with its entities but without the
    -- zone state that remembers them.
    local budget = ZONES_PER_TICK
    for key in pairs(wanted) do
        if budget <= 0 then
            break
        end
        if not filled[key] and not seeded[key] then
            local comma = string.find(key, ",")
            local cx = tonumber(string.sub(key, 1, comma - 1))
            local cy = tonumber(string.sub(key, comma + 1))
            populate_zone(cx, cy)
            seeded[key] = true
            budget = budget - 1
        end
    end

    zone_state.last_seq = last
    zone_state.idle = idle
    zone_state.seeded = seeded
    return entities, zone_state
end

function post_tick(tick_n, state)
    state.tick = tick_n
    return state
end
