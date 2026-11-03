-- Wordcraft: entry point.
-- Rendering happens at a fixed low resolution, then gets scaled up by an
-- integer factor so pixels stay crisp.
--
-- Debug flags (after the game folder):
--   love . --selftest   love . --shot   love . --shot-training   love . --shot-select   love . --bot
--   lovec . --sim 400 | --sim 1m [--stats] [--workers 8] [--cap 300] [--p1 profile] [--p2 profile]
--     (bot vs bot balance run: a number of rounds, or minutes; --stats
--     rewrites docs/STATS.md. See docs/SIMULATION.md.)
-- The game opens on the character select screen (Esc in a match goes back
-- to it). Keys: F2 toggles the training room (Space switches its tiles), F3
-- hands P2 to the bot (or back), F5 reloads code and data.

local loadData = require("src.data")
local Bot = require("src.bot")
local Game = require("src.game")
local Render = require("src.render")
local Select = require("src.select")

local GAME_W, GAME_H = 320, 180

-- Left hand on WASD, right hand on the arrows; each player dashes with the
-- Shift key on their own side.
local CONTROLS = {
    { up = "w", down = "s", left = "a", right = "d", dash = "lshift" },
    { up = "up", down = "down", left = "left", right = "right", dash = "rshift" },
}

local canvas
local data
local game
local sprites = {}
local dashPressed = { false, false }
local time = 0
local shotAt -- --shot: capture the canvas at this time, then quit
local mode = "versus" -- F2 toggles the training room
local showcased = false
local screen = "select" -- "select" (character select) or "game"
local selectScreen      -- the Select while on that screen
-- Last choices on the select screen, kept for the session.
local setup = { characters = { "wizard", "wizard" }, control = { "human", "human" } }
local bots = {}         -- bots[k]: player k's bot when setup says "ai" (versus only)

local function makeBots()
    for k = 1, 2 do
        bots[k] = setup.control[k] == "ai" and Bot.new(k, math.random) or nil
    end
end

local function toggleBot()
    setup.control[2] = setup.control[2] == "ai" and "human" or "ai"
    makeBots()
    print("P2: " .. (bots[2] and "bot" or "human"))
end

local function newGame()
    game = Game.new(data, { width = GAME_W, height = GAME_H, rand = math.random, mode = mode,
                            characters = setup.characters })
    screen = "game"
    dashPressed = { false, false }
end

local function openSelect()
    selectScreen = Select.new(data.characters.list, setup)
    screen, mode = "select", "versus"
end

