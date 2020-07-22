require "/scripts/vec2.lua"
require "/scripts/util.lua"
require "/scripts/colorutil.lua"

-- TODO: shift + activate for alt mode
-- TODO: multiple rings of projectiles?
-- TODO: impact effects (particles when u smack into things)
-- TODO: light rays like the nova staff 
-- TODO: stop spinning. maybe lean away from x vel? or rotate oppo of vel like a meteor
-- TODO: dash?

function init()
	self.projectiles = self.projectiles or {}

	initCommonParameters()
	--initColorator()
	initProjectiles()
	initTrailDefaults()
	initHandlers()
	
	self.coloratorInitalized = false
	
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
  
  -- movement stuff --
  self.hoverDist = config.getParameter("hoverDistance", 4)
  self.hoverRepelForce = config.getParameter("hoverRepelForce", 5)
  
  self.moveSpeed = config.getParameter("moveSpeed", 50)
  self.moveForce = config.getParameter("moveForce", 300)
  
  -- projectile stuff -- 
  self.projectileType = config.getParameter("projectileType", "az-novablitz_swarm")
  self.projectileParameters = config.getParameter("projectileParameters") or {}
  self.projOrbitRadius = config.getParameter("projectileOrbitRadius", 2.5)
  self.projOrbitClockwise = config.getParameter("projectileOrbitClockwise", true)
  self.projectileCount = config.getParameter("projectileCount", 5)
  
  self.projReplaceWait = config.getParameter("projectileRegenTimer", 3)
  self.projReplaceTimer = self.projReplaceWait
  
  self.checkTimer = 3
  self.checkTime = 3
  
  self.fireTimer = 0
  self.fireTime = config.getParameter("fireCooldown", 0.5)
  
  self.altTimer = 0
  self.altTime = 0.2
  
  self.pDirty = false
end

function initHandlers()
	message.setHandler("projDead", function(_, _, id, flag)
		projDead(id, flag)
	end)
end

