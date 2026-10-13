-- Scrappy cargo-case tuner, DEBUG ONLY (card #246): edit the saddlebags_c attachment of Scrappy_Body from
-- the chat, live, on the real dog in game (the attachment editor did not show the case at game scale).
--   /caixa                    show the current numbers
--   /caixa escala 2           scale
--   /caixa offset 0 0.05 0    offset (absolute)
--   /caixa mover 0 0.01 0     offset (relative)
--   /caixa girar 0 -90 90     rotate (degrees, absolute)
-- Each change prints the attachment block ready to paste into models_scrappy.txt. Nothing is saved: the
-- script goes back to the file on the next start. Same chat wrap as GENZ_MarketMockKeys (GENZ_Equipamentos).
if not isDebugEnabled() then return end

local MODEL = "Base.Scrappy_Body"
local ATTACHMENT = "saddlebags_c"

local function say(text)
    local player = getPlayer()
    if player then player:Say(text) end
    print("[GENZ_ScrappyCargoTuner] " .. text)
end

local function attachment()
    local script = getScriptManager():getModelScript(MODEL)
    if not script then
        say("model script " .. MODEL .. " not found")
        return nil
    end
    local attach = script:getAttachmentById(ATTACHMENT)
    if not attach then say("attachment " .. ATTACHMENT .. " not found") end
    return attach
end

local function block(attach)
    local o, r = attach:getOffset(), attach:getRotate()
    return string.format("offset = %.4f %.4f %.4f, rotate = %.1f %.1f %.1f, scale = %.3f",
        o:x(), o:y(), o:z(), r:x(), r:y(), r:z(), attach:getScale())
end

-- Hang the case again on every Scrappy in the cell: setAttachedItem rebuilds the attached models
-- (IsoGameCharacter.resetEquippedHandsModels, 42.21), so the new numbers show at once.
local function refresh()
    local animals = getCell():getAnimals()
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        local item = animal:getAttachedItem(ATTACHMENT)
        if item then animal:setAttachedItem(ATTACHMENT, item) end
    end
end

local function numbers(words, first, count)
    local out = {}
    for i = first, first + count - 1 do
        local n = tonumber(words[i])
        if not n then return nil end
        out[#out + 1] = n
    end
    return out
end

local function run(words)
    local attach = attachment()
    if not attach then return end
    local verb = words[2]
    if verb == "escala" then
        local n = numbers(words, 3, 1)
        if not n then return say("uso: /caixa escala 2") end
        attach:setScale(n[1])
    elseif verb == "offset" or verb == "mover" then
        local n = numbers(words, 3, 3)
        if not n then return say("uso: /caixa " .. verb .. " x y z") end
        local o = attach:getOffset()
        if verb == "mover" then n = { o:x() + n[1], o:y() + n[2], o:z() + n[3] } end
        o:set(n[1], n[2], n[3])
    elseif verb == "girar" then
        local n = numbers(words, 3, 3)
        if not n then return say("uso: /caixa girar x y z") end
        attach:getRotate():set(n[1], n[2], n[3])
    elseif verb ~= nil then
        return say("comandos: escala, offset, mover, girar")
    end
    refresh()
    say(block(attach))
end

local function wordsOf(text)
    local words = {}
    for word in string.gmatch(tostring(text or ""), "%S+") do words[#words + 1] = word end
    return words
end

local function wrapChat()
    if not (ISChat and ISChat.onCommandEntered) or ISChat._genzScrappyCargoTuner then return end
    ISChat._genzScrappyCargoTuner = true
    local original = ISChat.onCommandEntered
    ISChat.onCommandEntered = function(self)
        local chat = ISChat.instance
        local entry = chat and chat.textEntry
        local words = wordsOf(entry and entry:getText())
        if string.lower(words[1] or "") ~= "/caixa" then return original(self) end
        chat:unfocus()
        entry:setText("")
        run(words)
    end
    -- the text box keeps the function it had when the chat was built (ISChat.lua): point it at ours
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

wrapChat()
Events.OnGameStart.Add(wrapChat)
