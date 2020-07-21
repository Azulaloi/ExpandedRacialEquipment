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
	
	self.orbitRadius = config.getParameter("orbitRadius", 2.5)
	self.orbitGuide = config.getParameter("orbitGuide", {0, self.orbitRadius})
	
	self.cycle = 0
	
	self.kFlag = false
	
	self.firePos = {0, 0}
	
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
		if modeIn == 2 then mcontroller.applyParameters({collisionEnabled=false}) end
		self.seekMode = modeIn
	end)
end

function update(dt)
	if self.seekMode == 1 and self.entityToFollow ~= nil then
		orbitEntity(self.entityToFollow, dt)
	elseif self.seekMode == 2 and self.entityToFollow ~= nil then
		projectile.setTimeToLive(2)
		returnToEntity(self.entityToFollow, dt)
	elseif self.seekMode == 3 then
		--fire and forget behavior
		
		local ang = vecFlip(world.distance(mcontroller.position(), self.firePos))
		mcontroller.approachVelocity(vec2.mul(vec2.norm(ang), 50), 50)
		world.debugPoint(self.firePos, "red")
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

function orbitEntity(entityId, dt)
	if world.entityExists(entityId) then
		--projectile.setTimeToLive(5)
	
		local targetPosition = world.entityPosition(entityId)
		local targetDistance = self.orbitRadius
		local targetSpeed = 10
		local seekSpeed = 50
		
		local currentPosition = mcontroller.position()
		
		local flipDir = false
		local guidePos = self.orbitGuide --or {0, 0}
		local cycleSpeed = 5
		
		local speedMult = 0.1
		
		seekSpeed = seekSpeed * 0.2
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
		

		
		
		-- DEBUG -- 
		
		world.debugPoint(guidePos, "green")
		world.debugLine(currentPosition, guidePos, "green")
		--world.debugText(tostring(self.cycle), vec2.add(targetPosition, {4, 1}), "green")
		
		
		--util.debugCircle(targetPosition, targetDistance, "red", 8)
		world.debugLine(currentPosition, vec2.add(currentPosition, vec2.mul(targetDirection, math.abs(targetSpeed) / 3)), "blue")
		world.debugLine(currentPosition, edgePosition, "red")
		
		--world.debugText(tostring(edgeMixFactor), vec2.add(mcontroller.position(), {1, 1}), "green")
	end
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

	--sb.logInfo("blitzproj: dead")
end

function msgKill()
	self.kFlag = true
	projectile.die()
end

function vecFlip(vec)
	return {-vec[1], -vec[2]}
end