local _ = {}

local Set = Library.retrieve('Set', '^1.0.0')

local function onEvent(self, event, ...)
  if event == 'UNIT_SPELLCAST_SENT' then
    _.onUnitSpellcastSent(...)
  elseif event == 'UNIT_SPELLCAST_SUCCEEDED' then
    _.onUnitSpellcastSucceeded(...)
  end
end

local MINING_SPELL_ID = 366260
local HERB_GATHERING_SPELL_ID = 366252
local DISENCHANT_SPELL_ID = 13262

local spellIDs = Set.create({ MINING_SPELL_ID, HERB_GATHERING_SPELL_ID, DISENCHANT_SPELL_ID })

local lastSpellcastSent = nil

function _.onUnitSpellcastSent(unit, name, id, spellID)
  if unit == 'player' and Set.contains(spellIDs, spellID) then
    lastSpellcastSent = {
      id = id,
      name = name,
      spellID = spellID
    }
  else
    lastSpellcastSent = nil
  end
end

function _.onUnitSpellcastSucceeded(unit, id, spellID)
  if spellID == MINING_SPELL_ID and unit == 'player' then
    if lastSpellcastSent and lastSpellcastSent.id == id then
      Coroutine.runAsCoroutineImmediately(function()
        _.onMined(lastSpellcastSent.name)
      end)
    end
  elseif spellID == HERB_GATHERING_SPELL_ID and unit == 'player' then
    if lastSpellcastSent and lastSpellcastSent.id == id then
      Coroutine.runAsCoroutineImmediately(function()
        _.onHerbGathered(lastSpellcastSent.name)
      end)
    end
  elseif spellID == DISENCHANT_SPELL_ID and unit == 'player' then
    Coroutine.runAsCoroutineImmediately(_.onDisenchanted)
  end
end

function _.onMined(nodeName)
  _.onGathered(nodeName, 'miningYield')
end

function _.onHerbGathered(nodeName)
  _.onGathered(nodeName, 'herbalismYield')
end

function _.onGathered(nodeName, yieldName)
  local wasSuccessful2 = Events.waitForEvent('LOOT_READY', 1)

  local yield = {}

  if wasSuccessful2 then
    for index = 1, GetNumLootItems() do
      local itemLink = GetLootSlotLink(index)
      if itemLink then
        local itemID = GetItemInfoInstant(itemLink)
        local quantity = select(3, GetLootSlotInfo(index))
        local yieldEntry = {
          itemID = itemID,
          quantity = quantity
        }
        table.insert(yield, yieldEntry)
      else
        print('index', index, 'itemLink', itemLink)
      end
    end
  end

  local event = {
    name = nodeName,
    yield = yield
  }

  if not _G[yieldName] then
    _G[yieldName] = {}
  end

  table.insert(_G[yieldName], _.compress(event))

  _.print(event)
end

function _.print(event)
  print('event')
  DevTools_Dump(event)
  local gold = 0
  for __, yield in ipairs(event.yield) do
    gold = gold + yield.quantity * (_.retrieveMarketPrice(yield.itemID) or 0)
  end
  print('Gathered items that can be sold for ~' .. GetMoneyString(gold) .. '.')
end

function _.onDisenchanted()
  local yieldName = 'disenchantYield'
  local wasSuccessful, event, containerIndex, slotIndex = Events.waitForEvent('ITEM_LOCKED')
  if wasSuccessful then
    local itemLink = C_Container.GetContainerItemLink(containerIndex, slotIndex)
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
        itemLink = itemLink,
        yield = yield
      }

      if not _G[yieldName] then
        _G[yieldName] = {}
      end

      table.insert(_G[yieldName], _.compress(event))
    end
  end
end

function _.compress(event)
  local compressedEvent = {
    event.itemLink or event.name
  }
  for __, yieldEntry in ipairs(event.yield) do
    table.insert(compressedEvent, yieldEntry.itemID)
    table.insert(compressedEvent, yieldEntry.quantity)
  end
  return compressedEvent
end

function _.decompress(compressedEvent)

end

function _.compareRates(a, b)
  return b.rate < a.rate
end

local frame = CreateFrame('Frame')
frame:SetScript('OnEvent', onEvent)
frame:RegisterEvent('UNIT_SPELLCAST_SENT')
frame:RegisterEvent('UNIT_SPELLCAST_SUCCEEDED')

local herbalismSpellIDs = Set.create({
  391460,
  391415,
  391496,
  391431,
  391406,
  391509,
  391511,
  391444,
  391502,
  391441,
  391512,
  391514,
  391447,
  391501,
  391503,
  391504,
  391508,
  391513,
  391515,
  391500,
  391507,
  391510,
  391492,
})

local miningSpellIDs = Set.create({
  389463,
  389459,
  389462,
  389460,
  389461,
  384692,
  389413,
  389409,
  384688,
  396162,
  389464,
  372610,
  374990,
  384693,
  389406,
  389420,
  384690,
})

local spellIDs = Set.union(herbalismSpellIDs, miningSpellIDs)

if _G.TSM_API then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
    if tooltip == GameTooltip then
      TooltipUtil.SurfaceArgs(data)
      local spellID = data.id
      if spellIDs:contains(spellID) then
        local name = GetSpellInfo(spellID)
        local eventsSource
        if herbalismSpellIDs:contains(spellID) then
          eventsSource = herbalismYield
        elseif miningSpellIDs:contains(spellID) then
          eventsSource = miningYield
        end
        local events = Array.filter(eventsSource or {}, function(event)
          return event[1] == name
        end)
        local counts = {}
        Array.forEach(events, function(event)
          for index = 2, #event, 2 do
            local id = event[index]
            local count = event[index + 1] or 0
            if not counts[id] then
              counts[id] = 0
            end
            counts[id] = counts[id] + count
          end
        end)
        local rates = {}
        local numberOfEvents = #events
        local text
        if numberOfEvents >= 1 then
          for id, count in pairs(counts) do
            local rate = {
              id = id,
              rate = count / numberOfEvents
            }
            table.insert(rates, rate)
          end
          local averageGold = Array.reduce(rates, function(averageGold, rate)
            return averageGold + rate.rate * (_.retrieveMarketPrice(rate.id) or 0)
          end, 0)
          text = GetMoneyString(averageGold)
        else
          text = 'No data available'
        end
        tooltip:AddDoubleLine('Average gold:', text, nil, nil, nil, 1, 1, 1)
      end
    end
  end)
end

function _.retrieveMarketPrice(itemID)
  return TSM_API.GetCustomPriceValue('dbmarket', 'i:' .. itemID)
end
