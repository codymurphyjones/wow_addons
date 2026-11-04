local _, ns = ...

-- The game's frames that neither Edit Mode nor Bartender4 lets you move, movable in Edit Mode.
-- Opening the game's Edit Mode puts a box over each one (alongside Edit Mode's own); drag a box
-- to move its frame, right-click it to put the frame back where the game keeps it. The places are
-- remembered (account-wide) and kept: whenever the game puts one of those frames back in its old
-- spot, it goes back to yours.
--   /whud move          the boxes without Edit Mode (again to lock)
--   /whud move list     every frame on the list and what moves it in this client
--   /whud move reset    every frame back where the game keeps it
--
-- Which frames Edit Mode covers isn't the same in every client, so the list below holds every
-- candidate, and each is checked when the boxes come up: a frame Edit Mode registered as one of its
-- systems, one Bartender4 took over, one SaddleBags holds in a panel, one SimplePanel places itself
-- (its minimap square, the buffs lined up beside it) and the player frame while the orb replaces it
-- all get no box. Bartender4's frames (action bars, pet, stance, possess, totem bars, bags, micro
-- menu, queue status, extra action and zone ability buttons, vehicle leave, XP/reputation bars) are
-- left off the list altogether. The flag carrier column has its own box (RightColumn.lua).
local M = {}
ns.Movers = M

