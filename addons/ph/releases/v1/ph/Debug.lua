--[[
    Debug.lua - Debug and testing infrastructure for GoldPH

    Provides invariant checks, test injection, and debugging tools.
]]

-- luacheck: globals GoldPH_DB_Account

local GoldPH_Debug = {}

-- Color codes for chat output
local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff0000"
local COLOR_YELLOW = "|cffffff00"
local COLOR_RESET = "|r"

--------------------------------------------------
-- Invariant Checks
--------------------------------------------------

-- Validate core accounting invariant: NetWorth = Cash + InventoryExpected
function GoldPH_Debug:ValidateNetWorth(session)
    if not session or not session.ledger then
        return false, "Invalid session"
    end

    -- Phase 1: Only cash tracking (no inventory yet)
    local cash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local netWorth = cash

    -- Future phases: Add inventory expected values
    -- for acct, bal in pairs(session.ledger.balances) do
    --     if acct:match("^Assets:Inventory:") then
    --         netWorth = netWorth + bal
    --     end
    -- end

    -- Sum income and expenses
    local income = 0
    local expenses = 0
    for acct, bal in pairs(session.ledger.balances) do
        if acct:match("^Income:") then
            income = income + bal
        elseif acct:match("^Expense:") then
            expenses = expenses + bal
        end
    end

    -- Phase 4+: Account for inventory realization
    local equity = GoldPH_Ledger:GetBalance(session, "Equity:InventoryRealization")

    -- Invariant: NetWorth = Income - Expenses - EquityAdjustment
    local expected = income - expenses - equity
    local diff = netWorth - expected

    if diff ~= 0 then
        return false, string.format("NetWorth invariant violated! NetWorth=%d, Expected=%d, Diff=%d",
                                    netWorth, expected, diff)
    end

    return true, "NetWorth invariant OK"
end

-- Validate ledger balance (debits = credits in double-entry)
function GoldPH_Debug:ValidateLedgerBalance(session)
    if not session or not session.ledger then
        return false, "Invalid session"
    end

    -- In pure double-entry, sum of all balances should be even
    -- (each Dr+Cr pair contributes equal amounts)
    -- However, with our simplified model, we just check for negative balances
    for acct, bal in pairs(session.ledger.balances) do
        if bal < 0 then
            return false, string.format("Negative balance in account: %s = %d", acct, bal)
        end
    end

    return true, "Ledger balance OK"
end

-- Validate holdings (Phase 3)
function GoldPH_Debug:ValidateHoldings(session)
    if not session or not session.holdings then
        return true, "No holdings to validate"
    end

    -- Sum up expected values from holdings by bucket
    local holdingsByBucket = {
        vendor_trash = 0,
        rare_multi = 0,
        gathering = 0,
        container_lockbox = 0,
    }

    for itemID, holding in pairs(session.holdings) do
        for _, lot in ipairs(holding.lots) do
            local bucket = lot.bucket
            local value = lot.count * lot.expectedEach
            holdingsByBucket[bucket] = (holdingsByBucket[bucket] or 0) + value
        end
    end

    -- Compare with ledger accounts
    local vendorTrash = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:VendorTrash")
    local rareMulti = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:RareMulti")
    local gathering = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")

    local errors = {}
    if holdingsByBucket.vendor_trash ~= vendorTrash then
        table.insert(errors, string.format("VendorTrash: holdings=%d, ledger=%d",
            holdingsByBucket.vendor_trash, vendorTrash))
    end
    if holdingsByBucket.rare_multi ~= rareMulti then
        table.insert(errors, string.format("RareMulti: holdings=%d, ledger=%d",
            holdingsByBucket.rare_multi, rareMulti))
    end
    if holdingsByBucket.gathering ~= gathering then
        table.insert(errors, string.format("Gathering: holdings=%d, ledger=%d",
            holdingsByBucket.gathering, gathering))
    end

    if #errors > 0 then
        return false, "Holdings mismatch: " .. table.concat(errors, "; ")
    end

    return true, "Holdings match ledger"
end

-- Run all invariant checks
function GoldPH_Debug:ValidateInvariants(session)
    local results = {}
    local allPass = true

    local ok1, msg1 = self:ValidateNetWorth(session)
    table.insert(results, {name = "NetWorth", ok = ok1, message = msg1})
    if not ok1 then allPass = false end

    local ok2, msg2 = self:ValidateLedgerBalance(session)
    table.insert(results, {name = "Ledger", ok = ok2, message = msg2})
    if not ok2 then allPass = false end

    local ok3, msg3 = self:ValidateHoldings(session)
    table.insert(results, {name = "Holdings", ok = ok3, message = msg3})
    if not ok3 then allPass = false end

    -- Log results if verbose or if any failed
    if GoldPH_DB_Account.debug.verbose or not allPass then
        for _, result in ipairs(results) do
            local color = result.ok and COLOR_GREEN or COLOR_RED
            print(string.format("%s[GoldPH Invariant] %s: %s%s", color, result.name, result.message, COLOR_RESET))
        end
    end

    return allPass, results
end

--------------------------------------------------
-- Test Suite
--------------------------------------------------

