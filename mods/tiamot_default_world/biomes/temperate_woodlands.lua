-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.1 Temperate Woodlands.
--
-- Where: the temperate ring (t = 0.18 .. 0.35 from the axis), on the wetter
-- side of the humidity noise.
--
-- The brief (2026-09-09): low rolling hills with soft crests and gentle
-- gradient changes, broken by shallow gullies and seasonal creek beds. Deep
-- dark loam and rich grass turf, irregular patches of brown leaf litter,
-- exposed woody root nodes, and weathered limestone or granite boulders
-- half-buried in the soil. Oaks, with aspens here and there, and dead
-- wood — standing snags and fallen trunks — rarer still. The trees follow
-- the Better Trees idiom: rounded trunks, a fork now and then, branches
-- that each carry a clump of leaves, a canopy that is lumps and gaps.
--
-- The hills and the gullies are the terrain field's (shape.lua). What this
-- file owns is the FLOOR and what stands on it, by two mechanisms:
--
--   * The ground is native fills, run sub-node smooth for every chunk that
--     can touch this ring, each adding cells to the surface the soil fill
--     shaped: grass in the top blocks, leaf litter where a mid-scale noise
--     says so, wet gravel along the creek floors. The soil under all of it
--     is loam — the generator asks the biome what to paint the body as.
--
--   * Everything that stands on the ground GROWS, by random tick on grass.
--     A generator cannot read the terrain it just wrote, so nothing at
--     generation time knows where the surface is — but `register_random_tick`
--     hands a mod its blocks one at a time once the world exists. Trees,
--     rocks and root nodes are SCHEMATICS: shapes the code decides, rounded
--     to the cell with `game.set_block`'s 27-cell mask, with the random
--     stream picking sizes and offsets. Every structure is one batch on the
--     paced queue (edits.lua), since each chunk it touches is a relight on
--     the server and a remesh on every client.
--
-- The random tick offers a block only if it is one material, which on a
-- smooth surface the top block is: grass cells and air.
--
-- **Counted, and never silent.** The handler runs under pcall and logs an
-- error rather than letting the engine disable the mod without a word, and
-- every STATS_EVERY ticks it logs how many turns became what. If nothing
-- grows, that block of the log says why.

local HUMIDITY_MIN = -0.05     -- the noise runs about -0.42 .. +0.42
local HUMIDITY_FREQ = 1 / 9000

local LITTER_FREQ = 1 / 14     -- patches a dozen or so blocks across
local LITTER_MIN = 0.13        -- the noise (+/-0.42) must exceed this: a fifth of the ground

-- Ground cover, as fills in the shell of air just over the surface: ferns
-- two cells tall in carpets (a slow noise says where a carpet is, a fast
-- one breaks it into clumps with gaps to walk through), tufts of grass one
-- cell tall, sparser, everywhere the ferns are not.
local COVER_CELL = 0.001 / 3   -- km: one cell
local FERN_PATCH_FREQ = 1 / 36
local FERN_PATCH_MIN = 0.0     -- half the ground is fern country
local FERN_FREQ = 1 / 4
local FERN_MIN = 0.02          -- within it, a little under half the cells
local TUFT_FREQ = 1 / 3
local TUFT_MIN = 0.15          -- two or three of a block's nine cell columns, in clumps
local TUFT_HEIGHT_FREQ = 1 / 2 -- a fine noise: how many cells tall each column's tuft is, two or three

local TREE_CHANCE = 5          -- one grass block in this many is a candidate
local TREE_SPACING = 3         -- no other trunk within this many blocks (twice the trees of 4)
local BIRCH_ONE_IN = 7         -- of the trees, one in this many is a birch
local DEAD_ONE_IN = 42         -- of the trees, one in this many is dead wood (half standing, half fallen)
local ROOT_DEPTH = 3           -- how far down a trunk may go looking for whole ground

-- Species, in the Better Trees idiom: a trunk that may fork, a few main
-- branches leaving it at an angle and rising as they go out, and a clump of
-- leaves at the end of every branch and on the top — so the canopy is a
-- lumpy union of clumps with gaps between them, not one blob. Numbers are
-- { least, extra } ranges the stream picks from.
local OAK = {
    log = "tiamot_default_world:oak_log", leaves = "tiamot_default_world:oak_leaves",
    trunk = { 6, 4 },              -- blocks of trunk before the crown
    fork_one_in = 4,               -- one oak in this many splits into two leaders
    branches = { 2, 3 },           -- main branches off the upper trunk
    branch_out = { 2, 3 },         -- how far a branch reaches sideways
    branch_up = { 1, 3 },          -- and how far it rises doing so
    clump = { 2.2, 1.2 },          -- half-width of a branch-tip clump
    crown = { 2.6, 1.2 },          -- half-width of the clump on the trunk top
    flat = 0.7,                    -- clump height as a share of its width
    flares = { 2, 3 },
    hollow_one_in = HOLLOW_ONE_IN,  -- a den under the roots, now and then
}
-- Aspen: tall and narrow, and leafy the way a column is leafy — three to
-- five short branches stacked up the top half of the trunk, each with a
-- small clump hugging it, and a crown taller than it is wide.
local ASPEN = {
    log = "tiamot_default_world:birch_log", leaves = "tiamot_default_world:oak_leaves",
    trunk = { 10, 5 },
    fork_one_in = 10,
    branches = { 3, 2 },
    branch_out = { 1, 0 },
    branch_up = { 0, 1 },
    clump = { 1.5, 0.6 },
    crown = { 1.5, 0.6 },
    flat = 1.25,
    flares = { 0, 2 },
}
local BIRCH = ASPEN                -- the block is still called birch_log

