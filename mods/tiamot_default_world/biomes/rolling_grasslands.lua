-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.2 Rolling Grasslands: the dry half of the temperate ring.
--
-- Topography: broad, undulating swells and long continuous ridges with
-- wide shallow hollows, gentle everywhere, with sightlines to the horizon
-- — the swell and ridge terms in shape.lua, faded in by the dry weight of
-- the humidity noise so the ground crosses into the woodlands without a
-- step. Surface: grass over thick dirt (the biome's soil is dirt, so the
-- skin under the turf is dirt without a fill); packed dry dirt along the
-- exposed crests of some ridges and along winding game trails; and now and
-- then a smooth solitary glacial erratic, grown by random tick from the
-- shared rocks module with no cuts and a deeper burial than a woodland
-- boulder. The grass itself is the same block as the woodlands' — the
-- tint field runs it from green to sun-bleached gold across the swells.

local TUFT_FREQ = 1.5          -- as the woodlands: each cell nearly its own decision
local TUFT_MIN = 0.20          -- as the woodlands: about one column in three blocks
local COVER_CELL = 0.001 / 3

local TRAIL_FREQ = 1 / 220
local TRAIL_WIDTH = 0.012      -- noise units: a line two or three blocks wide
local TRAIL_PATCH_FREQ = 1 / 700
local TRAIL_PATCH_MIN = 0.08   -- trails in some stretches of the grass, not everywhere

local LEDGE_CREST = 0.7        -- a crest must reach this share of RIDGE_AMP to bare its dirt
local LEDGE_PATCH_FREQ = 1 / 300
local LEDGE_PATCH_MIN = 0.05   -- which crests are bared: the windward ones, as chance has it

local ERRATIC_CHANCE = 400     -- one grass block in this many, in a square that has one (the square and the spacing set the density)
local ERRATIC_CELL = 64        -- squares this wide...
local ERRATIC_CELL_ONE_IN = 3  -- ...one in this many may hold an erratic
local ERRATIC_APART = 40       -- and never within this many blocks of another stone
local ERRATIC_R = { 1.6, 1.4 } -- half-width, blocks: least and extra
local RESERVE = 6              -- a rare structure's reserve on the edit queue

-- Sentinel trees: the biome is treeless but for these, alone on the swells.
local SENTINEL_CHANCE = 300    -- one grass block in this many, in a square that has one
local SENTINEL_CELL = 96       -- squares this wide...
local SENTINEL_CELL_ONE_IN = 3 -- ...one in this many may hold a sentinel
local SENTINEL_APART = 48      -- and never within this many blocks of other wood
local SENTINEL_HEIGHT = { 7, 4 }   -- blocks of trunk: least and extra (two thirds of the first cut, 2026-09-11)
local SENTINEL_ROOT_DEPTH = 3

-- Burrows: tunnelled into hillsides, a den at the end, a second way out.
local BURROW_CHANCE = 500      -- one grass block in this many, in a square that has them
local BURROW_CELL = 48
local BURROW_CELL_ONE_IN = 2
local BURROW_R = 0.85          -- tunnel half-width, blocks: a fox's, not a player's
local DEN_R = { 1.5, 0.9 }     -- the chamber's half-width: least and extra

-- Rose bushes: thorny rounded bushes with red blooms over the top, in
-- loose groups, picked by hand (see `pick_roses` below).
local ROSE_CHANCE = 200        -- one grass block in this many, in a square that has them
local ROSE_CELL = 32           -- squares this wide...
local ROSE_CELL_ONE_IN = 3     -- ...one in this many has bushes
local ROSE_APART = 7           -- and never within this many blocks of another bush: a square fills to a loose group
local ROSE_R = { 0.7, 0.5 }    -- half-width, blocks: least and extra
local ROSE_BLOOMS = { 3, 4 }   -- blooms on a bush: least and extra
local ROSE_REGROW = 20 * 60 * 4 -- ticks until picked blooms come back: four minutes at 20 Hz
local ROSE_GRACE = 100         -- ticks after a pick before the bare bush can be dug: a button held through the pick does not take it

local STATS_EVERY = 200

local blocks = tdw.blocks
local shape = tdw.shape
local edits = tdw.edits
local FULL = game.OCCUPANCY_FULL

