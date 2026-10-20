# WallyChat

**The game's chat windows in the Wally suite's look: see-through hairline panels, underline tabs, Roboto Condensed, a quiet row of icon buttons, clickable web links, and a full-screen view where you can select and copy any line.**

WallyChat restyles the chat you already have. Your windows, tabs, channels and chat settings stay exactly as you set them up; only the look changes, plus a few things the game's chat can't do.

---

## What changes

- **Windows:** the gold-edged background and the button column beside the chat are gone. Each window gets one see-through panel with a thin 1px edge behind its tabs and messages.
- **Text:** Roboto Condensed, the suite's font, at the size you set in the game's chat settings, with a soft shadow so it reads over anything.
- **Tabs:** plain names in capitals. The window you're looking at is bright with a teal line under it; the others are dimmer. A window with something new flashes its line.
- **Edit box:** a dark well whose edge brightens while you type.
- **Buttons:** Friends (with how many are online), Channels, the chat menu and **Full screen** sit as small icons at the right of the tab bar. They're grey at rest and teal under the mouse.
- **Jump to newest:** while you've scrolled up, a small arrow in the window's corner takes you back down.

## Web links

Addresses in chat (`https://…`, `www.…`, `discord.gg/…`) turn teal and clickable. A click opens a box with the address selected: press **Ctrl+C** to copy it. The game can't open a browser for you.

## Full screen

Click the **Full screen** icon (or type `/wchat full`). The chat covers the whole screen below SimplePanel's bar, over every other window:
- **Select** any text by dragging, and **copy** it with **Ctrl+C**.
- **Click** a web address to copy it, or an item or player link to use it as you would in chat.
- **Tabs** at the top switch between your chat windows.
- **Plain text** leaves out colours and links, so what you copy pastes cleanly outside the game.
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
