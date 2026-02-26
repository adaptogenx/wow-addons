--[[
    AutoSession.lua - Source-aware automatic session start/pause/resume management

    Features:
    - Source-based auto-start/auto-resume rules
    - Prompt-based start policy for ambiguous events
    - Auto-pause on AFK/inactivity
    - Instance entry start behavior
    - Lifecycle-safe runtime state reset (prevents stale/circular behavior)
]]

-- luacheck: globals pH_SessionManager pH_Settings pH_HUD pH_Colors UnitIsAFK IsInInstance GetTime time GetFactionInfo GetNumFactions UnitXP UnitLevel GetMaxPlayerLevel GetSpellInfo UIParent

local pH_AutoSession = {}

local PROFILE_MANUAL = "manual"
local PROFILE_BALANCED = "balanced"
local PROFILE_HANDSFREE = "handsfree"

local ACTION_OFF = "off"
local ACTION_PROMPT = "prompt"
local ACTION_AUTO = "auto"

local PROMPT_NEVER = "never"
local PROMPT_SMART = "smart"
local PROMPT_ALWAYS = "always"

local INSTANCE_START_PAUSED = "paused"
local INSTANCE_START_ACTIVE = "active"
local QUEST_TURNIN_WINDOW_SEC = 8.0
local REP_KILL_SIGNAL_SEC = 2.5

local SOURCE_LABELS = {
    ["xp.mob_kill"] = "XP: Mob kill",
    ["xp.quest_turnin"] = "XP: Quest turn-in",
    ["xp.zone_discovery"] = "XP: Zone discovery",
    ["xp.other"] = "XP: Other",

    ["gold.mob_loot_coin"] = "Gold: Looted coin",
    ["gold.treasure_or_container_coin"] = "Gold: Treasure/container",
    ["gold.lockbox_coin"] = "Gold: Lockbox",
    ["gold.pickpocket_coin"] = "Gold: Pickpocket",
    ["gold.quest_reward"] = "Gold: Quest reward",
    ["gold.vendor_sale"] = "Gold: Vendor sale",
    ["gold.mail"] = "Gold: Mail",
    ["gold.auction_payout"] = "Gold: Auction payout",
    ["gold.trade_or_cod"] = "Gold: Trade/COD",
    ["gold.other"] = "Gold: Other",

    ["rep.mob_kill"] = "Rep: Mob kill",
    ["rep.quest_turnin"] = "Rep: Quest turn-in",
    ["rep.item_turnin"] = "Rep: Item turn-in",
    ["rep.other"] = "Rep: Other",

    ["gathering.node"] = "Gathering",
    ["honor.gain"] = "Honor",
}

local ALL_SOURCES = {
    "xp.mob_kill", "xp.quest_turnin", "xp.zone_discovery", "xp.other",
    "gold.mob_loot_coin", "gold.treasure_or_container_coin", "gold.lockbox_coin", "gold.pickpocket_coin",
    "gold.quest_reward", "gold.vendor_sale", "gold.mail", "gold.auction_payout", "gold.trade_or_cod", "gold.other",
    "rep.mob_kill", "rep.quest_turnin", "rep.item_turnin", "rep.other",
    "gathering.node", "honor.gain",
}

local function BuildRules(defaultAction)
    local rules = {}
    for _, source in ipairs(ALL_SOURCES) do
        rules[source] = { action = defaultAction }
    end
    return rules
end

local function BuildProfile(profile)
    local start = BuildRules(ACTION_OFF)
    local resume = BuildRules(ACTION_OFF)

    if profile == PROFILE_HANDSFREE then
        for source, entry in pairs(start) do
            if source ~= "gold.mail" and source ~= "gold.auction_payout" and source ~= "gold.trade_or_cod" and source ~= "gold.vendor_sale" then
                entry.action = ACTION_AUTO
            end
        end
        for source, entry in pairs(resume) do
            if source ~= "gold.mail" and source ~= "gold.auction_payout" and source ~= "gold.trade_or_cod" and source ~= "gold.vendor_sale" then
                entry.action = ACTION_AUTO
            end
        end
        start["xp.zone_discovery"].action = ACTION_PROMPT
        resume["xp.zone_discovery"].action = ACTION_OFF
    elseif profile ~= PROFILE_MANUAL then
        -- Balanced defaults
        start["gathering.node"].action = ACTION_AUTO
        resume["gathering.node"].action = ACTION_AUTO

        start["xp.mob_kill"].action = ACTION_AUTO
        resume["xp.mob_kill"].action = ACTION_AUTO

        start["honor.gain"].action = ACTION_AUTO
        resume["honor.gain"].action = ACTION_AUTO

        start["gold.mob_loot_coin"].action = ACTION_AUTO
        resume["gold.mob_loot_coin"].action = ACTION_AUTO

        start["gold.lockbox_coin"].action = ACTION_PROMPT
        resume["gold.lockbox_coin"].action = ACTION_AUTO

        start["gold.pickpocket_coin"].action = ACTION_AUTO
        resume["gold.pickpocket_coin"].action = ACTION_AUTO

        start["xp.zone_discovery"].action = ACTION_OFF
        resume["xp.zone_discovery"].action = ACTION_OFF

        start["xp.quest_turnin"].action = ACTION_PROMPT
        resume["xp.quest_turnin"].action = ACTION_OFF

        start["gold.quest_reward"].action = ACTION_OFF
        resume["gold.quest_reward"].action = ACTION_OFF

        start["gold.vendor_sale"].action = ACTION_OFF
        resume["gold.vendor_sale"].action = ACTION_OFF

        start["gold.mail"].action = ACTION_OFF
        resume["gold.mail"].action = ACTION_OFF

        start["gold.auction_payout"].action = ACTION_OFF
        resume["gold.auction_payout"].action = ACTION_OFF

        start["gold.trade_or_cod"].action = ACTION_OFF
        resume["gold.trade_or_cod"].action = ACTION_OFF

        start["gold.other"].action = ACTION_PROMPT
        resume["gold.other"].action = ACTION_AUTO

        start["xp.other"].action = ACTION_PROMPT
        resume["xp.other"].action = ACTION_AUTO

        start["rep.mob_kill"].action = ACTION_PROMPT
        resume["rep.mob_kill"].action = ACTION_AUTO

        start["rep.quest_turnin"].action = ACTION_OFF
        resume["rep.quest_turnin"].action = ACTION_OFF

        start["rep.item_turnin"].action = ACTION_OFF
        resume["rep.item_turnin"].action = ACTION_OFF

        start["rep.other"].action = ACTION_OFF
        resume["rep.other"].action = ACTION_OFF
    end

    return start, resume