tdw.build_biome("rolling_grasslands", function(ctx)
    local n = ctx.node
    local function masked(field)
        local mask = tdw.biome_mask(n, "temperate", false)
        return mask and n.min(field, mask) or field
    end
    local function top()
        return shape.terrain_band(0.0, shape.SKIN_TOP, false)
    end
    local grass = shape.compile("biome.grasslands.grass", masked(top()))
    -- Game trails: a thin band about the zero contour of a noise, in some
    -- stretches only, so they wind across the grass and peter out.
    local trails = shape.compile("biome.grasslands.trails", masked(n.min(n.min(top(),
        n.sub(n.const(TRAIL_WIDTH), n.abs(n.noise("trail", TRAIL_FREQ, 1, 1.0)))),
        n.sub(n.noise("trail_patch", TRAIL_PATCH_FREQ, 1, 1.0), n.const(TRAIL_PATCH_MIN)))))
    -- Bared crests: where the ridge term is near its top, on the crests a
    -- patch noise picks.
    local ledges = shape.compile("biome.grasslands.ledges", masked(n.min(n.min(top(),
        n.sub(shape.ridge(), n.const(LEDGE_CREST * shape.RIDGE_AMP))),
        n.sub(n.noise("ledge_patch", LEDGE_PATCH_FREQ, 1, 1.0), n.const(LEDGE_PATCH_MIN)))))
    -- The grass cover, as in the woodlands: stood on the surface by the
    -- engine's cover fill, two cells tall inside one block, never stacked.
    -- This field says where — one or two of a block's nine columns, and
    -- within a sixth of a block of the ground so cave floors get none.
    local tufts = shape.compile("biome.grasslands.tufts",
        masked(n.min(n.sub(n.const(COVER_CELL / 2), shape.terrain(false)),
            n.sub(n.noise("tuft", TUFT_FREQ, 1, 1.0), n.const(TUFT_MIN)))))
    return {
        { field = grass, material = blocks.grass },
        { field = trails, material = blocks.packed_dirt },
        { field = ledges, material = blocks.packed_dirt },
        { cover = blocks.tall_grass, cells = 2, take = tufts },
    }
end)
tdw.biomes.rolling_grasslands.soil = blocks.dirt

-- Runtime -----------------------------------------------------------------------

local schem = tdw.schem
local stats = { turns = 0, tries = 0, erratics = 0, sentinels = 0, burrows = 0, sentinel_tries = 0, burrow_tries = 0, shallow = 0,
    roses = 0, rose_tries = 0, picked = 0,
    spacing = 0, headroom = 0, unloaded = 0, flat = 0, no_room = 0, errors = 0 }
local last_error = nil

local at, bit, hash, DIR16 = schem.at, schem.bit, schem.hash, schem.DIR16
local LOG, LEAVES = "tiamot_default_world:oak_log", "tiamot_default_world:oak_leaves"

local function candidate(x, y, z, one_in)
    return hash(x, y, z) % one_in == 0
end
local function is_whole(b)
    return b ~= nil and b.occupancy == FULL
end
-- Nothing there but ground cover, which a structure may take over.
local function is_open(b)
    return b ~= nil and (b.occupancy == 0 or b.material == blocks.tall_grass)
end
local function is_wood(b)
    return b ~= nil and b.occupancy ~= 0 and b.material == blocks.oak_log
end

-- The tick may land on turf under the surface (it is three thick): climb
-- to the top grass block first.
local function climb(x, y, z)
    for _ = 1, 3 do
        local up = at(x, y + 1, z)
        if up == nil or up.occupancy == 0 or up.material ~= blocks.grass then break end
        y = y + 1
    end
    return y
end

-- The highest whole block within a few of the surface, for a trunk to
-- stand in. Nil if unloaded.
local function footing(x, y, z)
    local base = y
    for dy = 0, SENTINEL_ROOT_DEPTH do
        local b = at(x, y - dy, z)
        if b == nil then return nil end
        base = y - dy
        if is_whole(b) then break end
    end
    return base
end

