--[[
    init.lua - Entry point for GoldPH

    Handles initialization, slash commands, and event frame setup.
    Account-wide: GoldPH_DB_Account (sessions). Per-character: GoldPH_Settings (UI state).
]]

-- luacheck: globals GoldPH_DB GoldPH_DB_Account GoldPH_Settings

-- Create main addon frame
local GoldPH_MainFrame = CreateFrame("Frame", "GoldPH_MainFrame")

-- Ensure account-wide DB exists
local function EnsureAccountDB()
    if not GoldPH_DB_Account then
        GoldPH_DB_Account = {
            meta = { lastSessionId = 0 },
            priceOverrides = {},
            activeSession = nil,
            sessions = {},
            debug = { enabled = false, verbose = false, lastTestResults = {} },
        }
    end
    if not GoldPH_DB_Account.meta then
        GoldPH_DB_Account.meta = { lastSessionId = 0 }
    end
    if GoldPH_DB_Account.meta.lastSessionId == nil then
        GoldPH_DB_Account.meta.lastSessionId = 0
    end
    if not GoldPH_DB_Account.debug then
        GoldPH_DB_Account.debug = { enabled = false, verbose = false, lastTestResults = {} }
    end
end

-- Check for duplicate sessions and warn user
local function WarnIfDuplicatesExist()
    if not GoldPH_Debug or not GoldPH_Debug.ScanForDuplicates then
        return
    end

    local scanResult = GoldPH_Debug:ScanForDuplicates()
    if scanResult.totalDuplicates > 0 then
        print(string.format(
            "|cffff8000[GoldPH]|r Warning: %d duplicate sessions detected. " ..
            "Type |cff00ff00/goldph debug dupes|r for details.",
            scanResult.totalDuplicates
        ))
    end
end

