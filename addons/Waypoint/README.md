# Waypoint

<img src="Media/Logo.png" alt="Waypoint logo" width="128">

A navigation arrow, like TomTom. It points at one thing at a time:

1. **What another addon asks for**: Spyglass quest chains, WealthPlanner jobs, or any addon using the API below.
2. **Your group's waypoint path**: waypoints you and your group drop on the world map.
3. **Your Questie quests**, when nothing else is asking.

The newest of 1 and 2 wins. Whenever the arrow starts pointing at something else, a chat line says what.

Questie is optional. Without it the arrow only shows up for paths and other addons.

## The arrow

- It shows the target, the distance and about how long it takes to get there. At the target it shows a check mark.
- Drag it to move it (`/way lock` stops that).
- **Left-click** runs the target's own action, for example opening the Spyglass quest window.
- **Right-click** moves on: to the next waypoint, to another quest, or away from an addon's target.
- **Shift+right-click** clears the waypoint path.

The target also has a dot on the minimap (on the rim when it's out of range) and a marker on the world map.

## Flight paths

When flying gets you there sooner, the arrow leads to the flight master first ("Fly: Sentinel Hill to Lakeshire"). The flight master's menu gets a **Fly to Lakeshire (Waypoint)** button under it: click it to take off. Their own "Show me where I can fly" opens the normal flight map, with Lakeshire pulsing and a **Fly to Lakeshire** button under the map. A flight master with no menu (the map opens straight away) takes the planned flight by itself; hold Shift as you talk to them to choose yourself, or turn that off with `/way autofly off`. The arrow shows the time to landing in the air, and picks your target up again when you land.

How it decides:

- **Running:** the straight line to the target, plus 20% for roads and hills, at your travel speed. That is your mount's speed once you've ridden (Waypoint remembers the fastest mount you've had), else your run speed.
- **Flying:** each flight is timed from take-off to landing, and that time is used from then on (shared by all your characters). A flight you haven't taken yet is estimated from the ones you have, by seconds per yard of straight line.
- **By air:** run to the flight master + 20 s to talk, take off and land + the flight + run from where you land.
- Waypoint learns which flight points you know from the flight master's map, so **talk to a flight master once** after installing it. `/way flights` shows what it knows; `/way flights off` turns this off.

## The fastest way there

Flights are one of several ways Waypoint can plan a trip. It looks for the quickest mix of everything you can use, over as many steps as it takes. For example: run to the zeppelin, ride it to Undercity, fly to Tarren Mill, run to the target. A chat line gives the whole trip when it picks one ("Fastest way: zeppelin to Undercity, then fly Undercity to Tarren Mill, then walk (about 9m 30s)"). The arrow then leads one step at a time.

| Step | How long Waypoint counts it |
|---|---|
| **Running and swimming** | Along Waypoint's land and water map (below), from where you are and to the target: around lakes, cliffs and lava, or straight across water when swimming there is quicker than going around. Swims of 200 yards or more become their own step ("Swim to the far shore"). Between other stops on the way (a flight's landing and a dock), a straight line plus 20% |
| **Aquatic Form** | Druids who know it have their swims counted at its speed (50% faster at first, then the speed Waypoint saw you swim in it). Waypoint tells you when to shift: "Switch to Aquatic Form and swim to Auberdine" at the shore, and a chat line when you're in the water in your own form |
| **Flights** | As above, between flight points you know on one continent |
| **Boats, zeppelins, skyships** | How long the ride took you before, from reaching the dock to arriving, waiting included (an average of your last trips). A ride you haven't taken counts as 4 minutes for a zeppelin or skyship and 5 for a ship |
| **Hearthstone** | What's left of its cooldown + 10 s to cast + 15 s of loading screen, when it's in your bags |
| **Mage teleports** | 10 s to cast + 15 s of loading screen, for teleports you know with a Rune of Teleportation in your bags |
| **Jumping down cliffs** | Drops you'd take no damage from (under about 14.6 yards) are slid down. Bigger ones are jumped up to the fall damage you said you'll take (**Fall damage you'll take** in the settings: none by default). With **Walk on Air** (the Skyborne racial: no reagent, 90-second cooldown, used first when it's ready), or **Slow Fall** (mage) or **Levitate** (priest) known *and* a Light Feather in your bags, any drop is jumped. A cliff spread over several squares counts as one fall: the whole way down is checked against your limit, not each step. Each jump is its own step: "Jump down with Slow Fall" ("Cast Slow Fall and jump down" at the edge), or "Jump down 41 yd" ("Jump down: about 50% of your health (1,932 HP)"). At the edge, the arrow stays up, turns green and points the way to jump (toward where you land). It also checks your health now and says **Heal first** when the jump would leave you under 15% or kill you, since jumps in a row add up. The chat line gives the trip's total. Cliffs are never climbed, spell or not |

- **The docks** are Zeppelin Signs' list: the Horde zeppelins, Forever's skyships and all the ships. If you run Zeppelin Signs, docks you moved or added with `/zep mark` count too. Zeppelins are left out for Alliance, and ships from Alliance ports (Menethil, Theramore, Southshore, Auberdine, Rut'theran, Stormwind) for Horde.
- **On a ride** the arrow shows "On the zeppelin to Undercity" and when it should arrive, then picks your target up again.
- **Where things land:**
  - Your hearthstone is learned when you set it at an innkeeper or use it; until then it's guessed from the town of that name.
  - Each mage teleport is learned the first time you cast it.
  - A ride with no dock at the other end (the Thunder Bluff skyship, Gadgetzan) is learned the first time you take it.
- **When it's used:** on your own continent a route is only used when it saves at least 45 seconds and 15% of the trip over running. Somewhere you can't run to, the quickest way always wins.
- **Sticking to a plan:** once Waypoint has picked a way (a flight, a ride, your hearthstone or a teleport), it keeps it as you move. A different way only takes over if it's at least a minute and 15% quicker than finishing the current plan from where you are now. In combat, nothing about your bags, cooldowns or spells is re-read (the game hides them then), so the plan stays as it was and the arrow says "Hearthstone once combat ends".
- `/way transports off` plans without boats, zeppelins, skyships, your hearthstone and teleports (flights only). `/way flights` lists what it has learned.
- The Deeprun Tram isn't planned.

### The land and water map

`Data\Water.lua` divides every continent into 66-yard squares of land, water (deep enough to swim), cliff face, lava/slime/fel, or off the map, each with its height and which neighbours you can walk or drop to. `tools\Waypoint\build_water.py` builds it from the game's own map tiles: terrain heights and water surfaces, with bridges, piers and docks counted as land. It covers the Eastern Kingdoms, Kalimdor, Zephras Isle, Hyjal Crater and Dalaran City. Rebuild it with `yarn build` (or `python -I tools\Waypoint\build_water.py`) after a game patch.

- **Working out times:** in the background, a few milliseconds a frame, Waypoint works out how long it takes from you, and to the target, to every square of the continent. It redoes yours after you've moved about 200 yards. Until that's done it plans with straight lines.
- **It learns the ground.** The map misses passes narrower than its squares. Every step you walk from one square into the next on your own feet, where the map said you couldn't, is remembered for all your characters and used from then on: both ways if you walked it uphill or on the level, only down if it was a drop. Falling, flying, swimming and flights don't count, and neither does a drop that would have hurt.
- **This way is blocked.** The map can't see fences, buildings or a ledge you can't get down from. When the arrow leads somewhere that isn't there, right-click it and choose **This way is blocked** (or type `/way blocked`). It closes the next step the plan takes from where you stand (every jump out of there, when the next step is a jump), remembers it for all your characters, and plans another way. **Forget blocked ways** in the same menu (or `/way unblock`) clears them.
- **Walk on Air once per walk.** Its 90-second cooldown outlasts most walks, so a route plans at most one jump with it per stretch of walking. Slow Fall and Levitate, a feather a cast, can be used for every jump; a run of jumps one after another counts as one cast.
- **Roads.** Waypoint comes with the roads logged with RoadLog (`Data\Roads.lua`, built by `tools\Waypoint\build_roads.py`), so everyone has them, RoadLog or not. The small box at the end of the arrow's third line picks how much a walk keeps to them:
  - **Safe:** keeps to roads, and leaves them only where a way off the road is far quicker (or there's no road).
  - **Balanced** (the default): takes the roads that lead your way, and leaves them for the last stretch to where you're going.
  - **Speed:** the quickest way, roads or not; a road only when it's about as quick.

  Times are always real walking times, so the mode never makes a flight or a boat look better than it is.
- **RoadLog marks count too.** If you run RoadLog, its narrow-pass pins open every way out of their square, its roads count as walked (and as roads for the box above), and its blockers close the ways that cross them. New marks are picked up within 15 seconds.
- **The planned route** is drawn as a dashed line on the world map, and as a trail of dots on the minimap around you. It covers every walk, swim and jump along the land map, and flights and rides straight from stop to stop. Each kind of travel has its own colour family of 10 shades: walking yellow, flights and rides purple, jumps red, swimming green.
  - **Stages:** a whole trip to one target (your corpse, a quest objective) is one shade. Each new task the arrow follows takes the next shade.
  - **Your waypoint path:** every leg between the waypoints you dropped is drawn too, each in its waypoint's own shade. The shades are ordered so that each one differs clearly from the one before, and a waypoint keeps its colour as you reach the ones before it.
  - **Fixing a wrong way:** if the line goes the wrong way, walk the right way once, or drop a RoadLog narrow-pass pin there.
  - **Settings:** **Planned route on the world map** and **Planned route on the minimap** switch them off.
- **The arrow** follows the way around: when the straight line to the next stop crosses water or a cliff that the route goes around, it points along the route instead.
- **Clients:** the map is used on Forever and Classic Era clients only. Later expansions reshaped the continents.
- Swimming is the plain 4.7 yards a second (or Aquatic Form's). Lava, slime, fel and the edge of the map can't be crossed.
- **What you can climb:** the builder looks at the ground in 4-yard cells. A step between two cells is walkable when it rises less than about 51 degrees, as steep as you can walk up. Inside each square, the cells joined by walkable steps make patches, and the biggest is the square's ground. Between neighbouring squares, in all 8 directions, it records:
  - **walk:** some cell of one's ground is a walkable step from the other's, going either way;
  - **drop:** no walkable step, but this side is higher, so you can get down (slide or jump) but never back up;
  - **neither:** a wall.

  Waypoint then only takes walk links and drops. A drop under about 14.6 yards does no damage, so it's slid down (a little slower). Bigger ones are taken up to your fall damage setting, or any size with a safe fall. So mesas, needle pillars and mountain walls you can't climb are walked around, and a ramp or pass that does go up is found and used. Squares with no ground to stand on (cliff faces) can only be slid or jumped down.
- **Height:** every square also has its height (the ground's average, or the water's surface). Climbing costs extra: each yard up counts as a yard more on the flat. Going down costs nothing extra. The arrow says when where it leads is well above or below you ("60 yd above you", from 15 yards' difference).

## Questie quests

The arrow follows Questie's **focused** quest. If no quest is focused, it follows the tracked quest with the nearest thing to do.

- **Unfinished quest:** it leads to the nearest spawn of the objective's mobs or objects, then to the next spawn as you reach each one.
- **Complete quest:** it leads to the turn-in.

The pick holds while you walk. It changes when you track or untrack a quest, change the focus, finish an objective, or the quest is ready to turn in. Each change is announced in chat.

## Waypoint paths (world map)

| Click | What it does |
|---|---|
| **Ctrl+left-click** | Add a waypoint to the end of the path (asks first; `/way confirm off` stops asking) |
| **Ctrl+right-click** | Remove the waypoint nearest the cursor. The path joins up around it |
| **Ctrl+Z** | Undo your last path change (up to 10) |

Plain clicks still zoom the map in and out.

- The arrow leads through the path in order. Reaching a waypoint takes it off your copy, so everyone walks the path at their own pace.
- **Shared with your group:**
  - Your group sees your path on their map and arrow, and you see theirs. This only works for people who also run Waypoint.
  - Adds, removes and clears all show up immediately, with a chat line.
  - Anyone who joins later gets the path.
- **Someone else's path:** Ctrl+left-click asks whether to **Append** to it or start a **New path**. A new path wipes theirs for everyone, and Ctrl+Z brings it back.
- Your pins are gold and your teammates' are blue.

## Fall damage

Waypoint uses the servers' formula (TrinityCore, CMaNGOS): a fall costs 1.8% of your maximum health per yard, less 24.26%.

| Fall | Damage |
|---|---|
| under 14.6 yd | none |
| 20 yd | 12% |
| 30 yd | 30% |
| 40 yd | 48% |
| 47 yd | 60% |
| 60 yd | 84% |
| 69 yd | dead from full health |

Heights come from the land map's 66-yard squares, so a real cliff can be a few yards taller than Waypoint thinks. Leave yourself some room.

## Settings

Options → AddOns → Waypoint (or `/way options`):

- **The arrow:** show or lock it, lead around lakes and cliffs, the terrain line, the minimap button, and how windows under the arrow line up.
  - **Terrain line:** a line under the arrow that appears only when there's something to say. In the direction you're facing it says "Cliff ahead: 184 yd down (lethal)" (or "Walk on Air ready"), or "Too steep to climb ahead". It also says how far above or below you the target is ("Target 245 yd below you"). It comes from the 66-yard land map, so ridges and ledges narrower than that can be missed.
- **What it follows:** Questie quests, sharing paths with your group, asking before adding a waypoint.
- **World map:** town icons.
- **Planning the way there:**
  - **Transport:** flight paths, taking the planned flight by itself, boats/zeppelins/skyships, hearthstone, mage teleports.
  - **Terrain:** following the land map, swimming, Aquatic Form and its chat tip, Slow Fall/Levitate.
  - **Fall damage you'll take:** 0–90% of your health. The slider shows the height that allows and the health it costs: "60%: up to 46 yd (2,340 HP)".
  - **Cost of climbing:** each yard up counts as 0–3 yards on the flat.
  - **When a route beats walking:** the time a route must save (0–180 s) and the share of the trip (0–50%).
  - **Announcements:** the "Fastest way" chat line.

## Commands

| Command | |
|---|---|
| `/way` | What the arrow points at |
| `/way <x> <y> [title]` | Add a waypoint in your zone (`/way 42.5 65 Mailbox`) |
| `/way clear` | Clear the path (for your group too) |
| `/way undo` | Undo your last path change |
| `/way flights [on\|off]` | Lead to a flight master when flying is quicker; on its own, what it knows (flight points, timed flights, your travel speed, rides, hearthstone, teleports) |
| `/way options` | Open the settings |
| `/way arrow` | Show or hide the arrow |
| `/way lock` | Lock or unlock the arrow |
| `/way minimap` | Show or hide the minimap button |

`/waypoint` works too. WealthPlanner uses `/wp`.

## For addon authors

```lua
if Waypoint then
    Waypoint:Set("MyAddon", {
        title = "Turn in: The Defias Brotherhood",
        subtitle = "to Gryan Stoutmantle",       -- optional
        mapID = 52, x = 0.56, y = 0.47,          -- 0-1 on a uiMapID (uiMapID = ... works too)
        -- or points = { { mapID = 52, x = 0.5, y = 0.4 }, ... }: nearest first, then on to the next
        arrive = 15,                             -- yards that count as "there"
        key = "quest:1234",                      -- yours to read back with Get
        onClick = function(entry) end,           -- clicking the arrow
        onArrive = function(entry) end,          -- once, on reaching a single place
    })
end
```

| Call | |
|---|---|
| `Waypoint:Set(owner, wp)` | Your target. One per addon; setting it again replaces it and makes it the newest |
| `Waypoint:Clear(owner)` | Remove your target |
| `Waypoint:Get(owner)` | Your target, or nil |
| `Waypoint:GetCurrent()` | The entry the arrow follows (`entry.owner` is an addon, `"path"` or `"Questie"`) and its point |
| `Waypoint:RegisterCallback(owner, fn)` | `fn(event, entry)`: `"CHANGED"`, `"ARRIVED"`, or `"CLEARED"` (the player stopped a target from the arrow). Before `VERSION` 2 the names were lower case: compare with `event:upper()` to work with both |
| `Waypoint:UnregisterCallback(owner)` | |

Targets are saved without their functions. After a reload, `Get` still returns yours with its key and fields. Call `Set` again to put `onClick` back.

List Waypoint in `## OptionalDeps` so it loads first. `Waypoint.VERSION` is 2 (`API_VERSION`, its older name, still works): check `Waypoint.VERSION >= n` before using a newer function.
