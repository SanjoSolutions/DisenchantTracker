local _ = {}

local function onEvent(self, event, ...)
  if event == 'UNIT_SPELLCAST_SUCCEEDED' then
    _.onUnitSpellcastSucceeded(...)
  end
end

local DISENCHANT_SPELL_ID = 13262

function _.onUnitSpellcastSucceeded(unit, ___, spellID)
  if spellID == DISENCHANT_SPELL_ID and unit == 'player' then
    Coroutine.runAsCoroutine(_.onDisenchanted)
  end
end

function _.onDisenchanted()
  local wasSuccessful, event, containerIndex, slotIndex = Events.waitForEvent('ITEM_LOCKED')
  if wasSuccessful then
    local disenchantedItemID = C_Container.GetContainerItemID(containerIndex, slotIndex)
    local wasSuccessful2 = Events.waitForEvent('LOOT_READY')
    if wasSuccessful2 then
      local yield = {}
      for index = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(index)
        local itemID = GetItemInfoInstant(itemLink)
        local quantity = select(3, GetLootSlotInfo(index))
        local yieldEntry = {
          itemID = itemID,
          quantity = quantity
        }
        table.insert(yield, yieldEntry)
      end

      local event = {
        disenchantedItemID = disenchantedItemID,
        yield = yield
      }

      if not disenchantYield then
        disenchantYield = {}
      end

      table.insert(disenchantYield, _.compress(event))
    end
  end
end

function _.compress(event)
  local compressedEvent = {
    event.disenchantedItemID
  }
  for __, yieldEntry in ipairs(event.yield) do
    table.insert(compressedEvent, yieldEntry.itemID)
    table.insert(compressedEvent, yieldEntry.quantity)
  end
  return compressedEvent
end

function _.decompress(compressedEvent)

end

local frame = CreateFrame('Frame')
frame:SetScript('OnEvent', onEvent)
frame:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED')
