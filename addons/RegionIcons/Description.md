# OpenMaps: Region Icons

**See every map icon in the zones next door too, not only in the zone you're looking at.**

Most map addons put their icons on one map at a time. Open a zone and you get that zone's quests, herbs, rares and flight masters. The zone over the border stays blank, even though you can see part of it at the map's edge. And on the minimap, a node a few yards over the border isn't there until you cross. Region Icons fills in the zones that touch the one you're looking at, using each addon's own icons, tooltips and clicks.

It works with your addons as they are. It doesn't change them, and none of them is required.

---

## Whose icons

- **Questie, TomTom, GatherMate2, HandyNotes** and every other addon that draws its map icons through HereBeDragons, the map pin library most map addons share.
- **RareScanner:** its rares, treasures and events, with RareScanner's own tooltips. Click one for its spawn spots or guide, or Shift+right-click it for a waypoint.
- **Other addons' world map icons:** addons that draw their own icons are found by themselves. `/regionicons sources` lists them, and you can turn any of them off.
- **Blizzard's own icons:** flight masters, dungeon entrances and points of interest of the neighbouring zones.

Everything follows each addon's own filters and options.

## Where it shows

- **OpenMap's stitched world map:** pan across a border and the neighbouring zones already have their icons on them.
- **Blizzard's world map:** the edges of a zone map show bits of the zones next to it. Their icons now show there too.
- **Minimap:** near a zone border, the next zone's icons show as well as your own zone's.
- **Continent maps (optional, off by default):** every zone's icons on the continent map.

"Next door" means every zone that touches the one you're looking at.

## Settings

Options > AddOns > **Region Icons** has a switch for each map and each kind of icon. With OpenMap, the same switches are also in OpenMap's menu under **Region Icons**.

| Command | What it does |
|---|---|
| `/regionicons` | What's on, and how many icons were added |
| `/regionicons openmap` | Icons on OpenMap's stitched map, on or off |
| `/regionicons worldmap` | Icons on Blizzard's world map, on or off |
| `/regionicons minimap` | Icons on the minimap, on or off |
| `/regionicons continent` | Every zone's icons on a continent map, on or off |
| `/regionicons pins` | Questie, TomTom, gatherers and notes, on or off |
| `/regionicons rarescanner` | RareScanner's icons, on or off |
| `/regionicons blizzard` | Blizzard's flight points, dungeons and points of interest, on or off |
| `/regionicons addons` | Other addons' world map icons, on or off |
| `/regionicons sources` | List the addons whose world map icons were found |
| `/regionicons source <addon>` | One addon's icons, on or off |
| `/regionicons on` / `off` | All of Region Icons |
| `/regionicons config` | Open the options |

`/ricons` works too.

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001).
- Needs no other addon. It's made for **OpenMap**, but works on Blizzard's map as well.
- Doesn't change any other addon. If an update of one changes the parts Region Icons uses, Region Icons leaves that addon's icons out and says so once in chat.
