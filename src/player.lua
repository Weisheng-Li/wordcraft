-- Player body: movement, dash, HP, and the status that spells change
-- (shield charges, accelerate). No drawing here; render.lua draws players.
-- Position (x, y) is the feet on the floor plane.
-- Tuning is read every frame (never cached) so it can be live-reloaded later.

local Player = {}
Player.__index = Player

function Player.new(id, x, y, sprite, tuning)
    local self = setmetatable({}, Player)
    self.id = id
    self.sprite = sprite
    self.x, self.y = x, y
    self.facing = 1            -- 1 = right, -1 = left (sprite flip only)
    self.aimX, self.aimY = 1, 0 -- last movement direction, used for dashing in place
    self.hp = tuning.player.hp
    self.dashTime = 0          -- > 0 while dashing
    self.dashCooldown = 0
    self.dashX, self.dashY = 0, 0
    self.stillTime = 0
    self.knockTime = 0         -- > 0 while being pushed back by a hit
    self.knockX, self.knockY = 0, 0
    self.shield = 0            -- shield charges
    self.accelerate = 0        -- accelerate stacks (each adds accelerateBonus)
    self.infiniteHp = false    -- training room: hits still land, HP never drops
    -- Per-frame events, read by conditions and cleared by Game at frame end.
    self.justDashed = false
    self.justHit = false
    return self
end

function Player:isDashing()
    return self.dashTime > 0
end

function Player:isInvulnerable()
    return self:isDashing()
end

-- input: { x = -1..1, y = -1..1, dash = bool (pressed this frame) }
function Player:update(dt, input, tuning, arena)
    local t = tuning
    local w, h = t.player.hitboxW, t.player.hitboxH
    local moved = false

    self.dashCooldown = math.max(0, self.dashCooldown - dt)

    local ix, iy = input.x, input.y
    local len = math.sqrt(ix * ix + iy * iy)
    if len > 0 then
        ix, iy = ix / len, iy / len
        self.aimX, self.aimY = ix, iy
        if ix ~= 0 then self.facing = ix > 0 and 1 or -1 end
    end

    if input.dash and self.dashCooldown <= 0 and not self:isDashing() then
        self.dashTime = t.dash.duration
        self.dashCooldown = t.dash.cooldown
        self.dashX, self.dashY = self.aimX, self.aimY
        self.justDashed = true
    end

    local dx, dy
    if self:isDashing() then
        local speed = t.dash.distance / t.dash.duration
        local step = math.min(dt, self.dashTime)
        dx, dy = self.dashX * speed * step, self.dashY * speed * step
        self.dashTime = self.dashTime - dt
        moved = true
    else
        local speed = t.player.moveSpeed
        speed = speed * (1 + self.accelerate * t.spells.accelerateBonus)
        dx, dy = ix * speed * dt, iy * speed * dt
        moved = len > 0
    end

    -- Hit knockback adds on top of walking/dashing. It doesn't count as
    -- "moving" for the stand-still condition: the player didn't choose it.
    if self.knockTime > 0 then
        local speed = t.hit.knockbackDistance / t.hit.knockbackDuration
        local step = math.min(dt, self.knockTime)
        dx = dx + self.knockX * speed * step
        dy = dy + self.knockY * speed * step
        self.knockTime = self.knockTime - dt
    end

    if dx ~= 0 or dy ~= 0 then
        self.x, self.y = arena:moveBox(self.x, self.y - h / 2, dx, dy, w, h)
        self.y = self.y + h / 2
    end

    if moved then self.stillTime = 0 else self.stillTime = self.stillTime + dt end
end

-- Apply a laser hit coming from (fromX, fromY).
-- Returns "dodged", "blocked" or "hit". A real hit also pushes the player
-- straight away from the shooter.
function Player:receiveHit(damage, fromX, fromY, tuning)
    if self:isInvulnerable() then return "dodged" end
    if self.shield > 0 then
        self.shield = self.shield - 1
        return "blocked"
    end
    if not self.infiniteHp then self.hp = math.max(0, self.hp - damage) end
    self.justHit = true

    local dx, dy = self.x - fromX, self.y - fromY
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
        self.knockX, self.knockY = dx / len, dy / len
        self.knockTime = tuning.hit.knockbackDuration
    end
    return "hit"
end

function Player:clearFrameEvents()
    self.justDashed = false
    self.justHit = false
end

return Player
