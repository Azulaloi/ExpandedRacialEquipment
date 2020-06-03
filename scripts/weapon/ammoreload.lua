require "/scripts/util.lua"
require "/scripts/interp.lua"

-- Reload for use with gunfireammo as primary
-- read and write parameter "rounds" as ammo
-- use Weapon:ammoCall(x) to alert x slot ability to update ammo


Reload = WeaponAbility:new()

function Reload:init()
	sb.logInfo("reload init")
    self.cooldownTimer = self.fireTime
	
	self.rounds = config.getParameter("rounds", 6)
	self.maxRounds = config.getParameter("maxRounds", 3)
	self.cursorAmmo = config.getParameter("cursorAmmo", false)
	self.cursorDir = config.getParameter("cursorDir", "/cursors/12/azreticle")

end

function Reload:update(dt, fireMode, shiftHeld)
    WeaponAbility.update(self, dt, fireMode, shiftHeld)

    self.cooldownTimer = math.max(0, self.cooldownTimer - self.dt)
	
	if self.fireMode == (self.activatingFireMode or self.abilitySlot)
          and not self.weapon.currentAbility
          and self.cooldownTimer == 0
          and not status.resourceLocked("energy") then
		
		self:setState(self.reloadState)
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

function Reload:reloadState()
	self.weapon:setStance(self.stances.fire)

	self:reloadFx()
	
	if self.stances.fire.duration then
        util.wait(self.stances.fire.duration)
    end
	
	self:doReload(1, false)
	
	self.cooldownTimer = self.fireTime
    self:setState(self.cooldown)
end

function Reload:reloadFx()
	animator.playSound("reload")
end

function Reload:doReload(amount, replace)
	local toReload
	if amount then
		toReload = amount 
	else 
		toReload = self.maxRounds 
	end
	
	if not replace then
		toReload = config.getParameter("rounds") + toReload
	end
	
	--add option for overloading
	if toReload > self.maxRounds then toReload = self.maxRounds end
	
	activeItem.setInstanceValue("rounds", toReload)
	
	self.weapon:ammoCall(1)
end

function Reload:uninit()

end


