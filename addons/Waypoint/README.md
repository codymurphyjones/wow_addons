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
- **By air:** run to the flight master + 20 s to talk, take off and land + the flight + run from where you land. Every pair of flight points you know on your continent is tried. The quickest is used if it saves at least 45 seconds and 15% of the trip.
- Waypoint learns which flight points you know from the flight master's map, so **talk to a flight master once** after installing it. `/way flights` shows what it knows; `/way flights off` turns this off.
- Only flights on the continent you're on. Boats and zeppelins aren't planned.

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

## Commands

| Command | |
|---|---|
| `/way` | What the arrow points at |
| `/way <x> <y> [title]` | Add a waypoint in your zone (`/way 42.5 65 Mailbox`) |
| `/way clear` | Clear the path (for your group too) |
| `/way undo` | Undo your last path change |
| `/way quests on\|off` | Follow Questie quests when nothing else asks |
| `/way share on\|off` | Share your path with your group |
| `/way confirm on\|off` | Ask before adding a waypoint |
| `/way autofly on\|off` | At a flight master with no menu, take the planned flight right away (hold Shift to choose yourself) |
| `/way flights [on\|off]` | Lead to a flight master when flying is quicker; on its own, what it knows (flight points, timed flights, your travel speed) |
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
| `Waypoint:RegisterCallback(owner, fn)` | `fn(event, entry)`: `"changed"`, `"arrived"`, or `"cleared"` (the player stopped a target from the arrow) |
| `Waypoint:UnregisterCallback(owner)` | |

Targets are saved without their functions. After a reload, `Get` still returns yours with its key and fields. Call `Set` again to put `onClick` back.

List Waypoint in `## OptionalDeps` so it loads first.
