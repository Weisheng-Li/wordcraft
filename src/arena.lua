-- Arena: tile grid of walls, box-vs-wall collision, line of sight, random
-- open spots. Pure logic; render.lua draws it.
-- World space is game pixels. The grid starts at (0, top).

local Arena = {}
Arena.__index = Arena

function Arena.new(def, width, height)
    local self = setmetatable({}, Arena)
    self.tile = def.tileSize
    self.top = def.top
    self.cols = #def.rows[1]
    self.rows = #def.rows
    self.left, self.right = 0, width
    self.bottom = math.min(height, self.top + self.rows * self.tile)
    self.solid = {}
    self.starts = {}
    for r, line in ipairs(def.rows) do
        self.solid[r] = {}
        for c = 1, #line do
            local ch = line:sub(c, c)
            self.solid[r][c] = (ch == "#")
            if ch == "1" or ch == "2" then
                local x, y = self:tileCenter(c, r)
                self.starts[tonumber(ch)] = { x = x, y = y }
            end
        end
    end
    return self
end

function Arena:tileCenter(c, r)
    return (c - 0.5) * self.tile, self.top + (r - 0.5) * self.tile
end

function Arena:tileAt(x, y)
    return math.floor(x / self.tile) + 1, math.floor((y - self.top) / self.tile) + 1
end

-- Outside the grid counts as solid, so the grid edge is the arena boundary.
function Arena:isSolid(c, r)
    if c < 1 or c > self.cols or r < 1 or r > self.rows then return true end
    return self.solid[r][c]
end

function Arena:isSolidAt(x, y)
    return self:isSolid(self:tileAt(x, y))
end

-- Does an axis-aligned box centred on (x, y) overlap any wall?
function Arena:boxHitsWall(x, y, w, h)
    local x1, y1 = x - w / 2, y - h / 2
    local x2, y2 = x + w / 2 - 0.001, y + h / 2 - 0.001
    local c1, r1 = self:tileAt(x1, y1)
    local c2, r2 = self:tileAt(x2, y2)
    for r = r1, r2 do
        for c = c1, c2 do
            if self:isSolid(c, r) then return true end
        end
    end
    return false
end

-- If a box at (x, y) can't move by `step` along one axis, look for the
-- nearest gap within `nudge` pixels along the other axis and return the
-- sideways shift toward it (at most |step| per call), or 0. A tie (open on
-- both sides equally) gives 0: that's walking into the middle of a wall.
local function cornerShift(self, x, y, w, h, step, nudge, alongX)
    for off = 1, nudge do
        local freeA, freeB
        if alongX then
            freeA = not self:boxHitsWall(x + step, y - off, w, h) and not self:boxHitsWall(x, y - off, w, h)
            freeB = not self:boxHitsWall(x + step, y + off, w, h) and not self:boxHitsWall(x, y + off, w, h)
        else
            freeA = not self:boxHitsWall(x - off, y + step, w, h) and not self:boxHitsWall(x - off, y, w, h)
            freeB = not self:boxHitsWall(x + off, y + step, w, h) and not self:boxHitsWall(x + off, y, w, h)
        end
        if freeA ~= freeB then
            local amount = math.min(off, math.abs(step))
            return freeA and -amount or amount
        elseif freeA then
            return 0
        end
    end
    return 0
end

-- Move a box by (dx, dy), one axis at a time, stopping at walls.
-- Sub-steps keep fast moves (dashes) from tunnelling through a tile.
-- With `nudge` > 0, clipping a wall corner by up to that many pixels
-- slides the box around it instead of stopping (corner correction).
-- Returns the new x, y and whether each axis was hard-blocked (stopped
-- with no way around).
function Arena:moveBox(x, y, dx, dy, w, h, nudge)
    nudge = nudge or 0
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / 2))
    local sx, sy = dx / steps, dy / steps
    local hardX, hardY = false, false
    for _ = 1, steps do
        if sx ~= 0 then
            if not self:boxHitsWall(x + sx, y, w, h) then
                x = x + sx
            else
                local shift = nudge > 0 and cornerShift(self, x, y, w, h, sx, nudge, true) or 0
                if shift ~= 0 then y = y + shift else hardX = true; sx = 0 end
            end
        end
        if sy ~= 0 then
            if not self:boxHitsWall(x, y + sy, w, h) then
                y = y + sy
            else
                local shift = nudge > 0 and cornerShift(self, x, y, w, h, sy, nudge, false) or 0
                if shift ~= 0 then x = x + shift else hardY = true; sy = 0 end
            end
        end
    end
    return x, y, hardX, hardY
end

-- Walk the floor-plane segment; returns true if clear, or false plus the
-- point where it first enters a wall.
function Arena:lineOfSight(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / 2))
    for i = 1, steps do
        local t = i / steps
        local x, y = x1 + dx * t, y1 + dy * t
        if self:isSolidAt(x, y) then return false, x, y end
    end
    return true
end

-- Random point on an open floor tile that satisfies accept(x, y).
-- Returns nil if nothing fits after a bounded number of tries.
function Arena:randomOpenPoint(rand, accept)
    for _ = 1, 200 do
        local c, r = rand(1, self.cols), rand(1, self.rows)
        if not self:isSolid(c, r) then
            local x, y = self:tileCenter(c, r)
            if accept(x, y) then return x, y end
        end
    end
    return nil
end

return Arena
