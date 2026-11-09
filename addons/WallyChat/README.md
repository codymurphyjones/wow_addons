# WallyChat

The game's chat windows in the suite's look (WallyHUD's tokens and Roboto Condensed), plus clickable web links and a full-screen, copyable view. It restyles the game's own chat frames; it doesn't replace them, so channels, windows and the game's chat settings work as always.

## Files

| File | What it does |
|---|---|
| `Core.lua` | Settings (`WallyChatDB`: weight, background, plainCopy), the tokens (WallyHUD's, or the same values copied in), panels, ghost icon buttons, `/wchat` |
| `Skin.lua` | Each chat window: the game's art emptied, its button column hidden, one hairline panel behind the tab row and messages, the font, underline tabs (the new-message glow as an accent line), the edit box as a sunken well. Hooks the FCF_* functions so windows opened or changed later follow. |
| `Links.lua` | A message filter that turns web addresses into `wallychat:url:` links (outside the game's own links). `SetItemRef` is wrapped so a click on one opens a copy box. |
| `FullScreen.lua` | The full-screen view: a multi-line EditBox in a scroll frame with the chat window's history (`GetMessageInfo`), read-only, below `SimplePanelFrame`, at FULLSCREEN_DIALOG strata. A click that isn't a drag finds the link under the cursor (byte, character and shown-character offsets are all checked, since clients count the cursor differently). |
| `Alert.lua` | The game's layer-refresh notice (`ShardTransferImminentFrame` and its expand arrow `ShardTransferImminentMinimizeButton`, Blizzard_SocialToast), which the game hangs off `ChatAlertFrame` over the hidden button column: re-anchored just above the main chat window's panel. An outline of its space shows during Edit Mode, while the main chat is dragged by its tab, and on `/wchat alert`. |
| `DeathRoll.lua` | The dice button: keeps every roll the game reports for 10 minutes (and reads the ones in the chat windows' history on login), links them into death roll games (a game opens with 1-10000; a roll of 1-X carries on the game whose last roll came out at X, by the other player; two players a game; over at a 1 or 5 minutes quiet), and keeps a lock on one (a roll in it). Locked by itself when exactly one game is playable: one you're in, or an opening nobody has answered (5 minutes); a game you left isn't, and a locked opening someone else answers is let go. Continue (toolbar) shows while locked, lit in the accent on your turn, and rolls for you (`RandomRoll(1, X)` from the click), or says who you're waiting for. Dice: a list to lock onto when more than one game is playable, switch or Leave game when locked, else "Initiate Death Roll?" (rolls 1-10000, locks the game it opens). The locked game ending says who won and lets go. Nothing is ever typed. |
| `AutoPost.lua` | The Auto-post panel: slides up out of the main chat window's top edge (`ChatFrame1` + 30, the panel's edge) from a handle that rides on it, with Broadcast on the handle. Per-character settings in `WallyChatDB.autoPost[charKey]`: kind (sell, buy, group, custom), channel (a numbered channel saved by its base name, "Trade" from "Trade - City", or Say/Yell/Guild/Party/Raid), minutes, and each kind's fields. Sell/Buy items must be item links (Shift+click via a `ChatFrameUtil.InsertLink` hook, drag and drop, or a typed name swapped for `C_Item.GetItemInfo`'s link). `SendChatMessage` is restricted to a hardware event for numbered channels and Say/Yell, so Broadcast posts from its click, and broadcasting opens the chat box with the ad typed in (`ChatFrameUtil.OpenChat`) for Enter to send; Guild/Party/Raid are sent by the timer. Broadcasting is off after every login. |
| `Toolbar.lua` | The icon row on the tab bar (Death Roll's Continue and Dice, Friends with the online count, Channels, the chat menu, Full screen), hiding the game's buttons, and each window's jump-to-newest button. |

## Build

`tools/WallyChat/make_icons.py` draws the icons in `Media` (white glyphs the code tints, and `Icon.tga`). It needs Pillow, so run it with `python tools/WallyChat/make_icons.py` (not `-I`).

## Not covered yet

- The tab bar's own overflow button isn't moved: with many tabs, the last ones can sit under the icon row.
- Text in the full-screen view can't show icons (raid markers, textures) or protected Battle.net names; they're left out or shown as "(Battle.net friend)".
- Whisper windows opened after the full-screen view was first shown don't refresh it live (reopen it).
