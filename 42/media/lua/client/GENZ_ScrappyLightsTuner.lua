-- Scrappy lights tuner, DEBUG ONLY (card #246, skill pz-ajuste-ao-vivo): a small native window, opened and
-- closed by the chat command /luzes, that edits the front lights and the alert colours of
-- GENZ_ScrappyLightsClient live (through S.lightsDebug). Type the values, press Aplicar.
--   Copiar bloco  -> the numbers, as they go in the .lua, in the chat and in console.txt
--   Voltar ao arquivo -> the numbers the game started with
-- Nothing is saved: reopening the game goes back to the file. Leaves the mod once the numbers are in the
-- file (skill pz-ajuste-ao-vivo, item 9).
if not isDebugEnabled() or isServer() then return end
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local COMMAND = "/luzes"
local TAG = "[GENZ_ScrappyLightsTuner] "
local ROW = 22
local LABEL_W = 150
local ENTRY_W = 150
local PAD = 10
local ALERT_NAMES = { [0] = "verde", [1] = "ambar", [2] = "vermelho" }

-- A line in the chat, only for this player (recipe of GENZ_EventsClient.chatLine), and in console.txt.
local function chatLine(text, isError)
    print(TAG .. text)
    if not (ISChat and ISChat.instance and ISChat.instance.chatText) then return end
    local line = (isError and "<RGB:1,0.35,0.25>" or "<RGB:0.55,1,0.35>") .. TAG .. text
    ISChat.addLineInChat({
        getText = function() return line end,
        getTextWithPrefix = function() return line end,
        isServerAlert = function() return false end,
        isShowAuthor = function() return false end,
        getAuthor = function() return "" end,
        setShouldAttractZombies = function() return false end,
        setOverHeadSpeech = function() return false end,
    }, 0)
end

-- %.3f without trailing zeros (the /caixa proved %.Nf in Kahlua; %g is not relied on)
local function fmt(n)
    local s = string.format("%.3f", n):gsub("0+$", ""):gsub("%.$", "")
    return s
end

local function numberIn(low, high)
    return function(text)
        local n = tonumber(text)
        if not n then return nil, "nao e' numero" end
        if n < low or n > high then return nil, "fora de " .. fmt(low) .. " a " .. fmt(high) end
        return n
    end
end

local function wholeIn(low, high)
    local check = numberIn(low, high)
    return function(text)
        local n, err = check(text)
        if not n then return nil, err end
        if n ~= math.floor(n) then return nil, "tem que ser inteiro (o jogo so' aceita raio inteiro)" end
        return n
    end
end

-- "r g b", each 0..1
local function parseColour(text)
    local parts = {}
    for word in string.gmatch(text, "%S+") do parts[#parts + 1] = tonumber(word) end
    if #parts ~= 3 then return nil, "escreva 3 numeros: r g b" end
    for _, v in ipairs(parts) do
        if not v or v < 0 or v > 1 then return nil, "cada cor vai de 0 a 1" end
    end
    return parts
end

local function parseForced(text)
    if text == "" or text == "-" then return false end
    local n = tonumber(text)
    if n ~= 0 and n ~= 1 and n ~= 2 then return nil, "use 0, 1, 2 ou - (zumbis de verdade)" end
    return n
end

-- One row per value: label, show() -> text, parse(text) -> value | nil, error, set(value).
local function buildFields(debug)
    local fields = {}
    local lightNames = { "cabeca", "frente" }
    for i, spec in ipairs(debug.front) do
        local name = lightNames[i] or ("luz " .. i)
        local function add(key, label, parse)
            fields[#fields + 1] = {
                label = name .. ": " .. label,
                show = function() return fmt(spec[key]) end,
                parse = parse,
                set = function(v) spec[key] = v end,
            }
        end
        add("ahead", "a frente (quadr.)", numberIn(-5, 10))
        add("side", "lado (quadr., +dir)", numberIn(-5, 5))
        add("radius", "raio (quadr.)", wholeIn(1, 10))
        add("strength", "forca", numberIn(0, 3))
    end
    for level = 0, 2 do
        local tint = debug.alert[level].tint
        fields[#fields + 1] = {
            label = "cor " .. ALERT_NAMES[level] .. " (r g b)",
            show = function() return fmt(tint[1]) .. " " .. fmt(tint[2]) .. " " .. fmt(tint[3]) end,
            parse = parseColour,
            set = function(v) tint[1], tint[2], tint[3] = v[1], v[2], v[3] end,
        }
    end
    fields[#fields + 1] = {
        label = "forcar alerta (0/1/2, -)",
        show = function() return debug.forcedAlert and tostring(debug.forcedAlert) or "-" end,
        parse = parseForced,
        set = function(v) debug.forcedAlert = v or nil end,
    }
    return fields
end

local function snapshot(debug)
    local copy = { front = {}, tints = {} }
    for i, spec in ipairs(debug.front) do
        copy.front[i] = { ahead = spec.ahead, side = spec.side, radius = spec.radius, strength = spec.strength }
    end
    for level = 0, 2 do
        local t = debug.alert[level].tint
        copy.tints[level] = { t[1], t[2], t[3] }
    end
    return copy
end

local fileValues = nil             -- the numbers before the first change of this session

GENZ_ScrappyLightsTuner = ISCollapsableWindow:derive("GENZ_ScrappyLightsTuner")

function GENZ_ScrappyLightsTuner:new(debug)
    local fields = buildFields(debug)
    local width = PAD * 3 + LABEL_W + ENTRY_W
    local height = 20 + PAD + #fields * ROW + PAD + 2 * (ROW + 4) + PAD
    local x = getCore():getScreenWidth() - width - 20     -- top right corner: never over the dog
    local o = ISCollapsableWindow:new(x, 80, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Luzes do Scrappy (nao salva)"
    o.resizable = false
    o.debug = debug
    o.fields = fields
    return o
end

function GENZ_ScrappyLightsTuner:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + PAD
    local entryX = PAD * 2 + LABEL_W
    for i, field in ipairs(self.fields) do
        local entry = ISTextEntryBox:new(field.show(), entryX, top + (i - 1) * ROW, ENTRY_W, ROW - 3)
        entry:initialise()
        entry:instantiate()
        self:addChild(entry)
        field.entry = entry
    end
    local buttonsY = top + #self.fields * ROW + PAD
    local half = (self.width - PAD * 3) / 2
    self:makeButton(PAD, buttonsY, self.width - PAD * 2, "Aplicar", self.onApply)
    self:makeButton(PAD, buttonsY + ROW + 4, half, "Copiar bloco", self.onCopy)
    self:makeButton(PAD * 2 + half, buttonsY + ROW + 4, half, "Voltar ao arquivo", self.onRestore)
end

function GENZ_ScrappyLightsTuner:makeButton(x, y, w, label, onClick)
    local button = ISButton:new(x, y, w, ROW, label, self, onClick)
    button:initialise()
    button:instantiate()
    button.font = UIFont.Small
    self:addChild(button)
end

function GENZ_ScrappyLightsTuner:prerender()
    ISCollapsableWindow.prerender(self)
    local top = self:titleBarHeight() + PAD
    for i, field in ipairs(self.fields) do
        local bad = field == self.badField
        self:drawText(field.label, PAD, top + (i - 1) * ROW + 2, 1, bad and 0.35 or 1, bad and 0.25 or 1, 1,
            UIFont.Small)
    end
end

function GENZ_ScrappyLightsTuner:refreshEntries()
    for _, field in ipairs(self.fields) do field.entry:setText(field.show()) end
end

-- All or nothing: one bad field stops the rest and is named in the chat (and painted red).
function GENZ_ScrappyLightsTuner:onApply()
    local values = {}
    for i, field in ipairs(self.fields) do
        local value, err = field.parse(field.entry:getText())
        if value == nil then
            self.badField = field
            chatLine(field.label .. ": " .. err .. " -- nada aplicado", true)
            return
        end
        values[i] = value
    end
    self.badField = nil
    fileValues = fileValues or snapshot(self.debug)
    for i, field in ipairs(self.fields) do field.set(values[i]) end
    self.debug.refresh()
    self:refreshEntries()
    chatLine("aplicado")
end

function GENZ_ScrappyLightsTuner:onCopy()
    for _, spec in ipairs(self.debug.front) do
        chatLine("{ ahead = " .. fmt(spec.ahead) .. ", side = " .. fmt(spec.side) .. ", radius = "
            .. fmt(spec.radius) .. ", strength = " .. fmt(spec.strength) .. " },")
    end
    for level = 0, 2 do
        local t = self.debug.alert[level].tint
        chatLine(string.format("[%d] tint = { %.2f, %.2f, %.2f },  -- %s", level, t[1], t[2], t[3],
            ALERT_NAMES[level]))
    end
end

function GENZ_ScrappyLightsTuner:onRestore()
    if not fileValues then
        chatLine("nada mudou ainda: ja' esta' no arquivo")
        return
    end
    for i, spec in ipairs(self.debug.front) do
        local saved = fileValues.front[i]
        spec.ahead, spec.side, spec.radius, spec.strength = saved.ahead, saved.side, saved.radius, saved.strength
    end
    for level = 0, 2 do
        local t, saved = self.debug.alert[level].tint, fileValues.tints[level]
        t[1], t[2], t[3] = saved[1], saved[2], saved[3]
    end
    self.debug.forcedAlert = nil
    self.debug.refresh()
    self.badField = nil
    self:refreshEntries()
    chatLine("voltou ao arquivo")
end

function GENZ_ScrappyLightsTuner:close()
    self:removeFromUIManager()
    GENZ_ScrappyLightsTuner.instance = nil
end

function GENZ_ScrappyLightsTuner.toggle()
    if GENZ_ScrappyLightsTuner.instance then
        GENZ_ScrappyLightsTuner.instance:close()
        return
    end
    local debug = S.lightsDebug
    if not debug then
        chatLine("GENZ_ScrappyLightsClient nao carregou (S.lightsDebug ausente)", true)
        return
    end
    local window = GENZ_ScrappyLightsTuner:new(debug)
    window:initialise()
    window:addToUIManager()
    GENZ_ScrappyLightsTuner.instance = window
end

-- Same chat wrap as the old /caixa (skill pz-ajuste-ao-vivo, "Comando de chat").
local function wrapChat()
    if not (ISChat and ISChat.onCommandEntered) or ISChat._genzScrappyLightsTuner then return end
    ISChat._genzScrappyLightsTuner = true
    local original = ISChat.onCommandEntered
    ISChat.onCommandEntered = function(self)
        local chat = ISChat.instance
        local entry = chat and chat.textEntry
        local text = entry and entry:getText() or ""
        if string.lower(text:match("^%S+") or "") ~= COMMAND then return original(self) end
        chat:unfocus()
        entry:setText("")
        GENZ_ScrappyLightsTuner.toggle()
    end
    -- the text box keeps the function it had when the chat was built (ISChat.lua): point it at ours
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

wrapChat()
Events.OnGameStart.Add(wrapChat)
