-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- 1.3 Alpine Highlands: the frost ring's dry half, and the first biome
-- whose shape is a MAP rather than a field — the Alps, glacially carved.
--
-- Why a map. Every noise in a density field is three-dimensional, so a
-- steep wall built from one leans in y as much as it wanders in x: the
-- first cut of this biome (hard-clamped terraces on 3D noise) had
-- overhanging drop-offs everywhere. A map is a surface; a wall built from
-- it is vertical at worst. And a map can see all of itself, which is what
-- erosion is: blur-and-combine passes over the whole range, once per
-- world, in `game.register_on_world_init`.
--
-- The recipe (`alp_height`, in km above the base dome):
--   1. A ridged multifractal: four octaves of (0.42 - |n|)/0.42 — a crest
--      along each noise's zero contour — the finer octaves weighted by the
--      coarser (detail on the peaks, not in the valleys). The classic
--      alpine skyline: arêtes, horns where they meet.
--   2. Glacial valleys along the ZERO CONTOUR of a slow noise — a long
--      meandering ribbon, the same trick the creeks and the game trails
--      use — where the range is pulled down toward a flat floor over a
--      transition steep enough to read as a wall: the U profile, and the
--      valleys connect into a network rather than sitting as bowls.
--   3. Erosion passes, in the pre-pass: needle peaks capped at a height
--      over their neighbourhood mean; valley floors replaced by their own
--      wide blur, so they lie flat and smooth while the ridges keep their
--      edges (`docs/erosion-options.md`, method 1).
--   4. Lakes: medium to large, on the valley floors, where a lake noise is
--      high — the floor under a lake is smoothed harder still so the lake
--      lies level, and the fills turn its top block to ice and the eight
--      blocks under that to water. The lake is not carved: its surface IS
--      the floor, which is what keeps every lake chunk a surface chunk the
--      generator paints, and what makes the ice a band of the surface like
--      the snow. (The water is the `water` BLOCK, not the fluid: the fluid
--      fill takes one world level, and a lake's level cannot reach Lua —
--      engine-asks, item 18.)
-- Three more maps carry what the materials need: `alp_floor` (1 on a
-- valley floor), `alp_crest` (1 on a ridge crest) and `alp_lake` (1 in a
-- lake). The 3D crags stay in the field, small, for roughness up close.
--
-- Materials: the mountains are stone — granite with slate seams — but
-- above the snowline almost none of it shows: packed snow two blocks deep
-- on everything that is not a crest, and ice on the valley floors and in
-- the cirques (the glaciers). Below the snowline the lower slopes: scree
-- under the crests, permafrost and thin dirt in patches.
--
-- Coverage: ONE map, 16 km square at 16 blocks a sample, centred on the
-- spawn — enough to walk and fly for review under the dev switch. Outside
-- it the map holds its edge value. Tiling the whole frost ring is the
-- step after the shape is right.
--
-- Scale (2026-09-12): the range two and a half times the first cut in
-- both height and breadth, the snow twice as deep, the erosion passes
-- 1.75 times as strong (their radii in blocks, and the peak cap that much
-- lower), and the snow lying by aspect: down the valleys and off the walls
-- and crests, from the floor and crest masks the map already carries.
--
-- Nothing grows by random tick yet.

local blocks = tdw.blocks
local shape = tdw.shape
local n = shape.node

-- The map: where and how fine. Changing any of these makes a NEW map; a
-- world made with the old one keeps generating against the old one.
local MAP_SIDE = 1024
local MAP_SCALE = 16                                  -- blocks per sample
local MAP_ORIGIN_X = shape.SPAWN_X - MAP_SIDE * MAP_SCALE // 2
local MAP_ORIGIN_Z = shape.SPAWN_Z - MAP_SIDE * MAP_SCALE // 2
local MAP_SEED = 1303                                 -- mixed with the world's own by the engine

-- The range. Four ridged octaves, each a crest along its noise's zero
-- contour, the finer weighted by the coarser.
local RIDGE_FREQ = 1 / 3000                           -- the big ridges, two and a half kilometres apart
local RIDGE_AMP = { 0.50, 0.25, 0.1125, 0.05, 0.025, 0.012 }   -- km per octave: peaks near 0.9 km; the last two are ribs 47 and 23 blocks apart
-- The walls: the floor mask's transition band, f(1-f), which peaks at 1/4;
-- WALL_GAIN times that reads as 1 across the wall. Used by the ribs, the
-- field's detail and the snow.
local WALL_GAIN = 6.0
-- Ribs down the walls (couloirs): a ridged octave that shows only in the
-- valley mask's transition band.
local RIB_FREQ = 1 / 375
local RIB_AMP = 0.02                                  -- km: twenty blocks of rib, on a wall
-- Glacial valleys: floors within VALLEY_W of the valley noise's zero
-- contour, walls over the next 1/VALLEY_K of the noise, floors at
-- VALLEY_FLOOR of the ridge height plus VALLEY_BASE.
local VALLEY_FREQ = 1 / 3500
local VALLEY_W = 0.06                                 -- noise units: a trunk valley some 500 blocks across; about a quarter of the ground is floor
local VALLEY_K = 18                                   -- 1/18 of the noise's units from wall foot to rim
local VALLEY_FLOOR = 0.15                             -- share of the range kept on a floor
local VALLEY_BASE = 0.05                              -- km: the floor's own height
-- A gentle tilt under everything, so no two valleys sit at one height.
local BASE_FREQ = 1 / 7500
local BASE_AMP = 0.15
-- Erosion passes. SHARPEN is an unsharp pass — the height plus a share of
-- its difference from a short blur — which is what curvature-driven
-- erosion does: convex ground (arêtes, spurs) stands up, concave ground
-- (gullies, cirque floors) cuts down. Sharper shapes, from the erosion.
-- Then the peak cap and the floor smoothing, a little stronger again.
local SHARPEN_BLUR = 2                                -- samples (32 blocks): the scale the sharpening works at
local SHARPEN = 0.6                                   -- share of (h - blur) added back
local PEAK_BLUR = 4                                   -- samples (64 blocks): the neighbourhood a peak is judged against
local PEAK_OVER = 0.030                               -- km: how far a peak may stand over that mean
local FLOOR_BLUR = 5                                  -- samples (80 blocks): how smooth a valley floor is
-- Where the crests are, for the rock: the primary ridge term over this.
local CREST_FROM = 0.78
local CREST_K = 8
-- Lakes: where the lake noise is over LAKE_T, on the floors; its edge
-- crosses in 1/LAKE_K of the noise. About a fifth of the floors, in
-- bodies a hundred and fifty to three hundred blocks across.
local LAKE_FREQ = 1 / 700
local LAKE_T = 0.06
local LAKE_K = 15
local LAKE_BLUR = 14                                  -- samples (224 blocks): a lake lies level
local LAKE_DEPTH = 0.008                              -- km: eight blocks of water under the ice
local LAKE_ICE = 0.001                                -- km: one block of ice on top

