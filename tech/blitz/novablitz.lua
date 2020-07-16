require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/colorutil.lua"

function init()
	self.projectiles = self.projectiles or {}

	initCommonParameters()
	initColorator()
	initProjectiles()
end

function initProjectiles()
	
end

function initCommonParameters()
  if type(self.projectiles) ~= "table" then sb.logInfo("NovaBlitz: why isn't it a TABLE") end


  self.angularVelocity = 0
  self.angle = 0
  self.transformFadeTimer = 0

  self.energyCost = config.getParameter("energyCost")
  self.ballRadius = config.getParameter("ballRadius")
  self.ballFrames = config.getParameter("ballFrames")
  self.ballSpeed = config.getParameter("ballSpeed")
  self.transformFadeTime = config.getParameter("transformFadeTime", 0.3)
  self.transformedMovementParameters = config.getParameter("transformedMovementParameters")
  self.transformedMovementParameters.runSpeed = self.ballSpeed
  self.transformedMovementParameters.walkSpeed = self.ballSpeed
  self.basePoly = mcontroller.baseParameters().standingPoly
  self.collisionSet = {"Null", "Block", "Dynamic", "Slippery"}

  self.forceDeactivateTime = config.getParameter("forceDeactivateTime", 3.0)
  self.forceShakeMagnitude = config.getParameter("forceShakeMagnitude", 0.125)
  
  self.hoverDist = 4
  
  
  self.projectileParameters = config.getParameter("projectileParameters") or {}
end

function initColorator()
	local id = entity.id()
	self.bodyColors = {0, 0, 0}
	
	if id then
		self.bodyColors = extractTone(id)
		dexed = hextorgb(self.bodyColors[2])
		hsl = rgbtohsl(dexed)
		hsl[2] = 0.7
		hsl[3] = 0.45
		prepGlow = hsltorgb(hsl)
		
		sb.logInfo("NovaBlitz RGB: " .. "R" .. tostring(prepGlow[1]) .. "G" .. tostring(prepGlow[2]) .. "B" .. tostring(prepGlow[3]))
		
		
		local extDir = extractDirectives(id)
		--directives = string.sub(directives, 65, -1)
		self.directives = string.sub(extDir, 1, 63)
		sb.logInfo(tostring(self.directives))
	end
end

function uninit()
  storePosition()
  deactivate()
end

function update(args)
  restoreStoredPosition()

  if not self.specialLast and args.moves["special1"] then
    attemptActivation()
  end
  self.specialLast = args.moves["special1"]

  if not args.moves["special1"] then
    self.forceTimer = nil
  end

  if self.active then
    mcontroller.controlParameters(self.transformedMovementParameters)
	--mcontroller.controlParameters({gravityMultiplier = 0})
    status.setResourcePercentage("energyRegenBlock", 1.0)
	
	doControl(args)
	doHover(args)

    updateAngularVelocity(args.dt)
    updateRotationFrame(args.dt)

    checkForceDeactivate(args.dt)
	
	-- we don't need to update projectiles every frame
	updateProjectiles()
  end
  
  updateTransformFade(args.dt)

  self.lastPosition = mcontroller.position()
end

function doControl(args)
	local fSpeed = 50
	local cForce = 300
	local xV = 0
	local yV = 0
	
	if args.moves["left"] then xV = 0 - fSpeed
	elseif args.moves["right"] then xV = fSpeed
	else xV = 0 end
	
	if args.moves["up"] then yV = fSpeed
	elseif args.moves["down"] then yV = 0 - fSpeed
	else yV = 0 end
	
	mcontroller.controlApproachVelocity({xV, yV}, cForce)
end

