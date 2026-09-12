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
local RIDGE_AMP = { 0.50, 0.25, 0.1125, 0.05 }        -- km per octave: peaks near 0.9 km
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
-- Erosion passes, 1.75 times the first cut: the radii in blocks, and the
-- cap that much lower against the range's scale.
local PEAK_BLUR = 3                                   -- samples (48 blocks): the neighbourhood a peak is judged against
local PEAK_OVER = 0.036                               -- km: how far a peak may stand over that mean
local FLOOR_BLUR = 4                                  -- samples (64 blocks): how smooth a valley floor is
-- Where the crests are, for the rock: the primary ridge term over this.
local CREST_FROM = 0.78
local CREST_K = 8
-- Lakes: where the lake noise is over LAKE_T, on the floors; its edge
-- crosses in 1/LAKE_K of the noise. About a fifth of the floors, in
-- bodies a hundred and fifty to three hundred blocks across.
local LAKE_FREQ = 1 / 450
local LAKE_T = 0.10
local LAKE_K = 15
local LAKE_BLUR = 10                                  -- samples (160 blocks): a lake lies level
local LAKE_DEPTH = 0.008                              -- km: eight blocks of water under the ice
local LAKE_ICE = 0.001                                -- km: one block of ice on top

-- The materials. The snowline is not one height: it comes down
-- SNOW_VALLEY_DROP in the valleys (the floor mask) and goes up
-- SNOW_CREST_RAISE on the crests, and the walls — the valley mask's own
-- transition band, WALL_GAIN times f(1-f) — carry none: snow lies where
-- the ground faces up, which is the dot product the designer asked for,
-- read from the two masks the map already carries.
local SNOWLINE = 0.125                                -- km above the dome: snow and ice above, slopes below
local SNOW_VALLEY_DROP = 0.08                         -- km: how much lower the snow reaches down a valley
local SNOW_CREST_RAISE = 0.10                         -- km: how much higher it must be to lie on a crest
local WALL_GAIN = 6.0                                 -- f(1-f) peaks at 1/4; x6 makes the wall band read as 1
local SNOW_DEPTH = 0.004                              -- km: four blocks of packed snow
local ICE_DEPTH = 0.003                               -- km: three blocks of glacier
local SLATE_FREQ = 1 / 90
local SLATE_MIN = 0.12
local SCREE_FREQ = 1 / 40
local SCREE_MIN = -0.05
local PERMAFROST_FREQ = 1 / 120
local PERMAFROST_MIN = 0.06
local DIRT_FREQ = 1 / 70
local DIRT_MIN = 0.16
local DIRT_DEPTH = 0.0015
local CRAG_H = 0.003                                  -- km: the 3D roughness left in the field

local function map_spec(name)
    return { name = name, side = MAP_SIDE, scale = MAP_SCALE, origin_x = MAP_ORIGIN_X, origin_z = MAP_ORIGIN_Z }
end

-- A ridge: 1 on the noise's zero contour, 0 where |n| reaches its range.
local function ridge(stream, freq)
    return n.clamp(n.mul(n.sub(n.const(shape.NOISE_RANGE * 0.84), n.abs(n.noise(stream, freq, 1, 1.0))),
        n.const(1.0 / (shape.NOISE_RANGE * 0.84))), 0.0, 1.0)
end
local function r(k) return ridge("alp_ridge" .. k, RIDGE_FREQ * 2 ^ (k - 1)) end
-- The range: A1 r1^2 + A2 r1 r2 + A3 r2 r3 + A4 r3 r4. A ridge appears
-- twice because the stack machine has no dup; the map is filled once.
local function range()
    return n.add(n.add(n.mul(n.mul(r(1), r(1)), n.const(RIDGE_AMP[1])), n.mul(n.mul(r(1), r(2)), n.const(RIDGE_AMP[2]))),
        n.add(n.mul(n.mul(r(2), r(3)), n.const(RIDGE_AMP[3])), n.mul(n.mul(r(3), r(4)), n.const(RIDGE_AMP[4]))))
end
-- 1 on a valley floor, 0 on the massif, a wall between: the floor is the
-- band |v| < VALLEY_W about the valley noise's zero contour.
local function floor_mask()
    return n.clamp(n.mul(n.sub(n.const(VALLEY_W), n.abs(n.noise("alp_valley", VALLEY_FREQ, 2, 1.0))), n.const(VALLEY_K)), 0.0, 1.0)
