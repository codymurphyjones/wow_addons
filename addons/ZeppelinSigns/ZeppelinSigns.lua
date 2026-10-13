local _, Z = ...

Z.VERSION = "1.1.2"
-- How close (in yards) you must stand to a dock for its sign to show. The two
-- Grom'gol zeppelin masters are only ~17 yards apart, so zeppelins stay below that.
Z.RADIUS = { zeppelin = 15, ship = 30 }
-- How far /zep mark and /zep remove look for the sign to change.
Z.MARK_RANGE = 60
Z.TICK = 0.25

local KIND_LABEL = { zeppelin = "Zeppelin", ship = "Ship" }

-- Built-in signs (zone %, uiMapID). Zeppelin masters come from Wowhead's NPC data,
-- docks from Wowhead's Forever world map. npc = a master you can also mouse over
-- or look at to see the sign.
local SIGNS = {
    -- Horde zeppelin towers
    { key = "zep:orgrimmar:undercity",   kind = "zeppelin", dest = "Undercity",  mapID = 1411, x = 50.8, y = 13.5, npc = 9564 },  -- Frezza
    { key = "zep:orgrimmar:gromgol",     kind = "zeppelin", dest = "Grom'gol",   mapID = 1411, x = 50.6, y = 12.8, npc = 12136 }, -- Snurk Bucksquick
    { key = "zep:undercity:orgrimmar",   kind = "zeppelin", dest = "Orgrimmar",  mapID = 1420, x = 60.8, y = 58.8, npc = 9566 },  -- Zapetta
    { key = "zep:undercity:gromgol",     kind = "zeppelin", dest = "Grom'gol",   mapID = 1420, x = 61.8, y = 59.0, npc = 3150 },  -- Hin Denburg
    { key = "zep:gromgol:orgrimmar",     kind = "zeppelin", dest = "Orgrimmar",  mapID = 1434, x = 31.4, y = 29.8, npc = 3149 },  -- Nez'raz
    { key = "zep:gromgol:undercity",     kind = "zeppelin", dest = "Undercity",  mapID = 1434, x = 31.5, y = 29.4, npc = 12137 }, -- Squibby Overspeck
    -- Forever's skyships
    { key = "zep:skywatcher:valanaar",   kind = "zeppelin", dest = "Valanaar",      mapID = 1412, x = 34.3, y = 26.1 },
    { key = "zep:valanaar:thunderbluff", kind = "zeppelin", dest = "Thunder Bluff", mapID = 2521, x = 57.7, y = 81.0 },
    { key = "zep:valanaar:dalaran",      kind = "zeppelin", dest = "Dalaran",       mapID = 2521, x = 65.8, y = 83.8 },
    { key = "zep:dalaran:valanaar",      kind = "zeppelin", dest = "Valanaar",      mapID = 1416, x = 12.8, y = 51.2 },
    -- Ships
    { key = "ship:ratchet:bootybay",       kind = "ship", dest = "Booty Bay",          mapID = 1413, x = 63.8, y = 38.8, npc = 9558 },   -- Grimble
    { key = "ship:bootybay:ratchet",       kind = "ship", dest = "Ratchet",            mapID = 1434, x = 25.7, y = 73.1, npc = 9559 },   -- Grizzlowe
    { key = "ship:theramore:menethil",     kind = "ship", dest = "Menethil Harbor",    mapID = 1445, x = 71.7, y = 56.7 },
    { key = "ship:menethil:theramore",     kind = "ship", dest = "Theramore Isle",     mapID = 1437, x = 4.7,  y = 63.8 },
    { key = "ship:menethil:southshore",    kind = "ship", dest = "Southshore",         mapID = 1437, x = 4.5,  y = 56.7 },
    { key = "ship:southshore:auberdine",   kind = "ship", dest = "Auberdine",          mapID = 1424, x = 50.7, y = 70.4, npc = 276316 }, -- Raul Sweete
    { key = "ship:ruttheran:auberdine",    kind = "ship", dest = "Auberdine",          mapID = 1438, x = 54.8, y = 97.2 },
    { key = "ship:auberdine:ruttheran",    kind = "ship", dest = "Rut'theran Village", mapID = 1439, x = 33.3, y = 39.8 },
    { key = "ship:auberdine:menethil",     kind = "ship", dest = "Menethil Harbor",    mapID = 1439, x = 32.3, y = 44.1 },
    { key = "ship:auberdine:stormwind",    kind = "ship", dest = "Stormwind Harbor",   mapID = 1439, x = 30.5, y = 40.9 },
    { key = "ship:stormwind:auberdine",    kind = "ship", dest = "Auberdine",          mapID = 1453, x = 21.8, y = 56.9 },
    { key = "ship:steamwheedle:powderfuse", kind = "ship", dest = "Powderfuse Port",   mapID = 1446, x = 68.6, y = 23.0 },
    { key = "ship:powderfuse:gadgetzan",   kind = "ship", dest = "Gadgetzan",          mapID = 2548, x = 80.6, y = 54.6 },
    -- Wowhead only marks one end of this ferry; add the other with /zep mark new.
    { key = "ship:feathermoon",            kind = "ship", dest = "Feathermoon Ferry",  mapID = 1444, x = 31.0, y = 39.5 },
}

