-- Scrappy's cargo visual, client side (card #246). Its bag is built in (GENZ_ScrappyBagServer): empty,
-- nothing hangs on its back; with cargo inside, the vanilla ammo case (GENZ_ScrappyCargoBox) sits on the
-- saddlebags_c point of Scrappy_Body (placed in models_scrappy.txt). The leather saddlebags of
-- CompanionDogs are never drawn on Scrappy.
-- Purely VISUAL and LOCAL, like GENZ_ScrappyLightsClient: every client reads the bag record the server
-- already transmits in the dog's data.
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local CARGO_ITEM = "Base.GENZ_ScrappyCargoBox"
local CARGO_LOCATION = "saddlebags_c"
local LEATHER_LOCATIONS = { "saddlebags_l", "saddlebags_r" }
local CHECK_EVERY_TICKS = 30

local function hasCargo(animal)
    local bag = CompanionDogs.data(animal).bag
    return bag ~= nil and bag.items ~= nil and #bag.items > 0
end

local function syncCargo(animal)
    if not CompanionDogs.ensureAttachSlots(animal) then return end
    for _, location in ipairs(LEATHER_LOCATIONS) do
        if animal:getAttachedItem(location) ~= nil then
            animal:setAttachedItem(location, nil)
        end
    end
    local current = animal:getAttachedItem(CARGO_LOCATION)
    local currentType = current and current:getFullType()
    local wanted = hasCargo(animal) and CARGO_ITEM or nil
    if currentType == wanted then return end
    animal:setAttachedItem(CARGO_LOCATION, wanted and instanceItem(wanted) or nil)
end

-- The base client repaints the leather on every dog with a bag (CompanionDogs_Client bag paint loop).
local function cargoInsteadOfLeather()
    local CD = CompanionDogs
    local original = CD.applyBagVisualLocal
    if not original then
        print("[GENZ_Scrappy] ERROR: CompanionDogs.applyBagVisualLocal not found -- Scrappy may show leather saddlebags")
        return
    end
    CD.applyBagVisualLocal = function(animal)
        if animal and S.isScrappy(animal) then
            syncCargo(animal)
            return
        end
        return original(animal)
    end
end

Events.OnGameBoot.Add(cargoInsteadOfLeather)

local ticks = 0
Events.OnTick.Add(function()
    ticks = ticks + 1
    if ticks < CHECK_EVERY_TICKS then return end
    ticks = 0
    local cell = getCell()
    if not cell then return end
    local animals = cell:getAnimals()
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        if not animal:isDead() and CompanionDogs.isDog(animal) and S.isScrappy(animal) then
            syncCargo(animal)
        end
    end
end)

S.clientHandlers.builtinbag = function()
    local player = getPlayer()
    if player then HaloTextHelper.addBadText(player, getText("IGUI_Scrappy_BuiltInBag")) end
end
