-- Render: draws a Game onto the low-res canvas. All love.graphics calls for
-- gameplay live here. Top-down "2.5D": everything standing on the floor is
-- y-sorted so lower things draw in front.

local Render = {}

local function hex(s)
    return tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255
end

local C = {
    bg        = { hex("#1a1c2c") },
    floorA    = { hex("#333c57") },
    floorB    = { hex("#38425f") },
    wallTop   = { hex("#94b0c2") },
    wallFront = { hex("#566c86") },
    wallEdge  = { hex("#1a1c2c") },
    shadow    = { 0, 0, 0, 0.35 },
    text      = { hex("#f4f4f4") },
    dim       = { hex("#94b0c2") },
    spell     = { hex("#ef7d57") },
    condition = { hex("#73eff7") },
    blankBg   = { hex("#333c57") },
    hp        = { hex("#b13e53") },
    hpEmpty   = { hex("#333c57") },
    timer     = { hex("#ffcd75") },
    shield    = { hex("#73eff7") },
    aim       = { hex("#e43b44") },
    template  = { hex("#c9b2ff") },  -- training-room template tiles
    reset     = { hex("#94b0c2") },  -- training-room reset tile
    player    = { { hex("#41a6f6") }, { hex("#e43b44") } }, -- per-player: beams, orbs, pickups
    hpText    = { hex("#ff6b6b") },
    -- Template text / timer colour per stack level (1, 2, 3).
    level     = { { hex("#f4f4f4") }, { hex("#ffcd75") }, { hex("#ff77c8") } },
    p1        = { hex("#73eff7") },
    p2        = { hex("#a7f070") },
}

local WALL_RISE = 8 -- how far a wall's top face is lifted above its floor tile
local CHEST = 13    -- laser height above the feet

local fonts = {}
local hurt = { 0, 0 }   -- hit-flash timers, purely visual
local levelFlash = { 0, 0 } -- HUD flash when a template stacks up
local lastLevel = {}

-- Floating combat text ("-1", "BLOCK", "DODGE") spawned once per fired beam.
local FLOAT_TIME = 0.9
local floaters = {}                               -- { text, color, x, y, age }
local seenBeams = setmetatable({}, { __mode = "k" })
local drawFloaters -- defined with the other floater code below

-- Pickup feedback: the taken tile flies to the picker, a ring bursts at the
-- spot in the picker's colour.
local PICKUP_TIME = 0.35
local pickups = {}                                -- { def, x, y, player, age }
local seenPickups = setmetatable({}, { __mode = "k" })
local drawPickups -- defined below

function Render.load()
    fonts.small = love.graphics.newFont(8, "mono")
    fonts.big = love.graphics.newFont(16, "mono")
    fonts.small:setFilter("nearest", "nearest")
    fonts.big:setFilter("nearest", "nearest")
end

