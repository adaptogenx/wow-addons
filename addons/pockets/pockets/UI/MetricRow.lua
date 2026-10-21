--[[
    UI/MetricRow.lua - Shared compact "[icon]  primary        secondary"
    row (Glance's Bag/Gold/Ammo rows today; generic enough to reuse
    anywhere else Pockets needs an inline icon+value metric).

    Every metric row in Glance is built through this ONE component with
    the SAME iconSize/height/gap, so icon dimensions, icon position, left
    edge, row height, and spacing are identical by construction rather
    than by convention (METRIC ROW SYSTEM spec) - callers only vary
    texture/text/style, never geometry.

    Both width and height are required opts and set explicitly at
    creation, never left for a later SetText to establish - a frame
    anchored by a single point needs BOTH dimensions known for WoW to
    resolve its own rect, let alone the secondary text's RIGHT anchor
    inside it (see the Glance blank-render bug this pattern guards
    against).
]]

local _, Pockets = ...

Pockets.UI.MetricRow = Pockets.UI.MetricRow or {}
local MetricRow = Pockets.UI.MetricRow
local PHUI = Pockets.UI.PHUI

-- opts: width, height, iconSize (all required), texture, iconOpts
-- (passed through to PHUI.CreateNativeIcon - e.g. { insetTexCoord =
-- false } for art that's already clean at the edges), gap (icon-to-text,
-- default 6), primaryStyle/primaryFont (default "primary"/NORMAL),
-- hasSecondary (bool - reserves a right-aligned secondary value, e.g.
-- Bag's ETA; Gold/Ammo omit it), secondaryStyle/secondaryFont (default
-- "muted"/SMALL).
function MetricRow:Create(parent, opts)
    opts = opts or {}
    local gap = opts.gap or 6

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width, opts.height)

    row.icon = PHUI.CreateNativeIcon(row, opts.iconSize, opts.texture, opts.iconOpts)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.primaryText = PHUI.CreateLabel(row, opts.primaryStyle or "primary", nil, opts.primaryFont or PHUI.Fonts.NORMAL)
    row.primaryText:SetPoint("LEFT", row.icon, "RIGHT", gap, 0)
    row.primaryText:SetJustifyH("LEFT")

    if opts.hasSecondary then
        row.secondaryText = PHUI.CreateLabel(row, opts.secondaryStyle or "muted", nil, opts.secondaryFont or PHUI.Fonts.SMALL)
        row.secondaryText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.secondaryText:SetJustifyH("RIGHT")
    end

    function row:SetTexture(texture)
        self.icon:SetTexture(texture)
    end

    function row:SetPrimary(text)
        self.primaryText:SetText(text)
    end

    function row:SetPrimaryColor(r, g, b, a)
        self.primaryText:SetTextColor(r, g, b, a)
    end

    -- No-op (not an error) when this row was created without
    -- hasSecondary, so callers never need to branch on row shape.
    function row:SetSecondary(text)
        if self.secondaryText then
            self.secondaryText:SetText(text)
        end
    end

    return row
end
