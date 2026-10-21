--[[
    UI/LootLog.lua - Loot Log body: a dense, chronological
    `timestamp | loot` list of items and coin the player looted (not a ledger).

    Shell owns the frame, header, footer, scrollFrame and ScrollBar (the
    same chrome Menu/Category/All use); this module only fills Shell's
    scroll `content` with rows and reports the content height it needs.

    Rows are variable height: an item name that doesn't fit wraps onto
    further lines and the row grows with it (never truncated). Layout is
    a pure function of (entries, rowWidth, measure) - PlanRows - so the
    arithmetic is unit-testable without real font metrics; Render only
    supplies a real FontString-backed `measure`.

    Columns: [timestamp, fixed, never wraps][gap][loot content, rest].
    Item rows put icon + name (+ quantity) in the loot column; money rows
    have no icon and start at the loot column's left edge, so there is no
    empty icon column making them look awkward.

    Rows are pooled (created lazily, reused); nothing runs per frame.
]]

local _, Pockets = ...

Pockets.UI.LootLog = Pockets.UI.LootLog or {}
local LootLog = Pockets.UI.LootLog

local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local L = Constants.LAYOUT

local TIMES = "\195\151" -- "×"
local SEPARATOR_ALPHA = 0.15

--------------------------------------------------
-- Pure formatting
--------------------------------------------------

-- HH:MM in the client's local time, no seconds.
function LootLog:FormatTime(timestamp)
    return date("%H:%M", timestamp or 0)
end

-- "" for quantity <= 1, otherwise "×N".
function LootLog:FormatQuantity(quantity)
    if (quantity or 1) > 1 then
        return TIMES .. quantity
    end
    return ""
end

local function QualityHex(quality)
    if quality == nil or not GetItemQualityColor then
        return nil
    end
    local r, g, b = GetItemQualityColor(quality)
    if not r then
        return nil
    end
    return string.format("ff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Returns name, colorHex ("ffrrggbb" or nil). The item link already
-- carries both (quality color + [name]) so a link-bearing entry renders
-- fully even before the item cache has it; ItemAPI is only the fallback.
function LootLog:ResolveItemName(entry)
    local link = entry.itemLink
    if link then
        local color = link:match("^|c(%x%x%x%x%x%x%x%x)")
        local name = link:match("|h%[(.-)%]|h")
        if name then
            return name, color
        end
    end
    local meta = Pockets.Adapters.ItemAPI:GetItemMetadata(entry.itemID, entry.itemLink)
    if meta and meta.status == "ready" and meta.name then
        return meta.name, QualityHex(meta.quality)
    end
    return "Item " .. tostring(entry.itemID), nil
end

-- "|cffxxxxxxName|r ×2" - quantity only when > 1, in the default color.
function LootLog:ItemText(entry)
    local name, color = self:ResolveItemName(entry)
    local text = color and ("|c" .. color .. name .. "|r") or name
    local qty = self:FormatQuantity(entry.quantity)
    if qty ~= "" then
        text = text .. " " .. qty
    end
    return text
end

function LootLog:MoneyText(entry)
    return Pockets.UI.MoneyFormat:Format(entry.copper)
end

--------------------------------------------------
-- Pure layout
--------------------------------------------------

-- measure(entry, textWidth) -> height in px of that entry's loot text when
-- wrapped to textWidth. Returns rows ({ entry, y, height, textLeft,
-- textWidth, textHeight }) and the total content height. Row height is
-- the taller of the wrapped text and the icon, plus vertical padding.
function LootLog:PlanRows(entries, rowWidth, measure)
    local lootLeft = L.LOOT_TIME_WIDTH + L.LOOT_COLUMN_GAP
    local itemTextLeft = lootLeft + L.GLANCE_METRIC_ICON_SIZE + L.LOOT_COLUMN_GAP

    local rows = {}
    local y = 0
    for i, entry in ipairs(entries) do
        local textLeft = entry.kind == "item" and itemTextLeft or lootLeft
        local textWidth = math.max(rowWidth - textLeft, 1)
        local textHeight = measure(entry, textWidth)
        local height = math.max(textHeight, L.GLANCE_METRIC_ICON_SIZE) + L.LOOT_ROW_PAD_Y * 2
        rows[i] = {
            entry = entry,
            y = y,
            height = height,
            textLeft = textLeft,
            textWidth = textWidth,
            textHeight = textHeight,
        }
        y = y + height
    end
    return rows, y
end

--------------------------------------------------
-- Widgets
--------------------------------------------------

local function ShowItemTooltip(row)
    local entry = row.entry
    if not entry or entry.kind ~= "item" then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    -- A stale/invalid link must never error out of a hover.
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, entry.itemLink or ("item:" .. entry.itemID))
    if ok then
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

