require "/scripts/util.lua"
require "/scripts/vec2.lua"

function init()
	self.controlMovement = config.getParameter("controlMovement")
	self.controlRotation = config.getParameter("controlRotation")
	self.rotationSpeed = 0
	self.timedActions = config.getParameter("timedActions", {})

	-- 0 seeks aimPos (default unused) 
	-- 1 orbits entity (orbiting)
	-- 2 is returning (to die on return)
	-- 3 is fire and forget
	self.seekMode = config.getParameter("seekMode", 1)
	
	self.aimPosition = mcontroller.position()

	self.entityToFollow = projectile.sourceEntity() or nil
	self.tone = config.getParameter("tone", {0, 0, 0})
	self.orbitRadius = config.getParameter("orbitRadius", 2.5)
	self.orbitGuide = config.getParameter("orbitGuide", {0, self.orbitRadius})
	self.orbitClockwise = config.getParameter("orbitClockwise", true)
	
	self.cycle = 0
	self.firePos = {0, 0}
	self.kFlag = false
	self.readyToRelease = false
	
	initHandlers()
	
	util.setDebug(true)
end

function initHandlers()
	message.setHandler("updateProjectile", function(_, _, aimPosition)
		self.aimPosition = aimPosition
		return entity.id()
	end)
	
	message.setHandler("checkProjectile", function(_, _, timeIn)
		ttl = timeIn or projectile.timeToLive()
		projectile.setTimeToLive(ttl)
		return entity.id()
	end)
	
	message.setHandler("kill", function(_, _)
		msgKill()
    end)
	
	message.setHandler("setEntityToFollow", function(_, _, entityId)
		self.entityToFollow = entityId
	end)
	
	message.setHandler("setOrbitRadius", function(_, _, radiusIn)
		self.orbitRadius = radiusIn
	end)
	
	message.setHandler("setOrbitGuide", function(_, _, posIn)
		self.orbitGuide = posIn
	end)	
	
	message.setHandler("getCycle", function(_, _, posIn)
		return self.cycle
	end)	
	
	message.setHandler("setCycle", function(_, _, cycleIn)
		self.cycle = cycleIn
	end)
	
	message.setHandler("setOrbitAndCycle", function(_, _, posIn, cycleIn)
		self.orbitGuide = posIn
		self.cycle = cycleIn
	end)
	
	message.setHandler("fireAtPos", function(_, _, posIn)
		self.firePos = posIn
		self.seekMode = 3
	end)
	
	message.setHandler("setMode", function(_, _, modeIn)
		if modeIn == 2 then 
			mcontroller.applyParameters({collisionEnabled=false})
			--projectile.processAction(projectile.getParameter("actionOnFiredReap"))
		end
		self.seekMode = modeIn
	end)
end

function update(dt)
	if self.seekMode == 1 and self.entityToFollow ~= nil then
		-- ORBITING
		orbitEntity(self.entityToFollow, dt, false)
	elseif self.seekMode == 2 and self.entityToFollow ~= nil then
		-- RETURNING
		projectile.setTimeToLive(2)
		returnToEntity(self.entityToFollow, dt)
	elseif self.seekMode == 3 then
		-- FIRING
		if self.readyToRelease then
			local ang = vecFlip(world.distance(mcontroller.position(), self.firePos))
			mcontroller.approachVelocity(vec2.mul(vec2.norm(ang), 50), 50)
			world.debugPoint(self.firePos, "red")
		else 
			projectile.setTimeToLive(5)
			orbitEntity(self.entityToFollow, dt, true)
		end
	else
		if self.aimPosition then
			if self.controlMovement then
				controlTo(self.aimPosition)
			end
	
			if self.controlRotation then
				rotateTo(self.aimPosition, dt)
			end
	
			for _, action in pairs(self.timedActions) do
				processTimedAction(action, dt)
			end
		end
	end
	
	--world.debugText(tostring(entity.id()), vec2.add(mcontroller.position(), {1, 1}), "green")
end

