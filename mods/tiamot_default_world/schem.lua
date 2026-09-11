-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Schematic helpers any biome can use: ellipsoids of a material written
-- into the world, merged, and ellipsoids of air carved out of it.
--
-- Everything is plain + - * / and comparisons on the cell lattice, nothing
-- from a library, and everything pushes into the current `tdw.edits` batch
-- — the caller owns the batch.

local M = {}
tdw.schem = M

local edits = tdw.edits
local FULL = game.OCCUPANCY_FULL

function M.at(x, y, z)
    return game.get_block{ x = x, y = y, z = z }
end

-- Bit for cell (cx, cy, cz), each 0..2, indexed x + 3*y + 9*z.
function M.bit(cx, cy, cz)
    return 1 << (cx + 3 * cy + 9 * cz)
end

local function hash(x, y, z)
    local h = (x * 73856093) ~ (y * 19349663) ~ (z * 83492791) ~ ((tdw.seed_int or 0) * 2654435761)
    return h ~ (h >> 17)
end
M.hash = hash

-- Sixteen headings round the compass, as unit vectors: the only way a
-- direction is turned here, since there is no trigonometry in Lua that
-- charter rule 4 allows. Heading k is k sixteenths of a turn.
M.DIR16 = {
    { 1.0, 0.0 }, { 0.9239, 0.3827 }, { 0.7071, 0.7071 }, { 0.3827, 0.9239 },
    { 0.0, 1.0 }, { -0.3827, 0.9239 }, { -0.7071, 0.7071 }, { -0.9239, 0.3827 },
    { -1.0, 0.0 }, { -0.9239, -0.3827 }, { -0.7071, -0.7071 }, { -0.3827, -0.9239 },
    { 0.0, -1.0 }, { 0.3827, -0.9239 }, { 0.7071, -0.7071 }, { 0.9239, -0.3827 },
}

-- The mask of the cells of block (bx, by, bz) inside an ellipsoid centred at
-- (cx, cy, cz) with half-widths (rx, ry, rz). `rough`, if given, nudges the
-- edge per cell by up to that much either way from the integer hash of the
-- cell, so the surface is ragged at the cell rather than clean.
function M.ellipsoid_mask(bx, by, bz, cx, cy, cz, rx, ry, rz, rough)
    local mask = 0
    for iz = 0, 2 do
        local dz = (bz + (iz + 0.5) / 3 - cz) / rz
        for iy = 0, 2 do
            local dy = (by + (iy + 0.5) / 3 - cy) / ry
            for ix = 0, 2 do
                local dx = (bx + (ix + 0.5) / 3 - cx) / rx
                local edge = 1.0
                if rough then
                    edge = 1.0 + rough * ((hash(bx * 3 + ix, by * 3 + iy, bz * 3 + iz) % 9) - 4) / 4
                end
                if dx * dx + dy * dy + dz * dz <= edge then
                    mask = mask | M.bit(ix, iy, iz)
                end
            end
        end
    end
    return mask
end

-- An ellipsoid of `material`, merged: its cells become the material and
-- every other cell keeps what it held. Whole blocks are left alone unless
-- `opts.over_whole` — nothing of a buried thing shows there. With
-- `opts.carve` the material should be air and the ellipsoid is taken OUT
-- of whatever is there, whole blocks included. `opts.rough` as above;
-- `opts.jitter` is a stream and scales each block's part by 0.8 .. 1.1.
---@param opts { rough: number?, jitter: Tiamot.Stream?, carve: boolean?, over_whole: boolean? }?
function M.push_ellipsoid(material, cx, cy, cz, rx, ry, rz, opts)
    opts = opts or {}
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local scale = 1.0
                if opts.jitter then
                    scale = 0.8 + opts.jitter:below(7) / 20
                end
                local mask = M.ellipsoid_mask(bx, by, bz, cx, cy, cz, rx * scale, ry * scale, rz * scale, opts.rough)
                if mask ~= 0 then
                    local b = M.at(bx, by, bz)
                    if b ~= nil then
                        if opts.carve then
                            mask = mask & b.occupancy
                            if mask ~= 0 then
                                edits.push({ x = bx, y = by, z = bz }, material, mask, true)
                            end
                        elseif opts.over_whole or b.occupancy ~= FULL then
                            edits.push({ x = bx, y = by, z = bz }, material, mask, true)
                        end
                    end
                end
            end
        end
    end
end

-- Whether every chunk a box touches is loaded — `at` is nil in one that is
-- not, and an edit into one is dropped. Sampled every eight blocks.
function M.loaded_box(x0, y0, z0, x1, y1, z1)
    local function steps(a, b)
        local out = {}
        for v = a, b, 8 do out[#out + 1] = v end
        out[#out + 1] = b
        return out
    end
    for _, sx in ipairs(steps(x0, x1)) do
        for _, sy in ipairs(steps(y0, y1)) do
            for _, sz in ipairs(steps(z0, z1)) do
                if M.at(sx, sy, sz) == nil then
                    return false
                end
            end
        end
    end
    return true
end

-- Between two bounds, inclusive, from the stream: { least, extra }.
function M.pick(rng, range)
    return range[1] + rng:below(range[2] + 1)
end

return M
