# Instructions for Claude Code

## Where to edit: this repo only

**All work on the user's addons happens in `Z:\Workspaces\wow_addons\addons\<Addon>\`. Never edit, create, generate or delete anything inside the World of Warcraft folder (`Z:\Games\World of Warcraft\...\Interface\AddOns\`).**

The addon folders in the game's `Interface\AddOns` are temporary copies made by `addon_sync.py`:
- `yarn test` copies the workspace builds into the game (`yarn test:watch` keeps copying as files change). This is how the user loads their work in the game client.
- `yarn stop` deletes those copies and puts back whatever was installed before.
- `yarn deploy` packages releases from the workspace.

So anything written in the game folder is lost on the next `yarn stop`, and it never reaches a release. This already destroyed a full day of work once.

That covers everything:
- source code, TOC files and docs;
- generated data (Wowhead scrapes, `Data\*.lua`, zone pictures);
- tool caches (`tools\<Addon>\.wowhead_cache`).

What ships lives under `addons\<Addon>\`. Build logic does not: every script that generates an addon's data or art (scrapers, data builders, `make_icon.py`), with its caches and working files, lives under `tools\<Addon>\` at the repo root, and writes its output into `addons\<Addon>\`. Scripts find their addon from their own location, so they run from any folder (`python -I tools\Waypoint\build_places.py`). New build scripts go there too, never inside an addon folder.

`yarn build` (`tools\build_all.py`) runs every build in order. The datasets (each `tools\<Addon>\.wowhead_cache` and `.cache`) are kept packed as `.tar.xz` beside the folder: the build unpacks them first and packs them again at the end. Running one script by hand needs `yarn data:unpack` first and `yarn data:pack` after. Wowhead pages are fetched through a real Chrome window (`tools\_shared\webfetch.py`, Playwright), because Wowhead refuses curl and headless browsers.

## If a session starts in the game folder

If your working directory is `Z:\Games\World of Warcraft\...\Interface\AddOns` (or any addon folder in it), switch to the matching path in this repo before changing anything:

| Game folder (read-only to you) | Edit here instead |
|---|---|
| `...\Interface\AddOns\Spyglass\Core.lua` | `Z:\Workspaces\wow_addons\addons\Spyglass\Core.lua` |
| `...\Interface\AddOns\<Addon>\...` | `Z:\Workspaces\wow_addons\addons\<Addon>\...` |

Reading files in the game folder is fine: third-party addons, `WTF` saved variables, Blizzard data. Writing there is not.

The game folder also holds third-party addons that aren't in this repo. Patch one only when the user asks, and log the patch in `addons\myaddons.txt`.

## Testing in the game

Don't copy files into the game yourself. When a change needs testing in game, tell the user to run `yarn test` (or keep `yarn test:watch` running) and then `/reload`. Changes to TOC files, or new files, need a full game restart.

## The addons

`addons\myaddons.txt` lists the user's own addons; everything else in the game folder is third party.

The addons support only WoW Forever (`## Interface: 16001`, the 12.x engine; `yarn lint` errors on any other interface number). Don't add Classic Era, Retail or other-client branches. Names on Forever are realmless "Given Family": compare and key players with `addons\shared\Units.lua`, never by `UnitName("player")` or `GetRealmName()`.

`addons\shared\` is code and data several addons share, not an addon (see its README.md); scripts that generate its data live in `tools\shared\`. A TOC loads a shared file as `..\shared\<File>.lua`; the builds copy it into that addon's `Shared\` folder and rewrite the line. Don't fork shared code into an addon: change it in `addons\shared\`. An addon can't have a `Shared\` folder of its own.
