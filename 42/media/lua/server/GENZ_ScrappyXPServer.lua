-- Scrappy XP aura (card #246): while the owner has their Scrappy close by -- switched on and loyal --
-- Electricity and Metal Welding XP is worth sandbox AuraMultiplier times as much.
--
-- Same shape as the base mod's breed bonuses (CompanionDogs_XPBoost), on purpose:
--   * granted as EXTRA XP inside Events.AddXP, which the engine fires on the server and in single player;
--   * NEVER through addXpMultiplier: that is saved in the character and outlives the dog and the mod;
--   * a skill book uses the same multiplier slot, so the bigger one wins and they do not stack.
-- Not plugged into CD.ownerXPBoosts(): its save cleanup (purgeOwnerXPMultipliers) would wipe book and
-- trait multipliers up to our value on these two perks.
if isClient() and not isServer() then return end

require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

-- Sandbox AuraMultiplier (default 1.2, the Golden Retriever's and the Border Collie's), read per XP event.

local boostedPerks
local granting = false

local function ownersScrappyNearby(player)
    local CD = CompanionDogs
    local radius = CD.moodleHappyRadius()
    local dogs = CD.regCompanions()
    for i = 1, #dogs do
        local dog = dogs[i]
        if dog:isExistInTheWorld() and not dog:isDead() and S.isScrappy(dog) and CD.isOwnedBy(dog, player)
                and S.isWorking(dog) and not CD.isDisloyal(dog) and CD.dist2D(dog, player) <= radius then
            return dog
        end
    end
    return nil
end

local function onAddXP(chr, perk, amount)
    if granting or not chr or not perk or not boostedPerks[perk] then return end
    -- IsoAnimal extends IsoPlayer, and NPC mods gain XP too
    if instanceof(chr, "IsoAnimal") or chr:isNpc() then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    if not ownersScrappyNearby(chr) then return end
    local xp = chr:getXp()
    local book = xp:getMultiplier(perk)
    if book < 1 then book = 1 end
    local mult = S.opt("AuraMultiplier")
    if mult <= book then return end
    local bonus = amount * (mult / book - 1)
    granting = true
    xp:AddXP(perk, bonus, false, false, false)
    granting = false
end

S.atServerBoot(function()
    local CD = CompanionDogs
    if not (Perks and Perks.Electricity and Perks.MetalWelding) then
        print("[GENZ_Scrappy] ERROR: Perks.Electricity / Perks.MetalWelding not found -- XP aura is OFF")
        return
    end
    if not (CD and CD.regCompanions and CD.moodleHappyRadius and CD.dist2D) then
        print("[GENZ_Scrappy] ERROR: CompanionDogs API missing -- XP aura is OFF")
        return
    end
    boostedPerks = { [Perks.Electricity] = true, [Perks.MetalWelding] = true }
    Events.AddXP.Add(onAddXP)
    print("[GENZ_Scrappy] XP aura on: Electricity and MetalWelding x(sandbox AuraMultiplier)"
          .. " within " .. CD.moodleHappyRadius() .. " tiles")
end)