local ROCK_CHANCE = 900        -- one grass block in this many, inside a patch, starts a cluster
local ROCK_PATCH = 32          -- patches are this many blocks square...
local ROCK_PATCH_ONE_IN = 4    -- ...and one in this many has rocks and roots
local ROCK_APART = 14          -- no other stone within this many blocks of a new cluster
local LONE_ONE_IN = 4          -- one cluster candidate in this many is a single boulder
local ROOT_SHARE = 5           -- one candidate in this many is a root node, not rocks

local MANTLE_CHANCE = 600      -- one grass block in this many, inside a mantle patch, starts a patch
local MANTLE_PATCH = 24        -- patches this many blocks square, one in MANTLE_PATCH_ONE_IN
local MANTLE_PATCH_ONE_IN = 3
local MANTLE_BY_DEAD_ONE_IN = 2 -- dead wood gets a patch round it this often — not every time
local MANTLE_R = { 2, 2 }      -- patch radius, blocks
local MANTLE_BLOOM_ONE_IN = 3  -- columns of the patch that carry a bloom

local BRAMBLE_CHANCE = 700     -- one grass block in this many, inside a bramble patch
local BRAMBLE_PATCH = 24       -- patches this many blocks square, one in BRAMBLE_PATCH_ONE_IN
local BRAMBLE_PATCH_ONE_IN = 3
local HOLLOW_ONE_IN = 3        -- one oak in this many has a hollow under its roots

-- Trees are tried so often they keep the edit queue full; anything rarer
-- may queue this many batches past its cap, or it would never be placed.
local RESERVE = 6

local POOL_CHANCE = 1200       -- one grass block in this many: a vernal pool, tiny
local POOL_R = 2               -- radius of the bank, blocks; water is one block down
local POOL_APART = 18          -- no other water within this many blocks

local STATS_EVERY = 200        -- ticks between log lines: ten seconds

local blocks = tdw.blocks
local layers = tdw.layers
local shape = tdw.shape
local edits = tdw.edits

tdw.build_biome("temperate_woodlands", function(ctx)
    local n = ctx.node
    local ring = layers.ring_by_id.temperate
    -- Where the biome is, unless it is everywhere.
    local function masked(field)
        if ctx.everywhere then
            return field
        end
        local humidity = n.noise("humidity", HUMIDITY_FREQ, 2, 1.0)
        local mask = n.min(shape.ring(ring.u[1], ring.u[2]), n.sub(humidity, n.const(HUMIDITY_MIN)))
        return n.min(field, mask)
    end
    -- The top blocks under the real surface: one terrain evaluation each.
    local function top()
        return shape.terrain_band(0.0, shape.SKIN_TOP, false)
    end
    local grass = shape.compile("biome.woodlands.grass", masked(top()))
    local litter = shape.compile("biome.woodlands.litter",
        masked(n.min(top(), n.sub(n.noise("litter", LITTER_FREQ, 2, 1.0), n.const(LITTER_MIN)))))
    local creek = shape.compile("biome.woodlands.creek", masked(n.min(top(), shape.gully_floor())))
    -- The cover: bands of AIR over the surface, so the fills add plant cells
    -- on top of the ground's own. Ferns first, then tufts where ferns are
    -- not (the tuft field is cut by the fern patch).
    local function over(cells)
        return shape.terrain_band(-COVER_CELL * cells, 0.0, false)
    end
    local fern_patch = n.sub(n.noise("fern_patch", FERN_PATCH_FREQ, 1, 1.0), n.const(FERN_PATCH_MIN))
    local ferns = shape.compile("biome.woodlands.ferns",
        masked(n.min(n.min(over(2), fern_patch), n.sub(n.noise("fern", FERN_FREQ, 1, 1.0), n.const(FERN_MIN)))))
    -- Tufts: placed per cell so they stand on the surface wherever it is,
    -- two or three cells tall as a fine noise picks per column, and two or
    -- three of a block's nine columns taken, in clumps. The engine draws a
    -- run of billboard cells as ONE square sprite as tall as the run, the
    -- whole tile across it, so a two-cell run is a card two thirds of a
    -- block each way and a three-cell run a block — Minecraft's grass,
    -- standing on the sub-node surface rather than floating over a block.
    -- `a` is height above the ground in km; a column's tuft reaches
    -- 3 cells * (0.8 + 0.6 h), h in +/-0.5, so 1.5 to 3.3 cells: two or
    -- three. 0 < a < R as (R/2) - |a - R/2|: the terrain once, the cheap
    -- reach term twice, rather than the terrain twice (over the op limit).
    local function reach_half()
        return n.mul(n.add(n.mul(n.noise("tuft_height", TUFT_HEIGHT_FREQ, 1, 1.0), n.const(0.6)), n.const(0.8)),
            n.const(COVER_CELL * 1.5))
    end
    local above = n.mul(shape.terrain(false), n.const(-1.0))
    local tuft_band = n.sub(reach_half(), n.abs(n.sub(above, reach_half())))
    local tufts = shape.compile("biome.woodlands.tufts",
        masked(n.min(n.min(tuft_band, n.mul(fern_patch, n.const(-1.0))),
            n.sub(n.noise("tuft", TUFT_FREQ, 1, 1.0), n.const(TUFT_MIN)))))
    -- In order: turf everywhere, litter over it in patches, gravel over both
    -- along the creek floors; then the cover over all of it.
    return {
        { field = grass, material = blocks.grass },
        { field = litter, material = blocks.leaf_litter },
        { field = creek, material = blocks.creek_bed },
        { field = ferns, material = blocks.fern },
        { field = tufts, material = blocks.tall_grass },
    }
end)
tdw.biomes.temperate_woodlands.soil = blocks.loam

-- Reading the world ---------------------------------------------------------

local FULL = game.OCCUPANCY_FULL

-- `occupancy` is 0 for empty air and `material` is nil for a mixed block, so
-- these are the questions worth asking of a block on a smooth surface.
local function at(x, y, z)
    return game.get_block{ x = x, y = y, z = z }
end
local function is_empty(b)
    return b ~= nil and b.occupancy == 0
