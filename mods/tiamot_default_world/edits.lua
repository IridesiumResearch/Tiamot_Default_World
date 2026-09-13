-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A paced queue for runtime edits.
--
-- Every block a mod changes at runtime costs the server a relight of its
-- chunk (about 1.4 ms each) and every client a remesh of it, so what
-- matters is not how many edits go out a tick but how many CHUNKS they
-- touch. A tree is a few hundred edits in four to eight chunks; two hundred
-- trees' edits interleaved a tick would relight the whole neighbourhood
-- every tick, which on the reference machine was a tick over budget and on a
-- small laptop was the player being jerked back by the server's corrections.
--
-- So edits travel in BATCHES — one structure each — and a batch lands whole,
-- in one tick. One batch lands a tick; when the queue is filling, up to
-- BATCH_CATCH_UP of them, one more for every CATCH_UP_PER waiting. A
-- woodland grows over a minute rather than all at once, which is also how
-- a woodland reads. (One batch every four ticks, five a second, was the
-- alpine forest's ceiling: a thousand fir tries in ten seconds landed
-- forty, and the forest stood in patches where the player had waited.)
--
-- `later(ticks, fn)` runs a function after that many ticks: what a pool
-- needs, since water written into a block that is still solid is cleared by
-- the next fluid tick.

local BATCH_EVERY = 1          -- ticks between batches: twenty a second at least (a batch lands in about a millisecond)
local BATCH_CATCH_UP = 2       -- batches a tick at most, when the queue is filling (four built firs faster than the tick could relight them)
local CATCH_UP_PER = 10        -- one more batch a tick for every this many waiting
local MAX_WAITING = 20         -- batches held; past this, growth is refused until they land

local M = {}
local batches = {}
local head, tail = 1, 0
local cooldown = 0
local deferred = {}
local current = nil

-- Starts a batch. Every `push` until `commit` belongs to it.
function M.begin()
    current = {}
end

-- `merge` names the engine's merge write (Sub-Node Contract §7.4): the
-- cells in `occupancy` become `block` and every other cell keeps what it
-- held. Without it a masked write replaces the block, cells not named
-- becoming air — right for something growing into open air, wrong for
-- anything growing into ground.
local MERGE = { merge = true }

---@param position { x: integer, y: integer, z: integer }
---@param block string
---@param occupancy integer?
---@param merge boolean?
function M.push(position, block, occupancy, merge)
    assert(current, "edits.push outside begin/commit")
    current[#current + 1] = { position, block, occupancy, merge and MERGE or nil }
end

-- Queues the batch. Returns false, with nothing queued, if too many are
-- waiting: the caller should not have done the work, so `M.room()` first.
-- `reserve` lets a caller queue past the cap by that many batches: a rare
-- structure (a pool, a rock cluster) would otherwise never find room in a
-- queue that the common one (a tree) keeps full.
---@param reserve integer?
function M.commit(reserve)
    local batch = current
    current = nil
    if not batch or #batch == 0 then
        return true
    end
    if M.waiting() >= MAX_WAITING + (reserve or 0) then
        return false
    end
    tail = tail + 1
    batches[tail] = batch
    return true
end

-- Takes the batch instead of queuing it: `begin`, the pushes, then this
-- returns the list — `{ position, block, occupancy, merge }` each — and
-- clears it. For building a schematic at load from the same shape code
-- that grows the thing by tick.
function M.take()
    local batch = current or {}
    current = nil
    return batch
end

---@param reserve integer?
function M.room(reserve)
    return M.waiting() < MAX_WAITING + (reserve or 0)
end

function M.waiting()
    return tail - head + 1
end

---@param ticks integer
---@param fn fun()
function M.later(ticks, fn)
    deferred[#deferred + 1] = { ticks = ticks, fn = fn }
end

tdw.on_tick(function(dt_ticks)
    cooldown = cooldown - dt_ticks
    if cooldown <= 0 and head <= tail then
        local land = math.min(BATCH_CATCH_UP, 1 + M.waiting() // CATCH_UP_PER)
        for _ = 1, land do
            if head > tail then break end
            local batch = batches[head]
            batches[head] = nil
            head = head + 1
            for _, edit in ipairs(batch) do
                game.set_block(edit[1], edit[2], edit[3], edit[4])
            end
        end
        cooldown = BATCH_EVERY
        if head > tail then
            head, tail = 1, 0
        end
    end
    if #deferred > 0 then
        local kept = {}
        for _, item in ipairs(deferred) do
            item.ticks = item.ticks - dt_ticks
            if item.ticks <= 0 then
                item.fn()
            else
                kept[#kept + 1] = item
            end
        end
        deferred = kept
    end
end)

return M