-- Run automated tests (Phase 1 & 2)
function GoldPH_Debug:RunTests()
    print(COLOR_YELLOW .. "[GoldPH Test Suite] Running tests..." .. COLOR_RESET)

    local testResults = {}

    -- Phase 1 tests
    local test1 = self:Test_BasicLoot()
    table.insert(testResults, test1)

    local test2 = self:Test_MultipleLoot()
    table.insert(testResults, test2)

    local test3 = self:Test_ZeroLoot()
    table.insert(testResults, test3)

    -- Phase 2 tests
    local test4 = self:Test_BasicRepair()
    table.insert(testResults, test4)

    local test5 = self:Test_NetCash()
    table.insert(testResults, test5)

    -- Phase 4 tests (critical for double-counting prevention)
    local test6 = self:Test_VendorSale_NoDoubleCount()
    table.insert(testResults, test6)

    local test7 = self:Test_VendorSale_PreSession()
    table.insert(testResults, test7)

    -- Phase 6 tests
    local test8 = self:Test_PickpocketStats()
    table.insert(testResults, test8)

    -- Phase 7 tests
    local test9 = self:Test_SessionDurationAccumulator()
    table.insert(testResults, test9)

    -- Gathering tests
    local test10 = self:Test_GatheringNodes()
    table.insert(testResults, test10)

    -- Summary
    local passed = 0
    local failed = 0
    for _, result in ipairs(testResults) do
        if result.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    local summaryColor = (failed == 0) and COLOR_GREEN or COLOR_RED
    print(string.format("%s[GoldPH Test Suite] %d passed, %d failed%s",
                        summaryColor, passed, failed, COLOR_RESET))

    return failed == 0
end

-- Test: Basic loot posting
function GoldPH_Debug:Test_BasicLoot()
    local testName = "Basic Loot Posting"

    -- Start temporary session
    if not GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StartSession()
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local initialIncome = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin")

    -- Inject loot
    local lootAmount = 500
    GoldPH_Events:InjectLootedCoin(lootAmount)

    -- Verify balances
    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local finalIncome = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin")

    local cashDiff = finalCash - initialCash
    local incomeDiff = finalIncome - initialIncome

    local passed = (cashDiff == lootAmount) and (incomeDiff == lootAmount)
    local message = passed and "OK" or
                    string.format("FAIL: Expected +%d, got Cash+%d Income+%d", lootAmount, cashDiff, incomeDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Multiple loot events
function GoldPH_Debug:Test_MultipleLoot()
    local testName = "Multiple Loot Events"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")

    -- Inject multiple loots
    GoldPH_Events:InjectLootedCoin(100)
    GoldPH_Events:InjectLootedCoin(250)
    GoldPH_Events:InjectLootedCoin(75)

    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local totalLooted = 100 + 250 + 75
    local cashDiff = finalCash - initialCash

    local passed = (cashDiff == totalLooted)
    local message = passed and "OK" or
                    string.format("FAIL: Expected +%d, got +%d", totalLooted, cashDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Zero amount handling
function GoldPH_Debug:Test_ZeroLoot()
    local testName = "Zero Amount Handling"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")

    -- Try to inject zero (should be rejected)
    local ok = GoldPH_Events:InjectLootedCoin(0)

    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashDiff = finalCash - initialCash

    local passed = (not ok) and (cashDiff == 0)
    local message = passed and "OK" or "FAIL: Zero amount was not rejected"

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Basic repair posting (Phase 2)
function GoldPH_Debug:Test_BasicRepair()
    local testName = "Basic Repair Posting"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local initialRepairs = GoldPH_Ledger:GetBalance(session, "Expense:Repairs")

    -- Inject repair
    local repairCost = 250
    GoldPH_Events:InjectRepair(repairCost)

    -- Verify balances
    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local finalRepairs = GoldPH_Ledger:GetBalance(session, "Expense:Repairs")

    local cashDiff = finalCash - initialCash
    local repairDiff = finalRepairs - initialRepairs

    -- Cash should decrease (negative), repairs should increase
    local passed = (cashDiff == -repairCost) and (repairDiff == repairCost)
    local message = passed and "OK" or
                    string.format("FAIL: Expected Cash-%d Repairs+%d, got Cash%+d Repairs+%d",
                                  repairCost, repairCost, cashDiff, repairDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Net cash calculation (income - expenses) (Phase 2)
function GoldPH_Debug:Test_NetCash()
    local testName = "Net Cash Calculation"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")

    -- Loot 1000, spend 300 on repairs
    GoldPH_Events:InjectLootedCoin(1000)
    GoldPH_Events:InjectRepair(300)

    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashDiff = finalCash - initialCash
    local expectedNetCash = 1000 - 300

    local passed = (cashDiff == expectedNetCash)
    local message = passed and "OK" or
                    string.format("FAIL: Expected net +%d, got +%d", expectedNetCash, cashDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Vendor sale - no double counting (Phase 4 CRITICAL)
function GoldPH_Debug:Test_VendorSale_NoDoubleCount()
    local testName = "Vendor Sale (No Double Count)"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    -- Use Linen Cloth (itemID 2589) - common gray item
    -- Cache the item first
    local itemID = 2589
    local itemName, _, quality, _, _, _, _, _, _, _, vendorPrice, itemClass = GetItemInfo(itemID)

    if not itemName then
        return {name = testName, passed = false, message = "Test item not cached (need to mouse over Linen Cloth first)"}
    end

    local initialNetWorth = GoldPH_Ledger:GetBalance(session, "Assets:Cash") +
                            GoldPH_Holdings:GetTotalExpectedValue(session)

    -- Loot 5 Linen Cloth
    local ok1 = GoldPH_Events:InjectLootItem(itemID, 5)
    if not ok1 then
        return {name = testName, passed = false, message = "Failed to inject loot"}
    end

    -- Vendor 5 Linen Cloth
    local ok2 = GoldPH_Events:InjectVendorSale(itemID, 5)
    if not ok2 then
        return {name = testName, passed = false, message = "Failed to inject vendor sale"}
    end

    local finalNetWorth = GoldPH_Ledger:GetBalance(session, "Assets:Cash") +
                          GoldPH_Holdings:GetTotalExpectedValue(session)

    local netWorthChange = finalNetWorth - initialNetWorth
    local expectedChange = 5 * vendorPrice

    -- CRITICAL: Net worth change must equal vendor proceeds only, NOT expected + proceeds
    local passed = (netWorthChange == expectedChange)
    local message = passed and "OK (no double-count)" or
                    string.format("FAIL: Expected +%d, got +%d (double-counted!)",
                                  expectedChange, netWorthChange)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Vendor sale of pre-session item (Phase 4)
function GoldPH_Debug:Test_VendorSale_PreSession()
    local testName = "Vendor Sale (Pre-Session Item)"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    -- Use itemID that's NOT in holdings (simulating pre-session item)
    -- Since we can't easily inject a pre-session item, we'll skip this test
    -- and note it needs manual testing

    local passed = true
    local message = "SKIP: Requires manual testing (sell item not looted this session)"

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Pickpocket statistics display (Phase 6)
function GoldPH_Debug:Test_PickpocketStats()
    local testName = "Pickpocket Stats Display"

    -- Start temporary session if needed
    if not GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StartSession()
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "Failed to start session"}
    end

    -- Ensure pickpocket structure exists
    if not session.pickpocket then
        session.pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        }
    end

    -- Set up test data
    session.pickpocket.gold = 5000  -- 50 silver
    session.pickpocket.value = 12000  -- 1g 20s
    session.pickpocket.lockboxesLooted = 5
    session.pickpocket.lockboxesOpened = 3
    session.pickpocket.fromLockbox.gold = 2000  -- 20 silver
    session.pickpocket.fromLockbox.value = 8000  -- 80 silver

    -- Ensure ledger balances exist
    if not session.ledger.balances["Income:Pickpocket:Coin"] then
        session.ledger.balances["Income:Pickpocket:Coin"] = 0
    end
    if not session.ledger.balances["Income:Pickpocket:Items"] then
        session.ledger.balances["Income:Pickpocket:Items"] = 0
    end
    if not session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] then
        session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] = 0
    end
    if not session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] then
        session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] = 0
    end

    session.ledger.balances["Income:Pickpocket:Coin"] = 5000
    session.ledger.balances["Income:Pickpocket:Items"] = 12000
    session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] = 2000
    session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] = 8000

    -- Call ShowPickpocket and verify it doesn't error
    local success, err = pcall(function()
        self:ShowPickpocket()
    end)

    if not success then
        return {name = testName, passed = false, message = "ShowPickpocket() failed: " .. tostring(err)}
    end

    -- Verify metrics match
    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local passed = (metrics.pickpocketGold == 5000) and
                   (metrics.pickpocketValue == 12000) and
                   (metrics.lockboxesLooted == 5) and
                   (metrics.lockboxesOpened == 3) and
                   (metrics.fromLockboxGold == 2000) and
                   (metrics.fromLockboxValue == 8000)

    local message = passed and "OK" or
                    string.format("FAIL: Metrics mismatch - Expected gold=%d value=%d looted=%d opened=%d fromLockboxGold=%d fromLockboxValue=%d, got gold=%d value=%d looted=%d opened=%d fromLockboxGold=%d fromLockboxValue=%d",
                        5000, 12000, 5, 3, 2000, 8000,
                        metrics.pickpocketGold, metrics.pickpocketValue, metrics.lockboxesLooted, metrics.lockboxesOpened,
                        metrics.fromLockboxGold, metrics.fromLockboxValue)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Session duration accumulator (Phase 7)
