-- Scrappy shared rules: the breed key, the power model and the one path from the server
-- to the dog's owner. Loaded on client and server.
--
-- POWER MODEL: Scrappy does not eat. Its charge is the base mod's HUNGER read upside down, so the
-- base mod's own upkeep (CompanionDogs_Upkeep: +hungerPerDay per in-game day, same for every dog) is the
-- discharge, with no timer of ours: hunger 0 = 100%, hunger offLevel() = 0% (shut down).
-- offLevel() sits BELOW CD.SEVERE_NEED by the largest single upkeep step (it catches up at most
-- UPKEEP_MAX_CATCHUP_MIN at once). Above SEVERE_NEED the base mod switches invincibility off and drains
-- health -- a dog left empty would die. Kept under it, Scrappy shuts down instead of dying.
CompanionDogsScrappy = CompanionDogsScrappy or {}
local S = CompanionDogsScrappy

S.NET = "CompanionDogsScrappy"
S.BREED_KEY = "scrappy"
S.clientHandlers = S.clientHandlers or {}

-- SANDBOX: every number an admin may want to tune is an option of media/sandbox-options.txt (page
-- CompanionDogsScrappy), read at the moment it is used and never cached. An admin change made in game reaches
-- SandboxVars on the server and on every client at once (GameServer/GameClient.receiveSandboxOptions ->
-- SandboxOptions.toLua, decompiled 42.21), so caching would make the change wait for a restart.
function S.opt(name)
    local page = SandboxVars and SandboxVars.CompanionDogsScrappy
    local value = page and page[name]
    if value == nil then
        error("[CompanionDogsScrappy] sandbox option CompanionDogsScrappy." .. tostring(name) .. " is missing (sandbox-options.txt not loaded?)")
    end
    return value
end

-- Chargers: item -> sandbox option with the % of a full charge a FULL item gives (a half-used item gives half).
S.CHARGERS = {
    ["Base.Battery"] = "ChargeBattery",
    ["Base.CarBattery1"] = "ChargeCarBattery",
    ["Base.CarBattery2"] = "ChargeCarBattery",
    ["Base.CarBattery3"] = "ChargeCarBattery",
}

-- Full charges a full item of this type gives; 0 = not a charger (or switched off in the sandbox).
function S.chargeOf(fullType)
    local option = S.CHARGERS[fullType]
    if not option then return 0 end
    return S.opt(option) / 100
end

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
-- tested in game). A Scrappy that never wore down has no value yet: it is new.
-- Below this condition (sandbox WorkingThreshold, %): no jewel loot, no XP aura; at 0 it breaks and stays put.
function S.degradedBelow()
    return S.opt("WorkingThreshold") / 100
end

-- Maintenance is a training activity, modelled on the vanilla generator repair (ISFixGenerator: one
-- ElectronicsScrap per cycle, +4% + Electricity level / 2, 5 XP, repeats until full). Scrappy pays double
-- XP on Electricity by default on purpose: it is meant to be THE way to train it. Only a screwdriver is needed.
-- Parts by item TYPE (Base module). `opt` prefixes the sandbox options of that part: <opt>Gain and
-- <opt>GainPerLevel (% of condition), <opt>XP, <opt>Level (perk level below which it starts to fail).
S.REPAIRS = {
    ElectronicsScrap = { perk = "Electricity", opt = "Electronics" },
    ScrapMetal       = { perk = "MetalWelding", opt = "ScrapMetal" },
}
S.REPAIR_ORDER = { "ElectronicsScrap", "ScrapMetal" }
-- "Calibrate circuits": Electricity training that does not need wear, CalibratePerDay times per in-game day.
S.CALIBRATE = "calibrate"
S.CALIBRATION = { part = "ElectronicsScrap", perk = "Electricity", opt = "Calibrate" }

-- FAILURE, copied from the vanilla item repair (FixingManager.getChanceOfFail, decompiled 42.21): FailBase
-- (3%), +FailPerMissingLevel (30%) per level missing, -FailPerExtraLevel (5%) per level above, clamped
-- 0..100. Vanilla also adds +2% per earlier repair of the item; left out here, a dog repaired every few days
-- would end up never repairable. A failed cycle does what the vanilla one does: the part is spent, the
-- condition drops by FailedWear (1%), no XP.

-- What one maintenance mode spends and trains: a REPAIRS entry, or CALIBRATION.
function S.maintenanceRule(mode)
    if mode == S.CALIBRATE then return S.CALIBRATION end
    return S.REPAIRS[mode]
end

function S.maintenanceXp(mode)
    return S.opt(S.maintenanceRule(mode).opt .. "XP")
end

function S.requiredLevel(mode)
    return S.opt(S.maintenanceRule(mode).opt .. "Level")
end

function S.failedWear()
    return S.opt("FailedWear") / 100
end

-- Chance, 0..100, that one cycle of `mode` fails for this player.
function S.failPercent(player, mode)
    local rule = S.maintenanceRule(mode)
    local diff = player:getPerkLevel(Perks[rule.perk]) - S.requiredLevel(mode)
    local percent = S.opt("FailBase")
    if diff < 0 then
        percent = percent - diff * S.opt("FailPerMissingLevel")
    else
        percent = percent - diff * S.opt("FailPerExtraLevel")
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
    return not S.isOff(animal) and S.condition(animal) >= S.degradedBelow()
end

function S.toolNotBroken(item)
    return not item:isBroken()
end

function S.hasScrewdriver(player)
    return player:getInventory():containsTagEvalRecurse(ItemTag.SCREWDRIVER, S.toolNotBroken)
end

function S.repairGain(player, partType)
    local part = S.REPAIRS[partType]
    local level = player:getPerkLevel(Perks[part.perk])
    return (S.opt(part.opt .. "Gain") + level * S.opt(part.opt .. "GainPerLevel")) / 100
end

function S.today()
    return math.floor(getGameTime():getWorldAgeHours() / 24)
end

function S.calibrationsLeft(animal)
    local d = CompanionDogs.data(animal)
    local perDay = S.opt("CalibratePerDay")
    if d.scrappyCalDay ~= S.today() then return perDay end
    return math.max(0, perDay - (d.scrappyCalCount or 0))
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
-- player the client handler is called directly (same shape as a server reply).
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
    print("[CompanionDogsScrappy] '" .. tostring(command) .. "' has no client handler in single player")
end

-- Runs fn on the server once every mod's Lua has loaded, the same on the dedicated server and in single
-- player. Events.OnGameBoot alone never fires for a file in server/ outside the dedicated
-- server: there that folder loads BEFORE OnGameBoot (GameServer.java:1472-1474, :1499, decompiled 42.21);
-- in single player and on an MP client it loads AFTER (Core.java:3985 vs GameLoadingState.java:148), so
-- the handler waits for an event that already happened, with no error. OnInitGlobalModData is the first
-- event after that with the world's sandbox read and no chunk loaded yet (IsoWorld.java:1909, :2022).
-- One branch per side, so fn cannot run twice. An MP client loads the server folder too and has no
-- business running a server handler.
-- Scrappy keeps its own copy: it is published alone and requires only CompanionDogs (no shared
-- core library exists for it).
function S.atServerBoot(fn)
    if type(fn) ~= "function" then
        error("CompanionDogsScrappy.atServerBoot: expected a function, got " .. tostring(fn))
    end
    if isServer() then
        Events.OnGameBoot.Add(fn)
        return
    end
    if isClient() then return end
    Events.OnInitGlobalModData.Add(fn)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= S.NET then return end
    local handler = S.clientHandlers[command]
    if handler then
        handler(args)
    end
end)
