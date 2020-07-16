require "/scripts/util.lua"
require "/scripts/vec2.lua"

function init()
	self.controlMovement = config.getParameter("controlMovement")
	self.controlRotation = config.getParameter("controlRotation")
	self.rotationSpeed = 0
	self.timedActions = config.getParameter("timedActions", {})

	-- 0 seeks aimPos, 1 seeks entity
	self.seekMode = config.getParameter("seekMode", 1)
	
	self.aimPosition = mcontroller.position()
	
	self.entityToFollow = projectile.sourceEntity() or nil
	
	message.setHandler("updateProjectile", function(_, _, aimPosition)
		self.aimPosition = aimPosition
		return entity.id()
	end)
	
	message.setHandler("checkProjectile", function(_, _)
		projectile.setTimeToLive(5)
		return entity.id()
	end)
	
	message.setHandler("kill", function()
		projectile.die()
    end)
	
	message.setHandler("setEntityToFollow", function(_, _, entityId)
		self.entityToFollow = entityId
	end)
end

function update(dt)
	if self.seekMode == 1 and self.entityToFollow ~= nil then
		orbitEntity(self.entityToFollow)
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
	
	world.debugText(tostring(entity.id()), vec2.add(mcontroller.position(), {1, 1}), "green")
end

function orbitEntity(entityId)
	if world.entityExists(entityId) then
		--projectile.setTimeToLive(5)
	
		local targetPosition = world.entityPosition(entityId)
		local targetDistance = 2.5
		local targetSpeed = 50
		
		-- find closest position at the edge of the orbit
		local toCenterVector = vec2.sub(mcontroller.position(), targetPosition)
		local edgePosition = vec2.add(targetPosition, vec2.mul(vec2.norm(toCenterVector), targetDistance))
		
		-- get normalized direction to that position
		local toEdgeVector = vec2.sub(edgePosition, mcontroller.position())
		local toEdgeDirection = vec2.norm(toEdgeVector)
		
		-- mix in the direction of the orbit depending on how close we are
		local orbitDirection = vec2.norm(vec2.rotate(toCenterVector, math.pi / (targetSpeed > 0 and -2 or 2)))
		local edgeMixFactor = math.min(1, math.max(0, (vec2.mag(toEdgeVector) / targetDistance)))
		local targetDirection = vec2.add(vec2.mul(toEdgeDirection, edgeMixFactor), vec2.mul(orbitDirection, 1 - edgeMixFactor))
		
		-- move zig
		mcontroller.approachVelocity(vec2.mul(targetDirection, math.abs(targetSpeed)), 5000)
	end
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
