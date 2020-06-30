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
	
	self.venting = false
	
	self.heat = config.getParameter("heat", 0)
	--self.heatMax = config.getParameter("heatMax", 200)
	--self.heatPerShot = config.getParameter("heatPerShot", 5)
	--self.heatWait = config.getParameter("heatWait", 2)
	--self.heatCoolSpeed = config.getParameter("heatheatCoolSpeed", 35)
	self.coolTimer = 0
	
	self:cursorInit(config.getParameter("cursorMode", "none"))
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
	
	local overheated = (self.heat >= self.heatMax)
	
    if self.fireMode == (self.activatingFireMode or self.abilitySlot)
            and not self.weapon.currentAbility
            and self.cooldownTimer == 0
            and not status.resourceLocked("energy")
            and not world.lineTileCollision(mcontroller.position(), self:firePosition()) 
			and not overheated then

		if self.fireType == "auto" and status.overConsumeResource("energy", self:energyPerShot()) then
			self:setState(self.auto)
		elseif self.fireType == "burst" then
			self:setState(self.burst)
		end
    end
	
	if overheated then
		self:setState(self.overheat, 0)
	end
	
	self:updateDebug()
end

function GunFire:updateDebug()
	local heatPerc = (self.heat / self.heatMax) * 100
	world.debugText(sb.print("Heat: " .. self.heat), vec2.add(mcontroller.position(), {1, 2}), "green")
	world.debugText(sb.print("Perc: " .. tostring(heatPerc)), vec2.add(mcontroller.position(), {1, 2.5}), "green")
	world.debugText(sb.print("Vent: " .. tostring(self.venting)), vec2.add(mcontroller.position(), {1, 3}), "green")
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

function GunFire:overheat(iter)
	local stanceIn = "overheat" .. tostring(iter)
	
	local terminateFlag = iter == self.terminateIteration
	
	local stanceOut
	if not terminateFlag then
		stanceOut = "overheat" .. tostring(iter + 1)
	else stanceOut = "idle" end
	
	self.weapon:setStance(self.stances[stanceIn])
	
	if iter == self.ventIteration then
		animator.setParticleEmitterActive("vent", true)
		self.venting = true
	end
	
	local delta = 0
    util.wait(self.stances[stanceIn].duration, function()
        local alpha = self.stances[stanceIn].weaponOffset or {0,0}
        local beta = self.stances[stanceOut].weaponOffset or {0,0}

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances[stanceIn].weaponRotation, self.stances[stanceOut].weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances[stanceIn].armRotation, self.stances[stanceOut].armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances[stanceIn].duration))
    end)

	animator.setParticleEmitterActive("vent", false)
	self.venting = false
	
	if not terminateFlag then
		self:setState(self.overheat, iter + 1)
	end
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
	self:playSoundSafe("click")
end

function GunFire:reloadFx()
	self:playSoundSafe("reload")
end

function GunFire:playSoundSafe(sound, loopsIn)
	-- why do I have to do this myself
	-- this would still break if you pass non-string
	
	-- have to tostring item.name or else "attempt to concatenate function value" - but why?
	-- what does that mean? docs says item.name is type string. what is a function value? isnt tostring a function?
	-- lua pls
	
	local loops = loopsIn or 0
	if animator.hasSound(sound) then
		animator.playSound(sound, loops)
	else 
		sb.logWarn("azgunfireheat: Item <" .. tostring(item.name)
		.. "> tried to play undefined sound <" .. sound .. ">") 
	end
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
	if heatIn > self.heatMax then
		heatIn = self.heatMax end
	self.heat = heatIn
	self.coolTimer = self.heatWait

	
	self:cursorUpdate()
	--activeItem.setInstanceValue("rounds", self.rounds)
end

function GunFire:cycleCool(dt)
	local overMult = 0.75
	
	if not self.venting then
		self.heat = math.max(0, self.heat - self.heatCoolSpeed * dt)
	else 
		self.heat = math.max(0, self.heat - (self.heatCoolSpeed * overMult) * dt) 
	end
	
	self:cursorUpdate()
end

function GunFire:cursorInit(mode)
	local c = mode
	if       c == "none" then self.cursorType = 0
	  elseif c == "anim" then self.cursorType = 1
	  elseif c == "curs" then self.cursorType = 2
	  elseif c == 0 then self.cursorType = 0
	  elseif c == 1 then self.cursorType = 1
	  elseif c == 2 then self.cursorType = 2
	end
	
	if self.cursorType == 0 then
		activeItem.setScriptedAnimationParameter("doAnim", false)
		self.cursorDir0 = config.getParameter("cursorDir0", "/cursors/azdefault.cursor")
		activeItem.setCursor(self.cursorDir0)
	end
	
	if self.cursorType == 1 then
		self.cursorDir0 = config.getParameter("cursorDir0", "/cursors/azdefault.cursor")
		activeItem.setCursor(self.cursorDir0)
		
		self.cursorDir1 = config.getParameter("cursorDir1", "/cursors/anim/100/azreticle100.png")
		activeItem.setScriptedAnimationParameter("doAnim", true)
		activeItem.setScriptedAnimationParameter("ammoDisplayDirectory", self.cursorDir1)
		
		activeItem.setScriptedAnimationParameter("ammoDisplayOffset", config.getParameter("cursorAnimOffset", {0, 0}))
		activeItem.setScriptedAnimationParameter("ammoDisplayScale", config.getParameter("cursorAnimScale", 1))
	end
		
	if self.cursorType == 2 then
		activeItem.setScriptedAnimationParameter("doAnim", false)
		self.cursorDir2 = config.getParameter("cursorDir2", "/cursors/100/azreticle")
	end
end

function GunFire:cursorUpdate()
	if self.cursorType == 2 then		
		local heatPerc = (self.heat / self.heatMax) * 100
		activeItem.setCursor(self.cursorDir2 .. (math.max(0, math.ceil(heatPerc))) .. ".cursor")
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


