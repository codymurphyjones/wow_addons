# Zeppelin Signs

**Never board the wrong zeppelin again. Stand at a dock and a sign tells you where that ride goes.**

Zeppelin towers have two platforms side by side, and harbors have several ships tied up next to each other. Zeppelin Signs shows the answer in big text at the top of your screen, such as **Zeppelin: Undercity** or **Ship: Booty Bay**, while you stand at a dock. Walk away and the sign goes away. There's nothing to click and no window to set up.

---

## Features

### A sign where you can't miss it
- Large, outlined white text near the top of your screen, readable over any background.
- It shows the ride type and where it goes: **Zeppelin: Grom'gol**, **Ship: Menethil Harbor**.
- Clicks pass straight through it, so it never gets in your way.

### Knows which dock you're standing on
- **Zeppelin platforms:** the sign shows within **15 yards**. The two Grom'gol zeppelin masters are only about 17 yards apart, so you always get the right platform.
- **Ship docks:** the sign shows within **60 yards**, since piers are longer.
- If two docks are close together, the sign for the nearest one wins.
- Distances use world coordinates, so a dock right on a zone border still works.

### Look at the master, get the sign
Mouse over, target or soft-target a zeppelin master or dockmaster and their sign shows right away, from any distance, even before you reach the platform. Frezza, Snurk Bucksquick, Zapetta, Hin Denburg, Nez'raz, Squibby Overspeck, Grimble, Grizzlowe and Raul Sweete are built in.

### Make it yours
- **Move a sign:** stand where you want it and type `/zep mark`. The nearest sign within 60 yards moves to your spot.
- **Add a sign:** `/zep mark new` opens a small window. Pick **Ship** or **Zeppelin**, type the destination, then:
  - **Use my location** puts the sign where you stand, or
  - **Use target NPC** ties it to the NPC you're targeting, so looking at them shows it too.
- **Undo:** `/zep remove` deletes the nearest sign you added, or puts a moved built-in sign back where it was.

---

## Built-in routes

| From | Ride | To |
|---|---|---|
| Orgrimmar | Zeppelin | Undercity, Grom'gol |
| Undercity | Zeppelin | Orgrimmar, Grom'gol |
| Grom'gol | Zeppelin | Orgrimmar, Undercity |
| Skywatcher | Skyship | Valanaar |
| Valanaar | Skyship | Thunder Bluff, Dalaran |
| Dalaran | Skyship | Valanaar |
| Ratchet | Ship | Booty Bay |
| Booty Bay | Ship | Ratchet |
| Theramore Isle | Ship | Menethil Harbor |
| Menethil Harbor | Ship | Theramore Isle, Southshore |
| Southshore | Ship | Auberdine |
| Rut'theran Village | Ship | Auberdine |
| Auberdine | Ship | Rut'theran Village, Menethil Harbor, Stormwind Harbor |
| Stormwind Harbor | Ship | Auberdine |
| Steamwheedle Port | Ship | Powderfuse Port |
| Powderfuse Port | Ship | Gadgetzan |
| Feathermoon Stronghold (Sardor Isle) | Ship | The Forgotten Coast |
| The Forgotten Coast (Feralas) | Ship | Feathermoon Stronghold |

Skyships show as **Zeppelin** signs.

---

## Getting started

1. **Install** Zeppelin Signs and launch the game. A new addon folder is only picked up on a full launch, not on `/reload`.
2. Type `/zep test` to see a sample sign for five seconds.
3. Walk onto any zeppelin platform or ship dock. The sign appears on its own.
4. If a sign shows up a little off from where the ride actually docks, stand in the right spot and type `/zep mark`.
5. Found a dock that isn't covered? Stand on it and type `/zep mark new`.

---

## Commands

| Command | What it does |
|---|---|
| `/zep` | Turn signs on or off |
| `/zep test` | Show a sample sign for five seconds |
| `/zep mark` | Move the nearest sign (within 60 yards) to where you stand |
| `/zep mark new` | Add a new ship or zeppelin sign |
| `/zep remove` | Delete the nearest sign you added, or reset a moved built-in sign |
| `/zep help` | List the commands |

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001). No libraries required.
- Lightweight: it checks your position four times a second and does nothing else.
- Moved and added signs are saved account-wide in `ZeppelinSignsDB`, so every character sees them.
- Built-in dock positions come from Wowhead's NPC and world map data. Use `/zep mark` if one is off.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
