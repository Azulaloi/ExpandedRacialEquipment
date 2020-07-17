require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/colorutil.lua"

function init()
	self.projectiles = self.projectiles or {}

	initCommonParameters()
	initColorator()
	initProjectiles()
	initHandlers()
	
	util.setDebug(true)
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
  
  self.projOrbitRadius = 2.5
  
  self.projectileCount = 5
  self.projectileParameters = config.getParameter("projectileParameters") or {}
  
  self.projReplaceWait = 3
  self.projReplaceTimer = self.projReplaceWait
end

function initHandlers()
	message.setHandler("projDead", function(_, _, timeIn)
		ttl = timeIn or projectile.timeToLive()
		projectile.setTimeToLive(ttl)
		return entity.id()
	end)
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
		
		animator.setGlobalTag("novaTone", self.directives)
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
	updateProjectiles(args.dt)
  end
  
  updateTransformFade(args.dt)

  self.lastPosition = mcontroller.position()
  
  drawDebug()
end

function drawDebug()
	local q = 3

	if self.active then
		--for i = 1, q do
			--local theta = (2 * math.pi / q) * i
			--local pPos = { math.sin(theta + (2 * math.pi / q) / 2), 
			--			   math.cos(theta + (2 * math.pi / q) / 2) }
			--pPos = vec2.mul(pPos, self.projOrbitRadius)
			
			--local pPos = pointCircle(q, self.projOrbitRadius, i)
					 
			--world.debugPoint(vec2.add(mcontroller.position(), pPos), "red")
		--end
		
		--local pPos = pointCircle(3, self.projOrbitRadius, 3)
		--world.debugPoint(vec2.add(mcontroller.position(), pPos), "red")
	
		--local points = pointsCircle(q, self.projOrbitRadius)
		
		--for i = 1, #points do 
		--	local p = vec2.add(mcontroller.position(), points[i])
		--	world.debugPoint(p, "red")
		--end
		
		world.debugText("repCool: " .. round(self.projReplaceTimer, 2), vec2.add(mcontroller.position(), {4, 1.5}), "green")
		world.debugText("#proj: " .. tostring(#self.projectiles), vec2.add(mcontroller.position(), {4, 1}), "green")
		
		util.debugCircle(mcontroller.position(), self.projOrbitRadius, "red", 8)
	end
end

function round(num, dec)
	return string.format("%." .. (dec or 0) .. "f", num)
end

function pointsCircle(quant, radius)
	local points = {}
	
	for i = 1, quant do
		local p = pointCircle(quant, radius, i)
		points[i] = p
	end
	
	return points
end

-- vec2 (int, float, int)
function pointCircle(quant, radius, iter, thetaIn)
	--local theta = (2 * math.pi / quant) * iter
	local theta = thetaIn or (2 * math.pi / quant) * iter 
	
	local pPos = { math.sin(theta + (2 * math.pi / quant) / 2), 
				   math.cos(theta + (2 * math.pi / quant) / 2) }
				   
	pPos = vec2.mul(pPos, radius)
	
	-- alternatively...
	--pPos = vec2.rotate({0, radius}, (2 * math.pi/quant) * iter)
	
	return pPos
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
  
  createProjectiles(self.projectileCount, true)
  
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

function createProjectiles(countIn, circleIn)
	local createPos = mcontroller.position()
	
	local projCount = countIn or self.projectileCount or 5
	
	local cPoints = circleIn and pointsCircle(projCount, self.projOrbitRadius) or {0, 0}
	
	--util.mergeTable(self.projectileParameters, { periodicActions[1].specification = { color = hextorgb(self.bodyColors[2]) } } )
	--util.mergeTable(self.projectileParameters, { processing = "?" .. self.directives } )
	
	local pParams = copy(self.projectileParameters)
	pParams.processing = "?" .. self.directives
	pParams.periodicActions[1].specification.color = hextorgb(self.bodyColors[2])
	pParams.orbitRadius = self.projOrbitRadius
	
	for i = 1, projCount do
		local p = circleIn and cPoints[i] or {0, 0}
		pParams.orbitGuide = p
	
		local projId = world.spawnProjectile(
			"az-novablitz_swarm",
			vec2.add(createPos, p),
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

function spawnProjectile(countIn)
	
	for i = 1, countIn do
	
	end
end

function updateProjectiles(dt)
	self.projectiles = self.projectiles or {}

	local newProjectiles = {}
	for _, projId in pairs(self.projectiles) do
		if world.entityExists(projId) then
			local projResponse = world.sendEntityMessage(projId, "checkProjectile", 5)
			if projResponse:finished() then
				local newIds = projResponse:result()
				if type(newIds) ~= "table" then 
					newIds = {newIds}
				end
				for _, newId in pairs(newIds) do
					table.insert(newProjectiles, newId)
				end
			end
		--else table.remove(
		end
	end
	
	self.projectiles = newProjectiles
	
	-- todo: listen instead of polling
	if self.active and (#self.projectiles < self.projectileCount) then
		sb.logInfo("blitz: projectiles missing")
		
		if self.projReplaceTimer <= 0 then
			replaceProjectiles()
		end
		
		-- fix this being called a billion times
		adjustProjectiles()
	end
	
	self.projReplaceTimer = math.max(self.projReplaceTimer - dt, 0) 
end

function adjustProjectiles()
	local cPoints = pointsCircle(#self.projectiles, self.projOrbitRadius)
	
	for i = 1, #self.projectiles do
		local id = self.projectiles[i]
		sb.logInfo("blitz: adjust proj" .. tostring(id) .. " | new pos: " .. vecPrint(cPoints[i])) 
		world.sendEntityMessage(id, "setOrbitGuide", cPoints[i])
	end
end

function replaceProjectiles()
	local missing = self.projectileCount - #self.projectiles
	for i = 1, missing do 
		sb.logInfo("blitz: replacing " .. tostring(missing) .. " projectiles")
		createProjectiles(missing, false)
	end
	
	self.projReplaceTimer = self.projReplaceWait
	
	--alert adjust
end

function killProjectiles()
	for _, projId in pairs(self.projectiles) do 
		sb.logInfo("killing projectile" .. tostring(projId))
		if world.entityExists(projId) then 
			world.sendEntityMessage(projId, "kill")
		end
	end
end

function projDead(deadId)
	self.projReplaceTimer = self.projReplaceWait
	--for _, projId in pairs(self.projectiles) do
	--	if projId == deadId then 
end

function vecPrint(vecIn, decIn)
	local dec = decIn or 3
	--return "x" .. tostring(vecIn[1]) .. " : " .. "y" .. tostring(vecIn[2]) 
	return "x" .. round(vecIn[1], dec) .. " : " .. "y" .. round(vecIn[2], dec) 
end