-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- One of each engine hook for the whole mod, with subscribers.
--
-- The engine keeps ONE callback per hook per mod: a second `register_on_chat`
-- is refused at load, and a second `register_on_tick` quietly replaces the
-- first — which is how the edit queue's drain stopped running the day the
-- player file registered its own tick after it, and no tree was placed for
-- two days. So every file that wants a tick or a chat word subscribes here,
-- and this file holds the engine's one registration of each.

local M = {}
local ticks = {}
local words = {}

-- Runs `fn(dt_ticks)` every tick, after everything subscribed before it.
---@param fn fun(dt_ticks: integer)
function tdw.on_tick(fn)
    ticks[#ticks + 1] = fn
end

-- Runs `fn(player)` when a player says exactly `word` (case-insensitive),
-- and swallows the message.
---@param word string
---@param fn fun(player: string)
function tdw.on_chat(word, fn)
    assert(not words[word], "chat word registered twice: " .. word)
    words[word] = fn
end

-- Runs `fn(x, y, z)` when a block of `material` gets a random tick, until
-- one subscriber returns true — two biomes share the grass block, and each
-- takes only the ticks on its own ground.
local random_ticks = {}
---@param material integer
---@param fn fun(x: integer, y: integer, z: integer): boolean?
function tdw.on_random_tick(material, fn)
    local list = random_ticks[material]
    if list == nil then
        list = {}
        random_ticks[material] = list
        game.register_random_tick(material, function(event)
            for _, f in ipairs(list) do
                if f(event.x, event.y, event.z) then
                    return
                end
            end
        end)
    end
    list[#list + 1] = fn
end

game.register_on_tick(function(dt_ticks)
    for _, fn in ipairs(ticks) do
        fn(dt_ticks)
    end
end)

game.register_on_chat(function(event)
    local fn = words[string.lower(event.text)]
    if fn == nil then
        return
    end
    fn(event.player)
    return false
end)

return M
