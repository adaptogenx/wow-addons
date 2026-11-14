--[[
    UI/CastButtons.lua - Click an icon on a row to recast that spell.

    Rules copied from Warlock Tools Forever / Dyre's Toolkit:
      * The rows stay ordinary frames. A secure button is never parented or anchored to a row, so rows
        show, hide and resize in combat (anchoring a secure button to a frame makes that frame protected:
        "ADDON_ACTION_BLOCKED Frame:Show()"). Buttons live on their own layer, fixed offsets from the HUD frame.
      * Macro: "/cast [@focus,exists,harm,nodead] Spell; [harm,nodead] Spell" - your focus, else your target
        (WTF's chain: the first mob works with no focus set). Lab: works in and out of combat.
      * Secure code cannot tell mobs apart, so an ordinary blocker frame covers the icons of every row that
        the click would NOT land on: the row must be the focus, or, with no focus, the target. Blockers show
        and hide in combat; secure buttons cannot.
      * Visibility follows a state driver on unit conditions (the only thing allowed in combat), so with no
        hostile focus or target the buttons are hidden and the world is clickable.
    Slots are fixed: the Fear button sits on the Fear icon, DoT button i on the i-th known DoT of
    C.PLACEHOLDER_DOTS (the HUD always draws those first, in that order). Attributes change only out of
    combat (queued to PLAYER_REGEN_ENABLED).
]]

local _, HMF = ...

local CastButtons = {}
HMF.UI.CastButtons = CastButtons

local C = HMF.Constants
local K = C.HUD
local Unit = HMF.Adapters.Unit

local VISIBLE = "[@focus,exists,harm,nodead] show; [harm,nodead] show; hide"

local hud      -- the HUD frame (insecure, parent of the blocker frames)
local layer    -- the secure layer: child of hud, same box
local fears, dots, blockers = {}, {}, {}
local built, dirty = false, true
local waiter

local function Macro(spell)
    return "/cast [@focus,exists,harm,nodead] " .. spell .. "; [harm,nodead] " .. spell
end

-- DoT names the player knows, in slot order (shared with the HUD so icon and button line up).
function CastButtons.KnownDots()
    local list = {}
    for _, name in ipairs(C.PLACEHOLDER_DOTS) do
        if Unit.Knows(name) then list[#list + 1] = name end
    end
    return list
end

local function Tip(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText("Click: " .. (button.spell or "?") .. " this mob", 1, 1, 1)
    GameTooltip:AddLine("Your focus, else your target.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function NewButton(w, h)
    local b = CreateFrame("Button", nil, layer, "SecureActionButtonTemplate")
    b:SetSize(w, h)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("useOnKeyDown", false)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", Tip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local function RowTop(i) return -(i - 1) * (K.ROW_HEIGHT + K.ROW_GAP) end

local function BuildRow(i, slotX, slotY)
    local y = RowTop(i) + slotY()
    local fear = NewButton(K.ICON, K.ICON)
    fear:SetPoint("TOPRIGHT", layer, "TOPRIGHT", -K.PAD, y)
    fears[i] = fear
    dots[i] = {}
    for d = 1, #C.PLACEHOLDER_DOTS do
        local b = NewButton(K.ICON, K.ICON)
        b:SetPoint("TOPLEFT", layer, "TOPLEFT", slotX(d), y)
        dots[i][d] = b
    end

    -- Insecure blocker over the icon band (child of the HUD frame, above the buttons).
    local block = CreateFrame("Frame", nil, hud)
    block:SetPoint("TOPLEFT", hud, "TOPLEFT", slotX(1) - 2, y + 2)
    block:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -(K.PAD - 2), y + 2)
    block:SetHeight(K.ICON + 4)
    block:SetFrameLevel(layer:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Not your focus", 1, 0.8, 0.2)
        GameTooltip:AddLine("Click works on your focus, or on your target when you have no focus.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    block:SetScript("OnLeave", function() GameTooltip:Hide() end)
    block:Hide()
    blockers[i] = block
end

-- Out of combat only: point every button at its spell and its visibility driver.
local function Apply()
    local fear = Unit.CastName(C.FEAR_SPELL)
    local known = CastButtons.KnownDots()
    local function Set(b, spell)
        b.spell = spell
        b:SetAttribute("type1", spell and "macro" or nil)
        b:SetAttribute("macrotext1", spell and Macro(spell) or nil)
        UnregisterStateDriver(b, "visibility")
        RegisterStateDriver(b, "visibility", spell and VISIBLE or "hide")
    end
    for i = 1, #fears do
        Set(fears[i], fear)
        for d, b in ipairs(dots[i]) do
            local name = known[d]
            Set(b, name and Unit.CastName(name) or nil)
        end
    end
    dirty = false
end

local function Flush()
    if not built then return end
    if InCombatLockdown() then
        if not waiter then
            waiter = CreateFrame("Frame")
            waiter:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                Flush()
            end)
        end
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if dirty then Apply() end
end

-- Spellbook changed: attributes follow, out of combat (in combat, once it ends).
function CastButtons.Refresh()
    dirty = true
    Flush()
end

-- A click lands on the focus, else on the target. Cover every row it would NOT be right for.
function CastButtons.UpdateBlockers(list)
    if not built then return end
    local focus, target = Unit.FocusGUID(), Unit.GUID("target")
    local live = focus ~= nil or target ~= nil
    for i, block in ipairs(blockers) do
        local entry = list[i]
        local ok = entry and ((focus and entry.guid == focus) or (not focus and target and entry.guid == target))
        block:SetShown(live and not ok)
    end
end

-- Create the buttons once, out of combat. hudFrame: the HUD frame; slotX(i), slotY(): icon slot offsets.
function CastButtons.Build(hudFrame, rowCount, slotX, slotY)
    if built then return end
    if InCombatLockdown() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            CastButtons.Build(hudFrame, rowCount, slotX, slotY)
        end)
        return
    end
    hud = hudFrame
    layer = CreateFrame("Frame", nil, hud)
    layer:SetAllPoints(hud)
    layer:SetFrameLevel(hud:GetFrameLevel() + 20)
    for i = 1, rowCount do BuildRow(i, slotX, slotY) end
    built = true
    dirty = true
    Flush()
end
