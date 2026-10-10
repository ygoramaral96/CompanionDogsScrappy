-- Scrappy breed registration for Companion Dogs (add-on contract: CD.registerBreed).
-- Identity: a mechanical dog that loots jewelry off zombies, carries more than any other breed
-- and speeds up the owner's Electricity and MetalWelding. Those last two are NOT breed fields in
-- the base mod: they are separate systems (loot, owner XP) added in later phases of card #246.
-- This file only registers the breed.
local CD = CompanionDogs
-- Without the base mod (0.6.3+) the add-on stays inert, same gate as the official add-ons.
if not (CD and CD.registerBreed and (CD.API_VERSION or 0) >= 1) then return end

CD.registerBreed({
    key = "scrappy",
    engineBreed = "scrappy",
    typePrefix = "scrappy",                -- animal types: scrappypup / scrappyfemale / scrappymale
    nameKey = "IGUI_PD_Breed_scrappy",
    -- "Normal combat": placeholder copied from the Golden Retriever's combat block. Real balance
    -- comes from scripts/loja/balance_animais.py once the breed is measured.
    xpMult = { scent = 1, combat = 1, obedience = 1, hunt = 1, herding = 1 },
    combatPower = 0.34,
    lethalityCurve = { min = 0.40, max = 1.3 },
    canKill = true,
    canKnockdown = true,
    combatStressMult = 0.33,
    panicThreshold = 0.85,
    -- No offspring: breeding is refused by CD.breedCanBreed (Breeding.lua / Commands.lua). The pup
    -- type still has to exist because the base registers all three types for every breed.
    canBreed = false,
    -- Bigger saddlebag: capacity = (4 + 8 * strength gene ratio) * bagMult, hard cap 100.
    bagMult = 1.5,
    geneRange = {
        strength       = { 0.50, 0.70 },   -- high on purpose: the saddlebag scales with it
        aggressiveness = { 0.10, 0.30 },
        resistance     = { 0.20, 0.40 },
        stress         = { 0.30, 0.60 },
    },
    -- No `spawns`: Scrappy is not a stray. It only exists through the shop.
})
