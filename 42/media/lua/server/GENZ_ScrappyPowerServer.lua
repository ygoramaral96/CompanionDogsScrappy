-- Scrappy power, server side (card #246). Scrappy runs on batteries instead of food:
--   * food and water are refused (hand, bowl, trough) -- only for Scrappy, every other dog is untouched;
--   * thirst is held at 0 every in-game minute;
--   * when the charge runs out (GENZ_ScrappyShared.offLevel) it shuts down: hunger is held there, the dog
--     is put on STAY and the owner is told once;
--   * the "scrappyRecharge" command takes a pilha or a car battery from the owner's inventory;
--     on a STRAY Scrappy the same command builds trust instead, until it is adopted (card #253).
-- Hooks are installed in OnGameBoot, after every base-mod file has defined what we wrap.
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local RECHARGE_REACH = 3   -- tiles between the owner and the dog

local function animalFromArgs(args)
    if not args then return nil end
    if args.__animal then return args.__animal end
    if args.id then return getAnimal(tonumber(args.id)) end
    return nil
end

-- Hand feeding / watering goes through CD.Server.<command>(player, args). Refused for Scrappy only.
local function refuseForScrappy(command)
    local original = CompanionDogs.Server[command]
    if not original then
        print("[GENZ_Scrappy] ERROR: CompanionDogs.Server." .. command .. " not found -- Scrappy can still be fed by it")
        return
    end
    CompanionDogs.Server[command] = function(player, args)
        local animal = animalFromArgs(args)
        if animal and S.isScrappy(animal) then
            S.toOwner(player, "nofood", {})
            return
        end
        return original(player, args)
    end
end

-- Bowl and trough: the companion tick calls CD.tryAutoFeed by field each time, so wrapping it is enough.
local function refuseAutoFeed()
    local CD = CompanionDogs
    local original = CD.tryAutoFeed
    if not original then
        print("[GENZ_Scrappy] ERROR: CompanionDogs.tryAutoFeed not found -- Scrappy may eat from bowls")
        return
    end
    CD.tryAutoFeed = function(animal, owner, d)
        if S.isScrappy(animal) then
            CD.setAutoFeedTag(animal, d, nil)
            return false
        end
        return original(animal, owner, d)
    end
end

local function shutDown(dog, d)
    local CD = CompanionDogs
    d.scrappyOff = true
    CD.setState(dog, CD.STATE_STAY)
    CD.transmit(dog)
    local owner = CD.getOwnerPlayer(dog)
    print("[GENZ_Scrappy] shut down (no charge), owner " .. tostring(owner and owner:getUsername()))
    if owner then
        S.toOwner(owner, "shutdown", {})
    end
end

local function holdPower(dog)
    local CD = CompanionDogs
    CD.setNeed(dog, "thirst", 0)
    local off = S.offLevel()
    if dog:getHunger() < off then return end
    CD.setNeed(dog, "hunger", off)
    local d = CD.data(dog)
    if not d.scrappyOff then
        shutDown(dog, d)
    elseif CD.getState(dog) ~= CD.STATE_STAY then
        CD.setState(dog, CD.STATE_STAY)   -- an order to follow does not wake a dead battery
        CD.transmit(dog)
    end
end

local function everyMinute()
    local CD = CompanionDogs
    local dogs = CD.regCompanions()
    for i = 1, #dogs do
        local dog = dogs[i]
        if dog:isExistInTheWorld() and not dog:isDead() and S.isScrappy(dog) then
            holdPower(dog)
        end
    end
end

local function companionCount(player)
    local companions = CompanionDogs.playerData(player).companions
    if type(companions) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(companions) do n = n + 1 end
    return n
end

-- The tame step of CompanionDogs.Server.feed (CompanionDogs_Commands.lua), which is inline there and
-- cannot be called without a food item. Kept line for line so a Scrappy is adopted like any dog.
local function adopt(player, dog)
    local CD = CompanionDogs
    local pd = CD.playerData(player)
    if pd.token ~= nil and not CD.hasRecoverableCompanion(player) then
        pd.token = nil
        pd.name = nil
        pd.stash = nil
        player:transmitModData()
    end
    local prev = CD.getCompanionAnimal(player)
    CD.makeCompanion(dog, player)
    if prev and prev ~= dog then
        CD.setState(prev, CD.STATE_STAY)
        CD.transmit(prev)
    end
    player:transmitModData()
    local targs = { id = dog:getOnlineID(), breed = CD.getBreed(dog) }
    if not isServer() then
        targs.animal = dog
    end
    CD.notifyOwner(player, "tamed", targs)
    print("[GENZ_Scrappy] " .. tostring(player:getUsername()) .. " befriended a stray Scrappy")
end

-- A stray Scrappy is befriended with ENERGY instead of food (card #253): it refuses food, and the base
-- mod only gains trust by feeding. One full charge (100%) is the whole tame threshold, so with the
-- defaults 4 pilhas (25% each) or 1 car battery; only what is still missing is drawn from the item.
local function befriend(player, dog, item, uses, value)
    local CD = CompanionDogs
    local limit = CD.maxCompanions()
    if limit > 0 and companionCount(player) >= limit then
        CD.notifyOwner(player, "limitreached", { max = limit })   -- checked before the battery is spent
        return
    end
    local need = CD.tameThreshold()
    local missingCharge = math.max(0, need - CD.getTrust(dog)) / need
    local energy = uses * value
    local tamed = energy >= missingCharge
    local spent = tamed and missingCharge or energy
    item:setCurrentUsesFloat(uses - spent / value)
    item:syncItemFields()
    if tamed then
        CD.setTrust(dog, need)
        adopt(player, dog)
    else
        CD.setTrust(dog, CD.getTrust(dog) + spent * need)
        CD.notifyOwner(player, "trust",
            { id = dog:getOnlineID(), trust = CD.getTrust(dog), max = need, breed = CD.getBreed(dog) })
    end
    CD.transmit(dog)
end

local function recharge(player, args)
    local CD = CompanionDogs
    local dog = animalFromArgs(args)
    if not player or not dog or not S.isScrappy(dog) then return end
    local stray = not CD.isCompanion(dog)
    if not stray and not CD.isOwnedBy(dog, player) then return end
    local dx, dy = dog:getX() - player:getX(), dog:getY() - player:getY()
    if dx * dx + dy * dy > RECHARGE_REACH * RECHARGE_REACH then
        S.toOwner(player, "toofar", {})
        return
    end
    local item = args.itemId and player:getInventory():getItemById(tonumber(args.itemId))
    local value = item and S.chargeOf(item:getFullType()) or 0
    if value <= 0 then return end
    local uses = item:getCurrentUsesFloat()
    if uses <= 0 then return end
    if stray then
        befriend(player, dog, item, uses, value)
        return
    end

    local off = S.offLevel()
    local missing = math.min(dog:getHunger(), off)
    local given = math.min(missing, uses * value * off)
    if given > 0 then
        CD.setNeed(dog, "hunger", dog:getHunger() - given)
        item:setCurrentUsesFloat(uses - given / (value * off))
        item:syncItemFields()
        CD.setLoyalty(dog, math.min(CD.TRUST_MAX, CD.loyalty(dog) + CD.FEED_LOYALTY_GAIN))
    end
    local d = CD.data(dog)
    if d.scrappyOff then
        d.scrappyOff = nil
        if not S.isBroken(dog) then   -- charged but broken: still needs maintenance before it moves
            CD.setState(dog, CD.STATE_FOLLOW)
        end
    end
    CD.transmit(dog)
    local pct = math.floor(S.chargeFraction(dog) * 100 + 0.5)
    print("[GENZ_Scrappy] " .. tostring(player:getUsername()) .. " recharged Scrappy with "
          .. item:getFullType() .. " -> " .. pct .. "%")
    S.toOwner(player, "recharged", { pct = pct })
end

Events.OnGameBoot.Add(function()
    local CD = CompanionDogs
    if not (CD and CD.Server and CD.setNeed and CD.regCompanions) then
        print("[GENZ_Scrappy] ERROR: CompanionDogs server API missing -- Scrappy power is OFF (it will eat like a dog)")
        return
    end
    refuseForScrappy("feed")
    refuseForScrappy("water")
    refuseAutoFeed()
    CD.Server.scrappyRecharge = recharge
    Events.EveryOneMinute.Add(everyMinute)
    print(string.format("[GENZ_Scrappy] power on: shuts down at hunger %.3f (base drain starts above %.2f)",
                        S.offLevel(), CD.SEVERE_NEED))
end)
