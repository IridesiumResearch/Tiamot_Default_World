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
-- in one tick, with BATCH_EVERY ticks of quiet between batches. A woodland
-- grows a tree or two a second rather than all at once, which is also how a
-- woodland reads.
--
-- `later(ticks, fn)` runs a function after that many ticks: what a pool
-- needs, since water written into a block that is still solid is cleared by
-- the next fluid tick.

local BATCH_EVERY = 6          -- ticks between batches: about three a second
local MAX_WAITING = 12         -- batches held; past this, growth is refused until they land

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

---@param position { x: integer, y: integer, z: integer }
---@param block string
---@param occupancy integer?
function M.push(position, block, occupancy)
    assert(current, "edits.push outside begin/commit")
    current[#current + 1] = { position, block, occupancy }
end

-- Queues the batch. Returns false, with nothing queued, if too many are
-- waiting: the caller should not have done the work, so `M.room()` first.
function M.commit()
    local batch = current
    current = nil
    if not batch or #batch == 0 then
        return true
    end
    if M.waiting() >= MAX_WAITING then
        return false
    end
    tail = tail + 1
    batches[tail] = batch
    return true
end

function M.room()
    return M.waiting() < MAX_WAITING
end

function M.waiting()
    return tail - head + 1
end

---@param ticks integer
---@param fn fun()
function M.later(ticks, fn)
    deferred[#deferred + 1] = { ticks = ticks, fn = fn }
end

game.register_on_tick(function(dt_ticks)
    cooldown = cooldown - dt_ticks
    if cooldown <= 0 and head <= tail then
        local batch = batches[head]
        batches[head] = nil
        head = head + 1
        for _, edit in ipairs(batch) do
            game.set_block(edit[1], edit[2], edit[3])
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
