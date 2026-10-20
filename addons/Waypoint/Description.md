# Waypoint

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
- boats, zeppelins and skyships;
- swimming across to an island when that beats the boat (with Aquatic Form's speed for druids);
- your hearthstone;
- mage teleports.

The arrow leads one step at a time: "Zeppelin to Undercity", then "Fly: Undercity to Tarren Mill", then the target. A chat line gives the whole trip and how long it takes.

### Paths you draw on the map
- **Ctrl+left-click** the world map to drop waypoints. They join into a path, and the arrow leads you through it in order.
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
