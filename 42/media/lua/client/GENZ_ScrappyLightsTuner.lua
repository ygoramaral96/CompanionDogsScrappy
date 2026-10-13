-- Scrappy lights tuner, DEBUG ONLY (card #246, skill pz-ajuste-ao-vivo): a small native window, opened and
-- closed by the chat command /scrappy_luzes, that edits the head light, the beam and the alert colours of
-- GENZ_ScrappyLightsClient live (through S.lightsDebug). Type the values, press Aplicar.
--   Copiar bloco  -> the numbers, as they go in the .lua, in the chat, in console.txt and on the clipboard
--   Voltar ao arquivo -> the numbers the game started with
-- Fields take only digits, "." and "-" (setOnlyNumbers) and turn red while out of range. Nothing is saved:
-- reopening the game goes back to the file. Stays in the mod for later tests (Ygor, 13/10).
if not isDebugEnabled() or isServer() then return end
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "GENZ_ScrappyShared"
local S = GENZ_Scrappy

local COMMAND = "/scrappy_luzes"
local TAG = "[GENZ_ScrappyLightsTuner] "
local ROW = 22
local LABEL_W = 180                -- the longest label, "cabeca: frente lado raio forca"
local ENTRY_W = 170                -- 4 small cells on the head row
local CELL_GAP = 4
local MAX_CHARS = 7
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

-- Each line to the chat (and console), and the whole block to the clipboard: Ctrl+V pastes it
-- (zombie.core.Clipboard, exposed to Lua -- LuaManager 42.21).
local function copyBlock(lines)
    for _, line in ipairs(lines) do chatLine(line) end
    Clipboard.setClipboard(table.concat(lines, "\n"))
    chatLine("copiado: Ctrl+V cola o bloco")
end

-- %.3f without trailing zeros (%.Nf is proven in Kahlua; %g is not relied on)
local function fmt(n)
    local s = string.format("%.3f", n):gsub("0+$", ""):gsub("%.$", "")
    return s
end

-- parse(text) -> value | nil, reason
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
        if n ~= math.floor(n) then return nil, "tem que ser inteiro" end
        return n
    end
end

-- "-" (or empty) = the real zombies; 0, 1, 2 = that alert level
local function parseForced(text)
    if text == "" or text == "-" then return false end
    local n = tonumber(text)
    if n ~= 0 and n ~= 1 and n ~= 2 then return nil, "use 0, 1, 2 ou - (zumbis de verdade)" end
    return n
end

-- A row = a label and one or more cells; a cell = show() -> text, parse(text), set(value).
local function cellOf(spec, key, parse)
    return {
        show = function() return fmt(spec[key]) end,
        parse = parse,
        set = function(v) spec[key] = v end,
    }
end

local function buildRows(debug)
    local head, beam = debug.head, debug.beam
    local rows = {
        { label = "cabeca: frente lado raio forca", cells = {
            cellOf(head, "ahead", numberIn(-5, 10)), cellOf(head, "side", numberIn(-5, 5)),
            cellOf(head, "radius", wholeIn(1, 10)), cellOf(head, "strength", numberIn(0, 3)) } },
        { label = "feixe: quantas luzes (0-6)", cells = { cellOf(beam, "count", wholeIn(0, 6)) } },
        { label = "feixe: inicio, espaco", cells = {
            cellOf(beam, "start", numberIn(0, 10)), cellOf(beam, "spacing", numberIn(0.5, 5)) } },
        { label = "feixe: raio, +raio/luz", cells = {
            cellOf(beam, "radius", wholeIn(1, 10)), cellOf(beam, "radiusGrow", wholeIn(0, 5)) } },
        { label = "feixe: forca perto, longe", cells = {
            cellOf(beam, "strengthNear", numberIn(0, 3)), cellOf(beam, "strengthFar", numberIn(0, 3)) } },
    }
    for level = 0, 2 do
        local tint = debug.alert[level].tint
        local cells = {}
        for c = 1, 3 do cells[c] = cellOf(tint, c, numberIn(0, 1)) end
        rows[#rows + 1] = { label = "cor " .. ALERT_NAMES[level] .. " (r g b)", cells = cells }
    end
    rows[#rows + 1] = { label = "forcar alerta (0/1/2, -)", cells = { {
        show = function() return debug.forcedAlert and tostring(debug.forcedAlert) or "-" end,
        parse = parseForced,
        set = function(v) debug.forcedAlert = v or nil end,
    } } }
    return rows
end

