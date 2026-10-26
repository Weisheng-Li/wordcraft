-- Game: round flow (countdown -> fight -> over), lasers, and the order in
-- which everything updates each frame. Pure logic; render.lua draws it.

local Arena = require("src.arena")
local Player = require("src.player")
local Spellbook = require("src.spellbook")
local WordField = require("src.wordfield")

local Game = {}
Game.__index = Game

-- data: { tuning, arena, templates, words = { list, byId, byType }, training }
-- opts: { width, height, rand, mode = "versus" | "training" }
function Game.new(data, opts)
    local self = setmetatable({}, Game)
    self.data = data
    self.width, self.height = opts.width, opts.height
    self.rand = opts.rand
    self.mode = opts.mode or "versus"
    self:reset()
    return self
end

-- Training-room tiles from data/training.json, grouped by category
-- ("templates", "spells", "conditions", plus "always" for reset).
local function trainingTiles(data, arena)
    local templatesById = {}
    for _, def in ipairs(data.templates) do templatesById[def.id] = def end
    local sets = {}
    for _, item in ipairs(data.training.items) do
        local def
        if item.word then
            def = data.words.byId[item.word]
        elseif item.template then
            def = { type = "template", id = "tpl_" .. item.label, label = item.label,
                    template = templatesById[item.template], n = item.n }
        elseif item.reset then
            def = { type = "reset", id = "reset", label = item.label or "reset" }
        end
        local x, y = arena:tileCenter(item.col, item.row)
        sets[item.category] = sets[item.category] or {}
        table.insert(sets[item.category], { def = def, x = x, y = y })
    end
    return sets
end

