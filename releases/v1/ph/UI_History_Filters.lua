--[[
    UI_History_Filters.lua - Filter bar component for GoldPH History

    Provides search, sort, zone, character, and flag filters.
]]

-- luacheck: globals CreateFrame UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDROPDOWNMENU_OPEN_MENU ToggleDropDownMenu CloseDropDownMenus DropDownList1
-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local GoldPH_History_Filters = {
    parent = nil,
    historyController = nil,

    -- UI elements
    searchBox = nil,
    sortDropdown = nil,
    zoneDropdown = nil,
    charDropdown = nil,
    flagsDropdown = nil,

    -- Reusable dropdown menu frames (so buttons can toggle them closed)
    sortMenu = nil,
    zoneMenu = nil,
    charMenu = nil,
    flagsMenu = nil,

    -- Search debouncing
    searchTimer = nil,
    searchDebounceDelay = 0.2,  -- 200ms delay
}

--------------------------------------------------
-- Initialize
--------------------------------------------------
function GoldPH_History_Filters:Initialize(parent, historyController)
    self.parent = parent
    self.historyController = historyController

    -- Search box (left side, 120px width)
    local searchBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    searchBox:SetSize(120, 25)
    searchBox:SetPoint("LEFT", parent, "LEFT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(30)
    searchBox:SetScript("OnTextChanged", function(self)
        GoldPH_History_Filters:OnSearchChanged(self:GetText())
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    self.searchBox = searchBox

    -- Search label
    local searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOM", searchBox, "TOP", 0, 2)
    searchLabel:SetText("Search")

    -- Sort dropdown (next to search)
    local sortBtn = self:CreateDropdownButton(parent, "Sort", 80)
    sortBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    sortBtn:SetScript("OnClick", function(self)
        GoldPH_History_Filters:ShowSortMenu(self)
    end)
    self.sortDropdown = sortBtn

    -- Zone dropdown
    local zoneBtn = self:CreateDropdownButton(parent, "Zone: All", 100)
    zoneBtn:SetPoint("LEFT", sortBtn, "RIGHT", 5, 0)
    zoneBtn:SetScript("OnClick", function(self)
        GoldPH_History_Filters:ShowZoneMenu(self)
    end)
    self.zoneDropdown = zoneBtn

    -- Character dropdown
    local charBtn = self:CreateDropdownButton(parent, "Char: All", 100)
    charBtn:SetPoint("LEFT", zoneBtn, "RIGHT", 5, 0)
    charBtn:SetScript("OnClick", function(self)
        GoldPH_History_Filters:ShowCharMenu(self)
    end)
    self.charDropdown = charBtn

    -- Flags dropdown (replaces multiple checkboxes to avoid overflow)
    local flagsBtn = self:CreateDropdownButton(parent, "Flags: Any", 110)
    flagsBtn:SetPoint("LEFT", charBtn, "RIGHT", 10, 0)
    flagsBtn:SetScript("OnClick", function(self)
        GoldPH_History_Filters:ShowFlagsMenu(self)
    end)
    self.flagsDropdown = flagsBtn
end

--------------------------------------------------
-- Create Dropdown Button Helper
--------------------------------------------------
function GoldPH_History_Filters:CreateDropdownButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, 25)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    local PH_BG_DARK = pH_Colors.BG_DARK
    local PH_BORDER_BRONZE = pH_Colors.BORDER_BRONZE
    btn:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.90)
    btn:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.70)

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText

    -- Arrow icon (using WoW-compatible font character)
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Slightly higher and more inset for better alignment
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 1)
    arrow:SetText("v")
    local PH_TEXT_MUTED = pH_Colors.TEXT_MUTED
    arrow:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    return btn
end