-- { key, label, names (the first that exists in this client) }
local LIST = {
    -- Edit Mode covers these on clients that have them as systems; checked at run time.
    { key = "player", label = "Player frame", names = { "PlayerFrame" },
        skip = function() return ns.Vitals and ns.Vitals:PlayerFrameHidden() and "replaced by the orb" end },
    { key = "target", label = "Target frame", names = { "TargetFrame" } },
    { key = "focus", label = "Focus frame", names = { "FocusFrame" } },
    { key = "pet", label = "Pet frame", names = { "PetFrame" } },
    { key = "party", label = "Party frames", names = { "PartyFrame" } },
    { key = "boss", label = "Boss frames", names = { "BossTargetFrameContainer", "Boss1TargetFrame" } },
    { key = "castbar", label = "Cast bar", names = { "PlayerCastingBarFrame", "CastingBarFrame" } },
    { key = "minimap", label = "Minimap", names = { "MinimapCluster" } },
    { key = "buffs", label = "Buffs", names = { "BuffFrame" } },
    { key = "debuffs", label = "Debuffs", names = { "DebuffFrame" } },
    { key = "enchants", label = "Weapon enchants", names = { "TemporaryEnchantFrame" } },
    { key = "tracker", label = "Quest tracker", names = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" } },
    { key = "durability", label = "Durability figure", names = { "DurabilityFrame" } },
    { key = "seats", label = "Vehicle seats", names = { "VehicleSeatIndicator" } },
    { key = "timers", label = "Breath / fatigue bars", names = { "MirrorTimerContainer", "MirrorTimer1" } },
    { key = "encounterBar", label = "Encounter power bar", names = { "EncounterBar", "PlayerPowerBarAlt" } },
    { key = "talkingHead", label = "Talking head", names = { "TalkingHeadFrame" } },
    { key = "damageMeter", label = "Damage meter", names = { "DamageMeter" } },
    -- Never in Edit Mode.
    { key = "topCenter", label = "Top-center objectives (PvP, zone)", names = { "UIWidgetTopCenterContainerFrame" } },
    { key = "belowMinimap", label = "Below-minimap widgets", names = { "UIWidgetBelowMinimapContainerFrame" } },
    { key = "errors", label = "Error messages", names = { "UIErrorsFrame" } },
    { key = "raidWarning", label = "Raid warnings", names = { "RaidWarningFrame" } },
    { key = "bossEmote", label = "Boss emotes", names = { "RaidBossEmoteFrame" } },
    { key = "zoneText", label = "Zone name text", names = { "ZoneTextFrame" } },
    { key = "lootRolls", label = "Loot rolls", names = { "GroupLootContainer" } },
    { key = "alerts", label = "Alerts (loot won, achievements)", names = { "AlertFrame" } },
    { key = "eventToasts", label = "Event toasts (level up, zones)", names = { "EventToastManagerFrame" } },
    { key = "bossBanner", label = "Boss kill banner", names = { "BossBanner" } },
    { key = "bnToast", label = "Battle.net toasts", names = { "BNToastFrame" } },
    { key = "questTimers", label = "Quest timers", names = { "QuestTimerFrame" } },
    { key = "lossOfControl", label = "Loss of control alert", names = { "LossOfControlFrame" } },
    { key = "ticket", label = "GM ticket status", names = { "TicketStatusFrame" } },
    { key = "fps", label = "Framerate (Ctrl+R)", names = { "FramerateFrame" } },
}
M.LIST = LIST

local BY_FRAME = {}         -- [frame] = entry, for the frames found so far
local original = {}         -- [key] = the frame's own points, kept the first time it's moved
local hooked = {}           -- [frame] = SetPoint hooked
local movers = {}           -- [key] = its box
local applying = false
local shown = false         -- the boxes are up
local byEditMode = false    -- ... because Edit Mode opened them

local function Saved() return ns.db and ns.db.movers end

local function Resolve(entry)
    for _, name in ipairs(entry.names) do
        local f = _G[name]
        if type(f) == "table" and f.GetPoint then return f, name end
    end
end

local function Protected(f) return f.IsProtected ~= nil and f:IsProtected() end

local function EditModeSystem(f)
    if f.system ~= nil or f.systemInfo ~= nil then return true end
    local list = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
    if type(list) == "table" then
        for _, s in ipairs(list) do if s == f then return true end end
    end
    return false
end

-- nil when we move it; otherwise why not (for /whud move list).
local function WhyNot(entry, f)
    if not f then return "not in this client" end
    if f.IsForbidden and f:IsForbidden() then return "the game keeps it to itself" end
    if EditModeSystem(f) then return "Edit Mode moves it" end
    if Bartender4 and Bartender4.UIHider and f:GetParent() == Bartender4.UIHider then return "Bartender4 replaces it" end
    if SaddleBags and SaddleBags.captured and SaddleBags.captured[f] then return "held in a SaddleBags panel" end
    if SimplePanel and SimplePanel.PlacesFrame and SimplePanel.PlacesFrame(f) then return "SimplePanel places it" end
    if entry.skip then
        local why = entry.skip(f)
        if why then return why end
    end
    return nil
end

-- The frame's scale against UIParent's (UIParent units = own units * k).
local function ScaleOf(f)
    local s = f:GetEffectiveScale()
    if not s or s == 0 then return nil end
    return s / UIParent:GetEffectiveScale()
end

-- The point it hangs by (its first anchor's), so a container keeps growing the way it did.
local function HangPoint(f, entry)
    if original[entry.key] and original[entry.key][1] then return original[entry.key][1][1] end
    local p = f:GetNumPoints() > 0 and f:GetPoint(1)
    return type(p) == "string" and p or "CENTER"
end

-- Where point p of a rectangle sits (UIParent units).
local function PointXY(p, l, b, r, t)
    local x = p:find("LEFT") and l or p:find("RIGHT") and r or (l + r) / 2
    local y = p:find("TOP") and t or p:find("BOTTOM") and b or (b + t) / 2
    return x, y
end

-- The frame's edges in UIParent units, or nil when it has no place.
local function Edges(f)
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok or not (l and b and w and h) then return nil end
    if issecretvalue and (issecretvalue(l) or issecretvalue(b) or issecretvalue(w) or issecretvalue(h)) then return nil end
    local k = ScaleOf(f)
    if not k then return nil end
    return l * k, b * k, (l + w) * k, (b + h) * k
end

local function KeepOriginal(entry, f)
    if original[entry.key] then return end
    local pts = {}
    for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
    original[entry.key] = pts
end

local ApplyAll

local function Apply(entry)
    local saved = Saved() and Saved()[entry.key]
    if not saved then return end
    local f = Resolve(entry)
    if not f or WhyNot(entry, f) then return end
    if InCombatLockdown() and Protected(f) then return ns:AfterCombat("wallyhudMovers", ApplyAll) end
    local k = ScaleOf(f)
    if not k then return end
    KeepOriginal(entry, f)
    applying = true
    local ok = pcall(function()
        f:ClearAllPoints()
        f:SetPoint(saved.point, UIParent, "BOTTOMLEFT", saved.x / k, saved.y / k)
    end)
    applying = false
    if not ok then
        Saved()[entry.key] = nil
        ns:Print(entry.label .. " can't be moved in this client; it stays where the game keeps it.")
    end
end

-- Whenever the game (or another addon) puts it back in its spot: back to yours, next frame.
local function Hook(entry, f)
    BY_FRAME[f] = entry
    if hooked[f] then return end
    hooked[f] = true
    local queued = false
    hooksecurefunc(f, "SetPoint", function(self)
        if applying then return end
        local e = BY_FRAME[self]
        if not (e and Saved() and Saved()[e.key]) or queued then return end
        queued = true
        C_Timer.After(0, function() queued = false; Apply(e) end)
    end)
end

function ApplyAll()
    for _, entry in ipairs(LIST) do
        local f = Resolve(entry)
        if f and not WhyNot(entry, f) then
            Hook(entry, f)
            Apply(entry)
        end
    end
end
M.ApplyAll = ApplyAll

local function Reset(entry)
    local f = Resolve(entry)
    if Saved() then Saved()[entry.key] = nil end
    local pts = original[entry.key]
    original[entry.key] = nil
    if not (f and pts) then return true end
    if InCombatLockdown() and Protected(f) then
        ns:Print("After the fight: " .. entry.label .. " can't move in combat.")
        return false
    end
    applying = true
    pcall(function()
        f:ClearAllPoints()
        for _, pt in ipairs(pts) do f:SetPoint(unpack(pt)) end
    end)
    applying = false
    return true
end

-- Is this frame one we keep somewhere? (SimplePanel leaves those alone when it makes room for its bar.)
function WallyHUD.PlacesFrame(f)
    local entry = f and BY_FRAME[f]
    return entry ~= nil and Saved() ~= nil and Saved()[entry.key] ~= nil
end

-- ---------------------------------------------------------------------------
-- The boxes
-- ---------------------------------------------------------------------------

local MIN_W, MIN_H = 140, 26

-- The box's hang point, in UIParent units (the box's parent is UIParent, at scale 1).
local function BoxPoint(m)
    local l, b, w, h = m:GetRect()
    if not l then return nil end
    local s = m:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return PointXY(m.point, l * s, b * s, (l + w) * s, (b + h) * s)
end

local function Follow(m)
    local x, y = BoxPoint(m)
    if not x then return end
    Saved()[m.entry.key] = { point = m.point, x = x, y = y }
    Apply(m.entry)
end

-- Over the frame where it is now, at least big enough to grab.
local function PlaceBox(m, f)
    local l, b, r, t = Edges(f)
    if not l then
        local saved = Saved()[m.entry.key]
        if not saved then return false end
        l, b, r, t = saved.x, saved.y, saved.x, saved.y
    end
    local x, y = PointXY(m.point, l, b, r, t)
    m:SetSize(math.max(MIN_W, r - l), math.max(MIN_H, t - b))
    m:ClearAllPoints()
    m:SetPoint(m.point, UIParent, "BOTTOMLEFT", x, y)
    return true
end

local function MakeBox(entry)
    local T = ns.T
    local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m.entry = entry
    m:SetFrameStrata("DIALOG")
    m:SetMovable(true)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetClampedToScreen(true)
    WallyHUD.Panel(m, "raised")
    m:SetBackdropBorderColor(WallyHUD.RGBA(T.accent))
    local text = m:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(WallyHUD.FontLabel)
    text:SetPoint("TOPLEFT", 6, -4); text:SetPoint("BOTTOMRIGHT", -6, 4)
    text:SetWordWrap(true)
    text:SetText(WallyHUD.Upper(entry.label))
    m:SetScript("OnDragStart", function(self)
        local f = Resolve(self.entry)
        if not f or (InCombatLockdown() and Protected(f)) then return end
        self:StartMoving()
        self:SetScript("OnUpdate", Follow)
    end)
    m:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        Follow(self)
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        local f = Resolve(self.entry)
        if Reset(self.entry) and f then PlaceBox(self, f) end
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.entry.label)
        GameTooltip:AddLine("Drag to move it.", 1, 1, 1)
        GameTooltip:AddLine("Right-click: back where the game keeps it.", 1, 1, 1)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return m