-- Put category i's tiles (plus the always-there ones) on the floor.
-- Tiles that appear under the player count as already stepped on, so
-- switching never takes a word by accident.
function Game:showTrainingCategory(i)
    local cats = self.data.training.categories
    self.trainingCategory = (i - 1) % #cats + 1
    local list = {}
    for _, key in ipairs({ cats[self.trainingCategory].id, "always" }) do
        for _, tile in ipairs(self.trainingSets[key] or {}) do list[#list + 1] = tile end
    end
    local p, r = self.players[1], self.data.tuning.words.pickupRadius
    for _, tile in ipairs(list) do
        local dx, dy = tile.x - p.x, tile.y - p.y
        tile.touching = { dx * dx + dy * dy <= r * r }
    end
    self.wordfield:setStatic(list)
end

function Game:nextTrainingCategory()
    self:showTrainingCategory(self.trainingCategory + 1)
end

function Game:reset()
    local t = self.data.tuning
    local training = self.mode == "training"
    local arenaDef = training and self.data.training.arena or self.data.arena
    self.arena = Arena.new(arenaDef, self.width, self.height)
    local s1, s2 = self.arena.starts[1], self.arena.starts[2]
    self.players = {
        Player.new(1, s1.x, s1.y, "wizard_blue", t),
        Player.new(2, s2.x, s2.y, training and "dummy" or "wizard_red", t),
    }
    self.players[2].facing = -1
    -- A/B test: blue eases in and out of movement, red keeps instant
    -- start/stop as the baseline. Make it the same for both once decided.
    self.players[1].smoothMovement = true

    local cast = function(caster, spell) self:castSpell(caster, spell) end
    self.spellbooks = {
        Spellbook.new(self.players[1], self.players[2], self.data, cast),
        Spellbook.new(self.players[2], self.players[1], self.data, cast),
    }
    self.wordfield = WordField.new(self.data.words, self.arena)
    self.lasers = {}   -- charging: { caster, target, timer, slot }
    self.beams = {}    -- fired, for drawing: { caster, slot, x2, y2, result, timer }
    self.winner = nil  -- 1, 2 or "draw"

    if training then
        -- Nobody can lose; templates come from floor tiles; no countdown.
        for _, p in ipairs(self.players) do p.infiniteHp = true end
        for _, book in ipairs(self.spellbooks) do book.sandbox = true end
        self.trainingSets = trainingTiles(self.data, self.arena)
        self:showTrainingCategory(1)
        self.dummyCooldown = 0
        self.state = "fight"
    else
        self.state = "countdown"
        self.timer = t.round.countdown
    end
end

function Game:opponentOf(player)
    return self.players[3 - player.id]
end

function Game:castSpell(caster, spell)
    local t = self.data.tuning
    if spell == "attack" then
        -- slot = position within a volley cast on the same frame, so each
        -- simultaneous laser gets its own orb on screen.
        local slot = 1
        for _, l in ipairs(self.lasers) do
            if l.caster == caster and l.timer == t.spells.telegraph then slot = slot + 1 end
        end
        self.lasers[#self.lasers + 1] = {
            caster = caster, target = self:opponentOf(caster), timer = t.spells.telegraph, slot = slot,
        }
    elseif spell == "shield" then
        caster.shield = caster.shield + 1
    elseif spell == "accelerate" then
        caster.accelerate = math.min(caster.accelerate + 1, t.spells.accelerateMaxStacks)
    end
end

function Game:fireLaser(laser)
    local t = self.data.tuning
    local c, tg = laser.caster, laser.target
    local beam = { caster = c, slot = laser.slot, x2 = tg.x, y2 = tg.y, timer = t.spells.beamShowTime }
    local clear, wx, wy = self.arena:lineOfSight(c.x, c.y, tg.x, tg.y)
    if not clear then
        beam.x2, beam.y2, beam.result = wx, wy, "wall"
    else
        beam.result = tg:receiveHit(t.spells.attackDamage, c.x, c.y, t)
    end
    self.beams[#self.beams + 1] = beam
end

function Game:updateLasers(dt)
    for i = #self.lasers, 1, -1 do
        local laser = self.lasers[i]
        laser.timer = laser.timer - dt
        if laser.timer <= 0 then
            table.remove(self.lasers, i)
            self:fireLaser(laser)
        end
    end
    for i = #self.beams, 1, -1 do
        local b = self.beams[i]
        b.timer = b.timer - dt
        if b.timer <= 0 then table.remove(self.beams, i) end
    end
end

-- Training dummy: no AI. If the player is inside its range and its
-- cooldown is ready, it fires a normal laser at them.
function Game:updateDummy(dt)
    local cfg = self.data.training.dummy
    local dummy, p = self.players[2], self.players[1]
    self.dummyCooldown = math.max(0, self.dummyCooldown - dt)
    local dx, dy = p.x - dummy.x, p.y - dummy.y
    if self.dummyCooldown <= 0 and math.sqrt(dx * dx + dy * dy) <= cfg.range then
        self:castSpell(dummy, "attack")
        self.dummyCooldown = cfg.cooldown
    end
end

function Game:updateTraining(dt, inputs)
    local t = self.data.tuning
    local p, book = self.players[1], self.spellbooks[1]
    p:update(dt, inputs[1], t, self.arena)
    self.wordfield:update(dt, t, { p }, { book }, self.rand)
    self:updateLasers(dt)
    book:update(dt, t, self.rand)
    self:updateDummy(dt)
    for _, pl in ipairs(self.players) do pl:clearFrameEvents() end
end

-- inputs[k] = { x, y, dash } for player k.
function Game:update(dt, inputs)
    local t = self.data.tuning

    if self.mode == "training" then
        self:updateTraining(dt, inputs)
        return
    end

    if self.state == "countdown" then
        self.timer = self.timer - dt
        if self.timer <= 0 then
            self.state = "fight"
            for _, book in ipairs(self.spellbooks) do book:deal(t, self.rand) end
            self.wordfield:start(t)
        end
        return
    end

    if self.state ~= "fight" then
        self:updateLasers(dt) -- let the final beam fade out
        return
    end

    -- Order matters: movement sets "dashed", lasers set "hit", then
    -- spellbooks read both for their trap conditions.
    for k, p in ipairs(self.players) do p:update(dt, inputs[k], t, self.arena) end
    self.wordfield:update(dt, t, self.players, self.spellbooks, self.rand)
    self:updateLasers(dt)
    for _, book in ipairs(self.spellbooks) do book:update(dt, t, self.rand) end
    for _, p in ipairs(self.players) do p:clearFrameEvents() end

    local dead1, dead2 = self.players[1].hp <= 0, self.players[2].hp <= 0
    if dead1 or dead2 then
        self.state = "over"
        self.winner = (dead1 and dead2) and "draw" or (dead1 and 2 or 1)
        self.lasers = {}
        self.wordfield.markers = nil -- no incoming wave once the round is over
    end
end

return Game
