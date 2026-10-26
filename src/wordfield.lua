-- Word waves and pickups (DESIGN §9). Pure logic.
-- Each wave: markers appear `warning` seconds early, then the previous
-- wave's leftovers are cleared and the new words land on the markers.

local WordField = {}
WordField.__index = WordField

function WordField.new(data, arena)
    local self = setmetatable({}, WordField)
    self.data = data
    self.arena = arena
    self.words = {}    -- { def, x, y }
    self.markers = nil -- { {x, y}, ... } while a wave is incoming
    self.waveTimer = 0
    self.enabled = true -- the self-test turns waves off to control the board
    self.static = false -- training room: fixed tiles that never run out
    self.events = {}    -- pickups this frame, for render feedback
    return self
end

-- First wave lands `warning` seconds after the fight starts.
function WordField:start(tuning)
    self.enabled = true
    self.words = {}
    self.markers = nil
    self.waveTimer = tuning.words.warning
end

-- Training room: lay out fixed tiles and turn waves off.
function WordField:setStatic(words)
    self.static = true
    self.enabled = false
    self.markers = nil
    self.words = words
end

local function dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function WordField:pickPositions(count, tuning, players, rand)
    local w = tuning.words
    local points = {}
    for _ = 1, count do
        local x, y = self.arena:randomOpenPoint(rand, function(x, y)
            for _, p in ipairs(players) do
                if dist(x, y, p.x, p.y) < w.minPlayerDistance then return false end
            end
            for _, q in ipairs(points) do
                if dist(x, y, q.x, q.y) < w.minWordDistance then return false end
            end
            return true
        end)
        if x then points[#points + 1] = { x = x, y = y } end
    end
    return points
end

-- Take up to `count` random words from `pool` that aren't in `used` yet.
local function takeUnique(pool, count, used, out, rand)
    local candidates = {}
    for _, def in ipairs(pool) do
        if not used[def.id] then candidates[#candidates + 1] = def end
    end
    for _ = 1, math.min(count, #candidates) do
        local def = table.remove(candidates, rand(1, #candidates))
        used[def.id] = true
        out[#out + 1] = def
    end
end

-- A wave (DESIGN §9): the guaranteed words (attack), topped up to
-- spellsPerWave spells, plus one condition per open condition blank across
-- both players. Every word in a wave is unique.
function WordField:pickWave(tuning, spellbooks, rand)
    local w = tuning.words
    local picks, used = {}, {}
    for _, id in ipairs(w.guaranteed) do
        local def = self.data.byId[id]
        if def and not used[id] then used[id] = true; picks[#picks + 1] = def end
    end
    takeUnique(self.data.byType.spell, w.spellsPerWave - #picks, used, picks, rand)

    local conditionSlots = 0
    for _, book in ipairs(spellbooks) do
        for _, t in ipairs(book:openTypes()) do
            if t == "condition" then conditionSlots = conditionSlots + 1 end
        end
    end
    takeUnique(self.data.byType.condition, conditionSlots, used, picks, rand)

    for i = #picks, 2, -1 do
        local j = rand(1, i)
        picks[i], picks[j] = picks[j], picks[i]
    end
    return picks
end

-- True when no word on the map fits any player's open blanks. While a
-- player is between templates (the short deal delay) the board isn't
-- judged, since their next template may want what's there.
function WordField:isDead(spellbooks)
    for _, book in ipairs(spellbooks) do
        if not book.template then return false end
    end
    for _, word in ipairs(self.words) do
        for _, book in ipairs(spellbooks) do
            if book:canAccept(word.def) then return false end
        end
    end
    return true
end

-- The wave's words are chosen when its markers appear (`warning` seconds
-- before landing), so the marker count matches the word count.
function WordField:update(dt, tuning, players, spellbooks, rand)
    self.events = {}
    if not self.enabled then
        self:resolvePickups(tuning, players, spellbooks, rand)
        return
    end
    self.waveTimer = self.waveTimer - dt
    -- Dead board (empty, or nothing on it fits anyone): bring the next wave
    -- in now, after its usual flash warning, instead of leaving players
    -- with nothing to do.
    if not self.markers and self:isDead(spellbooks) then
        self.waveTimer = math.min(self.waveTimer, tuning.words.warning)
    end
    if not self.markers and self.waveTimer <= tuning.words.warning then
        local defs = self:pickWave(tuning, spellbooks, rand)
        self.markers = self:pickPositions(#defs, tuning, players, rand)
        for i, m in ipairs(self.markers) do m.def = defs[i] end
    end
    if self.waveTimer <= 0 then
        self.words = {}
        for i, m in ipairs(self.markers) do
            self.words[i] = { def = m.def, x = m.x, y = m.y }
        end
        self.markers = nil
        self.waveTimer = self.waveTimer + tuning.words.waveInterval
    end
    self:resolvePickups(tuning, players, spellbooks, rand)
end

-- A word goes to a touching player whose template can take it; if both
-- qualify, the closer one wins (random on an exact tie). In a static field
-- (training room) tiles stay put and only trigger when a player steps on
-- them, not every frame they stand there.
function WordField:resolvePickups(tuning, players, spellbooks, rand)
    local radius = tuning.words.pickupRadius
    for i = #self.words, 1, -1 do
        local word = self.words[i]
        word.touching = word.touching or {}
        local best, bestDist = nil, math.huge
        for k, p in ipairs(players) do
            local d = dist(word.x, word.y, p.x, p.y)
            local touching = d <= radius
            local fresh = touching and not (self.static and word.touching[k])
            word.touching[k] = touching
            if fresh and spellbooks[k]:canTake(word.def, tuning) then
                if d < bestDist or (d == bestDist and rand(1, 2) == 1) then
                    best, bestDist = k, d
                end
            end
        end
        if best then
            if not self.static then table.remove(self.words, i) end
            -- For render: who took what, from where (cleared each update).
            self.events[#self.events + 1] = { def = word.def, x = word.x, y = word.y, player = players[best] }
            spellbooks[best]:take(word.def, tuning, rand)
        end
    end
end

return WordField