end

function M:Show(fromEditMode)
    if InCombatLockdown() then return ns:Print("After the fight: frames can't be moved in combat.") end
    shown, byEditMode = true, fromEditMode and true or false
    for _, entry in ipairs(LIST) do
        local f = Resolve(entry)
        local m = movers[entry.key]
        if f and not WhyNot(entry, f) then
            Hook(entry, f)
            m = m or MakeBox(entry)
            movers[entry.key] = m
            m.point = HangPoint(f, entry)
            m:SetShown(PlaceBox(m, f))
        elseif m then
            m:Hide()
        end
    end
    if ns.RightColumn and ns.RightColumn.ShowMover then ns.RightColumn:ShowMover() end
end

function M:Hide()
    if not shown then return end
    shown = false
    for _, m in pairs(movers) do
        m:StopMovingOrSizing()
        m:SetScript("OnUpdate", nil)
        m:Hide()
    end
    if ns.RightColumn and ns.RightColumn.HideMover then ns.RightColumn:HideMover() end
end

function M:Toggle()
    if shown then
        self:Hide()
        ns:Print("Frames locked where they are.")
    else
        self:Show(false)
        ns:Print("Drag a box to move its frame; right-click it to put the frame back. /whud move again to lock.")
    end
end

function M:ResetAll()
    if InCombatLockdown() then return ns:Print("After the fight: frames can't be moved in combat.") end
    for _, entry in ipairs(LIST) do Reset(entry) end
    if shown then self:Show(byEditMode) end
    ns:Print("Every frame is back where the game keeps it.")
