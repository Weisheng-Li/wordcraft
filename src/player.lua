-- Player body: movement, dash, HP, and the status that spells change
-- (shield charges, accelerate). No drawing here; render.lua draws players.
-- Position (x, y) is the feet on the floor plane.
-- Tuning is read every frame (never cached) so it can be live-reloaded later.

local Player = {}
Player.__index = Player

-- character: an id under `characters` in tuning.json (default "wizard").
function Player.new(id, x, y, sprite, tuning, character)
    local self = setmetatable({}, Player)
    self.id = id
    self.sprite = sprite
    self.character = character or "wizard"
    self.x, self.y = x, y
    self.facing = 1            -- 1 = right, -1 = left (sprite flip only)
    self.aimX, self.aimY = 1, 0 -- last movement direction, used for dashing in place
    self.hp = self:maxHp(tuning)
    self.dashTime = 0          -- > 0 while dashing
    self.dashCooldown = 0
    self.dashX, self.dashY = 0, 0
    self.stillTime = 0
    self.knockTime = 0         -- > 0 while being pushed back by a hit
    self.knockX, self.knockY = 0, 0
    self.shield = 0            -- shield charges
    self.decayProgress = 0     -- lasting shields (optional): 0..1 toward losing the next charge
    self.accelerate = 0        -- accelerate stacks (each adds accelerateBonus)
    self.infiniteHp = false    -- training room: hits still land, HP never drops
    self.vx, self.vy = 0, 0    -- walking velocity
    self.parry = nil           -- Bulwark: { time, total, success } while the shield is raised
    self.healed = 0            -- HP healed so far (parry heal), read by render
    -- Per-frame events, read by conditions and cleared by Game at frame end.
    self.justDashed = false    -- the dash key started a dash (or a parry)
    return self
end

-- This character's rules (`characters.<id>` in tuning.json).
function Player:rules(tuning)
    return tuning.characters[self.character] or {}
end

-- Starting (and full) HP: per character, else tuning.player.hp.
function Player:maxHp(tuning)
    return self:rules(tuning).hp or tuning.player.hp
end

-- Seconds until the next shield charge decays at the current count, or nil
-- if this character's charges don't decay (or there are none).
function Player:shieldDecayLeft(tuning)
    local decay = self:rules(tuning).shieldDecay
    if not decay or self.shield <= 0 then return nil end
    return (1 - self.decayProgress) * decay / self.shield
end

function Player:moveSpeed(tuning)
    return self:rules(tuning).moveSpeed or tuning.player.moveSpeed
end

-- What the dash key does: "dash", or "parry" for the Bulwark.
function Player:special(tuning)
    return self:rules(tuning).special or "dash"
end

-- Full cooldown of the dash key (dash or parry), for the bar over the head.
function Player:specialCooldown(tuning)
    local r = self:rules(tuning)
    return r.special == "parry" and r.parry.cooldown or tuning.dash.cooldown
end

-- Can the dash key be used now?
function Player:canSpecial(tuning)
    return self.dashCooldown <= 0 and not self:isDashing() and not self.parry
end

