--[[
    init.lua - Entry point for pH

    Handles initialization, slash commands, and event frame setup.
    Account-wide: pH_DB_Account (sessions). Per-character: pH_Settings (UI state).
]]

-- luacheck: globals pH_DB pH_DB_Account pH_Settings pH_AutoSession

-- Create main addon frame
local pH_MainFrame = CreateFrame("Frame", "pH_MainFrame")

-- Ensure account-wide DB exists
local function EnsureAccountDB()
    if not pH_DB_Account then
        pH_DB_Account = {
            meta = {
                lastSessionId = 0,
                historyUndo = { stack = {}, maxEntries = 20 },
            },
            priceOverrides = {},
            activeSession = nil,
            activeSessions = {},
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
    if not pH_DB_Account.meta.historyUndo then
        pH_DB_Account.meta.historyUndo = { stack = {}, maxEntries = 20 }
    end
    if not pH_DB_Account.meta.historyUndo.stack then
        pH_DB_Account.meta.historyUndo.stack = {}
    end
    if not pH_DB_Account.meta.historyUndo.maxEntries then
        pH_DB_Account.meta.historyUndo.maxEntries = 20
    end
    if not pH_DB_Account.debug then
        pH_DB_Account.debug = { enabled = false, verbose = false, lastTestResults = {} }
    end
    if not pH_DB_Account.activeSessions then
        pH_DB_Account.activeSessions = {}
    end
    if pH_DB_Account.activeSession and next(pH_DB_Account.activeSessions) == nil then
        local legacy = pH_DB_Account.activeSession
        local charKey = (legacy.character or "Unknown") .. "-" .. (legacy.realm or "Unknown") .. "-" .. (legacy.faction or "Unknown")
        pH_DB_Account.activeSessions[charKey] = legacy
    end
    pH_DB_Account.activeSession = nil
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
            historyFilters = {
                sort = "totalPerHour",
                excludeShort = true,
                minDurationSec = 300,
                excludeArchived = true,
            },
            historyCleanup = {
                shortThresholdSec = 300,
            },
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
    -- Migration: add autoSession settings (source-aware model migrates in AutoSession.lua)
    if pH_Settings.autoSession == nil then
        pH_Settings.autoSession = {
            enabled = true,
        }
    end
    if pH_Settings.historyCleanup == nil then
        pH_Settings.historyCleanup = {
            shortThresholdSec = 300,
        }
    end
    if pH_Settings.historyCleanup.shortThresholdSec == nil then
        pH_Settings.historyCleanup.shortThresholdSec = 300
    end
    if pH_Settings.historyFilters == nil then
        pH_Settings.historyFilters = {}
    end
    if pH_Settings.historyFilters.excludeShort == nil then
        pH_Settings.historyFilters.excludeShort = true
    end
    if pH_Settings.historyFilters.minDurationSec == nil then
        pH_Settings.historyFilters.minDurationSec = 300
    end
    if pH_Settings.historyFilters.excludeArchived == nil then
        pH_Settings.historyFilters.excludeArchived = true
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

        -- Initialize auto-session management
        if pH_AutoSession then
            pH_AutoSession:Initialize()
        end

        print("[pH] Version 0.13.0 loaded. Type /ph help for commands (legacy /goldph still works).")
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
                historyFilters = {
                    sort = "totalPerHour",
                    excludeShort = true,
                    minDurationSec = 300,
                    excludeArchived = true,
                },
                historyCleanup = {
                    shortThresholdSec = 300,
                },
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

        -- Check for instance entry (auto-start paused session)
        if pH_AutoSession then
            pH_AutoSession:OnPlayerEnteringWorld()
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
    print("|cffffff00/ph history archive-short|r - Archive all short sessions (<5m)")
    print("|cffffff00/ph history archive <sessionId>|r - Archive one session")
    print("|cffffff00/ph history unarchive <sessionId>|r - Unarchive one session")
    print("|cffffff00/ph history delete <sessionId> confirm|r - Permanently delete session")
    print("|cffffff00/ph history merge <id1> <id2> [idN...] confirm|r - Merge same-character sessions")
    print("|cffffff00/ph history undo|r - Undo the last history action (30s)")
    print("|cffffff00/ph auto status|r - Show source-aware auto-session settings")
    print("|cffffff00/ph auto on|off|r - Enable/disable auto-session management")
    print("|cffffff00/ph auto profile <manual|balanced|handsfree>|r - Apply preset")
    print("|cffffff00/ph auto set <start|resume> <source> <off|prompt|auto>|r - Set one source rule")
    print("|cffffff00/ph auto prompt <never|smart|always>|r - Configure start prompts")
    print("|cffffff00/ph auto sources|r - List source keys")
    print("|cffffff00/ph auto ui|r - Open Auto Session settings panel")
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
    print("|cffffff00/ph debug data|r - Show session counts and per-character breakdown")
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
        gathering = true, data = true, on = true, off = true, verbose = true,
    }
    if debugShortcuts[cmd] then
        table.insert(args, 1, "debug")
        cmd = "debug"
    end

    if cmd == "start" then
        local ok, message = pH_SessionManager:StartSession("manual", "command")
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
        local ok, message = pH_SessionManager:PauseSession("manual", "command")
        print("[pH] " .. message)
        if ok then
            pH_HUD:Update()
        end

    elseif cmd == "resume" then
        local ok, message = pH_SessionManager:ResumeSession("manual", "command")
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
        local subCmd = (args[2] or ""):lower()
        if subCmd == "" then
            pH_History:Toggle()
        elseif subCmd == "archive-short" then
            local threshold = pH_SessionManager:GetShortSessionThresholdSec()
            local ok, message, undoSec = pH_SessionManager:ArchiveShortSessions(threshold)
            print("[pH] " .. message)
            if ok and undoSec then
                print(string.format("[pH] Undo available for %ds: /ph history undo", undoSec))
            end
        elseif subCmd == "archive" then
            local sessionId = tonumber(args[3])
            if not sessionId then
                print("[pH] Usage: /ph history archive <sessionId>")
            else
                local ok, message, undoSec = pH_SessionManager:SetSessionArchived(sessionId, true, "manual")
                print("[pH] " .. message)
                if ok and undoSec then
                    print(string.format("[pH] Undo available for %ds: /ph history undo", undoSec))
                end
            end
        elseif subCmd == "unarchive" then
            local sessionId = tonumber(args[3])
            if not sessionId then
                print("[pH] Usage: /ph history unarchive <sessionId>")
            else
                local ok, message, undoSec = pH_SessionManager:SetSessionArchived(sessionId, false, "manual")
                print("[pH] " .. message)
                if ok and undoSec then
                    print(string.format("[pH] Undo available for %ds: /ph history undo", undoSec))
                end
            end
        elseif subCmd == "delete" then
            local sessionId = tonumber(args[3])
            local confirm = (args[4] or ""):lower() == "confirm"
            if not sessionId then
                print("[pH] Usage: /ph history delete <sessionId> confirm")
            elseif not confirm then
                print("[pH] Confirm required: /ph history delete <sessionId> confirm")
            else
                local ok, message, undoSec = pH_SessionManager:DeleteSession(sessionId)
                print("[pH] " .. message)
                if ok and undoSec then
                    print(string.format("[pH] Undo available for %ds: /ph history undo", undoSec))
                end
            end
        elseif subCmd == "merge" then
            local confirm = (args[#args] or ""):lower() == "confirm"
            if not confirm then
                print("[pH] Usage: /ph history merge <id1> <id2> [idN...] confirm")
            else
                local ids = {}
                for i = 3, #args - 1 do
                    local id = tonumber(args[i])
                    if id then
                        table.insert(ids, id)
                    end
                end
                if #ids < 2 then
                    print("[pH] Usage: /ph history merge <id1> <id2> [idN...] confirm")
                else
                    local ok, message, undoSec = pH_SessionManager:MergeSessions(ids)
                    print("[pH] " .. message)
                    if ok and undoSec then
                        print(string.format("[pH] Undo available for %ds: /ph history undo", undoSec))
                    end
                end
            end
        elseif subCmd == "undo" then
            local ok, message = pH_SessionManager:UndoLastHistoryAction()
            print("[pH] " .. message)
        else
            print("[pH] History commands: archive-short, archive <id>, unarchive <id>, delete <id> confirm, merge <ids...> confirm, undo")
        end

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
        elseif subCmd == "data" then
            pH_Debug:ShowData()
        else
            print("[pH] Debug commands: on, off, verbose, dump, ledger, holdings, prices, pickpocket, gathering, data")
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

    elseif cmd == "auto" then
        local subCmd = (args[2] or ""):lower()
        if not pH_Settings.autoSession then
            print("[pH] Auto-session settings not initialized")
            return
        end
        if type(pH_AutoSession) ~= "table" then
            print("[pH] Auto-session module is not loaded")
            return
        end
        if subCmd == "on" then
            pH_Settings.autoSession.enabled = true
            print("[pH] Auto-session management enabled")
        elseif subCmd == "off" then
            pH_Settings.autoSession.enabled = false
            print("[pH] Auto-session management disabled")
        elseif subCmd == "" or subCmd == "status" then
            print("[pH] Auto-session settings:")
            for _, line in ipairs(pH_AutoSession:GetStatusLines()) do
                print(line)
            end
        elseif subCmd == "profile" then
            local profile = (args[3] or ""):lower()
            local ok, message = pH_AutoSession:ApplyProfile(profile)
            if ok then
                print("[pH] Auto-session profile set to " .. profile)
            else
                print("[pH] " .. (message or "Failed to set profile"))
            end
        elseif subCmd == "prompt" then
            local mode = (args[3] or ""):lower()
            local ok, message = pH_AutoSession:SetPromptMode(mode)
            if ok then
                print("[pH] Auto-session prompt mode set to " .. mode)
            else
                print("[pH] " .. (message or "Failed to set prompt mode"))
            end
        elseif subCmd == "set" then
            local kind = (args[3] or ""):lower()
            local source = (args[4] or ""):lower()
            local action = (args[5] or ""):lower()
            local ok, message = pH_AutoSession:SetRule(kind, source, action)
            if ok then
                print(string.format("[pH] Rule updated: %s %s = %s", kind, source, action))
            else
                print("[pH] " .. (message or "Failed to set rule"))
            end
        elseif subCmd == "sources" then
            pH_AutoSession:PrintSources()
        elseif subCmd == "ui" or subCmd == "settings" then
            pH_AutoSession:OpenSettingsPanel()
        else
            print("[pH] Usage:")
            print("  /ph auto status")
            print("  /ph auto on|off")
            print("  /ph auto profile <manual|balanced|handsfree>")
            print("  /ph auto prompt <never|smart|always>")
            print("  /ph auto set <start|resume> <source> <off|prompt|auto>")
            print("  /ph auto sources")
            print("  /ph auto ui")
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
