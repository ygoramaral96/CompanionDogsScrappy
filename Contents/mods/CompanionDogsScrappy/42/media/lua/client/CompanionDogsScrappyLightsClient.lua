-- Scrappy lights, client side.
--   SKIN (visor line + 4 back lamps, glowing through scrappy_neon; the lamps throw no light on the
--   world): Scrappy<alert><worn>.png --
--     <alert> = "" (lime visor) / "Amber" / "Red" by the zombies near it (ALERT, below);
--     <worn>  = "" (amber back lamps lit) / "Worn" (lamps dark) when it no longer works -- S.isWorking,
--               the same test the loot and the XP aura use, so the lamps go dark exactly when they stop;
--   shut down: ScrappyOff.png -- red visor line (much weaker glow), lamps dark, no alert.
--   FRONT LIGHT: switched on, a light in the alert colour sits on its head and a BEAM reaches ahead where
--   it looks. The engine only builds real cone lights (TorchInfo) for players holding a lamp and for car
--   lamps (LightingJNI, 42.21; the list is Java-only), so the beam is a row of point lights (IsoLightSource,
--   as in a mascot glow) whose radius grows with the distance -- a flashlight-like cone that still
--   spills a little sideways and backwards around each point. Lights snap to squares and exist only on
--   clients (a dedicated server has none).
--   WEAR AND CHARGE: below the sandbox WorkingThreshold (S.degradedBelow -- the condition under which
--   the loot and the XP aura stop), the front light fades with the condition AND with the battery
--   charge, following the lower of the two, in LIGHT_STEPS steps; it goes out at 0.
--   ALERT: zombies within CompanionDogs' own attack radius (CD.ZOMBIE_ATTACK_RADIUS, read on use), same
--   floor: from sandbox ThreatAmber it turns amber, from ThreatRed red. A higher alert shows at once; a
--   lower one only after ALERT_HOLD_MS, so a zombie stepping in and out of range does not flicker the
--   skin (every skin change rebuilds the model).
-- Purely VISUAL and LOCAL: AnimalVisual's skin name is written with the animal (AnimalVisual.save,
-- decompiled 42.21), so the server never changes it -- every client paints what it sees from the
-- data the server already transmits.
require "CompanionDogsScrappyShared"
local S = CompanionDogsScrappy

-- media/textures/Body/<name>.png (ModelInstanceTextureCreator, 42.21)
local TEXTURE_BASE = "Scrappy"
local TEXTURE_WORN = "Worn"
local TEXTURE_OFF = "ScrappyOff"
local SKIN_EVERY_TICKS = 30        -- about half a second: a shutdown or an alert shows almost at once
local LIGHT_EVERY_TICKS = 5        -- the light keeps up with a running dog
local ALERT_HOLD_MS = 2000
-- alert level -> skin infix and front-light colour (0..1; above 1 bleaches to white)
local ALERT = {
    [0] = { skin = "", tint = { 0.33, 1.00, 0.11 } },        -- calm: lime
    [1] = { skin = "Amber", tint = { 1.00, 0.55, 0.05 } },   -- some zombies near
    [2] = { skin = "Red", tint = { 1.00, 0.10, 0.06 } },     -- many zombies near
}
-- ahead = squares from the body centre along where it looks; side = squares to its right (negative: left);
-- radius in whole squares; strength scales the alert colour. Lights snap to squares (IsoLightSource takes
-- ints), so ahead/side below a square only matter where they cross one. The visor
-- line is already at ~85% of white (the shader cannot go further), so the light is what makes the eyes
-- read strong. Tested in game: a radius-2 head light painted the whole dog green -- the head light stays
-- small and faint, the beam ahead carries the colour.
-- the head, where the eyes are; ahead 1.3 found in game with /scrappy_lights
local HEAD_LIGHT = { ahead = 1.3, side = 0, radius = 1, strength = 0.45 }
-- the beam, built by rule (frontLights): count lights from `start` squares ahead, `spacing` apart; the
-- radius starts at `radius` and grows by `radiusGrow` per light; the strength goes from `strengthNear` to
-- `strengthFar`. 0 lights = head only. Tuned in game with /scrappy_lights.
local BEAM = {
    count = 3, start = 1.5, spacing = 1.5,
    radius = 1, radiusGrow = 1,
    strengthNear = 0.7, strengthFar = 0.6,
}
local LIGHT_STEPS = 10             -- the fade changes in 10% steps: a light is recreated only per step

local lightsByDog = {}             -- [animal] = { { src, x, y, z, level, alert }, ... } per frontLights()
local alertByDog = {}              -- [animal] = { level, since } (since = last time this level was seen)

-- Door for the debug tuner (CompanionDogsScrappyLightsTuner, debug only): it edits HEAD_LIGHT, BEAM and the ALERT
-- tints in place, may force an alert level, and calls refresh() so every light is rebuilt with the new
-- numbers. Nobody else writes here; forcedAlert stays nil outside a debug session.
S.lightsDebug = { head = HEAD_LIGHT, beam = BEAM, alert = ALERT, forcedAlert = nil }

