local _, ns = ...

-- Boats, zeppelins and skyships, for the route planner (Route.lua). The docks are ZeppelinSigns'
-- built-in signs (addons\ZeppelinSigns\ZeppelinSigns.lua, SIGNS), copied with the same keys, so
-- signs you move or add with /zep mark move these docks too. Positions are zone % on uiMapID.
--   place    the town the dock is in; a ride lands at a dock whose place is its dest
--   dest     where the ride goes
--   faction  "A" or "H" when only that faction can safely use it (zeppelins, Alliance ports)
--   town     where to assume it lands (an ns.Towns name) when no dock is at dest, until you've
--            ridden it once and Waypoint knows the real spot
ns.Transports = {
    -- Horde zeppelin towers
    { key = "zep:orgrimmar:undercity",   kind = "zeppelin", place = "Orgrimmar", dest = "Undercity",  mapID = 1411, x = 50.8, y = 13.5, npc = 9564, faction = "H" },  -- Frezza
    { key = "zep:orgrimmar:gromgol",     kind = "zeppelin", place = "Orgrimmar", dest = "Grom'gol",   mapID = 1411, x = 50.6, y = 12.8, npc = 12136, faction = "H" }, -- Snurk Bucksquick
    { key = "zep:undercity:orgrimmar",   kind = "zeppelin", place = "Undercity", dest = "Orgrimmar",  mapID = 1420, x = 60.8, y = 58.8, npc = 9566, faction = "H" },  -- Zapetta
    { key = "zep:undercity:gromgol",     kind = "zeppelin", place = "Undercity", dest = "Grom'gol",   mapID = 1420, x = 61.8, y = 59.0, npc = 3150, faction = "H" },  -- Hin Denburg
    { key = "zep:gromgol:orgrimmar",     kind = "zeppelin", place = "Grom'gol",  dest = "Orgrimmar",  mapID = 1434, x = 31.4, y = 29.8, npc = 3149, faction = "H" },  -- Nez'raz
    { key = "zep:gromgol:undercity",     kind = "zeppelin", place = "Grom'gol",  dest = "Undercity",  mapID = 1434, x = 31.5, y = 29.4, npc = 12137, faction = "H" }, -- Squibby Overspeck
    -- Forever's skyships
    { key = "zep:skywatcher:valanaar",   kind = "skyship", place = "Skywatcher", dest = "Valanaar",      mapID = 1412, x = 34.3, y = 26.1 },
    { key = "zep:valanaar:thunderbluff", kind = "skyship", place = "Valanaar",   dest = "Thunder Bluff", mapID = 2521, x = 57.7, y = 81.0, faction = "H", town = "Thunder Bluff" },
    { key = "zep:valanaar:dalaran",      kind = "skyship", place = "Valanaar",   dest = "Dalaran",       mapID = 2521, x = 65.8, y = 83.8 },
    { key = "zep:dalaran:valanaar",      kind = "skyship", place = "Dalaran",    dest = "Valanaar",      mapID = 1416, x = 12.8, y = 51.2 },
    -- Ships
    { key = "ship:ratchet:bootybay",        kind = "ship", place = "Ratchet",            dest = "Booty Bay",          mapID = 1413, x = 63.8, y = 38.8, npc = 9558 }, -- Grimble
    { key = "ship:bootybay:ratchet",        kind = "ship", place = "Booty Bay",          dest = "Ratchet",            mapID = 1434, x = 25.7, y = 73.1, npc = 9559 }, -- Grizzlowe
    { key = "ship:theramore:menethil",      kind = "ship", place = "Theramore Isle",     dest = "Menethil Harbor",    mapID = 1445, x = 71.7, y = 56.7, faction = "A" },
    { key = "ship:menethil:theramore",      kind = "ship", place = "Menethil Harbor",    dest = "Theramore Isle",     mapID = 1437, x = 4.7,  y = 63.8, faction = "A" },
    { key = "ship:menethil:southshore",     kind = "ship", place = "Menethil Harbor",    dest = "Southshore",         mapID = 1437, x = 4.5,  y = 56.7, faction = "A" },
    { key = "ship:southshore:auberdine",    kind = "ship", place = "Southshore",         dest = "Auberdine",          mapID = 1424, x = 50.7, y = 70.4, npc = 276316, faction = "A" }, -- Raul Sweete
    { key = "ship:ruttheran:auberdine",     kind = "ship", place = "Rut'theran Village", dest = "Auberdine",          mapID = 1438, x = 54.8, y = 97.2, faction = "A" },
    { key = "ship:auberdine:ruttheran",     kind = "ship", place = "Auberdine",          dest = "Rut'theran Village", mapID = 1439, x = 33.3, y = 39.8, faction = "A" },
    { key = "ship:auberdine:menethil",      kind = "ship", place = "Auberdine",          dest = "Menethil Harbor",    mapID = 1439, x = 32.3, y = 44.1, faction = "A" },
    { key = "ship:auberdine:stormwind",     kind = "ship", place = "Auberdine",          dest = "Stormwind Harbor",   mapID = 1439, x = 30.5, y = 40.9, faction = "A" },
    { key = "ship:stormwind:auberdine",     kind = "ship", place = "Stormwind Harbor",   dest = "Auberdine",          mapID = 1453, x = 21.8, y = 56.9, faction = "A" },
    { key = "ship:steamwheedle:powderfuse", kind = "ship", place = "Steamwheedle Port",  dest = "Powderfuse Port",    mapID = 1446, x = 68.6, y = 23.0 },
    { key = "ship:powderfuse:gadgetzan",    kind = "ship", place = "Powderfuse Port",    dest = "Gadgetzan",          mapID = 2548, x = 80.6, y = 54.6, town = "Gadgetzan" },
    -- The Feathermoon ferry: Sardor Isle and the Forgotten Coast, both in Feralas.
    { key = "ship:feathermoon:forgottencoast", kind = "ship", place = "Feathermoon Stronghold", dest = "The Forgotten Coast",    mapID = 1444, x = 31.0, y = 39.5, faction = "A" },
    { key = "ship:forgottencoast:feathermoon", kind = "ship", place = "The Forgotten Coast",    dest = "Feathermoon Stronghold", mapID = 1444, x = 44.0, y = 43.0, faction = "A" },
}

-- How close (yards) counts as standing at a dock: ZeppelinSigns' radii (the two Grom'gol
-- platforms are only ~17 yards apart).
ns.Transports.RADIUS = { zeppelin = 15, skyship = 15, ship = 60 }

-- Mage teleports: spell ID -> the city (an ns.Towns name), where to assume it lands until you've
-- cast it once. Spells the client doesn't have are simply never known.
ns.Transports.TELEPORTS = {
    [3561] = "Stormwind City", [3562] = "Ironforge", [3565] = "Darnassus",
    [3567] = "Orgrimmar", [3563] = "Undercity", [3566] = "Thunder Bluff",
    [32271] = "Exodar", [32272] = "Silvermoon City", [33690] = "Shattrath City", [35715] = "Shattrath City",
    [49359] = "Theramore Isle", [49358] = "Stonard", [53140] = "Dalaran",
}
