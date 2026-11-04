-- Scrappy loot (cards #246, #300). When a zombie dies, the closest Scrappy companion near the
-- corpse moves the registered loot from the corpse into its saddlebag. What does not fit stays on
-- the corpse.
--
-- WHAT IT COLLECTS: whatever another mod registers, through one call (card #300 -- Scrappy is
-- standalone, published on its own and in the Season 2 modpack, and reads nobody's tables):
--   GENZ_Scrappy.registerLoot(name, itemTypes)   itemTypes[fullType] = any non-nil value
-- The table is kept, not copied: an item added to it later is collected with no new call. On
-- our server the jewel economy of GENZ_Equipamentos registers its JEWELS (GENZ_JewelLootBridge).
-- With nothing registered, Scrappy collects nothing and says so once, at the first death.
--
-- WHY INSIDE OnZombieDead: GENZ_JewelDropServer (GENZ_Equipamentos) authors the jewels in this same
-- event, right after DoZombieInventory. The corpse inherits the zombie's container and is sent once by
-- sendCharacterDeath, so removing items here costs no network and cannot desync. One tick later the
-- corpse already exists on the clients and every removal would need its own sync.
--
-- WHY REGISTERED IN OnGameBoot: this handler must run AFTER the jewel drop. Lua event callbacks run in
-- the order they were added (zombie.Lua.Event.trigger walks an ArrayList), and the jewel drop adds its
-- handler at file load; adding ours at OnGameBoot puts it after every file-load registration.
-- The loot sources are looked up on every death, not at boot, so the mod that registers them may
-- load before or after this one.
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy
local LOG_TAG = "[GENZ_Scrappy] "

local lootSources = {}
local saidNothingRegistered = false

-- Kahlua has no global next() (pz-b42-modding §29): emptiness is asked with pairs.
local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

function S.registerLoot(name, itemTypes)
    if type(name) ~= "string" or name == "" then
        error("GENZ_Scrappy.registerLoot: the name must be a non-empty string, got " .. tostring(name))
    end
    if type(itemTypes) ~= "table" or isEmpty(itemTypes) then
        error("GENZ_Scrappy.registerLoot('" .. name .. "'): itemTypes must be a non-empty table keyed by full type")
    end
    lootSources[name] = itemTypes
    print(LOG_TAG .. "loot source '" .. name .. "' registered")
end

local function isLoot(fullType)
    for _, itemTypes in pairs(lootSources) do
        if itemTypes[fullType] ~= nil then return true end
    end
    return false
end

local function hasLootSource()
    return not isEmpty(lootSources)
end

-- Said once: with no loot source this runs on every zombie death.
local function warnNoLootSourceOnce()
    if saidNothingRegistered then return end
    saidNothingRegistered = true
    print(LOG_TAG .. "no loot source registered -- Scrappy collects nothing from corpses")
end

local function sameFloor(a, b)
    return math.floor(a) == math.floor(b)
end

local function closestScrappy(x, y, z)
    local CD = CompanionDogs
    local best, bestDist
    local radius = S.opt("LootRadius")   -- tiles from the corpse to the dog, same floor; read per death (live)
    local dogs = CD.regCompanions()
    for i = 1, #dogs do
        local dog = dogs[i]
        if dog:isExistInTheWorld() and not dog:isDead() and S.isScrappy(dog) and S.isWorking(dog)
                and sameFloor(dog:getZ(), z) then
            local dx, dy = dog:getX() - x, dog:getY() - y
            local dist = dx * dx + dy * dy
            if dist <= radius * radius and (bestDist == nil or dist < bestDist) then
                best, bestDist = dog, dist
            end
        end
    end
    return best
end

local function moveLootToBag(zombie)
    if not hasLootSource() then
        warnNoLootSourceOnce()
        return
    end
    local inv = zombie:getInventory()
    if not inv then return end
    local CD = CompanionDogs
    local dog = closestScrappy(zombie:getX(), zombie:getY(), zombie:getZ())
    if not dog or CD.isDisloyal(dog) or not CD.hasBag(dog) then return end
    local owner = CD.getOwnerPlayer(dog)
    if not owner then return end

    local taken = {}
    local items = inv:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        local fullType = item:getFullType()
        if isLoot(fullType) then
            local ok, reason = CD.bagInsert(owner, dog, item)
            if not ok then
                print("[GENZ_Scrappy] bag refused " .. fullType .. " (" .. tostring(reason) .. "); the rest stays on the corpse")
                break
            end
            inv:Remove(item)
            taken[#taken + 1] = fullType
        end
    end
    if #taken == 0 then return end
    print(LOG_TAG .. tostring(owner:getUsername()) .. "'s Scrappy looted " .. #taken
          .. " item(s): " .. table.concat(taken, ", "))
    S.toOwner(owner, "looted", { items = taken })
end

Events.OnGameBoot.Add(function()
    if not (CompanionDogs and CompanionDogs.regCompanions and CompanionDogs.bagInsert) then
        print(LOG_TAG .. "ERROR: CompanionDogs API missing (regCompanions/bagInsert) -- loot is OFF")
        return
    end
    Events.OnZombieDead.Add(moveLootToBag)
    print(LOG_TAG .. "loot on (radius: sandbox GENZ_Scrappy.LootRadius; items: what other mods register)")
end)
