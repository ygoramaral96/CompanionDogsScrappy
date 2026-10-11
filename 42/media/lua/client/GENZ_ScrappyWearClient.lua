-- Scrappy maintenance, client side (card #246): "Maintenance" on the dog's context menu, one entry per
-- part type the player carries (needs a screwdriver that is not broken), and the owner's notices.
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local function percent(fraction)
    return tostring(math.floor(fraction * 100 + 0.5)) .. "%"
end

local function onRepair(animal, playerObj, partType)
    CompanionDogs.request("scrappyRepair", animal, { part = partType }, playerObj)
end

local function disable(option, tipKey)
    option.notAvailable = true
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(getText(tipKey))
    option.toolTip = tip
end

local function addMaintenanceEntry(context, playerObj, animal)
    local header = context:addOption(getText("IGUI_Scrappy_Maintain", percent(S.condition(animal))), nil, nil)
    local inv = playerObj:getInventory()
    if not inv:containsTagEvalRecurse(ItemTag.SCREWDRIVER, S.toolNotBroken) then
        disable(header, "IGUI_Scrappy_NoScrewdriver")
        return
    end
    local sub = ISContextMenu:getNew(context)
    local count = 0
    for _, partType in ipairs(S.REPAIR_ORDER) do
        if inv:containsTypeRecurse(partType) then
            local label = getItemNameFromFullType("Base." .. partType) .. " (+" .. percent(S.REPAIRS[partType].gain) .. ")"
            sub:addOption(label, animal, onRepair, playerObj, partType)
            count = count + 1
        end
    end
    if count == 0 then
        disable(header, "IGUI_Scrappy_NoParts")
        return
    end
    context:addSubMenu(header, sub)
end

Events.OnClickedAnimalForContext.Add(function(player, context, animals)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    local CD = CompanionDogs
    for _, animal in ipairs(animals) do
        if CD.isDog(animal) and S.isScrappy(animal) and CD.isCompanion(animal) and CD.isOwnedBy(animal, playerObj) then
            addMaintenanceEntry(context, playerObj, animal)
        end
    end
end)

local function say(good, text)
    local player = getPlayer()
    if not player then return end
    if good then
        HaloTextHelper.addGoodText(player, text)
    else
        HaloTextHelper.addBadText(player, text)
    end
end

S.clientHandlers.repaired = function(args) say(true, getText("IGUI_Scrappy_Repaired", tostring(args.pct) .. "%")) end
S.clientHandlers.fullcondition = function() say(true, getText("IGUI_Scrappy_FullCondition")) end
S.clientHandlers.degraded = function() say(false, getText("IGUI_Scrappy_Degraded")) end
S.clientHandlers.broken = function() say(false, getText("IGUI_Scrappy_Broken")) end
