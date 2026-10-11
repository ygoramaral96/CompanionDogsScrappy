-- Scrappy wear and maintenance, server side (card #246).
--   * wear: a little every in-game minute, and more for each zombie it kills (CD.recordDogZombieKill,
--     called by CompanionDogs_Strike on the server and read by field, so wrapping it is enough);
--   * below GENZ_ScrappyShared.DEGRADED_BELOW the loot and the XP aura stop (they check S.isWorking);
--   * at 0 it breaks: STAY until repaired, owner told once;
--   * GENZ_ScrappyWear.maintain: what one cycle of GENZ_ScrappyMaintainAction does, called from its
--     complete() (server in MP, local in single player).
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

GENZ_ScrappyWear = GENZ_ScrappyWear or {}
local Wear = GENZ_ScrappyWear

local WEAR_PER_KILL = 0.01   -- 100 kills from new to broken
local WEAR_PER_DAY = 0.05    -- 20 in-game days from new to broken, even standing still

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

-- Takes one part out of the player's inventory, the way the base mod and ISFixGenerator do it.
local function consumeOne(player, partType)
    local inv = player:getInventory()
    local item = inv:getFirstTypeRecurse(partType)
    if not item then return false end
    local cont = item:getContainer() or inv
    player:removeFromHands(item)
    if isServer() then
        sendRemoveItemFromContainer(cont, item)   -- before Remove: a bare Remove leaves a ghost item on the client
    end
    cont:Remove(item)
    return true
end

-- XP through the vanilla global (what ISFixGenerator uses): on the server it goes through GameServer.addXp,
-- which applies the normal multipliers AND syncs XP to the client (updateXpChecker). The short
-- player:getXp():AddXP overloads give nothing on a dedicated server (skill §221). Events.AddXP fires inside,
-- so the Scrappy XP aura applies when the dog is working.
local function giveXp(player, perkName, amount)
    addXp(player, Perks[perkName], amount)
end

local function calibrate(player, dog)
    if not consumeOne(player, S.CALIBRATION.part) then return false end
    local d = CompanionDogs.data(dog)
    if d.scrappyCalDay ~= S.today() then
        d.scrappyCalDay = S.today()
        d.scrappyCalCount = 0
    end
    d.scrappyCalCount = d.scrappyCalCount + 1
    giveXp(player, S.CALIBRATION.perk, S.CALIBRATION.xp)
    CompanionDogs.transmit(dog)
    S.toOwner(player, "calibrated", { left = S.calibrationsLeft(dog) })
    return true
end

local function repair(player, dog, partType)
    local old = S.condition(dog)
    local gain = S.repairGain(player, partType)
    if not consumeOne(player, partType) then return false end
    setCondition(dog, old + gain)
    giveXp(player, S.REPAIRS[partType].perk, S.REPAIRS[partType].xp)
    if old <= 0 and not S.isOff(dog) then
        CompanionDogs.setState(dog, CompanionDogs.STATE_FOLLOW)
    end
    CompanionDogs.transmit(dog)
    local pct = math.floor(S.condition(dog) * 100 + 0.5)
    print("[GENZ_Scrappy] " .. tostring(player:getUsername()) .. " repaired Scrappy with " .. partType .. " -> " .. pct .. "%")
    S.toOwner(player, "repaired", { pct = pct })
    return true
end

-- One cycle of GENZ_ScrappyMaintainAction. Re-checks everything: complete() runs on the server with the
-- server's copy of the dog, which is the one that counts.
function Wear.maintain(player, dog, mode)
    if not player or not dog or not S.canMaintain(player, dog, mode) then return false end
    if mode == S.CALIBRATE then
        return calibrate(player, dog)
    end
    return repair(player, dog, mode)
end

Events.OnGameBoot.Add(function()
    local CD = CompanionDogs
    if not (CD and CD.recordDogZombieKill and CD.regCompanions) then
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
    Events.EveryOneMinute.Add(everyMinute)
    print(string.format("[GENZ_Scrappy] wear on: %.0f%% per kill, %.0f%% per in-game day, degraded below %.0f%%",
                        WEAR_PER_KILL * 100, WEAR_PER_DAY * 100, S.DEGRADED_BELOW * 100))
end)
