
-------------------------------------------------------------------------------
-- AddOn namespace.
-------------------------------------------------------------------------------
local FOLDER_NAME, private = ...

private.CONTINENT_ZONE_IDS = {
	[1414] = { zonefilter = true, npcfilter = true, showExplorer = true, id = 1, zones = {1411,1412,1413,1438,1439,1440,1441,1442,1443,1444,1445,1446,1447,1448,1449,1450,1451,1452,1454,1456,1457,2482} }; --Kalimdor
	[1415] = { zonefilter = true, npcfilter = true, showExplorer = true, id = 2, zones = {1416,1417,1418,1419,1420,1421,1422,1423,1424,1425,1426,1427,1428,1429,1430,1431,1432,1433,1434,1435,1436,1437,1453,1455,1458,2548} }; --Eastern Kingdoms
	[2521] = { zonefilter = true, npcfilter = true, showExplorer = true, id = 3, zones = {2521} }; --Zephras isles
	[9995] = { zonefilter = false, npcfilter = true, showExplorer = false, zones = {0} }; --Unknown
	[9997] = { zonefilter = true, npcfilter = true, showExplorer = true, zones = {100001,100002,100003,100004,100005,100006,100007,100008,100009,100010,100011,100012,100013,100014,100015,100016,100017,100018,100019,100020,100021,100022,100023,100024,100025,100026,100027,100028,100029,100030,100031,100032,100033,100034,100035,100036,100037,100039,100040,100041} }; --Dungeons or scenarios
}

private.SUBZONES_IDS = {

}

private.DUNGEONS_IDS = {
	[100001] = "The Deadmines";
	[100002] = "Wailing Caverns";
	[100003] = "Shadowfang Keep";
	[100004] = "Razorfen Kraul";
	[100005] = "The Temple of Atal'Hakkar";
	[100006] = "Gnomeregan";
	[100007] = "Scarlet Monastery - Graveyard";
	[100008] = "Blackrock Depths";
	[100009] = "Lower Blackrock Spire";
	[100010] = "Zul'Farrak";
	[100011] = "Stratholme - Main Gate";
	[100012] = "Upper Blackrock Spire";
	[100013] = "Dire Maul - East";
	[100014] = "Dire Maul - West";
	[100015] = "Maraudon";
	[100016] = "Ragefire Chasm";
	[100017] = "Naxxramas";
	[100018] = "Zul'Gurub";
	[100019] = "Molten Core";
	[100020] = "The Stockade";
	[100021] = "Blackfathom Deeps";
	[100022] = "Sunken Temple";
	[100023] = "Ruins of Lordaeron";
	[100024] = "The Hall of Thanes";
	[100025] = "Excavation Site: Wetlands";
	[100026] = "City of Dalaran";
	[100027] = "The Drowned City";
	[100028] = "Krol'dok Stronghold";
	[100029] = "Alcaz Prison";
	[100030] = "Blackmaw Hold";
	[100031] = "The Shaper's Terrace";
	[100032] = "Dire Maul - North";
	[100033] = "Scarlet Monastery - Armory";
	[100034] = "Scarlet Monastery - Cathedral";
	[100035] = "Scarlet Monastery - Library";
	[100036] = "Stratholme - Service Entrance";
	[100037] = "DEADMINES_ENTRANCE";
	[100039] = "WAILING_CAVERNS_ENTRANCE";
	[100040] = "SUNKEN_TEMPLE_ENTRANCE";
	[100041] = "BLACKROCK_DEPTHS_ENTRANCE";
}

private.ZONES_WITHOUT_VIGNETTE = {
	----[mapID] = { artID };
	[1425] = { 2162 }; --The Hinterlands
	[1418] = { 2159 }; --Badlands
	[1438] = { 2180 }; --Teldrassil
	[1453] = { 2146 }; --Stormwind City
	[1424] = { 2154 }; --Hillsbrad Foothills
	[1411] = { 2169 }; --Durotar
	[1420] = { 2126 }; --Tirisfal Glades
	[1417] = { 2147 }; --Arathi Highlands
	[1429] = { 2153 }; --Elwynn Forest
	[1451] = { 2177 }; --Silithus
	[1432] = { 2156 }; --Loch Modan
	[1423] = { 2134 }; --Eastern Plaguelands
	[1437] = { 2166 }; --Wetlands
	[1428] = { 2149 }; --Burning Steppes
	[1433] = { 2121 }; --Redridge Mountains
	[1427] = { 2157 }; --Searing Gorge
	[1446] = { 2179 }; --Tanaris
	[1436] = { 2165 }; --Westfall
	[1426] = { 2151 }; --Dun Morogh
	[1412] = { 1200 }; --Mulgore
	[1444] = { 2170 }; --Feralas
	[2482] = { 1997 }; --Mount Hyjal
	[1416] = { 2133 }; --Alterac Mountains
	[1440] = { 2167 }; --Ashenvale
	[1447] = { 2168 }; --Azshara
	[1419] = { 2148 }; --Blasted Lands
	[1457] = { 2172 }; --Darnassus
	[1439] = { 2171 }; --Darkshore
	[1443] = { 2130 }; --Desolace
	[1431] = { 2152 }; --Duskwood
	[1445] = { 2173 }; --Dustwallow Marsh
	[1455] = { 2155 }; --Ironforge
	[1450] = { 2175 }; --Moonglade
	[1454] = { 2176 }; --Orgrimmar
	[1421] = { 2158 }; --Silverpine Forest
	[1434] = { 2160 }; --Stranglethorn Vale
	[1435] = { 2161 }; --Swamp of Sorrows
	[1413] = { 2181 }; --The Barrens
	[1441] = { 2182 }; --Thousand Needles
	[1456] = { 2183 }; --Thunder Bluff
	[1449] = { 2184 }; --Un'Goro Crater
	[1422] = { 2164 }; --Western Plaguelands
	[2521] = { 2031 }; --Zephras Isle
	[2548] = { 2054 }; --Riverglades
	[1448] = { 2174 }; --Felwood
	[1442] = { 2178 }; --Stonetalon Mountains
	[1452] = { 2185 }; --Winterspring
	[1430] = { 2150 }; --Deadwind Pass
	[1458] = { 2163 }; --Undercity
}

private.RESETABLE_KILLS_ZONE_IDS = {
	----[mapID] = { artID or "all"};
}

private.PERMANENT_KILLS_ZONE_IDS = {

}

-- Relation between mapIDs and MajorFactionIDs
private.MAP_RENOWN_IDS = {

}

-- SpellIDs associated to entities
private.SPELL_IDS_ENTITY = {

}