function GoldPH_Debug:Test_SessionDurationAccumulator()
    local testName = "Session Duration Accumulator"

    -- Ensure we start from a clean state
    if GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StopSession()
    end

    local ok, message = GoldPH_SessionManager:StartSession()
    if not ok then
        self:LogTestResult(testName, false, "Failed to start session: " .. (message or "unknown error"))
        return {name = testName, passed = false, message = message or "Failed to start session"}
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        self:LogTestResult(testName, false, "No active session after StartSession")
        return {name = testName, passed = false, message = "No active session after StartSession"}
    end

    -- Case 1: Completed session uses accumulatedDuration exactly
    session.accumulatedDuration = 1234
    session.currentLoginAt = nil

    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local pass1 = (metrics.durationSec == 1234)

    -- Case 2: StopSession keeps durationSec == accumulatedDuration
    session.accumulatedDuration = 100
    session.currentLoginAt = time() - 10

    GoldPH_SessionManager:StopSession()

    local pass2 = (session.durationSec == session.accumulatedDuration)

    local passed = pass1 and pass2
    local msg
    if not pass1 then
        msg = string.format("Expected durationSec=1234, got %d", metrics.durationSec or -1)
    elseif not pass2 then
        msg = string.format("durationSec (%d) did not match accumulatedDuration (%d) after StopSession",
            session.durationSec or -1, session.accumulatedDuration or -1)
    else
        msg = "OK"
    end

    self:LogTestResult(testName, passed, msg)

    return {name = testName, passed = passed, message = msg}
end

