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
	self.loopsToDo = config.getParameter("loops", 3)
	
	self.releaseActionTimer = 0.1
	
	self.cycle = 0
	self.firePos = {0, 0}
	self.kFlag = false
	self.readyToRelease = false
	self.loopedOnce = false
	self.primeTimer = 1
	self.loops = 0
	self.loopBool = false
	self.releaseActioned = false
	
	self.fireReleasePos = false
	self.fireVector = false
	self.fireSourcePos = false
	
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
		actionSwitch("prime", 1)
		self.seekMode = 3
	end)
	
	message.setHandler("setMode", function(_, _, modeIn)
		if modeIn == 2 then 
			mcontroller.applyParameters({collisionEnabled=false})
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
			if not self.fireSourcePos then
				self.fireSourcePos = world.entityPosition(self.entityToFollow)
				self.fireReleasePos = mcontroller.position()
				self.fireVector = vecFlip(world.distance(self.fireSourcePos, self.firePos))
			end
			fireVec()
			
			self.releaseActionTimer = self.releaseActionTimer - dt
			if self.releaseActionTimer <= 0 and not self.releaseActioned then
				self.releaseActioned = true
				actionSwitch("release", 1) 
			end
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

-- TODO: slow initial emergence from player
-- TODO: cycle speed increases with primeTimer 

-- TODO: guide speed should not be applied to seek direction, as it's applying the guide speed as long as we are within the circle
-- which means whatever projectiles were in the direction we are moving can keep up, but the ones on the edge we move away from get dropped

-- TODO: reimplement adjustment along orbit... how can we have the projectile know when it was displaced from seeking or spacing?
-- maybe once it reaches a threshold from the edge, it will seek to its guide until close enough, then resume normal adjustment on orbit behavior

function orbitEntity(entityId, dt, primingIn)
	if world.entityExists(entityId) then
		local priming = primingIn or false
	
		local targetPosition = world.entityPosition(entityId)
		local targetDistance = self.orbitRadius
		local targetSpeed = 10
		local seekSpeed = 50
		
		local currentPosition = mcontroller.position()
		
		local flipDir = self.orbitClockwise
		local guidePos = guidePos or self.orbitGuide --or {0, 0}
		local cycleSpeed = 5
		
		local primeFactor = 1
		local primeMult = 2.8
		local speedMult = 1.0 * (priming and primeMult or 1) 
		
		seekSpeed = seekSpeed * 0.5
		targetSpeed = targetSpeed * speedMult
		cycleSpeed = cycleSpeed * speedMult
		
		if priming then
			self.primeTimer = self.primeTimer + dt
			guidePos = vec2.mul(guidePos, self.primeTimer * primeFactor)
		end
		
		self.cycle = self.cycle + ( ((dt * cycleSpeed) % 360) * (flipDir and 1 or -1) )
		local guideRot = vec2.rotate(guidePos, self.cycle)
		local guideAngle = math.atan(guideRot[2], guideRot[1])
		guidePos = vec2.add(targetPosition, guideRot)
		
		
		-- find closest position at the edge of the orbit
		local toCenterVector = vec2.sub(currentPosition, targetPosition)
		local edgePosition = vec2.add(targetPosition, vec2.mul(vec2.norm(toCenterVector), targetDistance))
		--local edgePosition = guidePos
		
		local orbitAngle = math.atan(toCenterVector[2], toCenterVector[1])
		
		-- get normalized direction to that position
		local toEdgeVector = vec2.sub(edgePosition, currentPosition)
		local toEdgeDirection = vec2.norm(toEdgeVector)
		
		local toGuideVector = vec2.sub(guidePos, currentPosition)
		local toGuideDirection = vec2.norm(toGuideVector)
		
		-- when we are in the circle, but not on our guide, we want to increase or decrease (whichever is closest)
		-- our speed until we are on the guide again. when we are not in the circle, we want to seek towards the guide position.
		
		-- if shortRot is negative then slow, otherwise fast
		local shortRot = shortestOrbit(orbitAngle, guideAngle, true)
		-- shortDir is true if should speed up
		local shortDir = (shortRot > 0) and true or false
		local shortMag = math.abs(shortRot) / 180
		
		-- mix in the direction of the orbit depending on how close we are
		--local orbitDirection = vec2.norm(vec2.rotate(toCenterVector, math.pi / (targetSpeed > 0 and -2 or 2)))
		local orbitDirection = vec2.norm(vec2.rotate(toCenterVector, math.pi / (flipDir and 2 or -2)))
		local edgeMixFactor = math.min(1, math.max(0, (vec2.mag(toEdgeVector) / 1)))
		local guideMixFactor = math.min(1, math.max(0, (vec2.mag(toGuideVector) / 1)))
		--local targetDirection = vec2.add(vec2.mul(toGuideDirection, edgeMixFactor), vec2.mul(orbitDirection, 1 - edgeMixFactor))
		local targetDirection = vec2.add(vec2.mul(toGuideDirection, guideMixFactor), vec2.mul(orbitDirection, 1 - guideMixFactor))
		
		
		
		
		-- mix in guidespeed depending on distance from guide
		local guideSpeed = 10
		--guideSpeed = guideSpeed * (shortDir and shortMag or math.min(-shortMag, 0))
		guideSpeed = guideSpeed * shortMag
		targetSpeed = targetSpeed * (guideSpeed * math.max(1 - edgeMixFactor, 0)) 
		
		-- mix in seekspeed depending on how far we are
		-- 0.03 is from centrifugal force (I guess) - might need testing with other orbit speeds
		targetSpeed = targetSpeed + (seekSpeed * math.max(edgeMixFactor - 0.03, 0))
		
		-- move zig
		mcontroller.approachVelocity(vec2.mul(targetDirection, math.abs(targetSpeed)), 5000)
		
		
		--	PRIMING --
		local anchor = 1.5708
		local ancThresh = 0.7854
	
		if priming then
			local shouldLoop = true
			local flag = false
			local toFirePos = vec2.sub(targetPosition, self.firePos)
			local toFireAng = math.atan(toFirePos[2], toFirePos[1])
			
			local anchorVec = {0,0}			
			anchorVec = vec2.rotate(vec2.withAngle(flipdir and -anchor or anchor, 4), toFireAng)
			flag = angleWithin(orbitAngle, math.atan(anchorVec[2], anchorVec[1]), ancThresh)
			
			if shouldLoop then 
				if not flag then
					self.loopBool = true
				end
			
				if flag then
					if self.loopBool then
						self.loops = self.loops + 1
						self.loopBool = false
					end
				
					if (self.loops >= self.loopsToDo) and not self.readyToRelease then 
						self.readyToRelease = true 
					end
				end
			elseif flag and not self.readyToRelease then
				self.readyToRelease = true 
			end
			
			local col = flag and "green" or "white"
			world.debugLine(targetPosition, vec2.add(targetPosition, vec2.withAngle(orbitAngle, 3)), col)
			world.debugLine(targetPosition, vec2.add(targetPosition, anchorVec), "blue")
			--world.debugLine(targetPosition, self.firePos, "green")
			--world.debugText(tostring(orbitAngle), vec2.add(targetPosition, {4, 6}), "green")
		end
		
		-- DEBUG -- 
		world.debugPoint(guidePos, "green")
		world.debugLine(currentPosition, guidePos, "green")
		world.debugLine(currentPosition, vec2.add(currentPosition, vec2.mul(targetDirection, math.abs(targetSpeed) / 3)), "blue")
		world.debugLine(currentPosition, edgePosition, "red")
		
		--world.debugText("diff: " .. round(shortRot, 3), vec2.add(targetPosition, {4, 5}), "green")
		--world.debugText("oAng: " .. round(orbitAngle, 3), vec2.add(targetPosition, {4, 6}), "green")
		world.debugText("loops: " .. tostring(self.loops), vec2.add(targetPosition, {4, 6}), "green")
		
		--util.debugCircle(targetPosition, targetDistance, "red", 8)
		--world.debugText(tostring(edgeMixFactor), vec2.add(mcontroller.position(), {1, 1}), "green")
		--world.debugText(tostring(self.cycle), vec2.add(targetPosition, {4, 1}), "green")
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

function fireVec()
	local pPos = mcontroller.position()
	
	--local ang = vecFlip(world.distance(pPos, self.firePos))
	--mcontroller.approachVelocity(vec2.mul(vec2.norm(ang), 50), 50)
	
	local distFromSource = world.distance(pPos, self.fireReleasePos)
	
	
	local alignVector = closestPointOnVector(self.fireSourcePos, self.fireVector, pPos)
	local toAlignVec = world.distance(pPos, alignVector)
	local distAlign = vec2.mag(toAlignVec)
	local aMixMult = 5
	local alignMixFactor = math.min(1, math.max(0, (distAlign / aMixMult)))
	
	
	-- mix in direction to fireVector depending on how far we are from it and the source
	
	local targetDirection = vec2.add(vec2.mul(vec2.norm(vecFlip(toAlignVec)), distAlign / 2), 
									 --vec2.mul(vec2.norm(self.fireVector), math.max(0 - alignMixFactor, 0)))
									 vec2.mul(vec2.norm(self.fireVector), 1)) 
	mcontroller.approachVelocity(vec2.mul(vec2.norm(targetDirection), 50), 150) -- should adjust the control force depending on how far we are
	
	
	local targetPosition = world.entityPosition(self.entityToFollow)
	local segEnd = alongAngle(self.fireSourcePos, self.fireVector, 30)
	world.debugLine(self.fireSourcePos, segEnd, "white")
	--world.debugLine(pPos, closestPoint2(self.fireSourcePos, segEnd, pPos), "green")
	world.debugLine(pPos, alignVector, "red")
	world.debugPoint(self.firePos, "red")
	
	world.debugText("distAlign: " .. tostring(distAlign), vec2.add(targetPosition, {4, 5}), "green")
	world.debugText("alignMix: " .. tostring(alignMixFactor), vec2.add(targetPosition, {4, 4}), "green")
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
	
	-- FX
	if self.seekMode == 3 then
		-- FIRED
		actionSwitch("firedImpact", 1)
	elseif self.seekMode == 2 then
		-- RETURNING
		actionSwitch("return", 1)
	else
		--MISC
		actionSwitch("misc", 1)
	end

	--sb.logInfo("blitzproj: dead")
