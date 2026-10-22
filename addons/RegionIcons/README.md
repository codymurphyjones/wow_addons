# RegionIcons (OpenMaps: Region Icons)

Shows every addon's map icons for the zones touching the one you're looking at, not only that zone's own: on OpenMap's stitched map, on Blizzard's world map (the bits of the neighbouring zones at a zone map's edges), and on the minimap near a zone border. No addon is changed and none is required; OpenMap, RareScanner, Questie and the rest are optional (`## OptionalDeps`, so they load first).

"Touching": the zones of the shown zone's continent whose rectangle on it (`C_Map.GetMapRectOnMap`) touches or overlaps the shown zone's. A continent map shows every zone's icons only with the `continent` option. Other map types (the world, dungeons) show nothing extra.

Icons reach a map in three ways, and each has its own file:

| How the icons get there | Who | File |
|---|---|---|
| A world map data provider (`MapCanvasDataProviderMixin`) | most addons that draw their own; Blizzard's flight points, dungeon entrances, points of interest | `Canvas.lua` |
| HereBeDragons-Pins (one copy per addon, Questie's renamed) | Questie, TomTom, GatherMate2, HandyNotes ... | `Pins.lua` |
| RareScanner's own canvas (`RSWorldMap`, over Blizzard's) | RareScanner | `RareScanner.lua`, `RareScannerMinimap.lua` |

## Files

| File | What it does |
|---|---|
| `Zones.lua` | The touching zones (`Neighbours`, `IsNeighbour`, cached per map) and where a zone's 0-1 point lands on the shown map (`Place`): through Blizzard's continent rectangles on its own map (only 0-1), through the shared `WorldMap.OnCanvas` on OpenMap's stitched one (past 0-1 too). `NearPlayer(reach)`: the zones whose edge is within reach yards of you (world rectangles from `C_Map.GetWorldPosFromMapPos`, secret-safe through the shared `WorldMap.Player`). |
| `Canvas.lua` | Hooks (`hooksecurefunc`) `RefreshAllData` of the world map's providers. After a provider's own refresh, its refresh runs again once per touching zone on a stand-in for the provider: its `GetMap()` is a stand-in map whose `GetMapID()` answers the zone and whose `AcquirePin` moves each new pin (`normalizedX/Y`) onto the shown map with `pin:SetPosition` (off it: given back after the passes). `RemoveAllData` and `RemoveAllPinsByTemplate` do nothing during a pass; every other read and write goes to the provider. A neighbour's pin of the same template at the same spot as one already there is dropped. Which providers: every addon's (`issecurevariable` names its addon) but HereBeDragons', RareScanner's, Questie's, OpenMap's and ours; of Blizzard's, `FlightPointDataProviderMixin`, `DungeonEntranceDataProviderMixin` and `AreaPOIDataProviderMixin` (matched by their own methods), on Blizzard's map only (OpenMap draws its own on the stitched one). A provider that never asks for the map ID in a pass draws the same for every map: dropped and left alone. Providers added later are found through `AddDataProvider` and as the map opens. |
| `Pins.lua` | Every loaded HereBeDragons-Pins copy (`LibStub:IterateLibraries`). World map, Blizzard's only (OpenMap's `Extras.lua` already does the stitched map): after the copy's `HandlePin`, a pin of a touching zone (`data.uiMapID`) is acquired in the copy's own template (its pool in `WorldMapFrame.pinPools`), or moved when the library placed it already (Questie's copy shows neighbours, from world coordinates that don't match Forever's zone maps). Its zone point: Questie's `mapX/mapY`, else the copy's `GetZoneCoordinatesFromWorld`. Pins flagged `-1` (Questie's show-only-on-own-map) and Questie's "hide on continents" are respected. Minimap, standard copies only (Questie's shows every pin in range already): every 2 s, pins of zones within the minimap's reach + 100 yards have `uiMapID` held aside, so the library shows them as world pins; it's put back once you move away (and when the option goes off). Floating pins (waypoints) are left alone. `AddMinimapIconWorld` / `AddMinimapIconMap` are wrapped so re-added pins start afresh. |
| `RareScanner.lua` | With RareScanner loaded: wraps its map provider (`RareScannerDataProviderMixin`, on `RSWorldMap`) at login. Its `RefreshAllData` clears once, then runs RareScanner's own refresh once per touching zone with the canvas's `mapID` set to that zone and `RemoveAllData` a no-op. Pins acquired in those passes are moved onto the shown map (`pin.x/y`, re-applied on every zoom by RareScanner) through `Zones.Place`. The shown map's own pass runs last, so its route, guide and animations end on it. Every override is restored after each pass, even when it errors. The same entity at the same spot shows once. `AcquirePin` stays wrapped, so overlay spots and guide icons that a neighbour's pin opens later (a click) are moved too. |
| `RareScannerMinimap.lua` | Every 3 s it looks for zones whose edge is within the minimap's radius + 150 yards. Their POIs come from the same refresh run for that zone with `AcquirePin` collecting POIs instead of drawing pins (groups flattened, POIs copied). They're drawn in our own pool of RareScanner's `RSMinimapPinTemplate` (its tooltip), placed with HereBeDragons-Pins' `AddMinimapIconWorld` so they show across the border. Entities RareScanner already shows for your own map are skipped. Collected again when the nearby zones change, RareScanner refreshes, or every 30 s. Never in combat, with the world map open, or in an instance. RareScanner's minimap icon scale and its "show minimap icons" option apply. |
| `Core.lua` | Options (`RegionIconsDB`: enabled; where: openmap, worldmap, minimap, continent; whose: pins, addons, blizzard, rarescanner; `off[addon]`), start-up, OpenMap's menu switches (`OpenMapAPI.RegisterMenuToggle`) and its `OpenMap_StitchedChanged` callback, `/regionicons` (`/ricons`). |
| `Settings.lua` | Options > AddOns > Region Icons (shared `OptionsPage.lua`). Any option change redraws. |

Shared: `Core.lua`, `WorldMap.lua`, `OptionsPage.lua`.

## Not covered yet

- Not yet tried in game: `Canvas.lua` (other addons' and Blizzard's providers) and `Pins.lua` (HereBeDragons) are new. Blizzard's providers' pins acquired from addon code may spread taint; if the game blocks an action after opening the map, turn off "Blizzard's flight points, dungeons and points of interest".
- A provider that adds pins outside `RefreshAllData` (on its own events) gets its neighbours' icons only at the next refresh. One that keeps its pins in a list keyed by ID may mix up a neighbour's icon with the shown map's of the same ID.
- Pins that place themselves again later from their own data (not `normalizedX/Y`) may jump back to the neighbour's coordinates.
- RareScanner's minimap icons use the world map's filters (its refresh is run as for the world map), so an entity filtered only on the minimap can still show for a neighbouring zone.
- Neighbours are found on one continent only (Blizzard's continent rectangles), even on OpenMap's stitched map.
- An icon of a neighbouring zone that RareScanner's world-map vignettes also show isn't filtered (RareScanner checks the shown map's vignettes only).
- Saved options from the addon's earlier name (Nearby Rares, `NearbyRaresDB`) aren't carried over.
