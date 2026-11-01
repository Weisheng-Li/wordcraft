-- All game data in one table, from data/*.json. `read(path)` returns a
-- file's text (love.filesystem.read, both in the game and in simulation
-- worker threads). Tuning lives here and is read every frame, so a future
-- playtest mode can reload it in place.

local json = require("src.json")

return function(read)
    local function load(path) return json.decode(read(path)) end
    local words = load("data/words.json").words
    local byId, byType = {}, {}
    for _, w in ipairs(words) do
        byId[w.id] = w
        byType[w.type] = byType[w.type] or {}
        table.insert(byType[w.type], w)
    end
    return {
        tuning = load("data/tuning.json"),
        arena = load("data/arena.json"),
        templates = load("data/templates.json").templates,
        training = load("data/training.json"),
        words = { list = words, byId = byId, byType = byType },
    }
end