-- Raise the shield: anything that lands in the next `parry.window` seconds
-- is parried. The cooldown starts now; a successful parry clears it.
function Player:startParry(tuning)
    local p = self:rules(tuning).parry
    self.parry = { time = p.window, total = p.window, success = false }
    self.dashCooldown = p.cooldown
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

    -- Parry window (the mage keeps walking with the shield up).
    if self.parry then
        self.parry.time = self.parry.time - dt
        if self.parry.time <= 0 then self.parry = nil end
    end

    -- Optional lasting shields (shieldLasts + shieldDecay, off for everyone
    -- now): charges decay one at a time, faster the more you
    -- hold. With n charges the next one goes after shieldDecay / n seconds
    -- (progress carries over, so gaining charges speeds up the current one).
    local decay = self:rules(t).shieldDecay
    if decay and self.shield > 0 then
        self.decayProgress = self.decayProgress + dt * self.shield / decay
        if self.decayProgress >= 1 then
            self.shield = self.shield - 1
            self.decayProgress = 0
        end
    else
        self.decayProgress = 0
    end

    if input.dash and self:canSpecial(t) then
        if self:special(t) == "parry" then
            self:startParry(t)
        else
            self.dashTime = t.dash.duration
            self.dashCooldown = t.dash.cooldown
            self.dashX, self.dashY = self.aimX, self.aimY
        end
        self.justDashed = true
    end

    local dx, dy
    if self:isDashing() then
        local speed = t.dash.distance / t.dash.duration
        local step = math.min(dt, self.dashTime)
        dx, dy = self.dashX * speed * step, self.dashY * speed * step
        self.dashTime = self.dashTime - dt
        moved = true
        if not self:isDashing() then
            -- Come out of the dash at walking speed instead of a dead stop.
            local walk = self:moveSpeed(t) * (1 + self.accelerate * t.spells.accelerateBonus)
            self.vx, self.vy = self.dashX * walk, self.dashY * walk
        end
    else
        local speed = self:moveSpeed(t)
        speed = speed * (1 + self.accelerate * t.spells.accelerateBonus)
        local tx, ty = ix * speed, iy * speed
        self:steer(tx, ty, speed, dt, t.movement)
        dx, dy = self.vx * dt, self.vy * dt
        moved = len > 0 or (self.vx * self.vx + self.vy * self.vy) > 1
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
        local hardX, hardY
        self.x, self.y, hardX, hardY = arena:moveBox(self.x, self.y - h / 2, dx, dy, w, h, t.movement.cornerNudge)
        self.y = self.y + h / 2
        -- A wall stops velocity on that axis, so we don't push into it.
        -- (Sliding around a corner keeps it.)
        if hardX then self.vx = 0 end
        if hardY then self.vy = 0 end
    end

    if moved then self.stillTime = 0 else self.stillTime = self.stillTime + dt end
end

-- Ease velocity toward the target (tx, ty) instead of snapping to it:
-- reach full speed in accelTime and stop in decelTime. Pushing against
-- the current motion drops it at once, so turning around feels like a
-- fresh start rather than a slow skid.
function Player:steer(tx, ty, speed, dt, m)
    local vx, vy = self.vx, self.vy
    local time
    if tx == 0 and ty == 0 then
        time = m.decelTime
    else
        if vx * tx + vy * ty < 0 then vx, vy = 0, 0 end
        time = m.accelTime
    end
    local rate = speed / math.max(time, 0.001) * dt
    local ex, ey = tx - vx, ty - vy
    local gap = math.sqrt(ex * ex + ey * ey)
    if gap <= rate then
        self.vx, self.vy = tx, ty
    else
        self.vx, self.vy = vx + ex / gap * rate, vy + ey / gap * rate
    end
end

-- Apply a laser hit coming from (fromX, fromY).
-- Returns "parried", "dodged", "blocked" or "hit". A parry (Bulwark,
-- shield raised) beats everything else: no damage, no charge used, and the
-- parry's cooldown is cleared. A real hit pushes the player straight away
-- from the shooter.
function Player:receiveHit(damage, fromX, fromY, tuning)
    if self.parry then
        -- Optional rewards for the first beam a parry stops: `shieldOnParry`
        -- shield charges (ordinary ones, ending with the effect window) and
        -- `healOnParry` HP (up to full).
        local gain = (self:rules(tuning).parry or {}).shieldOnParry or 0
        if not self.parry.success then
            self.shield = self.shield + gain
            local heal = math.min(self:rules(tuning).parry.healOnParry or 0, self:maxHp(tuning) - self.hp)
            self.hp = self.hp + heal
            self.healed = self.healed + heal -- running total, for the "+1" floater
        end
        self.parry.success = true
        self.dashCooldown = 0
        return "parried"
    end
    if self:isInvulnerable() then return "dodged" end
    if self.shield > 0 then
        self.shield = self.shield - 1
        return "blocked"
    end
    if not self.infiniteHp then self.hp = math.max(0, self.hp - damage) end

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
end

return Player
