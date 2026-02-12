-- Debug XP Tracking
-- luacheck: globals GoldPH_SessionManager UnitLevel MAX_PLAYER_LEVEL UnitXP UnitXPMax
-- Run this in-game with: /script [paste code below]

local function DebugXPTracking()
    print("=== XP Tracking Debug ===")

    -- Check if session exists
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print("ERROR: No active session")
        return
    end
    print("Session ID: " .. tostring(session.id))

    -- Check player level
    local level = UnitLevel("player")
    local maxLevel = MAX_PLAYER_LEVEL or 60
    print("Player Level: " .. level .. " / " .. maxLevel)

    if level >= maxLevel then
        print("WARNING: At max level - XP tracking disabled")
        return
    end

    -- Check XP values
    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    print("Current XP: " .. currentXP .. " / " .. maxXP)

    -- Check session metrics structure
    if not session.metrics then
        print("ERROR: session.metrics is nil")
        return
    end
    print("session.metrics exists: YES")

    if not session.metrics.xp then
        print("ERROR: session.metrics.xp is nil")
        return
    end
    print("session.metrics.xp exists: YES")

    -- Check XP metrics values
    print("xpGained: " .. tostring(session.metrics.xp.gained))
    print("xpEnabled: " .. tostring(session.metrics.xp.enabled))

    -- Check snapshots
    if session.snapshots and session.snapshots.xp then
        print("Snapshot XP: " .. tostring(session.snapshots.xp.cur) .. " / " .. tostring(session.snapshots.xp.max))
    else
        print("WARNING: No XP snapshots")
    end

    -- Check computed metrics
    local metrics = GoldPH_SessionManager:GetMetrics(session)
    if metrics then
        print("\n=== Computed Metrics ===")
        print("xpGained: " .. tostring(metrics.xpGained))
        print("xpPerHour: " .. tostring(metrics.xpPerHour))
        print("xpEnabled: " .. tostring(metrics.xpEnabled))
        print("durationHours: " .. tostring(metrics.durationHours))
    else
        print("ERROR: GetMetrics returned nil")
    end

    print("\n=== Done ===")
end

-- Run the debug
DebugXPTracking()
