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
spindle.areas = {}
spindle.area_list = {}
spindle.biomes = {}
spindle.biome_list = {}

-- An area is a division of the world: the surface, a depth band, a shell,
-- a stretch of the tail. `kind` says which coordinate bounds it.
---@param spec { id: string, name: string, kind: "surface"|"depth"|"shell"|"tail", note: string? }
function spindle.register_area(spec)
    assert(spec.id and spec.name and spec.kind, "register_area needs id, name and kind")
    assert(not spindle.areas[spec.id], "area registered twice: " .. spec.id)
    spec.biomes = {}
    spindle.areas[spec.id] = spec
    spindle.area_list[#spindle.area_list + 1] = spec
    return spec
end

-- A biome inside an area. Surface biomes name a `ring` from layers.RINGS and
-- optionally a `humidity` band in the noise's +/-0.42 range; `build` is the
-- function that makes it real.
---@param spec { id: string, name: string, area: string, ring: string?, humidity: number[]?, note: string?, build: (fun(ctx: table): table)? }
function spindle.register_biome(spec)
    assert(spec.id and spec.name and spec.area, "register_biome needs id, name and area")
    local area = spindle.areas[spec.area]
    assert(area, "biome " .. spec.id .. " names an unknown area " .. tostring(spec.area))
    assert(not spindle.biomes[spec.id], "biome registered twice: " .. spec.id)
    if spec.ring then
        assert(spindle.layers.ring_by_id[spec.ring], "biome " .. spec.id .. " names an unknown ring " .. spec.ring)
    end
    spec.fills = nil
    spindle.biomes[spec.id] = spec
    spindle.biome_list[#spindle.biome_list + 1] = spec
    area.biomes[#area.biomes + 1] = spec
    return spec
end

-- Attaches the native fills to an already-listed biome. Kept separate from
-- registration so the catalogue can list everything first and each biome's
-- own file can build it later, in load order.
---@param id string
---@param build fun(ctx: table): table  -- returns { { field = Density, material = integer }, ... }
function spindle.build_biome(id, build)
    local biome = spindle.biomes[id]
    assert(biome, "build_biome: no biome called " .. tostring(id))
    assert(not biome.fills, "biome built twice: " .. id)
    local ctx = { shape = spindle.shape, blocks = spindle.blocks, layers = spindle.layers, node = spindle.shape.node, sub = spindle.shape.sub }
    biome.fills = build(ctx)
    assert(type(biome.fills) == "table", "build for " .. id .. " must return a list of fills")
    for i, fill in ipairs(biome.fills) do
        assert(fill.field and fill.material, "fill " .. i .. " of " .. id .. " needs field and material")
    end
    game.log(string.format("spindle biome %-24s built, %d fill(s)", id, #biome.fills))
end

function spindle.built_count()
    local n = 0
    for _, biome in ipairs(spindle.biome_list) do
        if biome.fills then n = n + 1 end
    end
    return n
end

-- Built surface biomes whose ring overlaps [u_lo, u_hi]. Called per chunk by
-- the generator, so it walks a short list and allocates one table.
function spindle.surface_biomes_in(u_lo, u_hi)
    local found = {}
    for _, biome in ipairs(spindle.areas.surface.biomes) do
        if biome.fills and biome.ring then
            local ring = spindle.layers.ring_by_id[biome.ring]
            if ring.u[1] <= u_hi and ring.u[2] >= u_lo then
                found[#found + 1] = biome
            end
        end
    end
    return found
end

return M
