# Waypoint: Geography Aware Navigation

**An arrow that knows where you're going: your Questie quests, your addons' targets, and a waypoint path your whole group can draw on the map.**

---

## Features

### Follows your quests
With **Questie**, the arrow points at your focused quest. If no quest is focused, it points at the tracked quest with the nearest thing to do.
- For a kill or collect objective, it leads you spawn to spawn.
- Once the quest is done, it takes you to the turn-in.

The arrow stays on one quest while you walk. When you track something else, change the focus or finish an objective, a chat line tells you what it points at now.

### Takes the fastest way, even across continents
Waypoint times your flights, your rides and your travel speed, and plans the quickest trip using everything you have:
- flight paths;
- boats, zeppelins and skyships, with timetables for every route, Forever's own included;
- swimming across to an island when that beats the boat (with Aquatic Form's speed for druids);
- your hearthstone;
- mage teleports.

The arrow leads one step at a time: "Zeppelin to Undercity", then "Fly: Undercity to Tarren Mill", then the target. A chat line gives the whole trip and how long it takes.

### Walks the way you would
- Straight across open ground at any angle, not in right angles along a grid.
- Sweeps round hills and corners instead of turning on a point.
- Goes around cliffs, water and lava, and over bridges and up stairs.
- Three road preferences: **Safe** keeps to roads, **Balanced** uses a road when one runs your way, and **Speed** takes the quickest way. Roads are never faster, only safer, so with no road nearby all three take the same way.
- With Field Guide, the world map shows your next five stops, each in its own colour, so you can see the journey ahead at a glance.
- Hover the line on either map to see where it leads, what you'll do there, what it pays and how far it is.
- After a login or `/reload` it waits until you move, so the first route starts from where you really are.

### Paths you draw on the map
- **Ctrl+click** the world map to drop waypoints. They join into a path, and the arrow leads you through it in order.
- The first waypoint is **Blizzard's own map pin**, so the game's map and other map addons show it too. A pin set anywhere else (a chat link, OpenMap, another addon) becomes your next waypoint.
- **Ctrl+right-click** removes the waypoint nearest the cursor, and the path joins up around it.
- **Ctrl+Z** undoes your last 10 changes.

Plain clicks still zoom the map.

### Shared with your group
Everyone in your group who runs Waypoint sees the same path, live.
- Extend a teammate's path, or wipe it and start your own with one click.
- Players who join late get the path too.
- Your waypoints are gold and your teammates' are blue.

### Works with other addons
**Spyglass** quest chains and **WealthPlanner** jobs use Waypoint's arrow. Other addons can too, through a small API (see the README).

---

## Commands

| Command | |
|---|---|
| `/way` | What the arrow points at |
| `/way <x> <y> [title]` | Add a waypoint in your zone |
| `/way clear` / `/way undo` | Clear the path / undo your last change |
| `/way flights` | What it knows about flights, rides, your hearthstone and teleports |
| `/way arrow` / `/way lock` | Show or hide / lock the arrow |
