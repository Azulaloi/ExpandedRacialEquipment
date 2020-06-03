require "/scripts/util.lua"
require "/scripts/vec2.lua"

-- handles weapon stances, animations, and abilities
Weapon = {}

function Weapon:new(weaponConfig)
    local newWeapon = weaponConfig or {}
    newWeapon.damageLevelMultiplier = config.getParameter("damageLevelMultiplier", root.evalFunction("weaponDamageLevelMultiplier", config.getParameter("level", 1)))
    newWeapon.elementalType = config.getParameter("elementalType")
    newWeapon.muzzleOffset = config.getParameter("muzzleOffset") or {0,0}
    newWeapon.aimOffset = config.getParameter("aimOffset") or (newWeapon.muzzleOffset[2] - 0.25) -- why is it off by 0.25? nobody knows!

    newWeapon.abilities = {}
    newWeapon.shiftAbilities = {}
	newWeapon.primaryInternalShift = config.getParameter("abilityPrimaryInternalShift", false)
	newWeapon.secondaryInternalShift = config.getParameter("abilitySecondaryInternalShift", false)

    newWeapon.transformationGroups = {}
    newWeapon.handGrip = config.getParameter("handGrip", "inside")
    newWeapon.recoilToggle = config.getParameter("recoilToggle")
    newWeapon.cushion = config.getParameter("cushion") or 15
    newWeapon.scale = config.getParameter("scale") or {1, 1}
    setmetatable(newWeapon, extend(self))
    return newWeapon
end

function Weapon:init()
    self.attackTimer = 0
    self.aimAngle = 0
    self.aimDirection = 1

    animator.setGlobalTag("elementalType", self.elementalType or "")

    self.abilityTable = {}
    for _, ability in pairs(self.abilities) do
        if ability.abilitySlot ~= nil then
            self.abilityTable[ability.abilitySlot] = true
        end
    end

    self:checkAdd("alt", 2)
    self:checkAdd("shiftPrimary", 3)
    self:checkAdd("shiftAlt", 4)

    for _,ability in pairs(self.abilities) do
        ability:init()
    end

    if self.recoilToggle then self:initRecoil() end

end

function Weapon:checkAdd(select, int)
    if not self.abilityTable[select] == true then
        local ability = grabAbility(select)
        if ability then
            ability.select = int
            self:addAbility(ability)
        end
    end
end

function Weapon:initRecoil()
    self.cameraState = {0,0}
    self.cameraMove = {0,0}

    self.recoilId = nil
    if not self.recoilId then
        self:createRecoil()
    end
end

function Weapon:createRecoil()
    local recoil = world.spawnProjectile(
        "recoilProj",
        vec2.add(mcontroller.position(), self.cameraState),
        activeItem.ownerEntityId(),
        {0,0},
        false,
        nil
    )

    if recoil then
        activeItem.setCameraFocusEntity(recoil)
        self.recoilId = recoil
    end
end

function Weapon:update(dt, fireMode, shiftHeld, moves)

    self.time = player.playTime()
    self.attackTimer = math.max(0, self.attackTimer - dt)

    local select = 0
	
	
    if fireMode == "primary" then
        if shiftHeld then
			-- kind of a bandaid
            if self.primaryInternalShift then select = 1 else select = 3 end
        else
            select = 1
        end
    elseif fireMode == "alt" then
        if shiftHeld then
            select = 4
        else
            select = 2
        end
    end

    for _,ability in pairs(self.abilities) do
        if ability then
            if ability.select == select then
                ability:update(dt, ability.abilitySlot, shiftHeld, moves, self.time)
            else
                ability:update(dt, "none", shiftHeld, moves, self.time)
            end
        end
    end

    if self.currentState then
        if coroutine.status(self.stateThread) ~= "dead" then
            local status, result = coroutine.resume(self.stateThread)
            if not status then error(result) end
        else
            self.currentAbility:uninit()
            self.currentAbility = nil
            self.currentState = nil
            self.stateThread = nil
            if self.onLeaveAbility then
                self.onLeaveAbility()
            end
        end
    end

    if self.stance then
        self:updateAim()
        self.relativeArmRotation = self.relativeArmRotation + self.armAngularVelocity * dt
        self.relativeWeaponRotation = self.relativeWeaponRotation + self.weaponAngularVelocity * dt
    end

    if self.handGrip == "wrap" then
        activeItem.setOutsideOfHand(self:isFrontHand())
    elseif self.handGrip == "embed" then
        activeItem.setOutsideOfHand(not self:isFrontHand())
    elseif self.handGrip == "outside" then
        activeItem.setOutsideOfHand(true)
    elseif self.handGrip == "inside" then
        activeItem.setOutsideOfHand(false)
    end


    if self.recoilToggle then self:updateCamera() end
    self.cameraMove = {0, 0}
    self:clearDamageSources()