end

function msgKill()
	self.kFlag = true
	projectile.die()
end

-- who knew you could put functions in a table
function actionSwitch(case, countIn)
	local count = countIn or 1
	local tab = {
		["firedImpact"] = function() 
			local params = copy(config.getParameter("parametersFiredImpact"))
				
			params.actionOnReap[1].list[1].body[1].specification.color = self.tone
			
			return params
		end,
		
		["return"] = function()
			local params = copy(config.getParameter("parametersReturnReap"))
				
			params.actionOnReap[1].list[1].body[3].specification.color = self.tone
			
			return params
		end,
		
		["misc"] = function()
			local params = copy(config.getParameter("parametersReturnReap"))
				
			params.actionOnReap[1].list[1].body[3].specification.color = self.tone
			
			return params
		end,
		
		["prime"] = function()
			local params = copy(config.getParameter("parametersPrime"))
				
			params.actionOnReap[1].list[1].body[1].specification.color = self.tone
			
			return params
		end,
		
		["release"] = function()
			local params = copy(config.getParameter("parametersPrimeRelease"))
				
			params.actionOnReap[1].list[1].body[1].specification.color = self.tone
			
			return params
		end
	}
	
	pParams = type(tab[case]) == "function" and tab[case]() or {}
	
	for i = 1, count do
		world.spawnProjectile(
			"az-blitz_action",
			mcontroller.position(),
			projectile.sourceEntity() or false,
			{0, 0},
			false,
			pParams )
	end
