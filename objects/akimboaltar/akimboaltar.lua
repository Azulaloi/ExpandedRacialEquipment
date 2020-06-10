require "/scripts/util.lua"

function craftingRecipe(items)
  if #items ~= 1 then return end
  local item = items[1]
  if not item then 
	if self.tagLocked then
	  if not item.parameters.azAkimbo then return end
    else return end
  end
  
  --local newParams = copy(item.parameters) or {}
  --jremove(healedParams, "inventoryIcon")
  --jremove(healedParams, "currentPets")
  --for _,pet in pairs(healedParams.pets) do
  --  jremove(pet, "status")
  --end
  --newParams.twoHanded = ~newParams.twoHanded

  local newItem = copy(item)
  --clunk clunk
  if newItem.parameters.twoHanded then
	newItem.parameters.twoHanded = false 
	elseif not newItem.parameters.twoHanded then
	newItem.parameters.twoHanded = true 
  end
  
  local itemOut = {
      name = item.name,
      count = item.count,
      parameters = newItem.parameters
    }

  animator.setAnimationState("workState", "on")
  return {
      input = items,
      output = itemOut,
      duration = 0.2
    }
end

function update(dt)
  local powerOn = false

  for _,item in pairs(world.containerItems(entity.id())) do
    --if item.parameters and item.parameters.azAkimboSwap then
    if item.parameters then
      powerOn = true
      break
    end
  end

  if powerOn then
    animator.setAnimationState("powerState", "on")
  else
    animator.setAnimationState("powerState", "off")
  end
end
