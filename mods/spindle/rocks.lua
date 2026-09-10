-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Rocks: boulders and clusters of them, as schematics, for any biome.
--
-- A boulder is an ellipsoid that has been roughed up: its blocks are each
-- scaled a little at random so the surface is faceted rather than smooth,
-- and one or two flat CUTS take a side off it, which is what weathered
-- stone looks like — a rounded mass with a face or two. It sits about half
-- in the ground, merged into the turf's own cells (engine merge write) so
-- nothing stands in a footprint.
--
-- A cluster is one big boulder with a few smaller ones round it, closer
-- and overlapping on one side, and a scatter of pebbles — single cells to
-- a few — within a few blocks. Every rock finds its own ground, so a
-- cluster follows a slope. All of a cluster is one material.
--
-- Everything is deterministic from the stream the caller passes in. The
-- caller owns the batch: `place_cluster` and `place_rock` push into the
-- current `spindle.edits` batch and do not begin or commit it.

local M = {}
spindle.rocks = M

local edits = spindle.edits
local FULL = game.OCCUPANCY_FULL

local function at(x, y, z)
    return game.get_block{ x = x, y = y, z = z }
end

-- Bit for cell (cx, cy, cz), each 0..2, indexed x + 3*y + 9*z.
local function bit(cx, cy, cz)
    return 1 << (cx + 3 * cy + 9 * cz)
end

-- The y of the block the surface is in at (x, z), looked for from `hint`
-- two blocks up and four down: the highest block that holds anything with
-- air above it. Nil if nothing there is loaded or it is all air or all rock.
function M.surface_at(x, z, hint)
    local above = at(x, hint + 3, z)
    for y = hint + 2, hint - 4, -1 do
        local b = at(x, y, z)
        if b == nil or above == nil then
            return nil
        end
        if b.occupancy ~= 0 and above.occupancy == 0 then
            return y, b
        end
        above = b
    end
    return nil
end

