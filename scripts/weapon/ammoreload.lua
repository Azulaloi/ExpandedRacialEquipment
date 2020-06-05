require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Reload for use with gunfireammo as primary
-- read and write parameter "rounds" as ammo
-- use Weapon:ammoCall(x) to alert x slot ability to update ammo


Reload = WeaponAbility:new()

function Reload:init()
	sb.logInfo("reload init")
    self.cooldownTimer = self.fireTime
	
	self.rounds = config.getParameter("rounds", 6)
	self.maxRounds = config.getParameter("maxRounds", 3)
	self.cursorAmmo = config.getParameter("cursorAmmo", false)
	self.cursorDir = config.getParameter("cursorDir", "/cursors/6/azreticle")
	
	--self.reloadStanceChain = config.getParameter("reloadStanceChain")
	--self.reloadStance = self.reloadStanceChain
	
	--self.terminateIteration = config.getParameter("terminateIteration")
	--self.reloadIteration = config.getParameter("reloadIteration")
end

function Reload:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
	
	if self.fireMode == (self.activatingFireMode or self.abilitySlot)
          and not self.weapon.currentAbility
          and self.cooldownTimer == 0
          and not status.resourceLocked("energy") then
		
		--self:setState(self.reloadState)
		self:setState(self.animArbitrary, 0)
    end
end

function Reload:cooldown()
    self.weapon:setStance(self.stances.cooldown)
    self.weapon:updateAim()

    local progress = 0
    util.wait(self.stances.cooldown.duration, function()
        local from = self.stances.cooldown.weaponOffset or {0,0}
        local to = self.stances.idle.weaponOffset or {0,0}
        self.weapon.weaponOffset = {interp.linear(progress, from[1], to[1]), interp.linear(progress, from[2], to[2])}

        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.weaponRotation, self.stances.idle.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(progress, self.stances.cooldown.armRotation, self.stances.idle.armRotation))

        progress = math.min(1.0, progress + (self.dt / self.stances.cooldown.duration))
    end)
end

function Reload:reloadState()
	self.weapon:setStance(self.stances.fire)
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self:doReload(1, false)
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function Reload:doReload(amount, replace)
	local toReload
	if amount then
		toReload = amount 
	else 
		toReload = self.maxRounds 
	end
	
	if not replace then
		toReload = config.getParameter("rounds") + toReload
	end
	
	--add option for overloading
	if toReload > self.maxRounds then toReload = self.maxRounds end
	
	activeItem.setInstanceValue("rounds", toReload)
	self:reloadFx()
	self.weapon:ammoCall(1)
end

function Reload:reloadFx()
	animator.playSound("reload")
end

function Reload:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
    local params = sb.jsonMerge(self.projectileParameters, projectileParams or {})
    params.power = self:damagePerShot()
    params.powerMultiplier = activeItem.ownerPowerMultiplier()
    params.speed = util.randomInRange(params.speed)

    if not projectileType then
        projectileType = self.projectileType
    end
    if type(projectileType) == "table" then
        projectileType = projectileType[math.random(#projectileType)]
    end

    local projectileId = 0
    for i = 1, (projectileCount or self.projectileCount) do
        if params.timeToLive then
            params.timeToLive = util.randomInRange(params.timeToLive)
        end
        projectileId = world.spawnProjectile(
            projectileType,
            firePosition or self:firePosition(),
            activeItem.ownerEntityId(),
            self:aimVector(inaccuracy or self.inaccuracy),
            false,
            params
        )
    end

    return projectileId
end

function Reload:firePosition()
    --return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
    
	
	return vec2.add(mcontroller.position(), activeItem.handPosition(self.ejectOffset))
	
	--animator.partPoint(string partname, string propertyname)
	--this one applies all transforms
	--return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint())
end

function Reload:aimVector(inaccuracy)
    local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
    aimVector[1] = aimVector[1] * mcontroller.facingDirection()
    return aimVector
end

function Reload:energyPerShot()
    return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end

-- in case I want to add a gun that ejects giant shells that do damage idk lmao
function Reload:damagePerShot()
    return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount
end

function Reload:uninit()

end

function Reload:animArbitrary(iter)
	local stanceIn = "anim" .. tostring(iter)

	local terminateFlag = iter == self.terminateIteration
	
	local stanceOut
	if not terminateFlag then
		stanceOut = "anim" .. tostring(iter + 1)
	else stanceOut = "idle" end
	
	self.weapon:setStance(self.stances[stanceIn])
	
	local delta = 0
    util.wait(self.stances[stanceIn].duration, function()
        local alpha = self.stances[stanceIn].weaponOffset or {0,0}
        local beta = self.stances[stanceOut].weaponOffset or {0,0}

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances[stanceIn].weaponRotation, self.stances[stanceOut].weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances[stanceIn].armRotation, self.stances[stanceOut].armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances[stanceIn].duration))
    end)
	
	if iter == self.reloadIteration then
		self:doReload(6, true)
		
		-- TODO: ejection status should be stored in weapon like rounds
		-- such that one cannot anim cancel between ejection and reload
		-- and just spew ejection projectiles without reloading
		if self.eject then
			self:fireProjectile()
		end
	end
	
	if not terminateFlag then
		self:setState(self.animArbitrary, iter + 1)
	end
end