end

local function EnsureRuleShape(map, fallbackAction)
    if type(map) ~= "table" then
        map = {}
    end
    for _, source in ipairs(ALL_SOURCES) do
        if type(map[source]) ~= "table" then
            map[source] = { action = fallbackAction }
        end
        local action = map[source].action
        if action ~= ACTION_OFF and action ~= ACTION_PROMPT and action ~= ACTION_AUTO then
            map[source].action = fallbackAction
        end
    end
    return map
end

local function MigrateSettings()
    if not pH_Settings then
        pH_Settings = {}
    end

    local cfg = pH_Settings.autoSession
    if type(cfg) ~= "table" then
        cfg = {}
        pH_Settings.autoSession = cfg
    end

    -- Migrate legacy bool-style settings
    local oldAutoStart = cfg.autoStart
    local oldInstanceStart = cfg.instanceStart
    local oldAfkPause = cfg.afkPause
    local oldInactivityPromptMin = cfg.inactivityPromptMin
    local oldInactivityPauseMin = cfg.inactivityPauseMin
    local oldAutoResume = cfg.autoResume

    if cfg.enabled == nil then
        cfg.enabled = true
    end

    if type(cfg.profiles) ~= "table" then
        cfg.profiles = {}
    end
    if cfg.profiles.default ~= PROFILE_MANUAL and cfg.profiles.default ~= PROFILE_BALANCED and cfg.profiles.default ~= PROFILE_HANDSFREE then
        cfg.profiles.default = PROFILE_BALANCED
    end

    if type(cfg.prompt) ~= "table" then
        cfg.prompt = {}
    end
    if cfg.prompt.mode ~= PROMPT_NEVER and cfg.prompt.mode ~= PROMPT_SMART and cfg.prompt.mode ~= PROMPT_ALWAYS then
        cfg.prompt.mode = PROMPT_SMART
    end

    if type(cfg.start) ~= "table" then
        cfg.start = {}
    end
    if type(cfg.resume) ~= "table" then
        cfg.resume = {}
    end

    local defaultStart, defaultResume = BuildProfile(cfg.profiles.default)

    cfg.start.rules = EnsureRuleShape(cfg.start.rules or defaultStart, ACTION_OFF)
    cfg.resume.rules = EnsureRuleShape(cfg.resume.rules or defaultResume, ACTION_OFF)

    if type(cfg.resume.onlyIfAutoPaused) ~= "boolean" then
        cfg.resume.onlyIfAutoPaused = true
    end

    if type(cfg.pause) ~= "table" then
        cfg.pause = {}
    end
    if type(cfg.pause.afkEnabled) ~= "boolean" then
        cfg.pause.afkEnabled = oldAfkPause == nil and true or (oldAfkPause and true or false)
    end
    if type(cfg.pause.inactivityPromptMin) ~= "number" then
        cfg.pause.inactivityPromptMin = oldInactivityPromptMin or 5
    end
    if type(cfg.pause.inactivityPauseMin) ~= "number" then
        cfg.pause.inactivityPauseMin = oldInactivityPauseMin or 10
    end

    if type(cfg.instanceStart) ~= "table" then
        cfg.instanceStart = {}
    end
    if type(cfg.instanceStart.enabled) ~= "boolean" then
        cfg.instanceStart.enabled = oldInstanceStart == nil and true or (oldInstanceStart and true or false)
    end
    if cfg.instanceStart.mode ~= INSTANCE_START_PAUSED and cfg.instanceStart.mode ~= INSTANCE_START_ACTIVE then
        cfg.instanceStart.mode = INSTANCE_START_PAUSED
    end

    -- Preserve legacy intended behavior
    if oldAutoStart == false then
        for _, source in ipairs(ALL_SOURCES) do
            cfg.start.rules[source].action = ACTION_OFF
        end
    end
    if oldAutoResume == false then
        for _, source in ipairs(ALL_SOURCES) do
            cfg.resume.rules[source].action = ACTION_OFF
        end
    end

    -- One-time migration to updated source defaults (0.14.x):
    -- - Quest turn-in XP should prompt to start.
    -- - Ambiguous rep should be safe/off by default.
    if cfg._sourceRulesMigrationV1400 ~= true then
        local xpStart = cfg.start.rules["xp.quest_turnin"] and cfg.start.rules["xp.quest_turnin"].action
        local xpResume = cfg.resume.rules["xp.quest_turnin"] and cfg.resume.rules["xp.quest_turnin"].action
        if xpStart == ACTION_OFF and xpResume == ACTION_OFF then
            cfg.start.rules["xp.quest_turnin"].action = ACTION_PROMPT
        end

        local repOtherStart = cfg.start.rules["rep.other"] and cfg.start.rules["rep.other"].action
        local repOtherResume = cfg.resume.rules["rep.other"] and cfg.resume.rules["rep.other"].action
        if repOtherStart == ACTION_PROMPT and repOtherResume == ACTION_AUTO then
            cfg.start.rules["rep.other"].action = ACTION_OFF
            cfg.resume.rules["rep.other"].action = ACTION_OFF
        end

        cfg._sourceRulesMigrationV1400 = true
    end