local function stone_near(x, y, z)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
        for _, r in ipairs({ 6, 14, 26, ERRATIC_APART }) do
            for dy = -2, 2 do
                local b = at(x + d[1] * r, y + dy, z + d[2] * r)
                if b ~= nil and b.occupancy ~= 0 and (b.material == blocks.granite or b.material == blocks.limestone) then
                    return true
                end
            end
        end
    end
    return false
end

-- Other wood within SENTINEL_APART: sixteen headings, every six blocks,
-- from the ground to the pads. A candidate is rare, so the scan can be.
local function wood_near(x, y, z)
    for _, d in ipairs(DIR16) do
        for r = 6, SENTINEL_APART, 6 do
            local sx, sz = x + math.floor(d[1] * r + 0.5), z + math.floor(d[2] * r + 0.5)
            for dy = -1, 5 do
                if is_wood(at(sx, y + dy, sz)) then
                    return true
                end
            end
        end
    end
    return false
end

-- Erratics ----------------------------------------------------------------------

-- One smooth boulder, alone: no cuts, a little squat, deeper in the ground
-- than a woodland rock — it has been sitting there since the ice left.
local function place_erratic(x, y, z, rng)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local ground, top = tdw.rocks.surface_at(x, z, y)
    if ground == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    if stone_near(x, y, z) then
        stats.spacing = stats.spacing + 1
        return false
    end
    local r = ERRATIC_R[1] + rng:below(15) / 10
    local surface = ground + (top.occupancy == FULL and 1.0 or 0.6)
    edits.begin()
    tdw.rocks.place_rock("tiamot_default_world:granite", x, surface, z, r, rng,
        { cuts = 0, buried = 0.4 + rng:below(3) / 10, squat = 0.65 + rng:below(4) / 10 })
    return edits.commit(RESERVE)
end

-- Sentinel trees ----------------------------------------------------------------

