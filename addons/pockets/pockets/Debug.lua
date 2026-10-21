--[[
    Debug.lua - Debug and diagnostic infrastructure for Pockets (TDD §23)

    Provides /pockets debug ... inspection commands and /pockets test ...
    injection commands so domain logic can be exercised without performing
    every game action manually.
]]

-- luacheck: globals PocketsCharDB C_Texture

local _, Pockets = ...

Pockets.Debug = Pockets.Debug or {}
local Debug = Pockets.Debug

local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff0000"
local COLOR_YELLOW = "|cffffff00"
local COLOR_RESET = "|r"

function Debug:IsVerbose()
    return Pockets.CharDB and Pockets.CharDB.debug and Pockets.CharDB.debug.verbose
end

function Debug:Log(message)
    if self:IsVerbose() then
        print(COLOR_YELLOW .. "[Pockets Debug] " .. COLOR_RESET .. message)
    end
end

function Debug:LogError(message)
    print(COLOR_RED .. "[Pockets Error] " .. COLOR_RESET .. message)
    -- Keep the last few errors in SavedVariables so they can be read from
    -- disk after /reload (PocketsDB.errorLog), not just seen in chat.
    if _G.PocketsDB then
        local log = _G.PocketsDB.errorLog or {}
        table.insert(log, tostring(message))
        while #log > 20 do table.remove(log, 1) end
        _G.PocketsDB.errorLog = log
    end
end

--------------------------------------------------
-- Inspection commands
--------------------------------------------------

function Debug:DumpInventory()
    print(COLOR_YELLOW .. "=== Pockets Inventory ===" .. COLOR_RESET)
    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    local ammo = Pockets.Services.InventoryState:GetAmmoCapacity()
    print(string.format("  Bags: %d/%d (%.1f%%)", capacity.used, capacity.total, capacity.utilization * 100))
    print(string.format("  Ammo: %d/%d", ammo.used, ammo.total))

    for key, item in pairs(Pockets.Services.InventoryState:GetItems()) do
        print(string.format("  [%s] %s x%s (%s)", tostring(key), item.name or ("item:" .. tostring(item.itemID)),
            tostring(item.quantity), tostring(item.categoryID)))
    end
    print(COLOR_YELLOW .. "==========================" .. COLOR_RESET)
end

function Debug:DumpCategories()
    print(COLOR_YELLOW .. "=== Pockets Categories ===" .. COLOR_RESET)
    for _, entry in ipairs(Pockets.API.GetCategorySummary()) do
        print(string.format("  %-14s %d", entry.label, entry.count))
    end
    print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
end

