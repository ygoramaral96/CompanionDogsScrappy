-- Scrappy jewelry loot (card #246). When a zombie dies, the closest Scrappy companion near the
-- corpse moves the jewels from the corpse into its saddlebag. What does not fit stays on the corpse.
--
-- WHY INSIDE OnZombieDead: GENZ_JewelDropServer (GENZ_Equipamentos) authors the jewels in this same
-- event, right after DoZombieInventory. The corpse inherits the zombie's container and is sent once by
-- sendCharacterDeath, so removing items here costs no network and cannot desync. One tick later the
-- corpse already exists on the clients and every removal would need its own sync.
--
-- WHY REGISTERED IN OnGameBoot: this handler must run AFTER the jewel drop. Lua event callbacks run in
-- the order they were added (zombie.Lua.Event.trigger walks an ArrayList), and the jewel drop adds its
-- handler at file load; adding ours at OnGameBoot puts it after every file-load registration.
--
-- The list of jewels is GENZ_JewelEconomy.JEWELS, the same one that turns jewels into Z Coins. It is
-- read, never copied: a jewel added there is collected here with no change.
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

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

local function moveJewelsToBag(zombie, jewels)
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
        if jewels[fullType] then
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
    print("[GENZ_Scrappy] " .. tostring(owner:getUsername()) .. "'s Scrappy looted " .. #taken
          .. " jewel(s): " .. table.concat(taken, ", "))
    S.toOwner(owner, "looted", { items = taken })
end

Events.OnGameBoot.Add(function()
    local jewels = GENZ_JewelEconomy and GENZ_JewelEconomy.JEWELS
    if not jewels then
        print("[GENZ_Scrappy] ERROR: GENZ_JewelEconomy.JEWELS not found -- jewelry loot is OFF. "
              .. "Is GENZ_Equipamentos loaded (mod.info requires it)?")
        return
    end
    if not (CompanionDogs and CompanionDogs.regCompanions and CompanionDogs.bagInsert) then
        print("[GENZ_Scrappy] ERROR: CompanionDogs API missing (regCompanions/bagInsert) -- jewelry loot is OFF")
        return
    end
    Events.OnZombieDead.Add(function(zombie)
        moveJewelsToBag(zombie, jewels)
    end)
    print("[GENZ_Scrappy] jewelry loot on (radius: sandbox GENZ_Scrappy.LootRadius)")
end)
