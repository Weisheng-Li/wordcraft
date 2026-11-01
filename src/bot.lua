-- Bot: a rule-based opponent that plays a wizard by producing the same
-- { x, y, dash } input a keyboard would. Pure logic; it only reads Game.
-- Like a keyboard, it only moves and dashes in 8 directions.
--
-- Rules, highest priority first:
--   1. Dodge: a laser aimed at me with a clear line -> run behind a wall.
--      (No reflex dash: people rarely manage one, so the bot saves its
--      dash for word races instead.)
--   2. Use my armed trap whenever it can fire: walk up for "close", stand
--      still for "still", dash for "dash". While it recharges, collect words.
--   3. Keep my own charging attack in line of sight of the enemy.
--   4. Stay out of an enemy "close" trap.
--   5. Grab words: the best fitting word per path distance, a bonus for
--      denying words the enemy needs, skipping ones they'll reach first.
--      If the enemy is racing me to it and it's within a dash, dash.
--   6. Otherwise wait on an incoming wave's marker.
-- On top of these, "human limits" (their own section below) weaken the bot
-- on purpose: a reaction time, sometimes missing an aim ray, greed for a
-- nearby word over cover, and a moment to read each new word.
-- Numbers live under `bot` in tuning.json. A profile (from `botProfiles`,
-- for simulation A/B runs) overrides any of them, and can list
-- `avoidWords` the bot never picks up.

local Bot = {}
Bot.__index = Bot

local IDLE = { x = 0, y = 0, dash = false }

-- The 8 directions a keyboard player can press (x, y in -1..1).
local DIRS = {
    { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 },
}

-- Snap any direction to the nearest of the 8 key directions, so the bot
-- walks and dashes by the same rules as a keyboard player.
local function snap8(input)
    if input.x == 0 and input.y == 0 then return input end
    local k = math.floor(math.atan2(input.y, input.x) / (math.pi / 4) + 0.5) % 8
    local d = DIRS[k + 1]
    return { x = d[1], y = d[2], dash = input.dash }
end

-- profile: optional table of overrides for tuning.bot.
function Bot.new(id, rand, profile)
    local self = setmetatable({}, Bot)
    self.id = id
    self.rand = rand
    self.profile = profile or {}
    self.seen = setmetatable({}, { __mode = "k" })     -- laser -> { time, missed } (human limits)
    self.wordSeen = setmetatable({}, { __mode = "k" }) -- word -> time it first showed up (human limits)
    self.time = 0
    return self
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function has(list, id)
    for _, v in ipairs(list or {}) do
        if v == id then return true end
    end
    return false
end

-- The tile a player stands in (their hitbox centre, not their feet).
local function tileOf(arena, x, y, tuning)
    return arena:tileAt(x, y - tuning.player.hitboxH / 2)
end

