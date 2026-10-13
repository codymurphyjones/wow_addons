# SimplePanel

**A clean info bar across the top of your screen: gold, XP, bags, durability, quests, professions, friends and more, with rich tooltips, charts, drag-and-drop layout, color schemes, profiles and a drawer for minimap buttons.**

SimplePanel puts the things you check all the time into one thin bar along the top edge of your screen. Each piece of the bar is a **plugin**: hover it for a detailed tooltip, left-click it for its action, right-click it for its options. Arrange the plugins into three sections by dragging them, gather your minimap buttons into a tidy drawer, follow your gold, XP or frame rate on live charts, and give it all the look you like.

---

## Getting started

1. **Log in.** The bar appears across the top of the screen with a sensible set of plugins already on it, and SimplePanel says *"Type /sb for settings; right-click the bar for options"* in chat.
2. **Hover** any plugin to see its tooltip.
3. **Left-click** a plugin for its action: open your bags, the character sheet, the world map, a chart, a menu of switches and so on.
4. **Right-click** a plugin for its options. Every plugin's menu ends with **Display** (icon, colors, progress bar, section) and **Hide**.
5. **Right-click empty bar space** for the bar's own options and a list of every plugin to turn on or off.
6. **Type `/sb edit`** (or tick **Edit the bar** in that menu) to drag plugins around, and click **Done** when you're happy.
7. **Type `/sb`** to open the SimplePanel window with every plugin, your launchers, profiles and reset buttons.

---

## Features

