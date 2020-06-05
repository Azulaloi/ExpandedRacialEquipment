require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Reload for use with gunfireammo as primary
-- read and write parameter "rounds" as ammo
-- use Weapon:ammoCall(x) to alert x slot ability to update ammo

-- TODO: safety checks/helpful debug info for incorrect setups
-- such as missing properties that gunfireammo and reload share 
-- and are therefore not in the ability itself, specifically:
-- maxRounds, cursorAmmo, cursorDir
Reload = WeaponAbility:new()

function Reload:init()
	
	--if not pcall(self.checkWep()) then
	--	sb.logWarn('Reload (ability) initialized to incorrect weapon.lua, will not function correctly')
	--end
	
    self.cooldownTimer = self.fireTime
	
	self.rounds = config.getParameter("rounds", 6)
	self.maxRounds = config.getParameter("maxRounds", 3)
	self.cursorAmmo = config.getParameter("cursorAmmo", false)
	self.cursorDir = config.getParameter("cursorDir", "/cursors/6/azreticle")
end

function GunFire:checkWep()
	-- attempt to index nil value are you kidding me im just calling a function
	-- attempt to index more like why is everything made of TABLES
	-- HOW DO I CALL FUNCTIONS WITHOUT INDEXING MYSELF AAAAAAAAAA
	if self.weapon:checkAz() then
		return true else return false 
	end
end

function Reload:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
	
	if self.fireMode == (self.activatingFireMode or self.abilitySlot)
          and not self.weapon.currentAbility
          and self.cooldownTimer == 0
          and not status.resourceLocked("energy") then
		
		--self:setState(self.reloadState)
		self:setState(self.animArbitrary, 0)
	end
end

function Reload:cooldown()
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

-- this is no longer called, but I'll keep it a little longer
-- in case I need something to do a very simple reload without
-- any animation states.
function Reload:reloadState()
	self.weapon:setStance(self.stances.fire)
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self:doReload(1, false)
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end


-- args are optional, and can overrule ability config
function Reload:doReload(amountIn, replaceIn)
	if amountIn then 
		amount = amountIn 
	else amount = self.reloadQuantity end
	
	if not replaceIn == nil then
		replace = replaceIn
	else replace = self.reloadAdditive end

	local toReload
	if amount == -1 then
		toReload = self.maxRounds 
	else toReload = amount end
	
	if not replace then
		toReload = config.getParameter("rounds") + toReload
	end
	
	--add option for overloading
	if toReload > self.maxRounds then toReload = self.maxRounds end
	
	activeItem.setInstanceValue("rounds", toReload)
	self:reloadFx()
	self.weapon:ammoCall(1)
end

function Reload:reloadFx()
	animator.playSound("reload")
end

function Reload:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
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
    end

    return projectileId
end

function Reload:firePosition()
	--return vec2.add(mcontroller.position(), activeItem.handPosition(self.ejectOffset))
	
	-- in ability properties, use {"ejectPos" : partname} to specify a part with an ejectPos property
	-- that part just have an "ejectPos" property with a vec2 like so: {"ejectPos" : [x,y]}
	-- that position will inherit all transforms of its part
	if self.ejectPart then
		return vec2.add(mcontroller.position(), activeItem.handPosition(animator.partPoint(self.ejectPart, "ejectPos")))
	else --if no part is specified, just use the muzzle. this should probably be the center instead  
		return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
	end
end

function Reload:aimVector(inaccuracy)
    local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
    if self.ejectRotate then aimVector = vec2.rotate(aimVector, self.ejectRotate) end
	aimVector[1] = aimVector[1] * mcontroller.facingDirection()
    return aimVector
end

function Reload:energyPerShot()
    return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end

-- in case I want to add a gun that ejects giant shells that do damage idk lmao
function Reload:damagePerShot()
    return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount
end

function Reload:uninit()

end

-- TODO: read event flags (terminate, reload, eject) from the stances themselves 
function Reload:animArbitrary(iter)
	local stanceIn = "anim" .. tostring(iter)

	local terminateFlag = iter == self.terminateIteration
	
	local stanceOut
	if not terminateFlag then
		stanceOut = "anim" .. tostring(iter + 1)
	else stanceOut = "idle" end
	
	self.weapon:setStance(self.stances[stanceIn])
	
	local delta = 0
    util.wait(self.stances[stanceIn].duration, function()
        local alpha = self.stances[stanceIn].weaponOffset or {0,0}
        local beta = self.stances[stanceOut].weaponOffset or {0,0}

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances[stanceIn].weaponRotation, self.stances[stanceOut].weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances[stanceIn].armRotation, self.stances[stanceOut].armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances[stanceIn].duration))
    end)
	
	if iter == self.reloadIteration then
		self:doReload()
		
		-- TODO: ejection status should be stored in weapon like rounds
		-- such that one cannot anim cancel between ejection and reload
		-- and just spew ejection projectiles without reloading
		if self.eject then
			self:fireProjectile()
		end
	end
	
	if not terminateFlag then
		self:setState(self.animArbitrary, iter + 1)
	end
end