-- The materials. The snowline is not one height: it comes down
-- SNOW_VALLEY_DROP in the valleys (the floor mask) and goes up
-- SNOW_CREST_RAISE on the crests, and the walls — the valley mask's own
-- transition band, WALL_GAIN times f(1-f) — carry none: snow lies where
-- the ground faces up, which is the dot product the designer asked for,
-- read from the two masks the map already carries.
local SNOWLINE = 0.065                                -- km above the dome: snow and ice above, slopes below
-- The line is not drawn: it wanders by SNOW_WANDER over a few hundred
-- blocks and is flecked by SNOW_FLECK at a few blocks, so its edge is a
-- mottled zone some fifty blocks tall rather than a contour.
local SNOW_WANDER = 0.06                              -- km of noise amplitude (+/- half) at SNOW_WANDER_FREQ
local SNOW_WANDER_FREQ = 1 / 60
local SNOW_FLECK = 0.05
local SNOW_FLECK_FREQ = 1 / 9
-- Below the line, patches of snow that thin out with depth: a patch noise
-- against a threshold that rises SNOW_PATCH_FADE per km below the line,
-- so the snow does not stop at the line but peters out over a hundred
-- blocks or so. In the snow fill, so as deep as the snow.
local SNOW_PATCH_FREQ = 1 / 40
local SNOW_PATCH_T = 0.02                             -- near the line about half the ground is patch
local SNOW_PATCH_FADE = 1 / 0.12                      -- the threshold up by 1 (past the noise) 120 blocks below
local SNOW_VALLEY_DROP = 0.08                         -- km: how much lower the snow reaches down a valley
local SNOW_CREST_RAISE = 0.10                         -- km: how much higher it must be to lie on a crest
local SNOW_DEPTH = 0.004                              -- km: four blocks of packed snow
local ICE_DEPTH = 0.003                               -- km: three blocks of glacier
-- The patches of each material: two octaves rather than one, so a
-- patch has an irregular outline instead of a blob's, and a fine dither
-- at the threshold so its edge is speckled rather than drawn.
local SLATE_FREQ = 1 / 110
local SLATE_MIN = 0.10
local SCREE_FREQ = 1 / 50
local SCREE_MIN = -0.05
local PERMAFROST_FREQ = 1 / 140
local PERMAFROST_MIN = 0.05
-- Dirt over most of the ground below the snowline that faces up, and
-- turf (`alpine_turf`, the cold-tinted turf) over most of that below the tree line: the
-- granite shows on about a third of it, the walls and the crests and
-- the patches these leave.
local DIRT_FREQ = 1 / 80
local DIRT_MIN = -0.08
local DIRT_DEPTH = 0.003                              -- km: three blocks
local TREELINE = 200                                  -- blocks over the base dome: turf and firs below (the firs read it at runtime); 90 left most of the range bare
local TURF_FREQ = 1 / 60
local TURF_MIN = -0.02
local TURF_DEPTH = 0.001                              -- km: the top block of the dirt
local PATCH_DITHER = 0.18                             -- noise amplitude (+/- half) at PATCH_DITHER_FREQ, added before the threshold
local PATCH_DITHER_FREQ = 1 / 5
-- The field's own detail, under the map's resolution: a mid ridged noise
-- (ledges and ribs a few blocks high, strongest on the walls and crests,
-- quiet under the snowfields) and the fine crags. Both are 3D, so up
-- close they make the small ledges and overhangs that rock has.
local DETAIL_FREQ = 1 / 70
local DETAIL_H = 0.006                                -- km: up to two and a half blocks on the flats...
local DETAIL_ROCK = 2.0                               -- ...and three times that on a wall or a crest
-- (The fine crags and the ledges' second octave went on 2026-09-12 for
-- the tick budget: every surface fill re-evaluates the terrain, so an
-- octave in it is paid nine times a chunk. The clamped steps carry the
-- small scale now.)
-- Small clamped steps: a noise clamped hard makes little terraces and
-- ledges a block or so high wherever it crosses zero — the "slightly
-- clamped small-scale detail".
local COVER_CELL = 0.001 / 3                          -- km: one cell, for the cover's near-surface guard
local TUFT_FREQ = 1.5                                 -- the grass: each cell nearly its own decision
local TUFT_MIN = 0.30                                 -- sparse: a third of the 0.22 cut, a column in a dozen blocks
local STEP_FREQ = 1 / 18
local STEP_H = 0.0012                                 -- km: a step of about a block
local STEP_STEEP = 8.0                                -- how hard the clamp is: bigger is a sharper edge

local function map_spec(name)
    return { name = name, side = MAP_SIDE, scale = MAP_SCALE, origin_x = MAP_ORIGIN_X, origin_z = MAP_ORIGIN_Z }
end

-- A ridge: 1 on the noise's zero contour, 0 where |n| reaches its range.
local function ridge(stream, freq)
    return n.clamp(n.mul(n.sub(n.const(shape.NOISE_RANGE * 0.84), n.abs(n.noise(stream, freq, 1, 1.0))),
        n.const(1.0 / (shape.NOISE_RANGE * 0.84))), 0.0, 1.0)
end
local function r(k) return ridge("alp_ridge" .. k, RIDGE_FREQ * 2 ^ (k - 1)) end
-- The range: A1 r1^2 + A2 r1 r2 + A3 r2 r3 + ... each finer octave
-- weighted by the one before, so the detail is on the peaks. A ridge
-- appears twice because the stack machine has no dup; the map is filled
-- once, so it costs nothing that matters.
local function range()
    local acc = n.mul(n.mul(r(1), r(1)), n.const(RIDGE_AMP[1]))
    for k = 2, #RIDGE_AMP do
        acc = n.add(acc, n.mul(n.mul(r(k - 1), r(k)), n.const(RIDGE_AMP[k])))
    end
    return acc
