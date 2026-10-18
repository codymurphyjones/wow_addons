# RoadLog

<img src="Media/Logo.png" alt="RoadLog logo" width="128">

Records the roads you walk, as paths in world coordinates, so they can be used later (for example to time trips by road in Waypoint). No dataset of Classic's roads exists, so this one is built by walking them.

The game can't tell an addon what the ground under you is. So the rule is simple: **while RoadLog is on, every step you take counts as road.** Turn it on when you step onto a road, walk down the middle of it, and turn it off when you leave it.

## The minimap button

- **Left-click** turns recording on or off. The icon is grayed out while it's off.
- **Right-click** shows or hides the recorded roads on the world map.
- **Drag** moves it around the minimap.

The tooltip shows what RoadLog is doing and how much road you've recorded. The button is also in the AddOn Compartment.

## What it records

- While you move, a point goes down every 4 yards. On straight stretches the in-between points are dropped (anything within 0.75 yards of the straight line), so curves keep their detail and straight roads stay small.
- Standing still keeps the stretch open.
- **It pauses** while you're dead or a ghost, swimming, flying, on a flight path, indoors or in an instance. The stretch you were on ends there, and a new one starts when you move again. Recording stays on, so it picks up by itself once you're back on your feet.
- A hearthstone, portal or loading screen also ends the stretch, so no line joins the two places.
- Stretches shorter than 10 yards aren't kept.

Roads are saved for your whole account, so every character adds to the same map.

## Slash commands

| Command | What it does |
|---|---|
| `/roadlog` or `/roads` | Turn recording on or off (`on`, `off` also work) |
| `/roadlog map` | Show or hide the roads on the world map |
| `/roadlog undo` | Delete the last stretch, for when you forgot to turn it off |
| `/roadlog clear` | Delete every road (asks first) |
| `/roadlog stats` | Yards recorded per continent |
| `/roadlog minimap` | Show or hide the minimap button |

## The data

`RoadLogDB.roads` in `WTF\Account\<account>\SavedVariables\RoadLog.lua`:

```lua
roads = {
  [0] = {                -- the continent, as C_Map.GetWorldPosFromMapPos numbers it (0 Eastern Kingdoms, 1 Kalimdor)
    { zone = 1429,       -- the zone's map ID where the stretch started
      at = 1792345678,   -- when (time())
      pts = { n1, w1, n2, w2, ... } },  -- world yards: north, west, rounded to 0.1
  },
}
```

Each entry is one unbroken stretch, in the order you walked it. Roads you walk twice show up twice; merging them is left to whatever reads the data.

The art is drawn by `tools\RoadLog\make_icon.py`.