end

-- UTIL -- 

function shortestOrbit(curIn, tarIn, radIn)
	local radBool = radIn or false
	
	local cur = radBool and (curIn * 180/math.pi) or curIn
	local tar = radBool and (tarIn * 180/math.pi) or tarIn

	local a = tar - cur
	local b = tar - cur + 360
	local y = tar - cur - 360
	
	local tab = {a, b, y}
	
	local ind, val = 1, tab[1]
	for k, v in ipairs(tab) do
		if math.abs(tab[k]) < math.abs(val) then
			ind, val = k, v
		end
	end
	
	--sb.logInfo("motion: " .. tostring(tab[ind]))
	return tab[ind]
end

function angleDifference(alpha, beta, radIn)
	local a = radBool and (alpha * 180/math.pi) or alpha
	local b = radBool and (beta * 180/math.pi) or beta

	local rawDiff = (a > b) and (a - b) or (b - a)
	local modDiff = rawDiff % 360
	
	--return 180 - math.abs(modDiff-180)
	return modDiff
end

function angleWithin(angle, anchor, thresh)
	return (angle >= (anchor - thresh) and angle <= (anchor + thresh))
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

-- problems with this one
-- it just points to the closest end
function closestPointOnLine(a, b, p)
	local ap = world.distance(p, a)
	local ab = world.distance(b, a)
	
	local abMag = vec2.mag(ab)
	local product = vec2.dot(ap, ab)
	local dist = product / abMag
	
	if (dist < 0) then return a
	elseif (dist > 1) then return b
	--else return vec2.mul(vec2.add(a, ab), dist) end
	else return vec2.add(a, vec2.mul(ab, dist)) end
end

-- problems here too...
-- it seems to stretch into infinity or something but works when p is close to a
function closestPoint2(a, b, p)
	ap = {p[1] - a[1], p[2] - a[2]}
	ab = {b[1] - a[1], b[2] - a[2]}
	
	abMag = (ab[1] * 2) + (ab[2] * 2)
	dot = (ap[1] * ab[1]) + (ap[2] * ab[2])
	
	t = dot / abMag
	
	--return {a[1] + ab[1] * t, a[2] + ab[2] * t}
	return {a[1] + (ab[1] * t), a[2] + (ab[2] * t)}
end

-- this one works! it's for vectors/rays rather than segments but that's fine 
function closestPointOnVector(origin, angleVector, point)
	local dir = vec2.norm(angleVector)
	local a = world.distance(point, origin)
	
	local dot = vec2.dot(a, dir)
	return vec2.add(origin, vec2.mul(dir, dot))
end

function alongAngle(pos, angle, dist)
	local u = vec2.norm(angle)
	local du = vec2.mul(u, dist)
	return vec2.add(pos, du)
end