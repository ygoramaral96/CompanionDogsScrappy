-- Scrappy cargo-case tuner, DEBUG ONLY (card #246, skill pz-ajuste-ao-vivo): a small native window, opened
-- and closed by the chat command /scrappy_caixa, that edits the saddlebags_c attachment of Scrappy_Body live --
-- offset, rotate, scale and the BONE it hangs from (a list of the dog's bones). Type, press Aplicar.
--   Copiar bloco  -> the attachment block, as it goes in models_scrappy.txt, in the chat and in console.txt
--   Voltar ao arquivo -> the numbers the game started with
-- Fields take only digits, "." and "-" (setOnlyNumbers) and turn red while out of range. Nothing is saved:
-- reopening the game goes back to the file. Stays in the mod for later tests (Ygor, 13/10).
if not isDebugEnabled() or isServer() then return end
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"

local COMMAND = "/scrappy_caixa"
local TAG = "[GENZ_ScrappyCargoTuner] "
local MODEL = "Base.Scrappy_Body"
local ATTACHMENT = "saddlebags_c"
local ROW = 22
local LABEL_W = 110
local ENTRY_W = 170
local PAD = 10
local MAX_CHARS = 8
-- The skeleton of Scrappy_Body.glb (the German Shepherd's, 55 joints), read from the GLB's skin on 13/10;
-- Translation_Data is animation data, not a place to hang anything.
local BONES = {
    "Dummy01", "Base", "Root_bone", "Spine_base", "Spine_01", "Spine_02", "Spine_03", "Spine_04", "Spine_05",
    "neck", "Bip01_Head", "mouth", "nose", "eye.L", "eye.R", "Ear.L", "Ear.R",
    "tongue_1", "tongue_2", "tongue_3", "tongue_4",
    "tail_01", "tail_02", "tail_03", "tail_04", "tail_05",
    "hip_f.L", "thigh_f.L", "leg_f.L", "shin_f.L", "Bip01_L_Foot", "claws_f.L", "Helper_shin_f.L",
    "hip_f.R", "thigh_f.R", "leg_f.R", "shin_f.R", "Bip01_R_Foot", "claws_f.R", "Helper_shin_f.R",
    "hip_b.L", "thigh_b.L", "leg_b.L", "shin_b.L", "foot_b.L", "claws_b.L", "Helper_foot_b.L",
    "hip_b.R", "thigh_b.R", "leg_b.R", "shin_b.R", "foot_b.R", "claws_b.R", "Helper_foot_b.R",
}

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

-- %.4f without trailing zeros (%.Nf is proven in Kahlua; %g is not relied on)
local function fmt(n)
    local s = string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", "")
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

local function attachmentOf()
    local script = getScriptManager():getModelScript(MODEL)
    return script and script:getAttachmentById(ATTACHMENT)
end

-- One row per number: label, show() -> text, parse(text) -> value | nil, error, set(value).
local function buildFields(attach)
    local o, r = attach:getOffset(), attach:getRotate()
    local function axis(vector, label, i, parse)
        local get = { function() return vector:x() end, function() return vector:y() end,
            function() return vector:z() end }
        return {
            label = label,
            show = function() return fmt(get[i]()) end,
            parse = parse,
            set = function(v)
                local xyz = { vector:x(), vector:y(), vector:z() }
                xyz[i] = v
                vector:set(xyz[1], xyz[2], xyz[3])
            end,
        }
    end
    local offset, angle = numberIn(-5, 5), numberIn(-360, 360)
    return {
        axis(o, "offset X", 1, offset), axis(o, "offset Y", 2, offset), axis(o, "offset Z", 3, offset),
        axis(r, "giro X", 1, angle), axis(r, "giro Y", 2, angle), axis(r, "giro Z", 3, angle),
        { label = "escala", show = function() return fmt(attach:getScale()) end, parse = numberIn(0.01, 10),
          set = function(v) attach:setScale(v) end },
    }
end

local function snapshot(attach)
    local o, r = attach:getOffset(), attach:getRotate()
    return { offset = { o:x(), o:y(), o:z() }, rotate = { r:x(), r:y(), r:z() }, scale = attach:getScale(),
        bone = attach:getBone() }
end

-- Hang the case again on every dog wearing it, on a body that reads the attachment anew
-- (resetEquippedHandsModels rebuilds the hung models; parentBone is resolved when they are built).
local function rehang()
    local animals = getCell():getAnimals()
    local hung = 0
    for i = 0, animals:size() - 1 do
        local animal = animals:get(i)
        local item = animal:getAttachedItem(ATTACHMENT)
        if item then
            animal:setAttachedItem(ATTACHMENT, item)
            animal:resetEquippedHandsModels()
            hung = hung + 1
        end
    end
    return hung
end

local fileValues = nil             -- the attachment before the first change of this session

-- Red label while the field is out of range, as the player types.
local function onFieldChanged(field, entry)
    field.bad = field.parse(entry:getText()) == nil
end

GENZ_ScrappyCargoTuner = ISCollapsableWindow:derive("GENZ_ScrappyCargoTuner")

function GENZ_ScrappyCargoTuner:new(attach)
    local fields = buildFields(attach)
    local width = PAD * 3 + LABEL_W + ENTRY_W
    local height = 20 + PAD + (#fields + 1) * ROW + PAD + 2 * (ROW + 4) + PAD
    local x = getCore():getScreenWidth() - width - 20     -- top right corner: never over the dog
    local o = ISCollapsableWindow:new(x, 80, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Caixa do Scrappy (nao salva)"
    o.resizable = false
    o.attach = attach
    o.fields = fields
    return o
end

function GENZ_ScrappyCargoTuner:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + PAD
    local entryX = PAD * 2 + LABEL_W
    for i, field in ipairs(self.fields) do
        local entry = ISTextEntryBox:new(field.show(), entryX, top + (i - 1) * ROW, ENTRY_W, ROW - 3)
        entry:initialise()
        entry:instantiate()
        entry:setOnlyNumbers(true)          -- digits, "." and "-" only (Core keyboard filter, 42.21)
        entry:setMaxTextLength(MAX_CHARS)
        entry.target = field
        entry.onTextChangeFunction = onFieldChanged
        self:addChild(entry)
        field.entry = entry
    end
    local boneY = top + #self.fields * ROW
    self.boneBox = ISComboBox:new(entryX, boneY, ENTRY_W, ROW - 3, self, nil)
    self.boneBox:initialise()
    for _, bone in ipairs(BONES) do self.boneBox:addOption(bone) end
    self.boneBox:select(self.attach:getBone())
    self:addChild(self.boneBox)
    local buttonsY = boneY + ROW + PAD
    local half = (self.width - PAD * 3) / 2
    self:makeButton(PAD, buttonsY, self.width - PAD * 2, "Aplicar", self.onApply)
    self:makeButton(PAD, buttonsY + ROW + 4, half, "Copiar bloco", self.onCopy)
    self:makeButton(PAD * 2 + half, buttonsY + ROW + 4, half, "Voltar ao arquivo", self.onRestore)
end

function GENZ_ScrappyCargoTuner:makeButton(x, y, w, label, onClick)
    local button = ISButton:new(x, y, w, ROW, label, self, onClick)
    button:initialise()
    button:instantiate()
    button.font = UIFont.Small
    self:addChild(button)
end

function GENZ_ScrappyCargoTuner:prerender()
    ISCollapsableWindow.prerender(self)
    local top = self:titleBarHeight() + PAD
    for i, field in ipairs(self.fields) do
        local bad = field.bad
        self:drawText(field.label, PAD, top + (i - 1) * ROW + 2, 1, bad and 0.35 or 1, bad and 0.25 or 1, 1,
            UIFont.Small)
    end
    self:drawText("osso", PAD, top + #self.fields * ROW + 2, 1, 1, 1, 1, UIFont.Small)
end

function GENZ_ScrappyCargoTuner:refreshEntries()
    for _, field in ipairs(self.fields) do
        field.bad = false
        field.entry:setText(field.show())
    end
    self.boneBox:select(self.attach:getBone())
end

-- All or nothing: one bad field stops the rest and is named in the chat (and painted red).
function GENZ_ScrappyCargoTuner:onApply()
    local values = {}
    for i, field in ipairs(self.fields) do
        local value, err = field.parse(field.entry:getText())
        if value == nil then
            field.bad = true
            chatLine(field.label .. ": " .. err .. " -- nada aplicado", true)
            return
        end
        values[i] = value
    end
    fileValues = fileValues or snapshot(self.attach)
    for i, field in ipairs(self.fields) do field.set(values[i]) end
    self.attach:setBone(self.boneBox:getSelectedText())
    local hung = rehang()
    self:refreshEntries()
    if hung == 0 then
        chatLine("aplicado, mas nenhum Scrappy esta' com a caixa: ponha um item na bolsa dele", true)
        return
    end
    chatLine("aplicado (osso " .. self.attach:getBone() .. ")")
end

function GENZ_ScrappyCargoTuner:onCopy()
    local o, r = self.attach:getOffset(), self.attach:getRotate()
    chatLine("attachment " .. ATTACHMENT .. " {")
    chatLine("    offset = " .. fmt(o:x()) .. " " .. fmt(o:y()) .. " " .. fmt(o:z()) .. ",")
    chatLine("    rotate = " .. fmt(r:x()) .. " " .. fmt(r:y()) .. " " .. fmt(r:z()) .. ",")
    chatLine("    scale = " .. fmt(self.attach:getScale()) .. ",")
    chatLine("    bone = " .. self.attach:getBone() .. ",")
    chatLine("}")
end

function GENZ_ScrappyCargoTuner:onRestore()
    if not fileValues then
        chatLine("nada mudou ainda: ja' esta' no arquivo")
        return
    end
    local saved = fileValues
    self.attach:getOffset():set(saved.offset[1], saved.offset[2], saved.offset[3])
    self.attach:getRotate():set(saved.rotate[1], saved.rotate[2], saved.rotate[3])
    self.attach:setScale(saved.scale)
    self.attach:setBone(saved.bone)
    rehang()
    self:refreshEntries()
    chatLine("voltou ao arquivo")
end

function GENZ_ScrappyCargoTuner:close()
    self:removeFromUIManager()
    GENZ_ScrappyCargoTuner.instance = nil
end

function GENZ_ScrappyCargoTuner.toggle()
    if GENZ_ScrappyCargoTuner.instance then
        GENZ_ScrappyCargoTuner.instance:close()
        return
    end
    local attach = attachmentOf()
    if not attach then
        chatLine(MODEL .. " / " .. ATTACHMENT .. " nao encontrado no script", true)
        return
    end
    local window = GENZ_ScrappyCargoTuner:new(attach)
    window:initialise()
    window:addToUIManager()
    GENZ_ScrappyCargoTuner.instance = window
end

-- Chat command wrap (skill pz-ajuste-ao-vivo, "Comando de chat").
local function wrapChat()
    if not (ISChat and ISChat.onCommandEntered) or ISChat._genzScrappyCargoTuner then return end
    ISChat._genzScrappyCargoTuner = true
    local original = ISChat.onCommandEntered
    ISChat.onCommandEntered = function(self)
        local chat = ISChat.instance
        local entry = chat and chat.textEntry
        local text = entry and entry:getText() or ""
        if string.lower(text:match("^%S+") or "") ~= COMMAND then return original(self) end
        chat:unfocus()
        entry:setText("")
        GENZ_ScrappyCargoTuner.toggle()
    end
    -- the text box keeps the function it had when the chat was built (ISChat.lua): point it at ours
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

wrapChat()
Events.OnGameStart.Add(wrapChat)
