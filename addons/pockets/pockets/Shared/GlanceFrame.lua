--[[
    Shared/GlanceFrame.lua - Native window chrome (Forever's PortraitFrameTemplate)

    The one thing left of the old Glance chassis: wrapping a frame in the
    client's PortraitFrameTemplate (bag icon in the portrait ring, title bar).
    Generic drawing only - no Pockets business logic, no dependency on pH.
]]

local _, Pockets = ...

Pockets.UI.GlanceFrame = Pockets.UI.GlanceFrame or {}
local GlanceFrame = Pockets.UI.GlanceFrame

-- How far the native template's art overhangs its rect (left, top, right,
-- bottom), from the corner pieces' anchors in the portrait-frame dump.
-- Inset chosen so the template's ring centre (corner art centre (38.5, 38),
-- corner at -13,+16) lands on the Mini portrait's centre (31, 30 from the
-- HUD's top-left): opening/closing then keeps the ring where it was.
local CHROME_OVERHANG = { left = 6, top = 8, right = 2, bottom = 8 }

-- Plain, unmodified PortraitFrameTemplate filling `frame`: no scale, no
-- cropping, no hidden pieces. Only the bag icon goes in the portrait and the
-- title text is set. (The template's close button is hidden only because it
-- would hide this child frame, not the HUD.) Returns nil when the template
-- doesn't exist on this client.
function GlanceFrame:CreateChrome(frame, portrait, alpha, title, portraitOpts)
    local ok, chrome = pcall(CreateFrame, "Frame", nil, frame, "PortraitFrameTemplate")
    if not ok or not chrome or not chrome.PortraitContainer then
        return nil
    end
    -- The template's art overhangs its own rect (corners sit at -13/+16 left
    -- and up, +2/-8 right and down, measured with /pockets debug portrait).
    -- Inset the template by that overhang so the VISIBLE top-left corner lands
    -- exactly on the HUD's top-left anchor (and nothing is clipped at the
    -- screen's top/left edge).
    local o = CHROME_OVERHANG
    chrome:SetPoint("TOPLEFT", frame, "TOPLEFT", o.left, -o.top)
    chrome:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -o.right, o.bottom)
    chrome:EnableMouse(false)
    if chrome.SetPortraitToAsset then
        chrome:SetPortraitToAsset(portrait)
    elseif chrome.PortraitContainer.portrait then
        chrome.PortraitContainer.portrait:SetTexture(portrait)
    end
    -- Optional: size/centre the bag art to match another HUD's portrait
    -- (portraitOpts = { size, centerX, centerY } from the frame's TOPLEFT).
    local art = chrome.PortraitContainer.portrait
    if portraitOpts and art then
        art:SetTexture(portrait)
        art:SetTexCoord(0, 1, 0, 1)
        art:SetSize(portraitOpts.size, portraitOpts.size)
        art:ClearAllPoints()
        art:SetPoint("CENTER", frame, "TOPLEFT", portraitOpts.centerX, portraitOpts.centerY)
    end
    if chrome.CloseButton then
        chrome.CloseButton:Hide()
    end
    if chrome.SetTitle then
        chrome:SetTitle(title or "")
    end
    return chrome
end
