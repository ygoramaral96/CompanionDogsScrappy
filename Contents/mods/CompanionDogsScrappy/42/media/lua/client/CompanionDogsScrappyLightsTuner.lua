-- Scrappy lights tuner, DEBUG ONLY: a small native window, opened and
-- closed by the chat command /scrappy_lights, that edits the head light, the beam and the alert colours of
-- CompanionDogsScrappyLightsClient live (through S.lightsDebug). Type the values, press Apply.
--   Copy block    -> the numbers, as they go in the .lua, in the chat, in console.txt and on the clipboard
--   Back to file  -> the numbers the game started with
-- Fields take only digits, "." and "-" (setOnlyNumbers) and turn red while out of range. Nothing is saved:
-- reopening the game goes back to the file. Stays in the mod for later tests.
if not isDebugEnabled() or isServer() then return end
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "CompanionDogsScrappyShared"
local S = CompanionDogsScrappy

local COMMAND = "/scrappy_lights"
local TAG = "[CompanionDogsScrappyLightsTuner] "
local ROW = 22
local LABEL_W = 180                -- the longest label, "head: ahead side radius strength"
local ENTRY_W = 170                -- 4 small cells on the head row
local CELL_GAP = 4
local MAX_CHARS = 7
local PAD = 10
local ALERT_NAMES = { [0] = "green", [1] = "amber", [2] = "red" }

-- A line in the chat, only for this player (the usual chat-line recipe), and in console.txt.
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
    chatLine("copied: Ctrl+V pastes the block")
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
        if not n then return nil, "not a number" end
        if n < low or n > high then return nil, "out of " .. fmt(low) .. " to " .. fmt(high) end
        return n
    end
end

local function wholeIn(low, high)
    local check = numberIn(low, high)
    return function(text)
        local n, err = check(text)
        if not n then return nil, err end
        if n ~= math.floor(n) then return nil, "must be a whole number" end
        return n
    end
end

-- A row = a label and one or more cells; a cell = show() -> text, parse(text), set(value). A cell with
-- `options` is a drop-down list (ISComboBox) instead of a typed field: a small closed set of values is
-- picked, never typed.
local function cellOf(spec, key, parse)
    return {
        show = function() return fmt(spec[key]) end,
        parse = parse,
        set = function(v) spec[key] = v end,
    }
end

-- options = { { text, value }, ... }; get() -> current value; set(value)
local function choiceCell(options, get, set)
    return {
        options = options,
        show = function()
            local current = get()
            for _, option in ipairs(options) do
                if option[2] == current then return option[1] end
            end
            return options[1][1]
        end,
        parse = function(text)
            for _, option in ipairs(options) do
                if option[1] == text then return option[2] end
            end
            return nil, "pick an option from the list"
        end,
        set = set,
    }
end

local BEAM_COUNTS = { { "0 (head only)", 0 } }
for n = 1, 6 do BEAM_COUNTS[#BEAM_COUNTS + 1] = { tostring(n), n } end

-- false = the real zombies near the dog
local FORCED_ALERTS = { { "- real zombies", false }, { "0 green", 0 }, { "1 amber", 1 }, { "2 red", 2 } }

local function buildRows(debug)
    local head, beam = debug.head, debug.beam
    local rows = {
        { label = "head: ahead side radius strength", cells = {
            cellOf(head, "ahead", numberIn(-5, 10)), cellOf(head, "side", numberIn(-5, 5)),
            cellOf(head, "radius", wholeIn(1, 10)), cellOf(head, "strength", numberIn(0, 3)) } },
        { label = "beam: how many lights", cells = { choiceCell(BEAM_COUNTS,
            function() return beam.count end, function(v) beam.count = v end) } },
        { label = "beam: start, spacing", cells = {
            cellOf(beam, "start", numberIn(0, 10)), cellOf(beam, "spacing", numberIn(0.5, 5)) } },
        { label = "beam: radius, +radius/light", cells = {
            cellOf(beam, "radius", wholeIn(1, 10)), cellOf(beam, "radiusGrow", wholeIn(0, 5)) } },
        { label = "beam: strength near, far", cells = {
            cellOf(beam, "strengthNear", numberIn(0, 3)), cellOf(beam, "strengthFar", numberIn(0, 3)) } },
    }
    for level = 0, 2 do
        local tint = debug.alert[level].tint
        local cells = {}
        for c = 1, 3 do cells[c] = cellOf(tint, c, numberIn(0, 1)) end
        rows[#rows + 1] = { label = "colour " .. ALERT_NAMES[level] .. " (r g b)", cells = cells }
    end
    rows[#rows + 1] = { label = "force alert", cells = { choiceCell(FORCED_ALERTS,
        function() return debug.forcedAlert or false end, function(v) debug.forcedAlert = v or nil end) } }
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

CompanionDogsScrappyLightsTuner = ISCollapsableWindow:derive("CompanionDogsScrappyLightsTuner")

