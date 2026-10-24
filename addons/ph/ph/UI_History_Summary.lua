--[[
    UI_History_Summary.lua - Summary tab for the unified Session Detail

    One layout for active and archived sessions: overview + totals, per-hour rates
    with sparklines, a session activity chart, recent activity, and the detailed
    accounting sections. Widgets are built once and updated in place.
]]

-- luacheck: globals pH_Settings pH_SessionManager pH_Ledger pH_History pH_Index UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo UIDropDownMenu_AddButton ToggleDropDownMenu CloseDropDownMenus date time
local _, addon = ...
local PHUI = addon.UI.PHUI
local Panel = addon.UI.Panel
local Sparkline = addon.UI.Sparkline

local pH_History_Detail = _G.pH_History_Detail

local PAD = 8
local GAP = 8
local ROW_H = 18
local RECENT_ROWS = 8
local RATE_SPARK_MINUTES = 30

local METRICS = {
    { key = "gold", label = "Gold", chart = "Gold / Hour", icon = "Interface\\MoneyFrame\\UI-GoldIcon", color = { 1.00, 0.82, 0.00, 1 } },
    { key = "rep", label = "Reputation", chart = "Rep / Hour", icon = "Interface\\Icons\\INV_Misc_Ribbon_01", color = PHUI.Colors.ACCENT_GOOD },
    { key = "xp", label = "Experience", chart = "XP / Hour", icon = "Interface\\Icons\\INV_Misc_Book_11", color = { 0.58, 0.51, 0.79, 1 } },
    { key = "honor", label = "Honor", chart = "Honor / Hour", icon = "Interface\\Icons\\inv_bannerpvp_02", color = { 0.90, 0.60, 0.20, 1 } },
}

local KIND_STYLE = { gold = "good", expense = "bad", xp = "primary", rep = "primary", honor = "primary", gather = "muted" }

--------------------------------------------------
-- Formatting
--------------------------------------------------
local function FormatInt(value)
    local n = math.floor(tonumber(value) or 0)
    local sign = ""
    if n < 0 then
        sign = "-"
        n = -n
    end
    local s = tostring(n)
    while true do
        local replaced, count = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
        s = replaced
        if count == 0 then break end
    end
    return sign .. s
end

local function FormatRate(key, rate)
    rate = rate or 0
    if key == "gold" then
        return pH_Ledger:FormatMoneyShort(rate) .. "/hr"
    end
    if rate >= 1000 then
        return string.format("%.1fk/hr", rate / 1000)
    end
    return string.format("%d/hr", rate)
end

local function FormatTotal(key, total)
    total = total or 0
    if key == "gold" then
        return pH_Ledger:FormatMoney(total)
    end
    if total >= 10000 then
        return string.format("%.1fk", total / 1000)
    end
    return FormatInt(total)
end

local function FormatSpan(minutes)
    minutes = math.floor(minutes + 0.5)
    if minutes < 60 then
        return minutes .. "m"
    end
    return string.format("%dh%02dm", math.floor(minutes / 60), minutes % 60)
end

local function FormatActivityAmount(entry)
    local v = entry.value
    if entry.kind == "gold" then
        return "+" .. pH_Ledger:FormatMoneyShort(v or 0)
    elseif entry.kind == "expense" then
        return "-" .. pH_Ledger:FormatMoneyShort(v or 0)
    elseif entry.kind == "xp" then
        return string.format("+%s XP", FormatInt(v))
    elseif entry.kind == "rep" then
        return "+" .. FormatInt(v)
    elseif entry.kind == "honor" then
        return string.format("+%s Honor", FormatInt(v))
    end
    return ""
end

--------------------------------------------------
-- Detail sections (pure data: no frames). Mirrors the accounting breakdowns the
-- old Summary showed, so nothing is lost in the redesign.
-- Returns { { title = "...", rows = { { label, value, style }, ... } }, ... }
--------------------------------------------------
local function Money(c) return pH_Ledger:FormatMoney(c or 0) end
local function Expense(c)
    c = c or 0
    return c > 0 and ("-" .. Money(c)) or Money(c), c > 0 and "bad" or nil
end

