local _, ns = ...
local C = ns.Compat

-- Green pulsing borders and +% badges on Blizzard bag slots that hold an upgrade (from GearBot).
-- Cosmetic only: never equips anything or touches the bag buttons' clicks.
local Bags = { dirty = true, upgrades = {}, overlays = setmetatable({}, {__mode = "k"}) }
ns.Bags = Bags
-- The badge font: the suite's face (WallyHUD) in its bold weight, else the game's.
local function BadgeFont()
    return WallyHUD and WallyHUD.SuiteFace and WallyHUD.SuiteFace("bold") or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function IsCombat() return InCombatLockdown and InCombatLockdown() end
function Bags:Invalidate() self.dirty = true end

local function Coordinates(button, parent)
    if not button or not button.GetID or not button.IsShown or not button:IsShown() then return end
    local bag, slot
    if button.GetItemLocation then
        local ok, location = pcall(button.GetItemLocation, button)
        if ok and location and location.GetBagAndSlot then
            local valid, b, s = pcall(location.GetBagAndSlot, location)
            if valid then bag, slot = b, s end
        end
    end
    local function ReadID(widget, method)
        if not widget or not widget[method] then return end
        local ok, value = pcall(widget[method], widget)
        if ok and type(value) == "number" then return value end
    end
    if type(bag) ~= "number" then
        bag = ReadID(button, "GetBagID") or ReadID(parent, "GetBagID") or ReadID(parent, "GetID")
    end
    if type(slot) ~= "number" or slot < 1 then
        slot = ReadID(button, "GetSlotID") or ReadID(button, "GetID")
    end
    if type(bag) ~= "number" or bag < 0 or bag > (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) then return end
    if type(slot) ~= "number" or slot < 1 then return end
    return bag, slot
end

local function CreateOverlay(button)
    if IsCombat() then return end
    local f = CreateFrame("Frame", nil, button)
    f:SetAllPoints(button); f:SetFrameLevel(button:GetFrameLevel() + 8); f:EnableMouse(false)
    f.glow = CreateFrame("Frame", nil, f)
    f.glow:SetPoint("TOPLEFT", -2, 2); f.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    f.glow:EnableMouse(false)
    f.edges = {}
    for i = 1, 4 do
        local t = f.glow:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.23, 1, 0.52, 1)
        if i == 1 then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(3)
        elseif i == 2 then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(3)
        elseif i == 3 then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(3)
        else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(3) end
        f.edges[i] = t
    end
    -- Run in Blizzard's animation engine. Repeated bag refreshes must never
    -- restart the cycle. Animate the glow separately so the badge stays readable.
    f.pulse = f.glow:CreateAnimationGroup()
    local rise = f.pulse:CreateAnimation("Alpha")
    rise:SetOrder(1); rise:SetDuration(0.55); rise:SetFromAlpha(0.08); rise:SetToAlpha(1)
    local fall = f.pulse:CreateAnimation("Alpha")
    fall:SetOrder(2); fall:SetDuration(0.55); fall:SetFromAlpha(1); fall:SetToAlpha(0.08)
    f.pulse:SetLooping("REPEAT")
    function f:SyncPulse()
        if ns.db and (ns.db.bagPulse or self.test) then
            if not self.pulse:IsPlaying() then self.pulse:Play() end
        else
            self.pulse:Stop(); self.glow:SetAlpha(1)
        end
    end
    f.badge = CreateFrame("Frame", nil, f)
    f.badge:SetPoint("BOTTOMLEFT", 1, 1); f.badge:SetPoint("BOTTOMRIGHT", -1, 1); f.badge:SetHeight(13)
    local bg = f.badge:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.02, 0.10, 0.055, 0.94)
    f.text = f.badge:CreateFontString(nil, "OVERLAY", "TapeMeasureGameFontHighlightSmall")
    f.text:SetFont(BadgeFont(), 9, "OUTLINE")
    f.text:SetPoint("CENTER"); f.text:SetTextColor(0.5, 1, 0.67)
    f:SetScript("OnShow", function(self) self:SyncPulse() end)
    f:SetScript("OnHide", function(self) self.pulse:Stop(); self.glow:SetAlpha(1) end)
    f:Hide()
    return f
end

function Bags:Rebuild()
    self.upgrades = {}
    for _, info in ipairs(ns.Scoring:ScanBags()) do
        self.upgrades[info.bag .. ":" .. info.slot] = info
    end
    self.dirty = false