end
-- 1 on a valley floor, 0 on the massif, a wall between: the floor is the
-- band |v| < VALLEY_W about the valley noise's zero contour.
local function floor_mask()
    return n.clamp(n.mul(n.sub(n.const(VALLEY_W), n.abs(n.noise("alp_valley", VALLEY_FREQ, 2, 1.0))), n.const(VALLEY_K)), 0.0, 1.0)
end
-- The walls: the floor mask's transition band, f(1-f) scaled to read 1.
local function wall_mask()
    return n.clamp(n.mul(n.mul(floor_mask(), n.sub(n.const(1.0), floor_mask())), n.const(WALL_GAIN)), 0.0, 1.0)
end
-- The height: the range pulled down to its floor share where the floor
-- mask is 1, the floor's own height added there, ribs on the walls, and
-- the tilt under all.
local function height()
    local kept = n.add(n.const(1.0), n.mul(floor_mask(), n.const(VALLEY_FLOOR - 1.0)))
    local ribs = n.mul(n.mul(ridge("alp_rib", RIB_FREQ), wall_mask()), n.const(RIB_AMP))
    return n.add(n.add(n.add(n.mul(range(), kept), n.mul(floor_mask(), n.const(VALLEY_BASE))), ribs),
        n.noise("alp_base", BASE_FREQ, 2, BASE_AMP))
end
local function crest_mask()
    return n.clamp(n.mul(n.sub(r(1), n.const(CREST_FROM)), n.const(CREST_K)), 0.0, 1.0)
end
-- 1 in a lake: a blob of the lake noise, on a floor.
local function lake_mask()
    return n.mul(n.clamp(n.mul(n.sub(n.noise("alp_lake", LAKE_FREQ, 1, 1.0), n.const(LAKE_T)), n.const(LAKE_K)), 0.0, 1.0),
        floor_mask())
end

-- The pre-pass: build the maps once per world. Scratch maps are stored
-- with the world too (every named map is); they are small next to the
-- world.
game.register_on_world_init(function()
    local height_map = game.map(map_spec("alp_height"))
    local floor_map = game.map(map_spec("alp_floor"))
    local crest_map = game.map(map_spec("alp_crest"))
    local lake_map = game.map(map_spec("alp_lake"))
    local fill = { y = 0.0, seed = MAP_SEED }
    height_map:fill(game.density(height()), fill)
    floor_map:fill(game.density(floor_mask()), fill)
    crest_map:fill(game.density(crest_mask()), fill)
    lake_map:fill(game.density(lake_mask()), fill)

    -- Sharpen: h + SHARPEN * (h - blur(h)). Convex ground stands up,
    -- concave ground cuts down.
    local high = game.map(map_spec("alp_scratch_high"))
    high:combine(height_map, "add")
    high:blur(SHARPEN_BLUR)
    high:scale_by(-1.0)
    high:combine(height_map, "add")                   -- h - blur(h)
    high:scale_by(SHARPEN)
    height_map:combine(high, "add")

    -- Needle peaks capped at PEAK_OVER above their neighbourhood mean.
    local mean = game.map(map_spec("alp_scratch_mean"))
    mean:combine(height_map, "add")
    mean:blur(PEAK_BLUR)
    mean:offset(PEAK_OVER)
    height_map:combine(mean, "min")

    -- Valley floors replaced by their own wide blur: flat and smooth where
    -- the floor mask is 1, untouched where it is 0.
    local smooth = game.map(map_spec("alp_scratch_smooth"))
    smooth:combine(height_map, "add")
    smooth:blur(FLOOR_BLUR)
    smooth:combine(floor_map, "mul")                  -- blur(h) * floor
    local keep = game.map(map_spec("alp_scratch_keep"))
    keep:combine(floor_map, "add")
    keep:scale_by(-1.0)
    keep:offset(1.0)                                  -- 1 - floor
    height_map:combine(keep, "mul")                   -- h * (1 - floor)
    height_map:combine(smooth, "add")                 -- + blur(h) * floor

    -- Lakes lie level: the floor under a lake replaced by a much wider
    -- blur of itself, the same way, so the ice sheet is flat to a block
    -- or so across a lake.
    local level = game.map(map_spec("alp_scratch_level"))
    level:combine(height_map, "add")
    level:blur(LAKE_BLUR)
    level:combine(lake_map, "mul")                    -- blur(h) * lake
    local land = game.map(map_spec("alp_scratch_land"))
    land:combine(lake_map, "add")
    land:scale_by(-1.0)
    land:offset(1.0)                                  -- 1 - lake
    height_map:combine(land, "mul")
    height_map:combine(level, "add")
    game.log(string.format("tiamot_default_world alpine: maps built, %d samples a side at %d blocks, origin %d, %d",
        MAP_SIDE, MAP_SCALE, MAP_ORIGIN_X, MAP_ORIGIN_Z))
end)

-- The map nodes for the field. Fetched when a program is compiled — at the
-- first alpine chunk, after the pre-pass (a map node copies the map as it
-- is when `game.density` runs, so a program compiled at load would carry
-- an empty one).
local function map_node(name)
    return { op = "map", map = game.map(map_spec(name)) }
end
function shape.alpine_terms()
    -- Rock: 1 on a wall or a crest, 0 on a floor or a snowfield, from the
    -- maps; the mid detail is DETAIL_ROCK times stronger there.
    local rock = n.clamp(n.add(n.mul(n.mul(map_node("alp_floor"), n.sub(n.const(1.0), map_node("alp_floor"))), n.const(WALL_GAIN)),
        map_node("alp_crest")), 0.0, 1.0)
    local detail = n.mul(n.mul(n.abs(n.noise("alp_detail", DETAIL_FREQ, 1, 1.0)), n.const(DETAIL_H)),
        n.add(n.const(1.0), n.mul(rock, n.const(DETAIL_ROCK))))
    local steps = n.mul(n.clamp(n.mul(n.noise("alp_steps", STEP_FREQ, 1, 1.0), n.const(STEP_STEEP)), -1.0, 1.0), n.const(STEP_H))
    return n.add(map_node("alp_height"), n.add(detail, steps))
end
shape.ALPINE_PEAK = RIDGE_AMP[1] + RIDGE_AMP[2] + RIDGE_AMP[3] + RIDGE_AMP[4] + BASE_AMP * shape.NOISE_RANGE

