# WallyChat

**The game's chat windows in the Wally suite's look: see-through hairline panels, underline tabs, Roboto Condensed, a quiet row of icon buttons, clickable web links, and a full-screen view where you can select and copy any line.**

WallyChat restyles the chat you already have. Your windows, tabs, channels and chat settings stay exactly as you set them up; only the look changes, plus a few things the game's chat can't do.

---

## What changes

- **Windows:** the gold-edged background and the button column beside the chat are gone. Each window gets one see-through panel with a thin 1px edge behind its tabs and messages.
- **Text:** Roboto Condensed, the suite's font, at the size you set in the game's chat settings, with a soft shadow so it reads over anything.
- **Tabs:** plain names in capitals. The window you're looking at is bright with a teal line under it; the others are dimmer. A window with something new flashes its line.
- **Edit box:** a dark well whose edge brightens while you type.
- **Death Roll:** two buttons beside Friends.
  - When someone opens a death roll (a roll of 1-10000) and it's the only one going, WallyChat locks onto it by itself.
  - **Continue** shows while you're locked onto a game and lights up on your turn. Click it and it rolls for you, 1 to whatever your opponent got. You never type anything.
  - **Dice** is for when there's doubt: if more than one game is going, it lists them (who, and what to roll) so you can pick yours. It also leaves a game, or starts one (**Initiate Death Roll** rolls 1-10000 for you).
  - When the game ends it tells you who won.
- **Buttons:** Death Roll (two), Friends (with how many are online), Channels, the chat menu and **Full screen** sit as small icons at the right of the tab bar. They're grey at rest and teal under the mouse.
- **Layer refresh notice:** when the game is about to move you to another layer (say, after joining a group), its countdown notice sits just above the chat panel, so it moves with your chat. In Edit Mode (or with `/wchat alert`) an outline shows the space it takes.
- **Jump to newest:** while you've scrolled up, a small arrow in the window's corner takes you back down.

## Auto-post

A small **Auto-post** tab sits on top of the chat window. Click it and a panel slides up for ads you repeat:
- **Kind:** Sell (WTS), Buy (WTB), Group (LFM or LFG) or Custom. Each kind keeps its own settings.
- **Sell and Buy:** a list of items, each with its price, and a little **x** to take a line off when it sells. Items go out as real item links, so people can click them: **Shift+click** an item in your bags into its box, or **drag** it there. A typed name turns into its link when the game knows the item; until every item is linked, the panel says which one isn't and won't post.
- **Group:** LFM (tick the roles you need) or LFG (the roles you play), the dungeon, and a note. The dungeon comes from a searchable list of every dungeon and raid, with the ones for your level at the top. Wings (Scarlet Monastery's Graveyard, Library...) have their own lines. Type to search; Enter picks the first match, and a name that isn't on the list can be used as typed.
- **Channel:** Trade, General and LookingForGroup are always in the list, plus any other numbered channel you're in, or Say, Yell, Guild, Party or Raid. Trade only works in a city: picked anywhere else, the ad waits until you're in one.
- **Broadcasting:** tick it and the ad comes round every few minutes (1 at least). The game only lets addons post to Trade, General, Say or Yell from a click or key press, so when the ad is due the chat box opens with it typed in: **Enter** sends it, **Escape** skips it. If you're moving when it's due, a **3... 2... 1...** countdown shows in the middle of the screen first: time to press your auto run key, so you keep running while you send it (addons can't start auto run themselves). It waits while you're typing or fighting. Guild, party and raid ads post by themselves. Broadcasting is off whenever you log in.
- **Broadcast** (on the tab, panel open or not) posts the ad right now.

You can set everything up whether or not it's broadcasting. A line under the settings shows exactly what will be posted.

## Web links

Addresses in chat (`https://…`, `www.…`, `discord.gg/…`) turn teal and clickable. A click opens a box with the address selected: press **Ctrl+C** to copy it. The game can't open a browser for you.

## Full screen

Click the **Full screen** icon (or type `/wchat full`). The chat covers the whole screen below SimplePanel's bar, over every other window:
- **Select** any text by dragging, and **copy** it with **Ctrl+C**.
- **Click** a web address to copy it, or an item or player link to use it as you would in chat.
- **Tabs** at the top switch between your chat windows.
- **Plain text** leaves out colours and links, so what you copy pastes cleanly outside the game.
- **Channels** lists your numbered channels (General, Trade, LocalDefense...). Untick one to hide it here, or click its pop-out icon to give it a tab of its own, as Guild has. Right-click that tab to close it. Hiding only applies in full screen; your chat windows still show the channel.
- New messages keep coming in, but not while you're selecting.
- **Escape** or the corner icon closes it.

## Commands

| Command | What it does |
|---|---|
| `/wchat full` | Chat over the whole screen |
| `/wchat font regular \| medium \| semibold \| bold` | The chat text's weight |
| `/wchat bg 0-100` | The chat panel's opacity |
| `/wchat debug` | Which of the game's chat parts were found |

Works best with **WallyHUD** (the suite's font). Without it the colours stay and the game's chat font is kept.
