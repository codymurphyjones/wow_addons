# SaddleBags: Tabbed UI System

**Strap your windows into tabbed panels, and switch between quests, meters and anything else with one click.**

Your screen only has so much room. The quest tracker, the damage meter, Details!, the buff bar: they all want the same corner. SaddleBags gives them a tabbed panel called a **Saddle**. Drop a window on a tab and it locks in. Click a tab and that window shows; the others wait out of sight. Need panels in more than one place? Add another Saddle. Each one has its own tabs, size and position.

---

## Features

### Lock any window into a tab
- **Drag and drop:** drag a window (Details!, bags, the character window, anything that can be dragged) onto a tab and let go. It locks into that tab and stays there every time you log in.
- **Capture picker:** pick *Capture...* and hover any window on screen. It lights up green. Click to lock it in, and use the mouse wheel to cycle through windows stacked on top of each other.
- **Add by name:** type a frame's name (find it with `/fstack`), for windows that are hidden or can't be clicked.
- Windows in one tab stack top to bottom at their own size. Reorder them with **Up** and **Down** in the settings.

### As many Saddles as you need
- Make up to **10 Saddles**, each with up to **10 tabs**: quests on the right, meters on the left, raid tools wherever you want them.
- Each Saddle has its own **name**, **position**, **tabs**, **tab sizes** and **grow direction**.
- Add, rename and remove Saddles in the settings, or right-click any tab. Removing a Saddle sends its windows back to where they came from.

### One-click Blizzard windows
The settings list Blizzard's own windows with a **Not attached / Saddle > Tab** picker:

- Quest objectives tracker
- Blizzard's damage meter, every window of it
- Buffs, minimap, cast bar
- Player, pet and target frames
- And more

Pick a tab and it's done.

### Stays put
Other addons and Blizzard's UI like to move windows back where *they* think they belong. SaddleBags notices and puts them back, whether a window is moved, resized, re-shown or created late after login.
- **Questie:** its tracker places itself wherever Blizzard's tracker is. SaddleBags spots that and locks the Questie tracker into the same tab, so it never strays onto your screen.
- **Blizzard's damage meter:** handled hands-off, so it keeps reading its combat data without errors.

### Sized the way you want
- **Drag the corner grip** to set a tab's size. Anything taller scrolls.
- **Grow / shrink to fit** buttons, and **right-click the grip** to fit the tab to its windows.
- **=** gives every tab in the Saddle the same size, so switching tabs never changes its shape.
- **Grow direction:** pin the left or the right edge, so a Saddle on the right side of your screen grows to the left.
- The background shows only while you're editing or when a tab is empty, so locked windows look just like they always do.

### Edit Mode friendly
- By default, Saddles can only be moved or changed while **Edit Mode** is open. Every Saddle shows a blue overlay with its name, so you can drag it, resize it and right-click it there.
- Prefer a simple lock? Turn off *Require Edit Mode* and use **Lock Saddles** instead.

### Safe in combat
Hiding a tab never hides the windows in it. They're tucked out of sight instead, so no Blizzard code runs from SaddleBags and nothing is blocked. Windows that Blizzard protects in combat (like the player frame) lock their Saddle until combat ends. Anything you change mid-fight is applied the moment combat ends.

---

## Getting started

1. **Install** SaddleBags and launch the game. A new addon folder is only picked up on a full launch, not on `/reload`.
2. **Find your first Saddle.** It sits in the middle of your screen with two tabs, *Tab 1* and *Tab 2*.
3. **Open Edit Mode** (Game Menu > Edit Mode). Drag the Saddle to where you want it.
4. **Fill a tab.** Pick one of these:
   - Drag a window (for example a Details! window) onto a tab.
   - Right-click a tab and choose **Capture window...**, then click the window.
   - Open `/sb` and pick a tab for any Blizzard window, like the quest tracker.
5. **Rename tabs** by double-clicking them in Edit Mode, for example *Quests* and *Meters*.
6. **Size it.** Drag the corner grip, or click **+** to grow the tab until everything fits.
7. **Close Edit Mode.** Your Saddle locks, and one click on a tab switches windows.
8. **Want another panel?** In `/sb`, click **New Saddle...**, or right-click any tab and choose **New Saddle...**.

---

## Controls

| | |
|---|---|
| **Click** a tab | Show that tab's windows |
| **Double-click** a tab (editing) | Rename the tab |
| **Right-click** a tab (editing) | Tab and Saddle menu |
| **Drag** a tab or the Saddle (editing) | Move the Saddle |
| **Drag** the corner grip (editing) | Resize the current tab |
| **Right-click** the corner grip | Fit the tab to its windows |
| **Drag** any window onto a tab (editing) | Lock it into that tab |

| Command | What it does |
|---|---|
| `/sb` or `/saddlebags` | Open the settings |
| `/sb <n>` | Show tab *n* on the Saddle you used last |
| `/sb new [name]` | Make a new Saddle |
| `/sb capture <n>` | Pick a window for tab *n* |
| `/sb add <n> <FrameName>` | Lock a frame into tab *n* by name |
| `/sb detach <FrameName>` | Release a window |
| `/sb lock` | Lock or unlock Saddles (when not using Edit Mode) |
| `/sb reset` | Move every Saddle back to the middle of the screen |
| `/sb debug` | Print where every locked window is, for bug reports |

### Key bindings
Under **Options > Keybindings > AddOns > SaddleBags**:

- **Next tab**
- **Show tab 1** to **Show tab 5**
- **Switch Saddle**, which picks the Saddle the other keys control

The tab keys act on the Saddle you clicked last.

---

## Settings

Open **Options > AddOns > SaddleBags**, or type `/sb`:

- **Lock Saddles** and **Require Edit Mode**
- **Saddles:**
  - Add, rename, reset the position of, or remove each Saddle.
  - **Edit** picks the Saddle whose tabs are listed below.
- **Tabs and windows:**
  - Set the number of tabs.
  - Rename tabs, and Capture or Add by name for each one.
  - Every locked window has **Up**, **Down**, **Move to...** (any tab of any Saddle) and **Detach**.
- **Blizzard windows:** one-click placement for Blizzard's own windows.

---

## Works with

- **Details!**: drop a window on a tab. Its title bar and other parts come along, and multiple windows stack neatly.
- **Questie**: its tracker is kept in the tab that holds the quest tracker.
- **Blizzard's damage meter**: every window, safely and without errors.
- **Most other addons**: anything with a named window can be captured.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001). No libraries required.
- When you release a window, Blizzard windows go back to their original spot and addon windows go to the middle of the screen.
- Windows that Blizzard protects in combat (player, pet and target frames) freeze their Saddle in combat. It moves again as soon as combat ends.
- Saved variables: `SaddleBagsDB` (account-wide).

Bug reports and suggestions are welcome in the comments or on the issue tracker.