end

local function SourceLabel(source)
    return SOURCE_LABELS[source] or source
end

local state = {
    lastActivityAt = nil,
    inactivityToastShown = false,
    wasPausedLastCheck = nil,
    timerFrame = nil,
    afkFrame = nil,

    mailboxOpen = false,
    merchantOpen = false,
    vendorSaleUntil = 0,

    questTurnInUntil = 0,
    zoneDiscoveryUntil = 0,
    pickpocketUntil = 0,
    lockboxUntil = 0,
    itemTurnInUntil = 0,

    xpLastSeen = nil,
    repCache = {},
    pendingXPSource = nil,
    pendingXPSourceUntil = 0,
    pendingRepSource = nil,
    pendingRepSourceUntil = 0,
    pendingRepHint = nil,
    repKillSignalUntil = 0,

    toastFrame = nil,
    promptFrame = nil,
    promptCooldownBySource = {},
    promptContext = nil,
}

local GATHERING_SPELLS = {
    [2575] = true,
    [2366] = true,
    [8613] = true,
    [7620] = true,
}

local EVENT_INTEREST = {
    CHAT_MSG_MONEY = true,
    CHAT_MSG_LOOT = true,
    CHAT_MSG_COMBAT_HONOR_GAIN = true,
    CHAT_MSG_COMBAT_XP_GAIN = true,
    CHAT_MSG_COMBAT_FACTION_CHANGE = true,
    CHAT_MSG_SYSTEM = true,
    PLAYER_XP_UPDATE = true,
    UPDATE_FACTION = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    QUEST_TURNED_IN = true,
}

local function ParseCopper(message)
    if type(message) ~= "string" then
        return 0
    end
    local totalCopper = 0
    local gold = message:match("(%d+) Gold")
    if gold then
        totalCopper = totalCopper + tonumber(gold) * 10000
    end
    local silver = message:match("(%d+) Silver")
    if silver then
        totalCopper = totalCopper + tonumber(silver) * 100
    end
    local copper = message:match("(%d+) Copper")
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end
    return totalCopper
end

local function ParseHonor(message)
    if type(message) ~= "string" then
        return 0
    end
    local amount = message:match("(%d+) honor") or message:match("awarded (%d+) honor")
    return tonumber(amount) or 0
end

local function NormalizeAction(value, allowPrompt)
    if value == ACTION_OFF then
        return ACTION_OFF
    end
    if value == ACTION_AUTO then
        return ACTION_AUTO
    end
    if allowPrompt and value == ACTION_PROMPT then
        return ACTION_PROMPT
    end
    return nil
end

local function GetCfg()
    return pH_Settings and pH_Settings.autoSession or nil
end

function pH_AutoSession:InitializeRepCache()
    state.repCache = {}
    local numFactions = GetNumFactions and GetNumFactions() or 0
    for i = 1, numFactions do
        local _, _, _, _, _, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
        if not isHeader and factionID and barValue ~= nil then
            state.repCache[factionID] = barValue
        end
    end
end

function pH_AutoSession:ResetRuntimeOnSessionBoundary()
    state.lastActivityAt = GetTime()
    state.inactivityToastShown = false
    state.wasPausedLastCheck = nil
    state.promptContext = nil
    if state.promptFrame then
        state.promptFrame:Hide()
    end
    self:HideToast()
end

function pH_AutoSession:Initialize()
    MigrateSettings()
    self:InitializeRepCache()

    state.timerFrame = CreateFrame("Frame")
    state.timerFrame:SetScript("OnUpdate", function(selfFrame, elapsed)
        selfFrame.timer = (selfFrame.timer or 0) + elapsed
        if selfFrame.timer >= 10 then
            pH_AutoSession:CheckInactivity()
            selfFrame.timer = 0
        end
    end)

    state.afkFrame = CreateFrame("Frame")
    state.afkFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
    state.afkFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_FLAGS_CHANGED" and unit == "player" then
            pH_AutoSession:OnPlayerFlagsChanged(unit)
        end
    end)
end

function pH_AutoSession:OnSessionStarted(_session, _reason)
    self:ResetRuntimeOnSessionBoundary()
end

function pH_AutoSession:OnSessionStopped(_session)
    state.lastActivityAt = nil
    state.inactivityToastShown = false
    state.wasPausedLastCheck = nil
    state.promptContext = nil
    if state.promptFrame then
        state.promptFrame:Hide()
    end
    self:HideToast()
end

function pH_AutoSession:OnSessionPaused(session, reason)
    if session then
        session.autoSessionPauseReason = reason or "manual"
    end
    self:HideToast()
    if state.promptFrame then
        state.promptFrame:Hide()
    end
end

function pH_AutoSession:OnSessionResumed(session, _reason)
    if session then
        session.autoSessionPauseReason = nil
    end
    state.lastActivityAt = GetTime()
    state.inactivityToastShown = false
    state.wasPausedLastCheck = false
    self:HideToast()
    if state.promptFrame then
        state.promptFrame:Hide()
    end
end

function pH_AutoSession:SetMailboxOpen(open)
    state.mailboxOpen = open and true or false
end

function pH_AutoSession:SetMerchantOpen(open)
    state.merchantOpen = open and true or false
    local now = GetTime()
    if open then
        state.vendorSaleUntil = now + 3.0
    else
        -- Keep a short tail window in case money events land just after close.
        state.vendorSaleUntil = now + 1.5
    end
end