function orbitEntity(entityId, dt, primingIn)
	if world.entityExists(entityId) then
		local priming = primingIn or false
	
		local targetPosition = world.entityPosition(entityId)
		local targetDistance = self.orbitRadius
		local targetSpeed = 10
		local seekSpeed = 50
		
		local currentPosition = mcontroller.position()
		
		local flipDir = self.orbitClockwise
		local guidePos = self.orbitGuide --or {0, 0}
		local cycleSpeed = 5
		
		local primeMult = 2.4
		local speedMult = 0.8 * (priming and primeMult or 1) 
		
		seekSpeed = seekSpeed * 1
		targetSpeed = targetSpeed * speedMult
		cycleSpeed = cycleSpeed * speedMult
		
		self.cycle = self.cycle + ( ((dt * cycleSpeed) % 360) * (flipDir and 1 or -1) ) 
		guidePos = vec2.add(targetPosition, vec2.rotate(guidePos, self.cycle))
		
		-- find closest position at the edge of the orbit
		local toCenterVector = vec2.sub(currentPosition, targetPosition)
		--local edgePosition = vec2.add(targetPosition, vec2.mul(vec2.norm(toCenterVector), targetDistance))
		local edgePosition = guidePos
		
		-- get normalized direction to that position
		local toEdgeVector = vec2.sub(edgePosition, currentPosition)
		local toEdgeDirection = vec2.norm(toEdgeVector)
		
		-- mix in the direction of the orbit depending on how close we are
		local orbitDirection = vec2.norm(vec2.rotate(toCenterVector, math.pi / (targetSpeed > 0 and -2 or 2)))
		local edgeMixFactor = math.min(1, math.max(0, (vec2.mag(toEdgeVector) / targetDistance)))
		local targetDirection = vec2.add(vec2.mul(toEdgeDirection, edgeMixFactor), vec2.mul(orbitDirection, 1 - edgeMixFactor))
		
		-- mix in seekspeed depending on how far we are
		-- 0.03 is from centrifugal force (I guess) - might need testing with other orbit speeds
		targetSpeed = targetSpeed + (seekSpeed * math.max(edgeMixFactor - 0.03, 0))
		
		-- move zig
		mcontroller.approachVelocity(vec2.mul(targetDirection, math.abs(targetSpeed)), 5000)
		
		--	PRIMING --
		local anchor = 1.5708
		local ancThresh = 0.7854
	
		if priming then
			local flag = false
			local toFirePos = vec2.sub(targetPosition, self.firePos)
			local toFireAng = math.atan(toFirePos[2], toFirePos[1])
			
			local angle = math.atan(toCenterVector[2], toCenterVector[1]) 
			
			local anchorVec = {0,0}			
			if not flipDir then
				anchorVec = vec2.rotate(vec2.withAngle(-anchor, 4), toFireAng)
				--flag = (angle >= (anchor - ancThresh) and angle <= (anchor + ancThresh))
				flag = angleWithin(angle, math.atan(anchorVec[2], anchorVec[1]), ancThresh)
			else
				anchorVec = vec2.rotate(vec2.withAngle(anchor, 4), toFireAng)
				--flag = (angle >= -(anchor + ancThresh) and angle <= -(anchor - ancThresh))
				flag = angleWithin(angle, math.atan(anchorVec[2], anchorVec[1]), ancThresh)
			end
			
			if flag then self.readyToRelease = true end
			
			local col = flag and "green" or "white"
			world.debugLine(targetPosition, vec2.add(targetPosition, vec2.withAngle(angle, 3)), col)
			world.debugLine(targetPosition, vec2.add(targetPosition, anchorVec), "blue")
			--world.debugLine(targetPosition, self.firePos, "green")
			--world.debugText(tostring(angle), vec2.add(targetPosition, {4, 6}), "green")
		end
		
		-- DEBUG -- 
		world.debugPoint(guidePos, "green")
		world.debugLine(currentPosition, guidePos, "green")
		world.debugLine(currentPosition, vec2.add(currentPosition, vec2.mul(targetDirection, math.abs(targetSpeed) / 3)), "blue")
		world.debugLine(currentPosition, edgePosition, "red")
		--util.debugCircle(targetPosition, targetDistance, "red", 8)
		--world.debugText(tostring(edgeMixFactor), vec2.add(mcontroller.position(), {1, 1}), "green")
		--world.debugText(tostring(self.cycle), vec2.add(targetPosition, {4, 1}), "green")
	end
end

function angleWithin(angle, anchor, thresh)
	return (angle >= (anchor - thresh) and angle <= (anchor + thresh))
end

function returnToEntity(entityId, dt)
	local targetPosition = world.entityPosition(entityId)
	local vecTo = vecFlip(world.distance(mcontroller.position(), targetPosition))
	
	local returnSpeed = 50
	local returnForce = 100
	
	local returnThresh = 1.5
	
	local dist = vec2.mag(vecTo)
	
	mcontroller.approachVelocity(vec2.mul(vec2.norm(vecTo), returnSpeed), returnForce)
	if dist <= returnThresh then
		-- maybe do a sound or something
		projectile.die()
	end	
	
	--world.debugText(tostring(dist), vec2.add(mcontroller.position(), {2, 4}), "green")
