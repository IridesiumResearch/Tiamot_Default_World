-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Where a player is, remembered.
--
-- The engine saves a player's inventory between sessions and nothing else:
-- every join starts at its fixed spawn, which in this world is deep inside
-- the hot magical caves. So this file does two things the engine leaves to a
-- mod (charter rule 1):
--
--   * On a first visit, drops the player above the temperate woodlands and
--     walks them down onto the ground — the surface is under a relief field
--     nothing in Lua can evaluate, so it is FOUND, by reading blocks under
--     the player once the chunks there exist.
--   * Remembers where each player was, keyed on their UUID (charter rule 13)
--     in `game.storage`, and puts them back there when they return. The
--     position is sampled every half second and written every twenty, and
--     again when they leave, so a dropped connection loses at most a few
--     steps.

-- The plain: shape.lua scales the relief down around this radius, so the
-- ground is within about a hundred blocks of the base dome and one look down
-- from SPAWN_ABOVE finds it — no hopping through unloaded chunks.
local SPAWN_ABOVE = 110
local SPAWN = {
    x = spindle.shape.SPAWN_X + 0.5,
    y = spindle.shape.spawn_base_y() + SPAWN_ABOVE,
    z = spindle.shape.SPAWN_Z + 0.5,
}
local SAMPLE_EVERY = 10        -- ticks between position samples
local SAVE_EVERY = 400         -- ticks between writes to storage
local SCAN_DOWN = 190          -- blocks searched below a landing player (within the vertical view)
local HOP = 160                -- blocks dropped when all of that is air
local GIVE_UP_AFTER = 1200     -- ticks (one minute) before a landing is abandoned

local online = {}              -- uuid -> { pos, pending, landing }
local tick = 0

local function key(uuid)
    return "pos:" .. uuid
end

local function encode(p)
    return string.format("%.2f %.2f %.2f", p.x, p.y, p.z)
end

local function decode(text)
    local x, y, z = string.match(text, "^(%S+) (%S+) (%S+)$")
    if x == nil then
        return nil
    end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

local function where(uuid)
    local body = game.player_entity(uuid)
    if body == nil then
        return nil
    end
    local entity = game.entity(body)
    return entity and entity.pos or nil
end

local function save(uuid, rec)
    if rec.pos and not rec.landing then
        game.storage.set(key(uuid), encode(rec.pos))
    end
end

-- One step of finding the ground under a landing player. Returns nothing;
-- called every tick until `rec.landing` is cleared.
local function land(uuid, rec)
    rec.landing.ticks = rec.landing.ticks + 1
    if rec.landing.ticks > GIVE_UP_AFTER then
        game.log("spindle: gave up landing " .. uuid .. " — check the spawn column")
        rec.landing = nil
        return
    end
    local p = where(uuid)
    if p == nil then
        return
    end
    local x, z = math.floor(p.x), math.floor(p.z)
    local feet_y = math.floor(p.y)
    local function at(y)
        return game.get_block{ x = x, y = y, z = z }
    end

    local feet = at(feet_y)
    if feet == nil then
        return          -- not loaded yet; the player is held still until it is
    end

    if feet.occupancy ~= 0 then
        -- Inside rock: climb until there is headroom.
        local clear, y = 0, feet_y + 1
        for _ = 1, 200 do
            local block = at(y)
            if block == nil then
                return
            end
            clear = block.occupancy == 0 and clear + 1 or 0
            if clear >= 3 then
                game.move_player(uuid, { x = x + 0.5, y = y - 2 + 0.01, z = z + 0.5 })
                return
            end
            y = y + 1
        end
        return
    end

    -- In air: look for ground below.
    for y = feet_y - 1, feet_y - SCAN_DOWN, -1 do
        local block = at(y)
        if block == nil then
            return      -- the chunk below is still on its way
        end
        if block.occupancy ~= 0 then
            local landed = { x = x + 0.5, y = y + 1.01, z = z + 0.5 }
            if game.move_player(uuid, landed) then
                rec.landing = nil
                rec.pos = landed
                game.log(string.format("spindle: %s landed at %d, %d, %d", uuid, x, y + 1, z))
            end
            return
        end
    end
    -- Nothing but air for the whole scan: drop, and look again next tick.
    game.move_player(uuid, { x = p.x, y = p.y - HOP, z = p.z })
end

game.register_on_player_join(function(event)
    local rec = { pos = nil, pending = nil, landing = nil }
    online[event.player] = rec
    local saved = game.storage.get(key(event.player))
    local pos = saved and decode(saved) or nil
    if pos then
        rec.pending = pos
        rec.pos = pos
        game.log(string.format("spindle: %s returns to %s", event.name, saved))
    else
        rec.pending = SPAWN
        rec.landing = { ticks = 0 }
        game.log(string.format("spindle: %s is new here; dropping them at the woodlands", event.name))
    end
end)

game.register_on_player_leave(function(event)
    local rec = online[event.player]
    if rec then
        save(event.player, rec)
        online[event.player] = nil
    end
end)

game.register_on_tick(function(dt_ticks)
    tick = tick + dt_ticks
    for uuid, rec in pairs(online) do
        -- A move asked for during the join lands once the body exists.
        if rec.pending and game.move_player(uuid, rec.pending) then
            rec.pending = nil
        end
        if rec.landing then
            land(uuid, rec)
        elseif tick % SAMPLE_EVERY == 0 then
            local p = where(uuid)
            if p then
                rec.pos = p
            end
        end
    end
    if tick % SAVE_EVERY == 0 then
        for uuid, rec in pairs(online) do
            save(uuid, rec)
        end
    end
end)

-- Say "where" in chat to have the server log where you are, in the
-- Spindle's own terms. For checking the layers against the plan.
game.register_on_chat(function(event)
    if event.text ~= "where" then
        return
    end
    local p = where(event.player)
    if p == nil then
        return false
    end
    local shape = spindle.shape
    local r2 = (p.x * p.x + p.z * p.z) * 1e-6
    local u = r2 / (shape.R_DISC * shape.R_DISC)
    local Y = (p.y - shape.Y0) * shape.SCALE
    local ring = spindle.layers.rings_overlapping(u, u)[1]
    local depth = shape.dome_at(u) - Y
    game.log(string.format(
        "spindle where: y=%.0f  Spindle Y=%.2f km  r^2=%.1f km^2 (u=%.4f, ring %s)  ~%.2f km below the base dome",
        p.y, Y, r2, u, ring and ring.id or "beyond the rim", depth))
    return false
end)

game.log("spindle: player positions are remembered")
