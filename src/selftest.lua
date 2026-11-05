-- Headless rules check: `lovec . --selftest`. Drives Game with scripted
-- inputs and checks the rules from docs/DESIGN.md. Prints PASS/FAIL lines.

local Bot = require("src.bot")
local Game = require("src.game")
local Select = require("src.select")
local Spellbook = require("src.spellbook")

local SelfTest = {}

local W, H = 320, 180
local DT = 1 / 60
local IDLE = { x = 0, y = 0, dash = false }

-- characters (optional): { id, id }, default wizards.
local function newFight(data, characters)
    local g = Game.new(data, { width = W, height = H, rand = math.random, characters = characters })
    g:update(data.tuning.round.countdown + 0.01, { IDLE, IDLE })
    assert(g.state == "fight", "countdown should end")
    -- Move both players onto the open row (row 3) with a clear line between them.
    local _, y = g.arena:tileCenter(1, 3)
    g.players[1].x, g.players[1].y = 40, y
    g.players[2].x, g.players[2].y = 280, y
    g.wordfield.enabled = false -- no random words unless a test wants them
    return g
end

local function step(g, seconds, inputs)
    local n = math.floor(seconds / DT + 0.5)
    for _ = 1, n do g:update(DT, inputs or { IDLE, IDLE }) end
end

-- Wait until a laser cast now has fired.
local function fire(g)
    step(g, g.data.tuning.spells.telegraph + 0.05)
end

-- Force a template and fill it word by word.
local function template(g, templateId, n)
    for _, def in ipairs(g.data.templates) do
        if def.id == templateId then return Spellbook.makeTemplate(def, n, g.data.tuning) end
    end
end

local function give(g, k, templateId, n)
    g.spellbooks[k].template = template(g, templateId, n)
end

local function fill(g, k, ...)
    for _, id in ipairs({ ... }) do
        g.spellbooks[k]:accept(g.data.words.byId[id], g.data.tuning)
    end
end

local tests = {}

tests["combo attack+attack deals 2 after the telegraph"] = function(g)
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    assert(g.players[2].hp == 10, "no damage before telegraph")
    fire(g)
    assert(g.players[2].hp == 8, "expected 8 hp, got " .. g.players[2].hp)
end

tests["one shield charge blocks one of two lasers"] = function(g)
    g.players[2].shield = 1
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    fire(g)
    assert(g.players[2].hp == 9 and g.players[2].shield == 0)
end

tests["dash makes the target dodge"] = function(g)
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    step(g, g.data.tuning.spells.telegraph - 0.05)
    step(g, 0.1, { IDLE, { x = 0, y = 1, dash = true } })
    assert(g.players[2].hp == 10, "dash should dodge, hp " .. g.players[2].hp)
end

tests["wall blocks the laser"] = function(g)
    local _, y = g.arena:tileCenter(1, 5) -- row 5 has walls between the starts
    g.players[1].y, g.players[2].y = y, y
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    fire(g)
    assert(g.players[2].hp == 10)
end

tests["repeat N fires N attacks"] = function(g)
    give(g, 1, "repeat", 3); fill(g, 1, "attack")
    local s = g.data.tuning.spells
    fire(g)
    assert(g.players[2].hp == 9, "one shot per raise, hp " .. g.players[2].hp)
    step(g, 2 * (s.telegraph + s.repeatGap))
    assert(g.players[2].hp == 7, "expected 7, got " .. g.players[2].hp)
end

tests["when close fires immediately if already true"] = function(g)
    g.players[2].x = g.players[1].x + 30 -- already close
    give(g, 1, "when"); fill(g, 1, "close", "attack")
    assert(g.spellbooks[1].casting, "should fire on arming")
    fire(g)
    assert(g.players[2].hp == 9)
end

tests["close trap keeps firing while the enemy stays close, after each recharge"] = function(g)
    local t = g.data.tuning
    local p1 = g.players[1]
    g.players[2].x = p1.x + 30
    give(g, 1, "when"); fill(g, 1, "close", "shield")
    assert(p1.shield == 1, "fires on arming")
    step(g, t.spells.raiseTime + 0.05) -- spells done: the recharge starts
    step(g, t.traps.recharge - 0.2)
    assert(p1.shield == 1, "still recharging")
    step(g, 0.3)
    assert(p1.shield == 2, "fired again, got " .. p1.shield)
    g.players[2].x = p1.x + 150 -- enemy leaves
    step(g, t.spells.raiseTime + t.traps.recharge + 0.5)
    assert(p1.shield == 2, "nothing while the enemy is away")
end

tests["dash trap fires on every dash, with no recharge"] = function(g)
    local t = g.data.tuning
    local p1 = g.players[1]
    give(g, 1, "when"); fill(g, 1, "dash", "shield")
    step(g, DT, { { x = 1, y = 0, dash = true }, IDLE })
    assert(p1.shield == 1 and g.spellbooks[1].trap.recharge == 0, "fired, no recharge")
    step(g, t.dash.cooldown + 0.05)
    step(g, DT, { { x = -1, y = 0, dash = true }, IDLE })
    assert(p1.shield == 2, "fired on the second dash, got " .. p1.shield)
end

tests["a trap ignores its condition while its spells are being cast"] = function(g)
    local p1 = g.players[1]
    give(g, 1, "when"); fill(g, 1, "dash", "shield")
    step(g, DT, { { x = 1, y = 0, dash = true }, IDLE })
    assert(g.spellbooks[1].casting and not g.spellbooks[1]:trapReady("dash"))
    p1.dashCooldown = 0
    step(g, DT, { { x = -1, y = 0, dash = true }, IDLE })
    assert(p1.shield == 1, "second dash during the cast is ignored")
end

tests["a trap stays armed until the next template ends"] = function(g)
    g.players[2].x = g.players[1].x + 30
    give(g, 1, "when"); fill(g, 1, "close", "shield")
    assert(g.spellbooks[1].trap)
    give(g, 1, "repeat", 2); fill(g, 1, "accelerate")
    assert(not g.spellbooks[1].trap and g.players[1].shield == 0, "the next completion ends it")
end

tests["when dash fires on dash"] = function(g)
    give(g, 1, "when"); fill(g, 1, "dash", "shield")
    step(g, 0.1)
    assert(g.players[1].shield == 0)
    step(g, DT, { { x = 1, y = 0, dash = true }, IDLE })
    assert(g.players[1].shield == 1)
end

tests["effect ends when the next template times out"] = function(g)
    give(g, 1, "repeat", 3); fill(g, 1, "shield")
    step(g, 3 * g.data.tuning.spells.raiseTime + 2 * g.data.tuning.spells.repeatGap + 0.1)
    assert(g.players[1].shield == 3, "3 charges, got " .. g.players[1].shield)
    step(g, Spellbook.timeoutFor(1, g.data.tuning) + 0.1)
    assert(g.players[1].shield == 0, "charges cleared by timeout")
end