function pH_AutoSession:MarkQuestTurnIn(hasXP, hasMoney)
    local now = GetTime()
    state.questTurnInUntil = now + QUEST_TURNIN_WINDOW_SEC
    if hasXP then
        state.pendingXPSource = "xp.quest_turnin"
        state.pendingXPSourceUntil = now + QUEST_TURNIN_WINDOW_SEC
    end
    if hasMoney then
        -- used by CHAT_MSG_MONEY classification shortly after turn-in
        state.questTurnInUntil = now + QUEST_TURNIN_WINDOW_SEC
    end
end

function pH_AutoSession:MarkItemTurnIn()
    state.itemTurnInUntil = GetTime() + 2.0
end

function pH_AutoSession:MarkPickpocketWindow(durationSec)
    state.pickpocketUntil = GetTime() + (durationSec or 2.0)
end

function pH_AutoSession:MarkLockboxWindow(durationSec)
    state.lockboxUntil = GetTime() + (durationSec or 3.0)
end

local function IsDefaultBlockedSource(source)
    return source == "gold.mail" or source == "gold.auction_payout" or source == "gold.trade_or_cod" or source == "gold.vendor_sale"
end

function pH_AutoSession:MarkXPContextFromMessage(message)
    if type(message) ~= "string" then
        return
    end
    local lower = message:lower()
    local now = GetTime()
    if lower:find("discovered") and lower:find("experience") then
        state.zoneDiscoveryUntil = now + 2.0
        state.pendingXPSource = "xp.zone_discovery"
        state.pendingXPSourceUntil = now + 2.0
        return
    end

    if lower:find("experience") then
        if now <= state.questTurnInUntil then
            state.pendingXPSource = "xp.quest_turnin"
            state.repKillSignalUntil = 0
        else
            state.pendingXPSource = "xp.mob_kill"
            state.repKillSignalUntil = now + REP_KILL_SIGNAL_SEC
        end
        state.pendingXPSourceUntil = now + 2.0
    end
end

function pH_AutoSession:MarkRepContextFromMessage(message)
    state.pendingRepHint = nil
    if type(message) == "string" then
        local lower = message:lower()
        if lower:find("mark of", 1, true) or lower:find("arakkoa feather", 1, true) then
            self:MarkItemTurnIn()
            state.pendingRepHint = "rep.item_turnin"
        end
    end
    local now = GetTime()
    if now <= state.questTurnInUntil then
        state.pendingRepSource = "rep.quest_turnin"
    elseif now <= state.itemTurnInUntil then
        state.pendingRepSource = "rep.item_turnin"
    else
        -- Ambiguous until UPDATE_FACTION resolves source precedence.
        state.pendingRepSource = nil
    end
    state.pendingRepSourceUntil = now + 2.0
end

