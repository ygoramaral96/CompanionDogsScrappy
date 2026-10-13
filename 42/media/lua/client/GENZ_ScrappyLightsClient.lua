-- Scrappy lights, client side (card #246): switched on, it wears Scrappy.png, whose lime eyes and flank
-- screen glow through genz_scrappy_neon; shut down, it wears ScrappyOff.png (red screen, dark eyes, no
-- lime), so the same shader lights nothing.
-- Purely VISUAL and LOCAL: AnimalVisual's skin name is written with the animal (AnimalVisual.save,
-- decompiled 42.21), so the server never changes it -- every client paints what it sees from the
-- scrappyOff flag the server already transmits.
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local TEXTURE_ON = "Scrappy"       -- media/textures/Body/<name>.png (ModelInstanceTextureCreator, 42.21)
local TEXTURE_OFF = "ScrappyOff"
local CHECK_EVERY_TICKS = 30       -- about half a second: a shutdown shows almost at once

local function wantedTexture(animal)
    if S.isOff(animal) then return TEXTURE_OFF end
    return TEXTURE_ON
end

local function syncLights(animal)
    local visual = animal:getAnimalVisual()
    local wanted = wantedTexture(animal)
    if visual:getSkinTexture() == wanted then return end
    visual:setSkinTextureName(wanted)
    -- the pair the engine itself calls after a skin change (IsoAnimal.ensureCorrectSkin, 42.21)
    animal:resetModel()
    animal:resetModelNextFrame()
end

local ticks = 0
Events.OnTick.Add(function()
    ticks = ticks + 1
    if ticks < CHECK_EVERY_TICKS then return end
    ticks = 0
    local cell = getCell()
    if not cell then return end
    local animals = cell:getAnimals()
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        if not animal:isDead() and CompanionDogs.isDog(animal) and S.isScrappy(animal) then
            syncLights(animal)
        end
    end
end)
