-- Wordcraft: entry point.
-- Rendering happens at a fixed low resolution, then gets scaled up by an
-- integer factor so pixels stay crisp.
--
-- Debug flags (after the game folder):
--   love . --selftest   love . --shot   love . --shot-training
-- Keys: F2 toggles the training room (Space switches its tiles), F5 reloads code and data.

local json = require("src.json")
local Game = require("src.game")
local Render = require("src.render")

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

local function loadJson(path)
    return json.decode(love.filesystem.read(path))
end

-- All game data in one table. Tuning lives here and is read every frame,
-- so a future playtest mode can reload it in place.
local function loadData()
    local words = loadJson("data/words.json").words
    local byId, byType = {}, {}
    for _, w in ipairs(words) do
        byId[w.id] = w
        byType[w.type] = byType[w.type] or {}
        table.insert(byType[w.type], w)
    end
    return {
        tuning = loadJson("data/tuning.json"),
        arena = loadJson("data/arena.json"),
        templates = loadJson("data/templates.json").templates,
        training = loadJson("data/training.json"),
        words = { list = words, byId = byId, byType = byType },
    }
end

local function newGame()
    game = Game.new(data, { width = GAME_W, height = GAME_H, rand = math.random, mode = mode })
end

function love.load(args)
    math.randomseed(os.time())
    data = loadData()

    for _, a in ipairs(args or {}) do
        if a == "--selftest" then
            local ok = require("src.selftest").run(data)
            love.event.quit(ok and 0 or 1)
            return
        elseif a == "--shot-training" then
            shotAt, mode, showcased = 2.5, "training", "training"
        elseif a == "--shot" then
            shotAt = 3.85
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

    newGame()
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
    if not game then return end
    dt = math.min(dt, 1 / 30) -- avoid huge steps after a window drag/stall
    time = time + dt
    game:update(dt, { readInput(1), readInput(2) })

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
    if not game then return end
    love.graphics.setCanvas(canvas)
    Render.draw(game, sprites, time)
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

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "f5" then love.event.quit("restart") end -- reloads code and data from disk
    if key == "f2" then
        mode = (mode == "versus") and "training" or "versus"
        newGame()
        return
    end
    if not game then return end
    for k, c in ipairs(CONTROLS) do
        if key == c.dash then dashPressed[k] = true end
    end
    if key == "r" and game.state == "over" then game:reset() end
    if key == "space" and game.mode == "training" then game:nextTrainingCategory() end
end