local function CreateRow(view)
    local row = CreateFrame("Button", nil, view.parent)

    row.time = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.SMALL)
    row.time:SetJustifyH("LEFT")
    row.time:SetJustifyV("TOP")
    row.time:SetWordWrap(false)
    row.time:SetWidth(L.LOOT_TIME_WIDTH)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(L.GLANCE_METRIC_ICON_SIZE, L.GLANCE_METRIC_ICON_SIZE)

    row.text = PHUI.CreateLabel(row, "primary", nil, PHUI.Fonts.SMALL)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row.text:SetWordWrap(true)

    -- Subtle row separation, not a card.
    row.separator = row:CreateTexture(nil, "BACKGROUND")
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    do
        local color = PHUI.Colors.BORDER_BRONZE
        row.separator:SetColorTexture(color[1], color[2], color[3], SEPARATOR_ALPHA)
    end

    row:SetScript("OnEnter", ShowItemTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Historical entries, not inventory slots: tooltip + chat-link only,
    -- no pickup/use/drag.
    row:SetScript("OnClick", function(self)
        local entry = self.entry
        if entry and entry.kind == "item" and IsModifiedClick and IsModifiedClick("CHATLINK") then
            pcall(ChatEdit_InsertLink, entry.itemLink or ("item:" .. entry.itemID))
        end
    end)
    return row
end

-- parent: Shell's scroll content frame. Rows are its children so the
-- ScrollFrame clips them (a sibling would render unclipped).
function LootLog:Create(parent)
    local view = { parent = parent, rows = {} }

    -- Off-screen scratch FontString used only to measure wrapped heights.
    view.measureText = parent:CreateFontString(nil, "ARTWORK", PHUI.Fonts.SMALL)
    view.measureText:SetWordWrap(true)
    view.measureText:SetJustifyH("LEFT")
    -- Invisible rather than Hide()n: measuring must not depend on shown state.
    view.measureText:SetAlpha(0)
    view.measureText:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    view.emptyText = PHUI.CreateLabel(parent, "muted", "No recent loot.", PHUI.Fonts.SMALL)
    view.emptyText:SetPoint("TOP", parent, "TOP", 0, -L.SHELL_PADDING)
    view.emptyText:Hide()
    return view
end

function LootLog:Hide(view)
    for _, row in ipairs(view.rows) do
        row:Hide()
    end
    view.emptyText:Hide()
end

-- Lays out entries (newest first) into the pooled rows and returns the
-- total content height. rowWidth is the fixed body viewport width.
function LootLog:Render(view, entries, rowWidth)
    local scratch = view.measureText
    local function measure(entry, textWidth)
        scratch:SetWidth(textWidth)
        scratch:SetText(entry.kind == "item" and self:ItemText(entry) or self:MoneyText(entry))
        return math.ceil(scratch:GetStringHeight() or 0)
    end

    local rows, totalHeight = self:PlanRows(entries, rowWidth, measure)

    for i, plan in ipairs(rows) do
        local row = view.rows[i]
        if not row then
            row = CreateRow(view)
            view.rows[i] = row
        end
        local entry = plan.entry
        row.entry = entry
        row:SetSize(rowWidth, plan.height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.parent, "TOPLEFT", 0, -plan.y)

        row.time:ClearAllPoints()
        row.time:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -L.LOOT_ROW_PAD_Y)
        row.time:SetText(self:FormatTime(entry.time))

        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", plan.textLeft, -L.LOOT_ROW_PAD_Y)
        row.text:SetWidth(plan.textWidth)

        local c = PHUI.Colors.TEXT_PRIMARY
        if entry.kind == "item" then
            row.icon:ClearAllPoints()
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", L.LOOT_TIME_WIDTH + L.LOOT_COLUMN_GAP, -L.LOOT_ROW_PAD_Y)
            row.icon:SetTexture(Pockets.Adapters.ItemAPI:GetIcon(entry.itemID))
            row.icon:Show()
            row.text:SetText(self:ItemText(entry))
            row:EnableMouse(true)
        else
            row.icon:Hide()
            row.text:SetText(self:MoneyText(entry))
            row:EnableMouse(false)
        end
        row.text:SetTextColor(c[1], c[2], c[3])
        row:Show()
    end

    for i = #rows + 1, #view.rows do
        view.rows[i]:Hide()
        view.rows[i].entry = nil
    end
    view.emptyText:SetShown(#rows == 0)
    return totalHeight
end