-- Initialize saved variables on first load
local function InitializeSavedVariables()
    EnsureAccountDB()

    -- Per-character settings (UI state)
    if not GoldPH_Settings then
        GoldPH_Settings = {
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
    -- Ensure microBars exists (migration for existing GoldPH_Settings without it)
    if GoldPH_Settings.microBars == nil then
        GoldPH_Settings.microBars = {
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
    if GoldPH_Settings.metricCards == nil then
        GoldPH_Settings.metricCards = {
            enabled = true,
            useGridLayout = true,  -- Enable 2x2 grid layout
            sampleInterval = 10,
            bufferMinutes = 60,
            sparklineMinutes = 15,
            showInactive = false,
        }
    end
    -- Migration: add useGridLayout to existing settings
    if GoldPH_Settings.metricCards.useGridLayout == nil then
        GoldPH_Settings.metricCards.useGridLayout = true
    end

    -- Rest of addon uses GoldPH_DB_Account (see SessionManager, Index, Events, UI_*, etc.)
end

-- Addon loaded event handler
GoldPH_MainFrame:RegisterEvent("ADDON_LOADED")
GoldPH_MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GoldPH_MainFrame:RegisterEvent("PLAYER_LOGOUT")
GoldPH_MainFrame:SetScript("OnEvent", function(self, event, ...)
    local addonName = select(1, ...)

    if event == "ADDON_LOADED" and addonName == "GoldPH" then
        InitializeSavedVariables()

        -- Initialize UI
        GoldPH_HUD:Initialize()

        -- Initialize event system (registers additional events)
        GoldPH_Events:Initialize(GoldPH_MainFrame)

        local charName = UnitName("player") or "Unknown"
        local realm = GetRealmName() or "Unknown"
        print("[GoldPH] Version 0.8.0 (cross-character sessions) loaded. Type /goldph help for commands.")

        -- Check for duplicate sessions (delayed to avoid login spam)
        C_Timer.After(2, WarnIfDuplicatesExist)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure settings exist
        if not GoldPH_Settings then
            GoldPH_Settings = {
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
        if GoldPH_Settings.hudVisible == nil then
            GoldPH_Settings.hudVisible = true
        end
        if GoldPH_Settings.hudMinimized == nil then
            GoldPH_Settings.hudMinimized = false
        end
        if GoldPH_Settings.microBars == nil then
            GoldPH_Settings.microBars = {
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
        if GoldPH_Settings.metricCards == nil then
            GoldPH_Settings.metricCards = {
                sampleInterval = 10,
                bufferMinutes = 60,
                sparklineMinutes = 15,
                showInactive = false,
            }
        end

        -- Ensure active session has duration tracking fields (only for this character's session)
        local session = GoldPH_SessionManager:GetActiveSession()
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

            if GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
                print(string.format(
                    "[GoldPH Debug] PLAYER_ENTERING_WORLD | Session #%d | accumulatedDuration=%d | currentLoginAt=%s | wasNewLogin=%s",
                    session.id,
                    session.accumulatedDuration,
                    tostring(session.currentLoginAt),
                    tostring(wasNewLogin)
                ))
            end
        end

        -- Auto-restore HUD visibility and state if this character has an active session
        if GoldPH_SessionManager:GetActiveSession() then
            if GoldPH_Settings.hudVisible then
                GoldPH_HUD:Show()
                GoldPH_HUD:ApplyMinimizeState()
            else
                GoldPH_HUD:Update()
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Fold the current login segment into the session accumulator on logout (only for this character's session)
        local session = GoldPH_SessionManager:GetActiveSession()
        if session and session.currentLoginAt then
            local now = time()
            local segmentDuration = now - session.currentLoginAt
            local oldAccumulated = session.accumulatedDuration
            session.accumulatedDuration = session.accumulatedDuration + segmentDuration
            session.currentLoginAt = nil

            if GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
                print(string.format(
                    "[GoldPH Debug] PLAYER_LOGOUT | Session #%d | segmentDuration=%ds | oldAccumulated=%d | newAccumulated=%d",
                    session.id,
                    segmentDuration,
                    oldAccumulated,
                    session.accumulatedDuration
                ))
            end
        end

        GoldPH_Events:OnEvent(event, ...)
    else
        GoldPH_Events:OnEvent(event, ...)
    end
end)

--------------------------------------------------
-- Slash Commands
--------------------------------------------------

local function ShowHelp()
    print("|cff00ff00=== GoldPH Commands ===|r")
    print("|cffffff00/goldph start|r - Start a new session")
    print("|cffffff00/goldph stop|r - Stop the active session")
    print("|cffffff00/goldph pause|r - Pause the session (clock and events)")
    print("|cffffff00/goldph resume|r - Resume a paused session")
    print("|cffffff00/goldph show|r - Show/hide the HUD")
    print("|cffffff00/goldph status|r - Show current session status")
    print("|cffffff00/goldph history|r - Open session history")
    print("")
    print("|cff00ff00=== Debug Commands ===|r")
    print("|cffffff00/goldph debug on|off|r - Enable/disable debug mode (auto-run invariants)")
    print("|cffffff00/goldph debug verbose on|off|r - Enable/disable verbose logging")
    print("|cffffff00/goldph debug dump|r - Dump current session state")
    print("|cffffff00/goldph debug ledger|r - Show ledger balances")
    print("|cffffff00/goldph debug holdings|r - Show holdings (Phase 3+)")
    print("|cffffff00/goldph debug prices|r - Show available price sources (TSM, Custom AH)")
    print("|cffffff00/goldph debug pickpocket|r - Show pickpocket statistics (Phase 6)")
    print("|cffffff00/goldph debug gathering|r - Show gathering node statistics")
    print("|cffffff00/goldph debug dupes|r - Scan for duplicate sessions in database")
    print("|cffffff00/goldph debug purge-dupes [confirm]|r - Remove duplicate sessions (backup first!)")
    print("")
    print("|cff00ff00=== Test Commands ===|r")
    print("|cffffff00/goldph test run|r - Run automated test suite")
    print("|cffffff00/goldph test hud|r - Populate HUD with sample data for testing")
    print("|cffffff00/goldph test reset|r - Reset to fresh session")
    print("|cffffff00/goldph test loot <copper>|r - Inject looted coin event")
    print("|cffffff00/goldph test repair <copper>|r - Inject repair cost (Phase 2+)")
    print("|cffffff00/goldph test lootitem <itemID> <count>|r - Inject looted item (Phase 3+)")
    print("|cffffff00/goldph test vendoritem <itemID> <count>|r - Inject vendor sale (Phase 4+)")
    print("|cffffff00/goldph test gathernode <name> [count] [copperValueEach]|r - Inject gathering node + value")
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
        local ok, message = GoldPH_SessionManager:StartSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_Settings.hudMinimized = true  -- New session starts with HUD collapsed
            GoldPH_HUD:Show()
        end

    elseif cmd == "stop" then
        local ok, message = GoldPH_SessionManager:StopSession()
        print("[GoldPH] " .. message)
        GoldPH_HUD:Update()

    elseif cmd == "pause" then
        local ok, message = GoldPH_SessionManager:PauseSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_HUD:Update()
        end

    elseif cmd == "resume" then
        local ok, message = GoldPH_SessionManager:ResumeSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_HUD:Update()
        end

    elseif cmd == "show" then
        GoldPH_HUD:Toggle()

    elseif cmd == "status" then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local metrics = GoldPH_SessionManager:GetMetrics(session)
            local pausedStr = GoldPH_SessionManager:IsPaused(session) and " (paused)" or ""
            print(string.format("[GoldPH] Session #%d%s | Duration: %s | Cash: %s | Cash/hr: %s",
                                session.id,
                                pausedStr,
                                GoldPH_SessionManager:FormatDuration(metrics.durationSec),
                                GoldPH_Ledger:FormatMoney(metrics.cash),
                                GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour)))
        else
            print("[GoldPH] No active session")
        end

    elseif cmd == "history" then
        GoldPH_History:Toggle()

    elseif cmd == "debug" then
        local subCmd = args[2] or ""
        subCmd = subCmd:lower()
        if subCmd == "on" then
            GoldPH_DB_Account.debug.enabled = true
            print("[GoldPH] Debug mode enabled (invariants will auto-run)")
        elseif subCmd == "off" then
            GoldPH_DB_Account.debug.enabled = false
            print("[GoldPH] Debug mode disabled")
        elseif subCmd == "verbose" then
            local setting = (args[3] or ""):lower()
            if setting == "on" then
                GoldPH_DB_Account.debug.verbose = true
                print("[GoldPH] Verbose logging enabled")
            elseif setting == "off" then
                GoldPH_DB_Account.debug.verbose = false
                print("[GoldPH] Verbose logging disabled")
            else
                print("[GoldPH] Usage: /goldph debug verbose on|off")
            end
        elseif subCmd == "dump" then
            GoldPH_Debug:DumpSession()
        elseif subCmd == "ledger" then
            GoldPH_Debug:ShowLedger()
        elseif subCmd == "holdings" then
            GoldPH_Debug:ShowHoldings()
        elseif subCmd == "prices" then
            GoldPH_Debug:ShowPriceSources()
        elseif subCmd == "pickpocket" then
            GoldPH_Debug:ShowPickpocket()
        elseif subCmd == "gathering" then
            GoldPH_Debug:ShowGathering()
        elseif subCmd == "dupes" then
            GoldPH_Debug:ShowDuplicates()
        elseif subCmd == "purge-dupes" then
            local confirm = (args[3] or ""):lower() == "confirm"
            GoldPH_Debug:PurgeDuplicates(confirm)
        else
            print("[GoldPH] Debug commands: on, off, verbose, dump, ledger, holdings, prices, pickpocket, gathering, dupes, purge-dupes")
        end

    elseif cmd == "test" then
        local subCmd = (args[2] or ""):lower()
        if subCmd == "run" then
            GoldPH_Debug:RunTests()
        elseif subCmd == "hud" then
            GoldPH_Debug:TestHUD()
        elseif subCmd == "reset" then
            GoldPH_Debug:ResetTestHUD()
        elseif subCmd == "loot" then
            local copper = tonumber(args[3])
            if not copper then
                print("[GoldPH] Usage: /goldph test loot <copper>")
            else
                local ok, message = GoldPH_Events:InjectLootedCoin(copper)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject loot"))
                end
            end
        elseif subCmd == "repair" then
            local copper = tonumber(args[3])
            if not copper then
                print("[GoldPH] Usage: /goldph test repair <copper>")
            else
                local ok, message = GoldPH_Events:InjectRepair(copper)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject repair"))
                end
            end
        elseif subCmd == "lootitem" then
            local itemID = tonumber(args[3])
            local count = tonumber(args[4]) or 1
            if not itemID then
                print("[GoldPH] Usage: /goldph test lootitem <itemID> <count>")
            else
                local ok, message = GoldPH_Events:InjectLootItem(itemID, count)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject loot item"))
                end
            end
        elseif subCmd == "vendoritem" then
            local itemID = tonumber(args[3])
            local count = tonumber(args[4]) or 1
            if not itemID then
                print("[GoldPH] Usage: /goldph test vendoritem <itemID> <count>")
            else
                local ok, message = GoldPH_Events:InjectVendorSale(itemID, count)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject vendor sale"))
                end
            end
        elseif subCmd == "gathernode" then
            -- Usage: /goldph test gathernode <name> [count] [copperValueEach]
            -- Last 1-2 numeric args are count and value; everything else is the name
            if not args[3] then
                print("[GoldPH] Usage: /goldph test gathernode <name> [count] [copperValueEach]")
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
                    print("[GoldPH] Usage: /goldph test gathernode <name> [count] [copperValueEach]")
                else
                    local count = 1
                    local copperValueEach = nil
                    if #trailingNums == 1 then
                        count = trailingNums[1]
                    elseif #trailingNums >= 2 then
                        count = trailingNums[1]
                        copperValueEach = trailingNums[2]
                    end
                    local ok, message = GoldPH_Events:InjectGatherNode(nodeName, count, copperValueEach)
                    if not ok then
                        print("[GoldPH] " .. (message or "Failed to inject gather node"))
                    end
                end
            end
        else
            print("[GoldPH] Test commands: run, hud, reset, loot <copper>, repair <copper>, lootitem <itemID> <count>, vendoritem <itemID> <count>, gathernode <name> [count] [copperValueEach]")
        end

    elseif cmd == "help" then
        ShowHelp()

    else
        print("[GoldPH] Unknown command. Type /goldph help for usage.")
    end
end

SLASH_GOLDPH1 = "/goldph"
SLASH_GOLDPH2 = "/gph"
SLASH_GOLDPH3 = "/ph"
SlashCmdList["GOLDPH"] = HandleCommand
