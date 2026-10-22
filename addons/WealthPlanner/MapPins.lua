local _, ns = ...
local PAL = ns.Palette
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

local WM = ns.WorldMap
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
        GameTooltip:AddLine(pin.job.title, PAL.accent[1], PAL.accent[2], PAL.accent[3])
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

local function CreatePin(pin)
    pin.border = pin:CreateTexture(nil, "BACKGROUND")
    pin.border:SetPoint("TOPLEFT", -1, 1); pin.border:SetPoint("BOTTOMRIGHT", 1, -1)
    pin.border:SetColorTexture(0, 0, 0, 0.9)
    pin.dot = pin:CreateTexture(nil, "ARTWORK"); pin.dot:SetAllPoints()
    pin.label = pin:CreateFontString(nil, "OVERLAY", "WealthPlannerGameFontHighlightSmall")
    pin.label:SetPoint("LEFT", pin, "RIGHT", 3, 0)
    pin:SetScript("OnEnter", OnEnter)
    pin:SetScript("OnLeave", GameTooltip_Hide)
    pin:SetScript("OnClick", OnClick)
end

local function Draw(layer, mapID)
    local job = ns.db and ns.db.options.mapPins and JobShown()
    if not job then return end
    if mapID == job.zone then
        for _, pt in ipairs(ns.Jobs:Pins(job, job.zone)) do
            local pin = layer:Pin()
            pin.marker, pin.job = nil, job
            pin.kind, pin.id, pin.index, pin.mapID, pin.x, pin.y = pt.kind, pt.id, pt.index, job.zone, pt[1], pt[2]
            local col = Color(pt.index)
            pin.dot:SetTexture(nil); pin.dot:SetColorTexture(col[1], col[2], col[3], 1)
            pin.label:SetText("")
            layer:Place(pin, pt[1] / 100, pt[2] / 100, DOT)
        end
    else
        -- A bigger map: one marker in the middle of the job's spots.
        local sx, sy, n = 0, 0, 0
        for _, pt in ipairs(ns.Jobs:Pins(job, job.zone)) do sx, sy, n = sx + pt[1], sy + pt[2], n + 1 end
        if n == 0 then return end
        local px, py = WM.Project(job.zone, sx / n / 100, sy / n / 100, mapID)
        if not px then return end
        local pin = layer:Pin()
        pin.marker, pin.job = true, job
        pin.dot:SetTexture(ns.Jobs.KIND_ICON[job.kind]); pin.dot:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pin.label:SetText(job.title)
        layer:Place(pin, px, py, MARKER)
    end
end

-- Pins on the map canvas, 2000 levels over it; redrawn when the map changes, zooms or opens.
-- A preview lasts until the map closes.
local layer = WM.NewLayer({ base = "canvas", level = 2000, create = CreatePin, refresh = Draw,
    onHide = function() preview = nil end })
Pins.layer = layer

function Pins:Refresh() layer:Refresh() end
