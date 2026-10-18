local _, ns = ...

-- Pictures for the instance tiles, from the game's own files only: the
-- Dungeon Finder backgrounds where the game has one for the place, else a
-- tinted generic card with the first boss's portrait on it.
local Art = {}
ns.Art = Art

local LFG = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-"
local GENERIC = LFG .. "RANDOMDUNGEON"

-- AtlasLoot instance key -> Dungeon Finder picture names to try, in order.
local KEY_TO_LFG = {
    Ragefire = { "RAGEFIRECHASM" },
    WailingCaverns = { "WAILINGCAVERNS" },
    TheDeadmines = { "DEADMINES" },
    ShadowfangKeep = { "SHADOWFANGKEEP" },
    BlackfathomDeeps = { "BLACKFATHOMDEEPS" },
    TheStockade = { "STORMWINDSTOCKADES", "STOCKADES" },
    Gnomeregan = { "GNOMEREGAN" },
    RazorfenKraul = { "RAZORFENKRAUL" },
    ScarletMonasteryGraveyard = { "SCARLETMONASTERYGRAVEYARD", "SCARLETMONASTERY" },
    ScarletMonasteryLibrary = { "SCARLETMONASTERYLIBRARY", "SCARLETMONASTERY" },
    ScarletMonasteryArmory = { "SCARLETMONASTERYARMORY", "SCARLETMONASTERY" },
    ScarletMonasteryCathedral = { "SCARLETMONASTERYCATHEDRAL", "SCARLETMONASTERY" },
    RazorfenDowns = { "RAZORFENDOWNS" },
    Uldaman = { "ULDAMAN" },
    ["Zul'Farrak"] = { "ZULFARAK", "ZULFARRAK" },
    Maraudon = { "MARAUDON" },
    ["TheTempleOfAtal'Hakkar"] = { "SUNKENTEMPLE", "TEMPLEOFATALHAKKAR" },
    BlackrockDepths = { "BLACKROCKDEPTHS" },
    LowerBlackrockSpire = { "LOWERBLACKROCKSPIRE", "BLACKROCKSPIRE" },
    UpperBlackrockSpire = { "UPPERBLACKROCKSPIRE", "BLACKROCKSPIRE" },
    DireMaulEast = { "DIREMAULEAST", "DIREMAUL" },
    DireMaulWest = { "DIREMAULWEST", "DIREMAUL" },
    DireMaulNorth = { "DIREMAULNORTH", "DIREMAUL" },
    Scholomance = { "SCHOLOMANCE" },
    Stratholme = { "STRATHOLME" },
    MoltenCore = { "MOLTENCORE" },
    Onyxia = { "ONYXIASLAIR", "ONYXIA" },
    BlackwingLair = { "BLACKWINGLAIR" },
    ["Zul'Gurub"] = { "ZULGURUB" },
    TheRuinsofAhnQiraj = { "AHNQIRAJRUINS", "RUINSOFAHNQIRAJ", "AQRUINS" },
    TheTempleofAhnQiraj = { "AHNQIRAJTEMPLE", "TEMPLEOFAHNQIRAJ", "AQTEMPLE" },
    Naxxramas = { "NAXXRAMAS" },
}

-- Split places with no Dungeon Finder picture of their own in this client
-- (it has one for the whole place, or none): the shipped view goes first.
local SHIPPED_FIRST = {
    ScarletMonasteryGraveyard = true, ScarletMonasteryLibrary = true,
    ScarletMonasteryArmory = true, ScarletMonasteryCathedral = true,
    DireMaulEast = true, DireMaulWest = true, DireMaulNorth = true,
    LowerBlackrockSpire = true, UpperBlackrockSpire = true,
    Onyxia = true, TheTempleofAhnQiraj = true, TheRuinsofAhnQiraj = true,
}

-- A gentle hue per instance so generic cards don't all look alike. The
-- server's own instances lean blue-violet, the rest warm.
local function Hue(inst)
    local n = 0
    for i = 1, #inst.key do n = (n * 31 + inst.key:byte(i)) % 997 end
    local t = (n % 100) / 100
    if inst.isCustom then
        return 0.45 + 0.25 * t, 0.5 + 0.2 * (1 - t), 0.95
    end
    return 0.95, 0.65 + 0.25 * t, 0.45 + 0.2 * (1 - t)
end

local cache = {} -- [key] = { texture, generic, r, g, b, displayID, map }