function doHover(args)
	local hoverTo = self.hoverDist
	local hoverSpeed = 55
	local hoverConForce = 200
	
	local hoverForce2 = 5
	
	local currentPos = mcontroller.position()
	local queryPos = {currentPos[1], currentPos[2] - hoverTo}
	local ray = world.lineCollision(currentPos, queryPos, {"Block", "Dynamic", "Platform"})
	
	local debugCol = "white"
	if ray ~= nil then 
		world.debugPoint(ray, "blue")
		debugCol = "red"
		
		
		local targetPos = {ray[1], ray[2] + hoverTo}
		world.debugPoint(targetPos, "green")
		
		local toTarget = world.distance(targetPos, currentPos)
		--mcontroller.controlApproachYVelocity(toTarget[2] * hoverSpeed, hoverConForce)
		mcontroller.setYVelocity(mcontroller.velocity()[2] + hoverForce2)
		
		--local cV = mcontroller.velocity()
		--mcontroller.controlApproachYVelocity(cV[2]+hoverSpeed, hoverConForce)
		 
	end
	
	world.debugPoint(currentPos, "red")
	world.debugLine(currentPos, queryPos, debugCol)
end

function attemptActivation()
  if not self.active
      and not tech.parentLounging()
      and not status.statPositive("activeMovementAbilities")
      and status.overConsumeResource("energy", self.energyCost) then

    local pos = transformPosition()
    if pos then
      mcontroller.setPosition(pos)
      activate()
    end
  elseif self.active then
    local pos = restorePosition()
    if pos then
      mcontroller.setPosition(pos)
      deactivate()
    elseif not self.forceTimer then
      animator.playSound("forceDeactivate", -1)
      self.forceTimer = 0
    end
  end
end

function checkForceDeactivate(dt)
  animator.resetTransformationGroup("ball")

  if self.forceTimer then
    self.forceTimer = self.forceTimer + dt
    mcontroller.controlModifiers({
      movementSuppressed = true
    })

    local shake = vec2.mul(vec2.withAngle((math.random() * math.pi * 2), self.forceShakeMagnitude), self.forceTimer / self.forceDeactivateTime)
    animator.translateTransformationGroup("ball", shake)
    if self.forceTimer >= self.forceDeactivateTime then
      deactivate()
      self.forceTimer = nil
    else
      attemptActivation()
    end
    return true
  else
    animator.stopAllSounds("forceDeactivate")
    return false
  end
end

function storePosition()
  if self.active then
    storage.restorePosition = restorePosition()

    -- try to restore position. if techs are being switched, this will work and the storage will
    -- be cleared anyway. if the client's disconnecting, this won't work but the storage will remain to
    -- restore the position later in update()
    if storage.restorePosition then
      storage.lastActivePosition = mcontroller.position()
      mcontroller.setPosition(storage.restorePosition)
    end
  end
end

function restoreStoredPosition()
  if storage.restorePosition then
    -- restore position if the player was logged out (in the same planet/universe) with the tech active
    if vec2.mag(vec2.sub(mcontroller.position(), storage.lastActivePosition)) < 1 then
      mcontroller.setPosition(storage.restorePosition)
    end
    storage.lastActivePosition = nil
    storage.restorePosition = nil
  end
end

function updateAngularVelocity(dt)
  if mcontroller.groundMovement() then
    -- If we are on the ground, assume we are rolling without slipping to
    -- determine the angular velocity
    local positionDiff = world.distance(self.lastPosition or mcontroller.position(), mcontroller.position())
    self.angularVelocity = -vec2.mag(positionDiff) / dt / self.ballRadius

    if positionDiff[1] > 0 then
      self.angularVelocity = -self.angularVelocity
    end
  end
end

function updateRotationFrame(dt)
  self.angle = math.fmod(math.pi * 2 + self.angle + self.angularVelocity * dt, math.pi * 2)

  -- Rotation frames for the ball are given as one *half* rotation so two
  -- full cycles of each of the ball frames completes a total rotation.
  local rotationFrame = math.floor(self.angle / math.pi * self.ballFrames) % self.ballFrames
  animator.setGlobalTag("rotationFrame", rotationFrame)
end

function updateTransformFade(dt)
  if self.transformFadeTimer > 0 then
    self.transformFadeTimer = math.max(0, self.transformFadeTimer - dt)
    animator.setGlobalTag("ballDirectives", string.format("?fade=FFFFFFFF;%.1f", math.min(1.0, self.transformFadeTimer / (self.transformFadeTime - 0.15))))
  elseif self.transformFadeTimer < 0 then
    self.transformFadeTimer = math.min(0, self.transformFadeTimer + dt)
    tech.setParentDirectives(string.format("?fade=FFFFFFFF;%.1f", math.min(1.0, -self.transformFadeTimer / (self.transformFadeTime - 0.15))))
  else
    animator.setGlobalTag("ballDirectives", "")
    tech.setParentDirectives()
  end
