-- Scrappy power, server side (card #246). Scrappy runs on batteries instead of food:
--   * food and water are refused (hand, bowl, trough) -- only for Scrappy, every other dog is untouched;
--   * thirst is held at 0 every in-game minute;
--   * when the charge runs out (GENZ_ScrappyShared.offLevel) it shuts down: hunger is held there, the dog
--     is put on STAY and the owner is told once;
--   * the "scrappyRecharge" command takes a pilha or a car battery from the owner's inventory.
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

local function recharge(player, args)
    local CD = CompanionDogs
    local dog = animalFromArgs(args)
    if not player or not dog or not S.isScrappy(dog) or not CD.isOwnedBy(dog, player) then return end
    local dx, dy = dog:getX() - player:getX(), dog:getY() - player:getY()
    if dx * dx + dy * dy > RECHARGE_REACH * RECHARGE_REACH then
        S.toOwner(player, "toofar", {})
        return
    end
    local item = args.itemId and player:getInventory():getItemById(tonumber(args.itemId))
    local value = item and S.CHARGERS[item:getFullType()]
    if not value then return end
    local uses = item:getCurrentUsesFloat()
    if uses <= 0 then return end

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