function pH_AutoSession:ClassifyActivity(event, ...)
    local now = GetTime()

    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        self:MarkXPContextFromMessage(select(1, ...))
        return nil
    end

    if event == "CHAT_MSG_SYSTEM" then
        local message = select(1, ...)
        self:MarkXPContextFromMessage(message)
        if type(message) == "string" then
            local lower = message:lower()
            if lower:find("mail") then
                return { source = "gold.mail", confidence = "high", amount = 0, shouldSuppress = false }
            end
        end
        return nil
    end

    if event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        self:MarkRepContextFromMessage(select(1, ...))
        return nil
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitTarget, _, spellID = ...
        if unitTarget ~= "player" then
            return nil
        end
        if spellID and GATHERING_SPELLS[spellID] then
            return { source = "gathering.node", confidence = "high", amount = 1, shouldSuppress = false }
        end
        local spellName = spellID and GetSpellInfo and GetSpellInfo(spellID) or nil
        if spellName == "Pick Pocket" or spellName == "Pickpocket" then
            self:MarkPickpocketWindow(2.0)
        end
        return nil
    end

    if event == "CHAT_MSG_LOOT" then
        local message = select(1, ...)
        if type(message) ~= "string" then
            return nil
        end
        local itemLink = message:match("You receive loot: (|c%x+|H.+|h.+|h|r)")
        if not itemLink then
            return nil
        end
        local itemID = itemLink:match("|Hitem:(%d+):")
        if not itemID then
            return nil
        end
        itemID = tonumber(itemID)
        if not itemID then
            return nil
        end

        local itemName, quality, itemClass, itemSubClass
        if pH_Valuation and pH_Valuation.GetItemInfo then
            itemName, quality, itemClass, itemSubClass = pH_Valuation:GetItemInfo(itemID)
        end
        if not itemName and GetItemInfo then
            local itemNameInfo, _, qualityInfo, _, _, _, _, _, _, _, _, itemClassInfo, itemSubClassInfo = GetItemInfo(itemID)
            itemName = itemNameInfo
            quality = qualityInfo
            itemClass = itemClassInfo
            itemSubClass = itemSubClassInfo
        end
        if not itemName then
            return { source = "gold.other", confidence = "low", amount = 0, shouldSuppress = false }
        end
        if pH_Valuation and pH_Valuation.ClassifyItem then
            local bucket = pH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
            if bucket == "gathering" then
                return { source = "gathering.node", confidence = "high", amount = 1, shouldSuppress = false }
            end
            if bucket == "container_lockbox" then
                return { source = "gold.treasure_or_container_coin", confidence = "medium", amount = 0, shouldSuppress = false }
            end
        end
        return { source = "gold.other", confidence = "low", amount = 0, shouldSuppress = false }
    end

    if event == "CHAT_MSG_MONEY" then
        local message = select(1, ...)
        local amount = ParseCopper(message)
        local source = "gold.other"

        if state.mailboxOpen then
            source = "gold.mail"
        elseif state.merchantOpen or now <= state.vendorSaleUntil then
            source = "gold.vendor_sale"
        elseif now <= state.lockboxUntil then
            source = "gold.lockbox_coin"
        elseif now <= state.pickpocketUntil then
            source = "gold.pickpocket_coin"
        elseif now <= state.questTurnInUntil then
            source = "gold.quest_reward"
        else
            local lower = type(message) == "string" and message:lower() or ""
            if lower:find("auction") then
                source = "gold.auction_payout"
            elseif lower:find("mail") then
                source = "gold.mail"
            elseif lower:find("cod") or lower:find("trade") then
                source = "gold.trade_or_cod"
            elseif lower:find("you loot") then
                source = "gold.mob_loot_coin"
            end
        end

        return {
            source = source,
            confidence = (source == "gold.other" and "low" or "high"),
            amount = amount,
            shouldSuppress = false,
        }
    end

    if event == "PLAYER_XP_UPDATE" then
        local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
        if UnitLevel("player") >= maxLevel then
            return nil
        end

        local currentXP = UnitXP("player")
        if state.xpLastSeen == nil then
            state.xpLastSeen = currentXP
            return nil
        end

        local delta = currentXP - state.xpLastSeen
        state.xpLastSeen = currentXP
        if delta <= 0 then
            return nil
        end

        local source = "xp.other"
        if now <= state.pendingXPSourceUntil and state.pendingXPSource then
            source = state.pendingXPSource
        elseif now <= state.zoneDiscoveryUntil then
            source = "xp.zone_discovery"
        elseif now <= state.questTurnInUntil then
            source = "xp.quest_turnin"
        end

        return { source = source, confidence = "high", amount = delta, shouldSuppress = false }
    end

    if event == "UPDATE_FACTION" then
        local totalDelta = 0
        local numFactions = GetNumFactions and GetNumFactions() or 0
        for i = 1, numFactions do
            local _, _, _, _, _, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            if not isHeader and factionID and barValue ~= nil then
                local old = state.repCache[factionID] or barValue
                local delta = barValue - old
                if delta > 0 then
                    totalDelta = totalDelta + delta
                end
                state.repCache[factionID] = barValue
            end
        end

        if totalDelta <= 0 then
            return nil
        end

        local source = "rep.other"
        if now <= state.questTurnInUntil then
            source = "rep.quest_turnin"
        elseif now <= state.itemTurnInUntil then
            source = "rep.item_turnin"
        elseif now <= state.repKillSignalUntil then
            source = "rep.mob_kill"
        elseif now <= state.pendingRepSourceUntil and state.pendingRepSource then
            source = state.pendingRepSource
        end

        -- Consume hints to avoid stale/circular misclassification.
        state.pendingRepSource = nil
        state.pendingRepSourceUntil = 0
        state.pendingRepHint = nil
        if source == "rep.mob_kill" then
            state.repKillSignalUntil = 0
        end

        return { source = source, confidence = "medium", amount = totalDelta, shouldSuppress = false }
    end

    if event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local amount = ParseHonor(select(1, ...))
        if amount <= 0 then
            return nil
        end
        return { source = "honor.gain", confidence = "high", amount = amount, shouldSuppress = false }
    end

    if event == "QUEST_TURNED_IN" then
        local _, xpReward, moneyReward = ...
        self:MarkQuestTurnIn((xpReward or 0) > 0, (moneyReward or 0) > 0)
        return nil
    end

    return nil
end

local function MaybeShowHUD()
    if pH_HUD then
        pH_HUD:Update()
    end
end

function pH_AutoSession:GetSourceAction(kind, source)
    local cfg = GetCfg()
    if not cfg then
        return ACTION_OFF
    end
    local container = (kind == "start") and cfg.start or cfg.resume
    local rules = container and container.rules or nil
    local action = rules and rules[source] and rules[source].action or ACTION_OFF
    local allowPrompt = (kind == "start")
    return NormalizeAction(action, allowPrompt) or ACTION_OFF
end

function pH_AutoSession:ShouldPrompt(source, action, confidence)
    local cfg = GetCfg()
    if not cfg then
        return false
    end
    if IsDefaultBlockedSource(source) and action ~= ACTION_PROMPT then
        return false
    end
    local mode = cfg.prompt and cfg.prompt.mode or PROMPT_SMART
    if action == ACTION_PROMPT then
        if mode == PROMPT_NEVER then
            return false
        end
        return true
    end
    if mode == PROMPT_ALWAYS then
        return action ~= ACTION_OFF
    end
    if mode == PROMPT_SMART then
        return action == ACTION_PROMPT or confidence == "low"
    end
    return false
end

function pH_AutoSession:StartSessionFromSource(source)
    local ok, message = pH_SessionManager:StartSession("auto", source)
    if ok then
        state.lastActivityAt = GetTime()
        state.inactivityToastShown = false
        MaybeShowHUD()
        print("[pH] Auto-started session from " .. SourceLabel(source) .. ": " .. (message or ""))
    end
    return ok
end

function pH_AutoSession:ResumeSessionFromSource(source)
    local ok, message = pH_SessionManager:ResumeSession("auto", source)
    if ok then
        state.lastActivityAt = GetTime()
        state.inactivityToastShown = false
        MaybeShowHUD()
        print("[pH] Auto-resumed session from " .. SourceLabel(source) .. ": " .. (message or ""))
    end
    return ok
end

