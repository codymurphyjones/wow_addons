<img src="icon.png" alt="MusicLib logo" width="96">

# MusicLib

MusicLib plays your own music tracks when you enter specific zones or subzones. It can also play a custom sound when you shoot a wand.

## Adding music

### 1. Get your audio files ready

- Use **`.mp3`** or **`.ogg`** files.
- Use simple file names in lowercase with no spaces, such as `elwynn.mp3` or `stormwind_night.ogg`.

### 2. Put the files in the `music` folder

Copy your tracks into the `music` folder inside the addon:

```
Interface\AddOns\MusicLib\
├── MusicLib.lua
├── MusicLib.toc
├── music\
│   ├── elwynn.mp3      <- your tracks go here
│   └── goldshire.mp3
└── sounds\
    └── wand.ogg
```

### 3. Find the exact zone name

Log in, go to the zone, and type:

```
/musiclib zone
```

This prints the current zone and subzone exactly as the game names them, for example `zone 'Elwynn Forest', subzone 'Goldshire'`. The names are case-sensitive, so copy them exactly.

### 4. Add the zone to `MusicLib.lua`

Open `MusicLib.lua` in a text editor and find the `ZONE_MUSIC` table. Add one line per zone:

```lua
local ZONE_MUSIC = {
    ["Elwynn Forest"] = PATH .. "music\\elwynn.mp3",
    ["Goldshire"]     = PATH .. "music\\goldshire.mp3",
    ["Stormwind City"] = PATH .. "music\\stormwind.mp3",   -- new line
}
```

Things to watch:

- **Use double backslashes** (`music\\file.mp3`). A single backslash breaks the path and the track won't be found.
- Every line needs a **comma** at the end.
- A **subzone match wins over a zone match**. In the example above, Goldshire plays `goldshire.mp3` and the rest of Elwynn Forest plays `elwynn.mp3`.
- When you leave a zone, its track stops. If the new zone has no entry, or its file is missing from the `music` folder, the game's normal music plays instead.

### 5. Restart the game

**Fully exit and restart WoW.** The game only scans for new audio files at startup, so `/reload` won't find them. You can use `/reload` later if you only change `MusicLib.lua` and don't add new audio files.

## Custom wand sound

1. Put your sound at `sounds\wand.ogg`. To use a different name, change `WAND_SOUND` in `MusicLib.lua` to match.
2. Restart the game, then test the sound with `/musiclib wand`.
3. (Optional) To silence the default wand sound, look up its FileDataID on [wago.tools](https://wago.tools) by searching the files for "wand". Add the ID to `MUTED_WAND_SOUNDS`:

   ```lua
   local MUTED_WAND_SOUNDS = {
       123456,
   }
   ```

## Slash commands

| Command          | What it does                                        |
|------------------|-----------------------------------------------------|
| `/musiclib zone` | Shows the current zone, subzone and playing track   |
| `/musiclib wand` | Plays the wand sound and says whether it was found  |
| `/musiclib stop` | Stops the custom music                              |

## Troubleshooting

- **Nothing plays.** Check that Music is turned on and its volume is up in the game's sound settings. Make sure you restarted the game after adding the files.
- **`/musiclib zone` shows `track: nil`.** The zone name in `ZONE_MUSIC` doesn't match the game's name. Check the spelling and capital letters against what `/musiclib zone` prints.
- **`/musiclib wand` says "not found".** The file is missing, in the wrong folder, or has a different name from the one in `WAND_SOUND`.
- **The addon doesn't show up in the AddOns list.** The folder must be named exactly `MusicLib`.