tdw.biomes.alpine_highlands.ring_mode = "alpine"
tdw.biomes.alpine_highlands.lazy = true               -- its programs read the maps: compiled at the first chunk
tdw.build_biome("alpine_highlands", function(ctx)
    local function masked(field)
        local mask = tdw.biome_mask(n, "frost", false)
        return mask and n.min(field, mask) or field
    end
    local function top()
        return shape.terrain_band(0.0, shape.SKIN_TOP, false)
    end
    local function high()                             -- positive above the snowline
        return n.sub(map_node("alp_height"), n.const(SNOWLINE))
    end
    local function low()
        return n.sub(n.const(SNOWLINE), map_node("alp_height"))
    end
    local function crest() return map_node("alp_crest") end
    local function floor() return map_node("alp_floor") end
    local function lake() return map_node("alp_lake") end
    local function dry() return n.sub(n.const(0.5), lake()) end   -- positive off the lakes
    -- The walls: the valley mask's transition band, f(1-f) scaled; and
    -- "faces up": positive off the walls.
    local function wall()
        return n.mul(n.mul(floor(), n.sub(n.const(1.0), floor())), n.const(WALL_GAIN))
    end
    local function faces_up() return n.sub(n.const(0.5), wall()) end
    -- The snowline by aspect, wandering and flecked: positive where the
    -- ground is above it.
    local function snow_high()
        local line = n.add(n.sub(n.const(SNOWLINE), n.mul(floor(), n.const(SNOW_VALLEY_DROP))),
            n.mul(crest(), n.const(SNOW_CREST_RAISE)))
        local broken = n.add(n.noise("snow_wander", SNOW_WANDER_FREQ, 2, SNOW_WANDER),
            n.noise("snow_fleck", SNOW_FLECK_FREQ, 1, SNOW_FLECK))
        return n.add(n.sub(map_node("alp_height"), line), broken)
    end
    -- A patch of a material: three octaves of its noise plus a fine dither,
    -- over its threshold.
    local function patchy(stream, freq, min)
        return n.sub(n.add(n.noise(stream, freq, 2, 1.0), n.noise(stream .. "_dither", PATCH_DITHER_FREQ, 1, PATCH_DITHER)),
            n.const(min))
    end
    -- The rock: granite as the skin, laid by the generator as the biome's
    -- soil; the fill is needed only where another biome shares the chunk.
    local granite = shape.compile("biome.alpine.granite", masked(top()))

    -- The grass: tufts of the biome's own grass, darker and bluer, stood
    -- on the ground by the cover fill below the snowline where the ground
    -- faces up, off the crests and the lakes; sparse, in a fine scatter.
    -- Built as a left-leaning chain, the terrain first: a nested tree of
    -- minimums holds every pending operand in a buffer, and this one has
    -- six terms against the engine's eight buffers. Terrain FIRST, the
    -- constant after: a constant pushed before it holds a buffer through
    -- the terrain's own peak, which is the ninth.
    local take = n.add(n.mul(shape.terrain(false), n.const(-1.0)), n.const(COVER_CELL / 2))
    for _, term in ipairs({ low(), dry(), faces_up(), n.sub(n.const(0.5), crest()),
        n.sub(n.noise("alp_tuft", TUFT_FREQ, 1, 1.0), n.const(TUFT_MIN)) }) do
        take = n.min(take, term)
    end
    local tufts = shape.compile("biome.alpine.tufts", masked(take))
    -- Snow below the line, in patches that thin out with depth.
    local function snow_patches()
        return n.sub(n.noise("snow_patch", SNOW_PATCH_FREQ, 2, 1.0),
            n.add(n.const(SNOW_PATCH_T), n.mul(n.mul(snow_high(), n.const(-1.0)), n.const(SNOW_PATCH_FADE))))
    end

    -- Every other surface material from ONE evaluation of the terrain
    -- (`buf:fill_layers`, engine): a CODE field names, per block, which set
    -- of depth bands the block gets, and the depth is the terrain, smooth
    -- at the cells. The code is the greatest of k * step(condition_k) over
    -- the layers, later layers larger, so a later layer wins where two
    -- apply — the order the separate fills had. Where no condition holds
    -- the code is 0 and the granite shows through.
    local function step(field)
        return n.clamp(n.mul(field, n.const(1e4)), 0.0, 1.0)
    end
    local function chain(first, rest, op)
        local acc = first
        for _, term in ipairs(rest) do acc = op(acc, term) end
        return acc
    end
    local conditions = {
        -- 1: slate seams through the rock.
        patchy("slate", SLATE_FREQ, SLATE_MIN),
        -- 2: scree on the risers and cirque walls below the snowline.
        chain(low(), { dry(), n.sub(crest(), n.const(0.3)), patchy("scree", SCREE_FREQ, SCREE_MIN) }, n.min),
        -- 3: permafrost in patches below the snowline.
        chain(low(), { dry(), patchy("permafrost", PERMAFROST_FREQ, PERMAFROST_MIN) }, n.min),
        -- 4: dirt over most ground below the snowline that faces up.
        chain(low(), { dry(), faces_up(), patchy("thin_dirt", DIRT_FREQ, DIRT_MIN) }, n.min),
        -- 5: turf over the dirt below the tree line.
        chain(low(), { dry(), faces_up(), patchy("thin_dirt", DIRT_FREQ, DIRT_MIN),
            n.sub(n.const(TREELINE / 1000), map_node("alp_height")), patchy("turf", TURF_FREQ, TURF_MIN) }, n.min),
        -- 6: snow above the line by aspect, and its patches below.
        chain(n.max(snow_high(), snow_patches()), { dry(), faces_up(), n.sub(n.const(0.5), crest()) }, n.min),
        -- 7: the glaciers: ice on the floors above the snowline.
        chain(high(), { dry(), n.sub(floor(), n.const(0.5)) }, n.min),
        -- 8: the lakes.
        n.sub(lake(), n.const(0.5)),
    }
    local code = n.const(0.0)
    for k, condition in ipairs(conditions) do
        code = n.max(code, n.mul(step(condition), n.const(k)))
    end
    local mask = tdw.biome_mask(n, "frost", false)
    if mask then
        code = n.mul(code, step(mask))
    end
    local depth = shape.compile("biome.alpine.depth", shape.terrain(false))
    local codes = shape.compile("biome.alpine.codes", code)
    local km = 0.001
    local entries = {
        { code = 1, to = 3 * km, material = blocks.slate },
        { code = 2, to = 3 * km, material = blocks.creek_bed },
        { code = 3, to = 3 * km, material = blocks.permafrost },
        { code = 4, to = 3 * km, material = blocks.dirt },
        { code = 5, to = 1 * km, material = blocks.alpine_turf },
        { code = 5, from = 1 * km, to = 3 * km, material = blocks.dirt },
        { code = 6, to = SNOW_DEPTH, material = blocks.snow },
        { code = 7, to = ICE_DEPTH, material = blocks.ice },
        { code = 8, to = LAKE_ICE, material = blocks.ice },
        { code = 8, from = LAKE_ICE, to = LAKE_ICE + LAKE_DEPTH, material = blocks.water },
    }
    return {
        { field = granite, material = blocks.granite, shared_only = true },
        { layers = true, depth = depth, code = codes, entries = entries },
        { cover = blocks.alpine_grass, cells = 2, take = tufts },
    }
end)
tdw.biomes.alpine_highlands.soil = blocks.granite

