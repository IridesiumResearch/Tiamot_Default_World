-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Every area of the Spindle and every biome in it, as data.
--
-- This is the designer's list, top to bottom. A biome listed here is
-- REGISTERED: it has an id, an area, and a first guess at where it goes. It
-- is BUILT only when a file under biomes/ calls `tdw.build_biome` for it
-- — one at a time, in order, so each one gets looked at on its own.
--
-- `ring`, `humidity` and `note` on the surface biomes are placement
-- proposals, to be argued with when each is built. Humidity is the value of
-- the slow "humidity" noise, which runs about -0.42 .. +0.42.

local area, biome = tdw.register_area, tdw.register_biome

-- 1. The surface --------------------------------------------------------------
area{ id = "surface", name = "Surface", kind = "surface",
    note = "Rings by distance from the axis, split by humidity and altitude." }
biome{ id = "temperate_woodlands", name = "Temperate Woodlands", area = "surface",
    ring = "temperate", humidity = { -0.05, 0.42 }, note = "1.1 — oak woodland, the first biome built." }
biome{ id = "rolling_grasslands", name = "Rolling Grasslands", area = "surface",
    ring = "temperate", humidity = { -0.42, -0.05 }, note = "The dry half of the temperate ring." }
biome{ id = "alpine_highlands", name = "Alpine Highlands", area = "surface",
    ring = "frost", note = "Mountain form: also anywhere more than ~1.2 km above the base dome." }
biome{ id = "coastal_cliffs", name = "Coastal Cliffs", area = "surface",
    ring = "shore", note = "Steep stretches of the Long Shore." }
biome{ id = "sandy_shores", name = "Sandy Shores", area = "surface",
    ring = "shore", note = "Gentle stretches of the Long Shore." }
biome{ id = "river_valleys", name = "River Valleys", area = "surface",
    ring = "temperate", note = "Needs the map pre-pass (rivers are global facts)." }
biome{ id = "dense_rainforest_canopy", name = "Dense Rainforest Canopy", area = "surface",
    ring = "verdant", humidity = { 0.05, 0.42 }, note = "The wet half of the Verdant Belt." }
biome{ id = "arid_mesa", name = "Arid Mesa", area = "surface",
    ring = "glass", humidity = { -0.42, 0.0 }, note = "The Glass Waste, dry half." }
biome{ id = "badlands", name = "Badlands", area = "surface",
    ring = "glass", humidity = { 0.0, 0.42 }, note = "The Glass Waste, less dry half." }
biome{ id = "taiga", name = "Taiga", area = "surface",
    ring = "frost", humidity = { -0.05, 0.42 }, note = "Firwold: the wet half of the frost ring." }
biome{ id = "volcanic_foothills", name = "Volcanic Foothills", area = "surface",
    ring = "ember", note = "The Ember Ridge, the only surface sign of the magma shell." }
biome{ id = "coral_fringed_shallows", name = "Coral-Fringed Shallows", area = "surface",
    ring = "shore", note = "Needs generated water (fill_fluid_below at a sea level)." }

-- 2. Normal caves ----------------------------------------------------------------
area{ id = "normal_caves", name = "Normal Caves", kind = "depth", note = "100 to 1,600 blocks down." }
biome{ id = "mossy_limestone", name = "Mossy Limestone", area = "normal_caves" }
biome{ id = "crystal_seam", name = "Crystal Seam", area = "normal_caves" }
biome{ id = "underground_river", name = "Underground River", area = "normal_caves", note = "Needs generated water." }
biome{ id = "fungal_grove_chambers", name = "Fungal Grove Chambers", area = "normal_caves" }
biome{ id = "mineral_vein_tunnels", name = "Mineral Vein Tunnels", area = "normal_caves" }
biome{ id = "stalactite_forests", name = "Stalactite Forests", area = "normal_caves" }

-- 3. Dark caves ------------------------------------------------------------------
area{ id = "dark_caves", name = "Dark Caves", kind = "depth", note = "1,600 to 4,000 blocks down: the Gloam." }
biome{ id = "stone_labyrinth", name = "Stone Labyrinth", area = "dark_caves" }
biome{ id = "echoing_black_marble", name = "Echoing Black Marble", area = "dark_caves" }
biome{ id = "shadow_pool_chambers", name = "Shadow Pool Chambers", area = "dark_caves" }
biome{ id = "blind_fish_grottoes", name = "Blind Fish Grottoes", area = "dark_caves" }
biome{ id = "whispering_crevasse", name = "Whispering Crevasse", area = "dark_caves" }
biome{ id = "phosphorescent_fungi_pockets", name = "Phosphorescent Fungi Pockets", area = "dark_caves", note = "Rare." }

-- 4. The abyss -------------------------------------------------------------------
area{ id = "abyss", name = "Abyss Below", kind = "depth", note = "More than 4,000 blocks down." }
biome{ id = "pressure_crushed_depths", name = "Pressure-Crushed Depths", area = "abyss" }
biome{ id = "silent_vertical_shafts", name = "Silent Vertical Shafts", area = "abyss" }
biome{ id = "abyssal_mud_flats", name = "Abyssal Mud Flats", area = "abyss" }
biome{ id = "crush_zone_mineral_beds", name = "Crush-Zone Mineral Beds", area = "abyss" }
biome{ id = "black_water_reservoirs", name = "Black Water Reservoirs", area = "abyss", note = "Needs generated water." }
biome{ id = "fossil_embedded_walls", name = "Fossil-Embedded Walls", area = "abyss" }

