-- Runs simulation rounds on worker threads (src/simworker.lua), one per
-- CPU core by default, and returns all rounds' records for Sim.finish.
-- Stops after `opts.rounds` rounds, or once `opts.minutes` have passed
-- (rounds already being played still finish).

local Sim = require("src.sim")

local SimJobs = {}

-- opts: { rounds | minutes, workers, p1, p2, c1, c2, cap, seed, progress = fn(done, total, secondsLeft) }
function SimJobs.run(opts)
    local workers = opts.workers or love.system.getProcessorCount()
    if opts.rounds then workers = math.min(workers, opts.rounds) end
    local jobs, results = love.thread.newChannel(), love.thread.newChannel()
    local threads = {}
    for i = 1, workers do
        threads[i] = love.thread.newThread("src/simworker.lua")
        threads[i]:start(jobs, results, opts.p1 or "", opts.p2 or "", opts.cap, opts.seed, opts.c1 or "", opts.c2 or "")
    end

    local start = love.timer.getTime()
    local deadline = opts.minutes and start + opts.minutes * 60
    local sent, records = 0, {}
    local function more()
        if deadline then return love.timer.getTime() < deadline end
        return sent < opts.rounds
    end
    local function send()
        sent = sent + 1
        jobs:push(sent)
    end

    for _ = 1, workers do
        if more() then send() end
    end
    while #records < sent do
        local text = results:demand(1)
        if text then
            records[#records + 1] = Sim.decode(text)
            if more() then send() end
            if opts.progress then
                opts.progress(#records, opts.rounds, deadline and math.max(0, deadline - love.timer.getTime()))
            end
        else
            for _, t in ipairs(threads) do
                local err = t:getError()
                if err then error("simulation worker: " .. err) end
            end
        end
    end

    for _ = 1, workers do jobs:push(0) end
    for _, t in ipairs(threads) do t:wait() end
    return records, workers, love.timer.getTime() - start
end

return SimJobs
