-- Scrappy lights, client side (card #246).
--   EYES AND BACK LAMPS: switched on, it wears Scrappy.png -- lime visor line and 4 amber back lamps,
--   both glowing through genz_scrappy_neon (the lamps throw no light on the world); shut down, it wears
--   ScrappyOff.png -- red visor line (much weaker glow) and dark lamps.
--   FRONT LIGHT: switched on, a dim lime light starts on its head and reaches ahead where it looks. The
--   engine only builds real cone lights (TorchInfo) for players and car lamps (LightingJNI, 42.21), so
--   the "cone" is two point lights (IsoLightSource, as in GENZ_MascoteGlow): one on the head's square,
--   one further ahead. Lights snap to squares and exist only on clients (a dedicated server has none).
-- Purely VISUAL and LOCAL: AnimalVisual's skin name is written with the animal (AnimalVisual.save,
-- decompiled 42.21), so the server never changes it -- every client paints what it sees from the
-- scrappyOff flag the server already transmits.
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local TEXTURE_ON = "Scrappy"       -- media/textures/Body/<name>.png (ModelInstanceTextureCreator, 42.21)
local TEXTURE_OFF = "ScrappyOff"
local SKIN_EVERY_TICKS = 30        -- about half a second: a shutdown shows almost at once
local LIGHT_EVERY_TICKS = 5        -- the light keeps up with a running dog
-- ahead = squares from the body centre; radius in squares; colour 0..1 (above 1 bleaches to white,
-- GENZ_MascoteGlow). The visor line is already at ~85% of white (the shader cannot go further), so the
-- head light is what makes the eyes read strong: it lights the dog's own face and the ground lime.
local FRONT_LIGHTS = {
    { ahead = 0.6, radius = 2, r = 0.30, g = 0.90, b = 0.10 },   -- the head, where the eyes are
    { ahead = 2.5, radius = 2, r = 0.15, g = 0.45, b = 0.04 },   -- fainter, where it looks
}

local lightsByDog = {}             -- [animal] = { { src, x, y, z }, ... } one per FRONT_LIGHTS entry

local function wantedTexture(animal)
    if S.isOff(animal) then return TEXTURE_OFF end
    return TEXTURE_ON
end

local function syncSkin(animal)
    local visual = animal:getAnimalVisual()
    local wanted = wantedTexture(animal)
    if visual:getSkinTexture() == wanted then return end
    visual:setSkinTextureName(wanted)
    -- the pair the engine itself calls after a skin change (IsoAnimal.ensureCorrectSkin, 42.21)
    animal:resetModel()
    animal:resetModelNextFrame()
end

local function removeLights(cell, animal)
    for _, light in ipairs(lightsByDog[animal]) do
        cell:removeLamppost(light.src)
    end
    lightsByDog[animal] = nil
end

-- A light is recreated only when its square changes: one per square, never one per frame (a new
-- IsoLightSource every frame leaks, pz-b42-modding 04 (c)).
local function placeLights(cell, animal)
    local fx, fy = animal:getForwardDirectionX(), animal:getForwardDirectionY()
    local z = math.floor(animal:getZ())
    local lights = lightsByDog[animal] or {}
    for i, spec in ipairs(FRONT_LIGHTS) do
        local x = math.floor(animal:getX() + fx * spec.ahead)
        local y = math.floor(animal:getY() + fy * spec.ahead)
        local light = lights[i]
        if not light or light.x ~= x or light.y ~= y or light.z ~= z then
            if light then cell:removeLamppost(light.src) end
            local src = IsoLightSource.new(x, y, z, spec.r, spec.g, spec.b, spec.radius)
            cell:addLamppost(src)
            lights[i] = { src = src, x = x, y = y, z = z }
        end
    end
    lightsByDog[animal] = lights
end

local function isLiveScrappy(animal)
    return not animal:isDead() and CompanionDogs.isDog(animal) and S.isScrappy(animal)
end

local ticks = 0
Events.OnTick.Add(function()
    ticks = ticks + 1
    local doSkin = ticks % SKIN_EVERY_TICKS == 0
    local doLights = ticks % LIGHT_EVERY_TICKS == 0
    if not doSkin and not doLights then return end
    local cell = getCell()
    if not cell then return end
    local lit = {}
    local animals = cell:getAnimals()
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        if isLiveScrappy(animal) then
            if doSkin then syncSkin(animal) end
            if doLights and not S.isOff(animal) then
                placeLights(cell, animal)
                lit[animal] = true
            end
        end
    end
    if not doLights then return end
    -- shut down, dead, picked up or out of the cell: its lights go
    local gone = {}
    for animal in pairs(lightsByDog) do
        if not lit[animal] then gone[#gone + 1] = animal end
    end
    for _, animal in ipairs(gone) do
        removeLights(cell, animal)
    end
end)
