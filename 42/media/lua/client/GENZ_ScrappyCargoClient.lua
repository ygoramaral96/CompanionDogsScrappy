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

-- The engine draws an animal's hung models only through setAttachedItem -> resetEquippedHandsModels, which is
-- dropped while the animal has no model on screen (IsoGameCharacter.resetEquippedHandsModels: hasActiveModel).
-- A dog that comes back into view (teleport, chunk) gets a fresh model with nothing hung on it
-- (ModelManager.DoCharacterModelParts skips equipped models for animals, 42.21) though the item is still
-- attached. So each time its model shows up again, the hung models are redrawn once.
local wasShown = {}

local function redrawWhenShown(animal)
    local shown = animal:hasActiveModel()
    if shown and not wasShown[animal] then animal:resetEquippedHandsModels() end
    wasShown[animal] = shown
end

local function syncCargo(animal)
    if not CompanionDogs.ensureAttachSlots(animal) then
        print("[GENZ_Scrappy] ERROR: no attached-item slots on a Scrappy -- the cargo case cannot hang")
        return
    end
    for _, location in ipairs(LEATHER_LOCATIONS) do
        if animal:getAttachedItem(location) ~= nil then
            animal:setAttachedItem(location, nil)
        end
    end
    local current = animal:getAttachedItem(CARGO_LOCATION)
    local currentType = current and current:getFullType()
    local wanted = hasCargo(animal) and CARGO_ITEM or nil
    if currentType ~= wanted then
        animal:setAttachedItem(CARGO_LOCATION, wanted and instanceItem(wanted) or nil)
    end
    if wanted then
        redrawWhenShown(animal)
    else
        wasShown[animal] = nil
    end
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
    local seen = {}
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        if not animal:isDead() and CompanionDogs.isDog(animal) and S.isScrappy(animal) then
            seen[animal] = true
            syncCargo(animal)
        end
    end
    -- dogs gone from the cell: forget them, so a returning one is redrawn
    for animal in pairs(wasShown) do
        if not seen[animal] then wasShown[animal] = nil end
    end
end)

S.clientHandlers.builtinbag = function()
    local player = getPlayer()
    if player then HaloTextHelper.addBadText(player, getText("IGUI_Scrappy_BuiltInBag")) end
end