-- A very large bonsai in oak: the trunk is a path of overlapping rough
-- spheres that leans out one way as it rises and eases back past half
-- height (the S), while its heading turns a sixteenth every other block
-- so the lean spirals — a twist rather than a bend. Three or four
-- branches leave the upper half at angles off the lean, rise for two
-- blocks and then level out, each holding a flat pad of leaves at its tip
-- (a bonsai's pads are held out horizontal) and now and then one halfway;
-- a wider pad crowns the top. Root flares snake out from the foot, sunk
-- into the turf. Pads are written first and wood last, so wood wins any
-- cell both claim. The trunk column is whole blocks from the footing up
-- to the surface, so the tree stands in the ground rather than on a
-- sub-node slope.
local function grow_sentinel(x, y, z, rng)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local height = schem.pick(rng, SENTINEL_HEIGHT)
    if not schem.loaded_box(x - 9, y - 4, z - 9, x + 9, y + height + 6, z + 9) then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    for dy = 1, 4 do
        if not is_open(at(x, y + dy, z)) then
            stats.headroom = stats.headroom + 1
            return false
        end
    end
    local base = footing(x, y, z)
    if base == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    if wood_near(x, y, z) then
        stats.spacing = stats.spacing + 1
        return false
    end

    -- The trunk's path.
    local heading = rng:below(16)
    local twist = rng:next_bool() and 1 or -1
    local lean = (3 + rng:below(4)) / 10                    -- 0.3 .. 0.6 sideways per block of rise
    local r0 = 0.9 + rng:below(4) / 10                      -- 0.9 .. 1.2 at the foot: two thirds of the first cut
    local px, py, pz = x + 0.5, y + 0.5, z + 0.5
    local points = {}
    for i = 0, height do
        local phase = i / height
        points[#points + 1] = { px, py, pz, r0 * (1.0 - 0.55 * phase), heading }
        local l = lean * (phase < 0.5 and 1.0 or -0.5)       -- out, then back: the S
        local d = DIR16[heading + 1]
        px, pz = px + d[1] * l, pz + d[2] * l
        py = py + 0.8 + rng:below(4) / 10
        if i % 2 == 1 then
            heading = (heading + twist) % 16
        end
    end

    edits.begin()
    local wood = {}
    -- Pads are thicker than the first cut's (0.4 of their width rather than
    -- 0.28) and every branch carries one halfway as well as at its tip: a
    -- smaller tree, leafier.
    local function pad(cx, cy, cz, rx)
        local ry = rx * (0.4 + rng:below(3) / 10)
        local rz = rx * (0.8 + rng:below(5) / 10)
        schem.push_ellipsoid(LEAVES, cx, cy, cz, rx, ry, rz, { rough = 0.35, jitter = rng })
    end
    -- Branches, spread up the top half of the trunk, alternating sides.
    local count = 4 + rng:below(2)
    for b = 1, count do
        local i = math.min(height, math.floor(height * (0.45 + 0.45 * (b - 1) / count)) + rng:below(2))
        local p = points[i + 1]
        local bh = (p[5] + (b % 2 == 0 and 4 or 12) + rng:below(5) - 2) % 16
        local d = DIR16[bh + 1]
        local len = 2 + rng:below(3)
        local bx, by, bz = p[1], p[2], p[3]
        for s = 1, len do
            bx, bz = bx + d[1], bz + d[2]
            by = by + (s <= 2 and 0.5 or 0.1)               -- rises, then holds level
            wood[#wood + 1] = { bx, by, bz, p[4] * 0.45 * (1.0 - 0.5 * s / len) + 0.2 }
            if s == len then
                pad(bx, by + 0.4, bz, 1.8 + rng:below(9) / 10)
            elseif s == 2 then
                pad(bx, by + 0.6, bz, 1.3 + rng:below(6) / 10)
            end
        end
    end
    -- The crown pad, on the top of the trunk.
    local top = points[#points]
    pad(top[1], top[2] + 0.6, top[3], 2.2 + rng:below(9) / 10)
    -- Root flares.
    for _ = 1, 3 + rng:below(2) do
        local d = DIR16[rng:below(16) + 1]
        local rx, ry, rz = x + 0.5, base + 0.9, z + 0.5
        for s = 1, 2 + rng:below(2) do
            rx, rz = rx + d[1] * 0.8, rz + d[2] * 0.8
            ry = ry - 0.25
            wood[#wood + 1] = { rx, ry, rz, 0.45 - 0.08 * s }
        end
    end
    -- Wood last. The column under the first point is whole blocks.
    for by = base, y do
        edits.push({ x = x, y = by, z = z }, LOG)
    end
    for _, p in ipairs(points) do
        schem.push_ellipsoid(LOG, p[1], p[2], p[3], p[4], p[4] * 1.1, p[4], { rough = 0.15, jitter = rng })
    end
    for _, w in ipairs(wood) do
        schem.push_ellipsoid(LOG, w[1], w[2], w[3], w[4], w[4], w[4], { rough = 0.15 })
    end
    return edits.commit(RESERVE)
end

-- Burrows -------------------------------------------------------------------------

local DIR8 = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }

-- A burrow starts where the ground rises ahead — a hillside — and runs
-- into it, dropping a little and wandering, as a tunnel of air carved out
-- of whatever is there (merged, so the cells round it stay). It keeps at
-- least two blocks of roof, and stops where it would not. Half of them
-- fork once. At the end a den, a squat chamber; and from the den a second
-- tunnel climbs back toward the surface until it breaks out — the other
-- entrance of a small network.
local function dig_burrow(x, y, z, rng)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    if not schem.loaded_box(x - 16, y - 6, z - 16, x + 16, y + 8, z + 16) then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    local start = rng:below(8)
    local dir, dir_index
    for k = 0, 7 do
        local idx = (start + k) % 8
        local d = DIR8[idx + 1]
        local s5 = tdw.rocks.surface_at(x + d[1] * 5, z + d[2] * 5, y + 2)
        local s9 = tdw.rocks.surface_at(x + d[1] * 9, z + d[2] * 9, y + 4)
        -- The swells are gentle: a rise of a block over nine is a hillside
        -- here, and the tunnel's own descent finds the rest of its roof.
        if s5 ~= nil and s9 ~= nil and s5 >= y and s9 >= y + 1 then
            dir, dir_index = d, idx
            break
        end
    end
    if dir == nil then
        stats.flat = stats.flat + 1
        return false
    end
    -- Roofed: the block over the tunnel's top is whole — a block of cover.
    local function roofed(qx, qy, qz)
        return is_whole(at(math.floor(qx), math.floor(qy + BURROW_R) + 1, math.floor(qz)))
    end
    -- One tunnel: `len` steps of nine tenths of a block along `heading`,
    -- rising `rise` a step, needing roof past step `free`. With `breakout`
    -- the step that loses its roof is carved too, so the tunnel opens.
    local function tunnel(qx, qy, qz, heading, len, rise, free, breakout)
        local carved = 0
        for s = 1, len do
            local d = DIR16[heading + 1]
            qx, qz = qx + d[1] * 0.9, qz + d[2] * 0.9
            qy = qy + rise
            local ok = s <= free or roofed(qx, qy, qz)
            if ok or breakout then
                schem.push_ellipsoid("engine:air", qx, qy, qz, BURROW_R, BURROW_R * 0.9, BURROW_R, { carve = true })
                carved = carved + 1
            end
            if not ok then
                break
            end
            if s % 2 == 0 then
                heading = (heading + rng:below(3) - 1) % 16
            end
        end
        return qx, qy, qz, heading, carved
    end
    edits.begin()
    local heading = dir_index * 2
    -- The mouth opens in the surface block, and the tunnel dips at about
    -- twenty degrees, so four steps in it is under a whole block of turf.
    local ex, ey, ez = x + 0.5 + dir[1] * 0.5, y - 0.2, z + 0.5 + dir[2] * 0.5
    local lx, ly, lz, lh, carved = tunnel(ex, ey, ez, heading, 7 + rng:below(5), -0.35, 4, false)
    if carved < 5 then
        edits.begin()                                     -- discard: the hill was not deep enough
        stats.shallow = stats.shallow + 1
        return false
    end
    if rng:next_bool() then
        tunnel(lx, ly, lz, (lh + 4 + rng:below(2) * 8) % 16, 3 + rng:below(3), -0.05, 0, false)
    end
    local den = DEN_R[1] + rng:below(10) / 10 * DEN_R[2]
    if is_whole(at(math.floor(lx), math.floor(ly + 0.3 + den * 0.65) + 1, math.floor(lz))) then
        schem.push_ellipsoid("engine:air", lx, ly + 0.3, lz, den, den * 0.65, den, { carve = true, rough = 0.2 })
    end
    tunnel(lx, ly, lz, (lh + 6 + rng:below(5)) % 16, 9, 0.35, 0, true)
    return edits.commit(RESERVE)
end

-- Rose bushes -------------------------------------------------------------------

local ROSE_BUSH, ROSE_BLOOMS_ID = "tiamot_default_world:rose_bush", "tiamot_default_world:rose_blooms"
local first_bush = nil

-- Say `roses` in chat: the log prints where the first bush of this session
-- was planted and you are put down beside it. A way to go and look at one
-- (and the way the headless pick test finds one).
tdw.on_chat("roses", function(player)
    if first_bush == nil then
        game.log("tiamot_default_world grasslands: no rose bush planted yet")
        return
    end
    game.log(string.format("tiamot_default_world grasslands: first rose bush at %d, %d, %d", first_bush.x, first_bush.y, first_bush.z))
    game.move_player(player, { x = first_bush.x + 2.5, y = first_bush.y + 0.5, z = first_bush.z + 2.5 })
end)

local function is_bush(b)
    return b ~= nil and b.occupancy ~= 0 and (b.material == blocks.rose_bush or b.material == blocks.rose_blooms)
end

local function bush_near(x, y, z)
    for _, d in ipairs(DIR8) do
        for r = 2, ROSE_APART, 2 do
            for dy = -1, 2 do
                if is_bush(at(x + d[1] * r, y + dy, z + d[2] * r)) then
                    return true
                end
            end
        end
    end
    return false
end

-- The cells of a block holding `material`, as a mask.
local function cells_of(b, material)
    if b == nil or b.occupancy == 0 then return 0 end
    if b.cells then
        local mask = 0
        for i = 0, 26 do
            if b.cells[i + 1] == material then
                mask = mask | (1 << i)
            end
        end
        return mask
    end
    return b.material == material and b.occupancy or 0
end

-- A bush as the mod sees it: the 3x3x3 blocks round a centre, each with
-- its leaf mask and its bloom mask. Bushes stand ROSE_APART apart, so the
-- sweep never takes in two. `masks[key] = { leaves, blooms }`, keyed by
-- "bx:by:bz"; `order` lists the keys with their coordinates.
local function key_of(bx, by, bz) return bx .. ":" .. by .. ":" .. bz end

local function read_bush(cx, cy, cz)
    local masks, order = {}, {}
    for dz = -1, 1 do
        for dy = -1, 1 do
            for dx = -1, 1 do
                local bx, by, bz = cx + dx, cy + dy, cz + dz
                local b = at(bx, by, bz)
                local leaves, blooms = cells_of(b, blocks.rose_bush), cells_of(b, blocks.rose_blooms)
                if leaves ~= 0 or blooms ~= 0 then
                    local key = key_of(bx, by, bz)
                    masks[key] = { leaves = leaves, blooms = blooms }
                    order[#order + 1] = { bx, by, bz, key }
                end
            end
        end
    end
    return masks, order
end

-- The crown: bush cells (leaf or bloom) with no bush cell above them —
-- in the same block, or the block above. Blooms go there and nowhere else,
-- so none is buried inside a bush two blocks tall.
local function crown(masks, bx, by, bz)
    local here = masks[key_of(bx, by, bz)]
    if here == nil then return 0 end
    local own = here.leaves | here.blooms
    local above = masks[key_of(bx, by + 1, bz)]
    local over = above and (above.leaves | above.blooms) or 0
    local mask = 0
    for i = 0, 26 do
        if own & (1 << i) ~= 0 then
            local ix, iy, iz = i % 3, (i // 3) % 3, i // 9
            local covered
            if iy < 2 then
                covered = own & (1 << (i + 3)) ~= 0
            else
                covered = over & (1 << (ix + 9 * iz)) ~= 0
            end
            if not covered then
                mask = mask | (1 << i)
            end
        end
    end
    return mask
end

-- Which crown cells of a block get blooms: a hashed share, up to `count`
-- across the bush (the caller passes the running total).
local function choose_blooms(bx, by, bz, candidates, budget, salt)
    local mask, taken = 0, 0
    for i = 0, 26 do
        if candidates & (1 << i) ~= 0 and taken < budget
            and hash(bx * 3 + i % 3, by * 3 + (i // 3) % 3 + salt, bz * 3 + i // 9) % 3 == 0 then
            mask = mask | (1 << i)
            taken = taken + 1
        end
    end
    return mask, taken
end

-- A bush: a rough ellipsoid of leaf cells standing on the turf, its blooms
-- a hashed few of its crown. The masks are worked out first, so the crown
-- is known before anything is written; the tuft it stands in is carved.
local function place_rose_bush(x, y, z, rng)
    if not edits.room(RESERVE) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local ground, top = tdw.rocks.surface_at(x, z, y)
    if ground == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    if bush_near(x, y, z) then
        stats.spacing = stats.spacing + 1
        return false
    end
    local rx = ROSE_R[1] + rng:below(6) / 10 * ROSE_R[2]
    local rz = ROSE_R[1] + rng:below(6) / 10 * ROSE_R[2]
    local ry = 0.5 + rng:below(4) / 10
    local surface = ground + (top.occupancy == FULL and 1.0 or 0.6)
    local cx, cy, cz = x + 0.5, surface + ry * 0.7, z + 0.5
    local masks, order, carve = {}, {}, {}
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local leaves = schem.ellipsoid_mask(bx, by, bz, cx, cy, cz, rx, ry, rz, 0.3)
                local b = at(bx, by, bz)
                if leaves ~= 0 and b ~= nil and b.occupancy ~= FULL then
                    -- Only into air and grass cover: a bush does not eat the
                    -- turf, and the tuft it stands in goes.
                    local free = ~b.occupancy
                    if b.material == blocks.tall_grass then
                        free = FULL
                        local rest = b.occupancy & ~leaves & FULL
                        if rest ~= 0 then carve[#carve + 1] = { bx, by, bz, rest } end
                    end
                    leaves = leaves & free & FULL
                    if leaves ~= 0 then
                        local key = key_of(bx, by, bz)
                        masks[key] = { leaves = leaves, blooms = 0 }
                        order[#order + 1] = { bx, by, bz, key }
                    end
                end
            end
        end
    end
    if #order == 0 then
        stats.flat = stats.flat + 1
        return false
    end
    first_bush = first_bush or { x = x, y = math.floor(cy), z = z }
    local budget = schem.pick(rng, ROSE_BLOOMS)
    edits.begin()
    for _, c in ipairs(carve) do
        edits.push({ x = c[1], y = c[2], z = c[3] }, "engine:air", c[4], true)
    end
    for _, o in ipairs(order) do
        local bx, by, bz, key = o[1], o[2], o[3], o[4]
        local flowers, taken = choose_blooms(bx, by, bz, crown(masks, bx, by, bz), budget, 0)
        budget = budget - taken
        local leaves = masks[key].leaves & ~flowers
        if leaves ~= 0 then
            edits.push({ x = bx, y = by, z = bz }, ROSE_BUSH, leaves, true)
        end
        if flowers ~= 0 then
            edits.push({ x = bx, y = by, z = bz }, ROSE_BLOOMS_ID, flowers, true)
        end
    end
    return edits.commit(RESERVE)
end

-- Picking. The engine has no right-click hook (engine-asks, item 16), so a
-- dig on a bush that has blooms is the pick: the dig is cancelled, every
-- bloom on the bush turns to leaves, the player is given a rose or two,
-- and the blooms come back after ROSE_REGROW ticks — or on the bush's
-- random tick, whichever is first, so a restart never leaves a bush bare
-- for good.
--
-- The world cannot be READ inside the dig hook (engine-asks, item 17), so
-- the decision is made on the event's material alone and the bush is
-- read on the next tick: a dig on bush or blooms is cancelled unless the
-- mod knows that block to be bare, and the deferred read either picks or
-- learns that it is bare — after which a dig on it goes ahead like any
-- other. So a bare bush takes two digs after a restart. `bare` holds the
-- tick from which the block may be dug: a pick sets it ROSE_GRACE ahead,
-- so the button held through the pick does not go on to take the bush.
local picks, bare = {}, {}
local now = 0
tdw.on_tick(function(dt_ticks) now = now + dt_ticks end)

local function regrow(cx, cy, cz, salt)
    local masks, order = read_bush(cx, cy, cz)
    local budget = 0
    for _, o in ipairs(order) do
        if masks[o[4]].blooms ~= 0 then return end       -- still in bloom
    end
    if #order == 0 then return end                       -- the bush is gone
    budget = schem.pick(game.rng_stream(
        { x = cx // 16, y = cy // 16, z = cz // 16, seed = tdw.seed or 0 }, "roses:" .. salt), ROSE_BLOOMS)
    for _, o in ipairs(order) do
        local bx, by, bz = o[1], o[2], o[3]
        local flowers, taken = choose_blooms(bx, by, bz, crown(masks, bx, by, bz), budget, salt)
        budget = budget - taken
        if flowers ~= 0 then
            game.set_block({ x = bx, y = by, z = bz }, ROSE_BLOOMS_ID, flowers, { merge = true })
            bare[o[4]] = nil
        end
    end
end

local function pick(player, cx, cy, cz)
    local key = key_of(cx, cy, cz)
    local masks, order = read_bush(cx, cy, cz)
    local any = false
    for _, o in ipairs(order) do
        local blooms = masks[o[4]].blooms
        if blooms ~= 0 then
            game.set_block({ x = o[1], y = o[2], z = o[3] }, ROSE_BUSH, blooms, { merge = true })
            any = true
        end
    end
    if not any then
        bare[key] = now                                  -- the next dig on it goes ahead
        return
    end
    picks[key] = (picks[key] or 0) + 1
    local count = 1 + (hash(cx, cy + picks[key], cz) % 2)
    game.give(player, { material = blocks.rose, count = count })
    stats.picked = stats.picked + 1
    for _, o in ipairs(order) do
        bare[o[4]] = now + ROSE_GRACE
    end
    local salt = picks[key]
    edits.later(ROSE_REGROW, function() regrow(cx, cy, cz, salt) end)
end

local function pick_roses(event)
    if event.material ~= blocks.rose_blooms and event.material ~= blocks.rose_bush then
        return nil
    end
    local bx, by, bz = event.x // 3, event.y // 3, event.z // 3
    local since = bare[key_of(bx, by, bz)]
    if since and now >= since then
        return nil                                       -- known bare: dig it if you like
    end
    local player = event.player
    edits.later(1, function() pick(player, bx, by, bz) end)
    return ""                                            -- handled: nothing is dug
end

tdw.on_dig_complete(pick_roses)

tdw.on_random_tick(blocks.rose_bush, function(x, y, z)
    regrow(x, y, z, 0)
    return true
end)

-- The random tick ---------------------------------------------------------------

local function on_grass(x, y, z)
    stats.turns = stats.turns + 1
    y = climb(x, y, z)
    local sentinel = candidate(x, y, z, SENTINEL_CHANCE)
        and candidate(x // SENTINEL_CELL, 17, z // SENTINEL_CELL, SENTINEL_CELL_ONE_IN)
    local burrow = not sentinel and candidate(x, y, z, BURROW_CHANCE)
        and candidate(x // BURROW_CELL, 19, z // BURROW_CELL, BURROW_CELL_ONE_IN)
    local erratic = not sentinel and not burrow and candidate(x, y, z, ERRATIC_CHANCE)
        and candidate(x // ERRATIC_CELL, 5, z // ERRATIC_CELL, ERRATIC_CELL_ONE_IN)
    local rose = not sentinel and not burrow and not erratic and candidate(x, y, z, ROSE_CHANCE)
        and candidate(x // ROSE_CELL, 23, z // ROSE_CELL, ROSE_CELL_ONE_IN)
    if not sentinel and not burrow and not erratic and not rose then
        return
    end
    stats.tries = stats.tries + 1
    local rng = game.rng_stream(
        { x = x // 16, y = y // 16, z = z // 16, seed = tdw.seed or 0 },
        "grow:" .. x .. ":" .. y .. ":" .. z)
    if sentinel then
        stats.sentinel_tries = stats.sentinel_tries + 1
        if grow_sentinel(x, y, z, rng) then stats.sentinels = stats.sentinels + 1 end
    elseif burrow then
        stats.burrow_tries = stats.burrow_tries + 1
        if dig_burrow(x, y, z, rng) then stats.burrows = stats.burrows + 1 end
    elseif erratic then
        if place_erratic(x, y, z, rng) then stats.erratics = stats.erratics + 1 end
    else
        stats.rose_tries = stats.rose_tries + 1
        if place_rose_bush(x, y, z, rng) then stats.roses = stats.roses + 1 end
    end
end

-- The grass block is shared with the woodlands: a tick is this biome's
-- when the biome is everywhere, or when dirt is under the turf.
tdw.on_random_tick(blocks.grass, function(x, y, z)
    local only = tdw.config.everywhere
    local mine = only == "rolling_grasslands" or (only == nil and tdw.soil_under(x, y, z) == blocks.dirt)
    if not mine then
        return false
    end
    local ok, err = pcall(on_grass, x, y, z)
    if not ok then
        stats.errors = stats.errors + 1
        if last_error ~= tostring(err) then
            last_error = tostring(err)
            game.log("tiamot_default_world grasslands: grass tick failed: " .. last_error)
        end
    end
    return true
end)

local since = 0
tdw.on_tick(function(dt_ticks)
    since = since + dt_ticks
    if since < STATS_EVERY then
        return
    end
    since = 0
    if stats.turns == 0 then
        return
    end
    game.log(string.format(
        "tiamot_default_world grasslands: %d grass turns, %d tries: %d sentinels of %d, %d burrows of %d, %d erratics, %d rose bushes of %d, %d picked; refused: spacing %d, headroom %d, flat %d, shallow %d, room %d, unloaded %d; errors %d (%s)",
        stats.turns, stats.tries, stats.sentinels, stats.sentinel_tries, stats.burrows, stats.burrow_tries, stats.erratics,
        stats.roses, stats.rose_tries, stats.picked,
        stats.spacing, stats.headroom, stats.flat, stats.shallow, stats.no_room, stats.unloaded, stats.errors, last_error or "none"))
    for key in pairs(stats) do
        stats[key] = 0
    end
end)
