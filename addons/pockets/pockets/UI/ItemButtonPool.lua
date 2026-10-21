--[[
    UI/ItemButtonPool.lua - Reusable pool of REAL item buttons (TDD §13.4,
    §21; UI_SPEC §8, §10, §14)

    Flyouts and the full inventory view must not create new frames on every
    open; they Acquire()/ReleaseAll() from a shared pool per parent frame.

    Configure() is the single place that wires a pooled button to a live
    bag+slot: left-click/drag/split/tooltip go through Adapters/BagAPI on
    PreClick, and right-click use/equip/disenchant-target is Blizzard's own
    ContainerFrameItemButtonTemplate OnClick - never wrapped or replaced,
    only ever HookScript'd non-destructively if ever needed. That template
    resolves bag/slot itself, live at click time, via
    self:GetParent():GetID() (bagID) and self:GetID() (slotID) - the same
    mechanism Blizzard's own bag UI and every bag-replacement addon
    (confirmed against Baganator's real source) relies on, including native
    combat-safety and disenchant/enchant spell-targeting, with no custom
    secure-attribute bookkeeping required on our end. Pockets' pools are
    item-major (one grid mixes items from many bags), unlike a bag-major
    index frame, so each pooled button gets its own tiny bagIndexFrame
    wrapper carrying the bagID via SetID - see Acquire/Configure below.
    Shared by every body Shell renders (Category grid, All Items flow) so
    both stay in sync (UI_SPEC §10 "share item rendering/pooling code").
]]

local _, Pockets = ...

Pockets.UI.ItemButtonPool = Pockets.UI.ItemButtonPool or {}
local ItemButtonPool = Pockets.UI.ItemButtonPool

local BagAPI = Pockets.Adapters.BagAPI
local CombatAPI = Pockets.Adapters.CombatAPI

-- Alpha for a button whose secure target is stale/unavailable (visible,
-- but visibly not trustworthy) until it is repaired.
local STALE_ALPHA = 0.4
local SIZE = Pockets.Constants.LAYOUT.ITEM_BUTTON_SIZE

-- pools[parentFrame] = { free = {}, active = {} }
ItemButtonPool.pools = ItemButtonPool.pools or {}

-- Converts one InventoryState:AggregateRecords() aggregate ({ itemID,
-- itemLink, texture, quality, totalQuantity, stacks = {...} }) into the
-- flat record shape Configure() expects below (quantity, not
-- totalQuantity), bound to a representative physical stack. Prefers the
-- SMALLEST unlocked stack (Glance UI §7 - less disruptive to manipulate,
-- matches InventoryState:ResolveSmallestStack's resolver used again at
-- interaction time), falling back to any locked stack only if nothing is
-- unlocked. Shared by Shell's Category/All rendering so every item grid
-- collapses identical itemIDs into one button the same way.
function ItemButtonPool.ToButtonRecord(agg)
    local representative
    for _, stack in ipairs(agg.stacks) do
        if not stack.isLocked and (not representative or (stack.quantity or 0) < (representative.quantity or 0)) then
            representative = stack
        end
    end
    representative = representative or agg.stacks[1]

    return {
        itemID = agg.itemID,
        itemLink = agg.itemLink,
        name = agg.name,
        texture = agg.texture,
        quality = agg.quality,
        quantity = agg.totalQuantity,
        isLocked = representative and representative.isLocked,
        bagID = representative and representative.bagID,
        slotID = representative and representative.slotID,
        interactive = representative ~= nil,
    }
end

-- Re-resolves a button's physical stack at the moment of interaction
-- rather than trusting whatever bagID/slotID it was Configure()'d with
-- (Glance UI §7 "resolve the physical stack when the interaction occurs" /
-- "reject stale location"). If the bound stack is still valid, use it
-- unchanged (stable target for repeated clicks); otherwise fall back to
-- InventoryState's smallest-current-stack resolver. Returns
-- bagID, slotID, quantity (quantity of that specific physical stack, not
-- the aggregate total - needed for split-stack's max amount).
local function ResolveInteractionStack(button)
    local InventoryState = Pockets.Services.InventoryState
    if InventoryState:IsValidStack(button.bagID, button.slotID, button.itemID) then
        local record = InventoryState:GetItem(button.bagID .. ":" .. button.slotID)
        return button.bagID, button.slotID, record and record.quantity
    end
    local resolved = InventoryState:ResolveSmallestStack(button.itemID)
    if resolved then
        return resolved.bagID, resolved.slotID, resolved.quantity
    end
    return nil, nil, nil
end

-- Pickup/split-stack/modified-click path (wired on PreClick). Right-click
-- use is not handled here - it's Blizzard's own inherited OnClick (see
-- CreateItemButton), resolved from the button's own bagIndexFrame/self ID.
function ItemButtonPool.HandleInsecureClick(self, mouseButton)
    if not self.interactive then
        return
    end
    -- With a chat edit box open, the split modifier (shift) means "link
    -- this item", exactly like Blizzard's bags - so only split when chat
    -- is not the click's target.
    if IsModifiedClick and IsModifiedClick("SPLITSTACK") and BagAPI:CanSplit()
        and not BagAPI:IsChatEditActive() then
        local bagID, slotID, quantity = ResolveInteractionStack(self)
        if bagID and quantity and quantity > 1 then
            -- Remember exactly which physical stack the split UI was
            -- opened for (its quantity is the max), re-validated again
            -- when the amount is confirmed (M2 §22-§23).
            self.splitTarget = { bagID = bagID, slotID = slotID, itemID = self.itemID }
            BagAPI:OpenSplitFrame(quantity, self, "BOTTOMLEFT", "TOPLEFT")
        end
        return
    end
    if IsModifiedClick and IsModifiedClick() then
        -- Chat-link/delete-confirm/etc - Blizzard's own handler,
        -- never intercepted by Pockets navigation (Glance UI §6).
        BagAPI:HandleModifiedItemClick(self.itemLink)
        return
    end
    if mouseButton == "RightButton" then
        return
    end
    local bagID, slotID = ResolveInteractionStack(self)
    if bagID then
        BagAPI:PickupItem(bagID, slotID)
    end
end

-- Scripts are wired once at create time. OnClick is deliberately never
-- SetScript'd/replaced - it stays ContainerFrameItemButtonTemplate's own
-- Blizzard handler, which performs left-click pickup, right-click use/
-- equip, disenchant/enchant spell-targeting, and split-stack natively
-- (resolved from self:GetParent():GetID()/self:GetID() - see
-- CreateItemButton/Configure). PreClick only adds Pockets' own modified-
-- click (chat-link) and split-stack-frame handling on top.
local function WireItemButtonScripts(button)
    if button.pocketsScriptsWired then
        return
    end
    button.pocketsScriptsWired = true

    button:SetScript("PreClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local modified = IsModifiedClick and IsModifiedClick()
            if self.interactive and not modified then
                return
            end
        end
        ItemButtonPool.HandleInsecureClick(self, mouseButton)
    end)

    button.SplitStack = function(self, amount)
        local InventoryState = Pockets.Services.InventoryState
        local target = self.splitTarget
        self.splitTarget = nil
        local bagID, slotID, quantity
        if target and InventoryState:IsValidStack(target.bagID, target.slotID, target.itemID) then
            bagID, slotID = target.bagID, target.slotID
            local record = InventoryState:GetItem(bagID .. ":" .. slotID)
            quantity = record and record.quantity
        else
            bagID, slotID, quantity = ResolveInteractionStack(self)
        end
        -- The chosen amount must fit the physical stack actually being
        -- split; otherwise no-op rather than split something else.
        if bagID and quantity and amount and amount > 0 and amount < quantity then
            BagAPI:SplitStack(bagID, slotID, amount)
        end
    end

    button:SetScript("OnDragStart", function(self)
        if not self.interactive then
            return
        end
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:PickupItem(bagID, slotID)
        end
    end)

    button:SetScript("OnReceiveDrag", function(self)
        if not self.interactive then
            return
        end
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:PickupItem(bagID, slotID)
        end
    end)

    -- Every non-Recent item surface (Category Grid/List, All Items,
    -- Search) anchors its tooltip to the Pockets HUD's own top-right
    -- corner, not per-button - a consistent, predictable spot regardless
    -- of which row/icon in the list/grid/full-bag-view is hovered.
    -- Recent-strip buttons (button.isRecentItem, set by
    -- UI/RecentItemStrip.lua) are excluded: they already get their own,
    -- more specific anchor (top-right of the large hover preview, when
    -- that opt-in toggle is on) - see ItemPreview:Show. ANCHOR_NONE is
    -- used instead of an anchor type so the tooltip only ever moves via
    -- the explicit SetPoint below, with no initial per-button position
    -- to visibly jump away from.
    button:SetScript("OnEnter", function(self)
        if self.isRecentItem then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        else
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
        end
        if self.interactive then
            BagAPI:SetTooltipToBagItem(GameTooltip, self.bagID, self.slotID)
        elseif self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
        else
            GameTooltip:Hide()
            return
        end
        if not self.isRecentItem then
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", Pockets.UI.Shell:GetActiveFrame(), "TOPRIGHT", 4, 0)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- ContainerFrameItemButtonTemplate resolves bag/slot via
-- self:GetParent():GetID() (bagID) / self:GetID() (slotID), same as
-- Blizzard's real bag frames and every bag-replacement addon that
-- inherits it (confirmed against Baganator's live source). Pockets'
-- pools are item-major (one grid mixes items from many bags), unlike a
-- bag-major index frame, so each button gets its OWN tiny bagIndexFrame
-- wrapper carrying the bagID - see Configure, which sets both IDs fresh
-- every render.
-- Buttons are NAMED. Modern templates (WoW Forever) declare their regions
-- as "$parentCount" / "$parentIconTexture" etc. and Blizzard's helpers
-- (SetItemButtonCount, ...) fall back to _G[button:GetName() .. "Count"];
-- an anonymous button makes that concatenate nil (Forever M1 bug), and its
-- $parent children all collapse onto the ancestor's name. Classic exposes
-- the same regions as button.Count/.icon keys, so both are aliased below.
local buttonSerial = 0
local REGION_SUFFIXES = {
    icon = "IconTexture",
    Count = "Count",
    IconBorder = "IconBorder",
    Stock = "Stock",
    NormalTexture = "NormalTexture",
}

local function CreateItemButton(parent)
    local bagIndexFrame = CreateFrame("Frame", nil, parent)

    buttonSerial = buttonSerial + 1
    local name = "PocketsItemButton" .. buttonSerial
    -- SecureActionButtonTemplate goes LAST so its secure OnClick replaces
    -- the Container template's insecure one (right-click use is then
    -- driven purely by the type2/item2 attributes set in BindSecure).
    local template = "ContainerFrameItemButtonTemplate,BackdropTemplate"
    if BagAPI:UsesSecureItemAttributes() then
        template = template .. ",SecureActionButtonTemplate"
    end
    local button = CreateFrame("Button", name, bagIndexFrame, template)
    button.usesSecureAttributes = BagAPI:UsesSecureItemAttributes()
    if button.usesSecureAttributes and button.SetAttribute then
        -- Secure buttons fire on key-DOWN by default on modern clients
        -- (ActionButtonUseKeyDown); Pockets registers AnyUp clicks, so
        -- without this the secure item action never triggers.
        button:SetAttribute("useOnKeyDown", false)
    end
    for key, suffix in pairs(REGION_SUFFIXES) do
        if button[key] == nil then
            button[key] = _G[name .. suffix]
        end
    end
    -- Some modern templates expose neither key nor named global for these
    -- regions. Create the two Pockets cannot render without, so Blizzard's
    -- SetItemButtonCount/icon helpers always have something to write to.
    if button.icon == nil then
        button.icon = button:CreateTexture(name .. "IconTexture", "BORDER")
        button.icon:SetAllPoints(button)
    end
    if button.Count == nil then
        button.Count = button:CreateFontString(name .. "Count", "OVERLAY", "NumberFontNormal")
        button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
        button.Count:Hide()
    end
    button.bagIndexFrame = bagIndexFrame
    if ItemButtonPool.templateProtected == nil then
        ItemButtonPool.templateProtected = button.IsProtected and button:IsProtected() and true or false
    end
    button:SetSize(SIZE, SIZE)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    WireItemButtonScripts(button)
    button:Hide()
    return button
end

function ItemButtonPool:GetPool(parent)
    self.pools[parent] = self.pools[parent] or { free = {}, active = {} }
    return self.pools[parent]
end

-- Returns a hidden button. Caller must call Configure() then Show() it.
-- Returns nil when the pool cannot hand out a button safely (combat
-- lockdown with a protected button template) - callers must stop placing.
function ItemButtonPool:Acquire(parent)
    if self:IsStructurallyBlocked() then
        self.dirty = true
        return nil
    end
    local pool = self:GetPool(parent)
    local button = table.remove(pool.free)
    if not button then
        button = CreateItemButton(parent)
    end
    table.insert(pool.active, button)
    return button
end

-- Hides and recycles every button currently active for `parent`.
function ItemButtonPool:ReleaseAll(parent)
    local pool = self:GetPool(parent)
    for _, button in ipairs(pool.active) do
        if CombatAPI:CanMutateProtected(button) then
            button:Hide()
            button:ClearAllPoints()
            -- A recycled button must never carry the previous item's
            -- secure target into its next life (M2 §15).
            self:UnbindSecure(button)
            table.insert(pool.free, button)
        else
            -- Protected in combat: leave the frame untouched, logically
            -- remove it from active use, finish after PLAYER_REGEN_ENABLED
            -- (M2 §16). Its target is flagged stale meanwhile.
            button.secureBindingValid = false
            button:SetAlpha(STALE_ALPHA)
            pool.pendingRelease = pool.pendingRelease or {}
            table.insert(pool.pendingRelease, button)
            self.dirty = true
        end
    end
    pool.active = {}
end

-- record: a normalized item record (TDD §6) plus:
--   interactive - false for a Recent entry no longer carried (UI_SPEC §9);
--                 defaults to true when bagID/slotID are present.
-- Binds the button to record.itemID (used to re-resolve a fresh physical
-- stack at interaction time via ResolveInteractionStack above) rather than
-- trusting record.bagID/slotID forever - callers re-Configure on every
-- render, but interactions between renders must never act on a stale
-- location (UI_SPEC §8 "Stale-location safety"). Right-click use/equip/
-- disenchant-target resolves bag/slot itself, live at click time, via
-- ContainerFrameItemButtonTemplate's own OnClick reading
-- bagIndexFrame:GetID()/button:GetID() - so binding those here just keeps
-- them in sync with this render's physical location, the same as every
-- other field on the button.
local function SetCount(button, quantity)
    local helperOk = SetItemButtonCount ~= nil and pcall(SetItemButtonCount, button, quantity)
    if not helperOk and button.Count then
        button.Count:SetText(quantity > 1 and tostring(quantity) or "")
        if quantity > 1 then button.Count:Show() else button.Count:Hide() end
    end
    -- Surfaces that don't want stack numbers (Glance's Recent strip).
    if button.hideCount and button.Count then
        button.Count:Hide()
    end
end

function ItemButtonPool:Configure(button, record)
    local interactive = record.interactive ~= false and record.bagID ~= nil and record.slotID ~= nil

    if button.icon then
        button.icon:SetTexture(record.texture)
    end
    -- SetItemButtonCount (not a raw button.Count:SetText()) is what
    -- actually shows/hides the count fontstring - it starts hidden, and
    -- a bare :SetText() alone never makes it visible again.
    SetCount(button, record.quantity or 0)
    if SetItemButtonDesaturated then
        SetItemButtonDesaturated(button, record.isLocked and true or false)
    end
    if button.IconBorder then
        local color = record.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[record.quality]
        if color and record.quality > 1 then
            button.IconBorder:SetVertexColor(color.r, color.g, color.b)
            button.IconBorder:Show()
        else
            button.IconBorder:Hide()
        end
    end
    -- ContainerFrameItemButtonTemplate (unlike the old bare
    -- ItemButtonTemplate Pockets used before) ships several Blizzard
    -- attention/decoration overlays Pockets never asked for and never
    -- managed - identified via /pockets debug regions against a real
    -- button rather than guessed at: "flash" (a 90x90 glow, oversized at
    -- every Pockets button size) and "BattlepayItemTexture" (a shop-item
    -- ribbon) were both found rendering unconditionally regardless of
    -- item type. Explicitly hidden every render alongside NewItemTexture
    -- rather than left at whatever the inherited template defaults to.
    if button.NewItemTexture then
        button.NewItemTexture:Hide()
    end
    if button.flash then
        button.flash:Hide()
    end
    if button.BattlepayItemTexture then
        button.BattlepayItemTexture:Hide()
    end

    button.bagID = record.bagID
    button.slotID = record.slotID
    button.itemID = record.itemID
    button.itemLink = record.itemLink
    button.quantity = record.quantity
    button.interactive = interactive

    self:ConfigureSecure(button, record, interactive)
end

--------------------------------------------------
-- Secure state (M2 §9-§17). Blizzard's ContainerFrameItemButtonTemplate
-- OnClick (right-click use/equip/etc.) resolves its bag/slot from
-- bagIndexFrame:GetID()/button:GetID() live at click time. Those two IDs
-- ARE the secure target, tracked here as secureBagID/secureSlotID/
-- secureItemID and validated against InventoryState. Visual state
-- (Configure above) is independent of this and always updates.
--------------------------------------------------

-- Learns whether the template's buttons are protected (combat-locked)
-- on this client, once, from a throwaway button, so the answer is known
-- before the first combat. Call out of combat (Shell:Initialize).
function ItemButtonPool:Probe(parent)
    if self.templateProtected == nil then
        local probe = CreateItemButton(parent)
        probe:Hide()
        self.probeButton = probe
    end
    return self.templateProtected
end

-- True when item buttons cannot be acquired/shown/hidden/anchored right
-- now: combat lockdown AND a protected template.
function ItemButtonPool:IsStructurallyBlocked()
    return CombatAPI:IsInCombat() and self.templateProtected == true
end

-- Secure right-click target. Modified right-clicks are explicitly
-- neutralised so shift/ctrl/alt-right-click never also "use" the item
-- (Pockets' own PreClick handles those). Only called when mutation is
-- allowed (out of combat, or the button isn't protected).
local MODIFIER_PREFIXES = { "shift-", "ctrl-", "alt-" }
local function SetSecureAttributes(button, bagID, slotID)
    if not (button.usesSecureAttributes and button.SetAttribute) then
        return
    end
    if bagID then
        button:SetAttribute("type2", "item")
        button:SetAttribute("item2", bagID .. " " .. slotID)
        for _, prefix in ipairs(MODIFIER_PREFIXES) do
            button:SetAttribute(prefix .. "type2", "none")
        end
    else
        button:SetAttribute("type2", nil)
        button:SetAttribute("item2", nil)
        for _, prefix in ipairs(MODIFIER_PREFIXES) do
            button:SetAttribute(prefix .. "type2", nil)
        end
    end
end

local function BindSecure(button, bagID, slotID, itemID)
    button.secureBagID, button.secureSlotID, button.secureItemID = bagID, slotID, itemID
    SetSecureAttributes(button, bagID, slotID)
    button.bagIndexFrame:SetID(bagID)
    button:SetID(slotID)
    button.bagID, button.slotID = bagID, slotID
    button.interactive = true
    button.secureBindingValid = true
    button.pendingSecure = nil
    button:SetAlpha(1)
end

-- Out-of-combat only (callers check). Zeroes the IDs so a recycled/
-- unavailable button can never resolve to a previous item's slot.
function ItemButtonPool:UnbindSecure(button)
    button.secureBagID, button.secureSlotID, button.secureItemID = nil, nil, nil
    SetSecureAttributes(button, nil, nil)
    button.bagIndexFrame:SetID(0)
    button:SetID(0)
    button.secureBindingValid = false
    button.pendingSecure = nil
end

-- True if the secure target still holds the button's item, unlocked.
function ItemButtonPool:IsSecureTargetValid(button)
    if button.secureItemID == nil or button.secureItemID ~= button.itemID then
        return false
    end
    return Pockets.Services.InventoryState:IsValidStack(
        button.secureBagID, button.secureSlotID, button.secureItemID)
end

function ItemButtonPool:ConfigureSecure(button, record, interactive)
    if CombatAPI:CanMutateProtected(button) then
        if interactive then
            BindSecure(button, record.bagID, record.slotID, record.itemID)
        else
            self:UnbindSecure(button)
            button:SetAlpha(1)
        end
        return
    end
    -- Combat + protected: do not touch the IDs. Queue the intended
    -- target (re-resolved from fresh state at Reconcile) and treat the
    -- current one as unavailable unless it still matches.
    button.pendingSecure = interactive and { bagID = record.bagID, slotID = record.slotID, itemID = record.itemID } or { clear = true }
    button.secureBindingValid = interactive and self:IsSecureTargetValid(button) or false
    button:SetAlpha(button.secureBindingValid and 1 or STALE_ALPHA)
    if not button.secureBindingValid then
        self.dirty = true
    end
end

-- Re-checks one button's secure target against InventoryState; repairs it
-- out of combat, otherwise marks it stale and queues the repair.
function ItemButtonPool:ValidateButton(button)
    if button.itemID == nil then
        return
    end
    if self:IsSecureTargetValid(button) then
        button.secureBindingValid = true
        button.pendingSecure = nil
        button:SetAlpha(1)
        return
    end
    local target = Pockets.Services.InventoryState:ResolveSmallestStack(button.itemID)
    if CombatAPI:CanMutateProtected(button) then
        if target then
            BindSecure(button, target.bagID, target.slotID, button.itemID)
        else
            button.interactive = false
            self:UnbindSecure(button)
            button:SetAlpha(STALE_ALPHA)
        end
        return
    end
    button.secureBindingValid = false
    button.pendingSecure = target and { bagID = target.bagID, slotID = target.slotID, itemID = button.itemID } or { clear = true }
    button:SetAlpha(STALE_ALPHA)
    self.dirty = true
end

-- Validates every active button (call on inventory changes).
function ItemButtonPool:ValidateAll()
    for _, pool in pairs(self.pools) do
        for _, button in ipairs(pool.active) do
            self:ValidateButton(button)
        end
    end
end

-- Read-only visual refresh for buttons that cannot be re-rendered in
-- combat: counts follow InventoryState (count fontstring only - no
-- protected mutation).
function ItemButtonPool:RefreshCounts()
    local InventoryState = Pockets.Services.InventoryState
    for _, pool in pairs(self.pools) do
        for _, button in ipairs(pool.active) do
            if button.itemID then
                local quantity = InventoryState:GetCarriedQuantity(button.itemID)
                button.quantity = quantity
                SetCount(button, quantity)
            end
        end
    end
end

-- After PLAYER_REGEN_ENABLED: finish deferred releases, then repair every
-- active button from current state (never from the queued targets, which
-- may describe items that no longer exist). Returns true if anything was
-- deferred, so the caller knows a re-render is due.
function ItemButtonPool:Reconcile()
    local hadDeferred = self.dirty == true
    for _, pool in pairs(self.pools) do
        for _, button in ipairs(pool.pendingRelease or {}) do
            button:Hide()
            button:ClearAllPoints()
            self:UnbindSecure(button)
            button:SetAlpha(1)
            table.insert(pool.free, button)
        end
        pool.pendingRelease = {}
        for _, button in ipairs(pool.active) do
            button.pendingSecure = nil
            self:ValidateButton(button)
        end
    end
    self.dirty = false
    return hadDeferred
end