end

function positionOffset()
  return minY(self.transformedMovementParameters.collisionPoly) - minY(self.basePoly)
end

function transformPosition(pos)
  pos = pos or mcontroller.position()
  local groundPos = world.resolvePolyCollision(self.transformedMovementParameters.collisionPoly, {pos[1], pos[2] - positionOffset()}, 1, self.collisionSet)
  if groundPos then
    return groundPos
  else
    return world.resolvePolyCollision(self.transformedMovementParameters.collisionPoly, pos, 1, self.collisionSet)
  end
end

function restorePosition(pos)
  pos = pos or mcontroller.position()
  local groundPos = world.resolvePolyCollision(self.basePoly, {pos[1], pos[2] + positionOffset()}, 1, self.collisionSet)
  if groundPos then
    return groundPos
  else
    return world.resolvePolyCollision(self.basePoly, pos, 1, self.collisionSet)
  end
end

function activate()
  if not self.active then
    animator.burstParticleEmitter("activateParticles")
    animator.playSound("activate")
    animator.setAnimationState("ballState", "activate")
    self.angularVelocity = 0
    self.angle = 0
    self.transformFadeTimer = self.transformFadeTime
  end
  tech.setParentHidden(true)
  tech.setParentOffset({0, positionOffset()})
  tech.setToolUsageSuppressed(true)
  status.setPersistentEffects("movementAbility", {{stat = "activeMovementAbilities", amount = 1}})
  
  createProjectiles()
  
  self.active = true
end

function deactivate()
  if self.active then
    animator.burstParticleEmitter("deactivateParticles")
    animator.playSound("deactivate")
    animator.setAnimationState("ballState", "deactivate")
    self.transformFadeTimer = -self.transformFadeTime
  else
    animator.setAnimationState("ballState", "off")
  end
  animator.stopAllSounds("forceDeactivate")
  animator.setGlobalTag("ballDirectives", "")
  tech.setParentHidden(false)
  tech.setParentOffset({0, 0})
  tech.setToolUsageSuppressed(false)
  status.clearPersistentEffects("movementAbility")
  self.angle = 0
  
  killProjectiles()
  
  self.active = false
end

function minY(poly)
  local lowest = 0
  for _,point in pairs(poly) do
    if point[2] < lowest then
      lowest = point[2]
    end
  end
  return lowest
end

function createProjectiles()
	local createPos = mcontroller.position()
	
	local projCount = self.projectileCount or 2
	
	--util.mergeTable(self.projectileParameters, { periodicActions[1].specification = { color = hextorgb(self.bodyColors[2]) } } )
	--util.mergeTable(self.projectileParameters, { processing = "?" .. self.directives } )
	
	local pParams = copy(self.projectileParameters)
	pParams.processing = "?" .. self.directives
	pParams.periodicActions[1].specification.color = hextorgb(self.bodyColors[2])
	
	for i = 1, projCount do
		local projId = world.spawnProjectile(
			"az-novablitz_swarm",
			createPos,
			entity.id(),
			{0, 0},
			false,
			pParams
			)

		if projId then
			table.insert(self.projectiles, projId)
			--world.sendEntityMessage(projId, 
		end
	end
end

function updateProjectiles()
	self.projectiles = self.projectiles or {}

	local newProjectiles = {}
	for _, projId in pairs(self.projectiles) do
		if world.entityExists(projId) then
			local projResponse = world.sendEntityMessage(projId, "checkProjectile")
			if projResponse:finished() then
				local newIds = projResponse:result()
				if type(newIds) ~= "table" then 
					newIds = {newIds}
				end
				for _, newId in pairs(newIds) do
					table.insert(newProjectiles, newId)
				end
			end
		end
	end
	
	self.projectiles = newProjectiles
end

function killProjectiles()
	for _, projId in pairs(self.projectiles) do 
		sb.logInfo("killing projectile" .. tostring(projId))
		if world.entityExists(projId) then 
			world.sendEntityMessage(projId, "kill")
		end
	end
end