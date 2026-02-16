--[[
    init.lua - Entry point for pH

    Handles initialization, slash commands, and event frame setup.
    Account-wide: pH_DB_Account (sessions). Per-character: pH_Settings (UI state).
]]

-- luacheck: globals pH_DB pH_DB_Account pH_Settings

-- Create main addon frame
local pH_MainFrame = CreateFrame("Frame", "pH_MainFrame")

-- Ensure account-wide DB exists
local function EnsureAccountDB()
    if not pH_DB_Account then
        pH_DB_Account = {
            meta = { lastSessionId = 0 },
            priceOverrides = {},
            activeSession = nil,
            sessions = {},
            debug = { enabled = false, verbose = false, lastTestResults = {} },
        }
    end
    if not pH_DB_Account.meta then
        pH_DB_Account.meta = { lastSessionId = 0 }
    end
    if pH_DB_Account.meta.lastSessionId == nil then
        pH_DB_Account.meta.lastSessionId = 0
    end
    if not pH_DB_Account.debug then
        pH_DB_Account.debug = { enabled = false, verbose = false, lastTestResults = {} }
    end
end

-- Check for duplicate sessions and warn user
local function WarnIfDuplicatesExist()
    if not pH_Debug or not pH_Debug.ScanForDuplicates then
        return
    end

    local scanResult = pH_Debug:ScanForDuplicates()
    if scanResult.totalDuplicates > 0 then
        print(string.format(
            "|cffff8000[pH]|r Warning: %d duplicate sessions detected. " ..
            "Type |cff00ff00/goldph debug dupes|r for details.",
            scanResult.totalDuplicates
        ))
    end
end

-- Initialize saved variables on first load
local function InitializeSavedVariables()
    EnsureAccountDB()

    -- Per-character settings (UI state)
    if not pH_Settings then
        pH_Settings = {
            trackZone = true,
            hudVisible = true,
            hudMinimized = false,
            startPanelExpanded = true,  -- Expanded on first load (shows tips/zone context)
            historyVisible = false,
            historyMinimized = false,
            historyPosition = nil,
            historyActiveTab = "summary",
            historyFilters = { sort = "totalPerHour" },
            microBars = {
                enabled = true,
                height = 6,
                updateInterval = 0.25,
                smoothingAlpha = 0.25,
                normalization = {
                    mode = "sessionPeak",
                    peakDecay = { enabled = false, ratePerMin = 0.03 },
                },
                minRefFloors = { gold = 50000, xp = 5000, rep = 50, honor = 100 },
                updateThresholds = { gold = 1000, xp = 100, rep = 5, honor = 10 },
            },
            metricCards = {
                enabled = true,
                useGridLayout = true,  -- Enable 2x2 grid layout
                sampleInterval = 10,
                bufferMinutes = 60,
                sparklineMinutes = 15,
                showInactive = false,
            },
        }
    end
    -- Ensure microBars exists (migration for existing pH_Settings without it)
    if pH_Settings.microBars == nil then
        pH_Settings.microBars = {
            enabled = true,
            height = 6,
            updateInterval = 0.25,
            smoothingAlpha = 0.25,
            normalization = {
                mode = "sessionPeak",
                peakDecay = { enabled = false, ratePerMin = 0.03 },
            },
            minRefFloors = { gold = 50000, xp = 5000, rep = 50, honor = 100 },
            updateThresholds = { gold = 1000, xp = 100, rep = 5, honor = 10 },
        }
    end
    if pH_Settings.metricCards == nil then
        pH_Settings.metricCards = {
            enabled = true,
            useGridLayout = true,  -- Enable 2x2 grid layout
            sampleInterval = 10,
            bufferMinutes = 60,
            sparklineMinutes = 15,
            showInactive = false,
        }
    end
    -- Migration: add useGridLayout to existing settings
    if pH_Settings.metricCards.useGridLayout == nil then
        pH_Settings.metricCards.useGridLayout = true
    end
    -- Migration: add startPanelExpanded to existing settings (nil = first load or upgrade)
    if pH_Settings.startPanelExpanded == nil then
        pH_Settings.startPanelExpanded = true
    end

    -- Rest of addon uses pH_DB_Account (see SessionManager, Index, Events, UI_*, etc.)
end