end

function Weapon:updateCamera()
    self.cameraState = {
        self:lerp(self.cameraState[1], self.cameraMove[1], self.cushion),
        self:lerp(self.cameraState[2], self.cameraMove[2], self.cushion)
    }

    if self.recoilId and world.entityExists(self.recoilId) then
        world.callScriptedEntity(self.recoilId, "script.setUpdateDelta", 1)
        world.callScriptedEntity(self.recoilId, "mcontroller.setPosition", vec2.add(mcontroller.position(), self.cameraState))
    else
        self:createRecoil()
    end
end

function Weapon:updateScale()
    animator.scaleTransformationGroup("weapon", self.scale)
end

function Weapon:lerp(v, t, s)
    return v + ((t - v)/s)
end

function Weapon:recoil(recoilVector)
    self.cameraMove = recoilVector
end

function Weapon:recoilManual(a, b)
    self.cameraMove = {a, b}
end

function Weapon:uninit()
    for _,ability in pairs(self.abilities) do
        if ability.uninit then
            ability:uninit(true)
        end
    end

    if self.recoilToggle then self:uninitCamera() end

end

function Weapon:uninitCamera()
    local id = self.recoilId
    if id then
        if world.entityExists(id) then
            world.callScriptedEntity(id, "projectile.die")
        end
    end
end

function Weapon:clearDamageSources()
    if not self.damageWasSet and not self.damageCleared then
        activeItem.setItemDamageSources({})
        self.damageCleared = true
    end

    if not self.ownerDamageWasSet and not self.ownerDamageCleared then
        activeItem.setDamageSources({})
        self.ownerDamageCleared = true
    end

    self.damageWasSet = false
    self.ownerDamageWasSet = false
end

function Weapon:setAbilityState(ability, state, ...)
    self.currentAbility = ability
    self.currentState = state
    self.stateThread = coroutine.create(state)
    local status, result = coroutine.resume(self.stateThread, ability, ...)
    if not status then
        error(result)
    end
end

function Weapon:addAbility(newAbility)
    newAbility.weapon = self

    if newAbility.select == nil then
        if newAbility.abilitySlot == "primary" then
            newAbility.select = 1
        elseif newAbility.abilitySlot == "alt" then
            newAbility.select = 2
        end
    end

    table.insert(self.abilities, newAbility)
end

function Weapon:addTransformationGroup(name, offset, rotation, rotationCenter)
    self.transformationGroups = self.transformationGroups or {}
    table.insert(self.transformationGroups, {name = name, offset = offset, rotation = rotation, rotationCenter = rotationCenter})
end