-- Breadth-first search over open tiles (4-way) from (c, r). Returns
-- dist[r][c] in tiles and parent[r][c] = { c, r } for path rebuilding.
local function flood(arena, c0, r0)
    local d, parent = {}, {}
    for r = 1, arena.rows do d[r], parent[r] = {}, {} end
    if arena:isSolid(c0, r0) then return d, parent end
    d[r0][c0] = 0
    local queue, head = { { c0, r0 } }, 1
    while queue[head] do
        local c, r = queue[head][1], queue[head][2]
        head = head + 1
        for _, s in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nc, nr = c + s[1], r + s[2]
            if not arena:isSolid(nc, nr) and d[nr][nc] == nil then
                d[nr][nc] = d[r][c] + 1
                parent[nr][nc] = { c, r }
                queue[#queue + 1] = { nc, nr }
            end
        end
    end
    return d, parent
end

-- Can the hitbox slide straight from (x1, y1) to (x2, y2)? Checks the
-- line for each corner of a slightly padded box.
local function boxClear(arena, x1, y1, x2, y2, tuning)
    local hw, h = tuning.player.hitboxW / 2 + 1, tuning.player.hitboxH + 1
    for _, o in ipairs({ { -hw, -h }, { hw, -h }, { -hw, 1 }, { hw, 1 } }) do
        if not arena:lineOfSight(x1 + o[1], y1 + o[2], x2 + o[1], y2 + o[2]) then return false end
    end
    return true
end

-- Input that walks `me` toward world point (x, y) along the tile path,
-- cutting corners wherever the straight line is clear.
function Bot:walkTo(x, y)
    local me, arena, t = self.me, self.game.arena, self.tuning
    if dist(me.x, me.y, x, y) < 1.5 then return IDLE end
    local tx, ty = x, y
    if not boxClear(arena, me.x, me.y, x, y, t) then
        local c, r = tileOf(arena, x, y, t)
        if self.field[r] and self.field[r][c] then
            -- Rebuild the tile path (target back to me) and aim at the
            -- farthest point on it we can walk to in a straight line.
            local path = {}
            while self.parent[r] and self.parent[r][c] do
                path[#path + 1] = { c, r }
                c, r = self.parent[r][c][1], self.parent[r][c][2]
            end
            for i = #path, 1, -1 do
                local px, py = arena:tileCenter(path[i][1], path[i][2])
                py = py + t.player.hitboxH / 2 -- feet sit below the tile centre
                if i == #path or boxClear(arena, me.x, me.y, px, py, t) then tx, ty = px, py else break end
            end
        end
    end
    local dx, dy = tx - me.x, ty - me.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return IDLE end
    return { x = dx / len, y = dy / len, dash = false }
end

-- Path length in pixels from me to a world point (math.huge if unreachable).
function Bot:pathDist(field, x, y)
    local c, r = tileOf(self.game.arena, x, y, self.tuning)
    local d = field[r] and field[r][c]
    return d and d * self.game.arena.tile or math.huge
end

-- The reachable tile with the lowest cost(x, y, pathPx), or nil.
function Bot:bestSpot(cost)
    local arena = self.game.arena
    local best, bx, by = math.huge, nil, nil
    for r = 1, arena.rows do
        for c = 1, arena.cols do
            local d = self.field[r][c]
            if d then
                local x, y = arena:tileCenter(c, r)
                y = y + self.tuning.player.hitboxH / 2
                local v = cost(x, y, d * arena.tile)
                if v < best then best, bx, by = v, x, y end
            end
        end
    end
    return bx, by
end

-- 1. The soonest laser that would actually hurt me, with how many land
-- together with it (a volley). Nil when shields would soak them all.
function Bot:threat()
    local soonest, count
    for _, l in ipairs(self.game.lasers) do
        if l.target == self.me then
            if not soonest or l.timer < soonest.timer - 0.05 then
                soonest, count = l, 1
            elseif math.abs(l.timer - soonest.timer) <= 0.05 then
                count = count + 1
            end
        end
    end
    if not soonest or self.me.shield >= count then return nil end
    return soonest
end

function Bot:dodge(laser)
    local me, caster, arena = self.me, laser.caster, self.game.arena
    if not self:noticed(laser) then return nil end -- human limit
    if me:isDashing() then return nil end

    -- Find the nearest spot the caster can't see (where I am, if hidden).
    local x, y = self:bestSpot(function(x, y, d)
        if arena:lineOfSight(caster.x, caster.y, x, y) then return math.huge end
        return d
    end)
    if not x or self:tooGreedyToHide(self:pathDist(self.field, x, y)) then return nil end -- human limit
    return self:walkTo(x, y)
end

----------------------------------------------------------------------------
-- Human limits: these only exist to make the bot play like a person, and
-- each one makes it weaker. Without them it spots every aim ray at once,
-- always finds cover in time, and reads a new wave the frame it lands.
-- Numbers live under `bot.human` in tuning.json. A profile can override
-- some of them, or set `"human": false` to turn them all off (a future
-- difficulty setting would tune these).
----------------------------------------------------------------------------

-- The `bot.human` numbers for this bot, or nil when its profile turns them off.
function Bot:human()
    local h = self.profile.human
    if h == false then return nil end
    return setmetatable(h or {}, { __index = self.tuning.bot.human })
end

-- Reaction time and missed aim rays: has the bot noticed this laser, and
-- had time to react? Each laser has a `missChance` of going unnoticed
-- (looking at the words instead), decided once when it first appears.
function Bot:noticed(laser)
    local h = self:human()
    if not h then return true end
    local s = self.seen[laser]
    if not s then
        s = { time = self.time, missed = self.rand() < h.missChance }
        self.seen[laser] = s
    end
    return not s.missed and self.time - s.time >= h.reactionTime
end

-- Greed: keep going for a word instead of hiding, when it's within
-- `greedRange` and closer than the cover.
function Bot:tooGreedyToHide(coverDist)
    local h = self:human()
    if not h then return false end
    local book = self.game.spellbooks[self.me.id]
    for _, w in ipairs(self.game.wordfield.words) do
        if book:canAccept(w.def) and self:canRead(w) then
            local d = self:pathDist(self.field, w.x, w.y)
            if d <= h.greedRange and d < coverDist then return true end
        end
    end
    return false
end

-- Reading time: a word is ignored for `readTime` after it lands
-- (Bot:update notes when each word first shows up).
function Bot:canRead(word)
    local h = self:human()
    return not h or self.time - self.wordSeen[word] >= h.readTime
end

----------------------------------------------------------------------------

-- Dash at a word when the enemy wants it too and is about as close, and
-- one straight dash along one of the 8 key directions passes over it
-- (but walking wouldn't take a moment anyway). Returns that direction.
function Bot:raceDash(word, enemyBook)
    local me, t = self.me, self.tuning
    if me.dashCooldown > 0 or me:isDashing() or not enemyBook:canAccept(word.def) then return nil end
    local mine = dist(me.x, me.y, word.x, word.y)
    local theirs = dist(self.enemy.x, self.enemy.y, word.x, word.y)
    local r = t.words.pickupRadius - 2
    if mine <= r + self.cfg.raceMinGap or theirs > mine * self.cfg.raceRatio then return nil end
    local wx, wy = word.x - me.x, word.y - me.y
    local best, bestOff
    for _, d in ipairs(DIRS) do
        local len = math.sqrt(d[1] * d[1] + d[2] * d[2])
        local ux, uy = d[1] / len, d[2] / len
        local along = wx * ux + wy * uy        -- how far along the dash line
        local off = math.abs(wx * uy - wy * ux) -- how far the word is to the side
        if along > 0 and along <= t.dash.distance + r and off <= r and (not best or off < bestOff) then
            best, bestOff = d, off
        end
    end
    if best and boxClear(self.game.arena, me.x, me.y, word.x, word.y, t) then return best end
    return nil
end

-- 2-6. Everything that isn't dodging.
function Bot:plan()
    local g, me, enemy, t = self.game, self.me, self.enemy, self.tuning
    local book, enemyBook = g.spellbooks[me.id], g.spellbooks[enemy.id]
    local close = t.conditions.closeDistance
    local apart = dist(me.x, me.y, enemy.x, enemy.y)

    -- 2. My armed trap, when it can fire (while it recharges or casts,
    -- go collect words instead).
    local trap = book.trap
    if trap then
        if has(trap.conditions, "close") and book:trapReady("close") then
            return self:walkTo(enemy.x, enemy.y)
        elseif has(trap.conditions, "still") and book:trapReady("still") then
            return IDLE
        elseif has(trap.conditions, "dash") and book:trapReady("dash") and me.dashCooldown <= 0 then
            local seen = g.arena:lineOfSight(me.x, me.y, enemy.x, enemy.y)
            if seen or not has(trap.spells, "attack") then
                return { x = me.aimX, y = me.aimY, dash = true }
            end
            return self:walkTo(enemy.x, enemy.y)
        end
    end

    -- 3. My attack is charging but a wall is in the way: step out.
    for _, l in ipairs(g.lasers) do
        if l.caster == me and not g.arena:lineOfSight(me.x, me.y, enemy.x, enemy.y) then
            local x, y = self:bestSpot(function(x, y, d)
                if not g.arena:lineOfSight(x, y, enemy.x, enemy.y) then return math.huge end
                return d
            end)
            if x then return self:walkTo(x, y) end
        end
    end

    -- 4. Enemy "close" trap armed: keep out of range.
    local avoid = enemyBook.trap and has(enemyBook.trap.conditions, "close")
    local keepOff = close + self.cfg.trapMargin
    if avoid and apart < keepOff then
        local x, y = self:bestSpot(function(x, y, d)
            if dist(x, y, enemy.x, enemy.y) < keepOff then return math.huge end
            return d
        end)
        if x then return self:walkTo(x, y) end
    end

    -- 5. Words.
    local best, bestScore = nil, 0
    for _, w in ipairs(g.wordfield.words) do
        if self:canRead(w) and book:canAccept(w.def) and not has(self.cfg.avoidWords, w.def.id) -- canRead: human limit
            and not (avoid and dist(w.x, w.y, enemy.x, enemy.y) < keepOff) then
            local mine = self:pathDist(self.field, w.x, w.y)
            if mine < math.huge then
                local value = 1
                if w.def.id == "attack" then value = value + self.cfg.attackBonus end
                if enemyBook:canAccept(w.def) then
                    local theirs = self:pathDist(self.enemyField, w.x, w.y)
                    if theirs < mine * self.cfg.contestRatio then
                        value = value * self.cfg.lostCause -- they'll get there first
                    else
                        value = value + self.cfg.denyBonus
                    end
                end
                local score = value / (mine + g.arena.tile)
                if score > bestScore then best, bestScore = w, score end
            end
        end
    end
    if best then
        local dir = self:raceDash(best, enemyBook)
        if dir then return { x = dir[1], y = dir[2], dash = true } end
        return self:walkTo(best.x, best.y)
    end

    -- 6. Wait on the nearest marker of the incoming wave.
    local markers, near, nearD = g.wordfield.markers, nil, math.huge
    for _, m in ipairs(markers or {}) do
        local d = self:pathDist(self.field, m.x, m.y)
        if d < nearD then near, nearD = m, d end
    end
    if near then return self:walkTo(near.x, near.y) end
    return IDLE
end

function Bot:update(dt, game)
    self.time = self.time + dt
    if game.state ~= "fight" then return IDLE end
    self.game, self.tuning = game, game.data.tuning
    self.cfg = setmetatable(self.profile, { __index = self.tuning.bot }) -- read live, like all tuning
    self.me, self.enemy = game.players[self.id], game:opponentOf(game.players[self.id])
    local arena = game.arena
    self.field, self.parent = flood(arena, tileOf(arena, self.me.x, self.me.y, self.tuning))
    self.enemyField = flood(arena, tileOf(arena, self.enemy.x, self.enemy.y, self.tuning))
    for _, w in ipairs(game.wordfield.words) do self.wordSeen[w] = self.wordSeen[w] or self.time end

    local laser = self:threat()
    local input = laser and self:dodge(laser)
    return snap8(input or self:plan() or IDLE)
end

return Bot
