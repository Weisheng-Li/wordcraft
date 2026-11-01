-- Simulation: bot vs bot rounds with no window, much faster than real
-- time, then balance metrics (DESIGN §15). Pure logic: the caller passes
-- `print` and a `write(path, text)` for the CSV.
--
--   lovec . --sim 500 [--seed 1] [--p1 profile] [--p2 profile]
--
-- Metrics:
--   1. Rounds: length, win rate.
--   2. Finished templates by shape (and summed by level): completed vs
--      timed out, words, effect window length, current return (damage
--      dealt + hits its shields blocked) and future return (my share of
--      pickups while the effect window is open). A trap's window opens
--      when it's armed.
--   3. Traps: beam hit rate per triggering condition vs plain casts.
--   4. Word spawning: time between waves, early waves, one-sided boards
--      (only one player can use anything on the floor).
--   5. Combat: laser results, shield charges, accelerate.

local Bot = require("src.bot")
local Game = require("src.game")

local Sim = {}

local W, H = 320, 180
local DT = 1 / 60

local function shapeOf(kinds)
    local list = {}
    for i, k in ipairs(kinds) do list[i] = k end
    table.sort(list)
    return table.concat(list, "+")
end

local function newStats()
    return {
        rounds = {},     -- { length, winner }
        templates = {},  -- CSV rows: one per finished or timed-out template
        traps = {},      -- trigger -> { beams, hit, blocked, dodged, wall }
        lasers = { hit = 0, blocked = 0, dodged = 0, wall = 0 },
        shield = { gained = 0, used = 0, expired = 0 },
        accel = { gained = 0, time = 0, stackTime = 0, picksFast = 0, picksNormal = 0, playerTime = 0 },
        waves = { count = 0, early = 0, leftovers = 0, gaps = {} },
        oneSided = { time = 0, fightTime = 0, stretches = {} },
    }
end

