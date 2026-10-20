local _, ns = ...

-- Docks on the world map: a zeppelin or ship icon on every zeppelin tower, skyship and ship dock
-- you can use (your faction's and neutral ones, plus Zeppelin Signs' moved and added signs).
-- Hovering shows where it goes and how long the ride takes; clicking leads the arrow there (a
-- request, as town icons do). While you're on a ride, the dock you left shows its timer is running
-- (a green ring) and where it lands shows the ride ending there (a gold ring), with the time left.
-- Ride times come from Zeppelin Signs, which times each ride from boarding; without it, from
-- Waypoint's own (waiting included). /way docks turns them off.
local Pins = {}
ns.TransportPins = Pins

local SIZE = 18
local LEVEL = 2095 -- over the town badges (up to +2090), under the path's pins (+2100)
local MEDIA = "Interface\\AddOns\\Waypoint\\Media\\"
local ICONS = { zeppelin = MEDIA .. "Zeppelin", skyship = MEDIA .. "Zeppelin", ship = MEDIA .. "Ship" }
local RING = "Interface\\Cooldown\\star4"
local DEPART = { 0.35, 0.95, 0.55 } -- A: the ride's timer is running from here
local ARRIVE = { 1, 0.82, 0.3 }     -- B: the ride ends here

local pins, used = {}, 0
local warned -- the icons didn't load (the game only finds new files after a restart)

local function SetIcon(tex, path)
    if tex:SetTexture(path) == false or not tex:GetTexture() then
        tex:SetTexture(ns.ICON)
        if not warned then
            warned = true
            ns:Print("Dock icons need a full game restart to load (showing Waypoint's icon until then).")
        end
    end
end

local function MyFaction()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

-- The ride you're on, as { fromKey, toKey, landing, left, timed }: Zeppelin Signs' when it has one,
-- else Waypoint's own (no landing or time known for B then).
local function Ride()
    local z = ns.Route.ZepRide and ns.Route.ZepRide()
    if z then return z end
    local r, riding = ns.Route.riding, ns.Route:Riding()
    if r and riding then return { fromKey = r.d.t.key, left = riding.left } end
end

local function Clock(secs) return ns.Flight.Clock(secs) end

-- "Ride: 2m 10s (timed 3 times)", from Zeppelin Signs; else Waypoint's own timing or guess.
local function RideLine(t)
    local api = ZeppelinSignsAPI
    local secs, n
    if api and api.RideTime then
        local ok, s, c = pcall(api.RideTime, t.key)
        if ok then secs, n = s, c end
    end
    if secs then return ("Ride: %s (timed %d time%s)"):format(Clock(secs), n, n == 1 and "" or "s") end
    local wait, timed = ns.Route:RideSecs(t)
    if timed then return ("Ride and wait: about %s"):format(Clock(wait)) end
    return "Ride: not timed yet"
end

local function OnEnter(pin)
    local d = pin.dock
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if not d then
        GameTooltip:AddLine("Your ride lands here", ARRIVE[1], ARRIVE[2], ARRIVE[3])
    else
        GameTooltip:AddLine(d.point.label, 1, 0.82, 0)
        if d.t.place then GameTooltip:AddLine("From " .. d.t.place, 0.8, 0.85, 0.9) end
        GameTooltip:AddLine(RideLine(d.t), 1, 1, 1)
    end
    local ride = Ride()
    if ride and pin.state == "from" then
        GameTooltip:AddLine(("Your ride from here: %s left"):format(Clock(ride.left)), DEPART[1], DEPART[2], DEPART[3])
    elseif ride and pin.state == "to" then
        GameTooltip:AddLine(ride.left > 0 and ("Your ride ends here in %s"):format(Clock(ride.left)) or "Your ride is arriving",
            ARRIVE[1], ARRIVE[2], ARRIVE[3])
    end
    if d then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: navigate here", 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local function OnLeave() GameTooltip:Hide() end