end
-- The height: the range pulled down to its floor share where the floor
-- mask is 1, the floor's own height added there, and the tilt under all.
local function height()
    local kept = n.add(n.const(1.0), n.mul(floor_mask(), n.const(VALLEY_FLOOR - 1.0)))
    return n.add(n.add(n.mul(range(), kept), n.mul(floor_mask(), n.const(VALLEY_BASE))),
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
    return n.add(map_node("alp_height"), n.mul(n.abs(n.noise("crag", 1 / 35, 2, 1.0)), n.const(CRAG_H)))
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
    -- The snowline by aspect: positive where the ground is above it.
    local function snow_high()
        local line = n.add(n.sub(n.const(SNOWLINE), n.mul(floor(), n.const(SNOW_VALLEY_DROP))),
            n.mul(crest(), n.const(SNOW_CREST_RAISE)))
        return n.sub(map_node("alp_height"), line)
    end
    -- The rock: granite as the skin, slate in seams through it.
    local granite = shape.compile("biome.alpine.granite", masked(top()))
    local slate = shape.compile("biome.alpine.slate", masked(n.min(top(),
        n.sub(n.noise("slate", SLATE_FREQ, 1, 1.0), n.const(SLATE_MIN)))))
    -- The lower slopes, below the snowline: scree under the crests, in
    -- tongues; permafrost and thin dirt in patches elsewhere.
    local scree = shape.compile("biome.alpine.scree", masked(n.min(n.min(top(), n.min(low(), dry())),
        n.min(n.sub(crest(), n.const(0.3)), n.sub(n.noise("scree", SCREE_FREQ, 1, 1.0), n.const(SCREE_MIN))))))
    local permafrost = shape.compile("biome.alpine.permafrost", masked(n.min(n.min(top(), n.min(low(), dry())),
        n.sub(n.noise("permafrost", PERMAFROST_FREQ, 1, 1.0), n.const(PERMAFROST_MIN)))))
    local dirt = shape.compile("biome.alpine.dirt", masked(n.min(n.min(
        shape.terrain_band(0.0, DIRT_DEPTH, false), n.min(low(), dry())),
        n.sub(n.noise("thin_dirt", DIRT_FREQ, 1, 1.0), n.const(DIRT_MIN)))))
    -- Above the snowline by aspect: snow four blocks deep where the ground
    -- faces up — not on the walls, not on the crests — and ice three deep
    -- on the floors: the glaciers. Not on the lakes, which are their own.
    local snow = shape.compile("biome.alpine.snow", masked(n.min(n.min(
        shape.terrain_band(0.0, SNOW_DEPTH, false), n.min(snow_high(), dry())),
        n.min(faces_up(), n.sub(n.const(0.5), crest())))))
    local ice = shape.compile("biome.alpine.ice", masked(n.min(n.min(
        shape.terrain_band(0.0, ICE_DEPTH, false), n.min(high(), dry())), n.sub(floor(), n.const(0.5)))))
    -- The lakes: a block of ice at the surface and eight of water under
    -- it, written last so they take the lake's top from whatever the fills
    -- above left there.
    local lake_water = shape.compile("biome.alpine.lake_water", masked(n.min(
        shape.terrain_band(LAKE_ICE, LAKE_ICE + LAKE_DEPTH, false), n.sub(lake(), n.const(0.5)))))
    local lake_ice = shape.compile("biome.alpine.lake_ice", masked(n.min(
        shape.terrain_band(0.0, LAKE_ICE, false), n.sub(lake(), n.const(0.5)))))
    return {
        { field = granite, material = blocks.granite },
        { field = slate, material = blocks.slate },
        { field = scree, material = blocks.creek_bed },
        { field = permafrost, material = blocks.permafrost },
        { field = dirt, material = blocks.dirt },
        { field = snow, material = blocks.snow },
        { field = ice, material = blocks.ice },
        { field = lake_water, material = blocks.water },
        { field = lake_ice, material = blocks.ice },
    }
end)
tdw.biomes.alpine_highlands.soil = blocks.granite
