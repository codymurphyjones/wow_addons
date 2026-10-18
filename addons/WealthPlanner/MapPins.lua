local _, ns = ...
local C = ns.Compat

-- Questie-style world map pins for the job you took (or one you're previewing): a coloured dot for
-- every spawn of its mobs or nodes, one colour per mob or node. On a continent or world map the
-- job's zone gets one labelled marker instead. Hover a dot for what it drops; click it to point the
-- Waypoint addon's arrow at it. Built like Convergence's pins: pooled buttons on the map canvas.
local Pins = {}
ns.MapPins = Pins

local DOT = 9      -- on-screen size of a spawn dot
local MARKER = 18  -- on-screen size of a zone marker
local T = ns.Widgets.Theme

local pins, used = {}, 0
local preview -- job key shown without taking it (Jobs Board "Show on map")

function Pins:Preview(key) preview = key; self:Refresh() end

local function JobShown()
    local key = ns.char.activeJob or ns.char.trackedJob or preview
    return key and ns.Jobs:Get(key)
end

local function Color(i) return T.series[(i - 1) % #T.series + 1] end

local function OnEnter(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local data = ns.FarmData
    if pin.marker then
        GameTooltip:AddLine(pin.job.title, 0.33, 0.92, 0.78)
        GameTooltip:AddLine(("%s  -  %s an hour"):format(pin.job.zoneName, ns.Gold(pin.job.pay)), 1, 1, 1)
        GameTooltip:AddLine("Open this zone's map to see every spot.", 0.6, 0.6, 0.6)
    else
        local name, extra
        if pin.kind == "npc" then
            local npc = data.npcs[pin.id]
            name = npc[1]
            extra = ("Level %d%s%s"):format(npc[2] or 0, (npc[3] and npc[3] ~= npc[2]) and ("-" .. npc[3]) or "", (npc[4] or 0) == 1 and " Elite" or "")
        else
            local obj = data.objects[pin.id]
            name = obj[1]
            extra = obj.skill and obj.skill > 1 and ("Needs skill %d"):format(obj.skill) or nil
        end
        local col = Color(pin.index)
        GameTooltip:AddLine(name, col[1], col[2], col[3])
        if extra then GameTooltip:AddLine(extra, 0.8, 0.8, 0.8) end
        local per = 0
        for _, d in ipairs(ns.Jobs:DropsOf(pin.kind, pin.id)) do
            local price = ns.Prices:Price(d.item) or ns.Prices:Vendor(d.item) or 0
            per = per + price * d.chance
            local iname = C.GetItemInfo(d.item) or ("item " .. d.item)
            GameTooltip:AddDoubleLine(("%s%s"):format(iname, d.skin and " (skinned)" or ""),
                ("%.0f%%  %s"):format(d.chance * 100, ns.Gold(price)), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(("About %s a %s in goods"):format(ns.Gold(per), pin.kind == "npc" and "kill" or "node"), 0.35, 0.95, 0.55)
        GameTooltip:AddLine(("%s  %.1f, %.1f"):format(ns.Jobs.ZoneName(pin.mapID), pin.x, pin.y), 0.6, 0.6, 0.6)
        if ns.Nav:HasArrow() then GameTooltip:AddLine("Click to point the arrow here", 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function OnClick(pin)
    if pin.marker then return WorldMapFrame:SetMapID(pin.job.zone) end
    if not ns.Nav:HasArrow() then return end
    local data = ns.FarmData
    local info = pin.kind == "npc" and data.npcs[pin.id] or pin.kind == "object" and data.objects[pin.id]
    Waypoint:Set("WealthPlanner", {
        key = "spot", title = info and info[1] or pin.job.title, subtitle = pin.job.title,
        mapID = pin.mapID, x = pin.x / 100, y = pin.y / 100,
        onClick = function() ns.UI:Show("jobs") end,
    })
end

local function GetPin(canvas)
    used = used + 1
    local pin = pins[used]
    if not pin then
        pin = CreateFrame("Button", nil, canvas)
        pin.border = pin:CreateTexture(nil, "BACKGROUND")
        pin.border:SetPoint("TOPLEFT", -1, 1); pin.border:SetPoint("BOTTOMRIGHT", 1, -1)
        pin.border:SetColorTexture(0, 0, 0, 0.9)
        pin.dot = pin:CreateTexture(nil, "ARTWORK"); pin.dot:SetAllPoints()
        pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pin.label:SetPoint("LEFT", pin, "RIGHT", 3, 0)
        pin:SetScript("OnEnter", OnEnter)
        pin:SetScript("OnLeave", GameTooltip_Hide)
        pin:SetScript("OnClick", OnClick)
        pins[used] = pin
    end
    return pin
end

-- Where a point on zoneID lands on mapID, as 0..1 fractions, or nil if it's off that map.
local function Project(zoneID, x, y, mapID)
    if zoneID == mapID then return x, y end
    local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, zoneID, CreateVector2D(x, y))
    if not ok or not world then return end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, mapID)
    if not ok2 or not pos then return end
    local px, py = pos:GetXY()
    if px >= 0 and px <= 1 and py >= 0 and py <= 1 then return px, py end
end

local function Place(pin, canvas, scale, w, h, px, py, size)
    pin:SetSize(size, size)
    pin:SetScale(scale)
    pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", px * w / scale, -py * h / scale)
    pin:Show()
end

function Pins:Refresh()
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    local map = WorldMapFrame
    local mapID = map:GetMapID()
    local canvas = map:GetCanvas()
    for i = 1, used do pins[i]:Hide() end
    used = 0
    local job = ns.db and ns.db.options.mapPins and JobShown()
    if not (mapID and job) then return end

    local scale = 1 / (map:GetCanvasScale() or 1)
    local w, h = canvas:GetSize()
    if mapID == job.zone then
        for _, pt in ipairs(ns.Jobs:Pins(job, job.zone)) do
            local pin = GetPin(canvas)
            pin.marker, pin.job = nil, job
            pin.kind, pin.id, pin.index, pin.mapID, pin.x, pin.y = pt.kind, pt.id, pt.index, job.zone, pt[1], pt[2]
            local col = Color(pt.index)
            pin.dot:SetTexture(nil); pin.dot:SetColorTexture(col[1], col[2], col[3], 1)
            pin.label:SetText("")
            Place(pin, canvas, scale, w, h, pt[1] / 100, pt[2] / 100, DOT)
        end
    else
        -- A bigger map: one marker in the middle of the job's spots.
        local sx, sy, n = 0, 0, 0
        for _, pt in ipairs(ns.Jobs:Pins(job, job.zone)) do sx, sy, n = sx + pt[1], sy + pt[2], n + 1 end
        if n == 0 then return end
        local px, py = Project(job.zone, sx / n / 100, sy / n / 100, mapID)
        if not px then return end
        local pin = GetPin(canvas)
        pin.marker, pin.job = true, job
        pin.dot:SetTexture(ns.Jobs.KIND_ICON[job.kind]); pin.dot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pin.label:SetText(job.title)
        Place(pin, canvas, scale, w, h, px, py, MARKER)
    end
end

ns:On("PLAYER_LOGIN", function()
    if not WorldMapFrame then return end
    local function Refresh() Pins:Refresh() end
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Refresh)
    hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", Refresh)
    WorldMapFrame:HookScript("OnShow", Refresh)
    -- A preview lasts until the map closes.
    WorldMapFrame:HookScript("OnHide", function() preview = nil end)
end)
