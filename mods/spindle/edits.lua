-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A paced queue for runtime edits.
--
-- `game.set_block` lands on the next tick and its queue is shared by
-- everything on the server, with a few thousand entries in it. A tree is a
-- few hundred edits and a woodland grows several a second, so the mod keeps
-- its own list and hands the engine a bounded number each tick — the same
-- pacing the engine gives a plan stamp, done here because the plan API can
-- only stamp what was captured from the world.
--
-- `later(ticks, fn)` runs a function after the queue has had that many ticks
-- to drain: what a pool needs, since water written into a block that is
-- still solid is cleared by the next fluid tick.

local PER_TICK = 256

local M = {}
local queue = {}
local head, tail = 1, 0
local deferred = {}

---@param position { x: integer, y: integer, z: integer }
---@param block string
---@param occupancy integer?
function M.push(position, block, occupancy)
    tail = tail + 1
    queue[tail] = { position, block, occupancy }
end

---@param ticks integer
---@param fn fun()
function M.later(ticks, fn)
    deferred[#deferred + 1] = { ticks = ticks, fn = fn }
end

function M.pending()
    return tail - head + 1
end

game.register_on_tick(function()
    local budget = PER_TICK
    while head <= tail and budget > 0 do
        local edit = queue[head]
        queue[head] = nil
        head = head + 1
        budget = budget - 1
        if not game.set_block(edit[1], edit[2], edit[3]) then
            -- The engine's queue is full: put it back and try next tick.
            head = head - 1
            queue[head] = edit
            break
        end
    end
    if head > tail then
        head, tail = 1, 0
    end
    local kept = {}
    for _, item in ipairs(deferred) do
        item.ticks = item.ticks - 1
        if item.ticks <= 0 then
            item.fn()
        else
            kept[#kept + 1] = item
        end
    end
    deferred = kept
end)

return M