function Weapon:updateAim()
    for _,group in pairs(self.transformationGroups) do
        animator.resetTransformationGroup(group.name)
        animator.translateTransformationGroup(group.name, group.offset)
        animator.rotateTransformationGroup(group.name, group.rotation, group.rotationCenter)
        animator.translateTransformationGroup(group.name, self.weaponOffset)
        animator.rotateTransformationGroup(group.name, self.relativeWeaponRotation, self.relativeWeaponRotationCenter)
    end

    local aimAngle, aimDirection = activeItem.aimAngleAndDirection(self.aimOffset, activeItem.ownerAimPosition())

    if self.abilityAimOverride then
        self.aimAngle = self.abilityAimOverride -- new
    elseif self.stance.allowRotate then
        self.aimAngle = aimAngle
    elseif self.stance.aimAngle then
        self.aimAngle = self.stance.aimAngle
    end

    -- if self.abilityAimOverride then
    --   activeItem.setArmAngle(self.abilityAimOverride)
    -- else
    activeItem.setArmAngle(self.aimAngle + self.relativeArmRotation)
    -- end

    local isPrimary = activeItem.hand() == "primary"
    if isPrimary then
        -- primary hand weapons should set their aim direction whenever they can be flipped,
        -- unless paired with an alt hand that CAN'T flip, in which case they should use that
        -- weapon's aim direction
        if self.stance.allowFlip then
            if activeItem.callOtherHandScript("dwDisallowFlip") then
                local altAimDirection = activeItem.callOtherHandScript("dwAimDirection")
                if altAimDirection then
                    self.aimDirection = altAimDirection
                end
            else
                self.aimDirection = aimDirection
            end
        end
    elseif self.stance.allowFlip then
        -- alt hand weapons should be slaved to the primary whenever they can be flipped
        local primaryAimDirection = activeItem.callOtherHandScript("dwAimDirection")
        if primaryAimDirection then
            self.aimDirection = primaryAimDirection
        else
            self.aimDirection = aimDirection
        end
    end

    activeItem.setFacingDirection(self.aimDirection)

    activeItem.setFrontArmFrame(self.stance.frontArmFrame)
    activeItem.setBackArmFrame(self.stance.backArmFrame)
end

function Weapon:setOwnerDamage(damageConfig, damageArea, damageTimeout)
    self.ownerDamageWasSet = true
    self.ownerDamageCleared = false
    activeItem.setDamageSources({ self:damageSource(damageConfig, damageArea, damageTimeout) })
end

function Weapon:setOwnerDamageAreas(damageConfig, damageAreas, damageTimeout)
    self.ownerDamageWasSet = true
    self.ownerDamageCleared = false
    local damageSources = {}
    for i, area in ipairs(damageAreas) do
        table.insert(damageSources, self:damageSource(damageConfig, area, damageTimeout))
    end
    activeItem.setDamageSources(damageSources)
end

function Weapon:setDamage(damageConfig, damageArea, damageTimeout)
    self.damageWasSet = true
    self.damageCleared = false
    activeItem.setItemDamageSources({ self:damageSource(damageConfig, damageArea, damageTimeout) })
end

function Weapon:setDamageAreas(damageConfig, damageAreas, damageTimeout)
    self.damageWasSet = true
    self.damageCleared = false
    local damageSources = {}
    for i, area in ipairs(damageAreas) do
        table.insert(damageSources, self:damageSource(damageConfig, area, damageTimeout))
    end
    activeItem.setItemDamageSources(damageSources)
end

function Weapon:damageSource(damageConfig, damageArea, damageTimeout)
    if damageArea then
        local knockback = damageConfig.knockback
        if knockback and damageConfig.knockbackDirectional ~= false then
            knockback = knockbackMomentum(damageConfig.knockback, damageConfig.knockbackMode, self.aimAngle, self.aimDirection)
        end
        local damage = damageConfig.baseDamage * self.damageLevelMultiplier * activeItem.ownerPowerMultiplier()

        local damageLine, damagePoly
        if #damageArea == 2 then
            damageLine = damageArea
        else
            damagePoly = damageArea
        end

        return {
            poly = damagePoly,
            line = damageLine,
            damage = damage,
            trackSourceEntity = damageConfig.trackSourceEntity,
            sourceEntity = activeItem.ownerEntityId(),
            team = activeItem.ownerTeam(),
            damageSourceKind = damageConfig.damageSourceKind,
            statusEffects = damageConfig.statusEffects,
            knockback = knockback or 0,
            rayCheck = true,
            damageRepeatGroup = damageRepeatGroup(damageConfig.timeoutGroup),
            damageRepeatTimeout = damageTimeout or damageConfig.timeout
        }
    end
