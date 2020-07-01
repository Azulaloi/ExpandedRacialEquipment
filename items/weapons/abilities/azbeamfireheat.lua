require "/scripts/util.lua"
require "/scripts/interp.lua"

GunFire = WeaponAbility:new()

function GunFire:init()
	self.damageConfig.baseDamage = self.baseDps * self.fireTime
    self.weapon:setStance(self.stances.idle)
	
	--animator.setParticleEmitterActive("vent", false)
	self.venting = false
	
    self.cooldownTimer = self.fireTime
	self.impactSoundTimer = 0

    self.weapon.onLeaveAbility = function()
        self.weapon:setStance(self.stances.idle)
    end
	
	self.heat = config.getParameter("heat", 0)
	self.coolTimer = 0
	--self.heatMax = config.getParameter("heatMax", 200)
	--self.heatPerShot = config.getParameter("heatPerShot", 5)
	--self.heatWait = config.getParameter("heatWait", 2)
	--self.heatCoolSpeed = config.getParameter("heatheatCoolSpeed", 35)

	
	self:cursorInit(config.getParameter("cursorMode", "none"))
	self:cursorUpdate()

	self.weapon.onLeaveAbility = function()
		self.weapon:setDamage()
		activeItem.setScriptedAnimationParameter("chains", {})
		animator.setParticleEmitterActive("beamCollision", false)
		animator.stopAllSounds("fireLoop")
		self.weapon:setStance(self.stances.idle)
	end
end

function GunFire:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
	self.impactSoundTimer = math.max(self.impactSoundTimer - self.dt, 0)
	
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

		self:setState(self.fire)
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

function GunFire:fire()
  self.weapon:setStance(self.stances.fire)

  animator.playSound("fireStart")
  animator.playSound("fireLoop", -1)

  local wasColliding = false
  while self.fireMode == (self.activatingFireMode or self.abilitySlot) and status.overConsumeResource("energy", (self.energyUsage or 0) * self.dt) do
    local beamStart = self:firePosition()
    local beamEnd = vec2.add(beamStart, vec2.mul(vec2.norm(self:aimVector(0)), self.beamLength))
    local beamLength = self.beamLength

    local collidePoint = world.lineCollision(beamStart, beamEnd)
    if collidePoint then
      beamEnd = collidePoint

      beamLength = world.magnitude(beamStart, beamEnd)

      animator.setParticleEmitterActive("beamCollision", true)
      animator.resetTransformationGroup("beamEnd")
	  --animator.rotateTransformationGroup("beamEnd", 50)
      animator.translateTransformationGroup("beamEnd", {beamLength, 0})

      if self.impactSoundTimer == 0 then
        animator.setSoundPosition("beamImpact", {beamLength, 0})
        animator.playSound("beamImpact")
        self.impactSoundTimer = self.fireTime
      end
    else
      animator.setParticleEmitterActive("beamCollision", false)
    end

    self.weapon:setDamage(self.damageConfig, {self.weapon.muzzleOffset, {self.weapon.muzzleOffset[1] + beamLength, self.weapon.muzzleOffset[2]}}, self.fireTime)
    --self.weapon:setDamage(self.damageConfig, {self.weapon.muzzleOffset, {self.weapon.muzzleOffset[1] + beamLength, self.weapon.muzzleOffset[2] + 5}}, self.fireTime)
    --self.weapon:setDamage(self.damageConfig, {self.weapon.muzzleOffset, vec2.sub(mcontroller.position(), beamEnd)}, self.fireTime)

    self:drawBeam(beamEnd, collidePoint)
	self:cycle(self.heatGeneration * self.dt)
	
	
	world.debugText(sb.print("End"), vec2.add(beamEnd, {0.2, 0.2}), "blue")
	world.debugText(sb.print(vec2.print(beamEnd, 2)), vec2.add(beamEnd, {0.2, 0.7}), "blue")
	world.debugPoint(beamEnd, "blue")	
	
	--local ppoint = animator.partPoint("muzzleFlash", "offset")
	--world.debugPoint(vec2.add(mcontroller.position(), ppoint), "red")
	--world.debugPoint(vec2.add(vec2.add(mcontroller.position(), ppoint), {self.weapon.muzzleOffset[1] + beamLength, self.weapon.muzzleOffset[2]}), "red")
	
	--world.debugLine(self.weapon.muzzleOffset, {self.weapon.muzzleOffset[1] + beamLength, self.weapon.muzzleOffset[2]}, "blue")
	--world.debugPoint({self.weapon.muzzleOffset[1] + beamLength, self.weapon.muzzleOffset[2]}, "red")
	
    coroutine.yield()
  end

  self:reset()
  animator.playSound("fireEnd")

  self.cooldownTimer = self.fireTime
  self:setState(self.cooldown)
end

function GunFire:drawBeam(endPos, didCollide)
  local newChain = copy(self.chain)
  newChain.startOffset = self.weapon.muzzleOffset
  newChain.endPosition = endPos

  if didCollide then
    newChain.endSegmentImage = nil
  end

  activeItem.setScriptedAnimationParameter("chains", {newChain})
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
--		animator.setParticleEmitterActive("vent", true)
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

--	animator.setParticleEmitterActive("vent", false)
	self.venting = false
	
	if not terminateFlag then
		self:setState(self.overheat, iter + 1)
	end
end

function GunFire:clickFx()
	self:playSoundSafe("click")
end

function GunFire:playSoundSafe(sound, loopsIn)
	local loops = loopsIn or 0
	if animator.hasSound(sound) then
		animator.playSound(sound, loops)
	else 
		sb.logWarn("azbeamfireheat: Item <" .. tostring(item.name)
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

function GunFire:cycle(heatIn) 
	local heatAdd = self.heat + heatIn
	if heatAdd > self.heatMax then
		heatAdd = self.heatMax end
	self.heat = heatAdd
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


function GunFire:uninit()
	self:reset()
end

function GunFire:reset()
  self.weapon:setDamage()
  activeItem.setScriptedAnimationParameter("chains", {})
  animator.setParticleEmitterActive("beamCollision", false)
  animator.stopAllSounds("fireStart")
  animator.stopAllSounds("fireLoop")
end