-- 5. The magma shell -------------------------------------------------------------
area{ id = "magma_shell", name = "Magma Shell", kind = "shell",
    note = "Bleeds 50 blocks into the layers above and below; 25 blocks of lava caves in the middle." }
biome{ id = "magma_crust_above", name = "Cooked Crust (above)", area = "magma_shell" }
biome{ id = "lava_caves", name = "Lava Caves", area = "magma_shell", note = "The 25-block core. Lava is a look-alike solid until fluid can be generated here." }
biome{ id = "magma_crust_below", name = "Cooked Crust (below)", area = "magma_shell" }

-- 6. Hot magical caves -----------------------------------------------------------
area{ id = "hot_magical", name = "Hot Magical Caves", kind = "shell" }
biome{ id = "living_flame_corridors", name = "Living Flame Corridors", area = "hot_magical" }
biome{ id = "mana_lava_tubes", name = "Mana Lava Tubes", area = "hot_magical" }
biome{ id = "molten_crystal_gardens", name = "Molten Crystal Gardens", area = "hot_magical" }
biome{ id = "fire_spirit_nests", name = "Fire Spirit Nests", area = "hot_magical" }
biome{ id = "arcane_forge_caverns", name = "Arcane Forge Caverns", area = "hot_magical" }

-- 7. The slime border ------------------------------------------------------------
area{ id = "slime_border", name = "Slime Border", kind = "shell", note = "The Caul." }
biome{ id = "viscous_gel_chambers", name = "Viscous Gel Chambers", area = "slime_border" }
biome{ id = "amorphous_ooze_pools", name = "Amorphous Ooze Pools", area = "slime_border" }
biome{ id = "bouncing_gel_pillars", name = "Bouncing Gel Pillars", area = "slime_border" }
biome{ id = "semi_living_slime_reefs", name = "Semi-Living Slime Reefs", area = "slime_border" }

-- 8. Cold magical caves ----------------------------------------------------------
area{ id = "cold_magical", name = "Cold Magical Caves", kind = "shell" }
biome{ id = "frozen_mana_crystal_halls", name = "Frozen Mana Crystal Halls", area = "cold_magical" }
biome{ id = "stilled_time_chambers", name = "Stilled Time Chambers", area = "cold_magical" }
biome{ id = "forest_spirit_sanctums", name = "Forest Spirit Sanctums", area = "cold_magical" }
biome{ id = "ice_spider_nests", name = "Ice Spider Nests", area = "cold_magical" }
biome{ id = "mushroom_forest", name = "Mushroom Forest", area = "cold_magical" }

-- 9. The hollow ring -------------------------------------------------------------
area{ id = "hollow_ring", name = "The Hollow Ring", kind = "shell", note = "The rind around the void." }
biome{ id = "gravity_warped_forests", name = "Gravity-Warped Forests", area = "hollow_ring" }
biome{ id = "echoing_void_tunnels", name = "Echoing Void Tunnels", area = "hollow_ring" }
biome{ id = "fragmented_stone_arches", name = "Fragmented Stone Arches", area = "hollow_ring" }
biome{ id = "residual_magic_shells", name = "Residual Magic Shells", area = "hollow_ring" }
biome{ id = "silent_observatory_chambers", name = "Silent Observatory Chambers", area = "hollow_ring" }

-- 10. The hollow -----------------------------------------------------------------
area{ id = "hollow", name = "The Hollow", kind = "shell", note = "The void itself: 74 km across, 20 km high." }
biome{ id = "empty_cathedral_voids", name = "Empty Cathedral Voids", area = "hollow" }
biome{ id = "floating_island_clusters", name = "Floating Island Clusters", area = "hollow" }
biome{ id = "memory_eating_islands", name = "Memory-Eating Islands", area = "hollow" }
biome{ id = "dead_mushroom_yard", name = "Dead Mushroom Yard", area = "hollow" }
biome{ id = "weightless_dust_seas", name = "Weightless Dust Seas", area = "hollow" }
biome{ id = "poison_root_stones", name = "Poison Root Stones", area = "hollow" }
biome{ id = "forgotten_forest_fragments", name = "Forgotten Forest Fragments", area = "hollow" }
biome{ id = "pyre_stillness_domes", name = "Pyre Stillness Domes", area = "hollow" }

-- 11. The tail -------------------------------------------------------------------
area{ id = "tail", name = "The Tail", kind = "tail", note = "Extremely eerie and monstrous. Y -37 km to -63 km." }
biome{ id = "twisted_bone_corridors", name = "Twisted Bone Corridors", area = "tail" }
biome{ id = "old_bone_fields", name = "Old Bone Fields", area = "tail" }
biome{ id = "living_shadow_mazes", name = "Living Shadow Mazes", area = "tail" }
biome{ id = "wind_hollow_shafts", name = "Wind Hollow Shafts", area = "tail" }
biome{ id = "wall_of_eyes_caves", name = "Wall of Eyes Caves", area = "tail" }

-- 12. Below the apex -------------------------------------------------------------
area{ id = "below_apex", name = "The Below Apex", kind = "tail", note = "Truly horrifying. Y -63 km to the point." }
biome{ id = "impossible_geometry_vaults", name = "Impossible Geometry Vaults", area = "below_apex" }
biome{ id = "living_rooms", name = "Living Rooms", area = "below_apex" }
biome{ id = "body_changer_pools", name = "Body-Changer Pools", area = "below_apex" }
biome{ id = "anti_light_cathedrals", name = "Anti-Light Cathedrals", area = "below_apex" }
biome{ id = "nightmare_tunnels", name = "Nightmare Tunnels", area = "below_apex" }