end
function Bags:UpdateButton(button, parent, touched)
    local bag, slot = Coordinates(button, parent)
    local overlay = self.overlays[button]
    if overlay then touched[overlay] = true end
    if not bag then if overlay then overlay:Hide() end return end
    local info = self.upgrades[bag .. ":" .. slot]
    local testing = self.previewUntil and GetTime() < self.previewUntil
    if testing then
        local link = C.GetSlotLink(bag, slot)
        if link then info = {link = link, test = true} end
    end
    -- A reused or moved slot must not retain the previous item's badge while an
    -- event is queued; exact link verification clears it immediately.
    if info and C.GetSlotLink(bag, slot) ~= info.link then info = nil; self.dirty = true end
    if not info then if overlay then overlay:Hide() end return end
    if not overlay then
        overlay = CreateOverlay(button)
        if not overlay then return end
        self.overlays[button] = overlay; touched[overlay] = true
    end
    overlay.test = info.test and true or false
    overlay.text:SetText(overlay.test and "TEST" or ns.Scoring:FormatChange(info.cmp, true))
    overlay.text:SetFont(BadgeFont(), 9, "OUTLINE")
    if overlay.text.GetStringWidth and button.GetWidth and overlay.text:GetStringWidth() > button:GetWidth() - 3 then
        overlay.text:SetFont(BadgeFont(), 7, "OUTLINE")
    end
    overlay.badge:SetShown(ns.db.bagPercent or overlay.test)
    overlay:Show()
    overlay:SyncPulse()
end
function Bags:Refresh()
    if not ns.db then return end
    local testing = self.previewUntil and GetTime() < self.previewUntil
    if (not ns.db.enabled or not ns.db.bagGlow) and not testing then
        for _, overlay in pairs(self.overlays) do overlay:Hide() end
        return
    end
    if self.dirty then self:Rebuild() end
    local touched, seen = {}, {}
    local function IsButton(value)
        local kind = type(value)
        return (kind == "table" or kind == "userdata") and value.GetID and value.IsShown
    end
    local function Visit(container, depth)
        if not container or not container.IsShown or not container:IsShown() then return end
        if type(container.Items) == "table" then
            for _, button in pairs(container.Items) do
                if IsButton(button) and not seen[button] then
                    seen[button] = true; self:UpdateButton(button, container, touched)
                end
            end
        end
        if container.EnumerateValidItems then
            -- Accept both ipairs(Items) and pool iterators whose button is the key.
            local ok, iterator, state, key = pcall(container.EnumerateValidItems, container)
            if ok and type(iterator) == "function" then
                for a, b in iterator, state, key do
                    local button = IsButton(b) and b or (IsButton(a) and a)
                    if button and not seen[button] then seen[button] = true; self:UpdateButton(button, container, touched) end
                end
            end
        end
        for _, key in ipairs({"itemButtonPool", "ItemButtonPool"}) do
            local pool = container[key]
            if pool and pool.EnumerateActive then
                for button in pool:EnumerateActive() do
                    if IsButton(button) and not seen[button] then seen[button] = true; self:UpdateButton(button, container, touched) end
                end
            end
        end
        -- Support nested stock content frames and location-based item buttons.
        if container.GetChildren then
            for _, child in ipairs({container:GetChildren()}) do
                if (child.GetBagID or child.GetItemLocation) and child.GetID and not seen[child] then
                    seen[child] = true; self:UpdateButton(child, container, touched)
                elseif (depth or 0) < 2 and child.GetChildren and not seen[child] then
                    Visit(child, (depth or 0) + 1)
                end
            end
        end
        local name = container.GetName and container:GetName()
        if name then
            for index = 1, 100 do
                local button = _G[name .. "Item" .. index]
                if button and not seen[button] then seen[button] = true; self:UpdateButton(button, container, touched) end
            end
        end
    end
    Visit(ContainerFrameCombinedBags)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do Visit(_G["ContainerFrame" .. i]) end
    self.visibleOverlays = 0
    for _, overlay in pairs(self.overlays) do
        if not touched[overlay] then overlay:Hide() end
        if overlay:IsShown() then self.visibleOverlays = self.visibleOverlays + 1 end
    end
end
function Bags:TestPulse()
    self.previewSerial = (self.previewSerial or 0) + 1
    local serial = self.previewSerial
    self.previewUntil = GetTime() + 6
    self:Refresh()
    ns:Print("Pulse preview: carried items are marked TEST for 6 seconds. Open your Blizzard bags to see it.")
    C_Timer.After(6, function()
        if self.previewSerial ~= serial then return end
        self.previewUntil = nil; self:Refresh()
    end)
end
local events = CreateFrame("Frame")
for _, event in ipairs({"BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED", "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED"}) do
    pcall(events.RegisterEvent, events, event)
end
local uiQueued = false
events:SetScript("OnEvent", function(_, event)
    Bags:Invalidate()
    -- Items that were still loading may now have a verdict for the window too. Item data
    -- arrives in bursts, so refresh at most twice a second.
    if (event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT") and ns.UI and not uiQueued then
        uiQueued = true
        C_Timer.After(0.5, function() uiQueued = false; ns.UI:Refresh() end)
    end
end)
local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    -- No item rescoring on this ticker unless gear, weights or item data changed.
    Bags:Refresh()
end)
