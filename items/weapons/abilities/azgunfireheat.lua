require "/scripts/util.lua"
require "/scripts/interp.lua"

GunFire = WeaponAbility:new()

function GunFire:init()
    self.weapon:setStance(self.stances.idle)

	--if not pcall(self.checkWep()) then
	--	sb.logWarn('GunFireAmmo initialized to incorrect weapon.lua, will not function correctly')
	--end
	
    self.cooldownTimer = self.fireTime

    self.weapon.onLeaveAbility = function()
        self.weapon:setStance(self.stances.idle)
    end
	
	self.heat = config.getParameter("heat", 0)
	self.maxHeat = config.getParameter("maxHeat", 100)
	self.heatPerShot = config.getParameter("heatPerShot", 5)
	self.heatWait = config.getParameter("heatWait", 2)
	self.coolSpeed = config.getParameter("heatCoolSpeed", 35)
	self.coolTimer = 0
	
	self.cursorAmmo = config.getParameter("cursorAmmo", false)
	self.cursorDir = config.getParameter("cursorDir", "/cursors/100/azreticle")
	
	self:cursorUpdate()
end

function GunFire:checkWep()
	return self.weapon:checkAz()
	--if self.weapon:checkAz() then
	--	return true else return false 
	--end
end

function GunFire:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
	
	self.coolTimer = math.max(0, self.coolTimer - self.dt)
	if self.coolTimer <= 0 then
		self:cycleCool(dt)
	end

    if animator.animationState("firing") ~= "fire" then
        animator.setLightActive("muzzleFlash", false)
    end
	
    if self.fireMode == (self.activatingFireMode or self.abilitySlot)
            and not self.weapon.currentAbility
            and self.cooldownTimer == 0
            and not status.resourceLocked("energy")
            and not world.lineTileCollision(mcontroller.position(), self:firePosition()) then
			
		--if shiftHeld then
		--	self:setState(self.reload)
		--else
		if self.heat >= self.maxHeat then
			self:setState(self.click)
        elseif self.fireType == "auto" and status.overConsumeResource("energy", self:energyPerShot()) then
            self:setState(self.auto)
        elseif self.fireType == "burst" then
            self:setState(self.burst)
        end
    end
end

function GunFire:ammoCall()
	--sb.logInfo("ammocall received by primary")
	self.rounds = config.getParameter("rounds", 6)
	self:cursorUpdate()
end

function GunFire:auto()
    self.weapon:setStance(self.stances.fire)

    self:fireProjectile()
    self:muzzleFlash()

    if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end

    self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function GunFire:burst()
    self.weapon:setStance(self.stances.fire)

    local shots = self.burstCount
    while shots > 0 and status.overConsumeResource("energy", self:energyPerShot()) do
        self:fireProjectile()
        self:muzzleFlash()
        shots = shots - 1

        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.armRotation))

        util.wait(self.burstTime)
    end

    self.cooldownTimer = (self.fireTime - self.burstTime) * self.burstCount
end

function GunFire:cooldown()
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

function GunFire:click()
	self.weapon:setStance(self.stances.fire)

	self:clickFx()
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function GunFire:reload()
	self.weapon:setStance(self.stances.fire)

	self:reloadFx()
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self.rounds = self.maxRounds
	self:cursorUpdate()
	activeItem.setInstanceValue("rounds", self.rounds)
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function GunFire:clickFx()
	animator.playSound("click")
end

function GunFire:reloadFx()
	animator.playSound("reload")
end

function GunFire:muzzleFlash()
    animator.setPartTag("muzzleFlash", "variant", math.random(1, 3))
    animator.setAnimationState("firing", "fire")
    animator.burstParticleEmitter("muzzleFlash")
    animator.playSound("fire")

    animator.setLightActive("muzzleFlash", true)
end

function GunFire:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
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
		
		if projectileId then self:cycle() end
    end

    if self.weapon.recoilToggle then
        self.weapon:recoil({
            (math.random(self.recoilXAlpha) - self.recoilXBeta) / self.recoilXDividend,
            (math.random(self.recoilYAlpha) - self.recoilYBeta) / self.recoilYDividend})
    end

    return projectileId
end

function GunFire:cycle() 
	local heatIn = self.heat + self.heatPerShot
	if heatIn > self.maxHeat then
		heatIn = self.maxHeat end
	self.heat = heatIn
	self.coolTimer = self.heatWait

	
	self:cursorUpdate()
	--activeItem.setInstanceValue("rounds", self.rounds)
end

function GunFire:cycleCool(dt)
	self.heat = math.max(0, self.heat - self.coolSpeed * dt)
	self:cursorUpdate()
end

function GunFire:cursorUpdate()
	if self.cursorAmmo then
		--sb.logInfo("cursorUpdate: " .. tostring(self.heat))
		activeItem.setCursor(self.cursorDir .. (math.max(0, math.ceil(self.heat))) .. ".cursor")
	end
end

function GunFire:firePosition()
    return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
end

function GunFire:aimVector(inaccuracy)
    local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
    aimVector[1] = aimVector[1] * mcontroller.facingDirection()
    return aimVector
end

function GunFire:energyPerShot()
    return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end

function GunFire:damagePerShot()
    return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount
end

function GunFire:uninit()
    --local id = self.recoilId
    --if id then
    --  if world.entityExists(id) then
    --    world.sendEntityMessage(id, "return")
    --  end
    --end
end


