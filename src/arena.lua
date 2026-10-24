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

-- Move a box by (dx, dy), one axis at a time, stopping at walls.
-- Sub-steps keep fast moves (dashes) from tunnelling through a tile.
-- Returns new x, y and whether movement was blocked.
function Arena:moveBox(x, y, dx, dy, w, h)
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / 2))
    local sx, sy = dx / steps, dy / steps
    local blocked = false
    for _ = 1, steps do
        if sx ~= 0 then
            if self:boxHitsWall(x + sx, y, w, h) then blocked = true; sx = 0
            else x = x + sx end
        end
        if sy ~= 0 then
            if self:boxHitsWall(x, y + sy, w, h) then blocked = true; sy = 0
            else y = y + sy end
        end
    end
    return x, y, blocked
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
