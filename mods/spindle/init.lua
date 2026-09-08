-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Spindle: the default world. This file only decides the load order.
--
-- Every file below is loaded exactly once and hangs what it exports off the
-- `spindle` global, which the sandbox shares between a mod's own files. The
-- engine's `require` is confined to this directory and does not cache — so a
-- file required twice would run twice, which is why nothing but this file
-- calls it.
--
-- Order matters: blocks first (everything else needs their ids), then the
-- shape (the density programs), the layer table, the biome registry, the
-- biomes themselves, and only then the generator and the player hooks that
-- read all of it.

spindle = {}

-- The host reports a failed load as "errored in init.lua" and nothing more,
-- so say which file and what the error was before letting it through.
local function load(name)
    local ok, result = pcall(require, name)
    if not ok then
        game.log(string.format("spindle: %s.lua failed: %s", name, tostring(result)))
        error(result, 0)
    end
    return result
end

spindle.blocks = load("blocks")
spindle.shape = load("shape")
spindle.layers = load("layers")
load("biomes")             -- registry: spindle.register_area / register_biome
load("biomes.catalogue")   -- every area and every biome, as data
load("biomes.temperate_woodlands")   -- 1.1, the first one built
load("generate")
load("player")

game.log(string.format("spindle ready: %d areas, %d biomes (%d built)",
    #spindle.area_list, #spindle.biome_list, spindle.built_count()))