-- Runtime: boulders on the flats, hollows in the walls --------------------------
--
-- Grown by random tick, as the grasslands grow their erratics and dig
-- their burrows. A tick on snow, permafrost, dirt or scree at the surface
-- may put a boulder there if the ground is flat about it — granite mostly,
-- slate one in four, alone or in a cluster. A tick on granite that is a
-- wall face (air on one side, rock behind) may carve a hollow into it: a
-- short chain of rough spheres going in, a small cavern.

local edits, schem, rocks = tdw.edits, tdw.schem, tdw.rocks
local at, hash = schem.at, schem.hash
local FULL = game.OCCUPANCY_FULL
-- The edit queue's reserve for each kind: what may still be queued past
-- the common limit. Firs are the common thing and get none; hollows are
-- rare and get the most, so a full queue of firs never starves them.
local RESERVE = { fir = 0, rock = 2, boulder = 3, hollow = 6, crevasse = 8 }

local BOULDER_CHANCE = 20      -- one surface block in this many, in a square that has them
local BOULDER_CELL = 48        -- squares this wide...
local BOULDER_CELL_ONE_IN = 2  -- ...one in this many has boulders
local BOULDER_R = { 3.6, 4.7 } -- half-width, blocks: least and extra (doubled 2026-09-12, then up three tenths)
local ROCK_CHANCE = 45         -- small rocks, everywhere flat: one surface block in this many
local ROCK_R = { 0.5, 0.5 }    -- half-width, blocks: least and extra
-- Firs, below a rough tree line: TREELINE blocks over the base dome,
-- jittered TREELINE_JITTER either way per TREELINE_CELL square. Tall and
-- thin; one in three is a big one.
local TREELINE_JITTER = 40
local TREELINE_CELL = 24
local TREE_CHANCE = 3          -- one surface block in this many, below the line: the forest fills in within a minute or two of a chunk loading, held apart by TREE_APART; a try is one read when the block above is not air
local TREE_APART = 3           -- never within this many blocks of another fir's trunk
local FIR_SMALL = { 8, 6 }     -- blocks of height: least and extra
local FIR_BIG = { 18, 11 }
local DEAD_ONE_IN = 21         -- of the firs, one in this many is dead wood: half snags, half fallen (twice the woodlands' rate)
local HOLLOW_CHANCE = 120      -- one surface block in this many, in a square that has them; most find no wall within three blocks, cheaply
local HOLLOW_CELL = 64
local HOLLOW_CELL_ONE_IN = 2
local HOLLOW_R = { 1.6, 1.4 }  -- the first sphere's half-width: least and extra
-- Crevasses: now and then, on the glaciers and the high snow, a long
-- crack down into the ground, ice-coated. One tall ellipsoid of ice
-- written first and a slightly smaller one carved as air inside it, so
-- the walls are ice. Along x or z.
local CREVASSE_CHANCE = 300    -- one ice or high-snow block in this many, in a square that has them
local CREVASSE_CELL = 128
local CREVASSE_CELL_ONE_IN = 3
local CREVASSE_LENGTH = { 14, 20 }  -- blocks: least and extra
local CREVASSE_DEPTH = { 8, 14 }
local CREVASSE_HALF = { 0.7, 0.9 }  -- half-width, blocks: least and extra
local CREVASSE_COAT = 0.7           -- how far past the crack the ice reaches
local STATS_EVERY = 200

local GRANITE, SLATE = "tiamot_default_world:granite", "tiamot_default_world:slate"
local FIR_LOG, FIR_NEEDLES = "tiamot_default_world:fir_log", "tiamot_default_world:fir_needles"
local DEAD = "tiamot_default_world:dead_wood"
local DIR8 = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }

local stats = { turns = 0, boulders = 0, boulder_tries = 0, rocks = 0, rock_tries = 0, firs = 0, fir_tries = 0,
    crevasses = 0, crevasse_tries = 0,
    hollows = 0, hollow_tries = 0, hollow_room = 0, hollow_unloaded = 0,
    flat = 0, wall = 0, headroom = 0, spacing = 0, unloaded = 0, no_room = 0, errors = 0 }
local last_error = nil

local function candidate(x, y, z, one_in)
    return hash(x, y, z) % one_in == 0
end
local function is_air(b) return b ~= nil and b.occupancy == 0 end
local function is_fir(b) return b ~= nil and b.occupancy ~= 0 and b.material == blocks.fir_log end
-- Whether a tick here is this biome's: everywhere, or in the frost ring.
local function mine(x, z)
    local only = tdw.config.everywhere
    if only then return only == "alpine_highlands" end
    local u = (x * x + z * z) * 1e-6 / (shape.R_DISC * shape.R_DISC)
    local ring = tdw.layers.ring_by_id.frost
    return u >= ring.u[1] and u < ring.u[2]
end
-- The ground is flat about (x, z): the surface within two blocks of its
-- height three blocks out each way — the ledges and steps make even a
-- flat here a little rough. nil when any of it is unloaded.
local function flat_at(x, y, z)
    local g0 = rocks.surface_at(x, z, y)
    if g0 == nil then return nil end
    for _, d in ipairs({ { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } }) do
        local g = rocks.surface_at(x + d[1], z + d[2], y)
        if g == nil then return nil end
        if math.abs(g - g0) > 2 then return false end
    end
    return true
end