end

function control(direction)
  mcontroller.approachVelocity(vec2.mul(vec2.norm(direction), self.controlMovement.maxSpeed), self.controlMovement.controlForce)
end

function controlTo(position)
  local offset = world.distance(position, mcontroller.position())
  mcontroller.approachVelocity(vec2.mul(vec2.norm(offset), self.controlMovement.maxSpeed), self.controlMovement.controlForce)
end

function rotateTo(position, dt)
  local vectorTo = world.distance(position, mcontroller.position())
  local angleTo = vec2.angle(vectorTo)
  if self.controlRotation.maxSpeed then
    local currentRotation = mcontroller.rotation()
    local angleDiff = util.angleDiff(currentRotation, angleTo)
    local diffSign = angleDiff > 0 and 1 or -1

    local targetSpeed = math.max(0.1, math.min(1, math.abs(angleDiff) / 0.5)) * self.controlRotation.maxSpeed
    local acceleration = diffSign * self.controlRotation.controlForce * dt
    self.rotationSpeed = math.max(-targetSpeed, math.min(targetSpeed, self.rotationSpeed + acceleration))
    self.rotationSpeed = self.rotationSpeed - self.rotationSpeed * self.controlRotation.friction * dt

    mcontroller.setRotation(currentRotation + self.rotationSpeed * dt)
  else
    mcontroller.setRotation(angleTo)
  end
end

function processTimedAction(action, dt)
  if action.complete then
    return
  elseif action.delayTime then
    action.delayTime = action.delayTime - dt
    if action.delayTime <= 0 then
      action.delayTime = nil
    end
  elseif action.loopTime then
    action.loopTimer = action.loopTimer or 0
    action.loopTimer = math.max(0, action.loopTimer - dt)
    if action.loopTimer == 0 then
      projectile.processAction(action)
      action.loopTimer = action.loopTime
      if action.loopTimeVariance then
        action.loopTimer = action.loopTimer + (2 * math.random() - 1) * action.loopTimeVariance
      end
    end
  else
    projectile.processAction(action)
    action.complete = true
  end
end

function destroy()
	if self.seekMode == 1 then
		world.sendEntityMessage(projectile.sourceEntity(), "projDead", entity.id(), self.kFlag)
	end
	
	----
	-- FX
	----
	
	local pParams = {}
	--table.insert(pParams, config.getParameter("actionFireReap"))
	
	-- look idk why actions aren't working but I would have to do 
	-- it this way anyway to pass on the color properties
	
	if self.seekMode == 3 then
		-- FIRED
		
		pParams = copy(config.getParameter("parametersFiredReap")) 
		
		pParams.actionOnReap[1].list[1].body[1].specification.color = self.tone
		world.spawnProjectile(
			"az-blitz_impact_fire",
			mcontroller.position(),
			projectile.sourceEntity() or false,
			{0, 0},
			false,
			pParams
			)
			
		--projectile.processAction(projectile.getParameter("actionOnFiredReap"))
	elseif self.seekMode == 2 then
		-- RETURNING
		
		pParams = copy(config.getParameter("parametersReturnReap"))
		
		pParams.actionOnReap[1].list[1].body[3].specification.color = self.tone
		
		world.spawnProjectile(
			"az-blitz_impact_return",
			mcontroller.position(),
			projectile.sourceEntity() or false,
			{0, 0},
			false,
			pParams
			)
			
		--projectile.processAction(projectile.getParameter("actionOnMiscReap"))
	else
		--MISC
		
		world.spawnProjectile(
			"az-blitz_impact_misc",
			mcontroller.position(),
			projectile.sourceEntity() or false,
			{0, 0},
			false
			)
	end

	--sb.logInfo("blitzproj: dead")
end

function msgKill()
	self.kFlag = true
	projectile.die()
end

function vecFlip(vec)
	return {-vec[1], -vec[2]}
end

function vecPrint(vecIn, decIn)

	local dec = decIn or 3
	--return "x" .. tostring(vecIn[1]) .. " : " .. "y" .. tostring(vecIn[2]) 
	return "x" .. round(vecIn[1], dec) .. " : " .. "y" .. round(vecIn[2], dec) 
end

function round(num, dec)
	return string.format("%." .. (dec or 0) .. "f", num)
end