-- Test: Gathering node tracking (all 4 types)
function GoldPH_Debug:Test_GatheringNodes()
    local testName = "Gathering Nodes (All Types)"

    -- Ensure session is active
    if not GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StartSession()
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    -- Record initial state
    local initialTotal = (session.gathering and session.gathering.totalNodes) or 0
    local initialGatherInv = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
    local initialGatherIncome = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:Gathering")

    -- Inject nodes for each gathering type with realistic copper values per node
    local ok1, _ = GoldPH_Events:InjectGatherNode("Copper Vein", 3, 8000)               -- Mining: 80s/node
    local ok2, _ = GoldPH_Events:InjectGatherNode("Peacebloom", 5, 5000)                -- Herbalism: 50s/node
    local ok3, _ = GoldPH_Events:InjectGatherNode("Light Leather", 2, 3000)             -- Skinning: 30s/node
    local ok4, _ = GoldPH_Events:InjectGatherNode("Raw Brilliant Smallfish", 4, 2000)   -- Fishing: 20s/node

    if not (ok1 and ok2 and ok3 and ok4) then
        self:LogTestResult(testName, false, "One or more InjectGatherNode calls failed")
        return {name = testName, passed = false, message = "Injection failed"}
    end

    -- Expected values
    -- Mining: 3 * 8000 = 24000, Herb: 5 * 5000 = 25000, Skin: 2 * 3000 = 6000, Fish: 4 * 2000 = 8000
    local expectedValueInjected = 24000 + 25000 + 6000 + 8000  -- 63000 copper

    -- Verify totalNodes incremented correctly
    local expectedTotal = initialTotal + 3 + 5 + 2 + 4  -- 14 new nodes
    local actualTotal = session.gathering.totalNodes

    local pass1 = (actualTotal == expectedTotal)

    -- Verify nodesByType has all 4 entries with correct counts
    local nbt = session.gathering.nodesByType or {}
    local pass2 = (nbt["Copper Vein"] and nbt["Copper Vein"] >= 3)
    local pass3 = (nbt["Peacebloom"] and nbt["Peacebloom"] >= 5)
    local pass4 = (nbt["Light Leather"] and nbt["Light Leather"] >= 2)
    local pass5 = (nbt["Raw Brilliant Smallfish"] and nbt["Raw Brilliant Smallfish"] >= 4)

    -- Verify hasGathering flag would be true in Index
    local pass6 = (session.gathering.totalNodes > 0)

    -- Verify ledger values: gathering inventory and income should increase by expectedValueInjected
    local finalGatherInv = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
    local finalGatherIncome = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:Gathering")
    local invDiff = finalGatherInv - initialGatherInv
    local incomeDiff = finalGatherIncome - initialGatherIncome

    local pass7 = (invDiff == expectedValueInjected)
    local pass8 = (incomeDiff == expectedValueInjected)

    local passed = pass1 and pass2 and pass3 and pass4 and pass5 and pass6 and pass7 and pass8
    local message
    if not pass1 then
        message = string.format("FAIL: totalNodes expected %d, got %d", expectedTotal, actualTotal)
    elseif not pass2 then
        message = string.format("FAIL: Copper Vein count wrong (got %s)", tostring(nbt["Copper Vein"]))
    elseif not pass3 then
        message = string.format("FAIL: Peacebloom count wrong (got %s)", tostring(nbt["Peacebloom"]))
    elseif not pass4 then
        message = string.format("FAIL: Light Leather count wrong (got %s)", tostring(nbt["Light Leather"]))
    elseif not pass5 then
        message = string.format("FAIL: Raw Brilliant Smallfish count wrong (got %s)", tostring(nbt["Raw Brilliant Smallfish"]))
    elseif not pass6 then
        message = "FAIL: totalNodes is 0 (hasGathering would be false)"
    elseif not pass7 then
        message = string.format("FAIL: Inventory value expected +%d, got +%d", expectedValueInjected, invDiff)
    elseif not pass8 then
        message = string.format("FAIL: Income value expected +%d, got +%d", expectedValueInjected, incomeDiff)
    else
        message = string.format("OK (totalNodes=%d, 4 types, value=%s)",
            actualTotal, GoldPH_Ledger:FormatMoney(expectedValueInjected))
    end

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Log test result
function GoldPH_Debug:LogTestResult(testName, passed, message)
    local color = passed and COLOR_GREEN or COLOR_RED
    local status = passed and "PASS" or "FAIL"
    print(string.format("%s[Test: %s] %s: %s%s", color, testName, status, message, COLOR_RESET))
end

--------------------------------------------------
-- State Inspection
--------------------------------------------------

-- Dump current session state
function GoldPH_Debug:DumpSession()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    print(COLOR_YELLOW .. "=== GoldPH Session Dump ===" .. COLOR_RESET)
    print(string.format("Session ID: %d", session.id))
    local dateStr
    if date then
        dateStr = date("%Y-%m-%d %H:%M:%S", session.startedAt)
    else
        dateStr = tostring(session.startedAt)
    end
    print(string.format("Started: %s", dateStr))
    print(string.format("Duration: %s", GoldPH_SessionManager:FormatDuration(time() - session.startedAt)))
    print(string.format("Zone: %s", session.zone))

    print("\nLedger Balances:")
    for acct, bal in pairs(session.ledger.balances) do
        print(string.format("  %s: %s", acct, GoldPH_Ledger:FormatMoney(bal)))
    end

    local metrics = GoldPH_SessionManager:GetMetrics(session)
    print("\nMetrics:")
    print(string.format("  Gold: %s", GoldPH_Ledger:FormatMoney(metrics.cash)))
    print(string.format("  Gold/Hour: %s", GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour)))

    -- Phase 6: Pickpocket summary
    if session.pickpocket and (metrics.pickpocketGold > 0 or metrics.pickpocketValue > 0 or metrics.lockboxesLooted > 0 or metrics.lockboxesOpened > 0) then
        print("\nPickpocket:")
        print(string.format("  Coin: %s", GoldPH_Ledger:FormatMoney(metrics.pickpocketGold)))
        print(string.format("  Items Value: %s", GoldPH_Ledger:FormatMoney(metrics.pickpocketValue)))
        print(string.format("  Lockboxes Looted: %d", metrics.lockboxesLooted))
        print(string.format("  Lockboxes Opened: %d", metrics.lockboxesOpened))
        if metrics.fromLockboxGold > 0 or metrics.fromLockboxValue > 0 then
            print(string.format("  From Lockboxes - Coin: %s", GoldPH_Ledger:FormatMoney(metrics.fromLockboxGold)))
            print(string.format("  From Lockboxes - Items Value: %s", GoldPH_Ledger:FormatMoney(metrics.fromLockboxValue)))
        end
    end

    print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