-- Play one round; add what happened to `S`.
local function playRound(data, S, roundNo, opts)
    local profiles = data.tuning.botProfiles or {}
    local g = Game.new(data, { width = W, height = H, rand = math.random })
    local bots = {
        Bot.new(1, math.random, profiles[opts.p1]),
        Bot.new(2, math.random, profiles[opts.p2]),
    }

    local open = {}      -- effect -> template row while its window is open
    local rowOf = {}     -- effect -> row (also after closing, for late beams)
    local lastWave       -- time of the previous wave landing
    local frame = {}     -- what happened this frame (for one-sided board endings)
    local stretch        -- current one-sided board stretch

    local function closeWindow(effect, t)
        local row = open[effect]
        if row then
            row.window = t - row.start
            open[effect] = nil
        end
    end

    g.onEvent = function(e)
        if e.type == "complete" then
            local row = {
                round = roundNo, player = e.player.id, shape = shapeOf(e.effect.kinds),
                level = e.effect.level, words = e.effect.words, result = e.effect.trap and "trap" or "cast",
                start = e.time, window = 0, damage = 0, blocked = 0, mine = 0, theirs = 0, fired = 0,
            }
            S.templates[#S.templates + 1] = row
            open[e.effect], rowOf[e.effect] = row, row
        elseif e.type == "timeout" then
            S.templates[#S.templates + 1] = {
                round = roundNo, player = e.player.id, shape = shapeOf(e.kinds), level = e.level,
                words = 0, result = "timeout", start = e.time, window = 0,
                damage = 0, blocked = 0, mine = 0, theirs = 0, fired = 0,
            }
        elseif e.type == "effectEnd" then
            closeWindow(e.effect, e.time)
            S.shield.expired = S.shield.expired + e.shieldLeft
        elseif e.type == "trapFired" then
            local row = rowOf[e.effect]
            if row then row.fired = row.fired + 1 end
        elseif e.type == "pickup" then
            frame.pickup = frame.pickup or {}
            frame.pickup[e.player.id] = true
            for _, row in pairs(open) do
                if row.player == e.player.id then row.mine = row.mine + 1 else row.theirs = row.theirs + 1 end
            end
            if e.player.accelerate > 0 then
                S.accel.picksFast = S.accel.picksFast + 1
            else
                S.accel.picksNormal = S.accel.picksNormal + 1
            end
        elseif e.type == "spell" then
            if e.spell == "shield" then S.shield.gained = S.shield.gained + 1 end
            if e.spell == "accelerate" then S.accel.gained = S.accel.gained + 1 end
        elseif e.type == "laser" then
            local r = e.result
            S.lasers[r] = S.lasers[r] + 1
            local src = e.source
            if src and src.effect then
                local row = rowOf[src.effect]
                if row and r == "hit" then row.damage = row.damage + 1 end
                local key = src.trigger or "plain cast"
                local tr = S.traps[key] or { beams = 0, hit = 0, blocked = 0, dodged = 0, wall = 0 }
                S.traps[key] = tr
                tr.beams = tr.beams + 1
                tr[r] = tr[r] + 1
            end
            if r == "blocked" then
                S.shield.used = S.shield.used + 1
                local row = e.blocker and rowOf[e.blocker]
                if row then row.blocked = row.blocked + 1 end
            end
        elseif e.type == "wave" then
            frame.wave = true
            local w = S.waves
            w.count = w.count + 1
            if e.early then w.early = w.early + 1 end
            w.leftovers = w.leftovers + e.leftovers
            if lastWave then w.gaps[#w.gaps + 1] = e.time - lastWave end
            lastWave = e.time
        end
    end

    -- One-sided board: words on the floor, both players hold a template,
    -- and exactly one of them can use something there.
    local function boardSide()
        local books = g.spellbooks
        if not (books[1].template and books[2].template) or #g.wordfield.words == 0 then return nil end
        local usable = { false, false }
        local hasType = {}
        for _, w in ipairs(g.wordfield.words) do
            hasType[w.def.type] = true
            for k = 1, 2 do
                if books[k]:canAccept(w.def) then usable[k] = true end
            end
        end
        if usable[1] == usable[2] then return nil end
        local mix = (hasType.spell and hasType.condition) and "mixed"
            or (hasType.condition and "condition only" or "spell only")
        return usable[1] and 1 or 2, mix
    end

    local function endStretch(reason)
        stretch.length = g.clock - stretch.start
        stretch.ended = reason
        S.oneSided.stretches[#S.oneSided.stretches + 1] = stretch
        stretch = nil
    end

    local cap = opts.cap
    while g.state ~= "over" and g.clock < cap do
        frame = {}
        local inputs = { bots[1]:update(DT, g), bots[2]:update(DT, g) }
        g:update(DT, inputs)
        if g.state == "fight" or g.state == "over" then
            for _, p in ipairs(g.players) do
                if p.accelerate > 0 then
                    S.accel.time = S.accel.time + DT
                    S.accel.stackTime = S.accel.stackTime + DT * p.accelerate
                end
            end
            S.accel.playerTime = S.accel.playerTime + 2 * DT
            S.oneSided.fightTime = S.oneSided.fightTime + DT

            local side, mix = boardSide()
            if stretch and side ~= stretch.side then
                local reason = frame.wave and "wave"
                    or (frame.pickup and frame.pickup[stretch.side]) and "pickup"
                    or "other"
                endStretch(reason)
            end
            if side and not stretch then stretch = { side = side, mix = mix, start = g.clock } end
            if side then S.oneSided.time = S.oneSided.time + DT end
        end
    end
    if stretch then endStretch("round end") end
    for effect in pairs(open) do closeWindow(effect, g.clock) end

    S.rounds[#S.rounds + 1] = {
        length = g.clock,
        winner = g.state == "over" and tostring(g.winner) or "cap",
    }
end

-- Formatting helpers.
local function pct(a, b) return b > 0 and string.format("%5.1f%%", 100 * a / b) or "    -" end
local function avg(a, b) return b > 0 and a / b or 0 end

local function quantile(list, q)
    if #list == 0 then return 0 end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    table.sort(s)
    return s[math.max(1, math.ceil(q * #s))]
end

-- Sum template rows into groups by `keyOf(row)`.
local function groupTemplates(rows, keyOf)
    local groups, order = {}, {}
    for _, r in ipairs(rows) do
        local key = keyOf(r)
        local gr = groups[key]
        if not gr then
            gr = { key = key, level = r.level, done = 0, timeout = 0, words = 0, window = 0,
                   damage = 0, blocked = 0, mine = 0, theirs = 0 }
            groups[key] = gr
            order[#order + 1] = gr
        end
        if r.result == "timeout" then
            gr.timeout = gr.timeout + 1
        else
            gr.done = gr.done + 1
            gr.words = gr.words + r.words
            gr.window = gr.window + r.window
            gr.damage = gr.damage + r.damage
            gr.blocked = gr.blocked + r.blocked
            gr.mine = gr.mine + r.mine
            gr.theirs = gr.theirs + r.theirs
        end
    end
    table.sort(order, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.done + a.timeout > b.done + b.timeout
    end)
    return order
end

local function templateTable(out, title, order)
    out(title)
    out(string.format("  %-22s %6s %7s %6s %7s %7s %7s %8s %7s",
        "", "done", "t/out", "words", "window", "dmg", "blocked", "ret/word", "picks"))
    for _, gr in ipairs(order) do
        local n = gr.done
        out(string.format("  %-22s %6d %7s %6.1f %6.1fs %7.2f %7.2f %8.2f %7s",
            gr.key, n, pct(gr.timeout, n + gr.timeout), avg(gr.words, n), avg(gr.window, n),
            avg(gr.damage, n), avg(gr.blocked, n), avg(gr.damage + gr.blocked, gr.words),
            pct(gr.mine, gr.mine + gr.theirs)))
    end
end

local function report(S, opts, out)
    local n = #S.rounds
    out("")
    out(string.format("=== Simulation: %d rounds, seed %d, P1 %s vs P2 %s, cap %ds ===",
        n, opts.seed, opts.p1 or "default", opts.p2 or "default", opts.cap))

    -- 1. Rounds
    local lengths, wins = {}, {}
    for i, r in ipairs(S.rounds) do
        lengths[i] = r.length
        wins[r.winner] = (wins[r.winner] or 0) + 1
    end
    local total = 0
    for _, l in ipairs(lengths) do total = total + l end
    out("")
    out("1. Rounds")
    out(string.format("  length: avg %.0fs, median %.0fs, 10%% %.0fs, 90%% %.0fs",
        avg(total, n), quantile(lengths, 0.5), quantile(lengths, 0.1), quantile(lengths, 0.9)))
    out(string.format("  winner: P1 %s  P2 %s  draw %s  no winner by cap %s",
        pct(wins["1"] or 0, n), pct(wins["2"] or 0, n), pct(wins.draw or 0, n), pct(wins.cap or 0, n)))

    -- 2. Templates
    out("")
    out("2. Finished templates  (dmg/blocked per cast; ret/word = (dmg+blocked)/word;")
    out("   picks = my share of all pickups while the effect window is open)")
    templateTable(out, "  by shape:", groupTemplates(S.templates, function(r) return r.shape end))
    templateTable(out, "  by level:", groupTemplates(S.templates, function(r) return "level " .. r.level end))
    local all = groupTemplates(S.templates, function() return "all" end)
    templateTable(out, "  overall:", all)

    -- 3. Traps
    out("")
    out("3. Beam hit rate by what fired it")
    out(string.format("  %-14s %6s %7s %8s %7s %7s", "", "beams", "hit", "blocked", "dodged", "wall"))
    local keys = {}
    for k in pairs(S.traps) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return S.traps[a].beams > S.traps[b].beams end)
    for _, k in ipairs(keys) do
        local tr = S.traps[k]
        out(string.format("  %-14s %6d %7s %8s %7s %7s", k, tr.beams, pct(tr.hit, tr.beams),
            pct(tr.blocked, tr.beams), pct(tr.dodged, tr.beams), pct(tr.wall, tr.beams)))
    end

    -- 4. Words
    local w = S.waves
    local gapSum = 0
    for _, v in ipairs(w.gaps) do gapSum = gapSum + v end
    out("")
    out("4. Word spawning")
    out(string.format("  waves: %d, gap avg %.1fs (10%% %.1fs, 90%% %.1fs), pulled early (dead board) %s, leftovers/wave %.1f",
        w.count, avg(gapSum, #w.gaps), quantile(w.gaps, 0.1), quantile(w.gaps, 0.9),
        pct(w.early, w.count), avg(w.leftovers, w.count)))
    local o = S.oneSided
    local lens, ends, mixes = {}, {}, {}
    for i, s in ipairs(o.stretches) do
        lens[i] = s.length
        ends[s.ended] = (ends[s.ended] or 0) + 1
        mixes[s.mix] = (mixes[s.mix] or 0) + 1
    end
    local ns = #o.stretches
    out(string.format("  one-sided board: %s of fight time, %d stretches, length avg %.1fs (90%% %.1fs)",
        pct(o.time, o.fightTime), ns, avg(o.time, ns), quantile(lens, 0.9)))
    out(string.format("    ended by: pickup %s, next wave %s, other %s, round end %s",
        pct(ends.pickup or 0, ns), pct(ends.wave or 0, ns), pct(ends.other or 0, ns), pct(ends["round end"] or 0, ns)))
    out(string.format("    floor had: condition only %s, spell only %s, mixed %s",
        pct(mixes["condition only"] or 0, ns), pct(mixes["spell only"] or 0, ns), pct(mixes.mixed or 0, ns)))

    -- 5. Combat
    local L = S.lasers
    local beams = L.hit + L.blocked + L.dodged + L.wall
    out("")
    out("5. Combat")
    out(string.format("  beams: %d per round; hit %s, blocked %s, dodged %s, wall %s",
        math.floor(avg(beams, n) + 0.5), pct(L.hit, beams), pct(L.blocked, beams), pct(L.dodged, beams), pct(L.wall, beams)))
    local sh = S.shield
    out(string.format("  shield charges: %.1f gained per round; used %s, expired unused %s",
        avg(sh.gained, n), pct(sh.used, sh.gained), pct(sh.expired, sh.gained)))
    local a = S.accel
    local fastRate = avg(a.picksFast, a.time)
    local normalRate = avg(a.picksNormal, a.playerTime - a.time)
    out(string.format("  accelerate: %.1f stacks gained per round; active %s of the time, avg %.1f stacks when active",
        avg(a.gained, n), pct(a.time, a.playerTime), avg(a.stackTime, a.time)))
    out(string.format("    pickups per minute: %.1f while accelerated vs %.1f normal (x%.2f)",
        fastRate * 60, normalRate * 60, avg(fastRate, normalRate)))
end

local CSV_COLUMNS = { "round", "player", "shape", "level", "result", "words", "window",
                      "damage", "blocked", "fired", "mine", "theirs" }

local function csv(rows)
    local lines = { table.concat(CSV_COLUMNS, ",") }
    for _, r in ipairs(rows) do
        local cells = {}
        for i, c in ipairs(CSV_COLUMNS) do
            local v = r[c]
            cells[i] = type(v) == "number" and string.format(v % 1 == 0 and "%d" or "%.2f", v) or tostring(v)
        end
        lines[#lines + 1] = table.concat(cells, ",")
    end
    return table.concat(lines, "\n") .. "\n"
end

-- opts: { rounds, seed, cap, p1, p2, out = print, write = fn(path, text), progress = fn(i, n) }
function Sim.run(data, opts)
    opts.seed = opts.seed or 1
    opts.cap = opts.cap or 300
    local out = opts.out or print
    local S = newStats()
    for i = 1, opts.rounds do
        math.randomseed(opts.seed * 100003 + i)
        playRound(data, S, i, opts)
        if opts.progress then opts.progress(i, opts.rounds) end
    end
    report(S, opts, out)
    if opts.write then
        local path = string.format("sim_%s_vs_%s_seed%d.csv", opts.p1 or "default", opts.p2 or "default", opts.seed)
        opts.write(path, csv(S.templates))
        out("")
        out("CSV (one row per finished or timed-out template): " .. path)
    end
    return S
end

return Sim
