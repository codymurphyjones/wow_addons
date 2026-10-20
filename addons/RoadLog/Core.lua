local addonName, ns = ...

ns.VERSION = "0.1.0"
-- RoadLog's logo, shipped in the addon (tools\RoadLog\make_icon.py draws it).
ns.ICON = "Interface\\AddOns\\RoadLog\\Media\\Icon"

-- The logo as inline text markup, size x size pixels.
function ns.IconMarkup(size)
    return ("|T%s:%d:%d|t"):format(ns.ICON, size, size)
end

ns.PREFIX = ns.IconMarkup(14) .. " |cffd9b77aRoadLog|r"

-- Account-wide: roads are the same for every character.
ns.DEFAULTS = {
    enabled = false, -- the toggle: while on, every step you walk counts as road
    showMap = false, -- draw recorded roads on the world map (Settings: Show roads, /roadlog map)
    smooth = true,   -- draw roads cleaned up (Smooth.lua: weaving out, repeated passes merged, loops faint); what's recorded stays as is
    showBlockers = true, -- draw blockers (red lines) on the world map
    showPasses = true,   -- draw narrow passes (blue spots) on the world map
    showTransitions = true, -- draw zone transitions (purple spots) on the world map
    showCaves = true,       -- draw logged caves on the world map, shaded by height once it's worked out
    mode = "road",   -- what you're logging: "road", "blocker" or "cave" (the minimap button's right-click menu)
    minimap = { angle = 220, hide = false },
    -- [continent] = { { zone = mapID, at = time(), pts = { n1, w1, n2, w2, ... } } }: one entry per
    -- unbroken stretch of walking, in world yards (north, west) rounded to 0.1.
    roads = {},
    blockers = {},   -- the same, for walls, fences and cliff edges you walked along and can't cross
    -- the same, for paths through caves, every 2 yards and kept whole, plus name (the cave's, from
    -- the minimap), falls = { [point] = seconds in the air } and inside = "0011...", a character
    -- per point, 1 where the game had you indoors (heights: Data/Caves.lua, built)
    caves = {},
    passes = {},     -- [continent] = { { zone, at, n, w } }: narrow spots you can get through
    -- [continent] = { { zone, other, label, at, n, w } }: where one zone meets another (other: the
    -- nearest other zone, nil if none was found); label "Durotar-The Barrens Transition"
    transitions = {},
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. ": " .. tostring(msg))
end

-- Something changed: redraw the button and the map once, next frame.
local pending
function ns:Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if ns.MinimapButton then ns.MinimapButton:Refresh() end
        if ns.MapLines then ns.MapLines:Refresh() end
        if ns.Marks then ns.Marks:Refresh() end
    end)
end

local frame = CreateFrame("Frame")
local handlers = {}
function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(frame.RegisterEvent, frame, event)
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

function ns:OnLoad(fn)
    self.onLoad = self.onLoad or {}
    table.insert(self.onLoad, fn)
end

ns:On("ADDON_LOADED", function(name)
    if name ~= addonName then return end
    RoadLogDB = Merge(type(RoadLogDB) == "table" and RoadLogDB or {}, ns.DEFAULTS)
    ns.db = RoadLogDB
    -- Roads used to be drawn by default, and that default was saved like a choice. Switch them off
    -- once; after that Show roads is only ever changed by you.
    if not ns.db.roadsOffByDefault then
        ns.db.showMap = false
        ns.db.roadsOffByDefault = true
    end
    for _, fn in ipairs(ns.onLoad or {}) do fn() end
end)

ns:On("PLAYER_LOGIN", function()
    ns:Print("v" .. ns.VERSION .. " loaded. Recording is " .. (ns.db.enabled and "|cff7fdf7fon|r" or "off")
        .. ". |cffffffff/roadlog help|r for more.")
end)

-- Yards as text: "850 yd", "12,400 yd".
function ns.Yards(yd)
    yd = math.floor((yd or 0) + 0.5)
    local s = tostring(yd):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return s .. " yd"
end

function ns:SetEnabled(on)
    if on == nil then on = not self.db.enabled end
    self.db.enabled = on and true or false
    ns.Recorder:Update()
    self:Print(not self.db.enabled and "Recording off."
        or self.db.mode == "blocker" and "Logging |cffff6050blockers|r: walk along the wall, fence or cliff edge."
        or self.db.mode == "cave" and "Logging a |cff40c4cdcave|r: walk its passages; heights are worked out by the next build."
        or "Recording |cff7fdf7fon|r: walk down the middle of the road.")
    self:Changed()