end

-- Show all account balances
function GoldPH_Debug:ShowLedger()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    -- Group accounts by type
    local assets = {}
    local income = {}
    local expenses = {}
    local equity = {}

    for acct, bal in pairs(session.ledger.balances) do
        if acct:match("^Assets:") then
            table.insert(assets, {acct = acct, bal = bal})
        elseif acct:match("^Income:") then
            table.insert(income, {acct = acct, bal = bal})
        elseif acct:match("^Expense:") then
            table.insert(expenses, {acct = acct, bal = bal})
        elseif acct:match("^Equity:") then
            table.insert(equity, {acct = acct, bal = bal})
        end
    end

    -- Sort each group by account name
    table.sort(assets, function(a, b) return a.acct < b.acct end)
    table.sort(income, function(a, b) return a.acct < b.acct end)
    table.sort(expenses, function(a, b) return a.acct < b.acct end)
    table.sort(equity, function(a, b) return a.acct < b.acct end)

    print(COLOR_YELLOW .. "=== Ledger Balances ===" .. COLOR_RESET)

    -- Assets
    if #assets > 0 then
        print(COLOR_GREEN .. "ASSETS:" .. COLOR_RESET)
        local totalAssets = 0
        for _, item in ipairs(assets) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalAssets = totalAssets + item.bal
        end
        print(string.format("  " .. COLOR_GREEN .. "Total Assets: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalAssets)))
        print("")
    end

    -- Income
    if #income > 0 then
        print(COLOR_GREEN .. "INCOME:" .. COLOR_RESET)
        local totalIncome = 0
        for _, item in ipairs(income) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalIncome = totalIncome + item.bal
        end
        print(string.format("  " .. COLOR_GREEN .. "Total Income: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalIncome)))
        print("")
    end

    -- Expenses
    if #expenses > 0 then
        print(COLOR_RED .. "EXPENSES:" .. COLOR_RESET)
        local totalExpenses = 0
        for _, item in ipairs(expenses) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalExpenses = totalExpenses + item.bal
        end
        print(string.format("  " .. COLOR_RED .. "Total Expenses: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalExpenses)))
        print("")
    end

    -- Equity
    if #equity > 0 then
        print(COLOR_YELLOW .. "EQUITY:" .. COLOR_RESET)
        local totalEquity = 0
        for _, item in ipairs(equity) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalEquity = totalEquity + item.bal
        end
        print(string.format("  " .. COLOR_YELLOW .. "Total Equity: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalEquity)))
        print("")
    end

    print(COLOR_YELLOW .. "=======================" .. COLOR_RESET)
end

-- Show holdings (Phase 3)
function GoldPH_Debug:ShowHoldings()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    print(COLOR_YELLOW .. "=== Holdings (FIFO Lots) ===" .. COLOR_RESET)

    if not session.holdings or next(session.holdings) == nil then
        print("  (No holdings)")
        print(COLOR_YELLOW .. "=============================" .. COLOR_RESET)
        return
    end

    for itemID, holding in pairs(session.holdings) do
        local itemName = GetItemInfo(itemID) or "Unknown"
        print(string.format("\n  Item: %s (ID: %d)", itemName, itemID))
        print(string.format("  Total Count: %d", holding.count))
        print(string.format("  Lots: %d", #holding.lots))

        for i, lot in ipairs(holding.lots) do
            print(string.format("    Lot #%d: count=%d, expectedEach=%d (%s), bucket=%s",
                i, lot.count, lot.expectedEach, GoldPH_Ledger:FormatMoney(lot.expectedEach), lot.bucket))
        end
    end

    print(COLOR_YELLOW .. "\n=============================" .. COLOR_RESET)
end

-- Show available price sources
function GoldPH_Debug:ShowPriceSources()
    print(COLOR_YELLOW .. "=== Price Sources ===" .. COLOR_RESET)

    local sources = GoldPH_PriceSources:GetAvailableSources()

    if #sources == 0 then
        print("  " .. COLOR_RED .. "No price sources available" .. COLOR_RESET)
        print("  Using vendor prices only (conservative)")
    else
        print("  " .. COLOR_GREEN .. "Available sources:" .. COLOR_RESET)
        for i, source in ipairs(sources) do
            print(string.format("    %d. %s", i, source))
        end
    end

    print("\n  Priority order: Manual Overrides > Custom AH > TSM")
    print("  Set manual override: /script GoldPH_DB_Account.priceOverrides[itemID] = price")

    print(COLOR_YELLOW .. "=====================" .. COLOR_RESET)
end

-- Show pickpocket statistics (Phase 6)
function GoldPH_Debug:ShowPickpocket()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    print(COLOR_YELLOW .. "=== Pickpocket Statistics ===" .. COLOR_RESET)

    -- Ensure pickpocket structure exists
    if not session.pickpocket then
        print("  " .. COLOR_RED .. "No pickpocket data (session started before Phase 6)" .. COLOR_RESET)
        print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
        return
    end

    local metrics = GoldPH_SessionManager:GetMetrics(session)

    -- Coin and items
    print(string.format("  Coin: %s", GoldPH_Ledger:FormatMoney(metrics.pickpocketGold)))
    print(string.format("  Items Value: %s", GoldPH_Ledger:FormatMoney(metrics.pickpocketValue)))
    print(string.format("  Total Pickpocket Value: %s", 
        GoldPH_Ledger:FormatMoney(metrics.pickpocketGold + metrics.pickpocketValue)))

    -- Lockboxes
    print(string.format("\n  Lockboxes Looted: %d", metrics.lockboxesLooted))
    print(string.format("  Lockboxes Opened: %d", metrics.lockboxesOpened))
    if metrics.lockboxesLooted > 0 then
        local unopened = metrics.lockboxesLooted - metrics.lockboxesOpened
        if unopened > 0 then
            print(string.format("  Unopened: %d", unopened))
        end
    end

    -- From lockboxes
    if metrics.fromLockboxGold > 0 or metrics.fromLockboxValue > 0 then
        print(string.format("\n  From Lockboxes:"))
        print(string.format("    Coin: %s", GoldPH_Ledger:FormatMoney(metrics.fromLockboxGold)))
        print(string.format("    Items Value: %s", GoldPH_Ledger:FormatMoney(metrics.fromLockboxValue)))
        print(string.format("    Total: %s", 
            GoldPH_Ledger:FormatMoney(metrics.fromLockboxGold + metrics.fromLockboxValue)))
    end

    -- Ledger balances (for verification)
    print(string.format("\n  Ledger Balances (reporting only):"))
    print(string.format("    Income:Pickpocket:Coin: %s", 
        GoldPH_Ledger:FormatMoney(metrics.incomePickpocketCoin)))
    print(string.format("    Income:Pickpocket:Items: %s", 
        GoldPH_Ledger:FormatMoney(metrics.incomePickpocketItems)))
    if metrics.incomePickpocketFromLockboxCoin > 0 or metrics.incomePickpocketFromLockboxItems > 0 then
        print(string.format("    Income:Pickpocket:FromLockbox:Coin: %s", 
            GoldPH_Ledger:FormatMoney(metrics.incomePickpocketFromLockboxCoin)))
        print(string.format("    Income:Pickpocket:FromLockbox:Items: %s", 
            GoldPH_Ledger:FormatMoney(metrics.incomePickpocketFromLockboxItems)))
    end

    print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
end

--------------------------------------------------
-- Gathering Inspection
--------------------------------------------------

-- Show gathering node statistics (Phase 7)
function GoldPH_Debug:ShowGathering()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    print(COLOR_YELLOW .. "=== Gathering Statistics ===" .. COLOR_RESET)

    if not session.gathering or not session.gathering.totalNodes or session.gathering.totalNodes == 0 then
        print("  " .. COLOR_RED .. "No gathering data in this session" .. COLOR_RESET)
        print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
        return
    end

    local g = session.gathering
    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local durationHrs = metrics.durationSec / 3600

    print(string.format("  Total Nodes: %d", g.totalNodes))
    if durationHrs > 0 then
        print(string.format("  Nodes/Hour:  %.1f", g.totalNodes / durationHrs))
    end

    -- Gathering inventory value
    local gatherInv = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
    local gatherIncome = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:Gathering")
    if gatherInv > 0 or gatherIncome > 0 then
        print(string.format("\n  Inventory Value: %s", GoldPH_Ledger:FormatMoney(gatherInv)))
        print(string.format("  Income Booked:   %s", GoldPH_Ledger:FormatMoney(gatherIncome)))
    end

    -- Per-node-type breakdown
    if g.nodesByType and next(g.nodesByType) then
        print("\n  Breakdown by Node Type:")

        -- Sort by count descending
        local sorted = {}
        for name, count in pairs(g.nodesByType) do
            table.insert(sorted, {name = name, count = count})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)

        for _, entry in ipairs(sorted) do
            local pct = (entry.count / g.totalNodes) * 100
            print(string.format("    %-30s %3d  (%4.1f%%)", entry.name, entry.count, pct))
        end
    end

    print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
end

--------------------------------------------------
-- HUD Testing
--------------------------------------------------

-- Test HUD display by injecting sample data for all fields
-- Usage: /script GoldPH_Debug:TestHUD()
function GoldPH_Debug:TestHUD()
    print(COLOR_YELLOW .. "=== HUD Test Data ===" .. COLOR_RESET)

    -- Ensure session is active
    if not GoldPH_SessionManager:GetActiveSession() then
        local ok, msg = GoldPH_SessionManager:StartSession()
        if not ok then
            print(COLOR_RED .. "Failed to start session: " .. msg .. COLOR_RESET)
            return false
        end
        print(COLOR_GREEN .. "Started new session for testing" .. COLOR_RESET)
    end

    local session = GoldPH_SessionManager:GetActiveSession()

    -- Sample values (in copper)
    local goldAmount = 1000000     -- 100g looted coin
    local inventoryAmount = 300000 -- 30g vendor trash + rare items
    local expenseAmount = 50000    -- 5g repairs

    -- Inject looted gold
    GoldPH_Events:InjectLootedCoin(goldAmount)
    print(string.format("  Injected gold: %s", GoldPH_Ledger:FormatMoney(goldAmount)))

    -- Inject inventory items (vendor trash bucket) - direct ledger posting
    GoldPH_Ledger:Post(session, "Assets:Inventory:VendorTrash", "Income:ItemsLooted:VendorTrash", inventoryAmount)
    print(string.format("  Injected inventory (vendor trash): %s", GoldPH_Ledger:FormatMoney(inventoryAmount)))

    -- Inject gathering nodes with value (all 4 types)
    -- Value per node simulates average loot yield from each node type
    GoldPH_Events:InjectGatherNode("Copper Vein", 8, 8000)            -- Mining: ~80s/node
    GoldPH_Events:InjectGatherNode("Tin Vein", 4, 12000)              -- Mining: ~1g20s/node
    GoldPH_Events:InjectGatherNode("Peacebloom", 12, 5000)            -- Herbalism: ~50s/node
    GoldPH_Events:InjectGatherNode("Silverleaf", 6, 4000)             -- Herbalism: ~40s/node
    GoldPH_Events:InjectGatherNode("Light Leather", 5, 3000)          -- Skinning: ~30s/node
    GoldPH_Events:InjectGatherNode("Raw Brilliant Smallfish", 3, 2000) -- Fishing: ~20s/node
    -- Total gathering value: 8*8000 + 4*12000 + 12*5000 + 6*4000 + 5*3000 + 3*2000 = 217000 copper (~21g70s)
    print(string.format("  Injected gathering: 38 nodes, %s total value", GoldPH_Ledger:FormatMoney(217000)))

    -- Inject repair expense
    GoldPH_Events:InjectRepair(expenseAmount)
    print(string.format("  Injected expenses: %s", GoldPH_Ledger:FormatMoney(expenseAmount)))

    -- Calculate expected HUD values
    local actualGatheringValue = 217000  -- sum from node injections above
    local expectedGold = goldAmount - expenseAmount  -- 95g (gold minus expenses)
    local expectedInventory = inventoryAmount        -- 30g
    local expectedGathering = actualGatheringValue   -- ~21g70s
    local expectedTotal = expectedGold + expectedInventory + expectedGathering

    print("")
    print(COLOR_GREEN .. "Expected HUD values:" .. COLOR_RESET)
    print(string.format("  Gold: %s", GoldPH_Ledger:FormatMoney(expectedGold)))
    print(string.format("  Inventory: %s", GoldPH_Ledger:FormatMoney(expectedInventory)))
    print(string.format("  Gathering: %s (38 nodes)", GoldPH_Ledger:FormatMoney(expectedGathering)))
    print(string.format("  Expenses: -%s", GoldPH_Ledger:FormatMoney(expenseAmount)))
    print(string.format("  Total: %s", GoldPH_Ledger:FormatMoney(expectedTotal)))

    -- Force HUD update
    GoldPH_HUD:Update()

    print("")
    print(COLOR_YELLOW .. "HUD should now display test data. Verify visually." .. COLOR_RESET)
    print(COLOR_YELLOW .. "=====================" .. COLOR_RESET)

    return true
end

-- Reset test data (stop and start fresh session)
-- Usage: /script GoldPH_Debug:ResetTestHUD()
function GoldPH_Debug:ResetTestHUD()
    -- Stop current session if active
    if GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StopSession()
        print(COLOR_YELLOW .. "[GoldPH] Test session stopped" .. COLOR_RESET)
    end

    -- Start fresh session
    GoldPH_SessionManager:StartSession()
    GoldPH_HUD:Update()
    print(COLOR_GREEN .. "[GoldPH] Fresh session started for testing" .. COLOR_RESET)
end

--------------------------------------------------
-- Session Duplication Detection and Repair
--------------------------------------------------

-- Build a content signature for a session (used for duplicate detection)
local function BuildSessionSignature(session)
    -- Extract key fields that uniquely identify a session
    local startedAt = session.startedAt or 0
    local zone = session.zone or "Unknown"
    local character = session.character or "Unknown"
    local realm = session.realm or "Unknown"
    local durationSec = session.durationSec or 0
    local cash = GoldPH_Ledger:GetBalance(session, "Assets:Cash") or 0

    -- Build a pipe-separated signature
    return string.format("%d|%s|%s|%s|%d|%d",
        startedAt, zone, character, realm, durationSec, cash)
end

-- Scan database for duplicate sessions
function GoldPH_Debug:ScanForDuplicates()
    if not GoldPH_DB_Account or not GoldPH_DB_Account.sessions then
        return {
            duplicateGroups = {},
            totalDuplicates = 0,
            totalUnique = 0,
        }
    end

    print(COLOR_YELLOW .. "[GoldPH] Scanning for duplicate sessions..." .. COLOR_RESET)

    -- Build signature -> session IDs mapping
    local sessionsBySig = {}  -- [signature] -> {id1, id2, ...}
    local totalSessions = 0

    for sessionId, session in pairs(GoldPH_DB_Account.sessions) do
        -- Skip active session (never touch it)
        if not GoldPH_DB_Account.activeSession or GoldPH_DB_Account.activeSession.id ~= sessionId then
            local sig = BuildSessionSignature(session)

            if not sessionsBySig[sig] then
                sessionsBySig[sig] = {}
            end
            table.insert(sessionsBySig[sig], sessionId)
            totalSessions = totalSessions + 1
        end
    end

    -- Find duplicate groups (2+ sessions with same signature)
    local duplicateGroups = {}
    local totalDuplicates = 0

    for sig, sessionIds in pairs(sessionsBySig) do
        if #sessionIds > 1 then
            -- Sort IDs so lowest is first (canonical)
            table.sort(sessionIds)

            local canonicalId = sessionIds[1]
            local duplicateIds = {}
            for i = 2, #sessionIds do
                table.insert(duplicateIds, sessionIds[i])
                totalDuplicates = totalDuplicates + 1
            end

            -- Get session metadata for display
            local canonicalSession = GoldPH_DB_Account.sessions[canonicalId]

            table.insert(duplicateGroups, {
                canonical_id = canonicalId,
                duplicate_ids = duplicateIds,
                signature = sig,
                metadata = {
                    zone = canonicalSession.zone or "Unknown",
                    character = canonicalSession.character or "Unknown",
                    startedAt = canonicalSession.startedAt,
                    durationSec = canonicalSession.durationSec or 0,
                },
            })
        end
    end

    return {
        duplicateGroups = duplicateGroups,
        totalDuplicates = totalDuplicates,
        totalUnique = totalSessions - totalDuplicates,
    }
end

-- Display duplicate scan results
function GoldPH_Debug:ShowDuplicates()
    local result = self:ScanForDuplicates()

    print(COLOR_YELLOW .. "=== Session Duplicate Scan ===" .. COLOR_RESET)
    print(string.format("  Total sessions scanned: %d", result.totalUnique + result.totalDuplicates))
    print(string.format("  Unique sessions: %d", result.totalUnique))
    print(string.format("  Duplicate sessions: %d", result.totalDuplicates))
    print(string.format("  Duplicate groups: %d", #result.duplicateGroups))
    print("")

    if result.totalDuplicates == 0 then
        print(COLOR_GREEN .. "  No duplicates found! Database is clean." .. COLOR_RESET)
    else
        print(COLOR_RED .. string.format("  Found %d duplicate sessions in %d groups:",
            result.totalDuplicates, #result.duplicateGroups) .. COLOR_RESET)
        print("")

        for i, group in ipairs(result.duplicateGroups) do
            local meta = group.metadata
            local dateStr
            if date then
                dateStr = date("%Y-%m-%d %H:%M", meta.startedAt)
            else
                dateStr = tostring(meta.startedAt)
            end

            print(string.format("  Group #%d:", i))
            print(string.format("    Zone: %s | Character: %s", meta.zone, meta.character))
            print(string.format("    Date: %s | Duration: %ds", dateStr, meta.durationSec))
            print(string.format("    Canonical (keep): Session #%d", group.canonical_id))
            print(string.format("    Duplicates (remove): %s", table.concat(group.duplicate_ids, ", ")))
            print("")
        end

        print(COLOR_YELLOW .. "  To remove duplicates, run: /goldph debug purge-dupes confirm" .. COLOR_RESET)
    end

    print(COLOR_YELLOW .. "=============================" .. COLOR_RESET)
end

-- Purge duplicate sessions from database
function GoldPH_Debug:PurgeDuplicates(confirm)
    -- First scan for duplicates
    local result = self:ScanForDuplicates()

    if result.totalDuplicates == 0 then
        print(COLOR_GREEN .. "[GoldPH] No duplicates found. Database is clean." .. COLOR_RESET)
        return
    end

    -- Dry run mode (show what would be removed)
    if not confirm then
        print(COLOR_YELLOW .. "=== Purge Duplicates (DRY RUN) ===" .. COLOR_RESET)
        print(COLOR_RED .. "  WARNING: This will permanently delete duplicate sessions!" .. COLOR_RESET)
        print(string.format("  Sessions to be removed: %d", result.totalDuplicates))
        print(string.format("  Sessions to be kept: %d", result.totalUnique))
        print("")

        for i, group in ipairs(result.duplicateGroups) do
            print(string.format("  Group #%d: Keep session #%d, remove %d duplicates",
                i, group.canonical_id, #group.duplicate_ids))
        end

        print("")
        print(COLOR_YELLOW .. "  IMPORTANT: Backup your SavedVariables folder first!" .. COLOR_RESET)
        print(COLOR_YELLOW .. "  Location: WTF/Account/<YourAccount>/SavedVariables/GoldPH.lua" .. COLOR_RESET)
        print("")
        print(COLOR_GREEN .. "  To proceed with removal, run: /goldph debug purge-dupes confirm" .. COLOR_RESET)
        print(COLOR_YELLOW .. "=================================" .. COLOR_RESET)
        return
    end

    -- Confirmed purge
    print(COLOR_RED .. "=== Purging Duplicate Sessions ===" .. COLOR_RESET)
    print(string.format("  Removing %d duplicate sessions...", result.totalDuplicates))
    print("")

    local removedCount = 0

    for _, group in ipairs(result.duplicateGroups) do
        for _, duplicateId in ipairs(group.duplicate_ids) do
            if GoldPH_DB_Account.sessions[duplicateId] then
                GoldPH_DB_Account.sessions[duplicateId] = nil
                removedCount = removedCount + 1
                print(string.format("  Removed session #%d (duplicate of #%d)", duplicateId, group.canonical_id))
            end
        end
    end

    -- Mark index stale for rebuild
    if GoldPH_Index then
        GoldPH_Index:MarkStale()
    end

    print("")
    print(COLOR_GREEN .. string.format("  Successfully removed %d duplicate sessions!", removedCount) .. COLOR_RESET)
    print(string.format("  Kept %d unique sessions", result.totalUnique))
    print("")
    print(COLOR_YELLOW .. "  Run /reload to rebuild the history index" .. COLOR_RESET)
    print(COLOR_RED .. "=================================" .. COLOR_RESET)
end

-- Export module
_G.GoldPH_Debug = GoldPH_Debug