-- Addon loaded event handler
pH_MainFrame:RegisterEvent("ADDON_LOADED")
pH_MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
pH_MainFrame:RegisterEvent("PLAYER_LOGOUT")
pH_MainFrame:SetScript("OnEvent", function(self, event, ...)
    local addonName = select(1, ...)

    if event == "ADDON_LOADED" and addonName == "ph" then
        InitializeSavedVariables()

        -- Initialize UI
        pH_HUD:Initialize()

        -- Initialize event system (registers additional events)
        pH_Events:Initialize(pH_MainFrame)

        local charName = UnitName("player") or "Unknown"
        local realm = GetRealmName() or "Unknown"
        print("[pH] Version 0.11.0 loaded. Type /ph help for commands (legacy /goldph still works).")

        -- Check for duplicate sessions (delayed to avoid login spam)
        C_Timer.After(2, WarnIfDuplicatesExist)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure settings exist
        if not pH_Settings then
            pH_Settings = {
                trackZone = true,
                hudVisible = true,
                hudMinimized = false,
                historyVisible = false,
                historyMinimized = false,
                historyPosition = nil,
                historyActiveTab = "summary",
                historyFilters = { sort = "totalPerHour" },
                microBars = {
                    enabled = true,
                    height = 6,
                    updateInterval = 0.25,
                    smoothingAlpha = 0.25,
                    normalization = {
                        mode = "sessionPeak",
                        peakDecay = { enabled = false, ratePerMin = 0.03 },
                    },
                    minRefFloors = { gold = 50000, xp = 5000, rep = 50, honor = 100 },
                    updateThresholds = { gold = 1000, xp = 100, rep = 5, honor = 10 },
                },
            metricCards = {
                enabled = true,
                useGridLayout = true,  -- Enable 2x2 grid layout
                sampleInterval = 10,
                bufferMinutes = 60,
                sparklineMinutes = 15,
                showInactive = false,
            },
            }
        end
        if pH_Settings.hudVisible == nil then
            pH_Settings.hudVisible = true
        end
        if pH_Settings.hudMinimized == nil then
            pH_Settings.hudMinimized = false
        end
        if pH_Settings.microBars == nil then
            pH_Settings.microBars = {
                enabled = true,
                height = 6,
                updateInterval = 0.25,
                smoothingAlpha = 0.25,
                normalization = {
                    mode = "sessionPeak",
                    peakDecay = { enabled = false, ratePerMin = 0.03 },
                },
                minRefFloors = { gold = 50000, xp = 5000, rep = 50, honor = 100 },
                updateThresholds = { gold = 1000, xp = 100, rep = 5, honor = 10 },
            }
        end
        if pH_Settings.metricCards == nil then
            pH_Settings.metricCards = {
                sampleInterval = 10,
                bufferMinutes = 60,
                sparklineMinutes = 15,
                showInactive = false,
            }
        end

        -- Ensure active session has duration tracking fields (only for this character's session)
        local session = pH_SessionManager:GetActiveSession()
        if session then
            local wasNewLogin = false
            if session.accumulatedDuration == nil then
                session.accumulatedDuration = 0
            end
            -- Only start/resume the clock if not paused (pause state persists across logout)
            if session.currentLoginAt == nil and not session.pausedAt then
                session.currentLoginAt = time()
                wasNewLogin = true
            end

            if pH_DB_Account.debug and pH_DB_Account.debug.verbose then
                print(string.format(
                    "[pH Debug] PLAYER_ENTERING_WORLD | Session #%d | accumulatedDuration=%d | currentLoginAt=%s | wasNewLogin=%s",
                    session.id,
                    session.accumulatedDuration,
                    tostring(session.currentLoginAt),
                    tostring(wasNewLogin)
                ))
            end
        end

        -- Auto-restore HUD visibility and state if this character has an active session
        if pH_SessionManager:GetActiveSession() then
            if pH_Settings.hudVisible then
                pH_HUD:Show()
                pH_HUD:ApplyMinimizeState()
            else
                pH_HUD:Update()
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Fold the current login segment into the session accumulator on logout (only for this character's session)
        local session = pH_SessionManager:GetActiveSession()
        if session and session.currentLoginAt then
            local now = time()
            local segmentDuration = now - session.currentLoginAt
            local oldAccumulated = session.accumulatedDuration
            session.accumulatedDuration = session.accumulatedDuration + segmentDuration
            session.currentLoginAt = nil

            if pH_DB_Account.debug and pH_DB_Account.debug.verbose then
                print(string.format(
                    "[pH Debug] PLAYER_LOGOUT | Session #%d | segmentDuration=%ds | oldAccumulated=%d | newAccumulated=%d",
                    session.id,
                    segmentDuration,
                    oldAccumulated,
                    session.accumulatedDuration
                ))
            end
        end

        pH_Events:OnEvent(event, ...)
    else
        pH_Events:OnEvent(event, ...)
    end
end)

--------------------------------------------------
-- Slash Commands
--------------------------------------------------

local function ShowHelp()
    print("|cff00ff00=== pH Commands ===|r")
    print("|cffffff00/ph start|r - Start a new session")
    print("|cffffff00/ph stop|r - Stop the active session")
    print("|cffffff00/ph pause|r - Pause the session (clock and events)")
    print("|cffffff00/ph resume|r - Resume a paused session")
    print("|cffffff00/ph show|r - Show/hide the HUD")
    print("|cffffff00/ph status|r - Show current session status")
    print("|cffffff00/ph history|r - Open session history")
    print("")
    print("|cff00ff00=== Debug Commands ===|r")
    print("|cffffff00/ph debug on|off|r - Enable/disable debug mode (auto-run invariants)")
    print("|cffffff00/ph debug verbose on|off|r - Enable/disable verbose logging")
    print("|cffffff00/ph debug dump|r - Dump current session state")
    print("|cffffff00/ph debug ledger|r - Show ledger balances")
    print("|cffffff00/ph debug holdings|r - Show holdings (Phase 3+)")
    print("|cffffff00/ph debug prices|r - Show available price sources (TSM, Custom AH)")
    print("|cffffff00/ph debug pickpocket|r - Show pickpocket statistics (Phase 6)")
    print("|cffffff00/ph debug gathering|r - Show gathering node statistics")
    print("|cffffff00/ph debug dupes|r - Scan for duplicate sessions in database")
    print("|cffffff00/ph debug purge-dupes [confirm]|r - Remove duplicate sessions (backup first!)")
    print("")
    print("|cff00ff00=== Test Commands ===|r")
    print("|cffffff00/ph test run|r - Run automated test suite")
    print("|cffffff00/ph test hud|r - Populate HUD with sample data for testing")
    print("|cffffff00/ph test reset|r - Reset to fresh session")
    print("|cffffff00/ph test loot <copper>|r - Inject looted coin event")
    print("|cffffff00/ph test repair <copper>|r - Inject repair cost (Phase 2+)")
    print("|cffffff00/ph test lootitem <itemID> <count>|r - Inject looted item (Phase 3+)")
    print("|cffffff00/ph test vendoritem <itemID> <count>|r - Inject vendor sale (Phase 4+)")
    print("|cffffff00/ph test gathernode <name> [count] [copperValueEach]|r - Inject gathering node + value")
    print("======================")
end

local function HandleCommand(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] or "help"
    cmd = cmd:lower()

    local debugShortcuts = {
        dump = true, ledger = true, holdings = true, prices = true, pickpocket = true,
        gathering = true, on = true, off = true, verbose = true,
    }
    if debugShortcuts[cmd] then
        table.insert(args, 1, "debug")
        cmd = "debug"
    end

    if cmd == "start" then
        local ok, message = pH_SessionManager:StartSession()
        print("[pH] " .. message)
        if ok then
            pH_Settings.hudMinimized = true  -- New session starts with HUD collapsed
            pH_HUD:Show()
        end

    elseif cmd == "stop" then
        local ok, message = pH_SessionManager:StopSession()
        print("[pH] " .. message)
        pH_HUD:Update()

    elseif cmd == "pause" then
        local ok, message = pH_SessionManager:PauseSession()
        print("[pH] " .. message)
        if ok then
            pH_HUD:Update()
        end

    elseif cmd == "resume" then
        local ok, message = pH_SessionManager:ResumeSession()
        print("[pH] " .. message)
        if ok then
            pH_HUD:Update()
        end

    elseif cmd == "show" then
        pH_HUD:Toggle()

    elseif cmd == "status" then
        local session = pH_SessionManager:GetActiveSession()
        if session then
            local metrics = pH_SessionManager:GetMetrics(session)
            local pausedStr = pH_SessionManager:IsPaused(session) and " (paused)" or ""
            print(string.format("[pH] Session #%d%s | Duration: %s | Cash: %s | Cash/hr: %s",
                                session.id,
                                pausedStr,
                                pH_SessionManager:FormatDuration(metrics.durationSec),
                                pH_Ledger:FormatMoney(metrics.cash),
                                pH_Ledger:FormatMoneyShort(metrics.cashPerHour)))
        else
            print("[pH] No active session")
        end

    elseif cmd == "history" then
        pH_History:Toggle()

    elseif cmd == "debug" then
        local subCmd = args[2] or ""
        subCmd = subCmd:lower()
        if subCmd == "on" then
            pH_DB_Account.debug.enabled = true
            print("[pH] Debug mode enabled (invariants will auto-run)")
        elseif subCmd == "off" then
            pH_DB_Account.debug.enabled = false
            print("[pH] Debug mode disabled")
        elseif subCmd == "verbose" then
            local setting = (args[3] or ""):lower()
            if setting == "on" then
                pH_DB_Account.debug.verbose = true
                print("[pH] Verbose logging enabled")
            elseif setting == "off" then
                pH_DB_Account.debug.verbose = false
                print("[pH] Verbose logging disabled")
            else
                print("[pH] Usage: /ph debug verbose on|off")
            end
        elseif subCmd == "dump" then
            pH_Debug:DumpSession()
        elseif subCmd == "ledger" then
            pH_Debug:ShowLedger()
        elseif subCmd == "holdings" then
            pH_Debug:ShowHoldings()
        elseif subCmd == "prices" then
            pH_Debug:ShowPriceSources()
        elseif subCmd == "pickpocket" then
            pH_Debug:ShowPickpocket()
        elseif subCmd == "gathering" then
            pH_Debug:ShowGathering()
        elseif subCmd == "dupes" then
            pH_Debug:ShowDuplicates()
        elseif subCmd == "purge-dupes" then
            local confirm = (args[3] or ""):lower() == "confirm"
            pH_Debug:PurgeDuplicates(confirm)
        else
            print("[pH] Debug commands: on, off, verbose, dump, ledger, holdings, prices, pickpocket, gathering, dupes, purge-dupes")
        end

    elseif cmd == "test" then
        local subCmd = (args[2] or ""):lower()
        if subCmd == "run" then
            pH_Debug:RunTests()
        elseif subCmd == "hud" then
            pH_Debug:TestHUD()
        elseif subCmd == "reset" then
            pH_Debug:ResetTestHUD()
        elseif subCmd == "loot" then
            local copper = tonumber(args[3])
            if not copper then
                print("[pH] Usage: /ph test loot <copper>")
            else
                local ok, message = pH_Events:InjectLootedCoin(copper)
                if not ok then
                    print("[pH] " .. (message or "Failed to inject loot"))
                end
            end
        elseif subCmd == "repair" then
            local copper = tonumber(args[3])
            if not copper then
                print("[pH] Usage: /ph test repair <copper>")
            else
                local ok, message = pH_Events:InjectRepair(copper)
                if not ok then
                    print("[pH] " .. (message or "Failed to inject repair"))
                end
            end
        elseif subCmd == "lootitem" then
            local itemID = tonumber(args[3])
            local count = tonumber(args[4]) or 1
            if not itemID then
                print("[pH] Usage: /ph test lootitem <itemID> <count>")
            else
                local ok, message = pH_Events:InjectLootItem(itemID, count)
                if not ok then
                    print("[pH] " .. (message or "Failed to inject loot item"))
                end
            end
        elseif subCmd == "vendoritem" then
            local itemID = tonumber(args[3])
            local count = tonumber(args[4]) or 1
            if not itemID then
                print("[pH] Usage: /ph test vendoritem <itemID> <count>")
            else
                local ok, message = pH_Events:InjectVendorSale(itemID, count)
                if not ok then
                    print("[pH] " .. (message or "Failed to inject vendor sale"))
                end
            end
        elseif subCmd == "gathernode" then
            -- Usage: /ph test gathernode <name> [count] [copperValueEach]
            -- Last 1-2 numeric args are count and value; everything else is the name
            if not args[3] then
                print("[pH] Usage: /ph test gathernode <name> [count] [copperValueEach]")
            else
                -- Walk backwards to peel off numeric trailing args
                local trailingNums = {}
                local nameEnd = #args
                for j = #args, 3, -1 do
                    if tonumber(args[j]) then
                        table.insert(trailingNums, 1, tonumber(args[j]))
                        nameEnd = j - 1
                    else
                        break
                    end
                end
                -- Build name from remaining args
                local nameParts = {}
                for i = 3, nameEnd do
                    table.insert(nameParts, args[i])
                end
                local nodeName = table.concat(nameParts, " ")
                if nodeName == "" then
                    print("[pH] Usage: /ph test gathernode <name> [count] [copperValueEach]")
                else
                    local count = 1
                    local copperValueEach = nil
                    if #trailingNums == 1 then
                        count = trailingNums[1]
                    elseif #trailingNums >= 2 then
                        count = trailingNums[1]
                        copperValueEach = trailingNums[2]
                    end
                    local ok, message = pH_Events:InjectGatherNode(nodeName, count, copperValueEach)
                    if not ok then
                        print("[pH] " .. (message or "Failed to inject gather node"))
                    end
                end
            end
        else
            print("[pH] Test commands: run, hud, reset, loot <copper>, repair <copper>, lootitem <itemID> <count>, vendoritem <itemID> <count>, gathernode <name> [count] [copperValueEach]")
        end

    elseif cmd == "help" then
        ShowHelp()

    else
        print("[pH] Unknown command. Type /goldph help for usage.")
    end
end

SLASH_GOLDPH1 = "/goldph"
SLASH_GOLDPH2 = "/gph"
SLASH_GOLDPH3 = "/ph"
SlashCmdList["GOLDPH"] = HandleCommand
