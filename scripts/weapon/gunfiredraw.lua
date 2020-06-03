require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Base gun fire ability
GunFire = WeaponAbility:new()

function GunFire:init()
    self:setState(self.equip)

    self.cooldownTimer = self.stances.equip.duration

    self.weapon.onLeaveAbility = function()
        self.weapon:setStance(self.stances.idle)
    end

end

function GunFire:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)

    if animator.animationState("firing") ~= "fire" then
        animator.setLightActive("muzzleFlash", false)
    end

    if self.fireMode == (self.activatingFireMode or self.abilitySlot)
            and not self.weapon.currentAbility
            and self.cooldownTimer == 0
            and not status.resourceLocked("energy")
            and not world.lineTileCollision(mcontroller.position(), self:firePosition()) then

        if self.fireType == "auto" and status.overConsumeResource("energy", self:energyPerShot()) then
            self:setState(self.auto)
        elseif self.fireType == "burst" then
            self:setState(self.burst)
        end
    end
end

function GunFire:auto()
    self.weapon:setStance(self.stances.fire)

    self:fireProjectile()
    self:muzzleFlash()

    if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end

    self.cooldownTimer = self.fireTime
    self:setState(self.kick)
end

function GunFire:burst()
    self.weapon:setStance(self.stances.fire)

    local shots = self.burstCount
    while shots > 0 and status.overConsumeResource("energy", self:energyPerShot()) do
        self:fireProjectile()
        self:muzzleFlash()
        shots = shots - 1

        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(1 - shots / self.burstCount, 0, self.stances.fire.armRotation))

        util.wait(self.burstTime)
    end

    self.cooldownTimer = (self.fireTime - self.burstTime) * self.burstCount
end

function GunFire:cooldown()
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

function GunFire:muzzleFlash()
    animator.setPartTag("muzzleFlash", "variant", math.random(1, 3))
    animator.setAnimationState("firing", "fire")
    animator.burstParticleEmitter("muzzleFlash")
    animator.playSound("fire")

    animator.setLightActive("muzzleFlash", true)
end

function GunFire:fireProjectile(projectileType, projectileParams, inaccuracy, firePosition, projectileCount)
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

    if self.weapon.recoilToggle then
        self.weapon:recoil({
            (math.random(self.recoilXAlpha) - self.recoilXBeta) / self.recoilXDividend,
            (math.random(self.recoilYAlpha) - self.recoilYBeta) / self.recoilYDividend})
    end

    return projectileId
end

function GunFire:firePosition()
    return vec2.add(mcontroller.position(), activeItem.handPosition(self.weapon.muzzleOffset))
end

function GunFire:aimVector(inaccuracy)
    local aimVector = vec2.rotate({1, 0}, self.weapon.aimAngle + sb.nrand(inaccuracy, 0))
    aimVector[1] = aimVector[1] * mcontroller.facingDirection()
    return aimVector
end

function GunFire:energyPerShot()
    return self.energyUsage * self.fireTime * (self.energyUsageMultiplier or 1.0)
end

function GunFire:damagePerShot()
    return (self.baseDamage or (self.baseDps * self.fireTime)) * (self.baseDamageMultiplier or 1.0) * config.getParameter("damageLevelMultiplier") / self.projectileCount
end

function GunFire:uninit()
    --local id = self.recoilId
    --if id then
    --  if world.entityExists(id) then
    --    world.sendEntityMessage(id, "return")
    --  end
    --end
end

function GunFire:equip()
    self.weapon:setStance(self.stances.equip)

    local delta = 0
    util.wait(self.stances.equip.duration, function()
        local alpha = self.stances.equip.weaponOffset or {0,0}
        local beta = self.stances.equip1.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip.weaponRotation, self.stances.equip1.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip.armRotation, self.stances.equip1.armRotation))

        delta = math.min(1.0, delta + (self.stances.equip.duration))
    end)

    self:setState(self.equip1)
end

function GunFire:equip1()
    self.weapon:setStance(self.stances.equip1)

    local delta = 0
    util.wait(self.stances.equip1.duration, function()
        local alpha = self.stances.equip1.weaponOffset or {0,0}
        local beta = self.stances.equip2.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip1.weaponRotation, self.stances.equip2.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip1.armRotation, self.stances.equip2.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.equip1.duration))
    end)

    self:setState(self.equip2)
end

function GunFire:equip2()
    self.weapon:setStance(self.stances.equip2)

    local delta = 0
    util.wait(self.stances.equip2.duration, function()
        local alpha = self.stances.equip2.weaponOffset or {0,0}
        local beta = self.stances.equip3.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip2.weaponRotation, self.stances.equip3.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip2.armRotation, self.stances.equip3.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.equip2.duration))
    end)

    self:setState(self.equip3)
end

function GunFire:equip3()
    self.weapon:setStance(self.stances.equip3)

    local delta = 0
    util.wait(self.stances.equip3.duration, function()
        local alpha = self.stances.equip3.weaponOffset or {0,0}
        local beta = self.stances.equip4.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip3.weaponRotation, self.stances.equip4.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip3.armRotation, self.stances.equip4.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.equip3.duration))
    end)

    self:setState(self.equip4)
end

function GunFire:equip4()
    self.weapon:setStance(self.stances.equip4)

    local delta = 0
    util.wait(self.stances.equip4.duration, function()
        local alpha = self.stances.equip4.weaponOffset or {0,0}
        local beta = self.stances.equip5.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip4.weaponRotation, self.stances.equip5.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip4.armRotation, self.stances.equip5.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.equip4.duration))
    end)

    self:setState(self.equip5)
end

function GunFire:equip5()
    self.weapon:setStance(self.stances.equip5)

    local delta = 0
    util.wait(self.stances.equip5.duration, function()
        local alpha = self.stances.equip5.weaponOffset or {0,0}
        local beta = self.stances.equip6.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip5.weaponRotation, self.stances.equip6.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip5.armRotation, self.stances.equip6.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.equip5.duration))
    end)

    self:setState(self.equip6)
end

function GunFire:equip6()
    self.weapon:setStance(self.stances.equip6)

    local delta = 0
    util.wait(self.stances.equip6.duration, function()
        local alpha = self.stances.equip6.weaponOffset or {0,0}
        local beta = self.stances.idle.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.equip6.weaponRotation, self.stances.idle.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.equip6.armRotation, self.stances.idle.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.equip6.duration))
    end)
end

function GunFire:kick()
    self.weapon:setStance(self.stances.kick)

    local delta = 0
    util.wait(self.stances.kick.duration, function()
        local alpha = self.stances.kick.weaponOffset or {0,0}
        local beta = self.stances.cooldown.weaponOffset or {0,0 }

        self.weapon.weaponOffset = {interp.linear(delta, alpha[1], beta[1]), interp.linear(delta, alpha[2], beta[2]) }
        self.weapon.relativeWeaponRotation = util.toRadians(interp.linear(delta, self.stances.kick.weaponRotation, self.stances.cooldown.weaponRotation))
        self.weapon.relativeArmRotation = util.toRadians(interp.linear(delta, self.stances.kick.armRotation, self.stances.cooldown.armRotation))

        delta = math.min(1.0, delta + (self.dt / self.stances.kick.duration))
    end)

    self:setState(self.cooldown)
end