### The bar
- **Three sections:** left, center and right. Plugins line up from the left edge, from the right edge, and around the middle of the screen.
- **Edit mode** (`/sb edit`, **Edit the bar** on the bar menu or in the Plugins tab, or the game's own Edit Mode) outlines the three sections:
  - **Drag** plugins within a section or into another one.
  - Click a plugin's **×** to hide it.
  - **Right-click** a plugin for its options.
  - The toolbar under the bar has **Add plugin** (every hidden plugin, by category), **Reset layout** and **Done**.
- **Outside edit mode,** **shift-drag** a plugin to move it. Tick **Lock plugins** to stop that.
- **When the bar is too full,** nothing overlaps:
  - The center section slides aside rather than run into the others.
  - If it still doesn't fit, the plugins nearest the middle of the busiest section step into a **»** button. Its badge says how many are inside, hovering it shows their values, and clicking it gives each one's full menu.
  - Alerts from hidden plugins flash on **»**.
- **Auto-hide:** the bar slides away after a moment and comes back when your mouse touches the top of the screen. It stays put while you're using a menu, a tooltip or the drawer.
- **Hide in combat:** the bar steps aside during fights.
- **Push minimap and buffs down:** moves the minimap and your buffs below the bar so it doesn't cover them.
- **Size and look:** height, background opacity, dividers between plugins, small or normal font, and a **Scale** setting that grows the bar and its charts together.
- **Flashes:** a plugin briefly lights up when something happens: new mail, a skill-up, a quest done, ammo running low.

### Plugins
Every plugin has its own options on its right-click menu. Here's what each one shows and what a left-click does.

**Character**

| Plugin | On the bar | Left-click |
|---|---|---|
| **Experience** | XP %, rested XP and XP per hour, drawn as an XP bar with the rested part in blue. The tooltip has time to level, kills to level and an XP-per-hour chart. Flashes on level up. | XP chart |
| **Gold** | Your gold and this session's change. The tooltip lists every character's gold (this character, realm and faction, realm, or every realm) with a total and a 7-day chart. The bar can show their total. | Gold chart (session, 24 hours, 7 days, 30 days) |
| **Professions** | Your profession's icon and skill, such as 145/150, as a skill bar. It turns yellow when you're near your cap and should visit a trainer. Choose which one, or show both side by side. Flashes on every skill-up. | Opens that profession (Mining opens Smelting) |
| **Quests** | How many quests you have (white, turning yellow then red as the log fills), a **?** with how many are ready to hand in, and a map with how many are in your zone. The tooltip lists this zone's and your tracked quests with their objectives, or every quest if you prefer. Flashes and tells you when a quest is done. | Quest log |
| **Reputation** | Your watched faction, in its standing color, as a bar. The tooltip shows rep per hour and time to the next standing. | Pick a faction to watch |
| **Durability** | Your most damaged item, or the average. The tooltip has every slot and the repair cost. | Character sheet |
| **Bags** | Free slots, as one figure or one per kind of bag. Yellow when nearly full, red when full. | Opens your bags |
| **Hearthstone** | Where you're bound and the cooldown. | Uses your Hearthstone (optional, out of combat) |
| **Reagents** | Your class reagents, only for spells you know, with a warning when one runs low. | Choose which ones to show |
| **Ammo** | Ammo or thrown weapon count as a bar toward a full supply, with a warning when low and a chart of what you've used. | Warning and supply settings |
| **Hunter pet** | Your pet's name and happiness. Flashes and tells you when it turns unhappy. | |
| **Regen** | Health and mana per second, with a five-second-rule countdown. The tooltip has regen while casting and outside the five seconds, plus a mana chart. | Settings |
| **Alts** | How many other characters you have. The tooltip lists each with level, gold, location, last seen, rested XP (still growing while they're logged out) and /played. | Sort and choose characters |
| **Lockouts** | Saved instances and time to the next reset, for every character. | Refresh |
| **Honor** | Today's honorable kills and your rank, with progress to the next rank. | |
| **World buffs** | How many world buffs you have and the shortest time left. Warns before one runs out. | |
| **Currencies** | The currencies you choose to track, with their caps. | Currency tab |

**Information**

| Plugin | On the bar | Left-click |
|---|---|---|
| **Clock** | Local time, server time, or both, in 12- or 24-hour form. | Stopwatch and alarm |
| **Performance** | Frame rate and latency, colored. The tooltip has frame rate and latency charts. | Charts |
| **Memory** | Add-on memory. The tooltip lists the hungriest add-ons, by memory or CPU time. | Frees unused memory |
| **Location** | The place you're in and its zone, colored by PvP status, with coordinates. | World map (shift-click puts your location in chat) |
| **Session** | Time played this session, gold per hour or XP per hour. The tooltip has kills, deaths and a gold chart. | Chart |
| **Played** | /played for this character, total or this level, counting live. The tooltip has every character. | Ask the game again |
| **Volume** | Master volume as a bar, or **Muted**. **Scroll the mouse wheel** over it to change the volume. | Mute and a slider for each sound channel |
| **Timers** | The next timer's countdown. Start one for 1 minute to 1 hour, or type your own, like "25 raid starts". When time's up it flashes, sounds and shows a warning on screen. | New and running timers |
| **Speed** | Your speed as a % of run speed. | |

**Social**

| Plugin | On the bar | Left-click |
|---|---|---|
| **Social** (the full version) | Friends online, guild online and your status dot (green, Away or Busy). Optional icons show each of your interaction rules at a glance: colored when open, grey when blocked. | Whisper or invite anyone online, set Away or Busy, and every block and filter |
| **Mail** | The mailbox icon, with a dot on its corner when you have new mail. Tells you who it's from, and warns when mail on any of your characters is about to expire. | Settings |
| **Loot** | The loot threshold in its quality color, such as **Uncommon+**, or **Solo**. The tooltip has the method and master looter. | Leaders set the method and threshold. Anyone can **Roll 1-100** or **Reset all instances**. |
| **Group** | Party or raid size, plus how many are dead, offline or far away. | Ready check (leader or assist) |
| **Friends & Guild** | A simpler friends and guild counter. | Whisper or invite |

**Blocks and filters.** The Social plugin's switches act for you and keep working even if the button is hidden:
- Decline duels.
- Decline group invites from strangers.
- Accept group invites from friends and guild.
- Decline guild invites.
- Block trades and block channel invites.
- Hide whispers from strangers (GMs always get through).
- The mature language filter.
- Away and Busy.

Tick **Say in chat when something is declined** to see what it did for you.

### Charts
- Many plugins keep a history and open a **chart window**: Gold, Experience, Performance, Memory, Ammo, Regen and Session. Left-click the plugin, choose **Open chart** from its menu, or type `/sb chart <plugin>`.
- Chart windows can be **dragged**, **resized** from the corner and **pinned** (a pinned window stays put and doesn't close with Escape).
- Each plugin offers its own **ranges**, such as Session, 24 hours, 7 days and 30 days for gold.
- **Hover** the chart for exact values at any point.
- Windows remember their place, size and range.
- **Inline sparklines:** Performance, Memory, Regen and Speed can draw a tiny live chart right on the bar (Display > **Inline sparkline**).
- **Gold history** is kept for weeks, so the 30-day chart fills in as you play.

### The launcher drawer
Your add-ons' minimap buttons, gathered into one drawer:
- **Left-click the Launchers plugin** to open the drawer. Click a tile to use it, just as you'd click the minimap button. Hover it for that add-on's own tooltip. **Search** finds a launcher by name.
- **Shift-drag a tile onto the bar** to pin it there as its own button.
- **Shift-right-click** a tile to choose where it goes:
  - **In the drawer**;
  - **Pinned to the bar**;
  - **On the minimap**, left exactly where it was;
  - **Hidden**.
- The **Launchers** tab in the SimplePanel window shows the same four places as boxes. Drag launchers between them.
- **Sort** by name or most used first, and choose the tile size and number of columns.
- Placement can be shared by all characters or set for one character only.
- **Left alone on purpose:** Blizzard's own minimap controls and map-pin add-ons such as Questie, GatherMate, HandyNotes, pfQuest and TomTom.
- **New buttons:** buttons from add-ons that load later are picked up on their own. **Rescan minimap** (or `/sb scan`) looks right away.

### Broker (LibDataBroker) plugins
If another add-on provides LibDataBroker data, SimplePanel can show it:
- **Data feeds** appear as plugins in the **Broker** category, off until you turn them on.
- **Launchers** go into the drawer.
- Their own clicks and tooltips keep working. **Shift-right-click** one for SimplePanel's menu.

### Appearance
Left-click the **Appearance** plugin:
- **Color scheme:** Wally (the default), Slate, Jade, Violet, Ember, Gold, Crimson or Mono.
- **Accent in my class color:** highlights, titles and charts in your class color.
- **Window opacity:** for the SimplePanel window, menus, tooltips, the drawer and chart windows.
- **Text size:** from 80% to 130%, for everything SimplePanel draws.

### Profiles
A profile holds your bar settings, appearance, plugin layout and launcher placement. In the **Profiles** tab:
- **New**, **Copy**, **Rename**, **Reset** and **Delete** profiles.
- **Use** switches this character to the selected profile (the UI reloads). Each character remembers its own profile.
- **Export** a profile as text to share it or keep a backup, and **Import** one: nothing is overwritten.
- Gold history and your other characters' data aren't part of a profile, so switching never loses them.

### Your characters
SimplePanel remembers every character you log in on the account: gold, level and XP, rested XP, location, Hearthstone location, /played, lockouts and mail. That's how Gold, Alts, Played, Lockouts and Mail can show all your characters at once. **Forget a character** (on the Gold or Alts menu) removes one you've deleted.

### Reputation watch buttons
Adds a small eye beside every faction on the game's **Reputation** tab. Click it to make that faction your reputation bar (and the Reputation plugin's faction); click again to stop. Turn the eyes off with **Watch buttons on the Reputation tab** on the Reputation plugin's menu.

### Safe in combat
Plugins that open game windows do it through the game's own buttons, so they never cause "action blocked" errors. This covers:
- Bags, Durability, Location, Quests, Currencies and Professions.
- Hearthstone, which works out of combat only.

Most keep working in combat as long as the bar can't move then, meaning auto-hide and hide in combat are off. Edit mode closes when a fight starts, and layout changes wait until it's over.

---

## Settings

Most settings sit right on the bar.

| Where | What's there |
|---|---|
| **Right-click empty bar space** | **Edit the bar**; **Plugins** (every plugin, by category, to turn on or off); **Bar**: Auto-hide, Hide in combat, Push minimap and buffs down, Lock plugins, Dividers, Chat messages, Height, Background opacity, Scale (bar and charts), Font; Rescan minimap buttons; Settings; Reload UI |
| **Right-click any plugin** | Its own options, then **Display** (Show icon, Show label, Colored values, Inline sparkline, Progress bar: Fill or Underline and Bar width, Position: Left, Center or Right) and **Hide** |
| **Appearance plugin** | Color scheme, Accent in my class color, Window opacity, Text size |
| **Launchers plugin (right-click)** | Sort, Tile size, Columns, Show hidden launchers, Placement for this character only, Every launcher, Rescan minimap |
| **SimplePanel window (`/sb`)** | **Bar** (where everything lives, and the reset buttons), **Plugins**, **Launchers**, **Profiles**, **About**. One search box searches every page. |

**Reset buttons** (Bar tab):

| Button | What it does |
|---|---|
| **Reset plugin layout** | Every plugin back to its default section and order |
| **Reset window positions** | The SimplePanel window and every chart window back to the middle of the screen |
| **Reset launcher placement** | Every launcher back in the drawer, on all characters |
| **Reset all settings** | Everything in the profile you're using back to default, then a reload. Gold history and other characters' data are kept. |

SimplePanel also appears under **Options > AddOns > SimplePanel** and in the game's add-on compartment menu.

---

## Commands

| | |
|---|---|
| `/sb` or `/simplepanel` | Open or close the SimplePanel window |
| `/sb edit` | Edit the bar: drag plugins between sections, hide them |
| `/sb show` / `/sb hide` | Show or hide the bar |
| `/sb autohide` | Turn auto-hide on or off |
| `/sb lock` | Lock or unlock shift-dragging plugins |
| `/sb plugins` | List every plugin, its id and whether it's on |
| `/sb chart <plugin>` | Open a plugin's chart, e.g. `/sb chart gold` |
| `/sb scan` | Look for new minimap buttons for the drawer |
| `/sb profile` | Show your profiles |
| `/sb profile <name>` | Switch to a profile (the UI reloads) |
| `/sb reset` | Reset the plugin layout |
| `/sb errors` | List any plugin errors |
| `/sb reload` | Reload the UI |

---

## For add-on authors

Any add-on can put its own plugin on the bar. Add `## OptionalDeps: SimplePanel` to your TOC, then:

```lua
if SimplePanel then
    SimplePanel.RegisterPlugin({
        id = "MyThing",
        name = "My Thing",
        category = "Information",
        icon = 134400,
        events = { "BAG_UPDATE" },      -- refresh on these events
        text = function(p) return "12" end,
        tooltip = function(p, tt) tt:AddDouble("Things", "12") end,
        menu = function(p, m)
            m:Checkbox({ text = "Show more", get = function() return p:Get("more") end,
                set = function(v) p:Set("more", v) end })
        end,
        onClick = function(p, button) end,
    })
end
```

A plugin can also have:
- **Display:** colored segments with icons, a progress bar (`progress`), indicator icons, and a badge.
- **History:** a history (`series`) with a chart window and an inline sparkline.
- **Input:** mouse-wheel handling, and secure clicks for opening game windows.

Settings saved with `p:Get`/`p:Set` follow the user's profile. The full API is described at the top of `PluginKit.lua` and on the **About** tab.

---

## FAQ

**A plugin disappeared from the bar.**
The bar was too full, so it stepped into the **»** button. Hover **»** to see it, hide a plugin you don't need, or lower **Scale**.

**How do I get a hidden plugin back?**
Right-click empty bar space > **Plugins**, or **Add plugin** on the edit toolbar, or the **Plugins** tab in `/sb`.

**Professions shows nothing.**
Open your Skills tab and make sure the Professions section is expanded. If it still shows nothing, right-click the plugin and choose **Report what the game returned**, and include that in a bug report.

**Quests are missing from the Quests tooltip.**
By default it lists only quests in your zone and the ones you track. Tick **Show all quests on mouseover** on its menu. Quests under a folded zone in your quest log aren't counted until you unfold it.

**A window didn't open in combat.**
Some game windows can't be opened by add-ons during a fight. Use the game's own key for it, or try again once combat ends.

**I made a mess of the layout.**
`/sb reset`, or **Reset layout** on the edit toolbar, puts every plugin back where it started.

**A minimap button isn't in the drawer.**
Type `/sb scan`. Blizzard's own controls and map-pin add-ons are left on the minimap on purpose. Check the **Hidden** and **On the minimap** boxes in the Launchers tab.

**A plugin shows `<?>` in red.**
It hit an error. `/sb errors` lists the details, which are useful in a bug report.

---

## Notes

- Built for **World of Warcraft: Forever** (Interface 16001). It also loads on Classic Era, Classic progression and retail clients.
- **No libraries required.** If another add-on loads LibDataBroker, SimplePanel shows its feeds and launchers too.
- Its flat, dark look matches **Wally**.

Bug reports and suggestions are welcome in the comments or on the issue tracker.