tests["pickup only fills a matching blank"] = function(g)
    give(g, 1, "combo")
    local p = g.players[1]
    g.wordfield.words = { { def = g.data.words.byId.close, x = p.x, y = p.y } }
    step(g, DT)
    assert(#g.wordfield.words == 1, "condition word must stay")
    g.wordfield.words = { { def = g.data.words.byId.shield, x = p.x, y = p.y } }
    step(g, DT)
    assert(#g.wordfield.words == 0 and g.spellbooks[1].template.spells[1].word == "shield")
end

-- Run one wave with the given templates; returns the landed words.
local function wave(g)
    g.wordfield:start(g.data.tuning)
    step(g, g.data.tuning.words.warning + 0.05)
    return g.wordfield.words
end

local function ids(words)
    local set, n = {}, 0
    for _, w in ipairs(words) do
        assert(not set[w.def.id], "duplicate word " .. w.def.id)
        set[w.def.id] = w.def.type; n = n + 1
    end
    return set, n
end

local function countType(set, wordType)
    local n = 0
    for _, t in pairs(set) do if t == wordType then n = n + 1 end end
    return n
end

tests["wave: no condition slots -> 2 spells incl. attack, in open floor"] = function(g)
    give(g, 1, "combo"); give(g, 2, "repeat", 2)
    local words = wave(g)
    local set, n = ids(words)
    assert(n == 2 and set.attack and countType(set, "spell") == 2, "got " .. n .. " words")
    for _, w in ipairs(words) do assert(not g.arena:isSolidAt(w.x, w.y), "word in wall") end
end

tests["wave: one condition per open condition slot, all unique"] = function(g)
    local t = g.data.tuning
    g.spellbooks[1].template = Spellbook.merge(template(g, "when"), template(g, "when"), t) -- 2 slots
    give(g, 2, "when")                                                                      -- 1 slot
    local set, n = ids(wave(g))
    assert(set.attack and countType(set, "spell") == 2)
    assert(countType(set, "condition") == 3, "conditions " .. countType(set, "condition"))
    assert(n == 5)
end

tests["wave: filled condition slots don't count"] = function(g)
    give(g, 1, "when"); fill(g, 1, "close")
    give(g, 2, "combo")
    local set = ids(wave(g))
    assert(countType(set, "condition") == 0)
end

tests["wave: an emptied map gets the next wave right away"] = function(g)
    local t = g.data.tuning
    give(g, 1, "combo"); give(g, 2, "combo")
    wave(g)
    step(g, 2)
    g.wordfield.words = {} -- everything picked up
    step(g, t.words.warning + 0.05)
    assert(#g.wordfield.words > 0, "no new words")
    assert(g.wordfield.waveTimer > t.words.waveInterval - 1, "timer restarted")
end

tests["wave: a dead board (nothing fits anyone) brings the next wave early"] = function(g)
    local t = g.data.tuning
    give(g, 1, "combo"); give(g, 2, "combo")
    wave(g)
    step(g, 2)
    local close = g.data.words.byId.close
    local useless = { def = close, x = 300, y = 170 }
    g.wordfield.words = { useless } -- only a condition left; both need spells
    step(g, t.words.warning + 0.05)
    for _, w in ipairs(g.wordfield.words) do assert(w ~= useless, "dead word cleared") end
    assert(#g.wordfield.words > 0, "new wave landed")
end

tests["wave: a word that fits one player keeps the board alive"] = function(g)
    local t = g.data.tuning
    give(g, 1, "when"); give(g, 2, "combo")
    wave(g)
    step(g, 2)
    local keep = { def = g.data.words.byId.close, x = 300, y = 170 }
    g.wordfield.words = { keep } -- P1 still needs a condition
    step(g, t.words.warning + 0.5)
    assert(g.wordfield.words[1] == keep and not g.wordfield.markers, "no early wave")
end

tests["wave: 4+ open spell blanks across both players add a third spell"] = function(g)
    give(g, 1, "combo"); give(g, 2, "repeat", 2) -- 3 open spell blanks
    local set = ids(wave(g))
    assert(countType(set, "spell") == 2, "3 open -> 2 spells")
    give(g, 1, "combo"); give(g, 2, "combo")       -- 4 open spell blanks
    set = ids(wave(g))
    assert(countType(set, "spell") == 3 and set.attack, "4 open -> 3 spells incl. attack")
end

tests["wave: next wave clears leftovers"] = function(g)
    give(g, 1, "combo"); give(g, 2, "combo")
    local first = wave(g)[1]
    step(g, g.data.tuning.words.waveInterval)
    for _, w in ipairs(g.wordfield.words) do assert(w ~= first, "leftover not cleared") end
end

tests["a hit pushes the target away from the shooter"] = function(g)
    local x0 = g.players[2].x
    give(g, 1, "combo"); fill(g, 1, "attack", "shield")
    fire(g)
    step(g, g.data.tuning.hit.knockbackDuration + 0.05)
    local moved = g.players[2].x - x0
    assert(moved > g.data.tuning.hit.knockbackDistance * 0.8, "pushed only " .. moved)
end

tests["stack: timeout merges the next template and keeps filled words"] = function(g)
    local book = g.spellbooks[1]
    give(g, 1, "combo"); fill(g, 1, "shield")
    book.template.timeLeft = 0.01
    step(g, DT * 2)
    local tpl = book.template
    assert(tpl.level == 2, "level " .. tpl.level)
    assert(tpl.spells[1].word == "shield", "filled word kept")
    assert(#tpl.spells + #tpl.conditions >= 3, "blanks piled up")
    assert(tpl.timeLeft > Spellbook.timeoutFor(2, g.data.tuning) - 0.1, "timer reset to the level-2 time")
end

tests["stack: each level gets its own timeout"] = function(g)
    local book, t = g.spellbooks[1], g.data.tuning
    give(g, 1, "combo")
    for level = 1, 3 do
        local tpl = book.template
        assert(tpl.level == level, "level " .. tpl.level)
        assert(tpl.timeTotal == t.templates.timeout[level], "level " .. level .. " time " .. tpl.timeTotal)
        assert(math.abs(tpl.timeLeft - tpl.timeTotal) < 0.05, "starts full")
        tpl.timeLeft = 0.01; step(g, DT * 2)
    end
    assert(book.template.level == 1 and book.template.timeTotal == t.templates.timeout[1], "back to level-1 time")
end

tests["stack: level 3 timeout starts over at level 1"] = function(g)
    local book = g.spellbooks[1]
    give(g, 1, "combo"); fill(g, 1, "shield")
    for _ = 1, 2 do book.template.timeLeft = 0.01; step(g, DT * 2) end
    assert(book.template.level == 3)
    book.template.timeLeft = 0.01; step(g, DT * 2)
    assert(book.template.level == 1, "back to level 1")
    for _, b in ipairs(book:blanks()) do assert(not b.word, "fresh template has no words") end
end

tests["stack: merged repeats add up"] = function(g)
    local t = g.data.tuning
    local m = Spellbook.merge(template(g, "repeat", 3), template(g, "repeat", 4), t)
    assert(m.n == 7 and #m.spells == 1, "repeat 3 + repeat 4 = repeat 7 with one spell blank")
    m = Spellbook.merge(Spellbook.merge(template(g, "repeat", 5), template(g, "repeat", 5), t), template(g, "repeat", 5), t)
    assert(m.n == 15 and #m.spells == 1, "three repeat 5s make repeat 15 with one spell blank")
    m = Spellbook.merge(template(g, "repeat", 2), template(g, "combo"), t)
    assert(m.n == 2 and #m.spells == 3)
end

tests["stack: merged trap fires on either condition and casts everything"] = function(g)
    local t = g.data.tuning
    g.spellbooks[1].template = Spellbook.merge(template(g, "when"), template(g, "repeat", 2), t)
    fill(g, 1, "close", "attack", "attack") -- close is false, players are far apart
    assert(g.spellbooks[1].trap, "armed, not fired")
    g.spellbooks[1].trap.conditions[2] = "dash" -- an "or" that comes true
    step(g, DT, { { x = 1, y = 0, dash = true }, IDLE }) -- dash along the open row
    step(g, DT)
    step(g, 2 * t.spells.telegraph + t.spells.repeatGap + 0.1)
    assert(g.players[2].hp == 6, "2 spells x2 = 4 hits, hp " .. g.players[2].hp)
end

tests["stack: a timeout merge still ends the previous effect"] = function(g)
    give(g, 1, "repeat", 2); fill(g, 1, "shield")
    step(g, 1)
    assert(g.players[1].shield == 2)
    g.spellbooks[1].template.timeLeft = 0.01
    step(g, DT * 2)
    assert(g.players[1].shield == 0)
end

tests["accelerate stacks up to the cap and speeds up walking"] = function(g)
    local t = g.data.tuning
    local p = g.players[1]
    give(g, 1, "repeat", 5); fill(g, 1, "accelerate")
    step(g, 5 * t.spells.raiseTime + 4 * t.spells.repeatGap + 0.1)
    assert(p.accelerate == t.spells.accelerateMaxStacks, "stacks " .. p.accelerate)
    step(g, 0.2, { { x = 1, y = 0, dash = false }, IDLE }) -- get past any speed ramp
    local x0 = p.x
    step(g, 0.5, { { x = 1, y = 0, dash = false }, IDLE })
    local expected = 0.5 * t.player.moveSpeed * (1 + t.spells.accelerateMaxStacks * t.spells.accelerateBonus)
    assert(math.abs((p.x - x0) - expected) < 2, "moved " .. (p.x - x0) .. ", expected " .. expected)
end

tests["staff lowers between repeat raises"] = function(g)
    local s = g.data.tuning.spells
    local book = g.spellbooks[1]
    give(g, 1, "repeat", 2); fill(g, 1, "attack")
    assert(book:isRaising(), "raised on cast")
    step(g, s.telegraph + s.repeatGap / 2)
    assert(not book:isRaising(), "lowered in the gap")
    step(g, s.repeatGap)
    assert(book:isRaising(), "raised again")
    step(g, s.telegraph + 0.1)
    assert(not book.casting, "sequence finished")
end

tests["round end clears incoming wave markers"] = function(g)
    g.wordfield:start(g.data.tuning)
    step(g, DT)
    assert(g.wordfield.markers, "markers showing before the KO")
    g.players[2].hp = 1
    give(g, 1, "combo"); fill(g, 1, "attack", "shield")
    fire(g)
    assert(g.state == "over" and not g.wordfield.markers, "markers cleared")
end

tests["smooth movement ramps up, slides to a stop, and reverses fast"] = function(g)
    local m, p = g.data.tuning.movement, g.players[1]
    local full = g.data.tuning.player.moveSpeed
    local right, left = { x = 1, y = 0, dash = false }, { x = -1, y = 0, dash = false }
    step(g, DT, { right, IDLE })
    assert(p.vx > 0 and p.vx < full, "ramping up, vx " .. p.vx)
    step(g, m.accelTime, { right, IDLE })
    assert(math.abs(p.vx - full) < 0.01, "full speed after accelTime")
    step(g, DT, { IDLE, IDLE })
    assert(p.vx > 0, "slides after release")
    step(g, m.decelTime, { IDLE, IDLE })
    assert(p.vx == 0, "stopped after decelTime")
    step(g, m.accelTime, { right, IDLE })
    step(g, m.accelTime + DT, { left, IDLE })
    assert(math.abs(p.vx + full) < 0.01, "reversed to full speed quickly")
end

tests["corner correction slides past a barely-clipped corner"] = function(g)
    local a, nudge = g.arena, g.data.tuning.movement.cornerNudge
    -- Wall tile at col 4, row 2 spans x 48..64. Walk up into its bottom
    -- edge with the 10 px box overlapping its left corner by `overlap`.
    local function walkUp(overlap, n)
        local x = 48 + overlap - 5
        local y = a.top + 2 * a.tile + 4 -- just below the tile
        local nx, ny, _, hardY = a:moveBox(x, y, 0, -12, 10, 6, n)
        return nx, ny, hardY, x, y
    end
    local nx, ny, hardY, x0, y0 = walkUp(2, 0)
    assert(hardY and ny == y0 and nx == x0, "no nudge: stuck on the corner")
    nx, ny, hardY = walkUp(2, nudge)
    assert(not hardY and ny < y0 - 4 and nx + 5 <= 48, "nudge: slid left of the corner and kept going")
    nx, ny, hardY = walkUp(nudge + 2, nudge)
    assert(hardY and ny == y0, "bigger overlap than the nudge: blocked")
end

tests["KO ends the round"] = function(g)
    g.players[2].hp = 1
    give(g, 1, "combo"); fill(g, 1, "attack", "shield")
    fire(g)
    assert(g.state == "over" and g.winner == 1)
end

tests["random play for 3 minutes doesn't crash"] = function(g)
    g.wordfield:start(g.data.tuning)
    for _ = 1, 180 * 60 do
        local function rnd()
            return { x = math.random(-1, 1), y = math.random(-1, 1), dash = math.random() < 0.02 }
        end
        g:update(DT, { rnd(), rnd() })
        if g.state == "over" then g:reset(); step(g, 3.1) end
        for _, p in ipairs(g.players) do
            assert(not g.arena:boxHitsWall(p.x, p.y - 3, 10, 6), "player inside wall")
        end
    end
end

---------------------------------------------------------------- training room

local function newTraining(data)
    return Game.new(data, { width = W, height = H, rand = math.random, mode = "training" })
end

-- Find a tile by label, switching the floor's category until it shows.
local function tile(g, label)
    for _ = 1, #g.data.training.categories do
        for _, w in ipairs(g.wordfield.words) do
            if w.def.label == label then return w end
        end
        g:nextTrainingCategory()
    end
    error("no tile " .. label)
end

-- Step onto a tile for one frame, then off it again.
local function touch(g, label)
    local p, t = g.players[1], tile(g, label)
    p.x, p.y = t.x, t.y
    step(g, DT)
    p.x, p.y = t.x + 24, t.y -- step off sideways, into the gap between tiles
    step(g, DT)
end

local trainingTests = {}

-- Walk P1 toward (x, y) until the pick happens (or give up after 4 s).
local function walkInto(g, x, y)
    for _ = 1, 240 do
        if not g.trainingPicks then return end
        local p = g.players[1]
        local dx, dy = x - p.x, y - p.y
        local len = math.max(math.sqrt(dx * dx + dy * dy), 0.001)
        g:update(DT, { { x = dx / len, y = dy / len, dash = false }, IDLE })
    end
end

trainingTests["training: walk into a character to play it; then the tiles appear"] = function(g)
    g = Game.new(g.data, { width = W, height = H, rand = math.random, mode = "training", pickCharacter = true })
    assert(g.trainingPicks and #g.trainingPicks >= 2, "every available character should stand in the room")
    assert(#g.wordfield.words == 0, "no tiles while picking")
    assert(g.players[1].character == "ghost" and g.players[1].sprite == "ghost", "you start as the ghost")
    g:nextTrainingCategory()
    assert(g.trainingPicks, "space does nothing while picking")
    local mage
    for _, pk in ipairs(g.trainingPicks) do if pk.id == "shieldmage" then mage = pk end end
    walkInto(g, mage.x, mage.y)
    local p = g.players[1]
    assert(not g.trainingPicks, "the pick should be over")
    assert(p.character == "shieldmage" and p.sprite == "shieldmage_blue", "P1 should now be the Bulwark")
    assert(#g.wordfield.words > 0, "tiles should appear")
end

trainingTests["training: no character pick unless asked (tiles right away)"] = function(g)
    assert(not g.trainingPicks and #g.wordfield.words > 0, "plain training starts with tiles")
end

trainingTests["training: template tiles start and stack to the max, then refuse"] = function(g)
    local book = g.spellbooks[1]
    assert(not book.template, "starts empty")
    touch(g, "when")
    assert(book.template and book.template.level == 1)
    touch(g, "repeat")
    local n = book.template.n
    assert(book.template.level == 2 and n >= 2 and n <= 5, "random repeat 2-5, got " .. tostring(n))
    touch(g, "and")
    assert(book.template.level == 3)
    touch(g, "when")
    assert(book.template.level == 3 and book.template.n == n, "4th template refused")
end

trainingTests["training: tiles stay, and only trigger when stepped onto"] = function(g)
    local book = g.spellbooks[1]
    touch(g, "and")
    local p, t = g.players[1], tile(g, "attack")
    p.x, p.y = t.x, t.y
    step(g, 0.5) -- stand on it for many frames
    assert(book.template.spells[1].word == "attack" and not book.template.spells[2].word, "one pickup per step")
    assert(tile(g, "attack"), "tile still there")
    p.x = t.x + 24; step(g, DT); p.x = t.x; step(g, DT)
    assert(not book.template, "second step completed the template")
end

trainingTests["training: reset clears template and effects"] = function(g)
    local book, p = g.spellbooks[1], g.players[1]
    touch(g, "and"); touch(g, "shield"); touch(g, "shield")
    step(g, 2)
    assert(p.shield == 2)
    touch(g, "when"); touch(g, "close")
    touch(g, "reset")
    assert(not book.template and p.shield == 0)
end

trainingTests["training: no timeouts and no dealing"] = function(g)
    local book = g.spellbooks[1]
    local longest = Spellbook.timeoutFor(math.huge, g.data.tuning)
    step(g, longest + 1)
    assert(not book.template, "nothing dealt")
    touch(g, "and")
    step(g, longest + 1)
    assert(book.template and book.template.level == 1, "no timeout stacking")
end

trainingTests["training: dummy fires only in range; nobody can lose"] = function(g)
    local d, p = g.players[2], g.players[1]
    local cfg = g.data.training.dummy
    p.x, p.y = d.x - cfg.range - 20, d.y - 40
    step(g, 3)
    assert(#g.lasers == 0 and #g.beams == 0, "no shots out of range")
    p.x, p.y = d.x - cfg.range + 10, d.y - 24
    step(g, DT)
    assert(#g.lasers == 1 and g.lasers[1].caster == d, "dummy fires in range")
    for _ = 1, 20 do
        p.x, p.y = d.x - 30, d.y - 24
        step(g, cfg.cooldown)
    end
    assert(p.hp == g.data.tuning.player.hp and g.state == "fight", "infinite hp")
    touch(g, "and"); touch(g, "attack"); touch(g, "attack")
    local _, y = g.arena:tileCenter(17, 7)
    p.x, p.y = d.x - 20, y -- clear shot, below the wall
    step(g, g.data.tuning.spells.telegraph + 0.1)
    assert(d.hp == g.data.tuning.player.hp and g.state == "fight", "dummy can't die")
end

trainingTests["training: space cycles one category at a time; reset always shows"] = function(g)
    local cats = g.data.training.categories
    local function types()
        local set = {}
        for _, w in ipairs(g.wordfield.words) do set[w.def.type] = true end
        return set
    end
    for i = 1, #cats do
        assert(g.trainingCategory == i)
        local set = types()
        assert(set[cats[i].type] and set.reset, "category " .. i .. " shows its tiles and reset")
        for _, c in ipairs(cats) do
            if c ~= cats[i] then assert(not set[c.type], "only one category on the floor") end
        end
        g:nextTrainingCategory()
    end
    assert(g.trainingCategory == 1, "wraps around")
end

trainingTests["training: a tile appearing under the player isn't taken"] = function(g)
    local book, p = g.spellbooks[1], g.players[1]
    touch(g, "and")
    local t = tile(g, "attack") -- switches to spells
    for _ = 1, #g.data.training.categories - 1 do g:nextTrainingCategory() end -- back off spells
    p.x, p.y = t.x, t.y
    step(g, DT)
    g:showTrainingCategory(2) -- spells appear right under the player
    step(g, DT)
    assert(not book.template.spells[1].word, "not taken by switching")
end

trainingTests["pickups record who took the word"] = function(g)
    touch(g, "when")
    local p, t = g.players[1], tile(g, "close")
    p.x, p.y = t.x, t.y
    step(g, DT)
    local e = g.wordfield.events[1]
    assert(e and e.def.id == "close" and e.player == p, "event recorded")
    step(g, DT)
    assert(#g.wordfield.events == 0, "events last one frame")
end

-- Bot: P2 plays itself; P1 is IDLE unless a test says otherwise.
local function botStep(g, bot, seconds, p1)
    local n = math.floor(seconds / DT + 0.5)
    for _ = 1, n do g:update(DT, { p1 or IDLE, bot:update(DT, g) }) end
end

-- A bot with fixed "random" rolls. Human limits are off unless a test
-- passes its own profile, so rule tests don't wait on reaction times.
local function steadyBot(profile, roll)
    return Bot.new(2, function() return roll or 0.5 end, profile or { human = false })
end

tests["bot walks around a wall to a word it can use"] = function(g)
    local bot = steadyBot()
    local p = g.players[2]
    p.x, p.y = g.arena:tileCenter(12, 5) -- right of the central wall
    local wx, wy = g.arena:tileCenter(9, 5) -- left of it
    g.wordfield.words = { { def = g.data.words.byId.attack, x = wx, y = wy } }
    give(g, 2, "combo")
    botStep(g, bot, 3)
    assert(#g.wordfield.words == 0, "bot should have picked up the word")
    assert(g.spellbooks[2].template.spells[1].word == "attack")
end

tests["bot ignores words that don't fit"] = function(g)
    local bot = steadyBot()
    local p = g.players[2]
    local x0 = p.x
    g.wordfield.words = { { def = g.data.words.byId.close, x = p.x - 40, y = p.y } }
    give(g, 2, "combo")
    botStep(g, bot, 1)
    assert(#g.wordfield.words == 1 and math.abs(p.x - x0) < 1, "bot should stay put")
end

tests["bot dashes to win a word the enemy wants too"] = function(g)
    local bot = steadyBot()
    local p1, p2 = g.players[1], g.players[2]
    p1.x, p2.x = 190, 280
    g.wordfield.words = { { def = g.data.words.byId.attack, x = 240, y = p2.y } }
    give(g, 1, "combo"); give(g, 2, "combo")
    botStep(g, bot, 0.5)
    assert(#g.wordfield.words == 0 and g.spellbooks[2].template.spells[1].word == "attack", "bot should get the word")
    assert(p2.dashCooldown > 0, "bot should have dashed")
end

tests["bot only presses the 8 keyboard directions"] = function(g)
    local bot = steadyBot()
    local p = g.players[2]
    g.wordfield.words = { { def = g.data.words.byId.attack, x = p.x - 70, y = p.y + 37 } } -- awkward angle
    give(g, 2, "combo")
    for _ = 1, 120 do
        local input = bot:update(DT, g)
        for _, v in ipairs({ input.x, input.y }) do
            assert(v == -1 or v == 0 or v == 1, "analog input " .. tostring(v))
        end
        g:update(DT, { IDLE, input })
    end
end

tests["bot doesn't race-dash when no key direction lines up with the word"] = function(g)
    local bot = steadyBot()
    local p1, p2 = g.players[1], g.players[2]
    local _, y = g.arena:tileCenter(1, 3)
    p2.x, p2.y = 280, y
    p1.x, p1.y = 230, y - 25
    -- 35 px left, 20 px up: about 30 degrees, off both the row and the diagonal.
    g.wordfield.words = { { def = g.data.words.byId.attack, x = 245, y = y - 20 } }
    give(g, 1, "combo"); give(g, 2, "combo")
    botStep(g, bot, DT)
    assert(p2.dashCooldown == 0, "a keyboard dash would miss, so no dash yet")
end

tests["bot doesn't dash at a laser, it hides behind a wall"] = function(g)
    local bot = steadyBot()
    local p1, p2 = g.players[1], g.players[2]
    p1.x, p1.y = g.arena:tileCenter(2, 3)
    p2.x, p2.y = g.arena:tileCenter(13, 3)
    assert(g.arena:lineOfSight(p1.x, p1.y, p2.x, p2.y), "starts in the open")
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    botStep(g, bot, g.data.tuning.spells.telegraph + 0.1)
    assert(p2.hp == 10, "bot should take cover, hp " .. p2.hp)
    assert(p2.dashCooldown == 0, "bot shouldn't dash")
end

-- Human limits (they weaken the bot on purpose).
local function openRowDuel(g)
    local p1, p2 = g.players[1], g.players[2]
    p1.x, p1.y = g.arena:tileCenter(2, 3)
    p2.x, p2.y = g.arena:tileCenter(13, 3)
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    return p1, p2
end

tests["human limits: the bot reacts to an aim ray only after its reaction time"] = function(g)
    local bot = steadyBot({})
    local _, p2 = openRowDuel(g)
    local x0, y0 = p2.x, p2.y
    botStep(g, bot, g.data.tuning.bot.human.reactionTime - 0.1)
    assert(p2.x == x0 and p2.y == y0, "hasn't reacted yet")
    botStep(g, bot, 0.2)
    assert(p2.x ~= x0 or p2.y ~= y0, "now heading for cover")
end

tests["human limits: an aim ray the bot misses gets no reaction"] = function(g)
    local bot = steadyBot({}, 0.05) -- the roll lands under missChance
    local _, p2 = openRowDuel(g)
    botStep(g, bot, g.data.tuning.spells.telegraph + 0.1)
    assert(p2.hp == 8, "missed the aim ray, so both beams hit; hp " .. p2.hp)
end

tests["human limits: a word right next to the bot beats running for cover"] = function(g)
    local bot = steadyBot({ human = { readTime = 0 } })
    local _, p2 = openRowDuel(g)
    give(g, 2, "combo")
    g.wordfield.words = { { def = g.data.words.byId.attack, x = p2.x - 14, y = p2.y } }
    botStep(g, bot, 0.8)
    assert(#g.wordfield.words == 0, "went for the word first")
end

tests["human limits: a new word is ignored for the reading time"] = function(g)
    local bot = steadyBot({})
    local p = g.players[2]
    local x0 = p.x
    g.wordfield.words = { { def = g.data.words.byId.attack, x = p.x - 40, y = p.y } }
    give(g, 2, "combo")
    botStep(g, bot, g.data.tuning.bot.human.readTime - 0.1)
    assert(p.x == x0, "still reading")
    botStep(g, bot, 1.5)
    assert(#g.wordfield.words == 0, "then picks it up")
end

tests["bot walks up to the enemy with a close trap armed"] = function(g)
    local bot = steadyBot()
    g.spellbooks[2].trap = { conditions = { "close" }, spells = { "shield" }, n = 1, recharge = 0 }
    botStep(g, bot, 4)
    assert(g.players[2].shield >= 1, "trap should have fired")
end

tests["bot vs bot plays a full round"] = function(g)
    local b1, b2 = Bot.new(1, math.random), Bot.new(2, math.random)
    g.wordfield:start(g.data.tuning)
    local picked = 0
    for _ = 1, math.floor(180 / DT) do
        g:update(DT, { b1:update(DT, g), b2:update(DT, g) })
        picked = picked + #g.wordfield.events
        if g.state == "over" then break end
    end
    local p1, p2 = g.players[1], g.players[2]
    print(string.format("      bot vs bot: %d words, hp %d / %d, %s", picked, p1.hp, p2.hp,
        g.state == "over" and ("winner " .. tostring(g.winner)) or "no winner in 180 s"))
    assert(picked >= 10, "bots should be collecting words, got " .. picked)
    assert(p1.hp + p2.hp < 20, "someone should have been hit")
end

-- Stats hooks (used by the simulation).
tests["events: a finished template's beams and blocks are tagged with it"] = function(g)
    local log = {}
    g.onEvent = function(e) log[#log + 1] = e end
    g.players[2].shield = 0
    give(g, 2, "repeat", 2); fill(g, 2, "shield") -- P2's shields come from this effect
    local shieldEffect = g.spellbooks[2].effect
    give(g, 1, "combo"); fill(g, 1, "attack", "attack")
    local attackEffect = g.spellbooks[1].effect
    assert(attackEffect and attackEffect.kinds[1] == "combo" and attackEffect.words == 2)
    fire(g)
    local blocked = 0
    for _, e in ipairs(log) do
        if e.type == "laser" then
            assert(e.source.effect == attackEffect, "beam tagged with its template")
            if e.result == "blocked" then
                blocked = blocked + 1
                assert(e.blocker == shieldEffect, "block credited to the shield's template")
            end
        end
    end
    assert(blocked == 2, "both beams blocked, got " .. blocked)
end

tests["events: stacked templates remember their kinds; traps report their trigger"] = function(g)
    local t = g.data.tuning
    local log = {}
    g.onEvent = function(e) log[#log + 1] = e end
    g.spellbooks[1].template = Spellbook.merge(template(g, "when"), template(g, "repeat", 2), t)
    assert(table.concat(g.spellbooks[1].template.kinds, "+") == "when+repeat")
    fill(g, 1, "dash", "attack", "attack")
    step(g, DT, { { x = 1, y = 0, dash = true }, IDLE })
    local fired
    for _, e in ipairs(log) do if e.type == "trapFired" then fired = e end end
    assert(fired and fired.trigger == "dash", "trap fired by dash")
    step(g, t.spells.telegraph + 0.1)
    for _, l in ipairs(g.lasers) do assert(l.source.trigger == "dash") end
end

tests["sim: a short bot vs bot batch runs and reports"] = function(g)
    local Sim = require("src.sim")
    local lines = {}
    local S = Sim.run(g.data, { rounds = 2, cap = 90, seed = 7, out = function(s) lines[#lines + 1] = s end })
    assert(#S.rounds == 2, "two rounds")
    assert(#S.templates > 0, "templates recorded")
    local L = S.lasers
    local tagged = 0
    for _, tr in pairs(S.traps) do tagged = tagged + tr.beams end
    assert(tagged == L.hit + L.blocked + L.dodged + L.wall, "every beam is credited to a template")
    assert(#lines > 10, "report printed")
end

tests["sim: reading load counts template words, blanks included"] = function(g)
    local t = g.data.tuning
    assert(Spellbook.wordCount(template(g, "when")) == 4, "when ___, cast ___")
    assert(Spellbook.wordCount(template(g, "combo")) == 4, "cast ___ and ___")
    assert(Spellbook.wordCount(template(g, "repeat", 3)) == 4, "repeat 3: cast ___")
    local big = Spellbook.merge(template(g, "when"), template(g, "combo"), t)
    assert(Spellbook.wordCount(big) == 7, "when ___, cast ___, ___ and ___: " .. Spellbook.wordCount(big))
    local R = require("src.sim").playRound(g.data, 1, { seed = 7, cap = 30 })
    assert(R.load.time > 0 and R.load.template > 0 and #R.load.samples > 0, "load sampled")
end

tests["sim: a round record survives encoding (worker threads send them as text)"] = function(g)
    local Sim = require("src.sim")
    local R = Sim.playRound(g.data, 3, { seed = 7, cap = 60 })
    local back = Sim.decode(Sim.encode(R))
    assert(back.round == 3 and back.length == R.length and back.winner == R.winner)
    assert(#back.templates == #R.templates and #back.waves.gaps == #R.waves.gaps)
    for k, tr in pairs(R.traps) do assert(back.traps[k].beams == tr.beams) end
    local S = Sim.finish({ back, R }, { cap = 60, out = function() end })
    assert(#S.rounds == 2 and #S.templates == 2 * #R.templates, "records merge")
end

-- Sample scene for `--shot` screenshots: stacked templates, shields, a trap.
function SelfTest.showcase(g)
    local t = g.data.tuning
    local b1, b2 = g.spellbooks[1], g.spellbooks[2]
    b1.template = Spellbook.merge(Spellbook.merge(template(g, "when"), template(g, "combo"), t), template(g, "repeat", 3), t)
    b1.template.conditions[1].word = "close"
    b1.template.spells[2].word = "attack"
    -- A long level-3 template above a trap row.
    b2.template = Spellbook.merge(Spellbook.merge(template(g, "when"), template(g, "when"), t), template(g, "combo"), t)
    b2.template.conditions[1].word, b2.template.conditions[2].word = "close", "still"
    b2.template.spells[1].word, b2.template.spells[2].word = "shield", "accelerate"
    b2.trap = { conditions = { "dash" }, spells = { "shield" }, n = 1, recharge = 0 }
    g.players[2].shield = 9
    g.players[1].accelerate = 2
    g.players[1].dashCooldown = t.dash.cooldown * 0.4
    g.players[1].dashTime, g.players[1].dashX, g.players[1].dashY = 0.1, 1, 0 -- exercises dust puffs
    -- Widest possible trap text (level 3), half recharged.
    b1.trap = { conditions = { "close", "still", "dash" }, spells = { "attack", "shield", "accelerate" }, n = 1, recharge = 0.4 }
    b1.template.timeLeft = 1.5 -- P1's effects are about to expire: exercises the blink
    local _, y = g.arena:tileCenter(1, 3) -- open row, clear line of sight
    g.players[1].y, g.players[2].y = y, y
    for _ = 1, 3 do g:castSpell(g.players[1], "attack") end
end

-- Sample scene for `--shot-training`: a stacked template, the player inside
-- the dummy's range (so it starts firing), and a pickup in flight.
-- --shot-parry: the wizard's beam lands on the Bulwark's raised shield
-- right after the fight starts (the screenshot catches the burst).
function SelfTest.showcaseParry(g)
    local m, w = g.players[1], g.players[2]
    local _, y = g.arena:tileCenter(1, 3)
    m.x, m.y, w.x, w.y = 120, y, 220, y
    g:castSpell(w, "attack")
    g.lasers[#g.lasers].timer = 0.02
    m:startParry(g.data.tuning)
end

function SelfTest.showcaseTraining(g)
    local t = g.data.tuning
    local book, p, d = g.spellbooks[1], g.players[1], g.players[2]
    book:take(tile(g, "when").def, t, math.random)
    book:take(tile(g, "repeat").def, t, math.random)
    book:take(tile(g, "close").def, t, math.random)
    tile(g, "when") -- back to the templates tab: step 1 with the stack count
    p.x, p.y = d.x - 40, d.y + 26
    local w
    for _, tl in ipairs(g.wordfield.words) do if tl.def.label == "when" then w = tl end end
    g.wordfield.events = { { def = w.def, x = p.x - 30, y = p.y - 10, player = p } }
end

---------------------------------------------------------------- Bulwark

local PARRY = { x = 0, y = 0, dash = true }

-- P1 Bulwark vs P2 wizard, on the open row as usual.
local function mageFight(g)
    return newFight(g.data, { "shieldmage", "wizard" })
end

-- Fire one wizard beam at the mage and press parry `early` seconds before
-- it lands. Returns the beam's result.
local function parryAt(g, early)
    local results = {}
    g.onEvent = function(e) if e.type == "laser" then results[#results + 1] = e.result end end
    g:castSpell(g.players[2], "attack")
    step(g, g.data.tuning.spells.telegraph - early)
    step(g, DT, { PARRY, IDLE })
    step(g, early + 0.1)
    g.onEvent = nil
    return results[1]
end

tests["mage: starts with its own HP (fewer than the wizard)"] = function(g)
    g = mageFight(g)
    local t = g.data.tuning
    assert(g.players[1].hp == t.characters.shieldmage.hp and g.players[1].hp < t.player.hp, "mage hp " .. g.players[1].hp)
    assert(g.players[2].hp == t.player.hp, "wizard hp " .. g.players[2].hp)
    assert(g.players[1]:maxHp(t) == t.characters.shieldmage.hp, "max hp")
end

tests["mage: walks as fast as the wizard"] = function(g)
    g = mageFight(g)
    local m, w = g.players[1], g.players[2]
    local mx, wx = m.x, w.x
    step(g, 0.5, { { x = 1, y = 0, dash = false }, { x = -1, y = 0, dash = false } })
    local mageGone, wizGone = m.x - mx, wx - w.x
    assert(math.abs(mageGone - wizGone) < 0.01, string.format("mage %.1f px vs wizard %.1f px", mageGone, wizGone))
end

-- Lasting, decaying shields: an optional per-character rule (shieldLasts +
-- shieldDecay), tried on the mage and the wizard and switched off for both
-- (docs/SIMULATION.md results log, 2026-11-04). Kept working for experiments.
tests["option: lasting shield charges decay one at a time, faster the more you hold"] = function(g)
    local rules = g.data.tuning.characters.shieldmage
    local decay = 40
    rules.shieldLasts, rules.shieldDecay = true, decay
    local ok, err = pcall(function()
        local f = mageFight(g)
        local m = f.players[1]
        give(f, 1, "combo"); fill(f, 1, "shield", "shield")
        give(f, 1, "combo"); fill(f, 1, "accelerate", "accelerate") -- ends the shield's window
        assert(m.shield == 2, "charges outlast the window, got " .. m.shield)
        m.decayProgress = 0 -- 2 charges: next goes after decay / 2 seconds
        step(f, decay / 2 - 0.5)
        assert(m.shield == 2, "2 charges hold for a while, got " .. m.shield)
        step(f, 1)
        assert(m.shield == 1, "then one decays, got " .. m.shield)
        m.shield, m.decayProgress = 10, 0 -- 10 charges: one every decay / 10 seconds
        step(f, decay / 10 + 0.1)
        assert(m.shield == 9, "a big stack melts fast, got " .. m.shield)
        assert(math.abs(m:shieldDecayLeft(f.data.tuning) - decay / 9) < 0.2, "next one at the new rate")
    end)
    rules.shieldLasts, rules.shieldDecay = nil, nil
    assert(ok, err)
end

tests["mage: shield charges end with the effect window, like the wizard's"] = function(g)
    g = mageFight(g)
    give(g, 1, "combo"); fill(g, 1, "shield", "shield")
    assert(g.players[1].shield == 2, "2 charges")
    give(g, 1, "combo"); fill(g, 1, "accelerate", "accelerate") -- ends the shield's window
    assert(g.players[1].shield == 0, "charges should end with the window, got " .. g.players[1].shield)
end

tests["mage: a parry in time stops the beam, keeps the shield, and clears the cooldown"] = function(g)
    g = mageFight(g)
    local m = g.players[1]
    m.shield = 1
    local result = parryAt(g, 0.1)
    assert(result == "parried", "expected a parry, got " .. tostring(result))
    assert(m.hp == m:maxHp(g.data.tuning) and m.shield == 1, "no damage and no charge used")
    assert(m.dashCooldown == 0, "a successful parry has no cooldown")
end

tests["mage: the parry window is a bit longer than a dash, not much"] = function(g)
    local t = g.data.tuning
    local win = t.characters.shieldmage.parry.window
    assert(win > t.dash.duration and win <= t.dash.duration * 2,
        string.format("window %.2f s vs dash %.2f s", win, t.dash.duration))
    g = mageFight(g)
    assert(parryAt(g, win - 0.03) == "parried", "late in the window should still parry")
end

tests["mage: a parry too early misses and keeps the cooldown"] = function(g)
    g = mageFight(g)
    local m, p = g.players[1], g.data.tuning.characters.shieldmage.parry
    local result = parryAt(g, p.window + 0.15)
    assert(result == "hit" and m.hp == m:maxHp(g.data.tuning) - 1, "an early parry should miss, got " .. tostring(result))
    assert(m.dashCooldown > 0, "a missed parry keeps its cooldown")
end

tests["mage: one parry stops a whole volley"] = function(g)
    g = mageFight(g)
    local w, m = g.players[2], g.players[1]
    give(g, 2, "combo"); fill(g, 2, "attack", "attack")
    step(g, g.data.tuning.spells.telegraph - 0.1)
    step(g, DT, { PARRY, IDLE })
    step(g, 0.2)
    assert(m.hp == m:maxHp(g.data.tuning), "both beams should be parried, hp " .. m.hp)
end

tests["option: a successful parry gives shieldOnParry charges, once per press"] = function(g)
    local p = g.data.tuning.characters.shieldmage.parry
    local old = p.shieldOnParry
    p.shieldOnParry = 1
    local ok, err = pcall(function()
        local f = mageFight(g)
        local m = f.players[1]
        give(f, 2, "combo"); fill(f, 2, "attack", "attack") -- a volley of 2, one press
        step(f, f.data.tuning.spells.telegraph - 0.1)
        step(f, DT, { PARRY, IDLE })
        step(f, 0.2)
        assert(m.hp == m:maxHp(f.data.tuning), "both parried")
        assert(m.shield == 1, "one charge per parry press, got " .. m.shield)
    end)
    p.shieldOnParry = old
    assert(ok, err)
end

tests["option: a successful parry heals healOnParry HP, once per press, up to full"] = function(g)
    local p = g.data.tuning.characters.shieldmage.parry
    local old = p.healOnParry
    p.healOnParry = 1
    local ok, err = pcall(function()
        local f = mageFight(g)
        local m = f.players[1]
        local full = m:maxHp(f.data.tuning)
        m.hp = full - 2
        give(f, 2, "combo"); fill(f, 2, "attack", "attack") -- a volley of 2, one press
        step(f, f.data.tuning.spells.telegraph - 0.1)
        step(f, DT, { PARRY, IDLE })
        step(f, 0.2)
        assert(m.hp == full - 1, "one HP per parry press, got " .. m.hp)
        m.hp = full
        assert(parryAt(f, 0.1) == "parried" and m.hp == full, "never above full HP")
    end)
    p.healOnParry = old
    assert(ok, err)
end

tests["mage: a 'dash' trap fires when the mage parries"] = function(g)
    g = mageFight(g)
    local fired = 0
    g.onEvent = function(e) if e.type == "trapFired" and e.trigger == "dash" then fired = fired + 1 end end
    give(g, 1, "when"); fill(g, 1, "dash", "shield")
    step(g, DT, { PARRY, IDLE })
    assert(fired == 1, "the parry should set off the trap")
end

tests["mage bot: parries a beam just before it lands"] = function(g)
    g = mageFight(g)
    g:castSpell(g.players[2], "attack")
    local bot = Bot.new(1, math.random, { human = false })
    assert(not bot:update(DT, g).dash, "too early to parry")
    local lead = g.data.tuning.bot.parryLead
    step(g, g.data.tuning.spells.telegraph - lead + 0.02)
    assert(bot:update(DT, g).dash, "should parry now")
end

tests["mage bot: parry timing has human error, about 80% in the window"] = function(g)
    local t = g.data.tuning
    local ok, n = 0, 400
    local n2, tally = n, {}
    for _ = 1, n do
        local f = mageFight(g)
        local bot = Bot.new(1, math.random, { human = { missChance = 0 } })
        f:castSpell(f.players[2], "attack")
        local result
        f.onEvent = function(e) if e.type == "laser" then result = e.result end end
        for _ = 1, math.ceil((t.spells.telegraph + 0.5) / DT) do
            f:update(DT, { bot:update(DT, f), IDLE })
        end
        if result == "parried" then ok = ok + 1 end
        if result == "wall" or result == nil then n2 = n2 - 1 end
        tally[tostring(result)] = (tally[tostring(result)] or 0) + 1
    end
    local rate = ok / n2
    local parts = {}
    for k, v in pairs(tally) do parts[#parts + 1] = k .. " " .. v end
    assert(rate > 0.65 and rate < 0.92, string.format("parry rate %.0f%% (%s)", rate * 100, table.concat(parts, ", ")))
end

tests["mage vs wizard bots play a full round"] = function(g)
    g = newFight(g.data, { "shieldmage", "wizard" })
    g.wordfield.enabled = true
    local bots = { Bot.new(1, math.random), Bot.new(2, math.random) }
    local parried = 0
    g.onEvent = function(e) if e.type == "laser" and e.result == "parried" then parried = parried + 1 end end
    for _ = 1, 60 * 180 do
        g:update(DT, { bots[1]:update(DT, g), bots[2]:update(DT, g) })
        if g.state == "over" then break end
    end
    print(string.format("      mage vs wizard: hp %d / %d, %d parries, winner %s",
        g.players[1].hp, g.players[2].hp, parried, tostring(g.winner or "none in 180 s")))
    assert(parried > 0, "the mage bot should parry at least once")
end

---------------------------------------------------------------- character select

local selectTests = {}

local function newSelect(data)
    return Select.new(data.characters.list), data
end

local function confirmBoth(sel)
    sel:press(1, "confirm"); sel:press(2, "confirm")
    sel:update(Select.START_DELAY + 0.01)
end

selectTests["select: both confirm, match starts after the delay"] = function(sel)
    sel:press(1, "confirm"); sel:press(2, "confirm")
    sel:update(Select.START_DELAY / 2)
    assert(not sel.result, "should wait for the start delay")
    sel:update(Select.START_DELAY)
    assert(sel.result, "match should start")
    assert(sel.result.characters[1] == "wizard" and sel.result.control[2] == "human", "default setup")
end

selectTests["select: a character that isn't built can't be confirmed"] = function(_, data)
    local list = { data.characters.list[1], { id = "later", name = "Later", available = false, lines = {} } }
    local sel = Select.new(list)
    sel:press(1, "right")
    assert(not sel:character(1).available, "second character should be locked")
    sel:press(1, "confirm")
    assert(not sel.panels[1].ready and sel.panels[1].refused > 0, "confirm should be refused")
    sel:press(1, "left"); sel:press(1, "confirm")
    assert(sel.panels[1].ready, "wizard should confirm")
end

selectTests["select: once confirmed, your keys set up the other side"] = function(sel)
    sel:press(1, "confirm")
    assert(sel:panelFor(1) == 2, "P1 should now drive P2's panel")
    sel:press(1, "up"); sel:press(1, "right") -- control row: human -> AI
    sel:press(1, "confirm")
    sel:update(Select.START_DELAY + 0.01)
    assert(sel.result and sel.result.control[1] == "human" and sel.result.control[2] == "ai",
        "P2 should be set to AI by P1")
end

selectTests["select: esc un-confirms both panels"] = function(sel)
    sel:press(1, "confirm"); sel:press(2, "confirm")
    sel:reset()
    assert(not sel:anyReady(), "both should be un-confirmed")
    sel:update(Select.START_DELAY + 0.01)
    assert(not sel.result, "match shouldn't start after a reset")
    sel:reset() -- nothing confirmed: does nothing
    assert(not sel:anyReady(), "still nothing confirmed")
end

selectTests["select: remembers the last setup"] = function(_, data)
    local sel = Select.new(data.characters.list, { characters = { "wizard", "shieldmage" }, control = { "ai", "human" } })
    assert(sel:character(2).id == "shieldmage" and sel.panels[1].control == "ai", "setup should carry over")
    assert(not sel.panels[1].ready and not sel.panels[2].ready, "nothing confirmed")
end

selectTests["select: the chosen characters reach the players"] = function(sel, data)
    confirmBoth(sel)
    local g = Game.new(data, { width = W, height = H, rand = math.random, characters = sel.result.characters })
    assert(g.players[1].character == "wizard" and g.players[2].sprite == "wizard_red", "players should use the picks")
end

function SelfTest.run(data)
    local suites = { { tests, newFight }, { trainingTests, newTraining }, { selectTests, newSelect } }
    local total, failed = 0, 0
    for _, suite in ipairs(suites) do
        local list, make = suite[1], suite[2]
        local names = {}
        for name in pairs(list) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local ok, err = pcall(list[name], make(data))
            print((ok and "PASS  " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(err))))
            total = total + 1
            if not ok then failed = failed + 1 end
        end
    end
    print(string.format("%d/%d passed", total - failed, total))
    return failed == 0
end

return SelfTest
