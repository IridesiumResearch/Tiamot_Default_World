-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- One chat hook for the whole mod.
--
-- The engine allows one `register_on_chat` per mod, so files that want a
-- word — `where`, `stats` — register it here and this dispatches. A word is
-- the whole message, lower-cased; a handler returning nothing swallows it.

local M = {}
local words = {}

---@param word string
---@param fn fun(player: string)
function spindle.on_chat(word, fn)
    assert(not words[word], "chat word registered twice: " .. word)
    words[word] = fn
end

game.register_on_chat(function(event)
    local fn = words[string.lower(event.text)]
    if fn == nil then
        return
    end
    fn(event.player)
    return false
end)

return M
