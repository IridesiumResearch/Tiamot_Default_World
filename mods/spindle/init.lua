-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Spindle: the default world. This file only decides the load order.
--
-- Every file below is `require`d exactly once and hangs what it exports off
-- the `spindle` global, which the sandbox shares between a mod's own files.
-- `require` here is the engine's, confined to this directory, and it does not
-- cache — so a file required twice would run twice, which is why nothing but
-- this file calls it.
--
-- Order matters: blocks first (everything else needs their ids), then the
-- shape (the density programs), the layer table, the biome registry, the
-- biomes themselves, and only then the generator and the player hooks that
-- read all of it.

spindle = {}

spindle.blocks = require("blocks")
spindle.shape = require("shape")
spindle.layers = require("layers")
require("biomes")             -- registry: spindle.register_area / register_biome
require("biomes.catalogue")   -- every area and every biome, as data
require("biomes.temperate_woodlands")   -- 1.1, the first one built
require("generate")
require("player")

game.log(string.format("spindle ready: %d areas, %d biomes (%d built)",
    #spindle.area_list, #spindle.biome_list, spindle.built_count()))
