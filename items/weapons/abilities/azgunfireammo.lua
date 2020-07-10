require "/scripts/util.lua"
require "/scripts/interp.lua"

-- TODO: safety checks/helpful debug info for incorrect setups
-- such as missing properties that gunfireammo and reload share 
-- and are therefore not in the ability itself, specifically:
-- maxRounds, cursorDir

GunFire = WeaponAbility:new()
 
 
-- don't forget to change all the stance value queries to use swapstance!
function GunFire:swapStance(stanceName)
	local swapFlag = false

	if self.defaultHanded == nil then
		sb.logInfo("self.defaultHanded == nil")
		return stanceName
	end
	
	local twoHanded = config.getParameter("twoHanded")
	
	if self.defaultHanded == "two" then
		if twoHanded then
			swapFlag = false
		elseif not twoHanded then
			swapFlag = true
		end
	elseif self.defaultHanded == "one" then
		if twoHanded == true then
			swapFlag = true
		elseif twoHanded == false then
			swapFlag = false
		end
	end
	
	--sb.logInfo(tostring(swapFlag) .. " | " .. tostring(twoHanded))
	
	if swapFlag then
		local stanceOut = "alt-" .. stanceName
		--sb.logInfo(tostring(stanceOut))
		return stanceOut
	end
	
	--sb.logInfo(tostring(stanceName))
	return stanceName
end

function GunFire:setSwapStance(stanceName)
	if self.swappable then 
	self.weapon:setStance(self.stances[self:swapStance(stanceName)])
	else self.weapon:setStance(self.stances[stanceName]) end
end

function GunFire:init()
	self.swappable = config.getParameter("azSwappable", false)
	if self.swappable then self:setHandedAnimState() end
    self:setSwapStance("idle")
	--self.weapon:setStance(self.stances[self:swapStance("idle")])	

	--if not pcall(self.checkWep()) then
	--	sb.logWarn('GunFireAmmo initialized to incorrect weapon.lua, will not function correctly')
	--end
	
    self.cooldownTimer = self.fireTime

    self.weapon.onLeaveAbility = function()
        self:setSwapStance("idle")
    end
	
	
	self.ammoMode = config.getParameter("ammoMode", 1)
	self.maxRounds = config.getParameter("maxRounds", 3)
	self.rounds = config.getParameter("rounds", self.maxRounds)
	
	
	-- TODO: the chambering behavior might be overly complicated. 
	self.chamberMode = config.getParameter("chamberMode", 0)
	self.chamberAuto = config.getParameter("chamberAuto", 0)
	self.chamberStatus = config.getParameter("chamberStatus", 0)
	
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

    if animator.animationState("firing") ~= "fire" then
        animator.setLightActive("muzzleFlash", false)
    end
	
    if self.fireMode == (self.activatingFireMode or self.abilitySlot)
            and not self.weapon.currentAbility
            and self.cooldownTimer == 0
            and not status.resourceLocked("energy")
            and not world.lineTileCollision(mcontroller.position(), self:firePosition()) then
			
		if shiftHeld then
			self:setState(self.chamberingState)
		elseif not self:canFire() then
			self:setState(self.click)
        elseif self.fireType == "auto" and status.overConsumeResource("energy", self:energyPerShot()) then
            self:setState(self.auto)
        elseif self.fireType == "burst" then
            self:setState(self.burst)
        end
    end
	
	self:updateDebug()
end

function GunFire:updateDebug()
	world.debugText(sb.print("Ammo: " .. self.rounds), vec2.add(mcontroller.position(), {1, 2}), "green")
	world.debugText(sb.print("MaxAmmo: " .. self.maxRounds), vec2.add(mcontroller.position(), {1, 2.5}), "green")
	world.debugText(sb.print("FireState: " .. animator.animationState("firing")), vec2.add(mcontroller.position(), {1, 3}), "green")
	--world.debugText(sb.print("HandedState: " .. animator.animationState("handed")), vec2.add(mcontroller.position(), {1, 3.5}), "green")
	world.debugText(sb.print("ChamberStatus: " .. self.chamberStatus), vec2.add(mcontroller.position(), {1, 4}), "green")
	world.debugText(sb.print("CanFire: " .. tostring(self:canFire())), vec2.add(mcontroller.position(), {1, 4.5}), "green")
	--world.debugText(sb.print(self.weapon:getState()), vec2.add(mcontroller.position(), {1,4}), "green")
	
	--world.debugPoint(self:firePosition(), "red")
