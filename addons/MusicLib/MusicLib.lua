-- MusicLib: custom wand sound + zone music demo
-- Audio files must exist when the game starts; /reload won't pick up new ones.

local _, ns = ... -- ns:On (events): the shared Core.lua (addons/shared)
local ADDON = "MusicLib"
local PATH = "Interface\\AddOns\\" .. ADDON .. "\\"

-- Wand ------------------------------------------------------------------------

local WAND_SHOOT = 5019
local WAND_SOUND = PATH .. "sounds\\wand.ogg"

-- Stock wand sound FileDataIDs to mute. Look them up on wago.tools
-- (search the files for "wand"), one per wand element you care about.
local MUTED_WAND_SOUNDS = {
    -- 123456,
}

-- Zone music ------------------------------------------------------------------

-- Keys are zone or subzone names exactly as shown on the minimap.
-- Subzone matches win over zone matches.
-- File names are the zone name in lowercase, spaces -> underscores, no apostrophes.
local ZONE_MUSIC = {
    -- Eastern Kingdoms
    ["Alterac Mountains"]     = PATH .. "music\\alterac_mountains.mp3",
    ["Arathi Highlands"]      = PATH .. "music\\arathi_highlands.mp3",
    ["Badlands"]              = PATH .. "music\\badlands.mp3",
    ["Blasted Lands"]         = PATH .. "music\\blasted_lands.mp3",
    ["Burning Steppes"]       = PATH .. "music\\burning_steppes.mp3",
    ["Deadwind Pass"]         = PATH .. "music\\deadwind_pass.mp3",
    ["Dun Morogh"]            = PATH .. "music\\dun_morogh.mp3",
    ["Duskwood"]              = PATH .. "music\\duskwood.mp3",
    ["Eastern Plaguelands"]   = PATH .. "music\\eastern_plaguelands.mp3",
    ["Elwynn Forest"]         = PATH .. "music\\elwynn_forest.mp3",
    ["Hillsbrad Foothills"]   = PATH .. "music\\hillsbrad_foothills.mp3",
    ["Loch Modan"]            = PATH .. "music\\loch_modan.mp3",
    ["Redridge Mountains"]    = PATH .. "music\\redridge_mountains.mp3",
    ["Searing Gorge"]         = PATH .. "music\\searing_gorge.mp3",
    ["Silverpine Forest"]     = PATH .. "music\\silverpine_forest.mp3",
    ["Stranglethorn Vale"]    = PATH .. "music\\stranglethorn_vale.mp3",
    ["Swamp of Sorrows"]      = PATH .. "music\\swamp_of_sorrows.mp3",
    ["The Hinterlands"]       = PATH .. "music\\the_hinterlands.mp3",
    ["Tirisfal Glades"]       = PATH .. "music\\tirisfal_glades.mp3",
    ["Western Plaguelands"]   = PATH .. "music\\western_plaguelands.mp3",
    ["Westfall"]              = PATH .. "music\\westfall.mp3",
    ["Wetlands"]              = PATH .. "music\\wetlands.mp3",

    -- Kalimdor
    ["Ashenvale"]             = PATH .. "music\\ashenvale.mp3",
    ["Azshara"]               = PATH .. "music\\azshara.mp3",
    ["Darkshore"]             = PATH .. "music\\darkshore.mp3",
    ["Desolace"]              = PATH .. "music\\desolace.mp3",
    ["Durotar"]               = PATH .. "music\\durotar.mp3",
    ["Dustwallow Marsh"]      = PATH .. "music\\dustwallow_marsh.mp3",
    ["Felwood"]               = PATH .. "music\\felwood.mp3",
    ["Feralas"]               = PATH .. "music\\feralas.mp3",
    ["Moonglade"]             = PATH .. "music\\moonglade.mp3",
    ["Mulgore"]               = PATH .. "music\\mulgore.mp3",
    ["Silithus"]              = PATH .. "music\\silithus.mp3",
    ["Stonetalon Mountains"]  = PATH .. "music\\stonetalon_mountains.mp3",
    ["Tanaris"]               = PATH .. "music\\tanaris.mp3",
    ["Teldrassil"]            = PATH .. "music\\teldrassil.mp3",
    ["The Barrens"]           = PATH .. "music\\the_barrens.mp3",
    ["Thousand Needles"]      = PATH .. "music\\thousand_needles.mp3",
    ["Un'Goro Crater"]        = PATH .. "music\\ungoro_crater.mp3",
    ["Winterspring"]          = PATH .. "music\\winterspring.mp3",

    -- Cities
    ["Darnassus"]             = PATH .. "music\\darnassus.mp3",
    ["Deeprun Tram"]          = PATH .. "music\\deeprun_tram.mp3",
    ["Ironforge"]             = PATH .. "music\\ironforge.mp3",
    ["Orgrimmar"]             = PATH .. "music\\orgrimmar.mp3",
    ["Stormwind City"]        = PATH .. "music\\stormwind_city.mp3",
    ["Thunder Bluff"]         = PATH .. "music\\thunder_bluff.mp3",
    ["Undercity"]             = PATH .. "music\\undercity.mp3",

    -- Dungeons
    ["Blackfathom Deeps"]     = PATH .. "music\\blackfathom_deeps.mp3",
    ["Blackrock Depths"]      = PATH .. "music\\blackrock_depths.mp3",
    ["Blackrock Spire"]       = PATH .. "music\\blackrock_spire.mp3",
    ["Dire Maul"]             = PATH .. "music\\dire_maul.mp3",
    ["Gnomeregan"]            = PATH .. "music\\gnomeregan.mp3",
    ["Maraudon"]              = PATH .. "music\\maraudon.mp3",
    ["Ragefire Chasm"]        = PATH .. "music\\ragefire_chasm.mp3",
    ["Razorfen Downs"]        = PATH .. "music\\razorfen_downs.mp3",
    ["Razorfen Kraul"]        = PATH .. "music\\razorfen_kraul.mp3",
    ["Scarlet Monastery"]     = PATH .. "music\\scarlet_monastery.mp3",
    ["Scholomance"]           = PATH .. "music\\scholomance.mp3",
    ["Shadowfang Keep"]       = PATH .. "music\\shadowfang_keep.mp3",
    ["Stratholme"]            = PATH .. "music\\stratholme.mp3",
    ["The Deadmines"]         = PATH .. "music\\the_deadmines.mp3",
    ["The Stockade"]          = PATH .. "music\\the_stockade.mp3",
    ["The Temple of Atal'Hakkar"] = PATH .. "music\\the_temple_of_atalhakkar.mp3",
    ["Uldaman"]               = PATH .. "music\\uldaman.mp3",
    ["Wailing Caverns"]       = PATH .. "music\\wailing_caverns.mp3",
    ["Zul'Farrak"]            = PATH .. "music\\zulfarrak.mp3",

    -- Raids
    ["Ahn'Qiraj"]             = PATH .. "music\\ahnqiraj.mp3",
    ["Blackwing Lair"]        = PATH .. "music\\blackwing_lair.mp3",
    ["Molten Core"]           = PATH .. "music\\molten_core.mp3",
    ["Naxxramas"]             = PATH .. "music\\naxxramas.mp3",
    ["Onyxia's Lair"]         = PATH .. "music\\onyxias_lair.mp3",
    ["Ruins of Ahn'Qiraj"]    = PATH .. "music\\ruins_of_ahnqiraj.mp3",
    ["Zul'Gurub"]             = PATH .. "music\\zulgurub.mp3",

    -- Battlegrounds
    ["Alterac Valley"]        = PATH .. "music\\alterac_valley.mp3",
    ["Arathi Basin"]          = PATH .. "music\\arathi_basin.mp3",
    ["Warsong Gulch"]         = PATH .. "music\\warsong_gulch.mp3",
}

