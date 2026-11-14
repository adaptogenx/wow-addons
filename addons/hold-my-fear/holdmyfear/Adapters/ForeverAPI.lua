--[[
    Adapters/ForeverAPI.lua - What Forever allows instead of aura reads and the combat log.

    Learned from Warlock Tools Forever / Dyre's Toolkit (read in client, MIT): addon code cannot read
    enemy auras on Forever, but Blizzard's AuraContainer engine can. It reads the auras of a unit we
    bind it to and draws them into regions we made (icon bar, time text). So the addon only needs to
    know WHICH mob a cast went to (UNIT_SPELLCAST_SENT gives a name, locked to a unit as the cast
    starts) and to keep each row's container bound to a unit token that shows that mob.
    Never touch a region after handing it to the engine (taint); anchor it to a frame of ours instead.
]]

local _, HMF = ...

local Forever = {}
HMF.Adapters.Forever = Forever

local C = HMF.Constants
local Unit = HMF.Adapters.Unit

local TEMPLATE = "CustomAuraContainerTemplate"
local FILTER = "HARMFUL|PLAYER"
local TEXCOORD = { 0.07, 0.93, 0.07, 0.93 }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local available
local canonical = {} -- Forever name -> our tracked name

-- True on clients that ship Blizzard's aura engine (Forever). Loads its addon on first use.
function Forever.EngineAvailable()
    if available == nil then
        available = false
        if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
            if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
                pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
            end
            available = C_XMLUtil.GetTemplateInfo(TEMPLATE) ~= nil
        end
    end
    return available
end

function Forever.NewContainer(parent)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, TEMPLATE)
    if not ok then return nil end
    container:SetPoint("TOPLEFT", parent, "TOPLEFT")
    container:SetSize(1, 1)
    return container
end

function Forever.SpellName(spellID)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if Unit.IsSecret(name) or type(name) ~= "string" then return nil end
    return name
end

-- Tracked spell name for a cast spell ID; unlisted ranks match by spell name.
function Forever.TrackedName(spellID)
    if Unit.IsSecret(spellID) or type(spellID) ~= "number" then return nil end
    local name = C.SPELL_NAME_BY_ID[spellID]
    if name then return name end
    local cast = Forever.SpellName(spellID)
    cast = cast and (canonical[cast] or cast)
    if cast and C.SPELL_IDS[cast] then
        C.SPELL_NAME_BY_ID[spellID] = cast
        if Forever.LearnID(cast, spellID) then Forever.idsChanged = true end
        return cast
    end
    return nil
end

-- Icon for a cast spell ID (the Forever name may differ from our tracked name, e.g. Bane of Agony).
function Forever.IconFor(spellID)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    if Unit.IsSecret(tex) then return nil end
    return tex
end

-- Spell IDs the engine slot for each tracked spell accepts: our list, plus every spellbook rank by
-- name or alias (Forever renames and reworks some), plus any ID seen cast. Rebuilt on SPELLS_CHANGED.
local sets = {}
local function idSet(name)
    if not sets[name] then
        sets[name] = {}
        for _, id in ipairs(C.SPELL_IDS[name] or {}) do sets[name][id] = true end
    end
    return sets[name]
end

for name, alias in pairs(C.SPELL_ALIASES) do canonical[alias] = name end

function Forever.LearnID(name, id)
    local set = idSet(name)
    if set[id] then return false end
    set[id] = true
    return true
end

-- Add spellbook ranks by name. Returns true when the sets grew.
function Forever.ScanSpellbook()
    local grew = false
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo) then return grew end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if type(info) == "table" then
            for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                if type(item) == "table" and type(item.spellID) == "number" and type(item.name) == "string" then
                    local name = canonical[item.name] or item.name
                    if C.SPELL_IDS[name] and Forever.LearnID(name, item.spellID) then grew = true end
                end
            end
        end
    end
    return grew
end

-- Point every slot of a container at the current ID sets.
function Forever.RefreshFilters(container)
    for name in pairs(C.SPELL_IDS) do
        pcall(container.SetAuraSlotCandidateFilters, container, name, { includeSpellIDs = idSet(name) })
    end
end

-- Whether the engine is drawing this spell's bar now: true/false, or nil when it cannot be read.
local buttons = setmetatable({}, { __mode = "k" })
function Forever.SlotShown(container, name)
    local button = buttons[container] and buttons[container][name]
    if not button then return nil end
    local ok, shown = pcall(button.IsShown, button)
    if not ok or Unit.IsSecret(shown) then return nil end
    return shown == true
end

local function textureFor(name)
    for _, id in ipairs(C.SPELL_IDS[name] or {}) do
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if tex then return tex end
    end
    return Unit.SpellIcon(name) or QUESTION
end

-- One engine slot for a tracked spell, drawn over `anchor` (a frame of ours that we may move):
-- a dim copy of the icon behind a draining icon bar (remaining time on the left), and, with
-- opts.text, the engine's time-left text. The slot shows only while the bound unit has our aura.
function Forever.AddSlot(container, name, anchor, opts)
    opts = opts or {}
    container:AddAuraSlot(name, FILTER, {
        candidateFilters = { includeSpellIDs = idSet(name) },
        initializeFrame = function(button)
            buttons[container] = buttons[container] or {}
            buttons[container][name] = button
            local tex = textureFor(name)
            button:ClearAllPoints()
            button:SetAllPoints(anchor)
            button:SetMouseClickEnabled(false)
            if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
            local back = button:CreateTexture(nil, "BACKGROUND")
            back:SetPoint("TOPLEFT", 1, -1)
            back:SetPoint("BOTTOMRIGHT", -1, 1)
            back:SetTexture(tex)
            back:SetTexCoord(unpack(TEXCOORD))
            back:SetDesaturated(true)
            back:SetVertexColor(0.3, 0.3, 0.3)
            local status = CreateFrame("StatusBar", nil, button)
            status:SetPoint("TOPLEFT", 1, -1)
            status:SetPoint("BOTTOMRIGHT", -1, 1)
            status:SetStatusBarTexture(tex)
            local direction = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            button:SetDurationBar(status, { direction = direction })
            if opts.text then
                local fs = status:CreateFontString(nil, "OVERLAY")
                fs:SetFont(STANDARD_TEXT_FONT, opts.textSize or 14, "OUTLINE")
                fs:SetPoint("CENTER", 0, 0)
                button:SetDurationText(fs, {})
            end
        end,
    })
end

-- Bind a container to a unit token, or release it ("none") when no token shows the mob.
function Forever.Bind(container, token)
    container:SetUnit(token or "none")
    container:UpdateAllAuras()
end

-- The mob a cast sent at `targetName` goes to, read as the cast starts (SENT gives only a name; a
-- lookup by name at success time, after a tab, picked the wrong mob in WTF). First hostile, living
-- unit with that name in the order the player's own casts aim. Returns guid or nil.
function Forever.LockCast(targetName)
    if Unit.IsSecret(targetName) or type(targetName) ~= "string" or targetName == "" then return nil end
    local units = { "focus", "mouseover", "target" }
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    for _, token in ipairs(units) do
        if UnitExists(token) and Unit.Info(token) == targetName and Unit.CanAttack(token) and not Unit.IsDead(token) then
            local guid = Unit.GUID(token) or Unit.PlateGUID(token)
            if guid then return guid end
        end
    end
    return nil
end
