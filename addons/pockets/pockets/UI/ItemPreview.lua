--[[
    UI/ItemPreview.lua - Large floating item-icon preview, shown near
    top-center of the screen (opt-in toggle, /pockets recentpreview).

    A single lazily-created singleton frame, independent of Glance's own
    position/size (Glance is small; a big preview anchored to it would
    just get clipped or overlap other UI unpredictably depending on
    where the player has dragged Glance). Callers decide WHEN to show it
    (e.g. RecentItemStrip's hover handlers, gated on the
    recentItemPreviewEnabled setting) - this component only knows how to
    render one record, not the setting or the hover trigger itself.
]]

local _, Pockets = ...

Pockets.UI.ItemPreview = Pockets.UI.ItemPreview or {}
local ItemPreview = Pockets.UI.ItemPreview
local PHUI = Pockets.UI.PHUI

-- Stored on the table itself (not a private local) so tests can inspect
-- ItemPreview.frame:IsShown() directly rather than needing a separate
-- getter just for verification.
function ItemPreview:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local L = Pockets.Constants.LAYOUT
    local size = L.RECENT_PREVIEW_ICON_SIZE + L.RECENT_PREVIEW_PADDING * 2

    local frame = CreateFrame("Frame", "PocketsItemPreviewFrame", UIParent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -L.RECENT_PREVIEW_TOP_OFFSET)
    -- Above ordinary game UI (tooltips/action bars) but not fighting
    -- actual Blizzard tooltips, which sit at TOOLTIP - one strata below
    -- keeps this readable without ever covering a real tooltip.
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(false)
    PHUI.ApplyBackdrop(frame)

    frame.icon = PHUI.CreateNativeIcon(frame, L.RECENT_PREVIEW_ICON_SIZE, nil)
    frame.icon:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame:Hide()
    self.frame = frame
    return frame
end

-- record: anything with .texture and optionally .quality (same shape
-- Configure()/aggregated item records already use elsewhere).
function ItemPreview:Show(record)
    if not record or not record.texture then
        return
    end
    local f = self:EnsureFrame()
    f.icon:SetTexture(record.texture)

    local color = record.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[record.quality]
    if color and record.quality > 1 then
        PHUI.ApplyBackdrop(f, { borderColor = { color.r, color.g, color.b, 1 } })
    else
        PHUI.ApplyBackdrop(f)
    end

    f:Show()

    -- The caller's own OnEnter already showed/anchored GameTooltip
    -- against the small hovered button (ItemButtonPool's base OnEnter,
    -- which runs before this - Show() is called from a HookScript, not
    -- SetScript). Re-anchor it to this preview icon's top-right instead,
    -- so the big icon and its tooltip read as one cohesive hover result
    -- near the top of the screen rather than two disconnected pieces of
    -- UI. Only touches GameTooltip's POSITION (ClearAllPoints/SetPoint),
    -- never its owner/content - Configure()'d buttons still own what the
    -- tooltip actually shows.
    if GameTooltip:IsShown() then
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
    end
    self:Recenter()
    -- The tooltip can still be growing (extra lines added by post-call
    -- hooks, item info arriving), so settle once more next frame.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if f:IsShown() then
                ItemPreview:Recenter()
            end
        end)
    end
end

-- Centres the icon + tooltip pair (icon, 4px gap, tooltip) horizontally on
-- the screen. The tooltip stays anchored to the icon's top-right, so only
-- the icon moves.
function ItemPreview:Recenter()
    local f = self.frame
    if not f or not f:IsShown() then
        return
    end
    local tooltipWidth = GameTooltip:IsShown() and GameTooltip:GetWidth() or 0
    local gap = tooltipWidth > 0 and 4 or 0
    local total = f:GetWidth() + gap + tooltipWidth
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOP", -total / 2, -Pockets.Constants.LAYOUT.RECENT_PREVIEW_TOP_OFFSET)
end

function ItemPreview:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
