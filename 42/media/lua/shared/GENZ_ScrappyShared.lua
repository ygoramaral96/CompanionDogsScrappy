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
-- Maintenance is a training activity, modelled on the vanilla generator repair (ISFixGenerator: one
-- ElectronicsScrap per cycle, +4% + Electricity level / 2, 5 XP, repeats until full). Scrappy pays double
-- XP on Electricity on purpose: it is meant to be THE way to train it. Only a screwdriver is needed.
-- Parts by item TYPE (Base module): gain = base + perkLevel * perLevel (condition, 0..1); xp = perk XP;
-- level = perk level below which the cycle starts to fail (see S.failPercent).
S.REPAIRS = {
    ElectronicsScrap = { perk = "Electricity", xp = 10, base = 0.04, perLevel = 0.005, level = 3 },
    ScrapMetal       = { perk = "MetalWelding", xp = 15, base = 0.02, perLevel = 0.0025, level = 3 },
}
S.REPAIR_ORDER = { "ElectronicsScrap", "ScrapMetal" }
-- "Calibrate circuits": Electricity training that does not need wear, a few times per in-game day.
S.CALIBRATE = "calibrate"
S.CALIBRATION = { part = "ElectronicsScrap", perk = "Electricity", xp = 10, perDay = 3, level = 3 }

-- FAILURE, copied from the vanilla item repair (FixingManager.getChanceOfFail, decompiled 42.21): 3%, +30%
-- per level missing, -5% per level above, clamped 0..100. Vanilla also adds +2% per earlier repair of the
-- item; left out here, a dog repaired every few days would end up never repairable. A failed cycle does
-- what the vanilla one does: the part is spent, -1% condition, no XP.
S.FAIL_BASE = 3
S.FAIL_PER_MISSING_LEVEL = 30
S.FAIL_PER_EXTRA_LEVEL = 5
S.FAILED_WEAR = 0.01

-- What one maintenance mode spends and trains: a REPAIRS entry, or CALIBRATION.
function S.maintenanceRule(mode)
    if mode == S.CALIBRATE then return S.CALIBRATION end
    return S.REPAIRS[mode]
end

-- Chance, 0..100, that one cycle of `mode` fails for this player.
function S.failPercent(player, mode)
    local rule = S.maintenanceRule(mode)
    local diff = player:getPerkLevel(Perks[rule.perk]) - rule.level
    local percent = S.FAIL_BASE
    if diff < 0 then
        percent = percent - diff * S.FAIL_PER_MISSING_LEVEL
    else
        percent = percent - diff * S.FAIL_PER_EXTRA_LEVEL
    end
    return math.max(0, math.min(100, percent))
end

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

function S.hasScrewdriver(player)
    return player:getInventory():containsTagEvalRecurse(ItemTag.SCREWDRIVER, S.toolNotBroken)
end

function S.repairGain(player, partType)
    local part = S.REPAIRS[partType]
    return part.base + player:getPerkLevel(Perks[part.perk]) * part.perLevel
end

function S.today()
    return math.floor(getGameTime():getWorldAgeHours() / 24)
end

function S.calibrationsLeft(animal)
    local d = CompanionDogs.data(animal)
    if d.scrappyCalDay ~= S.today() then return S.CALIBRATION.perDay end
    return S.CALIBRATION.perDay - (d.scrappyCalCount or 0)
end

-- Can this player run maintenance `mode` on this dog right now? Shared by the action (client and server)
-- and the context menu, so the three never disagree.
function S.canMaintain(player, animal, mode)
    if not S.isScrappy(animal) or not CompanionDogs.isOwnedBy(animal, player) then return false end
    if not S.hasScrewdriver(player) then return false end
    local inv = player:getInventory()
    if mode == S.CALIBRATE then
        return S.calibrationsLeft(animal) > 0 and inv:containsTypeRecurse(S.CALIBRATION.part)
    end
    return S.REPAIRS[mode] ~= nil and S.condition(animal) < 1 and inv:containsTypeRecurse(mode)
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
