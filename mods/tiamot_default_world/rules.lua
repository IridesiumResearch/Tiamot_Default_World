-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Rules of the world that are not one biome's.
--
-- Leaves and water. Leaves placed into water, or against it, fall apart:
-- the placement is refused and the player keeps them. Water that reaches
-- a leaves block breaks it. There is no way yet to drop what it was as an
-- item at that spot (docs/engine-asks.md, item 11), so for now it is gone.

local blocks = tdw.blocks
local LEAVES = "tiamot_default_world:oak_leaves"

local function wet(x, y, z)
    local f = game.get_fluid{ x = x, y = y, z = z }
    return f ~= nil and not f.empty
end

game.register_on_place(function(event)
    if event.material ~= blocks.oak_leaves then
        return
    end
    local x, y, z = event.x, event.y, event.z
    if wet(x, y, z) or wet(x + 1, y, z) or wet(x - 1, y, z) or wet(x, y + 1, z)
        or wet(x, y - 1, z) or wet(x, y, z + 1) or wet(x, y, z - 1) then
        return "Leaves fall apart in water."
    end
end)

game.register_on_fluid_flow(function(event)
    if event.block == LEAVES then
        game.set_block(event.into, "engine:air")
    end
end)
