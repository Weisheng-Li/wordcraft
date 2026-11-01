-- Headless rules check: `lovec . --selftest`. Drives Game with scripted
-- inputs and checks the rules from docs/DESIGN.md. Prints PASS/FAIL lines.

local Bot = require("src.bot")
local Game = require("src.game")
local Spellbook = require("src.spellbook")

local SelfTest = {}

local W, H = 320, 180
local DT = 1 / 60
local IDLE = { x = 0, y = 0, dash = false }

local function newFight(data)
    local g = Game.new(data, { width = W, height = H, rand = math.random })
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

tests["when hit -> shield fires after taking damage"] = function(g)
    give(g, 2, "when"); fill(g, 2, "hit", "shield")
    assert(g.spellbooks[2].trap, "trap armed")
    give(g, 1, "combo"); fill(g, 1, "attack", "shield")
    fire(g)
    assert(g.players[2].hp == 9 and g.players[2].shield == 1 and not g.spellbooks[2].trap)
end

tests["when close fires immediately if already true"] = function(g)
    g.players[2].x = g.players[1].x + 30 -- already close
    give(g, 1, "when"); fill(g, 1, "close", "attack")
    assert(not g.spellbooks[1].trap, "should fire on arming")
    fire(g)
    assert(g.players[2].hp == 9)
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

tests["'I get hit' fires on a shield block, not on a dodge"] = function(g)
    local p2 = g.players[2]
    give(g, 2, "when"); fill(g, 2, "hit", "accelerate")
    p2.shield = 1 -- after arming, which clears earlier effects
    give(g, 1, "combo"); fill(g, 1, "attack", "shield")
    fire(g)
    assert(p2.hp == 10 and p2.shield == 0, "blocked")
    assert(not g.spellbooks[2].trap and p2.accelerate == 1, "trap fired on the block")

    give(g, 2, "when"); fill(g, 2, "hit", "accelerate")
    give(g, 1, "combo"); fill(g, 1, "attack", "shield")
    step(g, g.data.tuning.spells.telegraph - 0.05)
    step(g, 0.1, { IDLE, { x = 0, y = 1, dash = true } })
    assert(g.spellbooks[2].trap, "a dodge doesn't count as a hit")
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

-- A bot with fixed "random" rolls.
local function steadyBot()
    return Bot.new(2, function() return 0.5 end)
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

tests["bot walks up to the enemy with a close trap armed"] = function(g)
    local bot = steadyBot()
    g.spellbooks[2].trap = { conditions = { "close" }, spells = { "shield" }, n = 1 }
    botStep(g, bot, 4)
    assert(g.spellbooks[2].trap == nil and g.players[2].shield == 1, "trap should have fired")
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
    b2.trap = { conditions = { "hit" }, spells = { "shield" }, n = 1, recharge = 0 }
    g.players[2].shield = 9
    g.players[1].accelerate = 2
    g.players[1].dashCooldown = t.dash.cooldown * 0.4
    g.players[1].dashTime, g.players[1].dashX, g.players[1].dashY = 0.1, 1, 0 -- exercises dust puffs
    -- Widest possible trap text (level 3), half recharged.
    b1.trap = { conditions = { "close", "still", "dash" }, spells = { "attack", "shield", "accelerate" }, n = 1, recharge = 1 }
    b1.template.timeLeft = 1.5 -- P1's effects are about to expire: exercises the blink
    local _, y = g.arena:tileCenter(1, 3) -- open row, clear line of sight
    g.players[1].y, g.players[2].y = y, y
    for _ = 1, 3 do g:castSpell(g.players[1], "attack") end
end

-- Sample scene for `--shot-training`: a stacked template, the player inside
-- the dummy's range (so it starts firing), and a pickup in flight.
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

function SelfTest.run(data)
    local suites = { { tests, newFight }, { trainingTests, newTraining } }
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