end
local function is_whole(b)
    return b ~= nil and b.occupancy == FULL
end
local function is_wood(b)
    return b ~= nil and b.occupancy ~= 0
        and (b.material == blocks.oak_log or b.material == blocks.birch_log or b.material == blocks.dead_wood)
end
-- Nothing there but ground cover, which a pool or a plant may take over.
local function is_open(b)
    return b ~= nil and (b.occupancy == 0
        or b.material == blocks.tall_grass or b.material == blocks.fern
        or b.material == blocks.ladys_mantle or b.material == blocks.ladys_mantle_bloom)
end

-- Whether a grass block at (x, z) is in this biome's ring. Integer
-- arithmetic on block coordinates; exact.
local function in_ring(x, z)
    if tdw.config.everywhere == "temperate_woodlands" then
        return true
    end
    local ring = layers.ring_by_id.temperate
    local r2 = x * x + z * z
    local R2 = shape.R_DISC * shape.R_DISC * 1e6
    return r2 >= ring.u[1] * R2 and r2 < ring.u[2] * R2
end

-- Which grass blocks are candidates is decided by an integer hash of the
-- position and the world seed, before anything is read or any stream opened:
-- a busy world hands this handler thousands of blocks a tick and almost all
-- of them must cost nothing. Plain integer arithmetic; exact. `seed_int` is
-- the generator's integer form of the seed — the seed itself can be a float.
local function hash(x, y, z)
    local h = (x * 73856093) ~ (y * 19349663) ~ (z * 83492791) ~ ((tdw.seed_int or 0) * 2654435761)
    return h ~ (h >> 17)
end
local function candidate(x, y, z, one_in)
    return hash(x, y, z) % one_in == 0
end

-- Counts, for the log.
local stats = { turns = 0, candidates = 0, attempts = 0, grown = 0, rocks = 0, pools = 0, pool_tries = 0, pool_slope = 0, brambles = 0, mantle = 0,
    no_room = 0, headroom = 0, spacing = 0, unloaded = 0, errors = 0 }
local last_error = nil

-- Declared here and defined with the lady's mantle below, because dead wood
-- (defined first) sows a patch of it round itself.
local push_mantle

-- Cell masks -----------------------------------------------------------------

-- Bit for cell (cx, cy, cz), each 0..2, indexed x + 3*y + 9*z.
local function bit(cx, cy, cz)
    return 1 << (cx + 3 * cy + 9 * cz)
end

-- A thin bar of three cells through the middle of a block along one axis.
local BAR = {
    x = bit(0, 1, 1) | bit(1, 1, 1) | bit(2, 1, 1),
    y = bit(1, 0, 1) | bit(1, 1, 1) | bit(1, 2, 1),
    z = bit(1, 1, 0) | bit(1, 1, 1) | bit(1, 1, 2),
}
-- The bottom two layers of cells: a low hump.
local LOW = 0
-- A log lying along x or z: two cells wide, two tall, through the block.
local LYING = { x = 0, z = 0 }
for c = 0, 2 do
    for d = 0, 2 do
        LOW = LOW | bit(c, 0, d) | bit(c, 1, d)
    end
    for cy = 0, 1 do
        for cw = 0, 1 do
            LYING.x = LYING.x | bit(c, cy, cw)
            LYING.z = LYING.z | bit(cw, cy, c)
        end
    end
end

-- The mask of the cells of block (bx, by, bz) whose centres lie inside an
-- ellipsoid centred at (cx, cy, cz) with half-widths (rx, ry, rz). Plain
-- + - * / on doubles and comparisons: nothing here is a library call.
local function ellipsoid_mask(bx, by, bz, cx, cy, cz, rx, ry, rz)
    local mask = 0
    for iz = 0, 2 do
        local dz = (bz + (iz + 0.5) / 3 - cz) / rz
        for iy = 0, 2 do
            local dy = (by + (iy + 0.5) / 3 - cy) / ry
            for ix = 0, 2 do
                local dx = (bx + (ix + 0.5) / 3 - cx) / rx
                if dx * dx + dy * dy + dz * dz <= 1.0 then
                    mask = mask | bit(ix, iy, iz)
                end
            end
        end
    end
    return mask
end

-- Writes an ellipsoid of `material` into the world as part of the current
-- batch, MERGED: its cells become the material and every other cell of each
-- block keeps what it held, so a rock is in the turf rather than standing in
-- a footprint of its own bounding block. Whole blocks are left alone —
-- nothing of a buried thing shows there, and merging into one is an edit
-- per cell.
local function push_ellipsoid(material, cx, cy, cz, rx, ry, rz)
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local mask = ellipsoid_mask(bx, by, bz, cx, cy, cz, rx, ry, rz)
                if mask ~= 0 then
                    local b = at(bx, by, bz)
                    if b ~= nil and b.occupancy ~= FULL then
                        edits.push({ x = bx, y = by, z = bz }, material, mask, true)
                    end
                end
            end
        end
    end
end

-- Between two bounds, inclusive, from the stream.
local function pick(rng, range)
    return range[1] + rng:below(range[2] + 1)
end

-- Trees ----------------------------------------------------------------------

-- The foot of a trunk: down through the grass block and any partial ground
-- under it until it stands on a whole block, so on a slope it is planted
-- rather than perched. Nil if the ground there is not loaded.
local function footing(x, y, z)
    local base = y
    for dy = 0, ROOT_DEPTH do
        local b = at(x, y - dy, z)
        if b == nil then
            return nil
        end
        base = y - dy
        if is_whole(b) then
            break
        end
    end
    return base
end

-- Room for a trunk: air over it, and no other trunk within TREE_SPACING,
-- checked on a ring of points at chest height.
local function clear_for(x, y, z, height)
    for dy = 1, height + 6 do
        if not is_empty(at(x, y + dy, z)) then
            stats.headroom = stats.headroom + 1
            return false
        end
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        for r = 2, TREE_SPACING do
            if is_wood(at(x + d[1] * r, y + 2, z + d[2] * r)) then
                stats.spacing = stats.spacing + 1
                return false
            end
        end
    end
    return true
