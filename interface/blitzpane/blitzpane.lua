require "/scripts/util.lua"
require "/scripts/interp.lua"

function init()
  testSet()

  self.itemList = "itemScrollArea.itemList"

  self.upgradeLevel = config.getParameter("upgradeLevel")
  self.paramsToCheck = config.getParameter("blitzParameters")
  self.paramsStored = {}
  
  self.upgradeableWeaponItems = {}
  self.selectedItem = nil
  populateItemList(true)
end

function testSet()
	--player.setProperty("az-ere_blitz-quantity", 3)
end

function update(dt)
  populateItemList(true)
end

function upgradeCost(itemConfig)
  if itemConfig == nil then return 0 end

  --local prevValue = root.evalFunction("weaponEssenceValue", itemConfig.parameters.level or itemConfig.config.level or 1)
  --local newValue = root.evalFunction("weaponEssenceValue", self.upgradeLevel)

  --return math.floor(newValue - prevValue)
  
  return 0
end



function populateItemList(forceRepop)
  for i, v in pairs(self.paramsToCheck) do
	--sb.logInfo(tostring(i) .. " : " .. tostring(v))
	self.paramsStored[v] = player.getProperty(v, "none")
  end

  if forceRepop then
    widget.clearListItems(self.itemList)
    widget.setButtonEnabled("btnUpgrade", false)

    local showEmptyLabel = true

    for i, v in pairs(self.paramsStored) do
        showEmptyLabel = false

        local listItem = string.format("%s.%s", self.itemList, widget.addListItem(self.itemList))

        widget.setText(string.format("%s.itemName", listItem), v)
		widget.setText(string.format("%s.itemValue", listItem), i)
        --widget.setItemSlotItem(string.format("%s.itemIcon", listItem), item)

        local price = upgradeCost(config)
        widget.setData(listItem,
          {
            index = i,
            price = price
          })

        widget.setVisible(string.format("%s.unavailableoverlay", listItem), price > 0)
    end

    self.selectedItem = nil
    showWeapon(nil)

    widget.setVisible("emptyLabel", showEmptyLabel)
  end
end

function showWeapon(item, price)
  local playerEssence = player.currency("essence")
  local enableButton = false

  if item then
    enableButton = playerEssence >= price
    local directive = enableButton and "^green;" or "^red;"
    widget.setText("essenceCost", string.format("%s%s / %s", directive, playerEssence, price))
  else
    widget.setText("essenceCost", string.format("%s / --", playerEssence))
  end

  widget.setButtonEnabled("btnUpgrade", enableButton)
end

function itemSelected()
  local listItem = widget.getListSelected(self.itemList)
  self.selectedItem = listItem

  if listItem then
    local itemData = widget.getData(string.format("%s.%s", self.itemList, listItem))
    local weaponItem = self.upgradeableWeaponItems[itemData.index]
    showWeapon(weaponItem, itemData.price)
  end
end

function doUpgrade()
  if self.selectedItem then
    local selectedData = widget.getData(string.format("%s.%s", self.itemList, self.selectedItem))
    local upgradeItem = self.upgradeableWeaponItems[selectedData.index]

    if upgradeItem then
      local consumedItem = player.consumeItem(upgradeItem, false, true)
      if consumedItem then
        local consumedCurrency = player.consumeCurrency("essence", selectedData.price)
        local upgradedItem = copy(consumedItem)
        if consumedCurrency then
          upgradedItem.parameters.level = self.upgradeLevel
          local itemConfig = root.itemConfig(upgradedItem)
          if itemConfig.config.upgradeParameters then
            upgradedItem.parameters = util.mergeTable(upgradedItem.parameters, itemConfig.config.upgradeParameters)
          end
        end
        player.giveItem(upgradedItem)
      end
    end
    populateItemList(true)
  end
end
