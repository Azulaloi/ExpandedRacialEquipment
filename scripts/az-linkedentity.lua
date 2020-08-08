function init()
	entityIds = {}
	
	initHandlers()
	
	sb.logInfo("azlinkedentity player: init")
	-- add some feature to the item that lets u turn off deployment
	if player.hasItem({name = "az-linkedblade"}) then
		--if #entityIds >= 1 then 
			deployEntity() 
		--end
	end
end

function initHandlers()
	--message.setHandler("az-link_init", function(_, _) deployEntity() end)
	message.setHandler("az-link_init", function(_, _) returnEntity() end)
	message.setHandler("az-link_uninit", function(_, _) returnEntity() end)
	message.setHandler("az-linked_entity-uninit", function(_, _, entityId) removeEntity(entityId) end)
	
	
end

function deployEntity()
	entityParameters = {}
	entityParameters.parentEntity = player.id()
	entityParameters.movementMode = "Orbit"
	entityParameters.attackMode = "Target"
	entityParameters.targetRange = 40
	entityParameters.statusSettings = { stats = { flatMaxHealth = { baseValue = 1000 } } }
	entityParameters.gun = {
		fireDelay = 0.8,
		fireTime = 0.3,
		fireOffset = {1, 0},
		
		projectileType = "mechplasmabullet",
		projectileParameters = { speed = 60, power = 15},
		projectileInaccuracy = 0.05
	}
	entityParameters.targetOffset = {0, 1}
	--entityParameters.attackMode
	--entityParameters.movementMode == 

	local entity = world.spawnMonster("az-linkedblade", mcontroller.position(), entityParameters)
	if entity then table.insert(entityIds, entity) end
end

function returnEntity()
	sb.logInfo("az-linkedentity player: returning")
	for i, v in pairs(entityIds) do
		world.sendEntityMessage(v, "return")
	end
end

function removeEntity(entityId)
	local pointer = nil
	for i, v in pairs(entityIds) do
		if v == entityId then pointer = i break end
	end
	if pointer then table.remove(entityIds, pointer) end
end


function update()
	-- id rather do this by message on items uninit() but my weapon.lua uninits on init or something so whatever
	sb.printJson(entityIds)
	if entityIds[1] ~= nil then 
		local handItem = player.primaryHandItem()

		--if (handItem == nil) or (handItem.name ~= "az-linkedblade")then 
		--	sb.logInfo("az-linkedentity player: handitem wrong")
		--	sb.logInfo(sb.printJson(handItem))
		--	--returnEntity() 
		--	if not entityIds[1] then deployEntity() end
		--end
	else
		local handItem = player.primaryHandItem()

		if (handItem == nil) or (handItem.name ~= "az-linkedblade")then 
			sb.logInfo("az-linkedentity player: handitem wrong")
			sb.logInfo(sb.printJson(handItem))
			--returnEntity() 
			if not entityIds[1] then deployEntity() end
		end
	end
end

function uninit()

end