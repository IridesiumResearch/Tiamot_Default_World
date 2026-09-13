-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The area and biome registry.
--
-- AGENTS.md is right that a biome registry needs nothing from the engine: it is
-- a Lua table. What a biome IS here:
--
--   * metadata  - id, name, which area, and where in that area it lives
--                 (a surface ring and a humidity band; a depth band; a shell;
--                 a stretch of the tail). This is what every biome has from
--                 the day it is listed.
--   * build()   - optional. Called once at load; returns the native fills the
--                 generator runs for chunks that can touch this biome. A biome
--                 without one is REGISTERED BUT NOT BUILT: the catalogue lists
--                 it, the log names it, and the ground under it stays the
--                 area's default material until someone writes the file.
--
-- Building one biome at a time is the plan, so the registry is designed to
-- make an unbuilt biome cheap to list and a built one one file to add.

local M = {}
tdw.areas = {}
tdw.area_list = {}
tdw.biomes = {}
tdw.biome_list = {}

-- An area is a division of the world: the surface, a depth band, a shell,
-- a stretch of the tail. `kind` says which coordinate bounds it.
---@param spec { id: string, name: string, kind: "surface"|"depth"|"shell"|"tail", note: string? }
function tdw.register_area(spec)
    assert(spec.id and spec.name and spec.kind, "register_area needs id, name and kind")
    assert(not tdw.areas[spec.id], "area registered twice: " .. spec.id)
    spec.biomes = {}
    tdw.areas[spec.id] = spec
    tdw.area_list[#tdw.area_list + 1] = spec
    return spec
end

-- A biome inside an area. Surface biomes name a `ring` from layers.RINGS and
-- optionally a `humidity` band in the noise's +/-0.42 range; `build` is the
-- function that makes it real.
---@param spec { id: string, name: string, area: string, ring: string?, humidity: number[]?, note: string?, build: (fun(ctx: table): table)? }
function tdw.register_biome(spec)
    assert(spec.id and spec.name and spec.area, "register_biome needs id, name and area")
    local area = tdw.areas[spec.area]
    assert(area, "biome " .. spec.id .. " names an unknown area " .. tostring(spec.area))
    assert(not tdw.biomes[spec.id], "biome registered twice: " .. spec.id)
    if spec.ring then
        assert(tdw.layers.ring_by_id[spec.ring], "biome " .. spec.id .. " names an unknown ring " .. spec.ring)
    end
    spec.fills = nil
    tdw.biomes[spec.id] = spec
    tdw.biome_list[#tdw.biome_list + 1] = spec
    area.biomes[#area.biomes + 1] = spec
    return spec
end

-- Attaches the native fills to an already-listed biome. Kept separate from
-- registration so the catalogue can list everything first and each biome's
-- own file can build it later, in load order.
---@param id string
---@param build fun(ctx: table): table  -- returns { { field = Density, material = integer } | { cover = integer, cells = integer, take = Density }, ... }
function tdw.build_biome(id, build)
    local biome = tdw.biomes[id]
    assert(biome, "build_biome: no biome called " .. tostring(id))
    assert(not biome.fills, "biome built twice: " .. id)
    local ctx = {
        shape = tdw.shape, blocks = tdw.blocks, layers = tdw.layers,
        node = tdw.shape.node, sub = tdw.shape.sub,
        -- True when this biome is being put over the whole surface: leave
        -- the ring and humidity masks out of the fills.
        everywhere = tdw.config.everywhere == id,
    }
    -- The same builder, run once per terrain mode the biome's fills are
    -- needed in (shape.lua, "terrain MODES"): its own ring's mode for the
    -- chunks wholly in its ring, and "all" for the band where rings meet —
    -- a fill has the terrain inside it, and must carry the same terms the
    -- chunk's surface was made from or it paints at the wrong height.
    local function compile_fills(mode)
        tdw.shape.terrain_mode = mode
        local fills = build(ctx)
        tdw.shape.terrain_mode = nil
        assert(type(fills) == "table", "build for " .. id .. " must return a list of fills")
        for i, fill in ipairs(fills) do
            -- A fill paints where its field is positive; a cover stands a
            -- run of cells on the surface the fills made, where its take is.
            assert((fill.field and fill.material) or (fill.cover and fill.take)
                or (fill.layers and fill.depth and fill.code and fill.entries)
                or (fill.scatter and fill.depth and fill.schematics),
                "fill " .. i .. " of " .. id .. " needs field and material, cover and take, layers with depth, code and entries, or scatter with depth and schematics")
        end
        return fills
    end
    local own = tdw.config.everywhere and tdw.shape.default_mode() or biome.ring_mode or "temperate"
    biome.built = true
    biome.own_mode = own
    biome.compile_fills = compile_fills
    -- What is compiled now and what waits for the first chunk. A lazy
    -- biome's programs read maps the world pre-pass builds, which do not
    -- exist at load; the cross-faded ("all") fills of EVERY biome read them
    -- too, since they carry the alpine terms; and a biome that is not the
    -- one the dev switch puts everywhere is never asked for fills at all.
    -- The rest compiles here, where `--check-mods` sees it.
    local only = tdw.config.everywhere
    if only and only ~= id then
        game.log(string.format("tiamot_default_world biome %-24s built, fills not compiled (%s is everywhere)", id, only))
        return
    end
    if biome.lazy then
        game.log(string.format("tiamot_default_world biome %-24s built lazily, mode %s", id, own))
        return
    end
    biome.fills = compile_fills(own)
    game.log(string.format("tiamot_default_world biome %-24s built, %d fill(s), mode %s", id, #biome.fills, own))
end

-- A biome's fills for a terrain mode, compiled on first use if the biome
-- is lazy. Called per chunk by the generator.
function tdw.fills_for(biome, mode)
    local key = mode == "all" and "fills_all" or "fills"
    if biome[key] == nil then
        biome[key] = biome.compile_fills(mode == "all" and "all" or biome.own_mode)
        game.log(string.format("tiamot_default_world biome %-24s compiled %d fill(s), mode %s", biome.id, #biome[key],
            mode == "all" and "all" or biome.own_mode))
    end
    return biome[key]
end

-- A surface biome's placement mask for its fills: its ring, and its side
-- of the humidity split. Nil when a biome is put everywhere (nothing to
-- mask), so a builder does `field = mask and n.min(field, mask) or field`.
---@param n table The node builders (ctx.node).
---@param ring_id string
---@param wet boolean Which side of the split.
function tdw.biome_mask(n, ring_id, wet)
    if tdw.config.everywhere then
        return nil
    end
    local ring = tdw.layers.ring_by_id[ring_id]
    return n.min(tdw.shape.ring(ring.u[1], ring.u[2]), tdw.shape.humidity_mask(wet))
end

-- Which biome a grass block belongs to, at runtime, from what is under the
-- turf: the first block below that is not grass. Woodlands sit on loam,
-- grasslands on dirt, and each biome lays its own soil under its own grass,
-- so this is exact even in a chunk where the two meet. Nil when the column
-- is unloaded or the block under the turf is mixed.
---@return integer? material
function tdw.soil_under(x, y, z)
    local grass = tdw.blocks.grass
    for dy = 1, 5 do
        local b = game.get_block{ x = x, y = y - dy, z = z }
        if b == nil then
            return nil
        end
        if b.material ~= grass then
            return b.material
        end
    end
    return nil
end

function tdw.built_count()
    local n = 0
    for _, biome in ipairs(tdw.biome_list) do
        if biome.built then n = n + 1 end
    end
    return n
end

-- The soil under a chunk's skin: the biome's own when one built biome is
-- the only one in reach, plain dirt otherwise. Called per surface chunk.
function tdw.surface_soil(u_lo, u_hi)
    local found = tdw.surface_biomes_in(u_lo, u_hi)
    if #found == 1 and found[1].soil then
        return found[1].soil
    end
    return tdw.blocks.dirt
end

-- Built surface biomes whose ring overlaps [u_lo, u_hi]. Called per chunk by
-- the generator, so it walks a short list and allocates one table.
function tdw.surface_biomes_in(u_lo, u_hi)
    local found = {}
    local only = tdw.config.everywhere
    if only then
        local biome = tdw.biomes[only]
        if biome and biome.built then
            found[1] = biome
        end
        return found
    end
    for _, biome in ipairs(tdw.areas.surface.biomes) do
        if biome.built and biome.ring then
            local ring = tdw.layers.ring_by_id[biome.ring]
            if ring.u[1] <= u_hi and ring.u[2] >= u_lo then
                found[#found + 1] = biome
            end
        end
    end
    return found
end

return M
