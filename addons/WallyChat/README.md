# WallyChat

The game's chat windows in the suite's look (WallyHUD's tokens and Roboto Condensed), plus clickable web links and a full-screen, copyable view. It restyles the game's own chat frames; it doesn't replace them, so channels, windows and the game's chat settings work as always.

## Files

| File | What it does |
|---|---|
| `Core.lua` | Settings (`WallyChatDB`: weight, background, plainCopy), the tokens (WallyHUD's, or the same values copied in), panels, ghost icon buttons, `/wchat` |
| `Skin.lua` | Each chat window: the game's art emptied, its button column hidden, one hairline panel behind the tab row and messages, the font, underline tabs (the new-message glow as an accent line), the edit box as a sunken well. Hooks the FCF_* functions so windows opened or changed later follow. |
| `Links.lua` | A message filter that turns web addresses into `wallychat:url:` links (outside the game's own links). `SetItemRef` is wrapped so a click on one opens a copy box. |
| `FullScreen.lua` | The full-screen view: a multi-line EditBox in a scroll frame with the chat window's history (`GetMessageInfo`), read-only, below `SimplePanelFrame`, at FULLSCREEN_DIALOG strata. A click that isn't a drag finds the link under the cursor (byte, character and shown-character offsets are all checked, since clients count the cursor differently). |
| `Toolbar.lua` | The icon row on the tab bar (Friends with the online count, Channels, the chat menu, Full screen), hiding the game's buttons, and each window's jump-to-newest button. |

## Build

`tools/WallyChat/make_icons.py` draws the icons in `Media` (white glyphs the code tints, and `Icon.tga`). It needs Pillow, so run it with `python tools/WallyChat/make_icons.py` (not `-I`).

## Not covered yet

- The tab bar's own overflow button isn't moved: with many tabs, the last ones can sit under the icon row.
- Text in the full-screen view can't show icons (raid markers, textures) or protected Battle.net names; they're left out or shown as "(Battle.net friend)".
- Whisper windows opened after the full-screen view was first shown don't refresh it live (reopen it).
