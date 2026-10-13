-- Scrappy's built-in bag, server side (card #246). Scrappy is a robot: its cargo compartment is part of
-- the body, so it never wears CompanionDogs' leather saddlebags.
--   * every Scrappy companion gets the base mod's bag record by itself (d.bag.equipped = true), so
--     "Open bag" works with no saddlebag crafted or equipped;
--   * "equip" and "take off saddlebags" are refused for Scrappy (taking it off would drop the cargo
--     inside a leather saddlebag and leave it bagless);
--   * when the base mod spills the bag (released, purged, died while carried), Scrappy's cargo falls
--     LOOSE on the ground: the base spill wraps it in a new leather saddlebag the player never had;
--   * the leather visual is never hung on Scrappy (GENZ_ScrappyCargoClient draws the metal case).
-- Hooks are installed in OnGameBoot, after every base-mod file has defined what we wrap.
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local function animalFromArgs(args)
    if not args then return nil end
    if args.__animal then return args.__animal end
    if args.id then return getAnimal(tonumber(args.id)) end
    return nil
end

local function refuseForScrappy(command)
    local original = CompanionDogs.Server[command]
    if not original then
        print("[GENZ_Scrappy] ERROR: CompanionDogs.Server." .. command .. " not found -- Scrappy's bag can be swapped by it")
        return
    end
    CompanionDogs.Server[command] = function(player, args)
        local animal = animalFromArgs(args)
        if animal and S.isScrappy(animal) then
            S.toOwner(player, "builtinbag", {})
            return
        end
        return original(player, args)
    end
end

local function noLeatherOnScrappy()
    local CD = CompanionDogs
    local original = CD.applyBagVisual
    CD.applyBagVisual = function(animal)
        if animal and S.isScrappy(animal) then return end
        return original(animal)
    end
end

-- Same square choice as the base CD.spillBag (dog, else its owner); the records go back to items one by one.
local function spillLoose(animal, records)
    local CD = CompanionDogs
    local sq = animal:getCurrentSquare() or animal:getSquare()
    if not sq then
        local owner = CD.getOwnerPlayer(animal)
        sq = owner and (owner:getCurrentSquare() or owner:getSquare())
    end
    if not sq then
        print("[GENZ_Scrappy] ERROR: no square to drop Scrappy's cargo (" .. #records .. " item(s) kept in the bag)")
        return false
    end
    for _, record in ipairs(records) do
        local item = CD.bagItemFromRecord(record)
        if item then
            sq:AddWorldInventoryItem(item, 0.5, 0.5, 0.0)
        end
    end
    return true
end

local function spillLooseForScrappy()
    local CD = CompanionDogs
    local original = CD.spillBag
    CD.spillBag = function(animal)
        if not (animal and S.isScrappy(animal)) then return original(animal) end
        local d = CD.data(animal)
        if not d.bag or not d.bag.equipped then return end
        if not spillLoose(animal, d.bag.items or {}) then return end
        d.bag = nil
        CD.transmit(animal)
    end
end

local function ensureBuiltInBag(dog)
    local CD = CompanionDogs
    local d = CD.data(dog)
    if d.bag and d.bag.equipped then return end
    d.bag = { equipped = true, cap = CD.bagCapacity(dog), items = (d.bag and d.bag.items) or {} }
    CD.transmit(dog)
    print("[GENZ_Scrappy] built-in bag ready, owner " .. tostring(CD.getOwnerPlayer(dog) and CD.getOwnerPlayer(dog):getUsername()))
end

local function everyMinute()
    local dogs = CompanionDogs.regCompanions()
    for i = 1, #dogs do
        local dog = dogs[i]
        if dog:isExistInTheWorld() and not dog:isDead() and S.isScrappy(dog) then
            ensureBuiltInBag(dog)
        end
    end
end

Events.OnGameBoot.Add(function()
    local CD = CompanionDogs
    if not (CD and CD.Server and CD.applyBagVisual and CD.spillBag and CD.bagItemFromRecord and CD.regCompanions) then
        print("[GENZ_Scrappy] ERROR: CompanionDogs bag API missing -- Scrappy has NO built-in bag (leather saddlebags apply)")
        return
    end
    refuseForScrappy("equipsaddlebag")
    refuseForScrappy("unequipsaddlebag")
    noLeatherOnScrappy()
    spillLooseForScrappy()
    Events.EveryOneMinute.Add(everyMinute)
    print("[GENZ_Scrappy] built-in bag on: no leather saddlebags, cargo spills loose")
end)
