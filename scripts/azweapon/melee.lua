require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/azweapon/weapon.lua"

function init()
    activeItem.setCursor("/cursors/reticle0.cursor")
    
	animator.setGlobalTag("paletteSwaps", config.getParameter("paletteSwaps", ""))
	animator.setGlobalTag("directives", "")
	animator.setGlobalTag("bladeDirectives", "")

    self.weapon = Weapon:new()

	self.weapon:addTransformationGroup("weapon", {0,0}, util.toRadians(config.getParameter("baseWeaponRotation", 0)))
	self.weapon:addTransformationGroup("swoosh", {0,0}, math.pi/2)

    local primaryAbility = getPrimaryAbility()
    self.weapon:addAbility(primaryAbility)

    local secondaryAbility = getAltAbility(self.weapon.elementalType)
    if secondaryAbility then
        self.weapon:addAbility(secondaryAbility)
    end

    self.weapon:init()
end

function update(dt, fireMode, shiftHeld, moves)
    self.weapon:update(dt, fireMode, shiftHeld, moves)

    self.weapon:updateScale()
end

function uninit()
    self.weapon:uninit()
end