local function place_boulder(x, y, z, rng)
    if not edits.room(RESERVE.boulder) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local flat = flat_at(x, y, z)
    if flat == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    elseif not flat then
        stats.flat = stats.flat + 1
        return false
    end
    local ground, top = rocks.surface_at(x, z, y)
    local material = rng:below(4) == 0 and SLATE or GRANITE
    local r = BOULDER_R[1] + rng:below(6) / 10 * BOULDER_R[2]
    edits.begin()
    if rng:below(3) == 0 then
        rocks.place_cluster(material, x, y, z, rng, { big = r + 0.4, satellites = 2 + rng:below(3), pebbles = 3 })
    else
        local surface = ground + (top.occupancy == FULL and 1.0 or 0.6)
        rocks.place_rock(material, x, surface, z, r, rng,
            { cuts = 1 + rng:below(2), buried = 0.3 + rng:below(3) / 10, squat = 0.6 + rng:below(4) / 10 })
    end
    return edits.commit(RESERVE.boulder)
end

-- A small rock: a lone stone half a block or so across, on the flats.
local function place_small_rock(x, y, z, rng)
    if not edits.room(RESERVE.rock) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local flat = flat_at(x, y, z)
    if flat == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    elseif not flat then
        stats.flat = stats.flat + 1
        return false
    end
    local ground, top = rocks.surface_at(x, z, y)
    local surface = ground + (top.occupancy == FULL and 1.0 or 0.6)
    local material = rng:below(4) == 0 and SLATE or GRANITE
    edits.begin()
    rocks.place_rock(material, x, surface, z, ROCK_R[1] + rng:below(6) / 10 * ROCK_R[2], rng,
        { cuts = rng:below(2), buried = 0.3 + rng:below(3) / 10, squat = 0.7 + rng:below(3) / 10 })
    return edits.commit(RESERVE.rock)
end

-- Height of a surface block over the base dome, in blocks.
local function over_dome(x, y, z)
    local u = (x * x + z * z) * 1e-6 / (shape.R_DISC * shape.R_DISC)
    return (y - shape.Y0) - shape.dome_at(u) * 1000
