local _, ns = ...

-- One tracked place at a time: a marker on the world map (not the minimap)
-- and an on-screen tracker naming what's tracked. The tracker can be moved
-- in Edit Mode. Plugins set it through SpyGlass:SetWaypoint (API.lua).
local W = {}
ns.Waypoint = W

local PIN_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local current -- { uiMapID, x, y, title, subtitle, onClick }
local pin, tracker
local editing

local function DB()
    return ns.db
end

---------------------------------------------------------------------------
-- World map marker
---------------------------------------------------------------------------

-- Where the waypoint falls on the map being shown, as 0-1 coordinates, or
-- nil when it isn't on that map.
local function PositionOn(mapID)
    if not (current and mapID) then return nil end
    if mapID == current.uiMapID then return current.x, current.y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, current.uiMapID, CreateVector2D(current.x, current.y))
    if not (ok and continent and world) then return nil end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
    if not (ok2 and pos) then return nil end
    local x, y = pos:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function BuildPin()
    local canvas = WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
    if not canvas then return end
    pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(28, 28)
    pin:SetFrameStrata("HIGH")
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER")
    pin.glow:SetSize(44, 44)
    pin.glow:SetTexture("Interface\\Cooldown\\star4")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.82, 0.2, 0.8)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture(PIN_ICON)
    pin:SetScript("OnEnter", function(self)
        if not current then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(current.title, 1, 0.82, 0)
        if current.subtitle then GameTooltip:AddLine(current.subtitle, 1, 1, 1, true) end
        GameTooltip:AddLine("Tracked by SpyGlass. Click for details.", 0.4, 0.73, 1)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function()
        if current and current.onClick then current.onClick() end
    end)
    -- Keeps its size on screen however far the map is zoomed, and its place
    -- on the canvas (whose offsets are in the pin's scaled units).
    pin:SetScript("OnUpdate", function(self)
        local scroll = WorldMapFrame.ScrollContainer
        local scale = 1 / math.max(scroll.GetCanvasScale and scroll:GetCanvasScale() or 1, 0.01)
        self:SetScale(scale)
        local canvas = self:GetParent()
        self:ClearAllPoints()
        self:SetPoint("CENTER", canvas, "TOPLEFT", self.mapX * canvas:GetWidth() / scale,
            -self.mapY * canvas:GetHeight() / scale)
    end)
    pin:Hide()
end

function W:UpdatePin()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    if not pin then BuildPin() end
    if not pin then return end
    local x, y = PositionOn(WorldMapFrame:GetMapID())
    if not x then pin:Hide() return end
    pin.mapX, pin.mapY = x, y
    pin:Show()
end

---------------------------------------------------------------------------
-- Screen tracker (movable in Edit Mode)
---------------------------------------------------------------------------

local function SavePosition()
    local point, _, relPoint, x, y = tracker:GetPoint()
    DB().trackerPos = { point, relPoint, x, y }
end

local function BuildTracker()
    tracker = CreateFrame("Frame", "SpyGlassTracker", UIParent)
    tracker:SetSize(260, 44)
    local pos = DB().trackerPos
    if pos then
        tracker:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        tracker:SetPoint("TOP", 0, -120)
    end
    tracker:SetClampedToScreen(true)
    tracker:SetMovable(true)
    tracker:SetFrameStrata("MEDIUM")

    local bg = tracker:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    local edge = tracker:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(3)
    edge:SetColorTexture(1, 0.82, 0.2, 1)

    tracker.icon = tracker:CreateTexture(nil, "ARTWORK")
    tracker.icon:SetSize(24, 24)
    tracker.icon:SetPoint("LEFT", 10, 0)
    tracker.icon:SetTexture(PIN_ICON)
    tracker.label = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tracker.label:SetPoint("TOPLEFT", tracker.icon, "TOPRIGHT", 8, 1)
    tracker.label:SetText("Tracking")
    tracker.label:SetTextColor(0.7, 0.7, 0.7)
    tracker.title = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tracker.title:SetPoint("TOPLEFT", tracker.label, "BOTTOMLEFT", 0, -2)
    tracker.title:SetPoint("RIGHT", -24, 0)
    tracker.title:SetJustifyH("LEFT")
    tracker.title:SetWordWrap(false)

    local close = CreateFrame("Button", nil, tracker, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() W:Clear() end)
    tracker.close = close

    tracker:EnableMouse(true)
    tracker:SetScript("OnMouseUp", function(_, button)
        if editing or button ~= "LeftButton" then return end
        if current and current.onClick then current.onClick() end
    end)

    -- Edit Mode look: a blue box you can drag, like the game's own frames.
    tracker.selection = tracker:CreateTexture(nil, "OVERLAY")
    tracker.selection:SetPoint("TOPLEFT", -2, 2)
    tracker.selection:SetPoint("BOTTOMRIGHT", 2, -2)
    tracker.selection:SetColorTexture(0.25, 0.55, 1, 0.35)
    tracker.selection:Hide()
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", function(self) if editing then self:StartMoving() end end)
    tracker:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    tracker:Hide()
end

function W:UpdateTracker()
    if not tracker then BuildTracker() end
    if editing then
        tracker.title:SetText(current and current.title or "SpyGlass tracker")
        tracker.selection:Show()
        tracker.close:Hide()
        tracker:Show()
        return
    end
    tracker.selection:Hide()
    tracker.close:Show()
    if current then
        tracker.title:SetText(current.title)
        tracker:Show()
    else
        tracker:Hide()
    end
end

-- Edit Mode: show the tracker (even with nothing tracked) so it can be moved.
-- Hooks the manager's OnShow/OnHide rather than registering on EventRegistry:
-- writing into Blizzard's callback tables taints Edit Mode's layout pass,
-- which re-initializes PlayerFrame and breaks its secret health values.
local function HookEditMode()
    local mgr = EditModeManagerFrame
    if not (mgr and mgr.HookScript) then return end
    mgr:HookScript("OnShow", function()
        editing = true
        W:UpdateTracker()
    end)
    mgr:HookScript("OnHide", function()
        editing = false
        W:UpdateTracker()
    end)
end

-- Without Edit Mode on this client: /sg tracker unlocks it to drag.
function W:ToggleUnlocked()
    editing = not editing
    self:UpdateTracker()
    return editing
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- wp = { uiMapID, x, y (0-1 on that map), title, subtitle, onClick, key }.
-- Remembered across reloads (without onClick, which the plugin sets again).
function W:Set(wp)
    current = wp
    if DB() then
        DB().waypoint = { uiMapID = wp.uiMapID, x = wp.x, y = wp.y, title = wp.title, subtitle = wp.subtitle, key = wp.key }
    end
    self:UpdateTracker()
    self:UpdatePin()
end

function W:Clear()
    current = nil
    if DB() then DB().waypoint = nil end
    if pin then pin:Hide() end
    self:UpdateTracker()
end

function W:Get()
    return current
end

function W:Init()
    HookEditMode()
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() W:UpdatePin() end)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() W:UpdatePin() end)
        end
    end
    local saved = DB() and DB().waypoint
    if saved and saved.uiMapID then
        current = saved
    end
    self:UpdateTracker()
end