end

function ns:SetShowMap(on)
    if on == nil then on = not self.db.showMap end
    self.db.showMap = on and true or false
    self:Print(self.db.showMap and "Roads shown on the world map." or "Roads hidden on the world map.")
    self:Changed()
end

local function Stats()
    local marks = ns.Recorder:MarksText()
    if marks then ns:Print(marks .. " logged.") end
    local any = false
    for continent, segs in pairs(ns.db.roads) do
        if #segs > 0 then
            any = true
            local yd = 0
            for _, seg in ipairs(segs) do yd = yd + ns.Recorder.Length(seg.pts) end
            ns:Print(("Continent %s: %s in %d stretch%s"):format(tostring(continent), ns.Yards(yd), #segs, #segs == 1 and "" or "es"))
        end
    end
    if not any then ns:Print("No roads recorded yet.") end
end

StaticPopupDialogs.ROADLOG_CLEAR = {
    text = "Delete every road, blocker, cave, narrow pass and zone transition RoadLog has recorded, for all your characters?",
    button1 = YES, button2 = NO,
    OnAccept = function() ns.Recorder:Clear() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Help()
    ns:Print("/roadlog - turn recording on or off (or: on | off)")
    ns:Print("/roadlog map - show or hide recorded roads on the world map")
    ns:Print("/roadlog smooth - draw roads cleaned up (weaving out, repeated passes merged, loops faint) or as recorded")
    ns:Print("/roadlog road | blocker | cave - log roads, blockers (walls, fences, cliff edges you can't cross) or a cave")
    ns:Print("/roadlog pass - mark a narrow pass you can get through, where you stand")
    ns:Print("/roadlog transition - mark a zone transition where you stand (named after the two nearest zones)")
    ns:Print("/roadlog options - open RoadLog's settings")
    ns:Print("/roadlog undo - delete the last road, blocker, pass or transition you logged")
    ns:Print("/roadlog clear - delete every road (asks first)")
    ns:Print("/roadlog stats - yards recorded per continent")
    ns:Print("/roadlog minimap - show or hide the minimap button")
    ns:Print("While on, every step counts as road. It pauses while you're dead, swimming, flying, on a flight path, indoors or in an instance (caves: only dead, flying, flight path or instance).")
end

SLASH_ROADLOG1 = "/roadlog"
SLASH_ROADLOG2 = "/roads"
SlashCmdList.ROADLOG = function(msg)
    if not ns.db then return end
    local cmd = strlower(strtrim(msg or ""))
    if cmd == "" or cmd == "toggle" then
        ns:SetEnabled()
    elseif cmd == "on" or cmd == "off" then
        ns:SetEnabled(cmd == "on")
    elseif cmd == "map" then
        ns:SetShowMap()
    elseif cmd == "smooth" then
        ns.db.smooth = not ns.db.smooth
        ns:Print(ns.db.smooth and "Roads drawn with the weaving taken out." or "Roads drawn exactly as recorded.")
        ns:Changed()
    elseif cmd == "road" or cmd == "blocker" or cmd == "cave" then
        ns.Recorder:SetMode(cmd)
        ns:Print(cmd == "blocker" and "Logging blockers: walk along walls, fences and cliff edges you can't cross."
            or cmd == "cave" and "Logging caves: walk every passage; heights are worked out by the next build (yarn build --dev)."
            or "Logging roads.")
    elseif cmd == "pass" then
        ns.Recorder:MarkPass()
    elseif cmd == "transition" then
        ns.Recorder:MarkTransition()
    elseif cmd == "options" or cmd == "settings" then
        if ns.Settings then ns.Settings:Open() end
    elseif cmd == "undo" then
        ns.Recorder:Undo()
    elseif cmd == "clear" then
        StaticPopup_Show("ROADLOG_CLEAR")
    elseif cmd == "stats" then
        Stats()
    elseif cmd == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        ns.MinimapButton:Refresh()
        ns:Print(ns.db.minimap.hide and "Minimap button hidden. /roadlog minimap shows it again." or "Minimap button shown.")
    else
        Help()
    end
end

function RoadLog_OnCompartmentClick()
    if ns.db then ns:SetEnabled() end
end
