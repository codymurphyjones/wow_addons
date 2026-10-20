local _, ns = ...

-- Location: zone (colored by PvP status) and coordinates.
local T = SimplePanel.Theme

local PVP = {
    sanctuary = { T.blue, "Sanctuary" }, friendly = { T.green, "Friendly" }, hostile = { T.red, "Hostile" },
    contested = { T.orange, "Contested" }, arena = { T.red, "Arena" }, combat = { T.red, "Combat zone" },
}

local function Coords(p)
    local x, y = ns.Compat.PlayerCoords()
    if not x then return nil end
    local fmt = p:Get("precise") and "%.1f, %.1f" or "%d, %d"
    if not p:Get("precise") then x, y = math.floor(x + 0.5), math.floor(y + 0.5) end
    return fmt:format(x, y)
end

local PLACES = {
    { "both", "Place (Zone)", "Wildshore (Stranglethorn Vale). Just the zone where there's no smaller place." },
    { "minimap", "Place only", "The most specific place you're in, the same name the minimap shows: Wildshore, Booty Bay, an inn." },
    { "zone", "Zone only", "Stranglethorn Vale." },
}

-- The place (what the minimap shows) and, when the setting asks for it and it adds anything, the zone.
local function PlaceName(p)
    local zone = GetRealZoneText() or ""
    local place = (GetMinimapZoneText and GetMinimapZoneText()) or ""
    if place == "" then place = GetSubZoneText() or "" end
    if place == "" then place = zone end
    local mode = p:Get("placeName")
    if mode == "zone" then return zone end
    if mode == "both" and place ~= zone and zone ~= "" then return place, zone end
    return place
end

SimplePanel.RegisterPlugin({
    id = "Location",
    name = "Location",
    category = "Information",
    icon = 134269,
    zone = "center",
    minimapZone = true, -- can also sit on top of the minimap (the Minimap plugin's strip)
    showIcon = false,
    defaults = { coords = true, placeName = "both", precise = false },
    events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    interval = 0.5,

    -- Earlier versions kept this choice as `subzone`, then `place`.
    onInit = function(p) local s = p:Settings(); s.subzone, s.place = nil, nil end,

    text = function(p)
        local pvp = PVP[ns.Compat.ZonePVPInfo() or ""]
        local place, zone = PlaceName(p)
        local segs = { { text = place, color = pvp and pvp[1] or T.text } }
        if zone then segs[#segs + 1] = { text = "(" .. zone .. ")", color = T.muted } end
        local c = p:Get("coords") and Coords(p)
        if c then segs[#segs + 1] = { text = "\194\183 " .. c, color = T.muted } end
        return segs
    end,

    tooltip = function(p, tt)
        local pvpType, _, faction = ns.Compat.ZonePVPInfo()
        local pvp = PVP[pvpType or ""]
        tt:AddDouble("Zone", GetRealZoneText() or "")
        local sub = GetSubZoneText()
        if sub and sub ~= "" then tt:AddDouble("Subzone", sub) end
        if pvp then tt:AddDouble("Status", pvp[2] .. (faction and faction ~= "" and (" (" .. faction .. ")") or ""), nil, pvp[1]) end
        local c = Coords(p)
        tt:AddDouble("Coordinates", c or "n/a")
        tt:AddHint("Click: world map  ·  Shift-click: put coordinates in chat")
    end,

    menu = function(p, m)
        m:Checkbox({ text = "Coordinates", get = function() return p:Get("coords") end, set = function(v) p:Set("coords", v) end })
        m:Checkbox({ text = "Precise coordinates", get = function() return p:Get("precise") end, set = function(v) p:Set("precise", v) end })
        m:Header("Place name")
        for _, v in ipairs(PLACES) do
            m:Radio({ text = v[2], value = v[1], get = function() return p:Get("placeName") end, set = function(x) p:Set("placeName", x) end,
                tooltip = v[3] })
        end
    end,

    -- The world map opens through the minimap's own map button (see SecureClick.lua).
    secure = function() return ns.SecureClick.Click(MiniMapWorldMapButton) end,
    secureInCombat = true,

    onClick = function(p, button)
        if button ~= "LeftButton" then return end
        if IsShiftKeyDown() then
            local c = Coords(p)
            local zone, place = GetRealZoneText() or "", (GetMinimapZoneText and GetMinimapZoneText()) or ""
            local where = (place ~= "" and place ~= zone) and (place .. " (" .. zone .. ")") or zone
            local text = where .. (c and (" (" .. c .. ")") or "")
            if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then ChatEdit_GetActiveWindow():Insert(text)
            elseif ChatFrame_OpenChat then ChatFrame_OpenChat(text) end
        elseif ToggleWorldMap then
            ns.SecureClick.Open(ToggleWorldMap, "the map")
        end
    end,
})