function initColorator()
	local id = entity.id()
	self.bodyColors = {0, 0, 0}
	
	if id then
		self.bodyColors = extractTone(id)
		self.dexed = hextorgb(self.bodyColors[2])
		hsl = rgbtohsl(self.dexed)
		hsl[2] = 0.7
		hsl[3] = 0.45
		prepGlow = hsltorgb(hsl)
		
		--sb.logInfo("NovaBlitz RGB: " .. "R" .. tostring(prepGlow[1]) .. "G" .. tostring(prepGlow[2]) .. "B" .. tostring(prepGlow[3]))
		
		
		local extDir = extractDirectives(id)
		--directives = string.sub(directives, 65, -1)
		self.directives = string.sub(extDir, 1, 63)
		
		animator.setGlobalTag("novaTone", self.directives)
		
		
		
		-- this is a brute force method, don't ship this
		-- instead, put the specific tones present in the final sprites into a table
		glowTable = {"FDE03F", "FEE03F", "FEE03E"} 
		local glowTone = self.directives
		for i = 1, 255 do 
			for k, v in ipairs(glowTable) do
				local alpha = string.format("%x", tostring(i))
				if #alpha == 1 then alpha = alpha .. 0 end
				local str = ";" .. string.lower(v) .. alpha .. "=" .. 
					tostring(self.bodyColors[2]) .. alpha  
				glowTone = glowTone .. str
			end
		end
		
		animator.setGlobalTag("glowTone", glowTone)
		--sb.logInfo(tostring(glowTone))
		
		
		--local portrait = world.entityPortrait(id, "full")

		--for k,v in ipairs(portrait) do
		--	sb.logInfo(tostring(k))
		--end
		--sb.logInfo(sb.printJson(portrait))
		
		local brand = extractImage(id, "/humanoid/novakid/brand/")
		brand = sb.printJson(brand)
		brand = brand:sub(2)
		brand = brand:sub(0, #brand-1)
		sb.logInfo("brand: " .. brand)
		animator.setGlobalTag("brandImage", brand) 
		
		self.coloratorInitalized = true
	end
end

function extractImage(pid, str)
    --local directives = ""
	local image = nil
	
    local portrait = world.entityPortrait(pid, "full")

    for k, v in pairs(portrait) do
        if string.find(portrait[k].image, str) then
            image = portrait[k].image
            --local directive_location = string.find(body_image, "replace")
            --directives = string.sub(body_image,directive_location)
        end
    end
	
	return image
end

function uninit()
  storePosition()
  deactivate()
end

function update(args)
  if not self.coloratorInitalized then
	-- extractTone doesn't work in init
	initColorator()
  end

  restoreStoredPosition()

  if not self.specialLast and args.moves["special1"] then
    attemptActivation()
  end
  self.specialLast = args.moves["special1"]

  if not args.moves["special1"] then
    self.forceTimer = nil
  end

  if self.active then
	local lv = self.mnum * vec2.mag(mcontroller.velocity())
	spawnTrail(mcontroller.position(), mcontroller.velocity(), lv, false, true)
  
    mcontroller.controlParameters(self.transformedMovementParameters)
	--mcontroller.controlParameters({gravityMultiplier = 0})
    status.setResourcePercentage("energyRegenBlock", 1.0)
	
	doControl(args)
	doHover(args)

    --updateAngularVelocity(args.dt)
    --updateRotationFrame(args.dt)

    checkForceDeactivate(args.dt)
	
	-- we don't need to update projectiles every frame
	updateProjectiles(args.dt)
	
	self.fireTimer = math.max(self.fireTimer - args.dt, 0)
	if args.moves["primaryFire"] and (self.fireTimer <= 0) then
		doFire()
	end
	
	self.altTimer = math.max(self.altTimer - args.dt, 0)
	if args.moves["altFire"] and (self.altTimer <= 0) then
		replaceProjectiles(1)
		self.altTimer = self.altTime
	end
	
	
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
		
		local pos = mcontroller.position()
		
		--world.debugText("dirty: " .. (self.dirty and "true" or "false"), vec2.add(mcontroller.position(), {4, 2}), "green")
		
		
		world.debugText("resTimer: " .. round(self.projReplaceTimer, 2), vec2.add(mcontroller.position(), {4, 2}), "green")
		world.debugText("fireTimer: " .. round(self.fireTimer, 2), vec2.add(mcontroller.position(), {4, 1.5}), "green")
		world.debugText("projCount: " .. tostring(#self.projectiles), vec2.add(mcontroller.position(), {4, 1}), "green")
		
		util.debugCircle(mcontroller.position(), self.projOrbitRadius, "red", 8)
		
		
		--world.debugText("Projectiles: ", vec2.add(pos, {8, 2}), "green")
		--for i = 1, #self.projectiles do
		--	local pY = 2 - (0.5 * i)
		--	world.debugText("[" .. tostring(i) .. "]", vec2.add(pos, {8, pY}), "green")
		--	world.debugText(tostring(self.projectiles[i]), vec2.add(pos, {9, pY}), "green")
		--end
	end
end

function doControl(args)
	local fSpeed = self.moveSpeed
	local cForce = self.moveForce
	local xV = 0
	local yV = 0
	
	if args.moves["left"] then xV = 0 - fSpeed
	elseif args.moves["right"] then xV = fSpeed
	else xV = 0 end
	
	if args.moves["up"] then yV = fSpeed
	elseif args.moves["down"] then yV = 0 - fSpeed
	else yV = 0 end
	
	if (args.moves["up"] or args.moves["down"]) and (args.moves["left"] or args.moves["right"]) then
		xV = (xV / 3) * 2
		yV = (yV / 3) * 2
	end
	
	mcontroller.controlApproachVelocity({xV, yV}, cForce)
end

function doHover(args)
	local hoverTo = self.hoverDist
	local hoverSpeed = 55
	local hoverConForce = 200
	
	local hoverForce2 = self.hoverRepelForce
	
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
  
  sb.logInfo("blitz: activating")
	
 -- checkProjectiles()
  createProjectiles(self.projectileCount, true, true)
  
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
  
  sb.logInfo("blitz: deactivating")
  killProjectiles(true)
  
  -- somehow, checking right after killing makes them not die
  --checkProjectiles()
  
  self.active = false
end

----
-- projectile stuff
----

function doFire()
	self.fireTimer = self.fireTime
	local pos = tech.aimPosition()
	
	if self.projectiles[1] then
		world.sendEntityMessage(self.projectiles[1], "fireAtPos", pos)
		table.remove(self.projectiles, 1)
		animator.playSound("fire")
		markDirty(true)
	end
end

function createProjectiles(countIn, circleIn, replaceIn)
	local createPos = mcontroller.position()
	local projCount = countIn or self.projectileCount or 5
	local repFlag = replaceIn or false
	
	--local cPoints = circleIn and pointsCircle(projCount, self.projOrbitRadius) or {0, 0}
	local cPoints = pointsCircle(5, self.projOrbitRadius)
	
	--util.mergeTable(self.projectileParameters, { periodicActions[1].specification = { color = hextorgb(self.bodyColors[2]) } } )
	--util.mergeTable(self.projectileParameters, { processing = "?" .. self.directives } )
	
	if repFlag then
		for i = 1, #self.projectiles do 
			world.sendEntityMessage(self.projectiles[i], "setOrbitGuide", cPoints[i])
		end
	end
	
	local tone = hextorgb(self.bodyColors[2])
	local pParams = copy(self.projectileParameters)
	pParams.processing = "?" .. self.directives
	pParams.periodicActions[1].specification.color = tone
	pParams.tone = tone
	pParams.orbitRadius = self.projOrbitRadius
	pParams.orbitClockwise = self.projOrbitClockwise
	
	sb.logInfo("blitz: creating " .. tostring(projCount) .. " projectiles")
	for i = 1, projCount do
		--local p = circleIn and cPoints[i] or {0, 0}
		local iter = i
		--if repflag then iter = #self.projectiles + i
		local iter = repFlag and (#self.projectiles + 1) or i  
		--sb.logInfo(tostring(repFlag)..tostring(#self.projectiles))
		--sb.logInfo("blitz: creating proj #" .. tostring(iter))
		local p = repFlag and {0, 0} or cPoints[iter]
		pParams.orbitGuide = p
		
		--sb.logInfo(vecPrint(createPos) .. vecPrint(p))
	
		local projId = world.spawnProjectile(
			self.projectileType,
			vec2.add(createPos, p),
			entity.id(),
			{0, 0},
			false,
			pParams
			)

		if projId then
			table.insert(self.projectiles, projId)
		end
	end
	
	adjustProjectiles()
end

function updateProjectiles(dt)
	if self.checkTimer <= 0 then checkProjectiles(dt, true) end
	self.checkTimer = math.max(self.checkTimer - dt, 0)
	
	-- todo: listen instead of polling
	if #self.projectiles < self.projectileCount then
		--sb.logInfo("blitz: proj dirty")
		--self.pDirty = true
		
		self.projReplaceTimer = math.max(self.projReplaceTimer - dt, 0) 

		if self.projReplaceTimer <= 0 then
		-- disabled for testing
		--	replaceProjectiles(1)
		end
	end
	
	if self.pDirty then 
		checkProjectiles()
		adjustProjectiles()
	end
end

function checkProjectiles(dt, routine)
	self.projectiles = self.projectiles or {}
	local rFlag = routine or false
	
	local sufx = rFlag and " (routine)" or ""
	sb.logInfo("blitz: checking " .. tostring(#self.projectiles) .. " projectiles" .. sufx)

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
		end
	end

	if rFlag then self.checkTimer = self.checkTime end
	
	self.projectiles = newProjectiles
end 

function adjustProjectiles()
	self.pDirty = false
	
	if #self.projectiles > 0 then
		local cPoints = pointsCircle(#self.projectiles, self.projOrbitRadius)
		
		--local cycle = 0
		--local b1 = false
		
		--if #self.projectiles > 0 then b1 = world.entityExists(self.projectiles[1]) end
		
		local b1 = world.entityExists(self.projectiles[1])
		local cycle = world.sendEntityMessage(self.projectiles[1], "getCycle")
		
		if b1 and cycle:finished() then
			sb.logInfo("blitz: p[1] exists, aligning " .. tostring(#self.projectiles) .. " projectiles")
			for i = 1, #self.projectiles do
				local id = self.projectiles[i]	
				--sb.logInfo("blitz: adjust proj" .. tostring(id) .. " | new pos: " .. vecPrint(cPoints[i]))
				world.sendEntityMessage(id, "setOrbitAndCycle", cPoints[i], cycle:result())
			end
		elseif not b1 then
			sb.logInfo("blitz: p[1] missing, defaulting " .. tostring(#self.projectiles) .. " projectiles")
			for i = 1, #self.projectiles do
				local id = self.projectiles[i]
				--sb.logInfo("blitz: adjust proj" .. tostring(id) .. " | new pos: " .. vecPrint(cPoints[i])) 
				world.sendEntityMessage(id, "setOrbitAndCycle", cPoints[i], 0)
			end
		end
	end
end

function replaceProjectiles(countIn)
	local toReplace = countIn or (self.projectileCount - #self.projectiles)
	sb.logInfo("blitz: replacing " .. tostring(toReplace) .. " projectiles")
	
	createProjectiles(toReplace, false, true)
	
	self.projReplaceTimer = self.projReplaceWait
	
	self.pDirty = true
	--adjustProjectiles()
end

function killProjectiles(flag)
	sb.logInfo("blitz: killing " .. tostring(#self.projectiles) .. " projectiles")
	
	for k, v in pairs(self.projectiles) do
		--sb.logInfo("p: " .. tostring(k) .. tostring(v))
		--sb.logInfo("blitz: killing slot " .. tostring(k) .. " (" .. tostring(v) .. ")")
		--world.sendEntityMessage(v, "kill")
		world.sendEntityMessage(v, "setMode", 2)
	end
	
	--for i, v in ipairs(self.projectiles) do
		--sb.logInfo("i: " .. tostring(i) .. tostring(v))
	--end
	
	if flag then self.projectiles = {} end
end

-- flag is true if projectile was told to die
function projDead(deadId, flag)
	if not flag then 
		sb.logInfo("blitz: death received (" .. tostring(deadId) .. ")")
	end
	
	self.projReplaceTimer = self.projReplaceWait
	
	markDirty(flag and false or true)
	
	--table.remove(self.projectiles, tableFind(self.projectiles, deadId))
	--adjustProjectiles()
end

-- if boo2, set dirty to boo1. otherwise, set dirty to boo1 only if boo1 is true
function markDirty(boo1, boo2)
	if boo2 then self.pDirty = boo1 
	elseif self.pDirty then return else self.pDirty = boo1 end
end

-- trail stuff --

function initTrailDefaults()
	self.mnum = 0.1339

	default = {}
	default.thiccness = 2.5
	default.lifeTime = 0.4
	default.destTime = 0.4
	default.destAction = "shrink"
	default.fullbright = true
	default.layer = "back"
	default.color = {190, 190, 190, 200}
	
	default.thiccVar = 0
	default.colorVar = {0, 0, 0, 0}
end

function spawnTrail(posIn, velIn, lengthIn, destBool, velBool)
	local param = {}

	useVel = velBool or true
	local v = {0, 0}
	
	if useVel and not destBool then 		
		v = alongAngle({0, 0}, mcontroller.velocity(), {0, 0})
	end

	local trailColor = default.color
	if self.coloratorInitalized then
		trailColor = self.dexed
		trailColor[4] = 200
	end
	
	return world.spawnProjectile("azdebug", posIn, 0, {0, 0}, false, {
	timeToLive = 0.0,
	actionOnReap = {
	{
		action = "particle",
		specification = {
		  type = "streak",
          layer = param.layer or default.layer,
          fullbright = param.fullbright or default.fullbright,
          destructionAction = param.destAction or default.destAction,
          size = param.thiccness or default.thiccness,
          color = trailColor,
          collidesForeground = false,
          length = lengthIn,
          position = v,
          timeToLive = param.lifeTime or default.lifeTime,
          destructionTime = param.destTime or default.destTime,
          initialVelocity = vec2.mul(vec2.norm(velIn), 0.1),
		  --fade = 1,
          variance = {
            size = param.thiccVar or default.thiccVar,
			color = param.colorVar or default.colorVar,
            --destructionTime = 0.55,
		    initialVelocity = {0, 0},
            length = 0
          }
		}
	  }
	}
	})
end


----
-- util stuff
----

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

function round(num, dec)
	return string.format("%." .. (dec or 0) .. "f", num)
end

function vecPrint(vecIn, decIn)

	local dec = decIn or 3
	--return "x" .. tostring(vecIn[1]) .. " : " .. "y" .. tostring(vecIn[2]) 
	return "x" .. round(vecIn[1], dec) .. " : " .. "y" .. round(vecIn[2], dec) 
end

function tableFind(tabIn, valIn) 
	for i, v in pairs(tabIn) do
		if v == valIn then
			return i
		end
	end
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

function alongAngle(pos, angle, dist)
	local u = vec2.norm(angle)
	local du = vec2.mul(u, dist)
	return vec2.add(pos, du)
end