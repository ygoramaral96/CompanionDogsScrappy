-- Scrappy maintenance, client side (card #246): "Maintenance" on the dog's context menu. Each entry walks
-- next to the dog and queues GENZ_ScrappyMaintainAction (a timed action like the vanilla generator repair):
-- one repair entry per part type carried, plus "Calibrate circuits" (Electricity training, a few per day).
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local function percent(fraction)
    return tostring(math.floor(fraction * 100 + 0.5)) .. "%"
end

local function onMaintain(animal, playerObj, mode)
    luautils.walkAdj(playerObj, animal:getSquare())
    ISTimedActionQueue.add(GENZ_ScrappyMaintainAction:new(playerObj, animal, mode))
end

local function disable(option, tipKey, ...)
    option.notAvailable = true
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(getText(tipKey, ...))
    option.toolTip = tip
end

-- Same information the vanilla repair menu gives ("chance of success X%").
local function showSuccessChance(option, playerObj, mode)
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(getText("IGUI_Scrappy_SuccessChance", tostring(100 - S.failPercent(playerObj, mode)) .. "%"))
    option.toolTip = tip
end

local function addRepairEntries(sub, playerObj, animal)
    for _, partType in ipairs(S.REPAIR_ORDER) do
        if playerObj:getInventory():containsTypeRecurse(partType) then
            local part = S.REPAIRS[partType]
            local label = getText("IGUI_Scrappy_RepairWith", getItemNameFromFullType("Base." .. partType),
                                  percent(S.repairGain(playerObj, partType)), S.maintenanceXp(partType))
            local option = sub:addOption(label, animal, onMaintain, playerObj, partType)
            if S.condition(animal) >= 1 then
                disable(option, "IGUI_Scrappy_FullCondition")
            else
                showSuccessChance(option, playerObj, partType)
            end
        end
    end
end

local function addCalibrateEntry(sub, playerObj, animal)
    local left = S.calibrationsLeft(animal)
    local option = sub:addOption(getText("IGUI_Scrappy_Calibrate", left, S.maintenanceXp(S.CALIBRATE)), animal, onMaintain,
                                 playerObj, S.CALIBRATE)
    if left <= 0 then
        disable(option, "IGUI_Scrappy_NoCalibrations")
    elseif not playerObj:getInventory():containsTypeRecurse(S.CALIBRATION.part) then
        disable(option, "IGUI_Scrappy_NeedsPart", getItemNameFromFullType("Base." .. S.CALIBRATION.part))
    else
        showSuccessChance(option, playerObj, S.CALIBRATE)
    end
end

local function addMaintenanceEntry(context, playerObj, animal)
    local header = context:addOption(getText("IGUI_Scrappy_Maintain", percent(S.condition(animal))), nil, nil)
    if not S.hasScrewdriver(playerObj) then
        disable(header, "IGUI_Scrappy_NoScrewdriver")
        return
    end
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(header, sub)
    addRepairEntries(sub, playerObj, animal)
    addCalibrateEntry(sub, playerObj, animal)
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
S.clientHandlers.calibrated = function(args) say(true, getText("IGUI_Scrappy_Calibrated", tostring(args.left))) end
S.clientHandlers.failed = function(args)
    local player = getPlayer()
    if player then player:playSound("FixingItemFailed") end
    local key = args.mode == S.CALIBRATE and "IGUI_Scrappy_CalibrateFailed" or "IGUI_Scrappy_RepairFailed"
    say(false, getText(key))
end
S.clientHandlers.degraded = function() say(false, getText("IGUI_Scrappy_Degraded")) end
S.clientHandlers.broken = function() say(false, getText("IGUI_Scrappy_Broken")) end