local function setColor(c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local TYPE_COLOR = { spell = "spell", condition = "condition", template = "template", reset = "reset" }
local function typeColor(wordType)
    return C[TYPE_COLOR[wordType] or "condition"]
end

-- Movement juice (players with movementFx): a 4-frame walk cycle whose pace
-- follows speed, and dust puffs when starting to move, turning sharply,
-- or dashing. Purely visual state, kept here rather than in game logic.
local STRIDE = 28         -- pixels travelled per full walk cycle (4 frames)
local DUST_TIME = 0.35
local walkPhase = { 0, 0 }
local lastMove = {}       -- per player: { speed, dirX, dirY, dashing }
local dust = {}           -- { x, y, vx, vy, age, r }

local function puff(x, y, dirX, dirY, count)
    for i = 1, count do
        local a = math.atan2(dirY, dirX) + (i - (count + 1) / 2) * 0.6
        dust[#dust + 1] = {
            x = x, y = y - 1, age = 0, r = 1 + (i % 2),
            vx = math.cos(a) * 18, vy = math.sin(a) * 10 - 4,
        }
    end
end

local function updateMovementFx(dt, game)
    for k, p in ipairs(game.players) do
        if p.movementFx then
            local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
            local dashing = p:isDashing()
            local dirX, dirY = 0, 0
            if speed > 0 then dirX, dirY = p.vx / speed, p.vy / speed end
            local last = lastMove[k] or { speed = 0, dirX = 0, dirY = 0, dashing = false }

            if dashing and not last.dashing then
                puff(p.x, p.y, -p.dashX, -p.dashY, 4)          -- kicked up behind the dash
            elseif not dashing and speed > 10 then
                if last.speed <= 10 then
                    puff(p.x, p.y, -dirX, -dirY, 2)              -- starting off
                elseif dirX * last.dirX + dirY * last.dirY < 0 then
                    puff(p.x, p.y, -dirX, -dirY, 3)              -- sharp turn
                end
            end

            if speed > 10 and not dashing then
                walkPhase[k] = walkPhase[k] + speed * dt / STRIDE
            else
                walkPhase[k] = 0
            end
            lastMove[k] = { speed = speed, dirX = dirX, dirY = dirY, dashing = dashing }
        end
    end
    for i = #dust, 1, -1 do
        local d = dust[i]
        d.age = d.age + dt
        d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
        d.vx, d.vy = d.vx * 0.9, d.vy * 0.9
        if d.age >= DUST_TIME then table.remove(dust, i) end
    end
end

-- Walk cycle frame for p (1-4), or nil when standing, dashing or without
-- walk frames. The frame advances with distance walked, so faster walking
-- steps faster.
local function walkFrame(p, sprites)
    if not p.movementFx or walkPhase[p.id] == 0 then return nil end
    local name = p.sprite .. "_walk" .. (math.floor(walkPhase[p.id] * 4) % 4 + 1)
    return sprites[name] and name or nil
end

local function drawDust()
    for _, d in ipairs(dust) do
        local k = d.age / DUST_TIME
        setColor(C.dim, 0.7 * (1 - k))
        love.graphics.circle("fill", d.x, d.y, d.r + k * 1.5)
    end
end

local function printCentered(text, font, cx, y)
    love.graphics.setFont(font)
    love.graphics.print(text, math.floor(cx - font:getWidth(text) / 2), math.floor(y))
end

---------------------------------------------------------------- world

local function drawFloor(arena)
    for r = 1, arena.rows do
        for c = 1, arena.cols do
            setColor(((r + c) % 2 == 0) and C.floorA or C.floorB)
            love.graphics.rectangle("fill", (c - 1) * arena.tile, arena.top + (r - 1) * arena.tile, arena.tile, arena.tile)
        end
    end
end

local function drawWall(arena, c, r)
    local s = arena.tile
    local x, y = (c - 1) * s, arena.top + (r - 1) * s
    setColor(C.wallFront)
    love.graphics.rectangle("fill", x, y + s - WALL_RISE, s, WALL_RISE)
    setColor(C.wallTop)
    love.graphics.rectangle("fill", x, y - WALL_RISE, s, s)
    setColor(C.wallEdge)
    love.graphics.rectangle("line", x + 0.5, y - WALL_RISE + 0.5, s - 1, s + WALL_RISE - 1)
end

local function drawWord(word, time)
    local def = word.def
    local f = fonts.small
    local w = f:getWidth(def.label) + 4
    local h = 9
    local bob = math.floor(math.sin(time * 4 + word.x) * 1.5 + 0.5)
    local x, y = math.floor(word.x - w / 2), math.floor(word.y - h - 3 + bob)
    setColor(C.shadow)
    love.graphics.ellipse("fill", word.x, word.y, w / 2, 2)
    setColor(typeColor(def.type))
    love.graphics.rectangle("fill", x, y, w, h)
    setColor(C.bg)
    love.graphics.setFont(f)
    love.graphics.print(def.label, x + 2, y - 1)
end

local function drawMarker(m, time)
    if math.floor(time * 8) % 2 == 0 then return end
    setColor(C.text, 0.7)
    love.graphics.ellipse("line", m.x, m.y, 5, 2)
end

-- Gem centre in the casting frame, in sprite pixels (see make_sprites.ps1).
local CAST_GEM = { x = 14.5, y = 3.5 }
-- Extra orbs for a volley (several attacks in one raise) arc over the head,
-- offset from the gem in sprite pixels (x mirrored with facing).
local ORB_SLOTS = { { 0, 0 }, { -11, -2 }, { -22, 0 }, { -28, 9 }, { 6, 9 } }

-- The pose shows while the staff is raised and while any of p's lasers
-- is still charging.
local function isCasting(game, p)
    if game.spellbooks[p.id]:isRaising() then return true end
    for _, l in ipairs(game.lasers) do
        if l.caster == p then return true end
    end
    return false
end

-- While casting, the wizard turns to face the opponent.
local function castFacing(game, p)
    local o = game:opponentOf(p)
    return (o.x >= p.x) and 1 or -1
end

-- World position of orb `slot` (1 = the gem itself); rays start here.
local function orbPos(game, p, sprites, slot)
    local img = sprites[p.sprite .. "_cast"]
    local w, h = img:getDimensions()
    local f = castFacing(game, p)
    local o = ORB_SLOTS[((slot or 1) - 1) % #ORB_SLOTS + 1]
    return p.x + f * (CAST_GEM.x - w / 2 + o[1]), p.y - h + CAST_GEM.y + o[2]
end

-- Armed trap: a dashed rune circle turning on the floor under the wizard.
local function drawTrapRune(p, time)
    local segs = 12
    local spin = time * 1.5
    setColor(C.condition, 0.8 + 0.2 * math.sin(time * 6))
    for i = 0, segs - 1, 2 do
        local a1 = spin + i / segs * math.pi * 2
        local a2 = spin + (i + 1) / segs * math.pi * 2
        love.graphics.line(p.x + math.cos(a1) * 11, p.y + math.sin(a1) * 4,
                           p.x + math.cos(a2) * 11, p.y + math.sin(a2) * 4)
    end
end

local function drawPlayer(game, p, sprites, time)
    local tuning = game.data.tuning
    local casting = isCasting(game, p)
    local walk = not casting and walkFrame(p, sprites)
    local img = sprites[casting and (p.sprite .. "_cast") or walk or p.sprite]
    local w, h = img:getDimensions()
    local facing = casting and castFacing(game, p) or p.facing

    setColor(C.shadow)
    love.graphics.ellipse("fill", p.x, p.y, 6, 2)
    if game.spellbooks[p.id].trap then drawTrapRune(p, time) end

    local alpha = p:isDashing() and 0.45 or 1
    if hurt[p.id] > 0 and math.floor(hurt[p.id] * 20) % 2 == 0 then
        love.graphics.setColor(1, 0.4, 0.4, alpha)
    else
        love.graphics.setColor(1, 1, 1, alpha)
    end

    love.graphics.draw(img, math.floor(p.x), math.floor(p.y), 0, facing, 1, w / 2, h)

    -- One charging orb per laser: grows with the aim, flashes before firing.
    -- A raise with no attack (shield / accelerate) shows a small gold glint.
    if casting then
        local any = false
        for _, l in ipairs(game.lasers) do
            if l.caster == p then
                any = true
                local charge = 1 - l.timer / tuning.spells.telegraph
                local ox, oy = orbPos(game, p, sprites, l.slot)
                local r = 1.5 + charge * 2.5
                setColor(C.player[p.id], 0.35)
                love.graphics.circle("fill", ox, oy, r + 1.5)
                if charge > 0.8 and math.floor(time * 24) % 2 == 0 then
                    love.graphics.setColor(1, 1, 1, 1)
                else
                    setColor(C.player[p.id])
                end
                love.graphics.circle("fill", ox, oy, r)
            end
        end
        if not any then
            local ox, oy = orbPos(game, p, sprites, 1)
            setColor(C.timer, 0.4)
            love.graphics.circle("fill", ox, oy, 4)
            setColor(C.timer)
            love.graphics.circle("fill", ox, oy, 2)
        end
    end

    -- Dash cooldown: a small bar over the head, only while recharging.
    if p.dashCooldown > 0 then
        local bw = 14
        local bx, by = math.floor(p.x - bw / 2), math.floor(p.y - h - 4)
        setColor(C.hpEmpty)
        love.graphics.rectangle("fill", bx, by, bw, 2)
        setColor(C.dim)
        love.graphics.rectangle("fill", bx, by, math.floor(bw * (1 - p.dashCooldown / tuning.dash.cooldown) + 0.5), 2)
    end

    -- Shield charges: one ring per charge up to 5; beyond that a single
    -- bold ring with the count ("x6"), so a big stack stays readable.
    if p.shield > 5 then
        setColor(C.shield)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", p.x, p.y - 12, 14)
        love.graphics.setLineWidth(1)
        local label = "x" .. p.shield
        local f = fonts.small
        love.graphics.setFont(f)
        local lx, ly = math.floor(p.x + 11), math.floor(p.y - 30)
        setColor(C.bg)
        love.graphics.print(label, lx + 1, ly + 1)
        setColor(C.shield)
        love.graphics.print(label, lx, ly)
    else
        for i = 1, p.shield do
            setColor(C.shield, 0.9 - (i - 1) * 0.1)
            love.graphics.circle("line", p.x, p.y - 12, 11 + (i - 1) * 3)
        end
    end

    -- Speed lines trailing behind: two more per accelerate stack.
    local lines = p.accelerate * 2
    if lines > 0 then
        local back = -facing
        for i = 0, lines - 1 do
            local ly = p.y - 3 - i * (20 / lines)
            local lx = p.x + back * (9 + (i % 2) * 3)
            local len = 4 + (i % 3) * 2
            setColor(C.timer, 0.85)
            love.graphics.line(lx, ly, lx + back * len, ly)
        end
    end
end

local function drawLasers(game, sprites, time)
    local t = game.data.tuning
    -- Aim: thin ray in the caster's colour from their orb, flashing faster as it's
    -- about to fire.
    for _, l in ipairs(game.lasers) do
        local left = l.timer / t.spells.telegraph          -- 1 -> 0
        local rate = 6 + (1 - left) * 18
        local on = math.floor(time * rate) % 2 == 0
        -- Stop the ray at a wall so the target can see they're in cover.
        local clear, wx, wy = game.arena:lineOfSight(l.caster.x, l.caster.y, l.target.x, l.target.y)
        local ex, ey = l.target.x, l.target.y
        if not clear then ex, ey = wx, wy end
        local gx, gy = orbPos(game, l.caster, sprites, l.slot)
        setColor(C.player[l.caster.id], on and 0.9 or 0.25)
        love.graphics.setLineWidth(1)
        love.graphics.line(gx, gy, ex, ey - CHEST)
    end
    -- Fired beams: thick glow in the caster's colour with a white core, shrinking as it fades.
    for _, b in ipairs(game.beams) do
        local k = b.timer / t.spells.beamShowTime           -- 1 -> 0
        local x1, y1 = orbPos(game, b.caster, sprites, b.slot)
        local x2, y2 = b.x2, b.y2 - CHEST
        setColor(C.player[b.caster.id], 0.9)
        love.graphics.setLineWidth(math.max(1, 7 * k))
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(math.max(1, 3 * k))
        love.graphics.line(x1, y1, x2, y2)
        if b.result == "blocked" then
            setColor(C.shield)
            love.graphics.circle("fill", x2, y2, 6 * k + 2)
        elseif b.result == "wall" then
            setColor(C.timer)
            love.graphics.circle("fill", x2, y2, 4 * k + 1)
        elseif b.result == "hit" then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("fill", x2, y2, 6 * k + 1)
        end
    end
    love.graphics.setLineWidth(1)
end

local function drawWorld(game, sprites, time)
    local arena = game.arena
    drawFloor(arena)

    local wf = game.wordfield
    drawDust()

    if wf.markers then
        for _, m in ipairs(wf.markers) do drawMarker(m, time) end
    end

    -- Training dummy's range: thin circle, brighter while you're inside it.
    if game.mode == "training" then
        local d, p = game.players[2], game.players[1]
        local r = game.data.training.dummy.range
        local dx, dy = p.x - d.x, p.y - d.y
        setColor(C.aim, (dx * dx + dy * dy <= r * r) and 0.7 or 0.3)
        love.graphics.circle("line", d.x, d.y, r)
    end

    -- Y-sort walls, words and players by the y of their floor contact.
    local items = {}
    for r = 1, arena.rows do
        for c = 1, arena.cols do
            if arena.solid[r][c] then
                local y = arena.top + r * arena.tile
                items[#items + 1] = { y = y, draw = function() drawWall(arena, c, r) end }
            end
        end
    end
    for _, w in ipairs(wf.words) do
        items[#items + 1] = { y = w.y, draw = function() drawWord(w, time) end }
    end
    for _, p in ipairs(game.players) do
        items[#items + 1] = { y = p.y, draw = function() drawPlayer(game, p, sprites, time) end }
    end
    table.sort(items, function(a, b) return a.y < b.y end)
    for _, it in ipairs(items) do it.draw() end

    drawLasers(game, sprites, time)
    drawPickups()
    drawFloaters()
end

---------------------------------------------------------------- HUD

-- Template as a list of text and blank tokens, e.g.
-- "when [close] or [___], repeat 3: cast [attack] and [___]".
local function templateTokens(book, words)
    local tpl = book.template
    -- No template: "..." in versus (one is about to be dealt); a hint in training.
    if not tpl then return { { text = book.sandbox and "pick up a template tile" or "..." } } end
    local function blank(b)
        return { blank = b.type, text = b.word and words.byId[b.word].label or "___", filled = b.word and true }
    end
    local toks = {}
    local function add(t) toks[#toks + 1] = t end
    if #tpl.conditions > 0 then
        add({ text = "when " })
        for i, b in ipairs(tpl.conditions) do
            if i > 1 then add({ text = " or " }) end
            add(blank(b))
        end
        add({ text = ", " })
    end
    if tpl.n then add({ text = "repeat " .. tpl.n .. ": " }) end
    add({ text = "cast " })
    local n = #tpl.spells
    for i, b in ipairs(tpl.spells) do
        if i > 1 then add({ text = (i == n) and " and " or ", " }) end
        add(blank(b))
    end
    return toks
end

-- Split text tokens into words so long templates can wrap between them.
local function splitWords(tokens)
    local out = {}
    for _, tok in ipairs(tokens) do
        if tok.blank then
            out[#out + 1] = tok
        else
            for piece in tok.text:gmatch("[^ ]* *") do
                if piece ~= "" then out[#out + 1] = { text = piece } end
            end
        end
    end
    return out
end

-- Draw tokens wrapped to maxW; returns the number of lines used.
local function drawTokens(tokens, x0, y0, maxW, textColor)
    local f = fonts.small
    love.graphics.setFont(f)
    local x, y, lines = x0, y0, 1
    for _, tok in ipairs(splitWords(tokens)) do
        local w = f:getWidth(tok.text) + (tok.blank and 2 or 0)
        if x > x0 and x + w - x0 > maxW then
            x, y, lines = x0, y + 9, lines + 1
            if not tok.blank and tok.text:match("^ +$") then goto continue end
        end
        if tok.blank then
            local col = typeColor(tok.blank)
            setColor(col)
            if tok.filled then
                love.graphics.rectangle("fill", x, y + 1, w, 9)
                setColor(C.bg)
            else
                love.graphics.rectangle("line", x + 0.5, y + 1.5, w - 1, 8)
            end
            love.graphics.print(tok.text, x + 1, y)
        else
            setColor(textColor)
            love.graphics.print(tok.text, x, y)
        end
        x = x + w
        ::continue::
    end
    return lines
end

-- Only the trap gets text: which condition sets it off is useful to read.
-- Everything else (shields, speed, casting) is drawn on the wizard.
local function effectText(book, words)
    local function labels(ids, sep)
        local out = {}
        for i, id in ipairs(ids) do out[i] = words.byId[id].label end
        return table.concat(out, sep)
    end
    if book.trap then
        local tr = book.trap
        return "trap: " .. labels(tr.conditions, "/") .. " > " .. labels(tr.spells, "+")
            .. (tr.n > 1 and (" x" .. tr.n) or "")
    end
    return "" -- shields, speed and casting are shown on the wizard instead
end

local function drawBar(x, y, w, frac, col)
    setColor(C.hpEmpty)
    love.graphics.rectangle("fill", x, y, w, 2)
    setColor(col)
    love.graphics.rectangle("fill", x, y, math.floor(w * math.max(0, math.min(1, frac)) + 0.5), 2)
end

local PANEL_W = 152

-- Training room: which tile category is on the floor, as tabs along the
-- bottom of the arena. The active tab is filled in its tile colour.
local function drawCategoryTabs(game)
    local f = fonts.small
    love.graphics.setFont(f)
    local cats = game.data.training.categories
    local hint = "SPACE: switch"
    local gap = 6
    local widths, total = {}, f:getWidth(hint)
    for i, c in ipairs(cats) do
        widths[i] = f:getWidth(c.label) + 6
        total = total + widths[i] + gap
    end
    local y = game.height - 11
    setColor(C.bg, 0.8)
    love.graphics.rectangle("fill", 0, y - 1, game.width, 12)
    local x = math.floor((game.width - total) / 2)
    for i, c in ipairs(cats) do
        local col = typeColor(c.type)
        if i == game.trainingCategory then
            setColor(col)
            love.graphics.rectangle("fill", x, y, widths[i], 10)
            setColor(C.bg)
        else
            setColor(col, 0.45)
            love.graphics.rectangle("line", x + 0.5, y + 0.5, widths[i] - 1, 9)
        end
        love.graphics.print(c.label, x + 3, y)
        x = x + widths[i] + gap
    end
    setColor(C.dim)
    love.graphics.print(hint, x, y)
end

local function drawPanel(game, k, x)
    local t = game.data.tuning
    local words = game.data.words
    local book, p = game.spellbooks[k], game.players[k]
    local level = book.template and book.template.level or 1
    local levelCol = C.level[math.min(level, #C.level)]

    -- Flash the panel when a template stacks up a level.
    if levelFlash[k] > 0 then
        setColor(levelCol, levelFlash[k] * 0.6)
        love.graphics.rectangle("fill", x - 3, 0, PANEL_W + 2, 30)
    end

    drawTokens(templateTokens(book, words), x, 1, PANEL_W - 4, levelCol)

    -- HP pips + effect text
    for i = 1, t.player.hp do
        setColor(i <= p.hp and C.hp or C.hpEmpty)
        love.graphics.rectangle("fill", x + (i - 1) * 5, 32, 4, 4)
    end
    setColor(C.dim)
    love.graphics.setFont(fonts.small)
    love.graphics.print(effectText(book, words), x + t.player.hp * 5 + 4, 29)

    -- Template timeout, coloured by stack level (no timeouts in training)
    local tl = book.template and book.template.timeLeft / t.templates.timeout or 0
    if not book.sandbox then drawBar(x, 40, PANEL_W - 12, tl, levelCol) end
end

-- Training guide: a title, up to two lines of instructions, and a separate
-- counter (templates stacked / blanks left) set apart at the bottom. It
-- reads two things: the template held (top left) and which tile tab is on
-- the floor (bottom). Spell effects explain themselves, so only traps (not
-- obvious) get their own message. How to switch tabs is hinted elsewhere.
local function trainingGuide(game)
    local t, words = game.data.tuning, game.data.words
    local book = game.spellbooks[1]
    local tpl = book.template
    local max = t.stacking.maxLevel
    local level = tpl and tpl.level or 0
    local tab = game.data.training.categories[game.trainingCategory].type

    -- A trap was just armed and nothing new is being built yet.
    if book.trap and not tpl then
        local names = {}
        for i, id in ipairs(book.trap.conditions) do names[i] = words.byId[id].label end
        return "TRAP ARMED", {
            "it fires once, the moment",
            "this is true: " .. table.concat(names, " or "),
        }, "try it near the dummy"
    end

    -- Templates tab: step 1, with the stack count.
    if tab == "template" then
        local counter = "templates " .. level .. "/" .. max
        if level >= max then
            return "STEP 1: TEMPLATES", { "max " .. max .. " templates stacked:", "now fill the blanks" }, counter
        end
        return "STEP 1: TEMPLATES", { "walk onto templates: up to " .. max, "stack into one bigger spell" }, counter
    end

    -- Word tabs without a template: step 1 first.
    if not tpl then
        return "STEP 1: TEMPLATES", { "pick up a template first,", "from the templates tab" }
    end

    -- Word tabs with a template: step 2, fill the blanks.
    local open, needSpell, needCond = 0, false, false
    for _, b in ipairs(book:blanks()) do
        if not b.word then
            open = open + 1
            if b.type == "spell" then needSpell = true else needCond = true end
        end
    end
    local both = needSpell and needCond
    local l1, l2
    if (tab == "spell" and needSpell) or (tab == "condition" and needCond) then
        l1 = "walk onto " .. (tab == "spell" and "spells" or "conditions") .. " to fill"
        l2 = both and ("the rest: " .. (tab == "spell" and "conditions" or "spells") .. " tab") or "the blanks"
    else
        local need = needCond and "conditions" or "spells"
        l1 = both and "you need spells and" or ("you need " .. need .. ",")
        l2 = both and "conditions (other tabs)" or ("from the " .. need .. " tab")
    end
    return "STEP 2: FILL THE BLANKS", { l1, l2 }, open .. " blank" .. (open == 1 and "" or "s") .. " left"
end

local function drawTrainingPanel(game, x)
    local title, lines, counter = trainingGuide(game)
    love.graphics.setFont(fonts.small)
    setColor(C.template)
    love.graphics.print(title, x, 0)
    setColor(C.dim)
    for i, line in ipairs(lines) do
        love.graphics.print(line, x, i * 8)
    end
    -- Counter sits apart from the instructions, in brighter text.
    if counter then
        setColor(C.text)
        love.graphics.print(counter, x, 32)
    end
end

local function drawHud(game)
    setColor(C.bg)
    love.graphics.rectangle("fill", 0, 0, game.width, game.arena.top - WALL_RISE)
    drawPanel(game, 1, 4)
    if game.mode == "training" then
        drawTrainingPanel(game, game.width / 2 + 4)
    else
        drawPanel(game, 2, game.width / 2 + 4)
    end
end

local function drawBanner(game)
    local cx, cy = game.width / 2, game.height / 2
    if game.state == "countdown" then
        setColor(C.text)
        printCentered(tostring(math.ceil(game.timer)), fonts.big, cx, cy - 10)
    elseif game.state == "over" then
        setColor(C.bg, 0.7)
        love.graphics.rectangle("fill", 0, cy - 16, game.width, 32)
        local msg = game.winner == "draw" and "DRAW" or (game.winner == 1 and "BLUE WINS" or "RED WINS")
        setColor(C.text)
        printCentered(msg, fonts.big, cx, cy - 14)
        setColor(C.dim)
        printCentered("press R to restart", fonts.small, cx, cy + 4)
    end
end

---------------------------------------------------------------- entry

local function spawnPickups(game)
    for _, e in ipairs(game.wordfield.events) do
        if not seenPickups[e] then
            seenPickups[e] = true
            pickups[#pickups + 1] = { def = e.def, x = e.x, y = e.y, player = e.player, age = 0 }
        end
    end
end

function drawPickups()
    local f = fonts.small
    love.graphics.setFont(f)
    for _, pk in ipairs(pickups) do
        local k = pk.age / PICKUP_TIME
        local col = C.player[pk.player.id]
        -- Burst ring where the tile was.
        setColor(col, 1 - k)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", pk.x, pk.y - 6, 4 + k * 14)
        love.graphics.setLineWidth(1)
        -- Tile copy flying to the picker's head, shrinking.
        local e = 1 - (1 - k) * (1 - k)
        local tx, ty = pk.player.x, pk.player.y - 30
        local x = pk.x + (tx - pk.x) * e
        local y = (pk.y - 8) + (ty - (pk.y - 8)) * e
        local s = 1 - 0.6 * k
        local w, h = f:getWidth(pk.def.label) + 4, 9
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(s, s)
        setColor(col)
        love.graphics.rectangle("fill", -w / 2 - 1, -h / 2 - 1, w + 2, h + 2)
        setColor(typeColor(pk.def.type))
        love.graphics.rectangle("fill", -w / 2, -h / 2, w, h)
        setColor(C.bg)
        love.graphics.print(pk.def.label, -w / 2 + 2, -h / 2 - 1)
        love.graphics.pop()
    end
end

local function spawnFloaters(game)
    local t = game.data.tuning
    for _, b in ipairs(game.beams) do
        if not seenBeams[b] then
            seenBeams[b] = true
            local text, color
            if b.result == "hit" then
                text, color = "-" .. t.spells.attackDamage, C.hpText
                hurt[game:opponentOf(b.caster).id] = 0.4
            elseif b.result == "blocked" then
                text, color = "BLOCK", C.shield
            elseif b.result == "dodged" then
                text, color = "DODGE", C.text
            end
            if text then
                local target = game:opponentOf(b.caster)
                -- Stack texts that land together (a volley) so each is readable.
                local stack = 0
                for _, f in ipairs(floaters) do
                    if f.target == target and f.age < 0.3 then stack = stack + 1 end
                end
                floaters[#floaters + 1] = {
                    text = text, color = color, target = target, age = 0,
                    x = target.x, y = target.y - 30 - stack * 8,
                }
            end
        end
    end
end

function drawFloaters()
    local f = fonts.small
    love.graphics.setFont(f)
    for _, fl in ipairs(floaters) do
        local k = fl.age / FLOAT_TIME
        local alpha = k < 0.6 and 1 or (1 - (k - 0.6) / 0.4)
        local x = math.floor(fl.x - f:getWidth(fl.text) / 2)
        local y = math.floor(fl.y - fl.age * 12)
        setColor(C.bg, alpha)
        love.graphics.print(fl.text, x + 1, y + 1)
        setColor(fl.color, alpha)
        love.graphics.print(fl.text, x, y)
    end
end

function Render.update(dt, game)
    updateMovementFx(dt, game)
    spawnFloaters(game)
    spawnPickups(game)
    for i = #pickups, 1, -1 do
        pickups[i].age = pickups[i].age + dt
        if pickups[i].age >= PICKUP_TIME then table.remove(pickups, i) end
    end
    for i = #floaters, 1, -1 do
        floaters[i].age = floaters[i].age + dt
        if floaters[i].age >= FLOAT_TIME then table.remove(floaters, i) end
    end

    for k, p in ipairs(game.players) do
        hurt[k] = math.max(0, hurt[k] - dt)

        local tpl = game.spellbooks[k].template
        local level = tpl and tpl.level or lastLevel[k]
        if lastLevel[k] and level and level > lastLevel[k] then levelFlash[k] = 1 end
        lastLevel[k] = level
        levelFlash[k] = math.max(0, levelFlash[k] - dt * 2)
    end
end

function Render.draw(game, sprites, time)
    love.graphics.clear(C.bg)
    drawWorld(game, sprites, time)
    if game.mode == "training" then drawCategoryTabs(game) end
    drawHud(game)
    drawBanner(game)
end

return Render