end

function M:PrintList()
    ns:Print("The frames Edit Mode and Bartender4 don't move, and what moves each one here:")
    for _, entry in ipairs(LIST) do
        local f, name = Resolve(entry)
        local why = WhyNot(entry, f)
        local moved = Saved() and Saved()[entry.key] and " (moved)" or ""
        local state = why and ("|cff8a8f99" .. why .. "|r") or ("|cff40c4cdWallyHUD moves it|r" .. moved)
        ns:Print(("  %s%s: %s"):format(entry.label, name and (" [" .. name .. "]") or "", state))
    end
end

-- ---------------------------------------------------------------------------
-- When
-- ---------------------------------------------------------------------------

ns:OnLoad(function()
    ns.db.movers = ns.db.movers or {}
end)

ns:On("PLAYER_ENTERING_WORLD", function()
    ApplyAll()
    -- Frames the game builds a moment later (widgets, toasts) and the ones it lays out again.
    C_Timer.After(1, ApplyAll)
end)

-- Load-on-demand frames (the talking head, the boss banner) arrive with their Blizzard addon.
local loadQueued = false
ns:On("ADDON_LOADED", function()
    if not ns.db or loadQueued then return end
    loadQueued = true
    C_Timer.After(0.5, function() loadQueued = false; ApplyAll() end)
end)

ns:On("UI_SCALE_CHANGED", function() ApplyAll() end)
ns:On("DISPLAY_SIZE_CHANGED", function() ApplyAll() end)
ns:On("PLAYER_REGEN_DISABLED", function()
    -- the boxes can't move protected frames in a fight; Edit Mode closes the same way
    if shown and not byEditMode then M:Hide() end
end)

ns:On("PLAYER_LOGIN", function()
    if not (EditModeManagerFrame and EventRegistry) then return end
    EventRegistry:RegisterCallback("EditMode.Enter", function() M:Show(true) end, M)
    EventRegistry:RegisterCallback("EditMode.Exit", function() M:Hide() end, M)
end)
