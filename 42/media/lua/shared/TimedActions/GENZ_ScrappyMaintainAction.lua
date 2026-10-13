-- Scrappy maintenance as a timed action (card #246), modelled on the vanilla ISFixGenerator: a progress
-- bar, one part per cycle, and it queues the next cycle while it still makes sense.
-- mode = a part type from GENZ_Scrappy.REPAIRS ("ElectronicsScrap", "ScrapMetal") or GENZ_Scrappy.CALIBRATE.
--
-- NETWORK CONTRACT (decompiled 42.21, zombie/core/NetTimedAction.set/parse): the client sends, for every
-- parameter of new() after self, the action field WITH THE SAME NAME; the server rebuilds the action by
-- calling <Type>.new(...) with those values in order and then runs complete(). So every parameter of new()
-- must be stored under its own name (o.animal = animal, o.mode = mode) -- a renamed field arrives as nil on
-- the server, silently. The class must be a global in shared/ (the server looks it up by Type name).
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferUtil"
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local REACH = 3   -- squares, same as ISPetAnimal

GENZ_ScrappyMaintainAction = ISBaseTimedAction:derive("GENZ_ScrappyMaintainAction")
local Action = GENZ_ScrappyMaintainAction

local function perkOf(mode)
    if mode == S.CALIBRATE then return S.CALIBRATION.perk end
    return S.REPAIRS[mode].perk
end

function Action:isValid()
    if not self.animal or self.animal:isDead() or not self.animal:getSquare() then return false end
    if self.character:getSquare():DistTo(self.animal:getSquare()) >= REACH then return false end
    return S.canMaintain(self.character, self.animal, self.mode)
end

function Action:waitToStart()
    self.character:faceThisObject(self.animal)
    return self.character:shouldBeTurning()
end

function Action:update()
    self.character:faceThisObject(self.animal)
    self.character:setMetabolicTarget(Metabolics.UsingTools)
end

function Action:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
    self.animal:getBehavior():setBlockMovement(true)
    self.sound = self.character:playSound("GeneratorRepair")
end

function Action:release()
    self.character:stopOrTriggerSound(self.sound)
    self.animal:getBehavior():setBlockMovement(false)
end

function Action:stop()
    self:release()
    ISBaseTimedAction.stop(self)
end

-- Same as ISFixGenerator.continueFixing: bring the next part to the main inventory if needed, then queue
-- one more cycle. Stops by itself when the dog is full, the daily calibrations are used, or parts run out.
function Action:continueMaintaining()
    if not S.canMaintain(self.character, self.animal, self.mode) then return end
    local partType = self.mode == S.CALIBRATE and S.CALIBRATION.part or self.mode
    local part = self.character:getInventory():getFirstTypeRecurse(partType)
    if not part then return end
    local previous = self
    if part:getContainer() ~= self.character:getInventory() then
        local transfer = ISInventoryTransferUtil.newInventoryTransferAction(self.character, part,
            part:getContainer(), self.character:getInventory(), nil)
        ISTimedActionQueue.addAfter(self, transfer)
        previous = transfer
    end
    ISTimedActionQueue.addAfter(previous, Action:new(self.character, self.animal, self.mode))
end

function Action:perform()
    self:release()
    if isClient() then
        self:continueMaintaining()
    end
    ISBaseTimedAction.perform(self)
end

-- Runs on the server in MP (NetTimedAction) and locally in single player.
function Action:complete()
    if not (GENZ_ScrappyWear and GENZ_ScrappyWear.maintain) then
        print("[GENZ_Scrappy] ERROR: GENZ_ScrappyWear.maintain missing on this side -- maintenance did nothing")
        return false
    end
    local done = GENZ_ScrappyWear.maintain(self.character, self.animal, self.mode)
    if done and not isClient() and not isServer() then
        self:continueMaintaining()
    end
    return done
end

function Action:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    local level = self.character:getPerkLevel(Perks[perkOf(self.mode)])
    return math.max(1, S.opt("CycleTime") - level * S.opt("CycleTimePerLevel"))
end

function Action:new(character, animal, mode)
    local o = ISBaseTimedAction.new(self, character)
    o.animal = animal
    o.mode = mode
    o.maxTime = o:getDuration()
    o.caloriesModifier = 4
    return o
end