end
-- The tree line at (x, z): rough, by a hashed jitter per square.
local function treeline_at(x, z)
    return TREELINE + (hash(x // TREELINE_CELL, 7, z // TREELINE_CELL) % (2 * TREELINE_JITTER + 1)) - TREELINE_JITTER
end
-- Another fir's trunk within TREE_APART: eight headings, each distance,
-- two heights — a trunk is at least eight blocks, so a read at one block
-- up and one at four cannot both miss it. Forty-eight reads, not the
-- hundred and sixty-eight of a read at every height, which was most of
-- the mod's tick once the forest had filled in and every try was this.
local function fir_near(x, y, z)
    for _, d in ipairs(DIR8) do
        for r = 1, TREE_APART do
            local sx, sz = x + d[1] * r, z + d[2] * r
            if is_fir(at(sx, y + 1, sz)) or is_fir(at(sx, y + 4, sz)) then
                return true
            end
        end
    end
    return false
end

-- The trunk's cross-section: the middle cell column and the four beside
-- it, a plus, in every layer of the block. One mask, written per block,
-- so the trunk is the same plus all the way up — an ellipsoid thin enough
-- to be a trunk rounded to one cell in some blocks and a plus in others.
local PLUS = 0
for cy = 0, 2 do
    PLUS = PLUS | schem.bit(1, cy, 1) | schem.bit(0, cy, 1) | schem.bit(2, cy, 1) | schem.bit(1, cy, 0) | schem.bit(1, cy, 2)
end

-- A fallen fir lying along x or z: two cells tall and one wide, the
-- thin trunk it was, merged into the surface block of each column it
-- crosses so it reads as half sunk. The masks, one per direction.
local LYING = { x = 0, z = 0 }
for c = 0, 2 do
    for cy = 0, 1 do
        LYING.x = LYING.x | schem.bit(c, cy, 1)
        LYING.z = LYING.z | schem.bit(1, cy, c)
    end
end

-- Dead wood, one fir in DEAD_ONE_IN: a snag — the plus trunk in dead wood,
-- shorter, its top block holding only some of the plus, a stub or two —
-- or a fallen trunk.
local function grow_snag(x, y, z, rng, ground, top_block, big)
    local height = math.floor(schem.pick(rng, big and FIR_BIG or FIR_SMALL) * (0.4 + rng:below(4) / 10))
    for dy = 1, height do
        if not is_air(at(x, y + dy, z)) then
            stats.headroom = stats.headroom + 1
            return false
        end
    end
    edits.begin()
    local base = top_block.occupancy == FULL and ground + 1 or ground
    for by = base, base + height - 2 do
        edits.push({ x = x, y = by, z = z }, DEAD, PLUS, true)
    end
    -- The broken top: the plus's bottom layer and a couple of cells above.
    local jag = 0
    for _, c in ipairs({ { 1, 1 }, { 0, 1 }, { 2, 1 }, { 1, 0 }, { 1, 2 } }) do
        jag = jag | schem.bit(c[1], 0, c[2])
    end
    for _ = 1, 1 + rng:below(3) do
        jag = jag | schem.bit(1, 1 + rng:below(2), 1)
    end
    edits.push({ x = x, y = base + height - 1, z = z }, DEAD, jag, true)
    -- A stub or two: a bar out from the upper trunk.
    for _ = 1, 1 + rng:below(2) do
        local d = DIR8[rng:below(4) * 2 + 1]
        local sy = base + height - 2 - rng:below(math.max(1, height - 3))
        if is_air(at(x + d[1], sy, z + d[2])) then
            local bar = d[1] ~= 0 and LYING.x or LYING.z
            edits.push({ x = x + d[1], y = sy, z = z + d[2] }, DEAD, bar & ~(schem.bit(1, 1, 1) | schem.bit(0, 1, 1) | schem.bit(2, 1, 1) | schem.bit(1, 1, 0) | schem.bit(1, 1, 2)), true)
        end
    end
    return edits.commit(RESERVE.fir)
end

local function lay_fir(x, y, z, rng, big)
    local along_x = rng:next_bool()
    local dir = rng:next_bool() and 1 or -1
    local length = big and (8 + rng:below(6)) or (4 + rng:below(4))
    local mask = along_x and LYING.x or LYING.z
    local placed = 0
    edits.begin()
    for i = 0, length - 1 do
        local lx = along_x and x + i * dir or x
        local lz = along_x and z or z + i * dir
        -- The surface block of this column: partly filled, found from the
        -- start height down, then up.
        local ly = nil
        for dy = 0, -2, -1 do
            local b = at(lx, y + dy, lz)
            if b ~= nil and b.occupancy ~= 0 and b.occupancy ~= FULL then
                ly = y + dy
                break
            end
        end
        if ly == nil and is_air(at(lx, y, lz)) then
            local under = at(lx, y - 1, lz)
            if under ~= nil and under.occupancy == FULL then ly = y end
        end
        if ly ~= nil then
            edits.push({ x = lx, y = ly, z = lz }, DEAD, mask, true)
            placed = placed + 1
        end
    end
    if placed < 3 then
        edits.commit(RESERVE.fir)                        -- an empty-enough batch: commit clears it
        return false
    end
    return edits.commit(RESERVE.fir)
end

-- A fir: tall and thin. A plus-shaped trunk, bare for the lowest sixth,
-- and above that a cone of needle pads — flat rough ellipsoids shrinking
-- from the skirt to a point — every block on a small tree, every other
-- block on a big one, so the big ones read as tiered. Needles first, the
-- trunk last so wood wins any cell both claim.
local function grow_fir(x, y, z, rng)
    if not edits.room(RESERVE.fir) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local ground, top = rocks.surface_at(x, z, y)
    if ground == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    -- The block above first: a tick on buried snow is most tries, and one
    -- read settles it before the loaded box and the spacing scan.
    if not is_air(at(x, y + 1, z)) then
        stats.headroom = stats.headroom + 1
        return false
    end
    local big = rng:below(3) == 0
    local height = schem.pick(rng, big and FIR_BIG or FIR_SMALL)
    local reach = big and 12 or 6
    if not schem.loaded_box(x - reach, y - 2, z - reach, x + reach, y + height + 3, z + reach) then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    -- Dead wood, now and then: a snag or a fallen trunk instead.
    local dead = rng:below(DEAD_ONE_IN) == 0
    if dead then
        if fir_near(x, y, z) then
            stats.spacing = stats.spacing + 1
            return false
        end
        if rng:next_bool() then
            return grow_snag(x, y, z, rng, ground, top, big)
        end
        return lay_fir(x, y, z, rng, big)
    end
    for dy = 1, height do
        if not is_air(at(x, y + dy, z)) then
            stats.headroom = stats.headroom + 1
            return false
        end
    end
    if fir_near(x, y, z) then
        stats.spacing = stats.spacing + 1
        return false
    end
    local surface = ground + (top.occupancy == FULL and 1.0 or 0.6)
    local base_r = big and (2.25 + rng:below(7) / 10) or (1.4 + rng:below(6) / 10)   -- up an eighth in width: a quarter more needles
    local skirt = math.max(1, math.floor(height / 6))
    local every = big and 2 or 1
    edits.begin()
    for i = skirt, height - 1, every do
        local t = (i - skirt) / (height - skirt)
        local r = base_r * (1.0 - t) + 0.35
        schem.push_ellipsoid(FIR_NEEDLES, x + 0.5, surface + i + 0.5, z + 0.5, r, 0.65, r, { rough = 0.3, jitter = rng })
    end
    schem.push_ellipsoid(FIR_NEEDLES, x + 0.5, surface + height + 0.3, z + 0.5, 0.45, 0.9, 0.45, { rough = 0.2 })
    -- The trunk: from the block the surface is in (or the one above a
    -- whole block) up through the pads, merged so the needles stay.
    local base = top.occupancy == FULL and ground + 1 or ground
    for by = base, base + height - 1 do
        edits.push({ x = x, y = by, z = z }, FIR_LOG, PLUS, true)
    end
    return edits.commit(RESERVE.fir)
end

-- A hollow: from a SURFACE tick, a wall found by looking three blocks out
-- each way — where the ground stands WALL_RISE or more higher there is a
-- face between — and a chain of two to four rough spheres carved into it
-- at the foot, each a little smaller, wandering a little: a small cavern.
-- (A tick on rock itself was tried first and found faces almost never:
-- the random tick picks through the whole loaded volume, and a face is a
-- vanishing share of the stone.)
local WALL_RISE = 5
-- The surface at (x, z) looking well above the hint: the rocks module's
-- probe scans two blocks up, and a wall five blocks higher is above its
-- window, which read as unloaded. nil only when a read is.
local function ground_at(x, z, hint)
    local above = at(x, hint + 13, z)
    for yy = hint + 12, hint - 6, -1 do
        local b = at(x, yy, z)
        if b == nil or above == nil then return nil end
        if b.occupancy ~= 0 and above.occupancy == 0 then return yy end
        above = b
    end
    return hint - 6
end
local function carve_hollow(x, y, z, rng)
    if not edits.room(RESERVE.hollow) then
        stats.hollow_room = stats.hollow_room + 1
        return false
    end
    local g0 = ground_at(x, z, y)
    if g0 == nil then
        stats.hollow_unloaded = stats.hollow_unloaded + 1
        return false
    end
    local dir, rise = nil, 0
    for _, d in ipairs(DIR8) do
        local g = ground_at(x + 3 * d[1], z + 3 * d[2], y)
        if g == nil then
            stats.hollow_unloaded = stats.hollow_unloaded + 1
            return false
        end
        if g - g0 > rise then
            dir, rise = d, g - g0
        end
    end
    if dir == nil or rise < WALL_RISE then
        stats.wall = stats.wall + 1
        return false
    end
    if not schem.loaded_box(x - 7, y - 4, z - 7, x + 7, y + 6, z + 7) then
        stats.hollow_unloaded = stats.hollow_unloaded + 1
        return false
    end
    edits.begin()
    local r = HOLLOW_R[1] + rng:below(6) / 10 * HOLLOW_R[2]
    -- Start a block out from the tick, at the wall's foot, and go in.
    local cx, cy, cz = x + 0.5 + dir[1] * 1.5, g0 + 1.4 + r * 0.5, z + 0.5 + dir[2] * 1.5
    for _ = 1, 2 + rng:below(3) do
        schem.push_ellipsoid("engine:air", cx, cy, cz, r, r * 0.8, r, { carve = true, rough = 0.3 })
        cx = cx + dir[1] * r * 1.2 + (rng:below(3) - 1) * 0.5
        cz = cz + dir[2] * r * 1.2 + (rng:below(3) - 1) * 0.5
        cy = cy + rng:below(3) * 0.2
        r = r * (0.85 + rng:below(3) / 10)
    end
    return edits.commit(RESERVE.hollow)
end

-- A crevasse: from a tick on ice or high snow, a crack CREVASSE_LENGTH long
-- along x or z, CREVASSE_DEPTH deep in the middle and shallowing to its
-- ends (an ellipsoid's profile), one to three blocks wide, its walls
-- coated with ice. Two writes: ice over the crack's bounds plus the coat,
-- then the crack carved out of that as air — merged, so the ground round
-- it stays.
local function carve_crevasse(x, y, z, rng, anywhere)
    if not edits.room(RESERVE.crevasse) then
        stats.no_room = stats.no_room + 1
        return false
    end
    local b = at(x, y, z)
    if b == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    if not anywhere and not (b.material == blocks.ice or (b.material == blocks.snow and over_dome(x, y, z) > SNOWLINE * 1000)) then
        return false
    end
    local ground = ground_at(x, z, y)
    if ground == nil then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    local length = schem.pick(rng, CREVASSE_LENGTH)
    local depth = schem.pick(rng, CREVASSE_DEPTH)
    local half = CREVASSE_HALF[1] + rng:below(10) / 10 * CREVASSE_HALF[2]
    local along_x = rng:next_bool()
    local reach = length // 2 + 3
    if not schem.loaded_box(x - reach, ground - depth - 3, z - reach, x + reach, ground + 3, z + reach) then
        stats.unloaded = stats.unloaded + 1
        return false
    end
    -- Centred a little under the surface so the crack opens at the top:
    -- the ellipsoid's top sits a block over the ground, and the carve is
    -- clipped to what is there.
    local cx, cy, cz = x + 0.5, ground + 1.0 - depth * 0.5, z + 0.5
    local rx = along_x and length * 0.5 or half
    local rz = along_x and half or length * 0.5
    edits.begin()
    schem.push_ellipsoid("tiamot_default_world:ice", cx, cy, cz, rx + CREVASSE_COAT, depth * 0.5 + CREVASSE_COAT, rz + CREVASSE_COAT,
        { rough = 0.25, over_whole = true })
    schem.push_ellipsoid("engine:air", cx, cy, cz, rx, depth * 0.5, rz, { carve = true, rough = 0.35 })
    return edits.commit(RESERVE.crevasse)
end

-- Say `crevasse` in chat and one is carved where you stand, whatever the
-- ground: a way to look at one, and the way the headless test reaches it.
tdw.on_chat("crevasse", function(player)
    local body = game.player_entity(player)
    local entity = body and game.entity(body)
    local p = entity and entity.pos
    if p == nil then return end
    local x, y, z = math.floor(p.x), math.floor(p.y) - 1, math.floor(p.z)
    local rng = game.rng_stream({ x = x // 16, y = y // 16, z = z // 16, seed = tdw.seed or 0 }, "crevasse:chat:" .. x .. ":" .. z)
    local ok = carve_crevasse(x, y, z, rng, true)
    game.log(string.format("tiamot_default_world alpine: crevasse at %d, %d, %d: %s", x, y, z, ok and "carved" or "refused"))
end)

local function try(name, fn, x, y, z)
    stats[name .. "_tries"] = stats[name .. "_tries"] + 1
    local rng = game.rng_stream({ x = x // 16, y = y // 16, z = z // 16, seed = tdw.seed or 0 }, name .. ":" .. x .. ":" .. y .. ":" .. z)
    local ok, result = pcall(fn, x, y, z, rng)
    if not ok then
        stats.errors = stats.errors + 1
        last_error = tostring(result)
    elseif result then
        stats[name .. "s"] = stats[name .. "s"] + 1
    end
end

local function on_surface(x, y, z)
    if not mine(x, z) then return false end
    stats.turns = stats.turns + 1
    -- Below the tree line a fir first; then the boulders, in their
    -- squares; then the small rocks, everywhere.
    -- Each kind draws from its own salt of the hash: a chance of one in 45
    -- drawn from the same number as a chance of one in 9 is never a rock,
    -- because 45 is 9 times 5 and the tree took it first.
    if candidate(x, y + 4000, z, CREVASSE_CHANCE) and candidate(x // CREVASSE_CELL, 37, z // CREVASSE_CELL, CREVASSE_CELL_ONE_IN) then
        try("crevasse", carve_crevasse, x, y, z)
    elseif over_dome(x, y, z) < treeline_at(x, z) and candidate(x, y, z, TREE_CHANCE) then
        try("fir", grow_fir, x, y, z)
    elseif candidate(x, y + 1000, z, BOULDER_CHANCE) and candidate(x // BOULDER_CELL, 29, z // BOULDER_CELL, BOULDER_CELL_ONE_IN) then
        try("boulder", place_boulder, x, y, z)
    elseif candidate(x, y + 2000, z, ROCK_CHANCE) then
        try("rock", place_small_rock, x, y, z)
    elseif candidate(x, y + 3000, z, HOLLOW_CHANCE) and candidate(x // HOLLOW_CELL, 31, z // HOLLOW_CELL, HOLLOW_CELL_ONE_IN) then
        try("hollow", carve_hollow, x, y, z)
    end
    return true
end
for _, material in ipairs({ blocks.snow, blocks.permafrost, blocks.dirt, blocks.creek_bed, blocks.alpine_turf, blocks.ice }) do
    tdw.on_random_tick(material, on_surface)
end


local since = 0
tdw.on_tick(function(dt_ticks)
    since = since + dt_ticks
    if since < STATS_EVERY then return end
    since = 0
    if stats.turns == 0 then return end
    game.log(string.format(
        "tiamot_default_world alpine: %d turns, %d firs of %d, %d boulders of %d, %d rocks of %d, %d crevasses of %d, %d hollows of %d (no wall %d, room %d, unloaded %d); refused: flat %d, headroom %d, spacing %d, room %d, unloaded %d; errors %d (%s)",
        stats.turns, stats.firs, stats.fir_tries, stats.boulders, stats.boulder_tries, stats.rocks, stats.rock_tries,
        stats.crevasses, stats.crevasse_tries,
        stats.hollows, stats.hollow_tries, stats.wall, stats.hollow_room, stats.hollow_unloaded,
        stats.flat, stats.headroom, stats.spacing, stats.no_room, stats.unloaded, stats.errors, last_error or "none"))
    for key in pairs(stats) do stats[key] = 0 end
end)
