-- Spellbook: one player's template, the words filled into it, and the
-- active effect from the last completed template (see docs/DESIGN.md §8).
-- Pure rules; it asks the game to cast through the `castSpell` callback.
--
-- Every template, single or stacked, has the same shape:
--   when <conditions joined by "or">, repeat <n>: cast <spells joined by "and">
-- where the when-part and repeat-part are optional. A blank is
-- { type = "condition" | "spell", word = id or false }.

local Spellbook = {}
Spellbook.__index = Spellbook

-- data: { templates = {...}, words = { byId = {...} } }
-- castSpell(player, spellId): performs a spell for this player.
function Spellbook.new(player, opponent, data, castSpell)
    local self = setmetatable({}, Spellbook)
    self.player = player
    self.opponent = opponent
    self.data = data
    self.castSpell = castSpell
    self.template = nil  -- { level, conditions, spells, n, timeLeft }
    self.dealTimer = 0   -- counts down to the next template when template == nil
    self.trap = nil      -- { conditions = {ids}, spells = {ids}, n }
    self.casting = nil   -- { spells, left, raiseLeft, gapLeft } while raising the staff
    self.sandbox = false -- training room: no dealing, no timeouts; templates come from tiles
    return self
end

local function blanksOf(def, wanted)
    local list = {}
    for _, t in ipairs(def.blanks) do
        if t == wanted then list[#list + 1] = { type = t, word = false } end
    end
    return list
end

-- A fresh level-1 template from a definition in data/templates.json.
function Spellbook.makeTemplate(def, n, tuning)
    return {
        level = 1,
        conditions = blanksOf(def, "condition"),
        spells = blanksOf(def, "spell"),
        n = def.kind == "repeat" and n or nil,
        timeLeft = tuning.templates.timeout,
    }
end

local function append(into, from)
    for _, b in ipairs(from) do into[#into + 1] = b end
end

-- Stack `new` onto `old`: filled words stay and blanks pile up. Two
-- repeats are the exception: their counts add and the new repeat's spell
-- blank is dropped, so repeat 5 + repeat 5 = "repeat 10: cast ___" (more
-- casts of one spell) while repeat 5 + and = "repeat 5: cast ___ and ___"
-- (fewer casts, more spells). The result is one level higher.
function Spellbook.merge(old, new, tuning)
    local merged = {
        level = old.level + 1,
        conditions = {}, spells = {},
        timeLeft = tuning.templates.timeout,
    }
    append(merged.conditions, old.conditions); append(merged.conditions, new.conditions)
    append(merged.spells, old.spells)
    if old.n and new.n then
        merged.n = old.n + new.n
    else
        append(merged.spells, new.spells)
        merged.n = old.n or new.n
    end
    return merged
end

local function randomTemplate(self, tuning, rand)
    local list = self.data.templates
    local def = list[rand(1, #list)]
    local n = def.kind == "repeat" and rand(def.repeatMin, def.repeatMax) or nil
    return Spellbook.makeTemplate(def, n, tuning)
end

function Spellbook:deal(tuning, rand)
    self.template = randomTemplate(self, tuning, rand)
end

-- All blanks in fill order: conditions first, then spells.
function Spellbook:blanks()
    local list = {}
    if self.template then
        append(list, self.template.conditions)
        append(list, self.template.spells)
    end
    return list
end

-- Blank types still open in the current template (may contain duplicates).
function Spellbook:openTypes()
    local types = {}
    for _, b in ipairs(self:blanks()) do
        if not b.word then types[#types + 1] = b.type end
    end
    return types
end

function Spellbook:canAccept(word)
    for _, t in ipairs(self:openTypes()) do
        if t == word.type then return true end
    end
    return false
end

-- Fill the leftmost matching blank. Completes the template if it's full.
function Spellbook:accept(word, tuning)
    local blanks = self:blanks()
    for _, b in ipairs(blanks) do
        if not b.word and b.type == word.type then
            b.word = word.id
            break
        end
    end
    for _, b in ipairs(blanks) do
        if not b.word then return end
    end
    self:complete(tuning)
end

-- Training-room tiles. A template tile starts a template or stacks onto
-- the current one (up to the usual max level); reset clears everything.
function Spellbook:canTake(def, tuning)
    if def.type == "template" then
        return not self.template or self.template.level < tuning.stacking.maxLevel
    elseif def.type == "reset" then
        return true
    end
    return self:canAccept(def)
end

function Spellbook:take(def, tuning, rand)
    if def.type == "template" then
        local tpl = def.template
        local n = def.n or (tpl.kind == "repeat" and rand(tpl.repeatMin, tpl.repeatMax)) or nil
        local new = Spellbook.makeTemplate(tpl, n, tuning)
        self.template = self.template and Spellbook.merge(self.template, new, tuning) or new
    elseif def.type == "reset" then
        self:clearEffect()
        self.template = nil
    else
        self:accept(def, tuning)
    end
end

-- Remove whatever the previous template produced (the effect window ends).
function Spellbook:clearEffect()
    self.player.shield = 0
    self.player.accelerate = 0
    self.trap = nil
    self.casting = nil
end

local function words(blanks)
    local ids = {}
    for i, b in ipairs(blanks) do ids[i] = b.word end
    return ids
end

-- How long one raise of the staff lasts: the full aim time if it includes
-- an attack, otherwise a short pose.
function Spellbook.raiseTime(spells, tuning)
    for _, id in ipairs(spells) do
        if id == "attack" then return tuning.spells.telegraph end
    end
    return tuning.spells.raiseTime
end

-- One raise casts every spell in the list (attacks start charging, shield
-- and accelerate apply at once). `repeat N` raises N times with the staff
-- lowered for repeatGap in between; a plain cast raises once (DESIGN §6).
function Spellbook:raise(tuning)
    local c = self.casting
    for _, id in ipairs(c.spells) do self.castSpell(self.player, id) end
    c.left = c.left - 1
    c.raiseLeft = Spellbook.raiseTime(c.spells, tuning)
    c.gapLeft = tuning.spells.repeatGap
end

function Spellbook:castSequence(spells, n, tuning)
    self.casting = { spells = spells, left = n }
    self:raise(tuning)
end

-- True while the staff is up (not during the gap between raises).
function Spellbook:isRaising()
    return self.casting ~= nil and self.casting.raiseLeft > 0
end

function Spellbook:complete(tuning)
    local tpl = self.template
    self:clearEffect()
    self.template = nil
    self.dealTimer = tuning.templates.dealDelay

    local spells, n = words(tpl.spells), tpl.n or 1
    if #tpl.conditions > 0 then
        self.trap = { conditions = words(tpl.conditions), spells = spells, n = n }
        self:checkTrap(tuning) -- may fire right away (DESIGN §7)
    else
        self:castSequence(spells, n, tuning)
    end
end

-- Timeout: stack the next template onto this one, or start over at level 1
-- once the cap is reached. Either way the previous effect ends.
function Spellbook:timeout(tuning, rand)
    local old = self.template
    self:clearEffect()
    local new = randomTemplate(self, tuning, rand)
    if old.level < tuning.stacking.maxLevel then
        self.template = Spellbook.merge(old, new, tuning)
    else
        self.template = new
    end
end

function Spellbook:conditionTrue(id, tuning)
    local p, o = self.player, self.opponent
    local c = tuning.conditions
    if id == "dash" then return p.justDashed end
    if id == "still" then return p.stillTime >= c.standStillTime end
    if id == "hit" then return p.justHit end
    local dx, dy = o.x - p.x, o.y - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if id == "close" then return dist < c.closeDistance end
    if id == "far" then return dist > c.farDistance end
    return false
end

-- A trap fires when any of its conditions is true.
function Spellbook:checkTrap(tuning)
    local trap = self.trap
    if not trap then return end
    for _, id in ipairs(trap.conditions) do
        if self:conditionTrue(id, tuning) then
            self.trap = nil
            self:castSequence(trap.spells, trap.n, tuning)
            return
        end
    end
end

function Spellbook:update(dt, tuning, rand)
    if self.sandbox then
        -- no timeouts, no dealing
    elseif self.template then
        self.template.timeLeft = self.template.timeLeft - dt
        if self.template.timeLeft <= 0 then self:timeout(tuning, rand) end
    else
        self.dealTimer = self.dealTimer - dt
        if self.dealTimer <= 0 then self:deal(tuning, rand) end
    end

    if self.casting then
        local c = self.casting
        if c.raiseLeft > 0 then
            c.raiseLeft = c.raiseLeft - dt
        elseif c.left > 0 then
            c.gapLeft = c.gapLeft - dt
            if c.gapLeft <= 0 then self:raise(tuning) end
        else
            self.casting = nil
        end
    end

    self:checkTrap(tuning)
end

return Spellbook