end

function Weapon:setStance(stance)
    self.stance = stance
    self.weaponOffset = stance.weaponOffset or {0,0}
    self.relativeWeaponRotation = util.toRadians(stance.weaponRotation or 0)
    self.relativeWeaponRotationCenter = stance.weaponRotationCenter or {0, 0}
    self.relativeArmRotation = util.toRadians(stance.armRotation or 0)
    self.armAngularVelocity = util.toRadians(stance.armAngularVelocity or 0)
    self.weaponAngularVelocity = util.toRadians(stance.weaponAngularVelocity or 0)

    for stateType, state in pairs(stance.animationStates or {}) do
        animator.setAnimationState(stateType, state)
    end

    for _, soundName in pairs(stance.playSounds or {}) do
        animator.playSound(soundName)
    end

    for _, particleEmitterName in pairs(stance.burstParticleEmitters or {}) do
        animator.burstParticleEmitter(particleEmitterName)
    end

    activeItem.setFrontArmFrame(self.stance.frontArmFrame)
    activeItem.setBackArmFrame(self.stance.backArmFrame)
    activeItem.setTwoHandedGrip(stance.twoHanded or false)
    activeItem.setRecoil(stance.recoil == true)
end

function Weapon:isFrontHand()
    return (activeItem.hand() == "primary") == (self.aimDirection < 0)
end

function Weapon:faceVector(vector)
    return {vector[1] * self.aimDirection, vector[2]}
end

-- Weapon abilities, state machines for weapon functionality

WeaponAbility = {}

function WeaponAbility:new(abilityConfig)
    local newAbility = abilityConfig or {}
    newAbility.stances = newAbility.stances or {}
    setmetatable(newAbility, extend(self))
    return newAbility
end

function WeaponAbility:update(dt, fireMode, shiftHeld, moves)
    self.dt, self.fireMode, self.shiftHeld, self.moves = dt, fireMode, shiftHeld, moves
end

function WeaponAbility:setState(state, ...)
    self.weapon:setAbilityState(self, state, ...)
end

function getAbility(abilitySlot, abilityConfig)
    for _, script in ipairs(abilityConfig.scripts) do
        require(script)
    end
    local class = _ENV[abilityConfig.class]
    abilityConfig.abilitySlot = abilitySlot
    return class:new(abilityConfig)
end

function grabAbility(select)
    local abilityConfig = config.getParameter( select .. "Ability")
    if abilityConfig and abilityConfig.scripts then
        if abilityConfig.isPrimary then
            return getAbility("primary", abilityConfig)
        else
            return getAbility("alt", abilityConfig)
        end
    else
        return nil
    end
end

function getPrimaryAbility()
    local primaryAbilityConfig = config.getParameter("primaryAbility")
    return getAbility("primary", primaryAbilityConfig)
end

function getAltAbility()
    local altAbilityConfig = config.getParameter("altAbility")
    if altAbilityConfig then
        return getAbility("alt", altAbilityConfig)
    end
end

function partDamageArea(partName, polyName)
    return animator.partPoly(partName, polyName or "damageArea")
end

function damageRepeatGroup(mode)
    mode = mode or ""
    return activeItem.ownerEntityId() .. config.getParameter("itemName") .. activeItem.hand() .. mode
end

function knockbackMomentum(knockback, knockbackMode, aimAngle, aimDirection)
    knockbackMode = knockbackMode or "aim"

    if type(knockback) == "table" then
        return knockback
    end

    if knockbackMode == "facing" then
        return {aimDirection * knockback, 0}
    elseif knockbackMode == "aim" then
        local aimVector = vec2.rotate({knockback, 0}, aimAngle)
        aimVector[1] = aimDirection * aimVector[1]
        return aimVector
    end
    return knockback
end

-- used for cross-hand communication while dual wielding
function dwAimDirection()
    if self and self.weapon then
        return self.weapon.aimDirection
    end
end

function dwDisallowFlip()
    if self.weapon and self.weapon.stance then
        return not self.weapon.stance.allowFlip
    end

    return false
end