local LIVE_UNITS = { "mouseover", "softinteract", "softfriend", "target" }

local spots = {}     -- { sign, continent, wx, wy }, rebuilt by BuildSpots()
local signByNpc = {} -- NPC ID -> sign
local testUntil = 0

local function Print(msg)
    print("|cff33ff99Zeppelin Signs|r " .. msg)
end

local function Label(sign)
    return KIND_LABEL[sign.kind] .. ": " .. sign.dest
end

local function WorldPos(mapID, x, y)
    if not mapID or not x then return end
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not continent or not pos then return end
    return continent, pos.x, pos.y
end

local function PlayerWorldPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local continent, wx, wy = WorldPos(mapID, pos.x, pos.y)
    return continent, wx, wy, mapID, pos.x, pos.y
end

local function AddSpot(sign, mapID, x, y)
    local continent, wx, wy = WorldPos(mapID, x, y)
    if continent then
        spots[#spots + 1] = { sign = sign, continent = continent, wx = wx, wy = wy }
    end
end

-- Built-in signs (at their moved spot if /zep mark moved them) plus custom ones.
-- Custom signs store map fractions (0-1), built-in ones zone %.
local function BuildSpots()
    wipe(spots)
    wipe(signByNpc)
    for _, s in ipairs(SIGNS) do
        local m = ZeppelinSignsDB.moved[s.key]
        if m then
            AddSpot(s, m.mapID, m.x, m.y)
        else
            AddSpot(s, s.mapID, s.x / 100, s.y / 100)
        end
        if s.npc then signByNpc[s.npc] = s end
    end
    for _, s in ipairs(ZeppelinSignsDB.custom) do
        AddSpot(s, s.mapID, s.x, s.y)
        if s.npc then signByNpc[s.npc] = s end
    end
end

-- Nearest spot to the player whose sign passes range(sign) (a radius in yards, or nil to skip it).
local function NearestSpot(range)
    local continent, px, py = PlayerWorldPos()
    if not continent then return end
    local best, bestDist
    for _, spot in ipairs(spots) do
        local r = spot.continent == continent and range(spot.sign)
        if r then
            local dx, dy = spot.wx - px, spot.wy - py
            local d = dx * dx + dy * dy
            if d <= r * r and (not bestDist or d < bestDist) then
                best, bestDist = spot, d
            end
        end
    end
    return best
end

local function NpcID(unit)
    local guid = UnitGUID(unit)
    if not guid or (issecretvalue and issecretvalue(guid)) then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" then return end
    return tonumber(id)
end

-- Sign of a master you're looking at / mousing over right now, if any.
local function LiveSign()
    for _, unit in ipairs(LIVE_UNITS) do
        local id = UnitExists(unit) and NpcID(unit)
        if id and signByNpc[id] then return signByNpc[id] end
    end
end

local function NearbySign()
    local spot = NearestSpot(function(sign) return Z.RADIUS[sign.kind] end)
    return spot and spot.sign
end

local sign = CreateFrame("Frame", nil, UIParent)
sign:SetSize(1, 1)
sign:SetPoint("TOP", UIParent, "TOP", 0, -110)
sign:SetFrameStrata("HIGH")
sign:EnableMouse(false)
sign.text = sign:CreateFontString(nil, "OVERLAY")
sign.text:SetFont(STANDARD_TEXT_FONT, 28, "OUTLINE")
sign.text:SetTextColor(1, 1, 1)
sign.text:SetPoint("TOP")
sign:Hide()

local function ShowText(text)
    if text then
        sign.text:SetText(text)
        sign:Show()
    else
        sign:Hide()
    end
end

function Z.Update()
    if GetTime() < testUntil then return end
    if not ZeppelinSignsDB or not ZeppelinSignsDB.enabled then
        sign:Hide()
        return
    end
    local s = LiveSign() or NearbySign()
    ShowText(s and Label(s))
end

-- /zep mark: move the nearest sign to where you stand.
local function MarkNearest()
    local _, _, _, mapID, x, y = PlayerWorldPos()
    if not mapID then
        Print("Can't read your position here.")
        return
    end
    local spot = NearestSpot(function() return Z.MARK_RANGE end)
    if not spot then
        Print("No sign within " .. Z.MARK_RANGE .. " yards. Use /zep mark new to add one.")
        return
    end
    local s = spot.sign
    if s.custom then
        s.mapID, s.x, s.y = mapID, x, y
    else
        ZeppelinSignsDB.moved[s.key] = { mapID = mapID, x = x, y = y }
    end
    BuildSpots()
    Print("Moved the " .. Label(s) .. " sign here.")
end

-- /zep remove: delete the nearest custom sign, or put a moved built-in sign back.
local function RemoveNearest()
    local spot = NearestSpot(function(s)
        if s.custom or ZeppelinSignsDB.moved[s.key] then return Z.MARK_RANGE end
    end)
    if not spot then
        Print("No custom or moved sign within " .. Z.MARK_RANGE .. " yards.")
        return
    end
    local s = spot.sign
    if s.custom then
        tDeleteItem(ZeppelinSignsDB.custom, s)
        Print("Removed the " .. Label(s) .. " sign.")
    else
        ZeppelinSignsDB.moved[s.key] = nil
        Print("Put the " .. Label(s) .. " sign back in its default spot.")
    end
    BuildSpots()
end

local function AddCustom(kind, dest, npc)
    local _, _, _, mapID, x, y = PlayerWorldPos()
    if not mapID then
        Print("Can't read your position here.")
        return false
    end
    local custom = ZeppelinSignsDB.custom
    local s = { key = ("custom:%d:%d"):format(time(), #custom + 1), custom = true,
                kind = kind, dest = dest, mapID = mapID, x = x, y = y, npc = npc }
    custom[#custom + 1] = s
    BuildSpots()
    Print("Added a " .. Label(s) .. " sign" .. (npc and " on your target." or " here."))
    return true
end

-- /zep mark new popup: Ship or Zeppelin, destination, then location or target NPC.
local popup
local function ShowMarkPopup()
    if popup then
        popup:Show()
        return
    end
    local f = CreateFrame("Frame", "ZeppelinSignsMarkFrame", UIParent, "BasicFrameTemplateWithInset")
    popup = f
    f:SetSize(300, 160)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "ZeppelinSignsMarkFrame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("New Sign")

    f.kind = "ship"
    local radios = {}
    local function Radio(kind, xOff)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", xOff, -34)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        label:SetText(KIND_LABEL[kind])
        cb:SetScript("OnClick", function()
            f.kind = kind
            for k, other in pairs(radios) do other:SetChecked(k == kind) end
        end)
        radios[kind] = cb
    end
    Radio("ship", 20)
    Radio("zeppelin", 140)
    radios.ship:SetChecked(true)

    local destLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    destLabel:SetPoint("TOPLEFT", 22, -70)
    destLabel:SetText("Destination:")
    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(160, 20)
    edit:SetPoint("LEFT", destLabel, "RIGHT", 10, 0)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEnterPressed", edit.ClearFocus)
    f.edit = edit

    local function Save(useTarget)
        local dest = strtrim(edit:GetText() or "")
        if dest == "" then
            Print("Type a destination first.")
            return
        end
        local npc
        if useTarget then
            npc = UnitExists("target") and NpcID("target")
            if not npc then
                Print("Target the NPC first.")
                return
            end
        end
        if AddCustom(f.kind, dest, npc) then
            edit:SetText("")
            f:Hide()
        end
    end

    local here = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    here:SetSize(125, 24)
    here:SetPoint("BOTTOMLEFT", 16, 16)
    here:SetText("Use my location")
    here:SetScript("OnClick", function() Save(false) end)

    local target = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    target:SetSize(125, 24)
    target:SetPoint("BOTTOMRIGHT", -16, 16)
    target:SetText("Use target NPC")
    target:SetScript("OnClick", function() Save(true) end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ZeppelinSignsDB = ZeppelinSignsDB or {}
        if ZeppelinSignsDB.enabled == nil then ZeppelinSignsDB.enabled = true end
        ZeppelinSignsDB.moved = ZeppelinSignsDB.moved or {}
        ZeppelinSignsDB.custom = ZeppelinSignsDB.custom or {}
        ZeppelinSignsDB.learned = nil -- 1.0.0's guessed Gaznik Gearsnaps spot
        BuildSpots()
        C_Timer.NewTicker(Z.TICK, Z.Update)
        for _, e in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED",
                             "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED" }) do
            pcall(events.RegisterEvent, events, e)
        end
    end
    Z.Update()
end)

SLASH_ZEPPELINSIGNS1 = "/zep"
SlashCmdList.ZEPPELINSIGNS = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "test" then
        testUntil = GetTime() + 5
        ShowText("Zeppelin: Undercity")
        C_Timer.After(5, Z.Update)
    elseif msg == "mark" then
        MarkNearest()
    elseif msg == "mark new" then
        ShowMarkPopup()
    elseif msg == "remove" then
        RemoveNearest()
    elseif msg == "" then
        ZeppelinSignsDB.enabled = not ZeppelinSignsDB.enabled
        Print(ZeppelinSignsDB.enabled and "on." or "off.")
    else
        Print("commands:")
        print("  /zep - turn signs on/off")
        print("  /zep test - show a sample sign")
        print("  /zep mark - move the nearest sign to where you stand")
        print("  /zep mark new - add a new ship or zeppelin sign")
        print("  /zep remove - delete the nearest added sign, or reset a moved one")
    end
    Z.Update()
end