function CompanionDogsScrappyLightsTuner:new(debug)
    local rows = buildRows(debug)
    local width = PAD * 3 + LABEL_W + ENTRY_W
    local height = 20 + PAD + #rows * ROW + PAD + 2 * (ROW + 4) + PAD
    local x = getCore():getScreenWidth() - width - 20     -- top right corner: never over the dog
    local o = ISCollapsableWindow:new(x, 80, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Scrappy lights (not saved)"
    o.resizable = false
    o.debug = debug
    o.rows = rows
    return o
end

-- Red label while any cell of the row is out of range, as the player types.
local function onCellChanged(row, entry)
    row.bad = false
    for _, cell in ipairs(row.cells) do
        if cell.parse(cell.read()) == nil then row.bad = true end
    end
end

-- A drop-down for a closed set of values: nothing to validate, the list holds only valid ones.
local function makeChoiceBox(cell, x, y, w)
    local box = ISComboBox:new(x, y, w, ROW - 3, nil, nil)
    box:initialise()
    for _, option in ipairs(cell.options) do box:addOption(option[1]) end
    box:select(cell.show())
    cell.read = function() return box:getSelectedText() end
    cell.write = function(text) box:select(text) end
    return box
end

local function makeEntry(row, cell, x, y, w)
    local entry = ISTextEntryBox:new(cell.show(), x, y, w, ROW - 3)
    entry:initialise()
    entry:instantiate()
    entry:setOnlyNumbers(true)          -- digits, "." and "-" only (Core keyboard filter, 42.21)
    entry:setMaxTextLength(MAX_CHARS)
    entry.target = row
    entry.onTextChangeFunction = onCellChanged
    cell.read = function() return entry:getText() end
    cell.write = function(text) entry:setText(text) end
    return entry
end

function CompanionDogsScrappyLightsTuner:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + PAD
    local entryX = PAD * 2 + LABEL_W
    for i, row in ipairs(self.rows) do
        local n = #row.cells
        local cellW = (ENTRY_W - CELL_GAP * (n - 1)) / n
        for c, cell in ipairs(row.cells) do
            local x, y = entryX + (c - 1) * (cellW + CELL_GAP), top + (i - 1) * ROW
            if cell.options then
                self:addChild(makeChoiceBox(cell, x, y, cellW))
            else
                self:addChild(makeEntry(row, cell, x, y, cellW))
            end
        end
    end
    local buttonsY = top + #self.rows * ROW + PAD
    local half = (self.width - PAD * 3) / 2
    self:makeButton(PAD, buttonsY, self.width - PAD * 2, "Apply", self.onApply)
    self:makeButton(PAD, buttonsY + ROW + 4, half, "Copy block", self.onCopy)
    self:makeButton(PAD * 2 + half, buttonsY + ROW + 4, half, "Back to file", self.onRestore)
end

function CompanionDogsScrappyLightsTuner:makeButton(x, y, w, label, onClick)
    local button = ISButton:new(x, y, w, ROW, label, self, onClick)
    button:initialise()
    button:instantiate()
    button.font = UIFont.Small
    self:addChild(button)
end

function CompanionDogsScrappyLightsTuner:prerender()
    ISCollapsableWindow.prerender(self)
    local top = self:titleBarHeight() + PAD
    for i, row in ipairs(self.rows) do
        self:drawText(row.label, PAD, top + (i - 1) * ROW + 2, 1, row.bad and 0.35 or 1, row.bad and 0.25 or 1, 1,
            UIFont.Small)
    end
end

function CompanionDogsScrappyLightsTuner:refreshEntries()
    for _, row in ipairs(self.rows) do
        row.bad = false
        for _, cell in ipairs(row.cells) do cell.write(cell.show()) end
    end
end

-- All or nothing: one bad cell stops the rest and is named in the chat (and its row painted red).
function CompanionDogsScrappyLightsTuner:onApply()
    local values = {}
    for _, row in ipairs(self.rows) do
        for _, cell in ipairs(row.cells) do
            local value, err = cell.parse(cell.read())
            if value == nil then
                row.bad = true
                chatLine(row.label .. ": " .. err .. " -- nothing applied", true)
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
    chatLine("applied")
end

function CompanionDogsScrappyLightsTuner:onCopy()
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

function CompanionDogsScrappyLightsTuner:onRestore()
    if not fileValues then
        chatLine("nothing changed yet: it is already in the file")
        return
    end
    putBack(self.debug.head, fileValues.head)
    putBack(self.debug.beam, fileValues.beam)
    for level = 0, 2 do putBack(self.debug.alert[level].tint, fileValues.tints[level]) end
    self.debug.forcedAlert = nil
    self.debug.refresh()
    self:refreshEntries()
    chatLine("back to the file")
end

function CompanionDogsScrappyLightsTuner:close()
    self:removeFromUIManager()
    CompanionDogsScrappyLightsTuner.instance = nil
end

function CompanionDogsScrappyLightsTuner.toggle()
    if CompanionDogsScrappyLightsTuner.instance then
        CompanionDogsScrappyLightsTuner.instance:close()
        return
    end
    local debug = S.lightsDebug
    if not debug then
        chatLine("CompanionDogsScrappyLightsClient did not load (no S.lightsDebug)", true)
        return
    end
    local window = CompanionDogsScrappyLightsTuner:new(debug)
    window:initialise()
    window:addToUIManager()
    CompanionDogsScrappyLightsTuner.instance = window
end

-- Chat command wrap.
local function wrapChat()
    if not (ISChat and ISChat.onCommandEntered) or ISChat._scrappyLightsTuner then return end
    ISChat._scrappyLightsTuner = true
    local original = ISChat.onCommandEntered
    ISChat.onCommandEntered = function(self)
        local chat = ISChat.instance
        local entry = chat and chat.textEntry
        local text = entry and entry:getText() or ""
        if string.lower(text:match("^%S+") or "") ~= COMMAND then return original(self) end
        chat:unfocus()
        entry:setText("")
        CompanionDogsScrappyLightsTuner.toggle()
    end
    -- the text box keeps the function it had when the chat was built (ISChat.lua): point it at ours
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

wrapChat()
Events.OnGameStart.Add(wrapChat)
