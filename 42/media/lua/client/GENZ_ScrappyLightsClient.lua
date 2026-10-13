-- Scrappy lights, client side (card #246).
--   EYES AND BACK LAMPS: switched on, it wears Scrappy.png -- lime visor line and 4 amber back lamps,
--   both glowing through genz_scrappy_neon (the lamps throw no light on the world); on but no longer
--   working (worn: no loot, no aura) it wears ScrappyWorn.png -- lime visor, lamps dark; shut down, it
--   wears ScrappyOff.png -- red visor line (much weaker glow) and dark lamps.
--   FRONT LIGHT: switched on, a dim lime light starts on its head and reaches ahead where it looks. The
--   engine only builds real cone lights (TorchInfo) for players and car lamps (LightingJNI, 42.21), so
--   the "cone" is two point lights (IsoLightSource, as in GENZ_MascoteGlow): one on the head's square,
--   one further ahead. Lights snap to squares and exist only on clients (a dedicated server has none).
--   WEAR AND CHARGE: below the sandbox WorkingThreshold (S.degradedBelow -- the condition under which
--   the loot and the XP aura stop), the front light fades with the condition AND with the battery
--   charge, following the lower of the two, in LIGHT_STEPS steps; it goes out at 0 (Ygor, 13/10).
-- Purely VISUAL and LOCAL: AnimalVisual's skin name is written with the animal (AnimalVisual.save,
-- decompiled 42.21), so the server never changes it -- every client paints what it sees from the
-- scrappyOff flag the server already transmits.
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

-- media/textures/Body/<name>.png (ModelInstanceTextureCreator, 42.21)
local TEXTURE_ON = "Scrappy"       -- working: lime visor, amber back lamps
local TEXTURE_WORN = "ScrappyWorn" -- on but not working (no loot, no aura): lime visor, lamps dark
local TEXTURE_OFF = "ScrappyOff"   -- shut down: red visor, lamps dark
local SKIN_EVERY_TICKS = 30        -- about half a second: a shutdown shows almost at once
local LIGHT_EVERY_TICKS = 5        -- the light keeps up with a running dog
-- ahead = squares from the body centre; radius in squares; colour 0..1 (above 1 bleaches to white,
-- GENZ_MascoteGlow). The visor line is already at ~85% of white (the shader cannot go further), so the
-- light is what makes the eyes read strong. Tested 13/10: a radius-2 head light painted the whole dog
-- green -- the head light stays small and faint, the beam ahead carries the colour.
local FRONT_LIGHTS = {
    { ahead = 0.6, radius = 1, r = 0.15, g = 0.45, b = 0.05 },   -- the head, where the eyes are
    { ahead = 2.5, radius = 2, r = 0.25, g = 0.75, b = 0.08 },   -- where it looks
}
local LIGHT_STEPS = 10             -- the fade changes in 10% steps: a light is recreated only per step

local lightsByDog = {}             -- [animal] = { { src, x, y, z }, ... } one per FRONT_LIGHTS entry

-- S.isWorking is the same test the loot and the XP aura use: the lamps go dark exactly when they stop.
local function wantedTexture(animal)
    if S.isOff(animal) then return TEXTURE_OFF end
    if not S.isWorking(animal) then return TEXTURE_WORN end
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

-- 1 at or above the threshold; below it, the share of the threshold left.
local function fade(value, threshold)
    if threshold <= 0 or value >= threshold then return 1 end
    return value / threshold
end

-- The weaker of condition and charge, rounded to LIGHT_STEPS; 0 when broken or empty.
local function lightLevel(animal)
    local threshold = S.degradedBelow()
    local level = math.min(fade(S.condition(animal), threshold), fade(S.chargeFraction(animal), threshold))
    return math.floor(level * LIGHT_STEPS + 0.5) / LIGHT_STEPS
end

-- A light is recreated only when its square or its level changes, never every frame (a new
-- IsoLightSource every frame leaks, pz-b42-modding 04 (c)).
local function placeLights(cell, animal, level)
    local fx, fy = animal:getForwardDirectionX(), animal:getForwardDirectionY()
    local z = math.floor(animal:getZ())
    local lights = lightsByDog[animal] or {}
    for i, spec in ipairs(FRONT_LIGHTS) do
        local x = math.floor(animal:getX() + fx * spec.ahead)
        local y = math.floor(animal:getY() + fy * spec.ahead)
        local light = lights[i]
        if not light or light.x ~= x or light.y ~= y or light.z ~= z or light.level ~= level then
            if light then cell:removeLamppost(light.src) end
            local src = IsoLightSource.new(x, y, z, spec.r * level, spec.g * level, spec.b * level, spec.radius)
            cell:addLamppost(src)
            lights[i] = { src = src, x = x, y = y, z = z, level = level }
        end
    end
    lightsByDog[animal] = lights
end

-- SONDA card #246 (remove after the reading): what this client uses for the light, printed on change.
local probeLast = {}
local function probeLight(animal)
    local d = CompanionDogs.data(animal)
    local line = string.format("off=%s scrappyOff=%s cond=%s charge=%s threshold=%s level=%s",
        tostring(S.isOff(animal)), tostring(d.scrappyOff), tostring(d.scrappyCondition),
        tostring(S.chargeFraction(animal)), tostring(S.degradedBelow()), tostring(lightLevel(animal)))
    if probeLast[animal] == line then return end
    probeLast[animal] = line
    print("[GENZ_card246] light " .. line)
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
            if doSkin then probeLight(animal) end
            local level = doLights and not S.isOff(animal) and lightLevel(animal) or 0
            if level > 0 then
                placeLights(cell, animal, level)
                lit[animal] = true
            end
        end
    end
    if not doLights then return end
    -- shut down, broken, dead, picked up or out of the cell: its lights go
    local gone = {}
    for animal in pairs(lightsByDog) do
        if not lit[animal] then gone[#gone + 1] = animal end
    end
    for _, animal in ipairs(gone) do
        removeLights(cell, animal)
    end
end)
