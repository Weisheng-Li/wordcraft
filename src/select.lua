-- Select: the character select screen (docs/DESIGN.md §17). Pure logic;
-- render.lua draws it and main.lua feeds it key presses.
--
-- Each panel has two rows: 1 = control (human / AI), 2 = character.
-- Your keys drive your own panel until it's confirmed, then the other
-- panel until that one is confirmed too.

local Select = {}
Select.__index = Select

Select.START_DELAY = 0.4 -- both confirmed -> match starts after this
Select.REFUSE_TIME = 0.4 -- "coming soon" flash after confirming a locked character

-- characters: data.characters.list
-- setup (optional): { characters = { id, id }, control = { "human"|"ai", ... } }
function Select.new(characters, setup)
    local self = setmetatable({}, Select)
    self.characters = characters
    self.panels = {}
    for k = 1, 2 do
        local pick = 1
        for i, c in ipairs(characters) do
            if setup and setup.characters and setup.characters[k] == c.id then pick = i end
        end
        self.panels[k] = {
            pick = pick,
            control = setup and setup.control and setup.control[k] or "human",
            row = 2,
            ready = false,
            refused = 0,
        }
    end
    self.timer = nil  -- counts up once both are confirmed
    self.result = nil -- set when the match should start
    return self
end

-- Which panel keyboard k drives right now (nil once both are confirmed).
function Select:panelFor(k)
    if not self.panels[k].ready then return k end
    if not self.panels[3 - k].ready then return 3 - k end
end

function Select:character(k)
    return self.characters[self.panels[k].pick]
end

-- action: "up" | "down" | "left" | "right" | "confirm", from keyboard k.
function Select:press(k, action)
    local target = self:panelFor(k)
    if not target then return end
    local p = self.panels[target]
    if action == "up" or action == "down" then
        p.row = 3 - p.row
    elseif action == "left" or action == "right" then
        if p.row == 1 then
            p.control = p.control == "human" and "ai" or "human"
        else
            local n = #self.characters
            p.pick = (p.pick - 1 + (action == "right" and 1 or -1)) % n + 1
        end
    elseif action == "confirm" then
        if self:character(target).available then
            p.ready = true
        else
            p.refused = Select.REFUSE_TIME
        end
    end
end

function Select:anyReady()
    return self.panels[1].ready or self.panels[2].ready
end

-- Esc: un-confirm both panels. Does nothing if neither is confirmed.
function Select:reset()
    for _, p in ipairs(self.panels) do p.ready = false end
    self.timer = nil
end

function Select:update(dt)
    for _, p in ipairs(self.panels) do p.refused = math.max(0, p.refused - dt) end
    if not (self.panels[1].ready and self.panels[2].ready) then return end
    self.timer = (self.timer or 0) + dt
    if self.timer >= Select.START_DELAY and not self.result then
        self.result = {
            characters = { self:character(1).id, self:character(2).id },
            control = { self.panels[1].control, self.panels[2].control },
        }
    end
end

return Select