end

-- The top layer of cells: an arch of root over a hollow.
local ARCH = bit(0, 2, 0) | bit(1, 2, 0) | bit(2, 2, 0) | bit(0, 2, 1) | bit(1, 2, 1) | bit(2, 2, 1)
    | bit(0, 2, 2) | bit(1, 2, 2) | bit(2, 2, 2)

-- A root flare: low humps of wood on the ground beside the foot. With
-- `hollow`, the first of them is instead a natural hollow: the ground
-- under it is carved out a block or so deep and the root arches over the
-- opening — a den, the kind of place a fox would take.
local function push_flares(x, y, z, base, log, count, rng, hollow)
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local first = rng:below(4)
    for i = 0, count - 1 do
        local d = dirs[(first + i) % 4 + 1]
        local fx, fz = x + d[1], z + d[2]
        for fy = y, base, -1 do
            local b = at(fx, fy, fz)
            if b ~= nil and b.occupancy ~= FULL then
                if hollow and i == 0 then
                    -- Carve: an ellipsoid of air, centred a block and a
                    -- half out and a little below the surface, merged so
                    -- only its own cells go.
                    local cx, cy, cz = fx + 0.5 + d[1] * 0.8, fy + 0.2, fz + 0.5 + d[2] * 0.8
                    for bz = math.floor(cz - 1.3), math.floor(cz + 1.3) do
                        for by = math.floor(cy - 0.9), math.floor(cy + 0.9) do
                            for bx = math.floor(cx - 1.3), math.floor(cx + 1.3) do
                                local mask = ellipsoid_mask(bx, by, bz, cx, cy, cz, 1.3, 0.9, 1.3)
                                if mask ~= 0 and not (bx == x and bz == z) then
                                    local g = at(bx, by, bz)
                                    if g ~= nil and g.occupancy ~= 0 then
                                        edits.push({ x = bx, y = by, z = bz }, "engine:air", mask & g.occupancy, true)
                                    end
                                end
                            end
                        end
                    end
                    edits.push({ x = fx, y = fy, z = fz }, log, ARCH, true)
                else
                    edits.push({ x = fx, y = fy, z = fz }, log, LOW, true)
                end
                break
            end
        end
    end
end

-- The four corner columns of a block, and the mask with each of them gone.
local CORNER = {
    bit(0, 0, 0) | bit(0, 1, 0) | bit(0, 2, 0),
    bit(2, 0, 0) | bit(2, 1, 0) | bit(2, 2, 0),
    bit(0, 0, 2) | bit(0, 1, 2) | bit(0, 2, 2),
    bit(2, 0, 2) | bit(2, 1, 2) | bit(2, 2, 2),
}
local ROUND = FULL & ~(CORNER[1] | CORNER[2] | CORNER[3] | CORNER[4])

-- A trunk block: whole, minus most of its corner columns — each corner is
-- gone four times in five, so the trunk is round in most places and keeps
-- a knob or a flat here and there.
local function trunk_mask(rng)
    local mask = FULL
    for _, corner in ipairs(CORNER) do
        if rng:below(5) ~= 0 then
            mask = mask & ~corner
        end
    end
    return mask
end

-- A branch: from (x, y, z) out `out` blocks along the direction (sx, sz),
-- rising `up` as it goes, one block per step. Thick where it leaves the
-- trunk (the rounded trunk mask), a two-cell bar along the middle, and a
-- thin bar at the tip, where it turns upward to meet its clump. Writes into
-- `wood` (key -> {mask, y}) and returns the tip.
local function branch(wood, x, y, z, sx, sz, out, up, rng)
    local bx, by, bz = x, y, z
    local rises = {}
    for i = 1, up do
        rises[1 + rng:below(out)] = (rises[1 + rng:below(out)] or 0) + 1
    end
    local along_x = sx ~= 0 and sz == 0
    for step = 1, out do
        bx, bz = bx + sx, bz + sz
        if rises[step] then
            by = by + rises[step]
        end
        local key = bx .. ":" .. by .. ":" .. bz
        local mask
        if step == 1 then
            mask = trunk_mask(rng)
        elseif step == out then
            mask = (along_x and BAR.x or BAR.z) | BAR.y
        else
            mask = along_x and (LYING.x | (LYING.x << 3)) or (LYING.z | (LYING.z << 3))
            mask = mask & FULL
        end
        wood[key] = { mask = (wood[key] and wood[key].mask or 0) | mask, y = by }
    end
    return bx, by, bz
end