local currentTrack

-- PlayMusic gives no feedback, so probe the file with PlaySoundFile (which
-- reports whether it will play) and stop the probe immediately.
local function TrackExists(track)
    local willPlay, handle = PlaySoundFile(track, "Music")
    if handle then StopSound(handle) end
    return willPlay
end

local function UpdateMusic()
    local zone = GetSubZoneText()
    if not ZONE_MUSIC[zone] then zone = GetZoneText() end
    local track = ZONE_MUSIC[zone]
    if track == currentTrack then return end
    currentTrack = track
    -- Always end the previous zone's track first; this hands control back to
    -- the default zone music. PlayMusic silently does nothing if the file is
    -- missing, so without this the old track would keep playing.
    StopMusic()
    if track then
        PlayMusic(track)
        if TrackExists(track) then
            print(ADDON .. ": Playing " .. zone .. " Theme Song")
        end
    end
end

-- Events ----------------------------------------------------------------------

ns:On("PLAYER_LOGIN", function()
    for _, id in ipairs(MUTED_WAND_SOUNDS) do
        MuteSoundFile(id)
    end
end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    if spellID == WAND_SHOOT then
        PlaySoundFile(WAND_SOUND, "SFX")
    end
end)
-- Only the player's casts.
if ns.EventFrame.RegisterUnitEvent then ns.EventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
    ns:On(event, UpdateMusic)
end

-- Slash commands for testing --------------------------------------------------

SLASH_MUSICLIB1 = "/musiclib"
SlashCmdList.MUSICLIB = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "wand" then
        local ok = PlaySoundFile(WAND_SOUND, "SFX")
        print(ADDON .. ": wand sound " .. (ok and "played" or "not found"))
    elseif msg == "zone" then
        print(ADDON .. ": zone '" .. GetZoneText() .. "', subzone '" .. GetSubZoneText()
            .. "', track: " .. tostring(currentTrack))
    elseif msg == "stop" then
        currentTrack = nil
        StopMusic()
    else
        print(ADDON .. ": /musiclib wand | zone | stop")
    end
end
