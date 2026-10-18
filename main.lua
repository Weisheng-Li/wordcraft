-- Wordcraft: entry point.
-- Rendering happens at a fixed low resolution, then gets scaled up by an
-- integer factor so pixels stay crisp.

local json = require("src.json")

local GAME_W, GAME_H = 320, 180

local canvas
local words = {}

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    canvas = love.graphics.newCanvas(GAME_W, GAME_H)

    local raw = love.filesystem.read("data/words.json")
    words = json.decode(raw).words
end

function love.update(dt)
end

local function drawGame()
    love.graphics.clear(0.08, 0.06, 0.14)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("WORDCRAFT", 8, 8)
    love.graphics.print(#words .. " words loaded", 8, 24)
end

function love.draw()
    love.graphics.setCanvas(canvas)
    drawGame()
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
end