-- Leads the arrow to a dock, as a request (opening its master's window counts as there).
function Pins:Navigate(d)
    local p = d.point
    return ns.Targets:SetRequest("Docks", { title = p.label,
        points = { { mapID = p.mapID, x = p.x, y = p.y, label = p.label, npc = d.t.npc } },
        arrive = ns.Transports.RADIUS[d.t.kind] or 30 })
end

local function OnClick(pin, button)
    if IsControlKeyDown() then
        if button == "LeftButton" then ns.MapPins:AddAtCursor() end
    elseif button == "LeftButton" and pin.dock then
        Pins:Navigate(pin.dock)
    elseif button == "RightButton" and WorldMapFrame.NavigateToParentMap then
        WorldMapFrame:NavigateToParentMap()
    end
end

local function GetPin(canvas)
    used = used + 1
    local pin = pins[used]
    if not pin then
        pin = CreateFrame("Button", nil, canvas)
        pin.waypoint = true -- town badges never cover it (Towns.lua)
        pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pin.ring = pin:CreateTexture(nil, "BACKGROUND")
        pin.ring:SetPoint("CENTER")
        pin.ring:SetSize(SIZE * 2, SIZE * 2)
        pin.ring:SetTexture(RING)
        pin.ring:SetBlendMode("ADD")
        pin.icon = pin:CreateTexture(nil, "ARTWORK")
        pin.icon:SetAllPoints()
        pin.time = pin:CreateFontString(nil, "OVERLAY", "WaypointGameFontHighlightSmall")
        pin.time:SetPoint("TOP", pin, "BOTTOM", 0, -1)
        pin:SetScript("OnEnter", OnEnter)
        pin:SetScript("OnLeave", OnLeave)
        pin:SetScript("OnClick", OnClick)
        pins[used] = pin
    end
    return pin
end

-- A: the ride is on from here; B: it ends here; nil: neither.
local function SetState(pin, state)
    pin.state = state
    local c = state == "from" and DEPART or state == "to" and ARRIVE
    pin.ring:SetShown(c and true or false)
    pin.time:SetShown(c and true or false)
    if c then
        pin.ring:SetVertexColor(c[1], c[2], c[3], 0.9)
        pin.time:SetTextColor(c[1], c[2], c[3])
    end
end

local function Place(pin, canvas, mapID, x, y)
    local cx, cy = ns.Nav:OnCanvas(mapID, x, y, WorldMapFrame:GetMapID())
    if not cx then return false end
    local w, h = canvas:GetSize()
    local scale = 1 / (WorldMapFrame:GetCanvasScale() or 1) -- the same size on screen at any zoom
    pin:SetSize(SIZE, SIZE)
    pin:SetScale(scale)
    pin:SetFrameLevel(ns:MapBase(canvas) + LEVEL)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", cx * w / scale, -cy * h / scale)
    pin:Show()
    return true
end

-- Shown on zone and continent maps; the world map would be a pile of icons.
local function MapShows(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and info.mapType and Enum and Enum.UIMapType and info.mapType >= Enum.UIMapType.Continent
end

function Pins:Refresh()
    for i = 1, used do pins[i]:Hide() end
    used = 0
    if not (ns.db and ns.db.transportPins and ns.Transports and WorldMapFrame and WorldMapFrame:IsShown()) then return end
    if not MapShows(WorldMapFrame:GetMapID()) then return end
    local canvas = WorldMapFrame:GetCanvas()
    local mine, ride = MyFaction(), Ride()
    local landed -- B's dock was drawn
    for _, d in ipairs(ns.Route:Docks()) do
        if not d.t.faction or d.t.faction == mine then
            local pin = GetPin(canvas)
            pin.dock = d
            SetIcon(pin.icon, ICONS[d.t.kind] or ICONS.ship)
            if Place(pin, canvas, d.point.mapID, d.point.x, d.point.y) then
                local state = ride and (ride.fromKey == d.t.key and "from" or ride.toKey == d.t.key and "to") or nil
                if state == "to" then landed = true end
                SetState(pin, state)
            else
                used = used - 1
            end
        end
    end
    -- Where the ride lands, when that isn't a dock (you got off there last time).
    if ride and not landed and ride.landing then
        local pin = GetPin(canvas)
        pin.dock = nil
        SetIcon(pin.icon, ICONS[ride.kind] or ICONS.ship)
        if Place(pin, canvas, ride.landing.mapID, ride.landing.x, ride.landing.y) then SetState(pin, "to") else used = used - 1 end
    end
    self:Tick()
end

-- The time left under A and B, while a ride is on.
function Pins:Tick()
    local ride = used > 0 and Ride()
    for i = 1, used do
        local pin = pins[i]
        if pin.state == "from" then
            pin.time:SetText(ride and Clock(ride.left) or "")
        elseif pin.state == "to" then
            pin.time:SetText(ride and (ride.left > 0 and Clock(ride.left) or "Arriving") or "")
        end
    end
end

ns:On("PLAYER_LOGIN", function()
    if not WorldMapFrame then return end
    local function Refresh() Pins:Refresh() end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
    if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Refresh) end
    WorldMapFrame:HookScript("OnShow", Refresh)
    local acc = 0
    CreateFrame("Frame"):SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        if WorldMapFrame:IsShown() and used > 0 then Pins:Tick() end
    end)
end)