local function CreatePromptUI()
    if state.promptFrame then
        return state.promptFrame
    end

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(360, 120)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(1000)
    frame:SetMovable(false)
    frame:EnableMouse(true)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(pH_Colors.BG_PARCHMENT))

    frame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropBorderColor(unpack(pH_Colors.BORDER_BRONZE))

    frame.messageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.messageText:SetPoint("TOP", frame, "TOP", 0, -12)
    frame.messageText:SetPoint("LEFT", frame, "LEFT", 12, 0)
    frame.messageText:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    frame.messageText:SetJustifyH("CENTER")
    frame.messageText:SetWordWrap(true)

    frame.startBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.startBtn:SetSize(70, 22)
    frame.startBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)
    frame.startBtn:SetText("Start")

    frame.dismissBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.dismissBtn:SetSize(70, 22)
    frame.dismissBtn:SetPoint("LEFT", frame.startBtn, "RIGHT", 6, 0)
    frame.dismissBtn:SetText("Not now")

    frame.alwaysBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.alwaysBtn:SetSize(90, 22)
    frame.alwaysBtn:SetPoint("LEFT", frame.dismissBtn, "RIGHT", 6, 0)
    frame.alwaysBtn:SetText("Always")

    frame.neverBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.neverBtn:SetSize(90, 22)
    frame.neverBtn:SetPoint("LEFT", frame.alwaysBtn, "RIGHT", 6, 0)
    frame.neverBtn:SetText("Never")

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.autoDismissTimer = (self.autoDismissTimer or 0) + elapsed
        if self.autoDismissTimer >= 20 then
            self:Hide()
        end
    end)

    state.promptFrame = frame
    return frame
end

function pH_AutoSession:ShowStartPrompt(source, confidence)
    local now = GetTime()
    local nextAllowed = state.promptCooldownBySource[source] or 0
    if now < nextAllowed then
        return
    end

    state.promptCooldownBySource[source] = now + 20
    state.promptContext = { source = source, confidence = confidence }

    local frame = CreatePromptUI()
    local hudFrame = _G["pH_HUD_Frame"]
    if hudFrame and hudFrame:IsVisible() then
        frame:SetPoint("TOP", hudFrame, "BOTTOM", 0, -8)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end

    frame.messageText:SetText("Start session from " .. SourceLabel(source) .. "?")

    frame.startBtn:SetScript("OnClick", function()
        local ctx = state.promptContext
        if ctx and ctx.source then
            pH_AutoSession:StartSessionFromSource(ctx.source)
        end
        frame:Hide()
    end)

    frame.dismissBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.alwaysBtn:SetScript("OnClick", function()
        local cfg = GetCfg()
        local ctx = state.promptContext
        if cfg and ctx and ctx.source and cfg.start and cfg.start.rules and cfg.start.rules[ctx.source] then
            cfg.start.rules[ctx.source].action = ACTION_AUTO
            print("[pH] Auto-start enabled for " .. SourceLabel(ctx.source))
            pH_AutoSession:StartSessionFromSource(ctx.source)
        end
        frame:Hide()
    end)

    frame.neverBtn:SetScript("OnClick", function()
        local cfg = GetCfg()
        local ctx = state.promptContext
        if cfg and ctx and ctx.source and cfg.start and cfg.start.rules and cfg.start.rules[ctx.source] then
            cfg.start.rules[ctx.source].action = ACTION_OFF
            print("[pH] Auto-start disabled for " .. SourceLabel(ctx.source))
        end
        frame:Hide()
    end)

    frame.autoDismissTimer = 0
    frame:Show()
end

function pH_AutoSession:ProcessActivity(activity)
    if not activity or not activity.source then
        return
    end

    local cfg = GetCfg()
    if not cfg or not cfg.enabled then
        return
    end

    local session = pH_SessionManager:GetActiveSession()

    if not session then
        local action = self:GetSourceAction("start", activity.source)
        local shouldPrompt = self:ShouldPrompt(activity.source, action, activity.confidence)
        if shouldPrompt then
            self:ShowStartPrompt(activity.source, activity.confidence)
            return
        end
        if action == ACTION_AUTO then
            self:StartSessionFromSource(activity.source)
        end
        return
    end

    if session.pausedAt then
        if cfg.resume and cfg.resume.onlyIfAutoPaused and session.autoSessionPauseReason == "manual" then
            return
        end

        local action = self:GetSourceAction("resume", activity.source)
        if action == ACTION_AUTO then
            self:ResumeSessionFromSource(activity.source)
        end
        return
    end

    state.lastActivityAt = GetTime()
    state.inactivityToastShown = false
end

function pH_AutoSession:HandleEvent(event, ...)
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then
        return
    end

    if not EVENT_INTEREST[event] then
        return
    end

    if event == "QUEST_TURNED_IN" then
        local _, xpReward, moneyReward = ...
        self:MarkQuestTurnIn((xpReward or 0) > 0, (moneyReward or 0) > 0)
        if xpReward and xpReward > 0 then
            self:ProcessActivity({ source = "xp.quest_turnin", confidence = "high", amount = xpReward, shouldSuppress = false })
        end
        if moneyReward and moneyReward > 0 then
            self:ProcessActivity({ source = "gold.quest_reward", confidence = "high", amount = moneyReward, shouldSuppress = false })
        end
        return
    end

    local activity = self:ClassifyActivity(event, ...)
    self:ProcessActivity(activity)
end

function pH_AutoSession:OnPlayerEnteringWorld()
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then
        return
    end

    if not cfg.instanceStart or not cfg.instanceStart.enabled then
        return
    end

    local isInstance = IsInInstance()
    if not isInstance then
        return
    end

    if pH_SessionManager:GetActiveSession() then
        return
    end

    local ok = pH_SessionManager:StartSession("auto", "instance.entry")
    if not ok then
        return
    end

    if cfg.instanceStart.mode == INSTANCE_START_PAUSED then
        pH_SessionManager:PauseSession("instance")
        print("[pH] Session started in instance (paused). It will resume on configured activity.")
    else
        print("[pH] Session started in instance.")
    end

    MaybeShowHUD()
end