local function copyOf(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function putBack(target, saved)
    for k, v in pairs(saved) do target[k] = v end
end

local function snapshot(debug)
    local copy = { head = copyOf(debug.head), beam = copyOf(debug.beam), tints = {} }
    for level = 0, 2 do copy.tints[level] = copyOf(debug.alert[level].tint) end
    return copy
end

local fileValues = nil             -- the numbers before the first change of this session

GENZ_ScrappyLightsTuner = ISCollapsableWindow:derive("GENZ_ScrappyLightsTuner")

function GENZ_ScrappyLightsTuner:new(debug)
    local rows = buildRows(debug)
    local width = PAD * 3 + LABEL_W + ENTRY_W
    local height = 20 + PAD + #rows * ROW + PAD + 2 * (ROW + 4) + PAD
    local x = getCore():getScreenWidth() - width - 20     -- top right corner: never over the dog
    local o = ISCollapsableWindow:new(x, 80, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Luzes do Scrappy (nao salva)"
    o.resizable = false
    o.debug = debug
    o.rows = rows
    return o
end

-- Red label while any cell of the row is out of range, as the player types.
local function onCellChanged(row, entry)
    row.bad = false
    for _, cell in ipairs(row.cells) do
        if cell.parse(cell.entry:getText()) == nil then row.bad = true end
    end
end

function GENZ_ScrappyLightsTuner:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + PAD
    local entryX = PAD * 2 + LABEL_W
    for i, row in ipairs(self.rows) do
        local n = #row.cells
        local cellW = (ENTRY_W - CELL_GAP * (n - 1)) / n
        for c, cell in ipairs(row.cells) do
            local entry = ISTextEntryBox:new(cell.show(), entryX + (c - 1) * (cellW + CELL_GAP),
                top + (i - 1) * ROW, cellW, ROW - 3)
            entry:initialise()
            entry:instantiate()
            entry:setOnlyNumbers(true)          -- digits, "." and "-" only (Core keyboard filter, 42.21)
            entry:setMaxTextLength(MAX_CHARS)
            entry.target = row
            entry.onTextChangeFunction = onCellChanged
            self:addChild(entry)
            cell.entry = entry
        end
    end
    local buttonsY = top + #self.rows * ROW + PAD
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
    for i, row in ipairs(self.rows) do
        self:drawText(row.label, PAD, top + (i - 1) * ROW + 2, 1, row.bad and 0.35 or 1, row.bad and 0.25 or 1, 1,
            UIFont.Small)
    end
end

function GENZ_ScrappyLightsTuner:refreshEntries()
    for _, row in ipairs(self.rows) do
        row.bad = false
        for _, cell in ipairs(row.cells) do cell.entry:setText(cell.show()) end
    end
end

-- All or nothing: one bad cell stops the rest and is named in the chat (and its row painted red).
function GENZ_ScrappyLightsTuner:onApply()
    local values = {}
    for _, row in ipairs(self.rows) do
        for _, cell in ipairs(row.cells) do
            local value, err = cell.parse(cell.entry:getText())
            if value == nil then
                row.bad = true
                chatLine(row.label .. ": " .. err .. " -- nada aplicado", true)
                return
            end
            values[cell] = value
        end
    end
    fileValues = fileValues or snapshot(self.debug)
    for _, row in ipairs(self.rows) do
        for _, cell in ipairs(row.cells) do cell.set(values[cell]) end
    end
    self.debug.refresh()
    self:refreshEntries()
    chatLine("aplicado")
end

function GENZ_ScrappyLightsTuner:onCopy()
    local head, beam = self.debug.head, self.debug.beam
    local lines = {
        "local HEAD_LIGHT = { ahead = " .. fmt(head.ahead) .. ", side = " .. fmt(head.side)
            .. ", radius = " .. fmt(head.radius) .. ", strength = " .. fmt(head.strength) .. " }",
        "BEAM: count = " .. fmt(beam.count) .. ", start = " .. fmt(beam.start) .. ", spacing = "
            .. fmt(beam.spacing) .. ",",
        "      radius = " .. fmt(beam.radius) .. ", radiusGrow = " .. fmt(beam.radiusGrow) .. ",",
        "      strengthNear = " .. fmt(beam.strengthNear) .. ", strengthFar = " .. fmt(beam.strengthFar) .. ",",
    }
    for level = 0, 2 do
        local t = self.debug.alert[level].tint
        lines[#lines + 1] = string.format("[%d] tint = { %.2f, %.2f, %.2f },  -- %s", level, t[1], t[2], t[3],
            ALERT_NAMES[level])
    end
    copyBlock(lines)
end

function GENZ_ScrappyLightsTuner:onRestore()
    if not fileValues then
        chatLine("nada mudou ainda: ja' esta' no arquivo")
        return
    end
    putBack(self.debug.head, fileValues.head)
    putBack(self.debug.beam, fileValues.beam)
    for level = 0, 2 do putBack(self.debug.alert[level].tint, fileValues.tints[level]) end
    self.debug.forcedAlert = nil
    self.debug.refresh()
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

-- Chat command wrap (skill pz-ajuste-ao-vivo, "Comando de chat").
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