--------------------------------------------------
-- Show Sort Menu
--------------------------------------------------
function GoldPH_History_Filters:ShowSortMenu(button)
    if not self.sortMenu then
        self.sortMenu = CreateFrame("Frame", "GoldPH_SortMenu", button, "UIDropDownMenuTemplate")
    end
    local menu = self.sortMenu

    -- If this menu is already open, clicking the button should close it
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menu then
        CloseDropDownMenus()
        return
    end

    local function OnSortClick(sortField, label)
        self.historyController.filterState.sort = sortField
        self.sortDropdown.text:SetText(label)
        self:OnFilterChanged()
        CloseDropDownMenus()
    end

    local sortOptions = {
        {field = "totalPerHour", label = "Total g/hr"},
        {field = "cashPerHour", label = "Gold g/hr"},
        {field = "expectedPerHour", label = "Expected g/hr"},
        {field = "date", label = "Date"},
        {field = "xpPerHour", label = "XP/Hour"},
        {field = "repPerHour", label = "Rep/Hour"},
        {field = "honorPerHour", label = "Honor/Hour"},
    }

    UIDropDownMenu_Initialize(menu, function()
        for _, opt in ipairs(sortOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.func = function() OnSortClick(opt.field, opt.label) end
            info.checked = (self.historyController.filterState.sort == opt.field)
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, button, 0, 0)
end

--------------------------------------------------
-- Show Zone Menu
--------------------------------------------------
function GoldPH_History_Filters:ShowZoneMenu(button)
    if not self.zoneMenu then
        self.zoneMenu = CreateFrame("Frame", "GoldPH_ZoneMenu", button, "UIDropDownMenuTemplate")
    end
    local menu = self.zoneMenu

    -- Toggle closed if this menu is already open
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menu then
        CloseDropDownMenus()
        return
    end

    local function OnZoneClick(zone)
        self.historyController.filterState.zone = zone
        if zone then
            local zoneName = zone
            if #zoneName > 12 then
                zoneName = zoneName:sub(1, 9) .. "..."
            end
            self.zoneDropdown.text:SetText("Zone: " .. zoneName)
        else
            self.zoneDropdown.text:SetText("Zone: All")
        end
        self:OnFilterChanged()
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(menu, function()
        -- Add "All" option
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Zones"
        info.func = function() OnZoneClick(nil) end
        info.checked = (self.historyController.filterState.zone == nil)
        UIDropDownMenu_AddButton(info)

        -- Add zones
        local zones = GoldPH_Index:GetZones()
        for _, zone in ipairs(zones) do
            local zoneInfo = UIDropDownMenu_CreateInfo()
            zoneInfo.text = zone
            zoneInfo.func = function() OnZoneClick(zone) end
            zoneInfo.checked = (self.historyController.filterState.zone == zone)
            UIDropDownMenu_AddButton(zoneInfo)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, button, 0, 0)
end

--------------------------------------------------
-- Show Character Menu
--------------------------------------------------
function GoldPH_History_Filters:ShowCharMenu(button)
    if not self.charMenu then
        self.charMenu = CreateFrame("Frame", "GoldPH_CharMenu", button, "UIDropDownMenuTemplate")
    end
    local menu = self.charMenu

    -- Toggle closed if this menu is already open
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menu then
        CloseDropDownMenus()
        return
    end

    local function OnCharClick(charKey)
        if charKey then
            self.historyController.filterState.charKeys = {[charKey] = true}
            local charName = charKey:match("^([^-]+)")
            self.charDropdown.text:SetText("Char: " .. (charName or charKey))
        else
            self.historyController.filterState.charKeys = nil
            self.charDropdown.text:SetText("Char: All")
        end
        self:OnFilterChanged()
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(menu, function()
        -- Add "All" option
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Characters"
        info.func = function() OnCharClick(nil) end
        info.checked = (self.historyController.filterState.charKeys == nil)
        UIDropDownMenu_AddButton(info)

        -- Add characters
        local chars = GoldPH_Index:GetCharacters()
        for _, charKey in ipairs(chars) do
            local charInfo = UIDropDownMenu_CreateInfo()
            local charName = charKey:match("^([^-]+)")
            charInfo.text = charName or charKey
            charInfo.func = function() OnCharClick(charKey) end
            local isChecked = self.historyController.filterState.charKeys and self.historyController.filterState.charKeys[charKey]
            charInfo.checked = isChecked
            UIDropDownMenu_AddButton(charInfo)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, button, 0, 0)
end

--------------------------------------------------
-- Update Char Dropdown Label from filter state
--------------------------------------------------
function GoldPH_History_Filters:UpdateCharDropdownLabel()
    local charKeys = self.historyController.filterState.charKeys
    if not charKeys then
        self.charDropdown.text:SetText("Char: All")
        return
    end
    local count = 0
    local firstKey = nil
    for k, _ in pairs(charKeys) do
        count = count + 1
        if not firstKey then firstKey = k end
    end
    if count == 0 then
        self.charDropdown.text:SetText("Char: All")
    elseif count == 1 then
        local charName = firstKey:match("^([^-]+)")
        self.charDropdown.text:SetText("Char: " .. (charName or firstKey))
    else
        self.charDropdown.text:SetText("Char: " .. count .. " chars")
    end
end

--------------------------------------------------
-- Helper: Update Flags Button Label
--------------------------------------------------
function GoldPH_History_Filters:UpdateFlagsLabel()
    local parts = {}
    local fs = self.historyController.filterState

    if fs.hasGathering then table.insert(parts, "Gather") end
    if fs.hasPickpocket then table.insert(parts, "Pickpkt") end
    if fs.onlyXP then table.insert(parts, "XP") end
    if fs.onlyRep then table.insert(parts, "Rep") end
    if fs.onlyHonor then table.insert(parts, "Honor") end

    if #parts == 0 then
        self.flagsDropdown.text:SetText("Flags: Any")
    else
        self.flagsDropdown.text:SetText("Flags: " .. table.concat(parts, ","))
    end
end

--------------------------------------------------
-- Show Flags Menu (Gather/Pickpocket/XP/Rep/Honor)
--------------------------------------------------
function GoldPH_History_Filters:ShowFlagsMenu(button)
    if not self.flagsMenu then
        self.flagsMenu = CreateFrame("Frame", "GoldPH_FlagsMenu", button, "UIDropDownMenuTemplate")
    end
    local menu = self.flagsMenu

    -- Toggle closed if this menu is already open
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menu then
        CloseDropDownMenus()
        return
    end

    local function ToggleFlag(key)
        local fs = self.historyController.filterState
        fs[key] = not fs[key]
        self:UpdateFlagsLabel()
        self:OnFilterChanged()
        CloseDropDownMenus()
    end

    UIDropDownMenu_Initialize(menu, function()
        local fs = self.historyController.filterState

        local opts = {
            { label = "Gathering",   key = "hasGathering" },
            { label = "Pickpocket",  key = "hasPickpocket" },
            { label = "XP",          key = "onlyXP" },
            { label = "Reputation",  key = "onlyRep" },
            { label = "Honor",       key = "onlyHonor" },
        }

        for _, opt in ipairs(opts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.func = function() ToggleFlag(opt.key) end
            info.checked = fs[opt.key] and true or false
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, button, 0, 0)
end

--------------------------------------------------
-- On Search Changed (debounced)
--------------------------------------------------
function GoldPH_History_Filters:OnSearchChanged(text)
    -- Cancel existing timer if any
    if self.searchTimer then
        self.searchTimer:Cancel()
    end

    -- Start new timer with debounce delay
    self.searchTimer = C_Timer.NewTimer(self.searchDebounceDelay, function()
        self.historyController.filterState.search = text
        self:OnFilterChanged()
        self.searchTimer = nil
    end)
end

--------------------------------------------------
-- On Filter Changed (trigger refresh)
--------------------------------------------------
function GoldPH_History_Filters:OnFilterChanged()
    -- Trigger list refresh
    self.historyController:RefreshList()
end

-- Export module
_G.GoldPH_History_Filters = GoldPH_History_Filters
