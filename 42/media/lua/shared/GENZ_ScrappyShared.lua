-- Scrappy shared rules (card #246): the breed key, the power model and the one path from the server
-- to the dog's owner. Loaded on client and server.
--
-- POWER MODEL: Scrappy does not eat. Its charge is the base mod's HUNGER read upside down, so the
-- base mod's own upkeep (CompanionDogs_Upkeep: +hungerPerDay per in-game day, same for every dog) is the
-- discharge, with no timer of ours: hunger 0 = 100%, hunger offLevel() = 0% (shut down).
-- offLevel() sits BELOW CD.SEVERE_NEED by the largest single upkeep step (it catches up at most
-- UPKEEP_MAX_CATCHUP_MIN at once). Above SEVERE_NEED the base mod switches invincibility off and drains
-- health -- a dog left empty would die. Kept under it, Scrappy shuts down instead of dying.
GENZ_Scrappy = GENZ_Scrappy or {}
local S = GENZ_Scrappy

S.NET = "GENZ_Scrappy"
S.BREED_KEY = "scrappy"
S.clientHandlers = S.clientHandlers or {}

-- Full charges given by a FULL item; a half-used item gives half. Pilha = a quarter, car battery = full.
S.CHARGERS = {
    ["Base.Battery"] = 0.25,
    ["Base.CarBattery1"] = 1.0,
    ["Base.CarBattery2"] = 1.0,
    ["Base.CarBattery3"] = 1.0,
}

local OFF_MARGIN = 0.01

function S.isScrappy(animal)
    return CompanionDogs.getBreed(animal) == S.BREED_KEY
end

function S.offLevel()
    local CD = CompanionDogs
    local largestUpkeepStep = CD.hungerPerDay() * CD.UPKEEP_MAX_CATCHUP_MIN / 1440
    return CD.SEVERE_NEED - largestUpkeepStep - OFF_MARGIN
end

function S.chargeFraction(animal)
    local charge = 1 - animal:getHunger() / S.offLevel()
    if charge < 0 then return 0 end
    if charge > 1 then return 1 end
    return charge
end

function S.isOff(animal)
    return CompanionDogs.data(animal).scrappyOff == true
end

-- WEAR: condition 1 = new, 0 = broken, kept in the dog's CompanionDogs data (survives being picked up,
-- tested in game 10/10). A Scrappy that never wore down has no value yet: it is new.
S.DEGRADED_BELOW = 0.1   -- below this: no jewel loot, no XP aura; at 0 it breaks and stays put
-- Parts by item TYPE (Base module). gain = condition restored, xp = perk XP given to the mechanic.
S.REPAIRS = {
    ElectronicsScrap = { gain = 0.25, perk = "Electricity", xp = 5 },
    ScrapMetal       = { gain = 0.10, perk = "MetalWelding", xp = 5 },
}
S.REPAIR_ORDER = { "ElectronicsScrap", "ScrapMetal" }

function S.condition(animal)
    local value = CompanionDogs.data(animal).scrappyCondition
    if value == nil then return 1 end
    return value
end

function S.isBroken(animal)
    return S.condition(animal) <= 0
end

-- Switched on and not worn below the threshold: the jewel loot and the XP aura only run when this is true.
function S.isWorking(animal)
    return not S.isOff(animal) and S.condition(animal) >= S.DEGRADED_BELOW
end

function S.toolNotBroken(item)
    return not item:isBroken()
end

-- Server -> owner. sendServerCommand only acts when GameServer.server (decompiled 42.21), so in single
-- player the client handler is called directly (same shape as GENZ_KeysServer.reply).
function S.toOwner(owner, command, args)
    args = args or {}
    if isServer() then
        sendServerCommand(owner, S.NET, command, args)
        return
    end
    local handler = S.clientHandlers[command]
    if handler then
        handler(args)
        return
    end
    print("[GENZ_Scrappy] '" .. tostring(command) .. "' has no client handler in single player")
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= S.NET then return end
    local handler = S.clientHandlers[command]
    if handler then
        handler(args)
    end
end)
