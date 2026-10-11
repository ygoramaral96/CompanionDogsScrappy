-- Scrappy power, client side (card #246): "Recharge Scrappy" on the dog's context menu, one entry per
-- pilha / car battery with charge in the main inventory, and the owner's notices.
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local function percent(fraction)
    return tostring(math.floor(fraction * 100 + 0.5)) .. "%"
end

local function chargersIn(playerObj)
    local found = {}
    local items = playerObj:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if S.CHARGERS[item:getFullType()] and item:getCurrentUsesFloat() > 0 then
            found[#found + 1] = item
        end
    end
    return found
end

local function onRecharge(animal, playerObj, itemId)
    CompanionDogs.request("scrappyRecharge", animal, { itemId = itemId }, playerObj)
end

local function addRechargeEntry(context, playerObj, animal)
    local header = context:addOption(getText("IGUI_Scrappy_Recharge", percent(S.chargeFraction(animal))), nil, nil)
    local chargers = chargersIn(playerObj)
    if #chargers == 0 then
        header.notAvailable = true
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(getText("IGUI_Scrappy_NoCharger"))
        header.toolTip = tip
        return
    end
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(header, sub)
    for _, item in ipairs(chargers) do
        sub:addOption(item:getDisplayName() .. " (" .. percent(item:getCurrentUsesFloat()) .. ")",
                      animal, onRecharge, playerObj, item:getID())
    end
end

Events.OnClickedAnimalForContext.Add(function(player, context, animals)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    local CD = CompanionDogs
    for _, animal in ipairs(animals) do
        if CD.isDog(animal) and S.isScrappy(animal) and CD.isCompanion(animal) and CD.isOwnedBy(animal, playerObj) then
            addRechargeEntry(context, playerObj, animal)
        end
    end
end)

local function good(text)
    local player = getPlayer()
    if player then HaloTextHelper.addGoodText(player, text) end
end

local function bad(text)
    local player = getPlayer()
    if player then HaloTextHelper.addBadText(player, text) end
end

S.clientHandlers.recharged = function(args) good(getText("IGUI_Scrappy_Recharged", tostring(args.pct) .. "%")) end
S.clientHandlers.nofood = function() bad(getText("IGUI_Scrappy_NoFood")) end
S.clientHandlers.shutdown = function() bad(getText("IGUI_Scrappy_Shutdown")) end
S.clientHandlers.toofar = function() bad(getText("IGUI_Scrappy_TooFar")) end
