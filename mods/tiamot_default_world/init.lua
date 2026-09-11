-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Spindle: the default world. This file only decides the load order.
--
-- Every file below is loaded exactly once and hangs what it exports off the
-- `tdw` global, which the sandbox shares between a mod's own files. The
-- engine's `require` is confined to this directory and does not cache — so a
-- file required twice would run twice, which is why nothing but this file
-- calls it.
--
-- Order matters: blocks first (everything else needs their ids), then the
-- shape (the density programs), the layer table, the biome registry, the
-- biomes themselves, and only then the generator and the player hooks that
-- read all of it.

tdw = {}

-- Development switches. `everywhere` names a built surface biome and puts it
-- over the WHOLE surface, ignoring its ring and humidity, so one biome can be
-- looked at on its own while it is being made. Set it to nil for the world.
tdw.config = {
    everywhere = "temperate_woodlands",
}

-- The host reports a failed load as "errored in init.lua" and nothing more,
-- so say which file and what the error was before letting it through.
local function load(name)
    local ok, result = pcall(require, name)
    if not ok then
        game.log(string.format("tiamot_default_world: %s.lua failed: %s", name, tostring(result)))
        error(result, 0)
    end
    return result
end

tdw.blocks = load("blocks")
tdw.shape = load("shape")
tdw.layers = load("layers")
load("hooks")                   -- one tick and one chat hook, many subscribers
tdw.edits = load("edits")   -- the paced runtime edit queue
load("rocks")                   -- boulders and clusters, for any biome: tdw.rocks
load("biomes")             -- registry: tdw.register_area / register_biome
load("biomes.catalogue")   -- every area and every biome, as data
load("biomes.temperate_woodlands")   -- 1.1, the first one built
load("generate")
load("player")
load("rules")             -- leaves and water, and other rules of the whole world

game.log(string.format("tiamot_default_world ready: %d areas, %d biomes (%d built)",
    #tdw.area_list, #tdw.biome_list, tdw.built_count()))
