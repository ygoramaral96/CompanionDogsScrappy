-- Scrappy power, client side (card #246): "Recharge Scrappy" on the dog's context menu, one entry per
-- pilha / car battery with charge in the main inventory, and the owner's notices. Since card #253 it
-- takes the place of the base mod's "Feed" option, and a stray Scrappy gets it too (to befriend it).
require "CompanionDogsScrappyShared"
local S = CompanionDogsScrappy

local function percent(fraction)
    return tostring(math.floor(fraction * 100 + 0.5)) .. "%"
end

local function chargersIn(playerObj)
    local found = {}
    local items = playerObj:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if S.chargeOf(item:getFullType()) > 0 and item:getCurrentUsesFloat() > 0 then
            found[#found + 1] = item
        end
    end
    return found
end

local function onRecharge(animal, playerObj, itemId)
    CompanionDogs.request("scrappyRecharge", animal, { itemId = itemId }, playerObj)
end

-- A stray Scrappy gets the same chargers under a "befriend" header (card #253): on the server the
-- energy becomes trust until it is adopted.
local function entryTitle(animal)
    local CD = CompanionDogs
    if CD.isCompanion(animal) then
        return getText("IGUI_Scrappy_Recharge", percent(S.chargeFraction(animal)))
    end
    return getText("IGUI_Scrappy_Befriend", tostring(math.floor(CD.getTrust(animal))), tostring(CD.tameThreshold()))
end

-- Hangs the chargers of the inventory under `header` (an option of `menu`): one entry per charger,
-- or the option disabled with a tip when there is none.
local function fillChargers(menu, header, playerObj, animal)
    local chargers = chargersIn(playerObj)
    if #chargers == 0 then
        header.notAvailable = true
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(getText("IGUI_Scrappy_NoCharger"))
        header.toolTip = tip
        return
    end
    local sub = ISContextMenu:getNew(menu)
    menu:addSubMenu(header, sub)
    for _, item in ipairs(chargers) do
        sub:addOption(item:getDisplayName() .. " (" .. percent(item:getCurrentUsesFloat()) .. ")",
                      animal, onRecharge, playerObj, item:getID())
    end
end

-- The base mod's own "Feed" option, turned into ours IN PLACE (same spot in the menu): Scrappy
-- refuses food, so "Feed" always failed (Ygor, card #253: "recarregar soa melhor").
local function takeOver(menu, option, playerObj, animal)
    option.name = entryTitle(animal)
    option.target, option.onSelect = nil, nil
    option.iconTexture, option.toolTip, option.color = nil, nil, nil
    option.notAvailable, option.subOption = false, nil
    fillChargers(menu, option, playerObj, animal)
end

-- Where CompanionDogs_ContextMenu.onAnimalMenu put the feed option of this dog:
--   own SELECTED dog -> "IGUI_PD_FeedCompanion" inside the submenu named after the dog (same name
--     rule as the base mod: data name or breed noun, + pregnancy label);
--   stray -> one top-level "IGUI_PD_Feed" per stray, in the order of `animals`.
-- An own dog that is not the selected one has no feed option.
local function ownFeedOption(context, animal)
    local CD = CompanionDogs
    local name = CD.data(animal).name or CD.breedNoun(animal)
    if CD.isPregnant(animal) then
        name = name .. " (" .. CD.pregnancyLabel(animal) .. ")"
    end
    local header = context:getOptionFromName(name)
    local menu = header and header.subOption and context:getSubMenu(header.subOption)
    local option = menu and menu:getOptionFromName(getText("IGUI_PD_FeedCompanion"))
    return menu, option
end

local function strayFeedOption(context, strayIndex)
    local label = getText("IGUI_PD_Feed")
    local seen = 0
    for _, option in ipairs(context.options) do
        if option.name == label then
            seen = seen + 1
            if seen == strayIndex then return option end
        end
    end
    return nil
end

local function onAnimalMenu(player, context, animals)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    local CD = CompanionDogs
    local strays = 0
    for _, animal in ipairs(animals) do
        if CD.isDog(animal) then
            local stray = not CD.isCompanion(animal)
            if stray then strays = strays + 1 end
            if S.isScrappy(animal) and (stray or CD.isOwnedBy(animal, playerObj)) then
                local menu, feed = context, nil
                if stray then
                    feed = strayFeedOption(context, strays)
                else
                    menu, feed = ownFeedOption(context, animal)
                end
                if feed then
                    takeOver(menu, feed, playerObj, animal)
                else
                    fillChargers(context, context:addOption(entryTitle(animal), nil, nil), playerObj, animal)
                end
            end
        end
    end
end

-- In OnGameStart, so it runs AFTER CompanionDogs' own handler (added when its file loads) and the
-- feed option already exists when we look for it.
Events.OnGameStart.Add(function()
    Events.OnClickedAnimalForContext.Add(onAnimalMenu)
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