-- The head light, then the beam's lights, near to far.
local function frontLights()
    local specs = { HEAD_LIGHT }
    for i = 1, BEAM.count do
        local share = BEAM.count > 1 and (i - 1) / (BEAM.count - 1) or 0
        specs[#specs + 1] = {
            ahead = BEAM.start + (i - 1) * BEAM.spacing,
            side = 0,
            radius = BEAM.radius + (i - 1) * BEAM.radiusGrow,
            strength = BEAM.strengthNear + (BEAM.strengthFar - BEAM.strengthNear) * share,
        }
    end
    return specs
end

local function zombiesNear(animal)
    local radius = CompanionDogs.ZOMBIE_ATTACK_RADIUS
    local x, y, z = animal:getX(), animal:getY(), math.floor(animal:getZ())
    local zombies = getCell():getZombieList()
    local count = 0
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if not zombie:isDead() and math.floor(zombie:getZ()) == z then
            local dx, dy = zombie:getX() - x, zombie:getY() - y
            if dx * dx + dy * dy <= radius * radius then count = count + 1 end
        end
    end
    return count
end

local function rawAlert(animal)
    local count = zombiesNear(animal)
    if count >= S.opt("ThreatRed") then return 2 end
    if count >= S.opt("ThreatAmber") then return 1 end
    return 0
end

-- Up at once, down only after ALERT_HOLD_MS without the higher level.
local function updateAlert(animal)
    local now = getTimestampMs()
    local raw = S.lightsDebug.forcedAlert or rawAlert(animal)
    local state = alertByDog[animal]
    if not state or raw >= state.level then
        alertByDog[animal] = { level = raw, since = now }
    elseif now - state.since >= ALERT_HOLD_MS then
        alertByDog[animal] = { level = raw, since = now }
    end
    return alertByDog[animal].level
end

local function alertOf(animal)
    local state = alertByDog[animal]
    return state and state.level or 0
end

local function wantedTexture(animal)
    if S.isOff(animal) then return TEXTURE_OFF end
    local worn = S.isWorking(animal) and "" or TEXTURE_WORN
    return TEXTURE_BASE .. ALERT[alertOf(animal)].skin .. worn
end

local function syncSkin(animal)
    local visual = animal:getAnimalVisual()
    local wanted = wantedTexture(animal)
    if visual:getSkinTexture() == wanted then return end
    visual:setSkinTextureName(wanted)
    -- the pair the engine itself calls after a skin change (IsoAnimal.ensureCorrectSkin, 42.21)
    animal:resetModel()
    animal:resetModelNextFrame()
    -- the reset builds a new body but keeps the hung models (the cargo case) bound to the old one
    -- (ModelManager.Reset skips attachedModels, 42.21): rebuild them on the new body. The engine runs the
    -- body reset before the hung-model reset in the same frame (ModelManager.update).
    animal:resetEquippedHandsModels()
end

local function removeLights(cell, animal)
    for _, light in ipairs(lightsByDog[animal]) do
        cell:removeLamppost(light.src)
    end
    lightsByDog[animal] = nil
end

-- Drop every light; the next light pass rebuilds them from HEAD_LIGHT/BEAM/ALERT as they are now.
function S.lightsDebug.refresh()
    local cell = getCell()
    if not cell then return end
    local dogs = {}
    for animal in pairs(lightsByDog) do dogs[#dogs + 1] = animal end
    for _, animal in ipairs(dogs) do removeLights(cell, animal) end
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

-- A light is recreated only when its square, its level or the alert changes, never every frame (a new
-- IsoLightSource every frame leaks).
local function placeLights(cell, animal, level)
    local fx, fy = animal:getForwardDirectionX(), animal:getForwardDirectionY()
    local z = math.floor(animal:getZ())
    local alert = alertOf(animal)
    local tint = ALERT[alert].tint
    local lights = lightsByDog[animal] or {}
    local specs = frontLights()
    for i, spec in ipairs(specs) do
        -- right of the facing (fx, fy) is (-fy, fx) in PZ's y-down world
        local x = math.floor(animal:getX() + fx * spec.ahead - fy * spec.side)
        local y = math.floor(animal:getY() + fy * spec.ahead + fx * spec.side)
        local light = lights[i]
        if not light or light.x ~= x or light.y ~= y or light.z ~= z or light.level ~= level
                or light.alert ~= alert then
            if light then cell:removeLamppost(light.src) end
            local k = spec.strength * level
            local src = IsoLightSource.new(x, y, z, tint[1] * k, tint[2] * k, tint[3] * k, spec.radius)
            cell:addLamppost(src)
            lights[i] = { src = src, x = x, y = y, z = z, level = level, alert = alert }
        end
    end
    -- the beam got shorter: its far lights go
    for i = #lights, #specs + 1, -1 do
        cell:removeLamppost(lights[i].src)
        lights[i] = nil
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
    local lit, seen = {}, {}
    local animals = cell:getAnimals()
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        if isLiveScrappy(animal) then
            seen[animal] = true
            if doSkin then
                updateAlert(animal)
                syncSkin(animal)
            end
            local level = doLights and not S.isOff(animal) and lightLevel(animal) or 0
            if level > 0 then
                placeLights(cell, animal, level)
                lit[animal] = true
            end
        end
    end
    if doSkin then
        local forgotten = {}
        for animal in pairs(alertByDog) do
            if not seen[animal] then forgotten[#forgotten + 1] = animal end
        end
        for _, animal in ipairs(forgotten) do alertByDog[animal] = nil end
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
