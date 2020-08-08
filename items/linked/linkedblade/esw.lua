require "/scripts/util.lua"
require "/scripts/status.lua"
require "/scripts/az-key-core/azweapon/weapon.lua"

MeleeLunge = WeaponAbility:new()

function MeleeLunge:init()
  self.weapon:setStance(self.stances.idle)
  self.cooldownTimer = self:cooldownTime()
  activeItem.setShieldPolys()
  
  self.damageConfig.baseDamage = self.baseDps * self.fireTime
  self.energyUsage = self.energyUsage or 0
  
  activeItem.setCursor(self.cursorDir .. ".cursor")

  self.weapon.onLeaveAbility = function()
    self.weapon:setStance(self.stances.idle)
  end
  
  self.target = false
  
  self.thrustDuration = 0.5
  self.thrustTimer = self.thrustDuration
  
  self.lungeTimeout = 2
  self.lungeTimer = self.lungeTimeout
  
  self.lungeSpeed = 40
  self.lungeForce = 100
  
  util.setDebug(true)
end

-- Ticks on every update regardless if this is the active ability
function MeleeLunge:update(dt, fireMode, shiftHeld)
  WeaponAbility.update(self, dt, fireMode, shiftHeld)
  self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

  self:updateTarget()
  self:updateCursor()
  
  if not self.weapon.currentAbility and self.fireMode == (self.activatingFireMode or self.abilitySlot) and self.cooldownTimer == 0 and (self.energyUsage == 0 or not status.resourceLocked("energy")) then
    self:setState(self.windup)
  end
  
  self:drawDebug()
end

function MeleeLunge:updateTarget()
	local targetIn = self:findTarget()
	
	if targetIn then
		self.target = targetIn
	else self.target = false end
end

function MeleeLunge:findTarget()
  local nearEntities = world.entityQuery(activeItem.ownerAimPosition(), self.queryRange, { 
    includedTypes = {"npc", "monster",  "player"},
	order = "nearest"})
  
  nearEntities = util.filter(nearEntities, function(entityId)
    
	-- filter occluded entities
	if world.lineTileCollision(mcontroller.position(), world.entityPosition(entityId)) then
      return false
    end
	
	if not world.entityCanDamage(activeItem.ownerEntityId(), entityId) then
      return false
    end
	
    if world.entityDamageTeam(entityId).type == "passive" then
      return false
    end
	
	return true
  end)
  
  if #nearEntities > 0 then 
    return nearEntities[1]
  else 
    return false
  end
end

function MeleeLunge:updateCursor()
	if self.target then
		activeItem.setCursor(self.cursorDir .. "-active" .. ".cursor")
	else activeItem.setCursor(self.cursorDir .. ".cursor") end
end

function MeleeLunge:drawDebug()
	local ts = "false"
	if self.target then ts = "true" else ts = "false" end -- I miss ternary operators
	util.debugText(sb.print("Target: " .. ts), vec2.add(mcontroller.position(), {1, 2}), "green")
	
	util.debugText(sb.print("Thrust: " .. string.format("%.3f", self.thrustTimer)), vec2.add(mcontroller.position(), {1, 2.5}), "green")
	util.debugText(sb.print("Lunge: " .. string.format("%.3f", self.lungeTimer)), vec2.add(mcontroller.position(), {1, 3}), "green")
	
	-- draw cursor radius
	local colour = "white"
	if self.target then colour = "red" else colour = "white" end
	util.debugCircle(activeItem.ownerAimPosition(), self.queryRange , colour, 20)
end


-- State: windup
function MeleeLunge:windup()
  self.weapon:setStance(self.stances.windup)

  if self.stances.windup.hold then
    while self.fireMode == (self.activatingFireMode or self.abilitySlot) do
      coroutine.yield()
    end
  else
    util.wait(self.stances.windup.duration)
  end

  if self.energyUsage then
    status.overConsumeResource("energy", self.energyUsage)
  end

  if self.stances.preslash then
    self:setState(self.preslash)
  else
    self:setState(self.lunge)
  end
end

-- State: preslash
-- brief frame in between windup and fire
function MeleeLunge:preslash()
  self.weapon:setStance(self.stances.preslash)
  self.weapon:updateAim()

  util.wait(self.stances.preslash.duration)

  self:setState(self.lunge)
end

-- State: lunge
function MeleeLunge:lunge()
  self.weapon:setStance(self.stances.lunge)
  self.weapon:updateAim()
  
  local lungeFlag = true
  self.thrustTimer = self.thrustDuration
  self.lungeTimer = self.lungeTimeout

  animator.setAnimationState("swoosh", "fire")
  animator.playSound(self.fireSound or "fire")
  animator.burstParticleEmitter((self.elementalType or self.weapon.elementalType) .. "swoosh")
  
  local shieldPoly = animator.partPoly("swoosh", "shieldPoly")
  activeItem.setShieldPolys({shieldPoly})

  self.damageListener = damageListener("damageTaken", function(notifications)
    for _,notification in pairs(notifications) do
      if notification.hitType == "ShieldHit" then
		lungeFlag = false
		self:setState(self.slice)
	  end
	end
  end)
  
  while lungeFlag do
    self.lungeTimer = self.lungeTimer - self.dt
	if self.lungeTimer <= 0 then lungeFlag = false end
	
  	if self.target and world.entityExists(self.target) and self.thrustTimer > 0 then
	  self.thrustTimer = self.thrustTimer - self.dt
	  
	  --local thrustAngle = mcontroller.facingDirection() == 1 and self.weapon.aimAngle + math.pi or -self.weapon.aimAngle
      --mcontroller.controlApproachVelocity(vec2.withAngle(thrustAngle, speed), force)
	  
	  local targetPos = world.entityPosition(self.target)
	  if targetPos then
		local offset = world.distance(targetPos, mcontroller.position())
		mcontroller.controlApproachVelocity(vec2.mul(vec2.norm(offset), self.lungeSpeed), self.lungeForce)
	  end
    end
   
    local damageArea = partDamageArea("swoosh")
    self.weapon:setDamage(self.damageConfig, damageArea, self.fireTime)
	
	if self.target and not world.entityExists(self.target) then
		lungeFlag = false
	elseif not self.target then
		lungeFlag = false
	end
	
	coroutine.yield()
  end

  self.cooldownTimer = self:cooldownTime()
  
  if not lungeFlag then self:setState(self.slice)end
end

function MeleeLunge:slice()
  self.weapon:setStance(self.stances.fire)
  self.weapon:updateAim()
  
  animator.setAnimationState("swoosh", "fire")
  animator.playSound(self.fireSound or "fire")
  animator.burstParticleEmitter((self.elementalType or self.weapon.elementalType) .. "swoosh")
  
  activeItem.setShieldPolys()
  
  util.wait(self.stances.fire.duration, function() 
	local damageArea = partDamageArea("swoosh")
    self.weapon:setDamage(self.damageConfig, damageArea, self.fireTime)
  end)
end

function MeleeLunge:cooldownTime()
  return self.fireTime - self.stances.windup.duration - self.stances.fire.duration
end

function MeleeLunge:uninit()
  self.weapon:setDamage()
end