function pH_History_Detail:BuildDetailSections(session, metrics)
    local sections = {}
    local function add(title) local s = { title = title, rows = {} }; sections[#sections + 1] = s; return s end
    local function row(s, label, value, style) s.rows[#s.rows + 1] = { label, value, style } end

    local s = add("Economic Summary")
    row(s, "Total Per Hour", pH_Ledger:FormatMoneyShort(metrics.totalPerHour) .. "/hr")
    row(s, "Gold Per Hour", pH_Ledger:FormatMoneyShort(metrics.cashPerHour) .. "/hr", "good")
    row(s, "Expected Per Hour", pH_Ledger:FormatMoneyShort(metrics.expectedPerHour) .. "/hr")

    s = add("Income / Expenses")
    row(s, "Looted Coin", Money(metrics.income))
    row(s, "Quest Rewards", Money(metrics.incomeQuest))
    row(s, "Vendor Sales", Money(pH_Ledger:GetBalance(session, "Income:VendorSales")))
    local text, style = Expense(metrics.expenseRepairs)
    row(s, "Repairs", text, style)
    text, style = Expense(metrics.expenseVendorBuys)
    row(s, "Vendor Purchases", text, style)
    text, style = Expense(metrics.expenseTravel)
    row(s, "Travel", text, style)

    s = add("Inventory Expected")
    row(s, "Vendor Trash", Money(metrics.invVendorTrash))
    row(s, "Market Items", Money(metrics.invMarketItems))
    row(s, "Gathering", Money(metrics.invGathering))
    row(s, "Enchanting", Money(metrics.invEnchanting))

    -- Gold by source (same categories the old gold focus panel listed)
    if metrics.totalValue and metrics.totalValue > 0 then
        local bal = function(a) return pH_Ledger:GetBalance(session, a) or 0 end
        local pickpocket = bal("Income:Pickpocket:Coin") + bal("Income:Pickpocket:Items")
            + bal("Income:Pickpocket:FromLockbox:Coin") + bal("Income:Pickpocket:FromLockbox:Items")
        local categories = {
            { "Raw Gold", bal("Income:LootedCoin") },
            { "Quest Rewards", bal("Income:Quest") },
            { "Vendor Sales", bal("Income:VendorSales") },
            { "Vendor Trash", bal("Income:ItemsLooted:VendorTrash") },
            { "Market Items", bal("Income:ItemsLooted:MarketItems") },
            { "Gathering", bal("Income:ItemsLooted:Gathering") },
            { "Enchanting", bal("Income:ItemsLooted:Enchanting") },
            { "Pickpocketing", pickpocket },
        }
        local total = 0
        for _, c in ipairs(categories) do total = total + c[2] end
        local hours = metrics.durationHours
        if not hours or hours == 0 then hours = 1 end
        s = add("Gold by Source")
        for _, c in ipairs(categories) do
            if c[2] > 0 then
                local pct = total > 0 and math.floor(c[2] / total * 100) or 0
                row(s, c[1], string.format("%s  ·  %s/hr  ·  %d%%", Money(c[2]),
                    pH_Ledger:FormatMoneyShort(math.floor(c[2] / hours)), pct))
            end
        end
    end

    if session.pickpocket and ((metrics.pickpocketGold or 0) > 0 or (metrics.pickpocketValue or 0) > 0) then
        s = add("Pickpocket")
        row(s, "Coin", Money(metrics.pickpocketGold))
        row(s, "Items Value", Money(metrics.pickpocketValue))
        row(s, "Lockboxes Looted", tostring(metrics.lockboxesLooted or 0))
        row(s, "Lockboxes Opened", tostring(metrics.lockboxesOpened or 0))
        if (metrics.fromLockboxGold or 0) > 0 or (metrics.fromLockboxValue or 0) > 0 then
            row(s, "From Lockbox Coin", Money(metrics.fromLockboxGold))
            row(s, "From Lockbox Items", Money(metrics.fromLockboxValue))
        end
    end

    if session.gathering and (session.gathering.totalNodes or 0) > 0 then
        s = add("Gathering")
        row(s, "Total Nodes", tostring(session.gathering.totalNodes))
        local perHour = 0
        if (metrics.durationHours or 0) > 0 then
            perHour = math.floor(session.gathering.totalNodes / metrics.durationHours)
        end
        row(s, "Nodes Per Hour", tostring(perHour))
    end

    if metrics.xpEnabled and (metrics.xpGained or 0) > 0 then
        s = add("Experience")
        local src = metrics.xpBySource or {}
        row(s, "XP Gained", FormatInt(metrics.xpGained))
        row(s, "XP Per Hour", FormatInt(metrics.xpPerHour) .. "/hr")
        row(s, "Mob XP", FormatInt(tonumber(src.mob) or 0))
        row(s, "Quest XP", FormatInt(tonumber(src.quest) or 0))
        if (tonumber(src.other) or 0) > 0 then
            row(s, "Other XP", FormatInt(src.other))
        end
        row(s, "Quests Completed", FormatInt(metrics.xpQuestsCompleted or 0))
        local kills = {}
        for name, n in pairs(metrics.xpMobKillsByType or {}) do
            n = tonumber(n) or 0
            if n > 0 then kills[#kills + 1] = { name = tostring(name), count = n } end
        end
        table.sort(kills, function(a, b)
            if a.count == b.count then return a.name < b.name end
            return a.count > b.count
        end)
        for i = 1, math.min(5, #kills) do
            row(s, "  " .. kills[i].name, "x" .. FormatInt(kills[i].count), "muted")
        end
    end

    if metrics.repEnabled and (metrics.repGained or 0) > 0 then
        s = add("Reputation")
        row(s, "Rep Gained", FormatInt(metrics.repGained))
        row(s, "Rep Per Hour", FormatInt(metrics.repPerHour) .. "/hr")
        for _, f in ipairs(metrics.repTopFactions or {}) do
            row(s, "  " .. f.name, string.format("+%d", f.gain), "muted")
        end
    end

    if metrics.honorEnabled and (metrics.honorGained or 0) > 0 then
        s = add("Honor")
        row(s, "Honor Gained", FormatInt(metrics.honorGained))
        row(s, "Honor Per Hour", FormatInt(metrics.honorPerHour) .. "/hr")
        if (metrics.honorKills or 0) > 0 then
            row(s, "Honorable Kills", tostring(metrics.honorKills))
        end
    end

    return sections
end

--------------------------------------------------
-- Widgets (built once)
--------------------------------------------------
local function IconLabelRow(parent, texture)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.icon:SetTexture(texture)
    r.text = PHUI.CreateLabel(r, "primary", "", PHUI.Fonts.NORMAL)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    return r
end

function pH_History_Detail:EnsureSummaryUI()
    if self.summaryUI then return self.summaryUI end
    local scrollChild = self.contentFrames.summary.scrollChild
    local ui = { selectedMetric = "gold", sections = {} }
    self.summaryUI = ui

    -- Session Overview
    ui.overview = Panel:Create(scrollChild, { title = "Session Overview" })
    ui.overview:SetHeight(112)
    ui.overviewRows = {}
    for i, label in ipairs({ "Status", "Started", "Elapsed", "Location" }) do
        local r = Panel:CreateRow(ui.overview.body, label, "")
        r:SetPoint("TOPLEFT", ui.overview.body, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", ui.overview.body, "TOPRIGHT", 0, -(i - 1) * ROW_H)
        ui.overviewRows[label] = r
    end

    -- Totals
    ui.totals = Panel:Create(scrollChild, { title = "Totals" })
    ui.totals:SetHeight(112)
    ui.totalRows = {}
    for i, m in ipairs(METRICS) do
        local r = IconLabelRow(ui.totals.body, m.icon)
        r:SetPoint("TOPLEFT", ui.totals.body, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", ui.totals.body, "TOPRIGHT", 0, -(i - 1) * ROW_H)
        ui.totalRows[m.key] = r
    end

    -- Rates (per hour)
    ui.rates = Panel:Create(scrollChild, { title = "Rates (per hour)" })
    ui.rates:SetHeight(86)
    ui.rateCells = {}
    ui.rateDividers = {}
    for i, m in ipairs(METRICS) do
        local cell = CreateFrame("Button", nil, ui.rates.body)
        cell:SetScript("OnClick", function()
            ui.selectedMetric = m.key
            pH_History_Detail:UpdateSummary()
        end)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(14, 14)
        cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
        cell.icon:SetTexture(m.icon)
        cell.text = PHUI.CreateLabel(cell, "primary", "", PHUI.Fonts.NORMAL)
        cell.text:SetPoint("LEFT", cell.icon, "RIGHT", 4, 0)
        cell.spark = Sparkline:Create(cell, { width = 60, height = 28, color = m.color })
        cell.spark:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -22)
        ui.rateCells[m.key] = cell
        if i < #METRICS then
            ui.rateDividers[i] = Panel:CreateDivider(ui.rates.body, "vertical")
        end
    end

    -- Session Activity chart
    ui.activity = Panel:Create(scrollChild, { title = "Session Activity" })
    ui.activity:SetHeight(170)
    ui.metricMenu = CreateFrame("Frame", "pH_SummaryMetricMenu", ui.activity, "UIDropDownMenuTemplate")
    ui.metricBtn = Panel:CreateButton(ui.activity, "Gold / Hour  v", { width = 110, height = 20 })
    ui.metricBtn:SetPoint("TOPRIGHT", ui.activity, "TOPRIGHT", -PAD, -PAD + 2)
    ui.metricBtn:SetScript("OnClick", function(button)
        UIDropDownMenu_Initialize(ui.metricMenu, function()
            for _, m in ipairs(METRICS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = m.chart
                info.checked = (ui.selectedMetric == m.key)
                info.func = function()
                    ui.selectedMetric = m.key
                    pH_History_Detail:UpdateSummary()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, ui.metricMenu, button, 0, 0)
    end)
    ui.chart = Sparkline:Create(ui.activity.body, { width = 200, height = 90, maxPoints = 90 })
    ui.chart:SetPoint("TOPLEFT", ui.activity.body, "TOPLEFT", 0, -4)
    ui.chartPeak = PHUI.CreateLabel(ui.activity.body, "muted", "", PHUI.Fonts.SMALL)
    ui.chartPeak:SetPoint("LEFT", ui.activity.title, "RIGHT", 10, 0)
    ui.chartEmpty = PHUI.CreateLabel(ui.activity.body, "muted", "Not enough samples yet", PHUI.Fonts.SMALL)
    ui.chartEmpty:SetPoint("CENTER", ui.chart, "CENTER", 0, 0)
    ui.axis = {}
    for i = 1, 5 do
        ui.axis[i] = PHUI.CreateLabel(ui.activity.body, "muted", "", PHUI.Fonts.SMALL)
    end

    -- Recent Activity
    ui.recent = Panel:Create(scrollChild, { title = "Recent Activity" })
    ui.recentRows = {}
    for i = 1, RECENT_ROWS do
        local r = CreateFrame("Frame", nil, ui.recent.body)
        r:SetHeight(ROW_H - 2)
        r:SetPoint("TOPLEFT", ui.recent.body, "TOPLEFT", 0, -(i - 1) * (ROW_H - 2))
        r:SetPoint("TOPRIGHT", ui.recent.body, "TOPRIGHT", 0, -(i - 1) * (ROW_H - 2))
        r.time = PHUI.CreateLabel(r, "muted", "", PHUI.Fonts.SMALL)
        r.time:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.amount = PHUI.CreateLabel(r, "primary", "", PHUI.Fonts.SMALL)
        r.amount:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.amount:SetJustifyH("RIGHT")
        r.text = PHUI.CreateLabel(r, "primary", "", PHUI.Fonts.SMALL)
        r.text:SetPoint("LEFT", r, "LEFT", 44, 0)
        r.text:SetPoint("RIGHT", r.amount, "LEFT", -8, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        ui.recentRows[i] = r
    end
    ui.recentEmpty = PHUI.CreateLabel(ui.recent.body, "muted", "No activity recorded for this session", PHUI.Fonts.SMALL)
    ui.recentEmpty:SetPoint("TOPLEFT", ui.recent.body, "TOPLEFT", 0, 0)

    return ui
end

local function EnsureSection(ui, index, parent)
    local sec = ui.sections[index]
    if sec then return sec end
    sec = Panel:Create(parent, { title = "" })
    sec.rows = {}
    ui.sections[index] = sec
    return sec
end

local function EnsureSectionRow(sec, index)
    local r = sec.rows[index]
    if r then return r end
    r = Panel:CreateRow(sec.body, "", "")
    r:SetPoint("TOPLEFT", sec.body, "TOPLEFT", 0, -(index - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", sec.body, "TOPRIGHT", 0, -(index - 1) * ROW_H)
    sec.rows[index] = r
    return r
end

--------------------------------------------------
-- Layout (depends on width) and update (depends on data)
--------------------------------------------------
function pH_History_Detail:LayoutSummary()
    local ui = self.summaryUI
    if not ui then return end
    local scrollChild = self.contentFrames.summary.scrollChild
    local width = scrollChild:GetWidth()
    if not width or width <= 0 then return end
    local inner = width - 2 * PAD

    local leftW = math.floor((inner - GAP) * 0.58)
    ui.overview:ClearAllPoints()
    ui.overview:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -PAD)
    ui.overview:SetWidth(leftW)
    ui.totals:ClearAllPoints()
    ui.totals:SetPoint("TOPLEFT", ui.overview, "TOPRIGHT", GAP, 0)
    ui.totals:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -PAD)

    local y = PAD + ui.overview:GetHeight() + GAP
    local function place(panel)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y)
        panel:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y)
        y = y + panel:GetHeight() + GAP
    end
    place(ui.rates)
    place(ui.activity)
    place(ui.recent)
    for _, sec in ipairs(ui.sections) do
        if sec:IsShown() then place(sec) end
    end
    scrollChild:SetHeight(y + PAD)

    -- Rates cells: four equal columns
    local bodyW = width - 2 * PAD - 2 * PAD
    local cellW = math.floor(bodyW / #METRICS)
    for i, m in ipairs(METRICS) do
        local cell = ui.rateCells[m.key]
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", ui.rates.body, "TOPLEFT", (i - 1) * cellW, 0)
        cell:SetSize(cellW - 8, 50)
        cell.spark:SetWidth(math.max(20, cellW - 14))
        if ui.rateDividers[i] then
            ui.rateDividers[i]:ClearAllPoints()
            ui.rateDividers[i]:SetPoint("TOPLEFT", ui.rates.body, "TOPLEFT", i * cellW - 4, 0)
            ui.rateDividers[i]:SetPoint("BOTTOMLEFT", ui.rates.body, "TOPLEFT", i * cellW - 4, -50)
        end
    end

    ui.chart:SetWidth(math.max(40, bodyW))

    -- Axis labels evenly across the chart
    for i, label in ipairs(ui.axis) do
        label:ClearAllPoints()
        local frac = (i - 1) / (#ui.axis - 1)
        if i == 1 then
            label:SetPoint("TOPLEFT", ui.chart, "BOTTOMLEFT", 0, -4)       -- flush left, inside the panel
        elseif i == #ui.axis then
            label:SetPoint("TOPRIGHT", ui.chart, "BOTTOMRIGHT", 0, -4)     -- flush right
        else
            label:SetPoint("TOP", ui.chart, "BOTTOMLEFT", frac * ui.chart:GetWidth(), -4)
        end
    end
end

function pH_History_Detail:UpdateSummaryClock()
    local ui = self.summaryUI
    if not ui or not self.currentSession or not self.currentMetrics then return end
    ui.overviewRows.Elapsed:SetValue(pH_SessionManager:FormatDuration(self.currentMetrics.durationSec))
end

function pH_History_Detail:UpdateSummary()
    local ui = self:EnsureSummaryUI()
    local session, metrics = self.currentSession, self.currentMetrics
    if not session or not metrics then return end

    local active = (self.mode == "active")

    -- The empty-state render hides everything under the scroll child; undo that.
    if self.contentFrames.summary.scrollChild.emptyText then
        self.contentFrames.summary.scrollChild.emptyText:Hide()
    end
    for _, panel in ipairs({ ui.overview, ui.totals, ui.rates, ui.activity, ui.recent }) do
        panel:Show()
    end
    self:LayoutSummary()  -- sets widths the sparklines draw against

    -- Overview
    local status, style = "Completed", "muted"
    if active then
        if session.pausedAt then status, style = "Paused", "warning" else status, style = "Running", "good" end
    end
    ui.overviewRows.Status:SetValue(status, style)
    ui.overviewRows.Started:SetValue(date("%b %d, %Y %H:%M", session.startedAt or time()))
    ui.overviewRows.Elapsed:SetValue(pH_SessionManager:FormatDuration(metrics.durationSec))
    ui.overviewRows.Location:SetValue(session.zone or "Unknown")
    -- Totals and rates
    local data = {
        gold = { rate = metrics.totalPerHour, total = metrics.totalValue },
        rep = { rate = metrics.repPerHour, total = metrics.repGained },
        xp = { rate = metrics.xpPerHour, total = metrics.xpGained },
        honor = { rate = metrics.honorPerHour, total = metrics.honorGained },
    }
    for _, m in ipairs(METRICS) do
        local d = data[m.key]
        ui.totalRows[m.key].text:SetText(FormatTotal(m.key, d.total))
        local cell = ui.rateCells[m.key]
        cell.text:SetText(FormatRate(m.key, d.rate))
        local series = pH_SessionManager:GetMetricSeries(session, m.key, RATE_SPARK_MINUTES)
        cell.spark:SetValues(series)
    end

    -- Activity chart
    local sel
    for _, m in ipairs(METRICS) do
        if m.key == ui.selectedMetric then sel = m end
    end
    sel = sel or METRICS[1]
    ui.metricBtn:SetText(sel.chart .. "  v")
    local series, interval = pH_SessionManager:GetMetricSeries(session, sel.key)
    ui.chart:SetColor(sel.color)
    ui.chart:SetValues(series)
    local hasData = #series >= 2
    ui.chartEmpty:SetShown(not hasData)
    local peak = 0
    for _, v in ipairs(series) do if v > peak then peak = v end end
    ui.chartPeak:SetText(hasData and ("Peak " .. FormatRate(sel.key, peak)) or "")
    local spanMin = (#series * interval) / 60
    for i, label in ipairs(ui.axis) do
        label:SetText(hasData and FormatSpan(spanMin * (i - 1) / (#ui.axis - 1)) or "")
    end

    -- Recent activity (newest first)
    local log = session.activityLog or {}
    for i = 1, RECENT_ROWS do
        local r = ui.recentRows[i]
        local entry = log[#log - i + 1]
        if entry then
            r.time:SetText(date("%H:%M", entry.t))
            r.text:SetText(entry.text)
            r.amount:SetText(FormatActivityAmount(entry))
            PHUI.ApplyTextStyle(r.amount, KIND_STYLE[entry.kind] or "primary")
            r:Show()
        else
            r:Hide()
        end
    end
    ui.recentEmpty:SetShown(#log == 0)
    local shown = math.max(1, math.min(RECENT_ROWS, #log))
    ui.recent:SetHeight(PAD * 2 + 18 + shown * (ROW_H - 2) + 2)

    -- Detail sections
    local sections = self:BuildDetailSections(session, metrics)
    for i, sec in ipairs(sections) do
        local panel = EnsureSection(ui, i, self.contentFrames.summary.scrollChild)
        panel.title:SetText(sec.title)
        for j, rowData in ipairs(sec.rows) do
            local r = EnsureSectionRow(panel, j)
            r.label:SetText(rowData[1])
            r:SetValue(rowData[2], rowData[3] or "primary")
            r:Show()
        end
        for j = #sec.rows + 1, #panel.rows do panel.rows[j]:Hide() end
        panel:SetHeight(PAD * 2 + 18 + #sec.rows * ROW_H)
        panel:Show()
    end
    for i = #sections + 1, #ui.sections do ui.sections[i]:Hide() end

    self:LayoutSummary()
end

function pH_History_Detail:RenderSummaryTab()
    self:UpdateSummary()
end

-- Open the Summary tab with `metricKey` ("gold" | "xp" | "rep" | "honor") on the activity chart.
function pH_History_Detail:SelectMetric(metricKey)
    local ui = self:EnsureSummaryUI()
    ui.selectedMetric = metricKey
    if self.activeTab == "summary" then
        self:UpdateSummary()
    else
        self:SwitchTab("summary")  -- renders the summary with the new selection
    end
end
