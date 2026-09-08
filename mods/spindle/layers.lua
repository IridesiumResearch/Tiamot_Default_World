-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The world's layers, as data the generator and the biome registry read.
--
-- Three kinds of coordinate divide the Spindle:
--   depth  - km below the top surface (the terrain field is the proxy)
--   shell  - km of ellipsoidal distance E from the stack centre
--   tail   - Spindle Y in km, on the needle below the body
-- and the surface is divided again into RINGS by u = r^2 / R^2.

local shape = spindle.shape
local M = {}

-- Surface rings, by t = r / R, stored as thresholds on u = t^2 so a ring
-- mask is two subtractions and a min. Inner edge first.
M.RINGS = {
    { id = "crown",     t = { 0.00, 0.08 }, name = "The Crown" },
    { id = "frost",     t = { 0.08, 0.18 }, name = "Frostmoor and Firwold" },
    { id = "temperate", t = { 0.18, 0.35 }, name = "The Greensward, Oakhold, the Fen, the Downs" },
    { id = "ember",     t = { 0.35, 0.42 }, name = "The Ember Ridge" },
    { id = "glass",     t = { 0.42, 0.48 }, name = "The Glass Waste" },
    { id = "verdant",   t = { 0.48, 0.60 }, name = "The Verdant Belt and Goldwater" },
    { id = "shore",     t = { 0.60, 0.85 }, name = "The Long Shore" },
    { id = "hem",       t = { 0.85, 1.00 }, name = "The Hem" },
}
M.ring_by_id = {}
for _, ring in ipairs(M.RINGS) do
    ring.u = { ring.t[1] * ring.t[1], ring.t[2] * ring.t[2] }
    M.ring_by_id[ring.id] = ring
end

-- Rings whose u range overlaps [u_lo, u_hi].
function M.rings_overlapping(u_lo, u_hi)
    local found = {}
    for _, ring in ipairs(M.RINGS) do
        if ring.u[1] <= u_hi and ring.u[2] >= u_lo then
            found[#found + 1] = ring
        end
    end
    return found
end

-- The depth bands under the top surface, km. `material` is what the band is
-- made of before any cave is cut into it.
M.DEPTH = {
    { id = "surface",      d = { -0.05, 0.10 },  material = "stone" },
    { id = "normal_caves", d = { 0.10, shape.GLOAM_D }, material = "stone" },
    { id = "dark_caves",   d = { shape.GLOAM_D, shape.ABYSS_D }, material = "gloam_stone" },
    { id = "abyss",        d = { shape.ABYSS_D, 1e9 }, material = "abyss_stone" },
}

-- The core stack, outermost first, from shape.SHELLS.
M.SHELL_MATERIAL = {
    magma_above = "magma_crust",
    magma = "magma",
    magma_below = "magma_crust",
    hot_magical = "lantern_stone",
    slime_border = "caul",
    cold_magical = "dream_stone",
    hollow_ring = "scorch",
}

-- The tail: Spindle Y in km, top down.
M.TAIL = {
    { id = "tail",       y = { shape.TAIL_Y, shape.APEX_Y }, material = "marrow" },
    { id = "below_apex", y = { shape.APEX_Y, -70.0 }, material = "apex_stone" },
}

return M