-- A cut: a plane with normal `n` at distance `d` from the centre along it;
-- cells beyond it are removed. Normals are taken from a small set so a
-- face is flat across cells rather than a stair of them.
local NORMALS = {
    { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
    { 0.7071, 0, 0.7071 }, { -0.7071, 0, 0.7071 }, { 0.7071, 0, -0.7071 }, { -0.7071, 0, -0.7071 },
    { 0.7071, 0.7071, 0 }, { 0, 0.7071, 0.7071 }, { -0.7071, 0.7071, 0 }, { 0, 0.7071, -0.7071 },
}

-- The mask of the cells of block (bx, by, bz) inside a roughed-up ellipsoid
-- centred at (cx, cy, cz) with half-widths (rx, ry, rz), scaled by `scale`
-- for this block, and inside every cut in `cuts` ({n, d}). Plain + - * /
-- and comparisons; nothing here is a library call.
local function rock_mask(bx, by, bz, cx, cy, cz, rx, ry, rz, scale, cuts)
    local mask = 0
    for iz = 0, 2 do
        local pz = bz + (iz + 0.5) / 3 - cz
        local dz = pz / (rz * scale)
        for iy = 0, 2 do
            local py = by + (iy + 0.5) / 3 - cy
            local dy = py / (ry * scale)
            for ix = 0, 2 do
                local px = bx + (ix + 0.5) / 3 - cx
                local dx = px / (rx * scale)
                if dx * dx + dy * dy + dz * dz <= 1.0 then
                    local inside = true
                    for _, cut in ipairs(cuts) do
                        local n = cut[1]
                        if px * n[1] + py * n[2] + pz * n[3] > cut[2] then
                            inside = false
                            break
                        end
                    end
                    if inside then
                        mask = mask | bit(ix, iy, iz)
                    end
                end
            end
        end
    end
    return mask
end

-- One boulder. `r` is its half-width; it is squat (ry a share of r) and a
-- little longer one way than the other. `buried` is the share of its
-- height under `ground`, the y of the surface within the block (a partial
-- top block's cells rise about six tenths of the way up it).
---@param material string A qualified block id.
---@param x number
---@param ground number World y of the surface at (x, z).
---@param z number
---@param r number Half-width in blocks.
---@param rng Tiamot.Stream
---@param opts { buried: number?, cuts: integer?, squat: number? }?
function M.place_rock(material, x, ground, z, r, rng, opts)
    opts = opts or {}
    local buried = opts.buried or 0.5
    local squat = opts.squat or (0.55 + rng:below(4) / 10)
    local stretch = 0.75 + rng:below(6) / 10                -- 0.75 .. 1.25
    local rx, rz = r * stretch, r / stretch
    if rng:next_bool() then rx, rz = rz, rx end
    local ry = r * squat
    local cy = ground + ry * (1.0 - 2.0 * buried)
    local cx, cz = x + 0.5, z + 0.5
    -- Cuts: a couple of flat faces, never so deep as to halve the rock.
    local cuts = {}
    local count = opts.cuts or rng:below(3)
    for _ = 1, count do
        local n = NORMALS[rng:below(#NORMALS) + 1]
        cuts[#cuts + 1] = { n, r * (0.35 + rng:below(4) / 10) }
    end
    for bz = math.floor(cz - rz), math.floor(cz + rz) do
        for by = math.floor(cy - ry), math.floor(cy + ry) do
            for bx = math.floor(cx - rx), math.floor(cx + rx) do
                local scale = 0.8 + rng:below(7) / 20                -- 0.8 .. 1.1, per block
                local mask = rock_mask(bx, by, bz, cx, cy, cz, rx, ry, rz, scale, cuts)
                if mask ~= 0 then
                    local b = at(bx, by, bz)
                    -- Whole blocks are left alone: nothing of a buried rock
                    -- shows there, and merging into one is an edit a cell.
                    if b ~= nil and b.occupancy ~= FULL then
                        edits.push({ x = bx, y = by, z = bz }, material, mask, true)
                    end
                end
            end
        end
    end
end

-- A pebble: a few cells, in the block above the surface block's top, or
-- merged into the top block itself when its cells reach that high.
local function place_pebble(material, x, ground, z, rng)
    local cells = 1 + rng:below(3)
    local mask = 0
    local ox, oz = rng:below(2), rng:below(2)
    for i = 0, cells - 1 do
        mask = mask | bit((ox + i) % 3, 0, (oz + (i // 2)) % 3)
    end
    -- The surface within its block is at `ground`; the cell layer just
    -- above it is where a pebble lies.
    local by = math.floor(ground)
    local layer = math.floor((ground - by) * 3) + 1
    if layer > 2 then
        by, layer = by + 1, 0
    end
    mask = mask << (3 * layer)
    local b = at(x, by, z)
    if b ~= nil and b.occupancy ~= FULL then
        edits.push({ x = x, y = by, z = z }, material, mask, true)
    end
end

-- A cluster round (x, z): a big rock, a few smaller ones leaning in on one
-- side of it, and pebbles about. `hint` is a y near the ground there.
-- Returns how many rocks were placed (nil ground under a satellite skips
-- it).
---@param material string
---@param x integer
---@param hint integer
---@param z integer
---@param rng Tiamot.Stream
---@param opts { big: number?, satellites: integer?, pebbles: integer? }?
function M.place_cluster(material, x, hint, z, rng, opts)
    opts = opts or {}
    local placed = 0
    local ground, top = M.surface_at(x, z, hint)
    if ground == nil then
        return 0
    end
    -- The surface sits about six tenths up a partial top block.
    local function surface(gy, block)
        return gy + (block.occupancy == FULL and 1.0 or 0.6)
    end
    local big = opts.big or (1.6 + rng:below(11) / 10)          -- 1.6 .. 2.6
    M.place_rock(material, x, surface(ground, top), z, big, rng, { buried = 0.45 + rng:below(3) / 10 })
    placed = placed + 1
    -- Satellites lean to one side: a heading, and offsets within a quarter
    -- turn of it, at a distance that lets them touch or overlap the big one.
    local heading = rng:below(8)
    local count = opts.satellites or (2 + rng:below(4))
    for _ = 1, count do
        local dir = (heading + rng:below(3) - 1) % 8
        local dx = ({ 1, 1, 0, -1, -1, -1, 0, 1 })[dir + 1]
        local dz = ({ 0, 1, 1, 1, 0, -1, -1, -1 })[dir + 1]
        local dist = big + 0.5 + rng:below(3)
        local sx = x + math.floor(dx * dist + 0.5)
        local sz = z + math.floor(dz * dist + 0.5)
        local sg, sb = M.surface_at(sx, sz, ground)
        if sg ~= nil then
            local r = 0.7 + rng:below(10) / 10                     -- 0.7 .. 1.6
            M.place_rock(material, sx, surface(sg, sb), sz, r, rng, { buried = 0.4 + rng:below(3) / 10 })
            placed = placed + 1
        end
    end
    -- Pebbles, all round.
    local pebbles = opts.pebbles or (3 + rng:below(6))
    for _ = 1, pebbles do
        local px = x + rng:below(11) - 5
        local pz = z + rng:below(11) - 5
        local pg, pb = M.surface_at(px, pz, ground)
        if pg ~= nil then
            place_pebble(material, px, surface(pg, pb), pz, rng)
        end
    end
    return placed
end

return M