-- A clump of leaves: an ellipsoid, each block of it scaled a little up or
-- down at random so the surface is ragged rather than smooth.
local function clump(leaf_masks, cx, cy, cz, r, flat, rng)
    local rx, rz, ry = r, r, r * flat
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local scale = 0.85 + rng:below(6) / 20
                local mask = ellipsoid_mask(bx, by, bz, cx, cy, cz, rx * scale, ry * scale, rz * scale)
                if mask ~= 0 then
                    local key = bx .. ":" .. by .. ":" .. bz
                    leaf_masks[key] = (leaf_masks[key] or 0) | mask
                end
            end
        end
    end
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function grow_tree(x, y, z, rng, species)
    -- No room on the queue is the cheapest refusal, so it comes first: a
    -- canopy is a few thousand cell tests, not worth doing to throw away.
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local height = pick(rng, species.trunk)
    if not clear_for(x, y, z, height) then
        return false
    end
    local base = footing(x, y, z)
    if base == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end

    local wood = {}          -- key -> { mask, y }
    local leaf_masks = {}
    local top = y + height

    -- The trunk: whole in the ground, rounded above it.
    for by = base, top do
        local mask = by <= y and FULL or trunk_mask(rng)
        wood[x .. ":" .. by .. ":" .. z] = { mask = mask, y = by }
    end
    -- A fork: a second leader leaving diagonally at about half height and
    -- rising three or four blocks, with a crown of its own.
    if rng:below(species.fork_one_in) == 0 then
        local d = DIRS[rng:below(4) + 1]
        local fy = y + math.max(2, height // 2)
        local fx, fz = x, z
        local rise = 3 + rng:below(2)
        for i = 1, rise do
            if i <= 2 then
                fx, fz = fx + d[1], fz + d[2]
            end
            fy = fy + 1
            wood[fx .. ":" .. fy .. ":" .. fz] = { mask = trunk_mask(rng), y = fy }
        end
        clump(leaf_masks, fx + 0.5, fy + 0.5, fz + 0.5, pick(rng, species.clump), species.flat, rng)
    end
    -- Main branches off the upper trunk, each with a clump at its tip. They
    -- leave in different directions: the first is random, the rest go round.
    local count = pick(rng, species.branches)
    local first = rng:below(4)
    for i = 0, count - 1 do
        local d = DIRS[(first + i) % 4 + 1]
        local from = y + math.max(2, height * 3 // 5) + rng:below(math.max(1, height * 2 // 5))
        local tx, ty, tz = branch(wood, x, math.min(from, top - 1), z, d[1], d[2],
            pick(rng, species.branch_out), pick(rng, species.branch_up), rng)
        clump(leaf_masks, tx + 0.5, ty + 1.0, tz + 0.5, pick(rng, species.clump), species.flat, rng)
    end
    -- The crown on the trunk top.
    clump(leaf_masks, x + 0.5, top + 0.5, z + 0.5, pick(rng, species.crown), species.flat, rng)

    -- One batch: wood from the ground up (so the tree reads as growing),
    -- the root flare, then leaves wherever there is air and no wood.
    edits.begin()
    local keys = {}
    for key, entry in pairs(wood) do
        keys[#keys + 1] = { key = key, y = entry.y, mask = entry.mask }
    end
    table.sort(keys, function(p, q) return p.y < q.y or (p.y == q.y and p.key < q.key) end)
    for _, item in ipairs(keys) do
        local bx, by, bz = item.key:match("^(-?%d+):(-?%d+):(-?%d+)$")
        bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
        if by <= y and bx == x and bz == z then
            edits.push({ x = bx, y = by, z = bz }, species.log)
        else
            local b = at(bx, by, bz)
            if is_empty(b) or (bx == x and bz == z) then
                edits.push({ x = bx, y = by, z = bz }, species.log, item.mask == FULL and nil or item.mask, true)
            end
        end
    end
    local hollow = species.hollow_one_in ~= nil and rng:below(species.hollow_one_in) == 0
    push_flares(x, y, z, base, species.log, math.max(pick(rng, species.flares), hollow and 1 or 0), rng, hollow)
    -- Leaves go only where there is air, but reading every leaf block back
    -- is three hundred calls a tree and was most of the mod's tick. Terrain
    -- does not overhang a canopy from above, so one read per COLUMN, at its
    -- lowest leaf, decides the column: empty there, empty above.
    local columns = {}
    for key in pairs(leaf_masks) do
        local bx, by, bz = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
        bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
        local ck = bx .. ":" .. bz
        local col = columns[ck]
        if col == nil then
            columns[ck] = { x = bx, z = bz, low = by }
        elseif by < col.low then
            col.low = by
        end
    end
    local clear = {}
    for ck, col in pairs(columns) do
        clear[ck] = is_empty(at(col.x, col.low, col.z))
    end
    -- Merged, so a block that holds branch wood takes leaves in the cells
    -- the wood does not — a named cell is taken whatever was in it, so the
    -- wood's cells are left out of the mask rather than trusted to survive.
    for key, mask in pairs(leaf_masks) do
        local bx, by, bz = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
        bx, by, bz = tonumber(bx), tonumber(by), tonumber(bz)
        if wood[key] then
            mask = mask & ~wood[key].mask
        end
        if mask ~= 0 and (clear[bx .. ":" .. bz] or wood[key]) then
            edits.push({ x = bx, y = by, z = bz }, species.leaves, mask, true)
        end
    end
    return edits.commit()
end

-- Dead wood -------------------------------------------------------------------

-- A snag: a bare trunk, shorter than a living tree, with a stub or two of
-- branch and a broken top — the top block holds only some of its cells.
local function grow_snag(x, y, z, rng)
    local height = 4 + rng:below(5)
    if not clear_for(x, y, z, height) then
        return false
    end
    local base = footing(x, y, z)
    if base == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local top = y + height
    edits.begin()
    for by = base, top - 1 do
        edits.push({ x = x, y = by, z = z }, "tiamot_default_world:dead_wood")
    end
    -- The broken top: the bottom layer and a few cells above it.
    local jag = 0
    for c = 0, 2 do
        for d = 0, 2 do
            jag = jag | bit(c, 0, d)
        end
    end
    for _ = 1, 2 + rng:below(4) do
        jag = jag | bit(rng:below(3), 1, rng:below(3))
    end
    jag = jag | bit(rng:below(3), 2, rng:below(3))
    edits.push({ x = x, y = top, z = z }, "tiamot_default_world:dead_wood", jag)
    -- Stubs: one or two bars out from the upper trunk.
    for _ = 1, 1 + rng:below(2) do
        local dirs = { { 1, 0, "x" }, { -1, 0, "x" }, { 0, 1, "z" }, { 0, -1, "z" } }
        local d = dirs[rng:below(4) + 1]
        local sy = top - 1 - rng:below(math.max(1, height - 2))
        local sx, sz = x + d[1], z + d[2]
        if is_empty(at(sx, sy, sz)) then
            edits.push({ x = sx, y = sy, z = sz }, "tiamot_default_world:dead_wood", BAR[d[3]])
        end
    end
    push_flares(x, y, z, base, "tiamot_default_world:dead_wood", rng:below(3), rng)
    if rng:below(MANTLE_BY_DEAD_ONE_IN) == 0 then
        push_mantle(x, y, z, rng)
    end
    return edits.commit()
end

-- A fallen trunk: a log two cells thick lying along x or z, four to seven
-- blocks long, merged into the surface blocks it lies in so it reads as
-- half sunk in the turf. Its far end drops with the ground if the ground
-- drops.
local function lay_log(x, y, z, rng)
    if not edits.room() then
        stats.no_room = stats.no_room + 1
        return false
    end
    local along_x = rng:next_bool()
    local dir = rng:next_bool() and 1 or -1
    local length = 4 + rng:below(4)
    local lying = along_x and LYING.x or LYING.z
    local placed = 0
    edits.begin()
    for i = 0, length - 1 do
        local lx = along_x and x + i * dir or x
        local lz = along_x and z or z + i * dir
        -- The block whose cells this stretch of log shares: the surface block
        -- at this column, found from the start height downwards, then up.
        local ly = nil
        for dy = 0, -2, -1 do
            local b = at(lx, y + dy, lz)
            if b ~= nil and b.occupancy ~= 0 and b.occupancy ~= FULL then
                ly = y + dy
                break
            end
        end
        if ly == nil and is_empty(at(lx, y, lz)) and is_whole(at(lx, y - 1, lz)) then
            ly = y
        end
        if ly ~= nil then
            local b = at(lx, ly, lz)
            local mask = lying
            if i == length - 1 and rng:next_bool() then
                mask = mask & ~(along_x and (bit(2, 0, 0) | bit(2, 1, 0) | bit(2, 0, 1) | bit(2, 1, 1))
                    or (bit(0, 0, 2) | bit(1, 0, 2) | bit(0, 1, 2) | bit(1, 1, 2)))
            end
            edits.push({ x = lx, y = ly, z = lz }, "tiamot_default_world:dead_wood", mask, true)
            placed = placed + 1
        end
    end
    if placed < 3 then
        edits.commit()          -- an empty-enough batch; commit clears it
        return false
    end
    if rng:below(MANTLE_BY_DEAD_ONE_IN) == 0 then
        push_mantle(x, y, z, rng)
    end
    return edits.commit()
end

-- Rocks and root nodes ------------------------------------------------------

-- Rocks come from the shared module (rocks.lua): a cluster of weathered
-- limestone or granite — one big boulder, smaller ones leaning in on one
-- side, pebbles about — or now and then a single boulder. A root node is a
-- small flat lump of wood, the exposed knuckle of a root. Both come in
-- patches: a coarse grid of the world, one square in a few, is where they
-- may grow at all, and never within ROCK_APART of stone already placed.
local function stone_near(x, y, z)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        for _, r in ipairs({ 4, 9, ROCK_APART }) do
            for dy = -1, 1 do
                local b = at(x + d[1] * r, y + dy, z + d[2] * r)
                if b ~= nil and b.occupancy ~= 0
                    and (b.material == blocks.limestone or b.material == blocks.granite) then
                    return true
                end
            end
        end
    end
    return false
end

local function place_rocks(x, y, z, rng, root)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    if root then
        local r = 0.7 + rng:below(7) / 10
        edits.begin()
        push_ellipsoid("tiamot_default_world:oak_log", x + 0.5, y + 0.6 - r * 0.25, z + 0.5, r, r * 0.5, r * (0.8 + rng:below(5) / 10))
        return edits.commit(RESERVE)
    end
    if stone_near(x, y, z) then
        stats.spacing = stats.spacing + 1
        return false
    end
    local material = rng:next_bool() and "tiamot_default_world:limestone" or "tiamot_default_world:granite"
    edits.begin()
    local placed
    if rng:below(LONE_ONE_IN) == 0 then
        placed = tdw.rocks.place_cluster(material, x, y, z, rng, { satellites = 0, pebbles = 2 })
    else
        placed = tdw.rocks.place_cluster(material, x, y, z, rng)
    end
    if placed == 0 then
        edits.commit(RESERVE)
        return false
    end
    return edits.commit(RESERVE)
end

-- Brambles ---------------------------------------------------------------------

-- A tangle: over a disc of one to two blocks, each block gets about half
-- its lower two cell layers and a few cells of the top one, lifted to sit
-- on the surface within its block. Merged, so the turf's cells stay.
local function place_bramble(x, y, z, rng)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local radius = 1 + rng:below(2)
    edits.begin()
    local placed = 0
    for dz = -radius, radius do
        for dx = -radius, radius do
            if dx * dx + dz * dz <= radius * radius + 1 and rng:below(4) ~= 0 then
                local gy, gb = tdw.rocks.surface_at(x + dx, z + dz, y)
                if gy ~= nil then
                    local ground = gy + (gb.occupancy == FULL and 1.0 or 0.6)
                    local mask = 0
                    for cz = 0, 2 do
                        for cx = 0, 2 do
                            if rng:below(2) == 0 then mask = mask | bit(cx, 0, cz) end
                            if rng:below(3) == 0 then mask = mask | bit(cx, 1, cz) end
                            if rng:below(8) == 0 then mask = mask | bit(cx, 2, cz) end
                        end
                    end
                    -- Lift the tangle to the cell layer above the surface,
                    -- splitting it across two blocks where it has to.
                    local by = math.floor(ground)
                    local layer = math.floor((ground - by) * 3) + 1
                    if layer > 2 then by, layer = by + 1, 0 end
                    local low = (mask << (9 * layer)) & FULL
                    local high = mask >> (9 * (3 - layer))
                    if low ~= 0 then
                        edits.push({ x = x + dx, y = by, z = z + dz }, "tiamot_default_world:bramble", low, true)
                        placed = placed + 1
                    end
                    if high ~= 0 and is_empty(at(x + dx, by + 1, z + dz)) then
                        edits.push({ x = x + dx, y = by + 1, z = z + dz }, "tiamot_default_world:bramble", high, true)
                    end
                end
            end
        end
    end
    if placed == 0 then
        edits.commit(RESERVE)
        return false
    end
    return edits.commit(RESERVE)
end

-- Lady's mantle ------------------------------------------------------------------

-- A cell or two of plant lifted to sit on the surface within its column's
-- block, merged, split across two blocks where it has to be. Returns
-- whether anything was placed.
local function place_column(material, x, ground, z, layers)
    local by = math.floor(ground)
    local layer = math.floor((ground - by) * 3) + 1
    if layer > 2 then by, layer = by + 1, 0 end
    local mask = 0
    for l = 0, layers - 1 do
        mask = mask | (bit(1, l, 1) | bit(0, l, 1) | bit(1, l, 0))
    end
    local low = (mask << (9 * layer)) & FULL
    local high = mask >> (9 * (3 - layer))
    local placed = false
    if low ~= 0 then
        local b = at(x, by, z)
        if b ~= nil and b.occupancy ~= FULL then
            edits.push({ x = x, y = by, z = z }, material, low, true)
            placed = true
        end
    end
    if high ~= 0 and is_open(at(x, by + 1, z)) then
        edits.push({ x = x, y = by + 1, z = z }, material, high, true)
        placed = true
    end
    return placed
end

-- A patch of lady's mantle round (x, z): rosettes on most columns of a
-- small disc, two cells tall so each is a card two thirds of a block; a
-- bloom the same height rising from the top of a rosette over one column
-- in a few (a different billboard material starts its own sprite, so the
-- spray stands over the leaves). Pushes into the current batch.
function push_mantle(x, y, z, rng)
    local radius = pick(rng, MANTLE_R)
    local placed = 0
    for dz = -radius, radius do
        for dx = -radius, radius do
            if dx * dx + dz * dz <= radius * radius + 1 and rng:below(5) ~= 0 then
                local gy, gb = tdw.rocks.surface_at(x + dx, z + dz, y)
                if gy ~= nil and is_open(at(x + dx, gy + 1, z + dz)) then
                    local ground = gy + (gb.occupancy == FULL and 1.0 or 0.6)
                    if place_column("tiamot_default_world:ladys_mantle", x + dx, ground, z + dz, 2) then
                        placed = placed + 1
                        if rng:below(MANTLE_BLOOM_ONE_IN) == 0 and is_open(at(x + dx, gy + 2, z + dz)) then
                            place_column("tiamot_default_world:ladys_mantle_bloom", x + dx, ground + 2.0 / 3, z + dz, 2)
                        end
                    end
                end
            end
        end
    end
    return placed
end

local function place_mantle(x, y, z, rng)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    edits.begin()
    if push_mantle(x, y, z, rng) == 0 then
        edits.commit(RESERVE)
        return false
    end
    return edits.commit(RESERVE)
end

-- Pools ----------------------------------------------------------------------

-- A vernal pool is dug, not found: a flat patch of grass gets a bank one
-- block deep and a shallow bowl of water under it. The bank is what keeps
-- it in — the water sits a block below the grass, walled by whole blocks —
-- so a smooth slope cannot drain it. The turf is three blocks thick, so
-- the bowl's sides are grass and its floor the soil: lined with grass and
-- mud, without a block being placed for either.
--
-- The tick may land on a grass block a block or two under the surface
-- (the turf is three thick), so a try climbs to the top of the turf
-- first. "Flat" allows a column of the rim to be one block HIGHER — the
-- bank is dug a block deeper there, so a pool sits in a gentle slope
-- rather than only on the rare dead-level patch.
--
-- Fluid here is a volume per block, drawn at volume/27, so the surface
-- need not sit on a block boundary the way Minecraft's does: each pool is
-- filled to its own level, fifteen to twenty-seven cells, so the water
-- stands a cell or a few below the bank's lip. The bank ring is dug at the
-- cell too — its blocks keep their bottom layer — so the dip is a gentle
-- one, and the middle block goes a block deeper, so the pool has a deep
-- point rather than a flat floor.
local TOP_LAYERS = FULL
for cx = 0, 2 do
    for cz = 0, 2 do
        TOP_LAYERS = TOP_LAYERS & ~bit(cx, 0, cz)
    end
end
local function dig_pool(x, y, z)
    for _ = 1, 3 do
        local up = at(x, y + 1, z)
        if up == nil or up.occupancy == 0 or up.material ~= blocks.grass then break end
        y = y + 1
    end
    local extra = {}
    for dz = -POOL_R, POOL_R do
        for dx = -POOL_R, POOL_R do
            local d2 = dx * dx + dz * dz
            if d2 <= POOL_R * POOL_R then
                local ground, above = at(x + dx, y, z + dz), at(x + dx, y + 1, z + dz)
                local level = ground ~= nil and ground.occupancy ~= 0 and is_open(above)
                local high = not level and d2 > (POOL_R - 1) * (POOL_R - 1)
                    and is_whole(ground) and above ~= nil and above.occupancy ~= 0
                    and is_open(at(x + dx, y + 2, z + dz))
                if not level and not high then
                    stats.pool_slope = stats.pool_slope + 1
                    return false
                end
                if high then
                    extra[#extra + 1] = { x = x + dx, y = y + 1, z = z + dz }
                end
                if d2 <= (POOL_R - 1) * (POOL_R - 1) and not is_whole(at(x + dx, y - 1, z + dz)) then
                    stats.pool_slope = stats.pool_slope + 1
                    return false
                end
            end
        end
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        for _, r in ipairs({ 6, 12, POOL_APART }) do
            for dy = -2, 1 do
                local fluid = game.get_fluid{ x = x + d[1] * r, y = y + dy, z = z + d[2] * r }
                if fluid and not fluid.empty then
                    return false
                end
            end
        end
    end
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local water = {}
    local level = 15 + hash(x, y + 2, z) % 13             -- cells of 27: this pool's own
    edits.begin()
    for _, p in ipairs(extra) do
        edits.push(p, "engine:air")
    end
    for dz = -POOL_R, POOL_R do
        for dx = -POOL_R, POOL_R do
            local d2 = dx * dx + dz * dz
            if d2 <= (POOL_R - 1) * (POOL_R - 1) then
                edits.push({ x = x + dx, y = y, z = z + dz }, "engine:air")
                edits.push({ x = x + dx, y = y - 1, z = z + dz }, "engine:air")
                water[#water + 1] = { x = x + dx, y = y - 1, z = z + dz, volume = level }
            elseif d2 <= POOL_R * POOL_R then
                -- The bank: the top two cell layers off, the bottom one kept.
                edits.push({ x = x + dx, y = y, z = z + dz }, "engine:air", TOP_LAYERS, true)
            end
        end
    end
    if is_whole(at(x, y - 2, z)) then
        edits.push({ x = x, y = y - 2, z = z }, "engine:air")
        water[#water + 1] = { x = x, y = y - 2, z = z, volume = 27 }
    end
    if not edits.commit(RESERVE) then
        return false
    end
    -- The batch lands within MAX_WAITING * BATCH_EVERY ticks; wait past that.
    edits.later(90, function()
        for _, p in ipairs(water) do
            game.set_fluid({ x = p.x, y = p.y, z = p.z }, { fluid = "tiamot_default_world:water", volume = p.volume })
        end
    end)
    return true
end

-- The random tick -------------------------------------------------------------

local function on_grass(x, y, z)
    stats.turns = stats.turns + 1
    if not in_ring(x, z) then
        return
    end
    if candidate(x, y, z, POOL_CHANCE) then
        stats.pool_tries = stats.pool_tries + 1
        if dig_pool(x, y, z) then stats.pools = stats.pools + 1 end
        return
    end
    local rock = candidate(x, y, z, ROCK_CHANCE)
        and candidate(x // ROCK_PATCH, 7, z // ROCK_PATCH, ROCK_PATCH_ONE_IN)
    local bramble = not rock and candidate(x, y, z, BRAMBLE_CHANCE)
        and candidate(x // BRAMBLE_PATCH, 11, z // BRAMBLE_PATCH, BRAMBLE_PATCH_ONE_IN)
    local mantle = not rock and not bramble and candidate(x, y, z, MANTLE_CHANCE)
        and candidate(x // MANTLE_PATCH, 13, z // MANTLE_PATCH, MANTLE_PATCH_ONE_IN)
    if not rock and not bramble and not mantle and not candidate(x, y, z, TREE_CHANCE) then
        return
    end
    stats.candidates = stats.candidates + 1
    if not edits.room((rock or bramble or mantle) and RESERVE or 0) then
        stats.no_room = stats.no_room + 1
        return
    end
    -- One stream per block, so two grass blocks in one chunk do not grow the
    -- same thing. The world seed is captured by the generator.
    local rng = game.rng_stream(
        { x = x // 16, y = y // 16, z = z // 16, seed = tdw.seed or 0 },
        "grow:" .. x .. ":" .. y .. ":" .. z)
    if rock then
        if place_rocks(x, y, z, rng, candidate(x, y, z, ROOT_SHARE)) then
            stats.rocks = stats.rocks + 1
        end
        return
    end
    if bramble then
        if place_bramble(x, y, z, rng) then
            stats.brambles = stats.brambles + 1
        end
        return
    end
    if mantle then
        if place_mantle(x, y, z, rng) then
            stats.mantle = stats.mantle + 1
        end
        return
    end
    stats.attempts = stats.attempts + 1
    -- Which tree: the hash again, on a different axis so it is independent
    -- of being a candidate at all.
    local kind = hash(x, y + 1, z)
    local grown
    if kind % DEAD_ONE_IN == 0 then
        grown = (kind // DEAD_ONE_IN) % 2 == 0 and grow_snag(x, y, z, rng) or lay_log(x, y, z, rng)
    elseif kind % BIRCH_ONE_IN == 0 then
        grown = grow_tree(x, y, z, rng, BIRCH)
    else
        grown = grow_tree(x, y, z, rng, OAK)
    end
    if grown then
        stats.grown = stats.grown + 1
    end
end

game.register_random_tick(blocks.grass, function(event)
    local ok, err = pcall(on_grass, event.x, event.y, event.z)
    if not ok then
        stats.errors = stats.errors + 1
        if last_error ~= tostring(err) then
            last_error = tostring(err)
            game.log("tiamot_default_world woodlands: grass tick failed: " .. last_error)
        end
    end
end)

local function report()
    game.log(string.format(
        "tiamot_default_world woodlands: %d grass turns, %d candidates, %d tree attempts, %d grown, %d rocks, %d brambles, %d mantle, %d pools of %d tried (%d not flat); refused: room %d, headroom %d, spacing %d, unloaded %d; errors %d (%s); batches waiting %d",
        stats.turns, stats.candidates, stats.attempts, stats.grown, stats.rocks, stats.brambles, stats.mantle, stats.pools, stats.pool_tries, stats.pool_slope,
        stats.no_room, stats.headroom, stats.spacing, stats.unloaded, stats.errors, last_error or "none",
        edits.waiting()))
    for key in pairs(stats) do
        stats[key] = 0
    end
end

local ticks = 0
tdw.on_tick(function(dt_ticks)
    ticks = ticks + dt_ticks
    if ticks >= STATS_EVERY then
        ticks = 0
        report()
    end
end)

-- Say "stats" in chat for the counts now, without waiting for the timer.
tdw.on_chat("stats", report)

game.log("tiamot_default_world: woodlands grow oaks, birches, dead wood, rocks, root nodes and pools by random tick")