function love.load(args)
    math.randomseed(os.time())
    data = loadData(love.filesystem.read)

    args = args or {}
    for i, a in ipairs(args) do
        if a == "--sim" then
            local amount = args[i + 1] or ""
            local minutes = tonumber(amount:match("^([%d.]+)m$"))
            local opts = { minutes = minutes, rounds = not minutes and (tonumber(amount) or 200) or nil }
            for j = i + 1, #args do
                local key, value = args[j]:match("^%-%-(%w+)$"), args[j + 1]
                if key == "seed" or key == "cap" or key == "workers" then opts[key] = tonumber(value) end
                if key == "p1" or key == "p2" then opts[key] = value end
                if key == "stats" then
                    opts.writeStats = function(text)
                        local path = love.filesystem.getSource() .. "/docs/STATS.md"
                        local f = assert(io.open(path, "wb"))
                        f:write(text)
                        f:close()
                        print("stats: " .. path)
                    end
                end
            end
            opts.write = function(path, text)
                love.filesystem.write(path, text)
                print("  saved to " .. love.filesystem.getSaveDirectory() .. "/" .. path)
            end
            local lastShown = -1
            opts.progress = function(k, n, secondsLeft)
                local now = math.floor(love.timer.getTime())
                if now == lastShown and k ~= n then return end
                lastShown = now
                io.write(secondsLeft and string.format("\r  %d rounds, %ds left   ", k, secondsLeft)
                    or string.format("\r  %d / %d rounds   ", k, n))
                io.flush()
            end
            local Sim = require("src.sim")
            Sim.defaults(opts)
            local records, workers, seconds = require("src.simjobs").run(opts)
            print(string.format("\n  %d rounds on %d threads in %.0fs (%.1f rounds per minute)",
                #records, workers, seconds, #records / seconds * 60))
            Sim.finish(records, opts)
            love.event.quit(0)
            return
        end
    end

    for _, a in ipairs(args) do
        if a == "--selftest" then
            local ok = require("src.selftest").run(data)
            love.event.quit(ok and 0 or 1)
            return
        elseif a == "--shot-training" then
            shotAt, mode, showcased = 2.5, "training", "training"
        elseif a == "--shot-select" then
            shotAt, showcased = 0.5, "select"
        elseif a == "--shot" then
            shotAt = 3.85
        elseif a == "--bot" then
            setup.control[2] = "ai"
        end
    end

    love.graphics.setDefaultFilter("nearest", "nearest")
    canvas = love.graphics.newCanvas(GAME_W, GAME_H)
    Render.load()
    for _, name in ipairs({ "wizard_blue", "wizard_red", "dummy" }) do
        sprites[name] = love.graphics.newImage("assets/sprites/" .. name .. ".png")
        sprites[name .. "_cast"] = love.graphics.newImage("assets/sprites/" .. name .. "_cast.png")
        for f = 1, 4 do -- walk cycle (wizards only)
            local path = "assets/sprites/" .. name .. "_walk" .. f .. ".png"
            if love.filesystem.getInfo(path) then sprites[name .. "_walk" .. f] = love.graphics.newImage(path) end
        end
    end

    makeBots()
    if shotAt and showcased ~= "select" then newGame() else openSelect() end
end

local function readInput(k)
    local c = CONTROLS[k]
    local down = love.keyboard.isDown
    local x, y = 0, 0
    if down(c.left) then x = x - 1 end
    if down(c.right) then x = x + 1 end
    if down(c.up) then y = y - 1 end
    if down(c.down) then y = y + 1 end
    local input = { x = x, y = y, dash = dashPressed[k] }
    dashPressed[k] = false
    return input
end

function love.update(dt)
    dt = math.min(dt, 1 / 30) -- avoid huge steps after a window drag/stall
    time = time + dt
    if screen == "select" then
        if showcased == "select" then
            -- P1 confirmed, now setting up P2: AI, hovering the locked character.
            for _, action in ipairs({ "confirm", "up", "right", "down", "right" }) do selectScreen:press(1, action) end
            showcased = true
        end
        selectScreen:update(dt)
        if selectScreen.result then
            setup = selectScreen.result
            makeBots()
            newGame()
        end
        if shotAt and time >= shotAt then
            love.graphics.setCanvas(canvas)
            Render.drawSelect(selectScreen, sprites, time)
            love.graphics.setCanvas()
            canvas:newImageData():encode("png", "shot.png")
            print("screenshot: " .. love.filesystem.getSaveDirectory() .. "/shot.png")
            love.event.quit()
        end
        return
    end
    if not game then return end
    local inputs = {}
    for k = 1, 2 do
        inputs[k] = readInput(k) -- read anyway so a held dash doesn't carry over
        if bots[k] and game.mode == "versus" then inputs[k] = bots[k]:update(dt, game) end
    end
    game:update(dt, inputs)

    -- Screenshot sample scenes run between the game and render updates so
    -- render sees anything they inject (e.g. a pickup event).
    if showcased == "training" and time >= 2.35 then
        require("src.selftest").showcaseTraining(game)
        showcased = true
    end
    if shotAt and not showcased and game.state == "fight" then
        require("src.selftest").showcase(game)
        showcased = true
    end

    Render.update(dt, game)

    if shotAt and time >= shotAt then
        love.graphics.setCanvas(canvas)
        Render.draw(game, sprites, time)
        love.graphics.setCanvas()
        canvas:newImageData():encode("png", "shot.png")
        print("screenshot: " .. love.filesystem.getSaveDirectory() .. "/shot.png")
        love.event.quit()
    end
end

function love.draw()
    if not canvas then return end
    love.graphics.setCanvas(canvas)
    if screen == "select" then
        Render.drawSelect(selectScreen, sprites, time)
    else
        Render.draw(game, sprites, time)
    end
    love.graphics.setCanvas()

    -- Integer scale, centered (letterboxed).
    local ww, wh = love.graphics.getDimensions()
    local scale = math.max(1, math.floor(math.min(ww / GAME_W, wh / GAME_H)))
    local ox = math.floor((ww - GAME_W * scale) / 2)
    local oy = math.floor((wh - GAME_H * scale) / 2)

    love.graphics.clear(0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, ox, oy, 0, scale, scale)
end

-- Select screen: movement keys move the cursor, the dash key confirms.
local SELECT_ACTIONS = { up = "up", down = "down", left = "left", right = "right", dash = "confirm" }

function love.keypressed(key)
    if key == "f5" then love.event.quit("restart") end -- reloads code and data from disk
    if key == "f2" then
        if mode == "training" then
            openSelect()
        else
            mode = "training"
            newGame()
        end
        return
    end
    if screen == "select" then
        if key == "escape" then selectScreen:reset() end
        for k, c in ipairs(CONTROLS) do
            for name, action in pairs(SELECT_ACTIONS) do
                if key == c[name] then selectScreen:press(k, action) end
            end
        end
        return
    end
    if key == "escape" then
        openSelect()
        return
    end
    if key == "f3" then toggleBot() end
    if not game then return end
    for k, c in ipairs(CONTROLS) do
        if key == c.dash then dashPressed[k] = true end
    end
    if key == "r" and game.state == "over" then game:reset() end
    if key == "space" and game.mode == "training" then game:nextTrainingCategory() end
end
