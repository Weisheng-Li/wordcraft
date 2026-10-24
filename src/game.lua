-- Game: round flow (countdown -> fight -> over), lasers, and the order in
-- which everything updates each frame. Pure logic; render.lua draws it.

local Arena = require("src.arena")
local Player = require("src.player")
local Spellbook = require("src.spellbook")
local WordField = require("src.wordfield")

local Game = {}
Game.__index = Game

-- data: { tuning, arena, templates, words = { list, byId, byType } }
-- opts: { width, height, rand }
function Game.new(data, opts)
    local self = setmetatable({}, Game)
    self.data = data
    self.width, self.height = opts.width, opts.height
    self.rand = opts.rand
    self:reset()
    return self
end

function Game:reset()
    local t = self.data.tuning
    self.arena = Arena.new(self.data.arena, self.width, self.height)
    local s1, s2 = self.arena.starts[1], self.arena.starts[2]
    self.players = {
        Player.new(1, s1.x, s1.y, "wizard_blue", t),
        Player.new(2, s2.x, s2.y, "wizard_red", t),
    }
    self.players[2].facing = -1

    local cast = function(caster, spell) self:castSpell(caster, spell) end
    self.spellbooks = {
        Spellbook.new(self.players[1], self.players[2], self.data, cast),
        Spellbook.new(self.players[2], self.players[1], self.data, cast),
    }
    self.wordfield = WordField.new(self.data.words, self.arena)
    self.lasers = {}   -- charging: { caster, target, timer }
    self.beams = {}    -- fired, for drawing: { x1, y1, x2, y2, result, timer }
    self.state = "countdown"
    self.timer = t.round.countdown
    self.winner = nil  -- 1, 2 or "draw"
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

-- inputs[k] = { x, y, dash } for player k.
function Game:update(dt, inputs)
    local t = self.data.tuning

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
    end
end

return Game