end

function GunFire:canFire()
	local flagRounds = false
	local flagChamber = false
	
	if self.ammoMode == 0 then
		flagRounds = true
	elseif self.ammoMode == 1 then
		flagRounds = (self.rounds <= 0)
	end

	if self.chamberMode == 0 then
		flagChamber = true
	elseif self.chamberMode == 1 then
		flagChamber = (self.chamberStatus == 0)
	end
 	
	return (flagRounds and flagChamber)
end

function GunFire:ammoCall()
	--sb.logInfo("ammocall received by primary")
	self.rounds = config.getParameter("rounds", 6)
	self:cursorUpdate()
end

function GunFire:auto()
    self:setSwapStance("fire")

    self:fireProjectile()
    self:muzzleFlash()

    if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end

    self.cooldownTimer = self.fireTime
	
	if self.chamberMode == 1 and self.chamberAuto == 1 then
		self:setState(self.chamberingState)
	else self:setState(self.cooldown) end
end

function GunFire:burst()
    self:setSwapStance("fire")

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
    self:setSwapStance("cooldown")
    self.weapon:updateAim()

    local progress = 0
    util.wait(self.stances[self:swapStance("cooldown")].duration, function()
        local from = self.stances[self:swapStance("cooldown")].weaponOffset or {0,0}
        local to = self.stances[self:swapStance("idle")].weaponOffset or {0,0}
        self.weapon.weaponOffset = {interp.linear(progress, from[1], to[1]), interp.linear(progress, from[2], to[2])}

        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(progress, self.stances[self:swapStance("cooldown")].weaponRotation, self.stances[self:swapStance("idle")].weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(progress, self.stances[self:swapStance("cooldown")].armRotation, self.stances[self:swapStance("idle")].armRotation))

        progress = math.min(1.0, progress + (self.dt / self.stances[self:swapStance("cooldown")].duration))
    end)
end

function GunFire:chamberingState()
    self:setSwapStance("fire")

	animator.setAnimationState("pump", "action")
	animator.playSound("chamber")
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self.chamberStatus = 0 
	activeItem.setInstanceValue("chamberStatus", self.chamberStatus)
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function GunFire:click()
    self:setSwapStance("fire")

	self:clickFx()
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function GunFire:reload()
    self:setSwapStance("fire")

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
	local twoHanded = config.getParameter("twoHanded")
	
	-- this is incomplete placeholder, needs to check against default and all that
	if twoHanded then
		animator.setAnimationState("firing", "fire")
	else animator.setAnimationState("firing", "fireAlt") end

    animator.setPartTag("muzzleFlash", "variant", math.random(1, 3))
    --animator.setAnimationState("firing", "fire")
    animator.burstParticleEmitter("muzzleFlash")
    animator.playSound("fire")

    animator.setLightActive("muzzleFlash", true)
end

function GunFire:setHandedAnimState()
	local twoHanded = config.getParameter("twoHanded")
	
	if twoHanded then
		animator.setAnimationState("handed", "two")
	  else 
	    animator.setAnimationState("handed", "one") 
	end
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
	if self.ammoMode ~= 0 then
		self.rounds = self.rounds - 1
		self:cursorUpdate()
		activeItem.setInstanceValue("rounds", self.rounds)
	end
	
	if self.chamberMode == 1 then
		self.chamberStatus = 1
		activeItem.setInstanceValue("chamberStatus", self.chamberStatus)
	end
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
		self.cursorDir2 = config.getParameter("cursorDir2", "/cursors/12/azreticle")
	end
end

function GunFire:cursorUpdate()
	if self.cursorType == 1 then
		activeItem.setScriptedAnimationParameter("ammoDisplayQuantity", self.rounds)
	end
	
	if self.cursorType == 2 then
		activeItem.setCursor(self.cursorDir2 .. (self.rounds) .. ".cursor")
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