function Debug:DumpEstimator()
    local estimator = Pockets.Services.CapacityEstimator
    print(COLOR_YELLOW .. "=== Pockets Capacity Estimator ===" .. COLOR_RESET)
    print(string.format("  State: %s", estimator:GetState()))
    print(string.format("  Rate: %s slots/min", tostring(estimator:GetRate())))
    print(string.format("  ETA: %s seconds", tostring(estimator:GetETA())))
    print(string.format("  Confidence: %.2f", estimator:GetConfidence()))
    print(string.format("  Samples: %d", #estimator.samples))
    print(COLOR_YELLOW .. "===================================" .. COLOR_RESET)
end

-- Per-equipped-bag diagnostic dump (Ammo detection debugging pass §7):
-- itemID, name, GetItemFamily() bitmask, slot occupancy, and how Pockets
-- classified the bag - so a mis-detection can be diagnosed from actual
-- runtime values instead of guessed at.
function Debug:DumpBags()
    print(COLOR_YELLOW .. "=== Pockets Equipped Bags ===" .. COLOR_RESET)
    local BagAPI = Pockets.Adapters.BagAPI
    print(string.format("  reagentBagID=%s scannedBagIDs=%s", tostring(BagAPI:GetReagentBagID()),
        table.concat(BagAPI:GetScannedBagIDs(), ",")))
    for _, bag in ipairs(BagAPI:GetEquippedBags()) do
        local invSlot = BagAPI:ContainerIDToInventoryID(bag.bagID)
        local bagLink = invSlot and GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
        local bagName = bagLink and Pockets.Adapters.ItemAPI:RawGetItemInfo(bagLink)
        local bagFamily = bagLink and Pockets.Adapters.ItemAPI:GetItemFamily(bagLink)
        local used = BagAPI:CountUsedSlots(bag.bagID, bag.slotCount)
        local bagClass = BagAPI:GetBagClass(bag.bagID)
        local classID, subClassID = Pockets.Adapters.ItemAPI:GetInstantClass(bagLink)
        print(string.format(
            "  bag %d: %s | family=%s | itemClass=%s/%s | slots=%d/%d | class=%s",
            bag.bagID, tostring(bagName or "(backpack/none)"), tostring(bagFamily),
            tostring(classID), tostring(subClassID), used, bag.slotCount, tostring(bagClass or "general")))
    end
    print(COLOR_YELLOW .. "==============================" .. COLOR_RESET)
end

-- Right-click use/equip/disenchant-target diagnostic: dumps every
-- currently-active pooled item button's bagID/slotID/interactive flag
-- alongside the REAL bagIndexFrame:GetID()/button:GetID() values
-- ContainerFrameItemButtonTemplate's own inherited OnClick resolves bag/
-- slot from - so "right-click doesn't work" can be diagnosed from actual
-- runtime values instead of guessed at. Existing as a slash command (not
-- an ad-hoc /run) specifically because a long inline /run script can
-- exceed the chat edit box's line-length limit.
-- Client/adapter diagnostic (Forever M3 §22): which client, which adapter
-- paths are live, and whether tooltip/binding integration took.
function Debug:DumpClient()
    local C = Pockets.Adapters.ClientAPI
    local T = Pockets.Adapters.TooltipAPI
    print(COLOR_YELLOW .. "=== Pockets Client ===" .. COLOR_RESET)
    print(string.format("  client=%s interface=%s build=%s", C:GetClientType(),
        tostring(C:GetInterfaceNumber()), tostring(GetBuildInfo and select(2, GetBuildInfo()))))
    print(string.format("  tooltip: supported=%s mode=%s modernPipeline=%s", tostring(T.supported),
        tostring(T.mode), tostring(T:HasModernPipeline())))
    print(string.format("  binding SHIFT-B action key=%s", tostring(GetBindingKey and GetBindingKey("POCKETS_TOGGLE_FULL_INVENTORY"))))
    print(string.format("  C_Container=%s C_Item=%s issecretvalue=%s", tostring(C_Container ~= nil),
        tostring(C_Item ~= nil), tostring(issecretvalue ~= nil)))
end

function Debug:DumpShell()
    local Shell = Pockets.UI.Shell
    local Pool = Pockets.UI.ItemButtonPool
    print(COLOR_YELLOW .. "=== Pockets Shell ===" .. COLOR_RESET)
    print(string.format("  state=%s laidOut=%s displayed=%s expandedVisible=%s deferred=%s",
        tostring(Shell.state), tostring(Shell.laidOutState), tostring(Shell.displayedState),
        tostring(Shell.expandedVisible), tostring(Shell.renderDeferred)))
    print(string.format("  root shown=%s expanded shown=%s templateProtected=%s blocked=%s prewarmPending=%s",
        tostring(Shell.root:IsShown()), tostring(Shell.expanded:IsShown()),
        tostring(Pool.templateProtected), tostring(Shell:IsCombatBlocked()), tostring(Shell.prewarmPending)))
end

function Debug:DumpSecureButtons()
    print(COLOR_YELLOW .. "=== Pockets Item Buttons ===" .. COLOR_RESET)
    print(string.format("  CursorHasItem: %s", tostring(CursorHasItem and CursorHasItem())))
    print(string.format("  templateProtected=%s inCombat=%s dirty=%s",
        tostring(Pockets.UI.ItemButtonPool.templateProtected),
        tostring(Pockets.Adapters.CombatAPI:IsInCombat()),
        tostring(Pockets.UI.ItemButtonPool.dirty)))
    local count = 0
    for _, pool in pairs(Pockets.UI.ItemButtonPool.pools) do
        for _, button in ipairs(pool.active) do
            count = count + 1
            print(string.format(
                "  #%d bagID=%s slotID=%s interactive=%s resolvedBagID=%s resolvedSlotID=%s secure=%s:%s item=%s valid=%s protected=%s type2=%s",
                count, tostring(button.bagID), tostring(button.slotID), tostring(button.interactive),
                tostring(button.bagIndexFrame and button.bagIndexFrame:GetID()), tostring(button:GetID()),
                tostring(button.secureBagID), tostring(button.secureSlotID), tostring(button.secureItemID),
                tostring(button.secureBindingValid), tostring(button.IsProtected and button:IsProtected()),
                tostring(button.GetAttribute and button:GetAttribute("type2"))))
            print(string.format("     item2=%s useOnKeyDown=%s OnClickIsSecure=%s",
                tostring(button.GetAttribute and button:GetAttribute("item2")),
                tostring(button.GetAttribute and button:GetAttribute("useOnKeyDown")),
                tostring(SecureActionButton_OnClick ~= nil and button:GetScript("OnClick") == SecureActionButton_OnClick)))
        end
    end
    if count == 0 then
        print("  (no active item buttons found - open a category, All Items, or Recent items first)")
    end
    print(COLOR_YELLOW .. "====================================" .. COLOR_RESET)
end

-- Enumerates every visual region (Texture/FontString) a pooled item
-- button actually has, with real name/type/shown/size - so an unwanted
-- decoration (e.g. ContainerFrameItemButtonTemplate's glow/overlay
-- textures Pockets doesn't manage) can be identified from real runtime
-- data instead of guessed at by field name.
function Debug:DumpButtonRegions()
    local target
    for _, pool in pairs(Pockets.UI.ItemButtonPool.pools) do
        target = target or pool.active[1]
    end

    if not target then
        print("[Pockets] No active item buttons found - open a category, All Items, or Recent items first")
        return
    end

    -- region:GetName() only reports a GLOBAL frame name, which most of
    -- ContainerFrameItemButtonTemplate's sub-regions don't have. Cross-
    -- reference each region against the button's OWN Lua fields so we
    -- get the actual key (e.g. "IconBorder", "NewItemTexture") - what's
    -- actually needed to write button.<Field>:Hide().
    local fieldNameByRegion = {}
    for key, value in pairs(target) do
        if type(value) == "table" and value.GetObjectType then
            fieldNameByRegion[value] = key
        end
    end

    print(COLOR_YELLOW .. "=== Pockets Button Regions ===" .. COLOR_RESET)
    local regions = { target:GetRegions() }
    for i, region in ipairs(regions) do
        local w, h = region:GetSize()
        print(string.format(
            "  #%d field=%s type=%s shown=%s size=%.0fx%.0f",
            i, tostring(fieldNameByRegion[region]), tostring(region:GetObjectType()),
            tostring(region:IsShown()), w or -1, h or -1))
    end
    print(COLOR_YELLOW .. "===============================" .. COLOR_RESET)
end

-- Read-only dump of the native portrait template already built for Glance
-- (Shell.root.chrome): its frames/regions with atlas or texture, size and
-- anchor, to find which piece draws the circular border. Creates nothing.
function Debug:DumpPortrait()
    local chrome = Pockets.UI.Shell and Pockets.UI.Shell.root and Pockets.UI.Shell.root.chrome
    if not chrome then
        print("[Pockets] No native portrait chrome on this client")
        return
    end
    -- Also saved to PocketsDB.debugPortrait so it can be read from the
    -- SavedVariables file after /reload (chat can't be copied).
    local lines = {}
    local function out(line)
        table.insert(lines, line)
        print(line)
    end
    local function describe(obj, indent, key)
        local w, h = obj:GetSize()
        local extra = ""
        if obj.GetAtlas and obj:GetAtlas() then
            extra = " atlas=" .. tostring(obj:GetAtlas())
        elseif obj.GetTexture and obj:GetTexture() then
            extra = " tex=" .. tostring(obj:GetTexture())
        end
        local point, _, relPoint, x, y = obj:GetPoint(1)
        -- Stacking info: frames report strata + level; textures their draw
        -- layer and (for regions) the parent frame's level.
        local stack = ""
        if obj.GetFrameLevel then
            stack = string.format(" strata=%s level=%s", tostring(obj:GetFrameStrata()), tostring(obj:GetFrameLevel()))
        elseif obj.GetDrawLayer then
            local layer, sub = obj:GetDrawLayer()
            local parent = obj:GetParent()
            stack = string.format(" layer=%s/%s parentLevel=%s", tostring(layer), tostring(sub),
                tostring(parent and parent.GetFrameLevel and parent:GetFrameLevel()))
        end
        out(string.format("%s%s [%s] shown=%s %.0fx%.0f pt=%s/%s %.0f,%.0f%s%s", indent, tostring(key),
            tostring(obj:GetObjectType()), tostring(obj:IsShown()), w or -1, h or -1,
            tostring(point), tostring(relPoint), x or 0, y or 0, extra, stack))
    end
    local function dump(frame, indent, depth)
        local names = {}
        for k, v in pairs(frame) do
            if type(v) == "table" and v.GetObjectType then
                names[v] = k
            end
        end
        for _, region in ipairs({ frame:GetRegions() }) do
            describe(region, indent, names[region] or "?")
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            describe(child, indent, names[child] or "?")
            if depth > 0 then
                dump(child, indent .. "    ", depth - 1)
            end
        end
    end
    print(COLOR_YELLOW .. "=== Pockets Portrait Template ===" .. COLOR_RESET)
    local Shell = Pockets.UI.Shell
    describe(Shell.root, "  ", "ROOT")
    describe(chrome, "  ", "CHROME")
    describe(Shell.root.glance, "  ", "GLANCE")
    describe(Shell.root.glance.header, "  ", "GLANCE.header")
    dump(chrome, "  ", 2)
    PocketsDB.debugPortrait = lines
    print(COLOR_YELLOW .. "=================================" .. COLOR_RESET)
    print("[Pockets] Saved to PocketsDB.debugPortrait - /reload to write it to disk.")
end

-- Draws the native portrait-ring atlas at 3x in the screen centre with a
-- 10-native-pixel grid (every 5th line brighter), so the circle's position
-- inside the 95x95 art can be measured from a screenshot. Toggle with the
-- same command. Also saves the atlas info to PocketsDB.debugRing.
function Debug:ToggleRingView()
    local ATLAS = "UI-Frame-PortraitMetal-CornerTopLeft"
    if self.ringView then
        self.ringView:SetShown(not self.ringView:IsShown())
        return
    end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ATLAS)
    local saved = {}
    if info then
        for k, v in pairs(info) do
            saved[#saved + 1] = tostring(k) .. "=" .. tostring(v)
        end
        table.sort(saved)
    else
        saved[1] = "no atlas info"
    end
    PocketsDB.debugRing = saved

    local scale = 3
    local frame = CreateFrame("Frame", "PocketsRingView", UIParent)
    frame:SetSize(95 * scale, 95 * scale)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.2, 0.25, 0.3, 1)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(frame)
    tex:SetAtlas(ATLAS)
    for i = 0, 95, 10 do
        local strong = i % 50 == 0
        local v = frame:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(1, strong and 0.2 or 1, strong and 0.2 or 0, strong and 0.9 or 0.35)
        v:SetSize(1, 95 * scale)
        v:SetPoint("TOPLEFT", frame, "TOPLEFT", i * scale, 0)
        local h = frame:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(1, strong and 0.2 or 1, strong and 0.2 or 0, strong and 0.9 or 0.35)
        h:SetSize(95 * scale, 1)
        h:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -i * scale)
    end
    self.ringView = frame
    print("[Pockets] Ring view shown (grid = 10 native px; red = 0/50). Run again to hide. /reload to save atlas info.")
end

function Debug:DumpEvents()
    print(COLOR_YELLOW .. "=== Pockets EventBus Subscribers ===" .. COLOR_RESET)
    for eventName, list in pairs(Pockets.Services.EventBus.subscribers) do
        print(string.format("  %s: %d subscriber(s)", eventName, #list))
    end
    print(COLOR_YELLOW .. "=====================================" .. COLOR_RESET)
end

function Debug:HandleCommand(args)
    local subCmd = (args[2] or ""):lower()
    if subCmd == "on" then
        Pockets.CharDB.debug.enabled = true
        print("[Pockets] Debug mode enabled")
    elseif subCmd == "off" then
        Pockets.CharDB.debug.enabled = false
        print("[Pockets] Debug mode disabled")
    elseif subCmd == "verbose" then
        local setting = (args[3] or ""):lower()
        if setting == "on" then
            Pockets.CharDB.debug.verbose = true
            print("[Pockets] Verbose logging enabled")
        elseif setting == "off" then
            Pockets.CharDB.debug.verbose = false
            print("[Pockets] Verbose logging disabled")
        else
            print("[Pockets] Usage: /pockets debug verbose on|off")
        end
    elseif subCmd == "inventory" then
        self:DumpInventory()
    elseif subCmd == "categories" then
        self:DumpCategories()
    elseif subCmd == "estimator" then
        self:DumpEstimator()
    elseif subCmd == "events" then
        self:DumpEvents()
    elseif subCmd == "bags" then
        self:DumpBags()
    elseif subCmd == "secure" then
        self:DumpSecureButtons()
    elseif subCmd == "tooltip" then
        local on = (args[3] or ""):lower() == "on"
        PocketsDB.settings.modernTooltips = on
        print("[Pockets] modernTooltips=" .. tostring(on) .. " (applies after /reload)")
    elseif subCmd == "shell" then
        self:DumpShell()
    elseif subCmd == "client" then
        self:DumpClient()
    elseif subCmd == "regions" then
        self:DumpButtonRegions()
    elseif subCmd == "portrait" then
        self:DumpPortrait()
    elseif subCmd == "ring" then
        self:ToggleRingView()
    else
        print("[Pockets] Debug commands: on, off, verbose, inventory, categories, estimator, events, bags, secure, client, shell, regions, portrait, ring")
    end
end

--------------------------------------------------
-- Test injection commands (TDD §23)
--------------------------------------------------

function Debug:HandleTestCommand(args)
    local subCmd = (args[2] or ""):lower()

    if subCmd == "run" then
        self:RunTests()
    elseif subCmd == "sample" then
        local used = tonumber(args[3])
        local total = tonumber(args[4])
        local secondsAgo = tonumber(args[5]) or 0
        if not used or not total then
            print("[Pockets] Usage: /pockets test sample <used> <total> <secondsAgo>")
        else
            Pockets.Services.CapacityEstimator:AddSample(GetTime() - secondsAgo, used, total)
            print(string.format("[Pockets] Injected sample used=%d total=%d secondsAgo=%d", used, total, secondsAgo))
        end
    elseif subCmd == "category" then
        local itemID = tonumber(args[3])
        if not itemID then
            print("[Pockets] Usage: /pockets test category <itemID>")
        else
            local meta = Pockets.Adapters.ItemAPI:GetItemMetadata(itemID)
            local category = Pockets.Services.ItemCategorizer:Categorize(meta and {
                itemID = itemID,
                classID = meta.classID,
                subclassID = meta.subclassID,
                quality = meta.quality,
            } or { itemID = itemID })
            print(string.format("[Pockets] item %d -> category %s", itemID, category))
        end
    elseif subCmd == "recent" then
        local itemID = tonumber(args[3])
        local quantity = tonumber(args[4]) or 1
        if not itemID then
            print("[Pockets] Usage: /pockets test recent <itemID> <quantity>")
        else
            Pockets.Services.RecentItems:Record({ itemID = itemID, quantity = quantity, timestamp = GetTime() })
            print(string.format("[Pockets] Recorded recent item %d x%d", itemID, quantity))
        end
    elseif subCmd == "loot" then
        local kind = args[3]
        if kind == "item" and tonumber(args[4]) then
            local itemID, quantity = tonumber(args[4]), tonumber(args[5]) or 1
            local _, link = Pockets.Adapters.ItemAPI:RawGetItemInfo(itemID)
            Pockets.Services.LootLog:RecordItem(itemID, quantity, link)
            print(string.format("[Pockets] Logged item %d x%d", itemID, quantity))
        elseif kind == "money" and tonumber(args[4]) then
            Pockets.Services.LootLog:RecordMoney(tonumber(args[4]))
            print(string.format("[Pockets] Logged money %d", tonumber(args[4])))
        else
            print("[Pockets] Usage: /pockets test loot item <itemID> <quantity> | money <copper>")
        end
    else
        print("[Pockets] Test commands: run, sample <used> <total> <secondsAgo>, category <itemID>, recent <itemID> <quantity>, loot item|money ...")
    end
end

function Debug:RunTests()
    print(COLOR_YELLOW .. "[Pockets Test Suite] Running tests..." .. COLOR_RESET)
    local passed, failed = Pockets.Tests.TestRunner:RunAll()
    local color = (failed == 0) and COLOR_GREEN or COLOR_RED
    print(string.format("%s[Pockets Test Suite] %d passed, %d failed%s", color, passed, failed, COLOR_RESET))
    -- The runner temporarily replaces the shared widget getters, which taints
    -- them for the rest of the session (forbidden-action errors, lost mouse).
    -- Results are already in PocketsDB.lastTestRun; reloading clears the taint
    -- and writes them to disk.
    print(COLOR_YELLOW .. "[Pockets Test Suite] Reloading the UI in 3s to clear test taint "
        .. "(results saved to PocketsDB.lastTestRun)." .. COLOR_RESET)
    if _G.C_Timer and _G.ReloadUI then
        _G.C_Timer.After(3, _G.ReloadUI)
    end
    return failed == 0
end