-- World places are zones: their picture is the zone's own world map art
-- (the game's files, through C_Map), or, for a dungeon's name, its Dungeon
-- Finder picture. Map IDs by name, over every map under Azeroth.
local mapByName
local function MapIDByName(name)
    if not mapByName then
        mapByName = {}
        for _, root in ipairs({ 947, 946 }) do
            local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
            for _, info in ipairs(ok and children or {}) do
                if info.name and not mapByName[info.name] then mapByName[info.name] = info.mapID end
            end
        end
    end
    return mapByName[name]
end

-- The map's art: { textures = { fileID, ... }, cols, rows, tileW, tileH,
-- width, height } (the art comes in tiles, left to right, top to bottom).
local function MapArt(mapID)
    if not (mapID and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
    local ok, layers = pcall(C_Map.GetMapArtLayers, mapID)
    local layer = ok and layers and layers[1]
    if not layer then return nil end
    local okTex, textures = pcall(C_Map.GetMapArtLayerTextures, mapID, 1)
    if not (okTex and textures and #textures > 0) then return nil end
    return {
        textures = textures, tileW = layer.tileWidth, tileH = layer.tileHeight,
        width = layer.layerWidth, height = layer.layerHeight,
        cols = math.ceil(layer.layerWidth / layer.tileWidth), rows = math.ceil(layer.layerHeight / layer.tileHeight),
    }
end

-- A Dungeon Finder picture for an instance known by name ("Gnomeregan").
local function LFGByName(name, probe)
    local key = name and name:gsub("[%s']", ""):lower()
    for instKey, names in pairs(KEY_TO_LFG) do
        if instKey:gsub("[%s']", ""):lower() == key then
            for _, file in ipairs(names) do
                if probe:SetTexture(LFG .. file) then return LFG .. file end
            end
        end
    end
end

-- What to draw on an instance's tile:
-- { texture, generic = bool, r, g, b, displayID }. probe is any texture
-- region, used to test whether a picture exists (SetTexture answers false
-- when it doesn't).
function Art:For(inst, probe)
    local art = cache[inst.key]
    if art then return art end
    if inst.journalOnly and inst.kind == "world" then
        local lfg = LFGByName(inst.name, probe)
        local shipped = ns.ZoneArt and ns.ZoneArt[inst.name]
        if lfg then
            art = { texture = lfg, r = 1, g = 1, b = 1 }
        elseif shipped then
            -- A scenic view of the zone (or its revealed map), shipped in
            -- Media\Zones (tools/Spyglass/fetch_zone_art.py). Already the tile's shape.
            art = { texture = "Interface\\AddOns\\Spyglass\\Media\\Zones\\" .. shipped .. ".tga", r = 1, g = 1, b = 1,
                fit = true }
        else
            local map = MapArt(MapIDByName(inst.name) or 947) -- "The world": Azeroth
            if map then art = { map = map, r = 1, g = 1, b = 1 } end
        end
        if art then
            cache[inst.key] = art
            return art
        end
    end
    -- A shipped scenic view (tools/Spyglass/fetch_zone_art.py) for the places this
    -- client has no Dungeon Finder picture for. SetTexture can't tell: it
    -- answers true for a missing file too and draws nothing, so those places
    -- are listed (SHIPPED_FIRST) rather than probed.
    local shipped = ns.InstanceArt and ns.InstanceArt[inst.key]
    if shipped and SHIPPED_FIRST[inst.key] then
        art = { texture = "Interface\\AddOns\\Spyglass\\Media\\Zones\\" .. shipped .. ".tga", r = 1, g = 1, b = 1, fit = true }
    end
    for _, name in ipairs(not art and KEY_TO_LFG[inst.key] or {}) do
        if probe:SetTexture(LFG .. name) then
            art = { texture = LFG .. name, r = 1, g = 1, b = 1 }
            break
        end
    end
    if not art and shipped then
        art = { texture = "Interface\\AddOns\\Spyglass\\Media\\Zones\\" .. shipped .. ".tga", r = 1, g = 1, b = 1, fit = true }
    end
    if not art then
        local r, g, b = Hue(inst)
        local displayID
        for _, boss in ipairs(inst.bosses) do
            if boss.displayID then displayID = boss.displayID break end
        end
        art = { texture = GENERIC, generic = true, r = r, g = g, b = b, displayID = displayID }
    end
    cache[inst.key] = art
    return art
end
