-- Simulation: bot vs bot rounds with no window, much faster than real
-- time, then balance metrics (DESIGN §15, docs/SIMULATION.md). Pure logic:
-- each round's stats are a self-contained record (`Sim.playRound`), so
-- worker threads (src/simjobs.lua) can play rounds and send the records
-- back as text (`Sim.encode` / `Sim.decode`). `Sim.finish` merges them
-- and reports. Every average and share comes with ± one standard error,
-- from how much it varies between rounds.
--
--   lovec . --sim 400 | --sim 1m [--stats] [--p1 profile] [--p2 profile]
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

-- Play round `roundNo` and return its stats record. The round's random
-- numbers come from `opts.seed` and the round number.
function Sim.playRound(data, roundNo, opts)
    math.randomseed(opts.seed * 100003 + roundNo)
    local S = newStats()
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

    S.round = roundNo
    S.length = g.clock
    S.winner = g.state == "over" and tostring(g.winner) or "cap"
    return S
end

-- A round record as text (for sending between threads), and back.
local function encodeInto(v, out)
    local t = type(v)
    if t == "number" then
        out[#out + 1] = string.format("%.17g", v)
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            out[#out + 1] = "["
            encodeInto(k, out)
            out[#out + 1] = "]="
            encodeInto(x, out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    end
end

function Sim.encode(record)
    local out = {}
    encodeInto(record, out)
    return table.concat(out)
end

function Sim.decode(text)
    local chunk = assert(loadstring("return " .. text))
    setfenv(chunk, {})
    return chunk()
end

-- Add every number field of `src` into `dst`.
local function addInto(dst, src)
    for k, v in pairs(src) do
        if type(v) == "number" then dst[k] = (dst[k] or 0) + v end
    end
end

local function append(dst, src)
    for _, v in ipairs(src) do dst[#dst + 1] = v end
end

-- All rounds' records summed into one stats table.
function Sim.merge(records)
    local S = newStats()
    for _, R in ipairs(records) do
        S.rounds[#S.rounds + 1] = { length = R.length, winner = R.winner }
        append(S.templates, R.templates)
        for k, tr in pairs(R.traps) do
            S.traps[k] = S.traps[k] or {}
            addInto(S.traps[k], tr)
        end
        addInto(S.lasers, R.lasers)
        addInto(S.shield, R.shield)
        addInto(S.accel, R.accel)
        addInto(S.waves, R.waves)
        append(S.waves.gaps, R.waves.gaps)
        addInto(S.oneSided, R.oneSided)
        append(S.oneSided.stretches, R.oneSided.stretches)
    end
    return S
end

-- Formatting helpers.
local function avg(a, b) return b > 0 and a / b or 0 end
local function pct(a, b) return b > 0 and string.format("%5.1f%%", 100 * a / b) or "    -" end

local function quantile(list, q)
    if #list == 0 then return 0 end
    local s = {}
    for i, v in ipairs(list) do s[i] = v end
    table.sort(s)
    return s[math.max(1, math.ceil(q * #s))]
end

-- sum(a) / sum(b) over rounds, and its standard error. Rounds are the
-- independent samples, so this holds for shares of beams or pickups too,
-- which bunch up within a round. `f(item)` returns a, b for one round.
local function ratio(items, f)
    local as, bs, A, B = {}, {}, 0, 0
    for i, item in ipairs(items) do
        local a, b = f(item)
        as[i], bs[i] = a, b
        A, B = A + a, B + b
    end
    if B == 0 then return nil end
    local r, s, n = A / B, 0, #items
    for i = 1, n do
        local d = as[i] - r * bs[i]
        s = s + d * d
    end
    return r, n > 1 and math.sqrt(s * n / (n - 1)) / B or 0
end

-- "45.8±2.5%", "0.52±0.03"; "-" when there's no data.
local function pctSE(r, se) return r and string.format("%.1f±%.1f%%", 100 * r, 100 * se) or "-" end
local function numSE(fmt, r, se) return r and string.format(fmt .. "±" .. fmt, r, se) or "-" end

-- Pad to a display width ("±" is two bytes but one column).
local function width(s) return #s - select(2, s:gsub("±", "")) end
local function lpad(s, w) return string.rep(" ", w - width(s)) .. s end

-- Sum template rows into groups by `keyOf(row)`: key -> totals.
local function groupBy(rows, keyOf)
    local groups = {}
    for _, r in ipairs(rows) do
        local key = keyOf(r)
        local gr = groups[key]
        if not gr then
            gr = { key = key, level = r.level, done = 0, timeout = 0, words = 0, window = 0,
                   damage = 0, blocked = 0, mine = 0, theirs = 0 }
            groups[key] = gr
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
    return groups
end

local function templateTable(out, title, records, S, keyOf)
    local perRound = {}
    for i, R in ipairs(records) do perRound[i] = groupBy(R.templates, keyOf) end
    local order = {}
    for _, gr in pairs(groupBy(S.templates, keyOf)) do order[#order + 1] = gr end
    table.sort(order, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.done + a.timeout ~= b.done + b.timeout then return a.done + a.timeout > b.done + b.timeout end
        return a.key < b.key
    end)

    out(title)
    out(string.format("  %-22s %6s %7s %6s %7s %7s %7s %11s %11s",
        "", "done", "t/out", "words", "window", "dmg", "blocked", "ret/word", "picks"))
    for _, gr in ipairs(order) do
        local key, n = gr.key, gr.done
        local ret, retSE = ratio(perRound, function(m)
            local x = m[key]
            if not x then return 0, 0 end
            return x.damage + x.blocked, x.words
        end)
        local picks, picksSE = ratio(perRound, function(m)
            local x = m[key]
            if not x then return 0, 0 end
            return x.mine, x.mine + x.theirs
        end)
        out(string.format("  %-22s %6d %7s %6.1f %6.1fs %7.2f %7.2f %s %s",
            gr.key, n, pct(gr.timeout, n + gr.timeout), avg(gr.words, n), avg(gr.window, n),
            avg(gr.damage, n), avg(gr.blocked, n),
            lpad(numSE("%.2f", ret, retSE), 11), lpad(pctSE(picks, picksSE), 11)))
    end
end

local function report(records, S, out)
    local n = #records

    -- 1. Rounds
    local lengths = {}
    for i, R in ipairs(records) do lengths[i] = R.length end
    local function winShare(w)
        return pctSE(ratio(records, function(R) return R.winner == w and 1 or 0, 1 end))
    end
    out("1. Rounds")
    out(string.format("  length: avg %ss, median %.0fs, 10%% %.0fs, 90%% %.0fs",
        numSE("%.0f", ratio(records, function(R) return R.length, 1 end)),
        quantile(lengths, 0.5), quantile(lengths, 0.1), quantile(lengths, 0.9)))
    out(string.format("  winner: P1 %s  P2 %s  draw %s  no winner by cap %s",
        winShare("1"), winShare("2"), winShare("draw"), winShare("cap")))

    -- 2. Templates
    out("")
    out("2. Finished templates  (dmg/blocked per cast; ret/word = (dmg+blocked)/word;")
    out("   picks = my share of all pickups while the effect window is open)")
    templateTable(out, "  by shape:", records, S, function(r) return r.shape end)
    templateTable(out, "  by level:", records, S, function(r) return "level " .. r.level end)
    templateTable(out, "  overall:", records, S, function() return "all" end)

    -- 3. Traps
    out("")
    out("3. Beam hit rate by what fired it")
    out(string.format("  %-14s %6s %11s %8s %7s %7s", "", "beams", "hit", "blocked", "dodged", "wall"))
    local keys = {}
    for k in pairs(S.traps) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return S.traps[a].beams > S.traps[b].beams end)
    for _, k in ipairs(keys) do
        local tr = S.traps[k]
        local hit = pctSE(ratio(records, function(R)
            local x = R.traps[k]
            if not x then return 0, 0 end
            return x.hit, x.beams
        end))
        out(string.format("  %-14s %6d %s %8s %7s %7s", k, tr.beams, lpad(hit, 11),
            pct(tr.blocked, tr.beams), pct(tr.dodged, tr.beams), pct(tr.wall, tr.beams)))
    end

    -- 4. Words
    local w = S.waves
    out("")
    out("4. Word spawning")
    local gap = numSE("%.1f", ratio(records, function(R)
        local sum = 0
        for _, v in ipairs(R.waves.gaps) do sum = sum + v end
        return sum, #R.waves.gaps
    end))
    local early = pctSE(ratio(records, function(R) return R.waves.early, R.waves.count end))
    out(string.format("  waves: %d, gap avg %ss (10%% %.1fs, 90%% %.1fs), pulled early (dead board) %s, leftovers/wave %.1f",
        w.count, gap, quantile(w.gaps, 0.1), quantile(w.gaps, 0.9), early, avg(w.leftovers, w.count)))
    local o = S.oneSided
    local lens, ends, mixes = {}, {}, {}
    for i, s in ipairs(o.stretches) do
        lens[i] = s.length
        ends[s.ended] = (ends[s.ended] or 0) + 1
        mixes[s.mix] = (mixes[s.mix] or 0) + 1
    end
    local ns = #o.stretches
    local share = pctSE(ratio(records, function(R) return R.oneSided.time, R.oneSided.fightTime end))
    out(string.format("  one-sided board: %s of fight time, %d stretches, length avg %.1fs (90%% %.1fs)",
        share, ns, avg(o.time, ns), quantile(lens, 0.9)))
    out(string.format("    ended by: pickup %s, next wave %s, other %s, round end %s",
        pct(ends.pickup or 0, ns), pct(ends.wave or 0, ns), pct(ends.other or 0, ns), pct(ends["round end"] or 0, ns)))
    out(string.format("    floor had: condition only %s, spell only %s, mixed %s",
        pct(mixes["condition only"] or 0, ns), pct(mixes["spell only"] or 0, ns), pct(mixes.mixed or 0, ns)))

    -- 5. Combat
    local L = S.lasers
    local beams = L.hit + L.blocked + L.dodged + L.wall
    local function beamShare(result)
        return pctSE(ratio(records, function(R)
            local x = R.lasers
            return x[result], x.hit + x.blocked + x.dodged + x.wall
        end))
    end
    out("")
    out("5. Combat")
    out(string.format("  beams: %d per round; hit %s, blocked %s, dodged %s, wall %s",
        math.floor(avg(beams, n) + 0.5), beamShare("hit"), beamShare("blocked"), beamShare("dodged"), beamShare("wall")))
    local sh = S.shield
    out(string.format("  shield charges: %.1f gained per round; used %s, expired unused %s",
        avg(sh.gained, n),
        pctSE(ratio(records, function(R) return R.shield.used, R.shield.gained end)),
        pctSE(ratio(records, function(R) return R.shield.expired, R.shield.gained end))))
    local a = S.accel
    local fastRate = avg(a.picksFast, a.time)
    local normalRate = avg(a.picksNormal, a.playerTime - a.time)
    out(string.format("  accelerate: %.1f stacks gained per round; active %s of the time, avg %.1f stacks when active",
        avg(a.gained, n), pctSE(ratio(records, function(R) return R.accel.time, R.accel.playerTime end)),
        avg(a.stackTime, a.time)))
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

-- docs/STATS.md: the report, replaced by every `--stats` run, so the
-- file's git history shows how each gameplay change moved the numbers.
local function statsFile(rounds, lines)
    return table.concat({
        "# Wordcraft — Simulation stats",
        "",
        "Generated by `lovec . --sim ... --stats`; don't edit by hand. Each run replaces this file,",
        "so its git history shows how each gameplay change moved the numbers.",
        "What the numbers mean: [SIMULATION.md](SIMULATION.md). ± is one standard error.",
        "",
        "**Rounds:** " .. rounds,
        "",
        "```text",
        table.concat(lines, "\n"),
        "```",
        "",
    }, "\n")
end

-- Fill in defaults: a fresh seed each run, rounds stop at 300 s.
function Sim.defaults(opts)
    opts.seed = opts.seed or os.time()
    opts.cap = opts.cap or 300
    return opts
end

-- Merge round records, print the report, save the CSV and (with
-- `writeStats`) the stats file.
-- opts: { p1, p2, cap, out = print, write = fn(path, text), writeStats = fn(text) }
function Sim.finish(records, opts)
    table.sort(records, function(a, b) return a.round < b.round end)
    local S = Sim.merge(records)
    local out = opts.out or print
    out("")
    out(string.format("=== Simulation: %d rounds, P1 %s vs P2 %s, cap %ds ===",
        #records, opts.p1 or "default", opts.p2 or "default", opts.cap))
    out("")
    local lines = {}
    report(records, S, function(s)
        lines[#lines + 1] = s
        out(s)
    end)
    if opts.write then
        local path = string.format("sim_%s_vs_%s.csv", opts.p1 or "default", opts.p2 or "default")
        opts.write(path, csv(S.templates))
        out("")
        out("CSV (one row per finished or timed-out template): " .. path)
    end
    if opts.writeStats then opts.writeStats(statsFile(#records, lines)) end
    return S
end

-- All rounds in this thread, one after another (selftest; the game's
-- --sim spreads rounds over worker threads instead).
-- opts: Sim.finish's, plus { rounds, seed, progress = fn(i, n) }
function Sim.run(data, opts)
    Sim.defaults(opts)
    local records = {}
    for i = 1, opts.rounds do
        records[i] = Sim.playRound(data, i, opts)
        if opts.progress then opts.progress(i, opts.rounds) end
    end
    return Sim.finish(records, opts)
end

return Sim
