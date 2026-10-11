-- Scrappy wear and maintenance, server side (card #246).
--   * wear: a little every in-game minute, and more for each zombie it kills (CD.recordDogZombieKill,
--     called by CompanionDogs_Strike on the server and read by field, so wrapping it is enough);
--   * below GENZ_ScrappyShared.DEGRADED_BELOW the loot and the XP aura stop (they check S.isWorking);
--   * at 0 it breaks: STAY until repaired, owner told once;
--   * "scrappyRepair": the owner, with a screwdriver, spends one part to restore condition and gets XP.
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local WEAR_PER_KILL = 0.01   -- 100 kills from new to broken
local WEAR_PER_DAY = 0.05    -- 20 in-game days from new to broken, even standing still
local REPAIR_REACH = 3       -- tiles between the mechanic and the dog

local function animalFromArgs(args)
    if not args then return nil end
    if args.__animal then return args.__animal end
    if args.id then return getAnimal(tonumber(args.id)) end
    return nil
end

-- 2 = working, 1 = degraded, 0 = broken
local function band(condition)
    if condition <= 0 then return 0 end
    if condition < S.DEGRADED_BELOW then return 1 end
    return 2
end

-- Writes the new condition and tells the owner when it drops into a worse band. Sync is the caller's job:
-- the kill path is followed by CD.transmit in CompanionDogs_Strike, the minute tick syncs band changes.
local function setCondition(dog, value)
    local CD = CompanionDogs
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    local oldBand = band(S.condition(dog))
    CD.data(dog).scrappyCondition = value
    local newBand = band(value)
    if newBand >= oldBand then return end
    local owner = CD.getOwnerPlayer(dog)
    if newBand == 0 then
        CD.setState(dog, CD.STATE_STAY)
        print("[GENZ_Scrappy] broke down (condition 0), owner " .. tostring(owner and owner:getUsername()))
        if owner then S.toOwner(owner, "broken", {}) end
    elseif owner then
        S.toOwner(owner, "degraded", {})
    end
end

local function everyMinute()
    local CD = CompanionDogs
    local dogs = CD.regCompanions()
    for i = 1, #dogs do
        local dog = dogs[i]
        if dog:isExistInTheWorld() and not dog:isDead() and S.isScrappy(dog) then
            if not S.isBroken(dog) then
                local oldBand = band(S.condition(dog))
                setCondition(dog, S.condition(dog) - WEAR_PER_DAY / 1440)
                if band(S.condition(dog)) ~= oldBand then
                    CD.transmit(dog)
                end
            elseif CD.getState(dog) ~= CD.STATE_STAY then
                CD.setState(dog, CD.STATE_STAY)   -- an order to follow does not fix a broken dog
                CD.transmit(dog)
            end
        end
    end
end

local function repair(player, args)
    local CD = CompanionDogs
    local dog = animalFromArgs(args)
    if not player or not dog or not S.isScrappy(dog) or not CD.isOwnedBy(dog, player) then return end
    local dx, dy = dog:getX() - player:getX(), dog:getY() - player:getY()
    if dx * dx + dy * dy > REPAIR_REACH * REPAIR_REACH then
        S.toOwner(player, "toofar", {})
        return
    end
    local part = args.part and S.REPAIRS[args.part]
    if not part then return end
    local inv = player:getInventory()
    if not inv:containsTagEvalRecurse(ItemTag.SCREWDRIVER, S.toolNotBroken) then return end
    local item = inv:getFirstTypeRecurse(args.part)
    if not item then return end
    local old = S.condition(dog)
    if old >= 1 then
        S.toOwner(player, "fullcondition", {})
        return
    end

    local cont = item:getContainer() or inv
    if isServer() then
        sendRemoveItemFromContainer(cont, item)   -- before Remove: a bare Remove leaves a ghost item on the client
    end
    cont:Remove(item)
    setCondition(dog, old + part.gain)
    -- 5-argument form on purpose (decompiled 42.21): the short AddXP overloads only act when
    -- isLocalPlayer(), which a player never is on a dedicated server. doXPBoost = true applies the normal
    -- rules (traits, book, sandbox multiplier); AddXP fires Events.AddXP regardless of callLua, so the
    -- Scrappy XP aura also applies when the repaired dog is working.
    player:getXp():AddXP(Perks[part.perk], part.xp, true, true, false)
    if old <= 0 and not S.isOff(dog) then
        CD.setState(dog, CD.STATE_FOLLOW)
    end
    CD.transmit(dog)
    local pct = math.floor(S.condition(dog) * 100 + 0.5)
    print("[GENZ_Scrappy] " .. tostring(player:getUsername()) .. " repaired Scrappy with " .. args.part .. " -> " .. pct .. "%")
    S.toOwner(player, "repaired", { pct = pct })
end

Events.OnGameBoot.Add(function()
    local CD = CompanionDogs
    if not (CD and CD.Server and CD.recordDogZombieKill and CD.regCompanions) then
        print("[GENZ_Scrappy] ERROR: CompanionDogs API missing (recordDogZombieKill/regCompanions) -- wear is OFF")
        return
    end
    local originalKill = CD.recordDogZombieKill
    CD.recordDogZombieKill = function(animal)
        originalKill(animal)
        if S.isScrappy(animal) and not S.isBroken(animal) then
            setCondition(animal, S.condition(animal) - WEAR_PER_KILL)
        end
    end
    CD.Server.scrappyRepair = repair
    Events.EveryOneMinute.Add(everyMinute)
    print(string.format("[GENZ_Scrappy] wear on: %.0f%% per kill, %.0f%% per in-game day, degraded below %.0f%%",
                        WEAR_PER_KILL * 100, WEAR_PER_DAY * 100, S.DEGRADED_BELOW * 100))
end)
