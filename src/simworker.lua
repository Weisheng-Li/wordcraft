-- Simulation worker thread (started by src/simjobs.lua, one per CPU core).
-- Takes round numbers from `jobs`, plays each round and pushes its stats
-- record to `results` as text. Round number 0 means stop.

require("love.filesystem")
local Sim = require("src.sim")
local loadData = require("src.data")

local jobs, results, p1, p2, cap, seed, c1, c2 = ...
local opts = { p1 = p1 ~= "" and p1 or nil, p2 = p2 ~= "" and p2 or nil, cap = cap, seed = seed,
               c1 = c1 ~= "" and c1 or nil, c2 = c2 ~= "" and c2 or nil }
local data = loadData(love.filesystem.read)

while true do
    local round = jobs:demand()
    if round == 0 then break end
    results:push(Sim.encode(Sim.playRound(data, round, opts)))
end