local function CreateToastUI()
    if state.toastFrame then
        return state.toastFrame
    end

    local toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    toast:SetSize(300, 100)
    toast:SetFrameStrata("DIALOG")
    toast:SetFrameLevel(1000)
    toast:SetMovable(false)
    toast:EnableMouse(true)
    toast:Hide()

    local bg = toast:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(pH_Colors.BG_PARCHMENT))

    toast:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    toast:SetBackdropBorderColor(unpack(pH_Colors.BORDER_BRONZE))

    local messageText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("TOP", toast, "TOP", 0, -12)
    messageText:SetPoint("LEFT", toast, "LEFT", 12, 0)
    messageText:SetPoint("RIGHT", toast, "RIGHT", -12, 0)
    messageText:SetPoint("BOTTOM", toast, "BOTTOM", 0, 44)
    messageText:SetJustifyH("CENTER")
    messageText:SetJustifyV("TOP")
    messageText:SetTextColor(unpack(pH_Colors.TEXT_PRIMARY))
    messageText:SetWordWrap(true)
    toast.messageText = messageText

    local actionBtn = CreateFrame("Button", nil, toast, "UIPanelButtonTemplate")
    actionBtn:SetSize(90, 24)
    actionBtn:SetPoint("BOTTOMLEFT", toast, "BOTTOM", 12, 10)
    actionBtn:SetText("Pause")
    actionBtn:SetScript("OnClick", function()
        toast.actionCallback()
        pH_AutoSession:HideToast()
    end)
    toast.actionBtn = actionBtn

    local dismissBtn = CreateFrame("Button", nil, toast, "UIPanelButtonTemplate")
    dismissBtn:SetSize(90, 24)
    dismissBtn:SetPoint("BOTTOMRIGHT", toast, "BOTTOM", -12, 10)
    dismissBtn:SetText("Dismiss")
    dismissBtn:SetScript("OnClick", function()
        pH_AutoSession:HideToast()
    end)
    toast.dismissBtn = dismissBtn

    toast.autoDismissTimer = 0
    toast:SetScript("OnUpdate", function(selfFrame, elapsed)
        selfFrame.autoDismissTimer = selfFrame.autoDismissTimer + elapsed
        if selfFrame.autoDismissTimer >= 30 then
            pH_AutoSession:HideToast()
        end
    end)

    state.toastFrame = toast
    return toast
end

function pH_AutoSession:ShowInactivityToast()
    local toast = CreateToastUI()
    local hudFrame = _G["pH_HUD_Frame"]
    if hudFrame and hudFrame:IsVisible() then
        toast:SetPoint("TOP", hudFrame, "BOTTOM", 0, -8)
    else
        toast:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end

    toast.messageText:SetText("No activity detected. Pause session?")
    toast.actionBtn:SetText("Pause")
    toast.actionCallback = function()
        local ok, message = pH_SessionManager:PauseSession("inactivity")
        if ok then
            state.inactivityToastShown = false
            MaybeShowHUD()
            print("[pH] Session paused: " .. (message or ""))
        end
    end

    toast.autoDismissTimer = 0
    toast:Show()
end

function pH_AutoSession:HideToast()
    if state.toastFrame then
        state.toastFrame:Hide()
    end
end

function pH_AutoSession:CheckInactivity()
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then
        return
    end

    local session = pH_SessionManager:GetActiveSession()
    if not session then
        state.wasPausedLastCheck = nil
        return
    end

    if session.pausedAt then
        state.wasPausedLastCheck = true
        return
    end

    if state.wasPausedLastCheck then
        state.lastActivityAt = GetTime()
        state.inactivityToastShown = false
        state.wasPausedLastCheck = false
        self:HideToast()
        return
    end
    state.wasPausedLastCheck = false

    if not state.lastActivityAt then
        state.lastActivityAt = GetTime()
        return
    end

    local idleSeconds = GetTime() - state.lastActivityAt
    local promptMin = cfg.pause and cfg.pause.inactivityPromptMin or 5
    local pauseMin = cfg.pause and cfg.pause.inactivityPauseMin or 10

    if idleSeconds >= (promptMin * 60) and not state.inactivityToastShown then
        self:ShowInactivityToast()
        state.inactivityToastShown = true
    end

    if idleSeconds >= (pauseMin * 60) then
        local ok, message = pH_SessionManager:PauseSession("inactivity")
        if ok then
            state.inactivityToastShown = false
            self:HideToast()
            MaybeShowHUD()
            print("[pH] Auto-paused session due to inactivity: " .. (message or ""))
        end
    end
end

function pH_AutoSession:OnPlayerFlagsChanged(unit)
    local cfg = GetCfg()
    if not cfg or not cfg.enabled then
        return
    end
    if unit ~= "player" then
        return
    end
    if not cfg.pause or not cfg.pause.afkEnabled then
        return
    end

    local session = pH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    local isAFK = UnitIsAFK("player")

    if isAFK and not session.pausedAt then
        local ok, message = pH_SessionManager:PauseSession("afk")
        if ok then
            state.inactivityToastShown = false
            self:HideToast()
            MaybeShowHUD()
            print("[pH] Auto-paused session (AFK): " .. (message or ""))
        end
        return
    end

    if not isAFK and session.pausedAt and session.autoSessionPauseReason == "afk" then
        local action = self:GetSourceAction("resume", "xp.mob_kill")
        if action == ACTION_AUTO then
            local ok, message = pH_SessionManager:ResumeSession("auto", "afk_clear")
            if ok then
                state.lastActivityAt = GetTime()
                state.inactivityToastShown = false
                MaybeShowHUD()
                print("[pH] Auto-resumed session (no longer AFK): " .. (message or ""))
            end
        end
    end
end

