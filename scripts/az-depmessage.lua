function init()
	sb.logInfo("az-depmessage init")
	--sb.logInfo(player.id())
	player.setProperty("az-message-test", "fe fi fo fum")
	
	message.setHandler("az-key_checkMessage", function(_, _) return true end)
	
	--.setHandler("az-key_getProperty", function(_, _, name, default) return player.getProperty(name, default))
	message.setHandler("az-key_getProperty", function(_, _, name) return player.getProperty(name) end)
	message.setHandler("az-key_setProperty", function(_, _, name, value) player.setProperty(name, value) end)
	message.setHandler("az-key_printProperty", function(_, _, name) sb.logInfo("playerProperty: '" .. name .. "' : '" .. player.getProperty(name) .. "'") end)
	
	message.setHandler("az-key_getSpecies", function(_, _) return player.species() end)
	message.setHandler("az-key_getGender", function(_, _) return player.gender() end)
	message.setHandler("az-key_getAdmin", function(_, _) return player.isAdmin() end)
	message.setHandler("az-key_getCurrency", function(_, _, str) return player.currency(str) end)
	message.setHandler("az-key_consumeCurrency", function(_, _, str, q) return player.currency(str, q) end)	
	
	initEvalHandlers()
end

function initEvalHandlers()
	message.setHandler("az-evaltest", function(_, _) sb.logInfo(player.species()) end)
	
end

function test()
	return player.species()
end