function pH_AutoSession:ApplyProfile(profile)
    local cfg = GetCfg()
    if not cfg then
        return false, "Auto-session settings unavailable"
    end
    if profile ~= PROFILE_MANUAL and profile ~= PROFILE_BALANCED and profile ~= PROFILE_HANDSFREE then
        return false, "Invalid profile"
    end

    local startRules, resumeRules = BuildProfile(profile)
    cfg.profiles.default = profile
    cfg.start.rules = startRules
    cfg.resume.rules = resumeRules
    cfg.resume.onlyIfAutoPaused = true

    -- Keep hard safety defaults
    cfg.start.rules["gold.vendor_sale"].action = ACTION_OFF
    cfg.resume.rules["gold.vendor_sale"].action = ACTION_OFF
    cfg.start.rules["gold.mail"].action = ACTION_OFF
    cfg.resume.rules["gold.mail"].action = ACTION_OFF
    cfg.start.rules["gold.auction_payout"].action = ACTION_OFF
    cfg.resume.rules["gold.auction_payout"].action = ACTION_OFF
    cfg.start.rules["gold.trade_or_cod"].action = ACTION_OFF
    cfg.resume.rules["gold.trade_or_cod"].action = ACTION_OFF

    return true
end

function pH_AutoSession:SetRule(kind, source, action)
    local cfg = GetCfg()
    if not cfg then
        return false, "Auto-session settings unavailable"
    end
    local validSource = SOURCE_LABELS[source] ~= nil
    if not validSource then
        return false, "Unknown source: " .. tostring(source)
    end
    if kind ~= "start" and kind ~= "resume" then
        return false, "Kind must be start or resume"
    end

    action = NormalizeAction(action, kind == "start")
    if not action then
        return false, "Invalid action"
    end

    local rules = (kind == "start") and cfg.start.rules or cfg.resume.rules
    if not rules[source] then
        rules[source] = { action = ACTION_OFF }
    end
    rules[source].action = action
    return true
end

function pH_AutoSession:SetPromptMode(mode)
    local cfg = GetCfg()
    if not cfg then
        return false, "Auto-session settings unavailable"
    end
    if mode ~= PROMPT_NEVER and mode ~= PROMPT_SMART and mode ~= PROMPT_ALWAYS then
        return false, "Invalid prompt mode"
    end
    cfg.prompt.mode = mode
    return true
end

function pH_AutoSession:GetStatusLines()
    local cfg = GetCfg()
    if not cfg then
        return { "Auto-session settings unavailable" }
    end

    local lines = {}
    table.insert(lines, string.format("  Enabled: %s", cfg.enabled and "Yes" or "No"))
    table.insert(lines, string.format("  Profile: %s", cfg.profiles.default))
    table.insert(lines, string.format("  Prompt mode: %s", cfg.prompt.mode))
    table.insert(lines, string.format("  Instance start: %s (%s)", cfg.instanceStart.enabled and "Yes" or "No", cfg.instanceStart.mode))
    table.insert(lines, string.format("  AFK pause: %s", cfg.pause.afkEnabled and "Yes" or "No"))
    table.insert(lines, string.format("  Inactivity prompt: %d min", cfg.pause.inactivityPromptMin or 5))
    table.insert(lines, string.format("  Inactivity pause: %d min", cfg.pause.inactivityPauseMin or 10))
    table.insert(lines, string.format("  Resume only if auto-paused: %s", cfg.resume.onlyIfAutoPaused and "Yes" or "No"))
    return lines
end

function pH_AutoSession:OpenSettingsPanel()
    -- Keep UI footprint minimal for classic compatibility: status + usage helper frame
    if not self.settingsFrame then
        local frame = CreateFrame("Frame", "pH_AutoSession_Settings", UIParent, "BackdropTemplate")
        frame:SetSize(420, 260)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(500)
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -12)
        title:SetText("pH Auto Session Settings")

        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

        local body = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        body:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
        body:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetText("Use /ph auto status, /ph auto profile <manual|balanced|handsfree>,\n/ph auto set <start|resume> <source> <off|prompt|auto>,\n/ph auto prompt <never|smart|always>.\n\nCommon sources:\n  xp.mob_kill, xp.quest_turnin, xp.zone_discovery\n  gold.mob_loot_coin, gold.vendor_sale, gold.mail\n  rep.mob_kill, rep.quest_turnin\n  gathering.node")

        local profileBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        profileBtn:SetSize(110, 24)
        profileBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
        profileBtn:SetText("Balanced")
        profileBtn:SetScript("OnClick", function()
            pH_AutoSession:ApplyProfile(PROFILE_BALANCED)
            print("[pH] Auto-session profile set to balanced")
        end)

        local manualBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        manualBtn:SetSize(110, 24)
        manualBtn:SetPoint("LEFT", profileBtn, "RIGHT", 8, 0)
        manualBtn:SetText("Manual")
        manualBtn:SetScript("OnClick", function()
            pH_AutoSession:ApplyProfile(PROFILE_MANUAL)
            print("[pH] Auto-session profile set to manual")
        end)

        local handsfreeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        handsfreeBtn:SetSize(110, 24)
        handsfreeBtn:SetPoint("LEFT", manualBtn, "RIGHT", 8, 0)
        handsfreeBtn:SetText("Handsfree")
        handsfreeBtn:SetScript("OnClick", function()
            pH_AutoSession:ApplyProfile(PROFILE_HANDSFREE)
            print("[pH] Auto-session profile set to handsfree")
        end)

        self.settingsFrame = frame
    end

    self.settingsFrame:Show()
end

function pH_AutoSession:PrintSources()
    print("[pH] Source keys:")
    for _, source in ipairs(ALL_SOURCES) do
        print("  " .. source .. " - " .. SourceLabel(source))
    end
end

_G.pH_AutoSession = pH_AutoSession
